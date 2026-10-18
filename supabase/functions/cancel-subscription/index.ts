import Stripe from "npm:stripe@^22.0.0"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const jsonHeaders = { "Content-Type": "application/json" }

function response(
  body: Record<string, unknown>,
  status: number,
  origin: string,
) {
  return Response.json(body, {
    status,
    headers: {
      ...jsonHeaders,
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      Vary: "Origin",
    },
  })
}

function allowedOrigin(request: Request) {
  const configured = Deno.env.get("APP_URL")?.trim()
  const candidate = configured || request.headers.get("Origin") || ""
  if (!candidate) return "*"
  const url = new URL(candidate)
  if (!["http:", "https:"].includes(url.protocol))
    throw new Error("Invalid application URL")
  return url.origin
}

Deno.serve(async (request) => {
  let origin = "*"
  try {
    origin = allowedOrigin(request)
  } catch {
    if (request.method !== "OPTIONS")
      return response(
        { error: "The application origin is not allowed" },
        400,
        "*",
      )
  }

  if (request.method === "OPTIONS") return response({ ok: true }, 200, origin)
  if (request.method !== "POST")
    return response({ error: "Method not allowed" }, 405, origin)

  try {
    const authorization = request.headers.get("Authorization")
    if (!authorization?.startsWith("Bearer "))
      throw new Error("Sign in before canceling your subscription")

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    )
    const { data: authData, error: authError } =
      await serviceClient.auth.getUser(authorization.slice(7))
    if (authError || !authData.user)
      throw new Error("Your session is no longer valid")

    const { data: account, error: accountError } = await serviceClient
      .from("user")
      .select("user_id, stripe_customer_id")
      .eq("auth_user_id", authData.user.id)
      .single()
    if (accountError || !account)
      throw new Error("No StreamFlix account is linked to this login")

    const { data: membership, error: membershipError } = await serviceClient
      .from("user_subscription")
      .select("user_subscription_id, subscription_id, stripe_subscription_id")
      .eq("user_id", account.user_id)
      .ilike("status", "active")
      .or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
      .order("started_at", { ascending: false })
      .limit(1)
      .maybeSingle()
    if (membershipError) throw membershipError
    if (!membership) {
      const { error: accountUpdateError } = await serviceClient
        .from("user")
        .update({ subscription_id: null })
        .eq("user_id", account.user_id)
      if (accountUpdateError) throw accountUpdateError

      return response({ canceled: true, alreadyInactive: true }, 200, origin)
    }

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!)
    let stripeSubscriptionId = String(
      membership.stripe_subscription_id ?? "",
    ).trim()
    let stripeConfirmedInactive = false

    // Recover older memberships that predate persisted Stripe identifiers.
    if (!stripeSubscriptionId.startsWith("sub_")) {
      const stripeCustomerId = String(account.stripe_customer_id ?? "").trim()
      if (stripeCustomerId.startsWith("cus_")) {
        const subscriptions = await stripe.subscriptions.list({
          customer: stripeCustomerId,
          status: "all",
          limit: 100,
        })
        const liveStatuses = new Set([
          "active",
          "trialing",
          "past_due",
          "unpaid",
          "incomplete",
          "paused",
        ])
        const liveSubscriptions = subscriptions.data.filter((subscription) =>
          liveStatuses.has(subscription.status),
        )
        const metadataMatches = liveSubscriptions.filter(
          (subscription) =>
            subscription.metadata.streamflix_user_id ===
            String(account.user_id),
        )

        let matches = metadataMatches
        if (matches.length !== 1) {
          const { data: plan } = await serviceClient
            .from("subscription")
            .select("stripe_price_id")
            .eq("subscription_id", membership.subscription_id)
            .maybeSingle()
          const stripePriceId = String(plan?.stripe_price_id ?? "").trim()
          matches = stripePriceId
            ? liveSubscriptions.filter((subscription) =>
                subscription.items.data.some(
                  (item) => item.price.id === stripePriceId,
                ),
              )
            : []
        }

        if (matches.length !== 1 && liveSubscriptions.length === 1)
          matches = liveSubscriptions

        if (matches.length === 1) {
          stripeSubscriptionId = matches[0].id
          const { error: linkError } = await serviceClient
            .from("user_subscription")
            .update({ stripe_subscription_id: stripeSubscriptionId })
            .eq("user_subscription_id", membership.user_subscription_id)
            .eq("user_id", account.user_id)
          if (linkError) throw linkError
        } else if (liveSubscriptions.length > 0) {
          throw new Error(
            "More than one Stripe subscription matches this account. Contact support before canceling to avoid canceling the wrong plan.",
          )
        } else {
          stripeConfirmedInactive = true
        }
      }
    }

    if (stripeSubscriptionId.startsWith("sub_")) {
      let subscription =
        await stripe.subscriptions.retrieve(stripeSubscriptionId)
      const stripeCustomerId = String(account.stripe_customer_id ?? "").trim()
      const subscriptionCustomerId =
        typeof subscription.customer === "string"
          ? subscription.customer
          : subscription.customer.id
      if (
        stripeCustomerId.startsWith("cus_") &&
        subscriptionCustomerId !== stripeCustomerId
      ) {
        throw new Error(
          "The Stripe subscription does not belong to this StreamFlix account.",
        )
      }

      if (subscription.status !== "canceled") {
        try {
          subscription = await stripe.subscriptions.cancel(
            stripeSubscriptionId,
            { invoice_now: false, prorate: false },
          )
        } catch (cancelError) {
          subscription =
            await stripe.subscriptions.retrieve(stripeSubscriptionId)
          if (subscription.status !== "canceled") throw cancelError
        }
      }
      if (subscription.status !== "canceled")
        throw new Error("Stripe did not confirm the cancellation")
      stripeConfirmedInactive = true
    }

    if (!stripeConfirmedInactive)
      throw new Error(
        "Stripe could not confirm which subscription to cancel. Contact support before trying again.",
      )

    const canceledAt = new Date().toISOString()
    const { data: canceledMembership, error: cancelError } = await serviceClient
      .from("user_subscription")
      .update({ status: "Canceled", ends_at: canceledAt })
      .eq("user_subscription_id", membership.user_subscription_id)
      .eq("user_id", account.user_id)
      .select("status")
      .single()
    if (cancelError) throw cancelError
    if (String(canceledMembership.status).toLowerCase() !== "canceled")
      throw new Error(
        "StreamFlix could not confirm the membership cancellation",
      )

    const { data: canceledAccount, error: accountUpdateError } =
      await serviceClient
        .from("user")
        .update({ subscription_id: null, end_date: canceledAt })
        .eq("user_id", account.user_id)
        .select("subscription_id")
        .single()
    if (accountUpdateError) throw accountUpdateError
    if (canceledAccount.subscription_id !== null)
      throw new Error("StreamFlix could not confirm the account cancellation")

    return response(
      {
        canceled: true,
        stripeCanceled: stripeConfirmedInactive,
      },
      200,
      origin,
    )
  } catch (error) {
    console.error(
      "cancel-subscription",
      error instanceof Error ? error.message : error,
    )
    return response(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unable to cancel the subscription",
      },
      400,
      origin,
    )
  }
})
