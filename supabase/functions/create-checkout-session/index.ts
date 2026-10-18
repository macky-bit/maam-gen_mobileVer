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

const priceForPlan = (configuredPrice: unknown) => {
  const price = String(configuredPrice ?? "").trim()
  const allowed = new Set([
    Deno.env.get("STRIPE_PRICE_BASIC")?.trim(),
    Deno.env.get("STRIPE_PRICE_STANDARD")?.trim(),
    Deno.env.get("STRIPE_PRICE_PREMIUM")?.trim(),
  ])
  if (!price.startsWith("price_") || !allowed.has(price)) {
    throw new Error("This plan is not configured for Stripe Checkout")
  }
  return price
}

async function enablePortalPlanUpdates(stripe: Stripe, configuration: string) {
  const priceIds = [
    Deno.env.get("STRIPE_PRICE_BASIC")?.trim(),
    Deno.env.get("STRIPE_PRICE_STANDARD")?.trim(),
    Deno.env.get("STRIPE_PRICE_PREMIUM")?.trim(),
  ].filter((price): price is string => Boolean(price?.startsWith("price_")))
  const prices = await Promise.all(
    [...new Set(priceIds)].map((price) => stripe.prices.retrieve(price)),
  )
  const groupedProducts = new Map<string, string[]>()
  for (const price of prices) {
    const productId =
      typeof price.product === "string" ? price.product : price.product.id
    groupedProducts.set(productId, [
      ...(groupedProducts.get(productId) ?? []),
      price.id,
    ])
  }

  await stripe.billingPortal.configurations.update(configuration, {
    features: {
      subscription_update: {
        enabled: true,
        default_allowed_updates: ["price"],
        proration_behavior: "none",
        products: [...groupedProducts].map(([product, configuredPrices]) => ({
          product,
          prices: configuredPrices,
        })),
      },
    },
  })
}

Deno.serve(async (request) => {
  let origin = "*"
  try {
    origin = allowedOrigin(request)
  } catch {
    if (request.method !== "OPTIONS") {
      return response(
        { error: "The application origin is not allowed" },
        400,
        "*",
      )
    }
  }

  if (request.method === "OPTIONS") return response({ ok: true }, 200, origin)
  if (request.method !== "POST")
    return response({ error: "Method not allowed" }, 405, origin)

  try {
    const authorization = request.headers.get("Authorization")
    if (!authorization?.startsWith("Bearer "))
      throw new Error("Sign in before choosing a plan")

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: authData, error: authError } =
      await serviceClient.auth.getUser(authorization.slice(7))
    if (authError || !authData.user)
      throw new Error("Your session is no longer valid")

    const body = (await request.json().catch(() => ({}))) as {
      planId?: unknown
      mobile?: unknown
    }
    const planId = Number(body.planId)
    const mobile = body.mobile === true
    if (!Number.isSafeInteger(planId) || planId <= 0)
      throw new Error("Select a valid plan")
    if (!mobile && origin === "*")
      throw new Error("The application origin is not allowed")

    const [
      { data: account, error: accountError },
      { data: plan, error: planError },
    ] = await Promise.all([
      serviceClient
        .from("user")
        .select("user_id, email, stripe_customer_id")
        .eq("auth_user_id", authData.user.id)
        .single(),
      serviceClient
        .from("subscription")
        .select("subscription_id, plan_name, stripe_price_id")
        .eq("subscription_id", planId)
        .single(),
    ])
    if (accountError || !account)
      throw new Error("No StreamFlix account is linked to this login")
    if (planError || !plan) throw new Error("The selected plan is unavailable")

    const { data: activeMembership } = await serviceClient
      .from("user_subscription")
      .select("user_subscription_id, subscription_id, stripe_subscription_id")
      .eq("user_id", account.user_id)
      .ilike("status", "active")
      .or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
      .limit(1)
      .maybeSingle()
    const stripe = new Stripe(stripeKey)
    const selectedPrice = priceForPlan(plan.stripe_price_id)
    const metadata = {
      streamflix_user_id: String(account.user_id),
      streamflix_plan_id: String(plan.subscription_id),
    }

    const stripeSubscriptionId = String(
      activeMembership?.stripe_subscription_id ?? "",
    ).trim()
    if (activeMembership && stripeSubscriptionId.startsWith("sub_")) {
      const subscription =
        await stripe.subscriptions.retrieve(stripeSubscriptionId)
      if (
        subscription.status !== "canceled" &&
        Number(activeMembership.subscription_id) === planId
      ) {
        return response({ updated: true, unchanged: true, planId }, 200, origin)
      }
      if (
        subscription.status !== "canceled" &&
        subscription.items.data.length !== 1
      ) {
        throw new Error(
          "This subscription has an unsupported billing configuration. Contact support for assistance.",
        )
      }

      if (subscription.status !== "canceled") {
        const configuration = Deno.env
          .get("STRIPE_PORTAL_CONFIGURATION_ID")
          ?.trim()
        if (!configuration?.startsWith("bpc_"))
          throw new Error("Stripe Customer Portal is not configured")
        await enablePortalPlanUpdates(stripe, configuration)

        const customerId =
          typeof subscription.customer === "string"
            ? subscription.customer
            : subscription.customer.id
        const returnUrl = mobile
          ? `${supabaseUrl}/functions/v1/stripe-mobile-return?billing=updated`
          : `${origin}/?billing=updated`
        const portalSession = await stripe.billingPortal.sessions.create({
          customer: customerId,
          configuration,
          return_url: returnUrl,
          flow_data: {
            type: "subscription_update_confirm",
            subscription_update_confirm: {
              subscription: stripeSubscriptionId,
              items: [
                {
                  id: subscription.items.data[0].id,
                  price: selectedPrice,
                  quantity: 1,
                },
              ],
            },
            after_completion: {
              type: "redirect",
              redirect: { return_url: returnUrl },
            },
          },
        })
        return response({ url: portalSession.url }, 200, origin)
      }
    }

    const returnBase = mobile
      ? `${supabaseUrl}/functions/v1/stripe-mobile-return`
      : origin
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: selectedPrice, quantity: 1 }],
      client_reference_id: String(account.user_id),
      customer: account.stripe_customer_id || undefined,
      customer_email: account.stripe_customer_id
        ? undefined
        : String(account.email),
      metadata,
      subscription_data: { metadata },
      success_url: mobile
        ? `${returnBase}?checkout=success&session_id={CHECKOUT_SESSION_ID}`
        : `${returnBase}/?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: mobile
        ? `${returnBase}?checkout=cancelled`
        : `${returnBase}/?checkout=cancelled`,
    })

    if (!session.url) throw new Error("Stripe did not return a Checkout URL")
    return response({ url: session.url }, 200, origin)
  } catch (error) {
    console.error(
      "create-checkout-session",
      error instanceof Error ? error.message : error,
    )
    return response(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unable to start Stripe Checkout",
      },
      400,
      origin,
    )
  }
})
