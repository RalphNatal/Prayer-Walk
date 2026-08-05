// Deriving the caller's id from their JWT — never from anything the request
// body says. This is the one thing every privileged Edge Function in this
// project must get right: a member can only ever act on their own account
// through this path, because the id this returns is the one Supabase's own
// auth server has already verified, not one a client typed into a form field.

import { createClient } from "jsr:@supabase/supabase-js@2";

export class UnauthorizedError extends Error {}

/**
 * Verifies the `Authorization` header against Supabase Auth and returns the
 * caller's user id.
 *
 * Uses the anon key (not the service role) for this call on purpose: it is
 * the same verification path RLS itself relies on, so a token this rejects is
 * a token nothing else in the project would have trusted either.
 */
export async function verifiedCallerId(req: Request): Promise<string> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new UnauthorizedError("Missing Authorization header");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    // Both are injected automatically into every deployed Edge Function's
    // environment. Missing here means local `supabase functions serve`
    // without `--env-file`, not a real deployment.
    throw new Error("SUPABASE_URL/SUPABASE_ANON_KEY not available");
  }

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new UnauthorizedError(error?.message ?? "No user for this token");
  }
  return data.user.id;
}

/** A service-role client for the privileged work only this function may do. */
export function serviceRoleClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY not available");
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
