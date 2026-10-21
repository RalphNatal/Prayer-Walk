// Sign in with Apple, from the server side: the client secret Apple asks for,
// and the one thing this project does with it — revoke the app's
// authorization on a member's Apple ID when they delete their account (App
// Store Guideline 5.1.1(v)).
//
// Why there is a code exchange at all: Apple's revoke endpoint takes a refresh
// or access token, and native Sign in with Apple never leaves one anywhere
// this project can reach — the app hands Supabase only the identity token,
// which Apple will not revoke. So at deletion the app asks Apple for one fresh
// authorization code (see AuthRepository.deleteAccount), and this trades it
// for a token and revokes that token straight away. Nothing is stored.
//
// Apple's references:
//   https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens
//   https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

const APPLE_ORIGIN = "https://appleid.apple.com";
const TOKEN_URL = `${APPLE_ORIGIN}/auth/token`;
const REVOKE_URL = `${APPLE_ORIGIN}/auth/revoke`;

/**
 * The iOS app's bundle ID: the `aud` of every token its native sign-in
 * produces, and so the `client_id` Apple expects back. Not a secret.
 */
export const APPLE_BUNDLE_ID = "com.calledpresentations.prayerwalk";

export interface AppleConfig {
  /** Apple Developer Team ID — the `iss` of the client secret. */
  teamId: string;
  /** The Sign in with Apple key's ID — the `kid` of the client secret. */
  keyId: string;
  /** The key's `.p8` contents: a PKCS#8 PEM. */
  privateKey: string;
  /** The bundle ID, unless overridden — the `sub` of the client secret. */
  clientId: string;
}

/**
 * What `delete-account` is handed: either a way to revoke, or the names of
 * the environment variables that would have made one.
 */
export type AppleRevoker =
  | {
    ready: true;
    revoke(authorizationCode: string, appleSubject: string): Promise<void>;
  }
  | { ready: false; missing: string[] };

export class AppleRevocationError extends Error {}

/**
 * Reads the Sign in with Apple key from the environment. Missing values are
 * reported by name rather than thrown: the caller decides what an
 * unconfigured project means, and for `delete-account` it means "delete
 * anyway, and say so".
 */
export function appleRevokerFromEnv(
  env: (name: string) => string | undefined,
  fetchImpl: typeof fetch = fetch,
): AppleRevoker {
  const read = (name: string) => env(name)?.trim() || undefined;
  const teamId = read("APPLE_TEAM_ID");
  const keyId = read("APPLE_KEY_ID");
  const privateKey = read("APPLE_PRIVATE_KEY");

  const missing = [
    ...(teamId ? [] : ["APPLE_TEAM_ID"]),
    ...(keyId ? [] : ["APPLE_KEY_ID"]),
    ...(privateKey ? [] : ["APPLE_PRIVATE_KEY"]),
  ];
  if (!teamId || !keyId || !privateKey) return { ready: false, missing };

  const config: AppleConfig = {
    teamId,
    keyId,
    privateKey,
    clientId: read("APPLE_CLIENT_ID") ?? APPLE_BUNDLE_ID,
  };
  return {
    ready: true,
    revoke: (code, subject) =>
      revokeAppleAuthorization(config, code, subject, fetchImpl),
  };
}

/**
 * The Apple user id (`sub`) behind an account's Apple identity, or null if
 * the account has none — i.e. it never signed in with Apple.
 */
export function appleSubjectOf(
  user:
    | {
      identities?:
        | Array<{
          provider?: string;
          id?: string;
          identity_data?: Record<string, unknown> | null;
        }>
        | null;
    }
    | null
    | undefined,
): string | null {
  const identity = user?.identities?.find((i) => i.provider === "apple");
  if (!identity) return null;
  const sub = identity.identity_data?.["sub"];
  if (typeof sub === "string" && sub.length > 0) return sub;
  return identity.id || null;
}

/**
 * The client secret Apple's token and revoke endpoints authenticate with: a
 * short-lived ES256 JWT signed by the Sign in with Apple key.
 */
export async function appleClientSecret(
  config: AppleConfig,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = { alg: "ES256", kid: config.keyId };
  const claims = {
    iss: config.teamId,
    iat: nowSeconds,
    // Five minutes: it is minted for two requests made back to back.
    exp: nowSeconds + 300,
    aud: APPLE_ORIGIN,
    sub: config.clientId,
  };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto's ECDSA signature is already the raw r‖s pair a JWS ES256
  // signature is — no DER to unwrap, unlike most other crypto libraries.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

/**
 * Trades [authorizationCode] for a token and revokes it — which ends this
 * app's authorization on that Apple ID, the same as the member removing it
 * under Settings → Apple ID → Sign in with Apple.
 *
 * Refuses to revoke anything unless the code turns out to belong to
 * [appleSubject], the Apple ID on the account being deleted. A code for some
 * other Apple ID (the device signed in to a different one, say) would
 * otherwise sign a stranger out of the app. Throws [AppleRevocationError] on
 * any failure; nothing here is retried.
 */
export async function revokeAppleAuthorization(
  config: AppleConfig,
  authorizationCode: string,
  appleSubject: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const clientSecret = await appleClientSecret(config);

  const tokenResponse = await fetchImpl(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) {
    throw new AppleRevocationError(
      `token exchange failed: HTTP ${tokenResponse.status} ${await
        errorBody(tokenResponse)}`,
    );
  }
  const tokens = await tokenResponse.json();

  // The identity token's signature is not checked, deliberately: it arrived
  // straight from Apple's token endpoint over TLS, in answer to a request
  // this function authenticated, which is the case OpenID Connect allows to
  // skip it (Core §3.1.3.7). Only the subject is read.
  const subject = typeof tokens.id_token === "string"
    ? jwtSubject(tokens.id_token)
    : null;
  if (subject !== appleSubject) {
    throw new AppleRevocationError(
      "the authorization code belongs to a different Apple ID; not revoking",
    );
  }

  const [token, tokenTypeHint] = typeof tokens.refresh_token === "string"
    ? [tokens.refresh_token, "refresh_token"]
    : typeof tokens.access_token === "string"
    ? [tokens.access_token, "access_token"]
    : [null, null];
  if (!token || !tokenTypeHint) {
    throw new AppleRevocationError("token exchange returned no token");
  }

  const revokeResponse = await fetchImpl(REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokenTypeHint,
    }),
  });
  if (!revokeResponse.ok) {
    throw new AppleRevocationError(
      `revoke failed: HTTP ${revokeResponse.status} ${await
        errorBody(revokeResponse)}`,
    );
  }
}

/**
 * The key's DER bytes, from however the `.p8` reached the environment: the
 * PEM as-is, the PEM with its newlines flattened to literal `\n`, or the
 * base64 body alone.
 */
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0)).buffer;
}

function jwtSubject(jwt: string): string | null {
  const payload = jwt.split(".")[1];
  if (!payload) return null;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const json = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)),
      ),
    );
    return typeof json?.sub === "string" ? json.sub : null;
  } catch {
    return null;
  }
}

/** Apple's error bodies are short codes (`{"error":"invalid_grant"}`). */
async function errorBody(response: Response): Promise<string> {
  try {
    return (await response.text()).slice(0, 200);
  } catch {
    return "(no body)";
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}
