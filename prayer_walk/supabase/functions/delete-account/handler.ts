// The order and the failure policy of `delete-account`, apart from the
// Supabase and Apple calls that carry them out. index.ts wires those up, and
// its header explains what each step removes and why it runs where it does.
// Split out so the tests in ../tests/ can drive it with no server, no
// database and no Apple.

import { handleCorsPreflight, jsonResponse } from "../_shared/cors.ts";
import { UnauthorizedError } from "../_shared/auth.ts";
import type { AppleRevoker } from "../_shared/apple.ts";

export interface DeleteAccountDeps {
  /** The caller's id, from their verified JWT. Throws [UnauthorizedError]. */
  callerId(req: Request): Promise<string>;
  /** The account's Apple user id (`sub`), or null if it has no Apple identity. */
  appleSubject(uid: string): Promise<string | null>;
  /** Removes the account's avatar objects from Storage. Throws on failure. */
  removeAvatars(uid: string): Promise<void>;
  /** Deletes the auth user. Resolves to GoTrue's error, or null. */
  deleteUser(
    uid: string,
  ): Promise<{ status?: number; message?: string } | null>;
  apple: AppleRevoker;
}

export async function handleDeleteAccount(
  req: Request,
  deps: DeleteAccountDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
  }

  let uid: string;
  try {
    uid = await deps.callerId(req);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      return jsonResponse({ error: "unauthorized" }, { status: 401 });
    }
    console.error("delete-account: auth verification failed", error);
    return jsonResponse({ error: "auth_check_failed" }, { status: 500 });
  }

  // Best-effort, and first: it needs the account's Apple identity, which
  // goes with the account. Never blocks the deletion — see revokeAppleToken.
  await revokeAppleToken(uid, await appleAuthorizationCode(req), deps);

  // Best-effort. A failure here is logged but must not block the deletion
  // itself — an orphaned ~40-80 KB avatar object is a cheap, documented trade
  // against blocking someone's deletion on a storage hiccup.
  try {
    await deps.removeAvatars(uid);
  } catch (error) {
    console.error(
      `delete-account: avatar cleanup failed for ${uid}, continuing`,
      error,
    );
  }

  const deleteError = await deps.deleteUser(uid);
  if (deleteError) {
    // GoTrue's "user not found" is the idempotent-retry case: a previous call
    // already deleted this account (e.g. the client retried after losing the
    // response to a network drop). That is success, not a new failure.
    const alreadyGone = deleteError.status === 404 ||
      /not.?found/i.test(deleteError.message ?? "");
    if (!alreadyGone) {
      console.error(`delete-account: deleteUser failed for ${uid}`, deleteError);
      return jsonResponse({ error: "delete_failed" }, { status: 500 });
    }
  }

  return jsonResponse({ ok: true });
}

/**
 * The fresh Apple authorization code the app sends for an Apple account, or
 * null. Every other account's request has no body at all.
 */
async function appleAuthorizationCode(req: Request): Promise<string | null> {
  try {
    const text = await req.text();
    if (!text) return null;
    const code = JSON.parse(text)?.apple_authorization_code;
    return typeof code === "string" && code.length > 0 ? code : null;
  } catch {
    return null;
  }
}

/**
 * Revokes the app's Apple authorization for an Apple account — and for every
 * way that can fail, logs it loudly and returns, so the deletion goes ahead.
 *
 * Apple requires the revocation; the member's right to leave comes first. A
 * project missing its Apple key, an app that sent no code, or Apple saying no
 * must not strand someone who has asked for their account to be deleted. The
 * log line says the token was NOT revoked, so whoever reads it can remove the
 * authorization by hand.
 */
async function revokeAppleToken(
  uid: string,
  code: string | null,
  deps: DeleteAccountDeps,
): Promise<void> {
  let subject: string | null;
  try {
    subject = await deps.appleSubject(uid);
  } catch (error) {
    console.error(
      `delete-account: could not read identities for ${uid}; deleting ` +
        "WITHOUT revoking any Apple token, continuing",
      error,
    );
    return;
  }
  // Not an Apple account. Nothing to revoke, and Apple is never contacted.
  if (subject === null) return;

  if (!deps.apple.ready) {
    console.error(
      `delete-account: [CONFIG] Apple account ${uid} is being deleted WITHOUT ` +
        `revoking its Apple token — ${deps.apple.missing.join(", ")} not ` +
        "set. See supabase/functions/README.md.",
    );
    return;
  }
  if (!code) {
    console.error(
      `delete-account: Apple account ${uid} sent no ` +
        "apple_authorization_code; deleting WITHOUT revoking its Apple token",
    );
    return;
  }

  try {
    await deps.apple.revoke(code, subject);
    console.log(`delete-account: Apple token revoked for ${uid}`);
  } catch (error) {
    console.error(
      `delete-account: Apple token revocation failed for ${uid}; deleting ` +
        "WITHOUT revoking, continuing",
      error,
    );
  }
}
