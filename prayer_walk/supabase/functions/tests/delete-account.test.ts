// `delete-account`'s order and failure policy, driven through handler.ts with
// every Supabase and Apple call replaced. Run from prayer_walk/:
//
//   deno test --no-lock supabase/functions/tests/

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { AppleRevoker } from "../_shared/apple.ts";
import {
  type DeleteAccountDeps,
  handleDeleteAccount,
} from "../delete-account/handler.ts";

const UID = "2b7c1f0e-0000-4000-8000-0000000000aa";
const APPLE_SUB = "001234.5b6c7d8e9f.0123";
const CODE = "c1a2b3.0.abcd.EFGH";

function request(body?: unknown): Request {
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers: { Authorization: "Bearer member-jwt" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/**
 * Fake dependencies that record, in order, every step the handler takes —
 * so a test can assert not just that revocation happened, but that it
 * happened before the account was deleted.
 */
function fakes(options: {
  appleSubject?: string | null | Error;
  apple?: "ready" | "throws" | { missing: string[] };
} = {}) {
  const steps: string[] = [];
  const subject = options.appleSubject ?? null;
  const appleMode = options.apple ?? "ready";

  const apple: AppleRevoker = typeof appleMode === "object"
    ? { ready: false, missing: appleMode.missing }
    : {
      ready: true,
      revoke: (code, sub) => {
        steps.push(`revoke ${code} for ${sub}`);
        return appleMode === "throws"
          ? Promise.reject(new Error("HTTP 400 invalid_grant"))
          : Promise.resolve();
      },
    };

  const deps: DeleteAccountDeps = {
    callerId: () => Promise.resolve(UID),
    appleSubject: () => {
      steps.push("read identities");
      return subject instanceof Error
        ? Promise.reject(subject)
        : Promise.resolve(subject);
    },
    removeAvatars: () => {
      steps.push("remove avatars");
      return Promise.resolve();
    },
    deleteUser: () => {
      steps.push("delete user");
      return Promise.resolve(null);
    },
    apple,
  };
  return { deps, steps };
}

/** Runs [fn] with console.error captured, and returns what it logged. */
async function capturingErrors<T>(
  fn: () => Promise<T>,
): Promise<{ result: T; errors: string[] }> {
  const errors: string[] = [];
  const original = console.error;
  const originalLog = console.log;
  console.error = (...args: unknown[]) => errors.push(args.map(String).join(" "));
  console.log = () => {};
  try {
    return { result: await fn(), errors };
  } finally {
    console.error = original;
    console.log = originalLog;
  }
}

Deno.test("an Apple account's token is revoked, before anything is deleted", async () => {
  const { deps, steps } = fakes({ appleSubject: APPLE_SUB });

  const { result: response } = await capturingErrors(() =>
    handleDeleteAccount(request({ apple_authorization_code: CODE }), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, [
    "read identities",
    `revoke ${CODE} for ${APPLE_SUB}`,
    "remove avatars",
    "delete user",
  ]);
});

Deno.test("an account without Apple never reaches Apple", async () => {
  const { deps, steps } = fakes({ appleSubject: null });

  const { result: response, errors } = await capturingErrors(() =>
    handleDeleteAccount(request(), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, ["read identities", "remove avatars", "delete user"]);
  assertEquals(errors, []);
});

Deno.test("a stray code on an account without Apple is ignored", async () => {
  const { deps, steps } = fakes({ appleSubject: null });

  const { result: response } = await capturingErrors(() =>
    handleDeleteAccount(request({ apple_authorization_code: CODE }), deps)
  );

  assertEquals(response.status, 200);
  assert(!steps.some((step) => step.startsWith("revoke")));
});

Deno.test("a failed revocation still deletes the account, and says so", async () => {
  const { deps, steps } = fakes({ appleSubject: APPLE_SUB, apple: "throws" });

  const { result: response, errors } = await capturingErrors(() =>
    handleDeleteAccount(request({ apple_authorization_code: CODE }), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, [
    "read identities",
    `revoke ${CODE} for ${APPLE_SUB}`,
    "remove avatars",
    "delete user",
  ]);
  assert(errors.some((line) => line.includes("WITHOUT revoking")));
});

Deno.test("a missing Apple key still deletes the account, and names what is missing", async () => {
  const { deps, steps } = fakes({
    appleSubject: APPLE_SUB,
    apple: { missing: ["APPLE_KEY_ID", "APPLE_PRIVATE_KEY"] },
  });

  const { result: response, errors } = await capturingErrors(() =>
    handleDeleteAccount(request({ apple_authorization_code: CODE }), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, ["read identities", "remove avatars", "delete user"]);
  assert(
    errors.some((line) =>
      line.includes("[CONFIG]") && line.includes("APPLE_KEY_ID, APPLE_PRIVATE_KEY")
    ),
  );
});

Deno.test("an Apple account that sent no code still deletes, without calling Apple", async () => {
  const { deps, steps } = fakes({ appleSubject: APPLE_SUB });

  const { result: response, errors } = await capturingErrors(() =>
    handleDeleteAccount(request(), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, ["read identities", "remove avatars", "delete user"]);
  assert(errors.some((line) => line.includes("no apple_authorization_code")));
});

Deno.test("identities that can't be read still let the deletion through", async () => {
  const { deps, steps } = fakes({ appleSubject: new Error("network down") });

  const { result: response } = await capturingErrors(() =>
    handleDeleteAccount(request({ apple_authorization_code: CODE }), deps)
  );

  assertEquals(response.status, 200);
  assertEquals(steps, ["read identities", "remove avatars", "delete user"]);
});

Deno.test("a body that isn't JSON is treated as no code, not as a failure", async () => {
  const { deps, steps } = fakes({ appleSubject: APPLE_SUB });

  const { result: response } = await capturingErrors(() =>
    handleDeleteAccount(
      new Request("http://localhost/delete-account", {
        method: "POST",
        body: "not json",
      }),
      deps,
    )
  );

  assertEquals(response.status, 200);
  assertEquals(steps, ["read identities", "remove avatars", "delete user"]);
});
