// `_shared/apple.ts`: the client secret, and the exchange-then-revoke calls to
// Apple, against a fake `fetch`. Run from prayer_walk/:
//
//   deno test --no-lock supabase/functions/tests/

import {
  assert,
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1";
import {
  APPLE_BUNDLE_ID,
  type AppleConfig,
  appleClientSecret,
  AppleRevocationError,
  appleRevokerFromEnv,
  appleSubjectOf,
  revokeAppleAuthorization,
} from "../_shared/apple.ts";

const APPLE_SUB = "001234.5b6c7d8e9f.0123";

/** A real P-256 key pair, with the private half as a `.p8`-style PEM. */
async function keyPair(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const base64 = btoa(String.fromCharCode(...der));
  const lines = base64.match(/.{1,64}/g)!.join("\n");
  return {
    pem: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`,
    publicKey: pair.publicKey,
  };
}

function config(privateKey: string): AppleConfig {
  return {
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    privateKey,
    clientId: APPLE_BUNDLE_ID,
  };
}

function decodeSegment(segment: string): Record<string, unknown> {
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}

function encodeSegment(value: unknown): string {
  return btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** An identity token shaped like Apple's, with a caller-chosen subject. */
function idToken(sub: string): string {
  return `${encodeSegment({ alg: "RS256" })}.${
    encodeSegment({ iss: "https://appleid.apple.com", sub })
  }.signature`;
}

/** A fake `fetch` that answers Apple's two endpoints and records each call. */
function fakeApple(answers: {
  token?: { status: number; body: unknown };
  revoke?: { status: number; body?: string };
}) {
  const calls: Array<{ url: string; form: URLSearchParams }> = [];
  const fetchImpl = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, form: new URLSearchParams(String(init?.body ?? "")) });
    if (url.endsWith("/auth/token")) {
      const answer = answers.token ?? {
        status: 200,
        body: { refresh_token: "r.refresh", id_token: idToken(APPLE_SUB) },
      };
      return Promise.resolve(
        new Response(JSON.stringify(answer.body), { status: answer.status }),
      );
    }
    if (url.endsWith("/auth/revoke")) {
      const answer = answers.revoke ?? { status: 200 };
      return Promise.resolve(
        new Response(answer.body ?? "", { status: answer.status }),
      );
    }
    return Promise.reject(new Error(`unexpected request to ${url}`));
  }) as typeof fetch;
  return { fetchImpl, calls };
}

Deno.test("the client secret is an ES256 JWT Apple can verify", async () => {
  const { pem, publicKey } = await keyPair();

  const secret = await appleClientSecret(config(pem), 1_800_000_000);
  const [header, claims, signature] = secret.split(".");

  assertEquals(decodeSegment(header), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(decodeSegment(claims), {
    iss: "TEAM123456",
    iat: 1_800_000_000,
    exp: 1_800_000_300,
    aud: "https://appleid.apple.com",
    sub: APPLE_BUNDLE_ID,
  });

  const raw = Uint8Array.from(
    atob(signature.replace(/-/g, "+").replace(/_/g, "/").padEnd(
      Math.ceil(signature.length / 4) * 4,
      "=",
    )),
    (c) => c.charCodeAt(0),
  );
  // 64 bytes: the raw r‖s a JWS wants, not a DER-wrapped signature.
  assertEquals(raw.length, 64);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      raw,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
});

Deno.test("a key pasted with its newlines flattened to \\n still signs", async () => {
  const { pem } = await keyPair();
  const flattened = pem.replace(/\n/g, "\\n");

  const secret = await appleClientSecret(config(flattened));
  assertEquals(secret.split(".").length, 3);
});

Deno.test("revocation trades the code, then revokes the refresh token", async () => {
  const { pem } = await keyPair();
  const { fetchImpl, calls } = fakeApple({});

  await revokeAppleAuthorization(config(pem), "the-code", APPLE_SUB, fetchImpl);

  assertEquals(calls.map((call) => call.url), [
    "https://appleid.apple.com/auth/token",
    "https://appleid.apple.com/auth/revoke",
  ]);
  const [exchange, revoke] = calls;
  assertEquals(exchange.form.get("grant_type"), "authorization_code");
  assertEquals(exchange.form.get("code"), "the-code");
  assertEquals(exchange.form.get("client_id"), APPLE_BUNDLE_ID);
  assert((exchange.form.get("client_secret") ?? "").split(".").length === 3);

  assertEquals(revoke.form.get("token"), "r.refresh");
  assertEquals(revoke.form.get("token_type_hint"), "refresh_token");
  assertEquals(revoke.form.get("client_id"), APPLE_BUNDLE_ID);
  assertEquals(
    revoke.form.get("client_secret"),
    exchange.form.get("client_secret"),
  );
});

Deno.test("a code for a different Apple ID is never revoked", async () => {
  const { pem } = await keyPair();
  const { fetchImpl, calls } = fakeApple({
    token: {
      status: 200,
      body: { refresh_token: "r.other", id_token: idToken("someone.else") },
    },
  });

  await assertRejects(
    () => revokeAppleAuthorization(config(pem), "code", APPLE_SUB, fetchImpl),
    AppleRevocationError,
    "different Apple ID",
  );
  assertEquals(calls.length, 1);
});

Deno.test("a rejected code stops before the revoke call", async () => {
  const { pem } = await keyPair();
  const { fetchImpl, calls } = fakeApple({
    token: { status: 400, body: { error: "invalid_grant" } },
  });

  await assertRejects(
    () => revokeAppleAuthorization(config(pem), "used", APPLE_SUB, fetchImpl),
    AppleRevocationError,
    "invalid_grant",
  );
  assertEquals(calls.length, 1);
});

Deno.test("a refused revoke is reported, not swallowed", async () => {
  const { pem } = await keyPair();
  const { fetchImpl } = fakeApple({
    revoke: { status: 400, body: '{"error":"invalid_client"}' },
  });

  await assertRejects(
    () => revokeAppleAuthorization(config(pem), "code", APPLE_SUB, fetchImpl),
    AppleRevocationError,
    "invalid_client",
  );
});

Deno.test("an unconfigured environment names every missing variable", () => {
  const revoker = appleRevokerFromEnv((name) =>
    name === "APPLE_TEAM_ID" ? "TEAM123456" : name === "APPLE_KEY_ID" ? "  " : undefined
  );

  assertEquals(revoker, {
    ready: false,
    missing: ["APPLE_KEY_ID", "APPLE_PRIVATE_KEY"],
  });
});

Deno.test("a configured environment is ready, defaulting to the bundle ID", async () => {
  const { pem } = await keyPair();
  const { fetchImpl, calls } = fakeApple({});
  const env: Record<string, string> = {
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_PRIVATE_KEY: pem,
  };

  const revoker = appleRevokerFromEnv((name) => env[name], fetchImpl);
  assert(revoker.ready);
  await revoker.revoke("code", APPLE_SUB);

  assertEquals(calls[0].form.get("client_id"), APPLE_BUNDLE_ID);
});

Deno.test("the Apple subject comes from the apple identity, and only that one", () => {
  const appleUser = {
    identities: [
      { provider: "email", id: "x", identity_data: { sub: "not-apple" } },
      { provider: "apple", id: APPLE_SUB, identity_data: { sub: APPLE_SUB } },
    ],
  };
  assertEquals(appleSubjectOf(appleUser), APPLE_SUB);

  assertEquals(
    appleSubjectOf({ identities: [{ provider: "google", id: "g-1" }] }),
    null,
  );
  assertEquals(appleSubjectOf({ identities: [] }), null);
  assertEquals(appleSubjectOf(null), null);
});
