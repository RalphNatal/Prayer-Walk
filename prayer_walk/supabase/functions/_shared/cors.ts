// Shared CORS headers for every Edge Function in this project.
//
// Mobile builds (Android/iOS) never hit CORS at all — it is a browser-only
// concept — but this app also ships a web target (see `web/`), where
// `supabase.functions.invoke(...)` is a `fetch()` from the page's own origin.
// Without these headers a browser blocks the response before the app ever
// sees it, including the preflight `OPTIONS` request every non-trivial POST
// triggers first.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function handleCorsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

export function jsonResponse(
  body: unknown,
  init: { status?: number } = {},
): Response {
  return new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
