import Stripe from "npm:stripe@^22.0.0"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!)
const cryptoProvider = Stripe.createSubtleCryptoProvider()

type JsonRecord = Record<string, unknown>

const idOf = (value: unknown) => {
  if (typeof value === "string") return value
  if (value && typeof value === "object" && "id" in value)
    return String((value as { id: unknown }).id)
  return ""
}

const isoTime = (value: unknown) => {
  const seconds = Number(value)
  return Number.isFinite(seconds) && seconds > 0
    ? new Date(seconds * 1000).toISOString()
    : ""
}

const subscriptionPeriod = (subscription: Stripe.Subscription) => {
  const raw = subscription as unknown as JsonRecord
  const items = subscription.items?.data ?? []
  const starts = items
    .map((item) => Number((item as unknown as JsonRecord).current_period_start))
    .filter(Number.isFinite)
  const ends = items
    .map((item) => Number((item as unknown as JsonRecord).current_period_end))
    .filter(Number.isFinite)
  return {
    start: isoTime(Number(raw.current_period_start) || Math.min(...starts)),
    end: isoTime(Number(raw.current_period_end) || Math.max(...ends)),
  }
}

const subscriptionFromInvoice = (invoice: Stripe.Invoice) => {
  const raw = invoice as unknown as JsonRecord
  const parent = raw.parent as JsonRecord | undefined
  const details = parent?.subscription_details as JsonRecord | undefined
  return idOf(raw.subscription) || idOf(details?.subscription)
}

async function retrieveSubscription(id: string) {
  if (!id) throw new Error("Stripe event does not identify a subscription")
  return await stripe.subscriptions.retrieve(id)
}

function metadataPayload(subscription: Stripe.Subscription) {
  const metadata = subscription.metadata ?? {}
  const period = subscriptionPeriod(subscription)
  return {
    user_id: metadata.streamflix_user_id ?? "",
    plan_id: metadata.streamflix_plan_id ?? "",
    stripe_subscription_id: subscription.id,
    stripe_customer_id: idOf(subscription.customer),
    stripe_status: subscription.status,
    stripe_price_id: subscription.items?.data[0]?.price?.id ?? "",
    cancel_at_period_end: subscription.cancel_at_period_end,
    period_start: period.start,
    period_end: period.end,
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 })
  }

  const signature = request.headers.get("Stripe-Signature")
  if (!signature)
    return Response.json({ error: "Missing Stripe signature" }, { status: 400 })

  try {
    const event = await stripe.webhooks.constructEventAsync(
      await request.text(),
      signature,
      Deno.env.get("STRIPE_WEBHOOK_SIGNING_SECRET")!,
      undefined,
      cryptoProvider,
    )

    let payload: JsonRecord | null = null
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session
      if (
        session.mode !== "subscription" ||
        !["paid", "no_payment_required"].includes(session.payment_status)
      ) {
        return Response.json({ received: true, ignored: true })
      }
      const subscription = await retrieveSubscription(
        idOf(session.subscription),
      )
      payload = {
        ...metadataPayload(subscription),
        user_id:
          subscription.metadata.streamflix_user_id ||
          session.metadata?.streamflix_user_id ||
          session.client_reference_id ||
          "",
        plan_id:
          subscription.metadata.streamflix_plan_id ||
          session.metadata?.streamflix_plan_id ||
          "",
        checkout_session_id: session.id,
      }
    } else if (event.type === "invoice.paid") {
      const invoice = event.data.object as Stripe.Invoice
      const subscription = await retrieveSubscription(
        subscriptionFromInvoice(invoice),
      )
      const raw = invoice as unknown as JsonRecord
      payload = {
        ...metadataPayload(subscription),
        amount_total: invoice.amount_paid,
        currency: invoice.currency,
        stripe_invoice_id: invoice.id,
        stripe_payment_intent_id: idOf(raw.payment_intent),
        receipt_url: invoice.hosted_invoice_url ?? invoice.invoice_pdf ?? "",
      }
    } else if (
      event.type === "customer.subscription.updated" ||
      event.type === "customer.subscription.deleted"
    ) {
      payload = metadataPayload(event.data.object as Stripe.Subscription)
    } else if (event.type === "invoice.payment_failed") {
      const invoice = event.data.object as Stripe.Invoice
      const subscription = await retrieveSubscription(
        subscriptionFromInvoice(invoice),
      )
      payload = metadataPayload(subscription)
    } else {
      return Response.json({ received: true, ignored: true })
    }

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    )
    // The product revokes StreamFlix access as soon as a member confirms
    // cancellation, even when Stripe schedules it for the period end.
    const billingEventType =
      event.type === "customer.subscription.updated" &&
      payload.cancel_at_period_end === true
        ? "customer.subscription.deleted"
        : event.type

    const { data, error } = await serviceClient.rpc(
      "process_stripe_billing_event",
      {
        p_event_id: event.id,
        p_event_type: billingEventType,
        p_data: payload,
      },
    )
    if (error) throw error

    if (
      event.type === "customer.subscription.updated" &&
      payload.cancel_at_period_end !== true
    ) {
      const stripeSubscriptionId = String(
        payload.stripe_subscription_id ?? "",
      ).trim()
      let selectedPlanId = Number(payload.plan_id)
      const stripePriceId = String(payload.stripe_price_id ?? "").trim()
      if (stripePriceId.startsWith("price_")) {
        const { data: selectedPlan } = await serviceClient
          .from("subscription")
          .select("subscription_id")
          .eq("stripe_price_id", stripePriceId)
          .maybeSingle()
        selectedPlanId = Number(selectedPlan?.subscription_id)
      }
      if (
        stripeSubscriptionId.startsWith("sub_") &&
        Number.isSafeInteger(selectedPlanId) &&
        selectedPlanId > 0
      ) {
        const { error: planSyncError } = await serviceClient.rpc(
          "sync_stripe_subscription_plan",
          {
            selected_stripe_subscription_id: stripeSubscriptionId,
            selected_plan_id: selectedPlanId,
          },
        )
        if (planSyncError) throw planSyncError
      }
    }

    return Response.json({ received: true, processed: data === true })
  } catch (error) {
    console.error(
      "stripe-webhook",
      error instanceof Error ? error.message : error,
    )
    return Response.json(
      {
        error:
          error instanceof Error ? error.message : "Webhook processing failed",
      },
      { status: 400 },
    )
  }
})
