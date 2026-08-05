// Hands the caller back their own data as one JSON object — the cheap half of
// "export before you delete." Every query below is filtered by `uid`, which
// comes from the verified JWT (see `_shared/auth.ts`), never from anything
// the request supplies. The service-role client bypasses RLS deliberately
// (a member exporting their own comments still needs to see comments on
// other people's walks), but every filter below scopes that access back down
// to exactly one person's rows.

import { handleCorsPreflight, jsonResponse } from "../_shared/cors.ts";
import {
  serviceRoleClient,
  UnauthorizedError,
  verifiedCallerId,
} from "../_shared/auth.ts";

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
  }

  let uid: string;
  try {
    uid = await verifiedCallerId(req);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      return jsonResponse({ error: "unauthorized" }, { status: 401 });
    }
    console.error("export-data: auth verification failed", error);
    return jsonResponse({ error: "auth_check_failed" }, { status: 500 });
  }

  const admin = serviceRoleClient();

  const [profile, activities, comments, encouragements, scriptureDeliveries] =
    await Promise.all([
      admin.from("profiles").select("*").eq("id", uid).maybeSingle(),
      admin.from("activities").select("*").eq("user_id", uid),
      admin.from("comments").select("*").eq("author_id", uid),
      admin.from("encouragements").select("*").eq("from_user_id", uid),
      admin.from("scripture_deliveries").select("*").eq("user_id", uid),
    ]);

  const firstError = [
    profile,
    activities,
    comments,
    encouragements,
    scriptureDeliveries,
  ].find((r) => r.error)?.error;
  if (firstError) {
    console.error(`export-data: query failed for ${uid}`, firstError);
    return jsonResponse({ error: "export_failed" }, { status: 500 });
  }

  return jsonResponse({
    exported_at: new Date().toISOString(),
    profile: profile.data,
    activities: activities.data,
    comments: comments.data,
    encouragements: encouragements.data,
    scripture_deliveries: scriptureDeliveries.data,
  });
});
