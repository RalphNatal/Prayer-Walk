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
// What has no foreign key at all, and is the one thing in this project this
// function must clean up by hand: the avatar object in the `avatars` Storage
// bucket. Ownership there is derived from the object path
// (`avatars/{user_id}/...`), not a column `on delete cascade` can see.
//
// And one thing that is not in this project at all: for a member who signed
// in with Apple, the app's authorization on their Apple ID. Apple requires an
// app offering Sign in with Apple to revoke it when the account is deleted
// (App Store Guideline 5.1.1(v)). Revocation takes a refresh or access token,
// and native sign-in never leaves one anywhere this project can reach — the
// app hands Supabase the identity token only — so the app asks Apple for one
// fresh authorization code at deletion and sends it here as
// `apple_authorization_code`, and `_shared/apple.ts` trades it for a token and
// revokes that. Nothing is stored. It needs the Sign in with Apple key, which
// reaches this function as environment variables (see ../README.md). Without
// them, without a code, or if Apple refuses, the account is still deleted and
// the log says loudly that the token was NOT revoked: a misconfigured project
// must not keep a member who has asked to leave.
//
// Order matters for safety, not just tidiness: Apple revocation, then storage
// cleanup, run BEFORE the account is deleted. Revocation needs the account to
// still exist — its Apple identity is what the code is checked against, so a
// code for some other Apple ID is never revoked — and if this function dies
// partway through, the account (and the caller's JWT) is still valid and a
// retry behaves identically: the app asks Apple for a fresh code, since a code
// is single-use, and revoking an authorization twice is harmless. Once
// `auth.admin.deleteUser` succeeds, the JWT stops resolving to anyone on the
// next call — which is exactly "already done," not a new failure.
//
// The order and the failure policy live in handler.ts, where ../tests/ can
// drive them; this file wires each step to Supabase and Apple.

import { serviceRoleClient, verifiedCallerId } from "../_shared/auth.ts";
import { appleRevokerFromEnv, appleSubjectOf } from "../_shared/apple.ts";
import { handleDeleteAccount } from "./handler.ts";

Deno.serve((req) => {
  // Built only once a step needs it, so a preflight or a rejected caller
  // never creates a service-role client.
  let client: ReturnType<typeof serviceRoleClient> | undefined;
  const admin = () => (client ??= serviceRoleClient());

  return handleDeleteAccount(req, {
    callerId: verifiedCallerId,

    async appleSubject(uid) {
      const { data, error } = await admin().auth.admin.getUserById(uid);
      if (error) throw error;
      return appleSubjectOf(data.user);
    },

    async removeAvatars(uid) {
      const { data: files, error: listError } = await admin().storage
        .from("avatars")
        .list(uid);
      if (listError) throw listError;
      if (files && files.length > 0) {
        const paths = files.map((f) => `${uid}/${f.name}`);
        const { error: removeError } = await admin().storage
          .from("avatars")
          .remove(paths);
        if (removeError) throw removeError;
      }
    },

    async deleteUser(uid) {
      const { error } = await admin().auth.admin.deleteUser(uid);
      return error;
    },

    apple: appleRevokerFromEnv((name) => Deno.env.get(name)),
  });
});
