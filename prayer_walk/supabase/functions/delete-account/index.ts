// Deletes the caller's own account, and everything that belongs to it.
//
// What removes itself for free (`on delete cascade` from `profiles.id`, which
// itself cascades from `auth.users(id)` — see the migrations under
// supabase/migrations/):
//
//   profiles, activities, follows (both directions), encouragements,
//   comments, privacy_zones, blocks (both directions), scripture_deliveries,
//   moderation_reports.reported_by
//
// What deliberately does NOT cascade, by existing design (see
// 20260728020000_devotionals.sql and 20260728040000_announcements.sql):
// devotionals.author_id and announcements.sent_by are `on delete set null`.
// A devotional or announcement a member published keeps its byline text and
// loses only the link back to the now-deleted account — the same way a
// newspaper doesn't unpublish an article because its author moved on. This
// function does not touch those rows.
//
// What has no foreign key at all, and is the one thing this function must
// clean up by hand: the avatar object in the `avatars` Storage bucket.
// Ownership there is derived from the object path (`avatars/{user_id}/...`),
// not a column `on delete cascade` can see.
//
// Order matters for safety, not just tidiness: storage cleanup runs BEFORE
// the account is deleted. If this function dies partway through, the account
// (and the caller's JWT) is still valid and a retry behaves identically. Once
// `auth.admin.deleteUser` succeeds, the JWT stops resolving to anyone on the
// next call — which is exactly "already done," not a new failure.

import {
  handleCorsPreflight,
  jsonResponse,
} from "../_shared/cors.ts";
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
    console.error("delete-account: auth verification failed", error);
    return jsonResponse({ error: "auth_check_failed" }, { status: 500 });
  }

  const admin = serviceRoleClient();

  // Best-effort. A failure here is logged but must not block the deletion
  // itself — an orphaned ~40-80 KB avatar object is a cheap, documented trade
  // against blocking someone's deletion on a storage hiccup.
  try {
    const { data: files, error: listError } = await admin.storage
      .from("avatars")
      .list(uid);
    if (listError) throw listError;
    if (files && files.length > 0) {
      const paths = files.map((f) => `${uid}/${f.name}`);
      const { error: removeError } = await admin.storage
        .from("avatars")
        .remove(paths);
      if (removeError) throw removeError;
    }
  } catch (error) {
    console.error(
      `delete-account: avatar cleanup failed for ${uid}, continuing`,
      error,
    );
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    // GoTrue's "user not found" is the idempotent-retry case: a previous call
    // already deleted this account (e.g. the client retried after losing the
    // response to a network drop). That is success, not a new failure.
    const alreadyGone =
      deleteError.status === 404 ||
      /not.?found/i.test(deleteError.message ?? "");
    if (!alreadyGone) {
      console.error(`delete-account: deleteUser failed for ${uid}`, deleteError);
      return jsonResponse({ error: "delete_failed" }, { status: 500 });
    }
  }

  return jsonResponse({ ok: true });
});
