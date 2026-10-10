const appUrl = (status: string) =>
  `com.streamflix.app://billing-callback/?checkout=${status}`

Deno.serve((request) => {
  const requested = new URL(request.url).searchParams.get("checkout")
  const status = requested === "success" ? "success" : "cancelled"
  const target = appUrl(status)
  const title = status === "success" ? "Payment complete" : "Checkout canceled"
  const message = status === "success"
    ? "Return to StreamFlix to finish activating your subscription."
    : "No payment was made. Return to StreamFlix when you're ready."
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>${title}</title><script>location.replace(${JSON.stringify(target)})</script>
<style>body{background:#08080f;color:#fff;font:16px system-ui;display:grid;min-height:100vh;place-items:center;margin:0}main{text-align:center;padding:24px}a{display:inline-block;margin-top:18px;padding:12px 18px;border-radius:999px;background:#7c3aed;color:#fff;text-decoration:none}</style></head>
<body><main><h1>${title}</h1><p>${message}</p><a href="${target}">Open StreamFlix</a></main></body></html>`
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
    },
  })
})
