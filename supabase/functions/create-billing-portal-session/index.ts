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
      throw new Error("Sign in before managing your subscription")

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    )
    const { data: authData, error: authError } =
      await serviceClient.auth.getUser(authorization.slice(7))
    if (authError || !authData.user)
      throw new Error("Your session is no longer valid")

    const body = (await request.json().catch(() => ({}))) as {
      action?: unknown
      mobile?: unknown
    }
    if (body.action !== "change" && body.action !== "cancel")
      throw new Error("Choose a supported subscription action")
    const mobile = body.mobile === true
    if (!mobile && origin === "*")
      throw new Error("The application origin is not allowed")

    const { data: account, error: accountError } = await serviceClient
      .from("user")
      .select("user_id, stripe_customer_id")
      .eq("auth_user_id", authData.user.id)
      .single()
    if (accountError || !account)
      throw new Error("No StreamFlix account is linked to this login")

    const customerId = String(account.stripe_customer_id ?? "").trim()
    if (!customerId.startsWith("cus_"))
      throw new Error("Subscribe through Stripe before managing your plan")

    const { data: membership, error: membershipError } = await serviceClient
      .from("user_subscription")
      .select("stripe_subscription_id")
      .eq("user_id", account.user_id)
      .ilike("status", "active")
      .not("stripe_subscription_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle()
    const subscriptionId = String(
      membership?.stripe_subscription_id ?? "",
    ).trim()
    if (membershipError || !subscriptionId.startsWith("sub_"))
      throw new Error("No active Stripe subscription can be managed")

    const configuration = Deno.env.get("STRIPE_PORTAL_CONFIGURATION_ID")?.trim()
    if (!configuration?.startsWith("bpc_"))
      throw new Error("Stripe Customer Portal is not configured")

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!)
    if (body.action === "cancel") {
      await stripe.billingPortal.configurations.update(configuration, {
        features: {
          subscription_cancel: {
            enabled: true,
            mode: "immediately",
            proration_behavior: "none",
          },
        },
      })
    }

    const mobileReturn = (status: string) =>
      `${supabaseUrl}/functions/v1/stripe-mobile-return?billing=${status}`
    const webReturn = (status: string) => `${origin}/?billing=${status}`
    const returnUrl = mobile ? mobileReturn : webReturn
    const flowData =
      body.action === "cancel"
        ? {
            type: "subscription_cancel" as const,
            subscription_cancel: { subscription: subscriptionId },
            after_completion: {
              type: "redirect" as const,
              redirect: { return_url: returnUrl("cancelled") },
            },
          }
        : {
            type: "subscription_update" as const,
            subscription_update: { subscription: subscriptionId },
            after_completion: {
              type: "redirect" as const,
              redirect: { return_url: returnUrl("updated") },
            },
          }

    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      configuration,
      return_url:
        body.action === "cancel"
          ? returnUrl("cancel-abandoned")
          : mobile
            ? mobileReturn("unchanged")
            : `${origin}/`,
      flow_data: flowData,
    })

    return response({ url: session.url }, 200, origin)
  } catch (error) {
    console.error(
      "create-billing-portal-session",
      error instanceof Error ? error.message : error,
    )
    return response(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unable to open Stripe Customer Portal",
      },
      400,
      origin,
    )
  }
})
