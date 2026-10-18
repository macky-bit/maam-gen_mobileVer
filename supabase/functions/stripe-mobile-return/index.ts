const appUrl = (key: "checkout" | "billing", status: string) =>
  `com.streamflix.app://billing-callback/?${key}=${status}`

Deno.serve((request) => {
  const params = new URL(request.url).searchParams
  const requestedBilling = params.get("billing")
  const billing =
    requestedBilling &&
    new Set(["updated", "cancelled", "cancel-abandoned", "unchanged"]).has(
      requestedBilling,
    )
      ? requestedBilling
      : null
  const key = billing ? "billing" : "checkout"
  const status =
    billing ?? (params.get("checkout") === "success" ? "success" : "cancelled")
  return new Response(null, {
    status: 302,
    headers: {
      Location: appUrl(key, status),
      "Cache-Control": "no-store",
    },
  })
})
