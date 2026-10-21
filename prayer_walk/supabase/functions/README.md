# Edge Functions

Two functions, both invoked by the app from `AuthRepository`
(`lib/src/features/auth/data/auth_repository.dart`):

- **`delete-account`** — deletes the caller's own account: for a member who
  signed in with Apple, it first revokes the app's Apple token; then the
  avatar object in Storage; then the `auth.users` row, which cascades to
  everything else (see the comment at the top of `delete-account/index.ts`
  for exactly what cascades, what deliberately doesn't, and why the order is
  what it is).
- **`export-data`** — returns the caller's own profile, activities, comments,
  encouragements and scripture delivery history as one JSON object.

Both derive the caller's id from their verified JWT (`_shared/auth.ts`),
never from the request body, and both need the service-role key for the
privileged half of their work. **The service-role key is never given to the
app** — Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` into every deployed function's environment
automatically. The one thing that is not automatic is the Sign in with Apple
key, below.

## Sign in with Apple key (`delete-account`)

Apple requires an app that offers Sign in with Apple to revoke the member's
Apple token when they delete their account (App Store Guideline 5.1.1(v)).
`delete-account` does that with Apple's revoke endpoint, which authenticates
with a client secret signed by a Sign in with Apple key. The key reaches the
function as secrets — set them under **Supabase Dashboard → Edge Functions →
Secrets** (or `supabase secrets set NAME=value`):

| Secret | Value | Where it comes from |
| --- | --- | --- |
| `APPLE_TEAM_ID` | The 10-character Team ID | Apple Developer → Membership details |
| `APPLE_KEY_ID` | The 10-character Key ID | Apple Developer → Certificates, Identifiers & Profiles → Keys → the Sign in with Apple key |
| `APPLE_PRIVATE_KEY` | The whole contents of `AuthKey_<KEY_ID>.p8`, including the `BEGIN`/`END` lines | Downloaded once, when the key is created |
| `APPLE_CLIENT_ID` | *Optional.* Defaults to the bundle ID, `com.calledpresentations.prayerwalk` | Only set it if the bundle ID changes |

The key must have **Sign in with Apple** enabled and be configured for the
primary App ID `com.calledpresentations.prayerwalk`. The `.p8` can only be
downloaded once: keep it somewhere safe, and **never commit it** — `*.p8` is
already in `.gitignore`. `APPLE_PRIVATE_KEY` accepts the PEM with real
newlines, with the newlines flattened to `\n`, or the base64 body alone,
whichever the dashboard's secret field preserves.

If any of the three is missing, the function **still deletes the account** —
a misconfigured project must not keep a member who has asked to leave — and
logs, on every Apple account it deletes, a line starting
`delete-account: [CONFIG]` that names the missing secrets and says the token
was NOT revoked. The same goes for Apple refusing the request. Search the
function's logs for `WITHOUT revoking` to find every account that left
without a revocation.

## Deploying

Either works; the code is plain Deno and doesn't care which path put it on
the server.

**Supabase CLI**, if the project is linked (`supabase link --project-ref
<ref>`):

```bash
supabase functions deploy delete-account
supabase functions deploy export-data
```

**Dashboard**, if you'd rather not install the CLI: Supabase Dashboard → Edge
Functions → Create a function → paste the contents of `index.ts` (and
the `_shared/` files it imports, as the dashboard's editor supports
multi-file functions — check the current dashboard UI for how it wants
shared modules split out; at time of writing it supports a single file per
function, in which case inline the `_shared` files' contents at the top of
each `index.ts` rather than importing them). `delete-account` is five files:
its `index.ts` and `handler.ts`, plus `_shared/cors.ts`, `_shared/auth.ts`
and `_shared/apple.ts`.

## Tests

The functions' Deno tests drive `delete-account`'s order and failure policy,
and the Apple client secret, exchange and revocation, with every network
call faked — no server, database or Apple account needed. From
`prayer_walk/`:

```bash
deno test --no-lock supabase/functions/tests/
```

## Testing locally

```bash
supabase functions serve delete-account --env-file ./supabase/.env.local
```

`--env-file` needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` for local testing —
the CLI's own `supabase start` prints both. Never put a real
`SUPABASE_SERVICE_ROLE_KEY` in a file that could be committed; the local CLI
provides its own local-only service role key automatically.
