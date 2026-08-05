# Edge Functions

Two functions, both invoked by the app from `AuthRepository`
(`lib/src/features/auth/data/auth_repository.dart`):

- **`delete-account`** — deletes the caller's own account: the avatar object
  in Storage, then the `auth.users` row, which cascades to everything else
  (see the comment at the top of `delete-account/index.ts` for exactly what
  cascades and what deliberately doesn't).
- **`export-data`** — returns the caller's own profile, activities, comments,
  encouragements and scripture delivery history as one JSON object.

Both derive the caller's id from their verified JWT (`_shared/auth.ts`),
never from the request body, and both need the service-role key for the
privileged half of their work. **The service-role key is never given to the
app** — Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` into every deployed function's environment
automatically, so there is nothing to configure beyond deploying.

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
`_shared/cors.ts` / `_shared/auth.ts` as the dashboard's editor supports
multi-file functions — check the current dashboard UI for how it wants
shared modules split out; at time of writing it supports a single file per
function, in which case inline the two `_shared` files' contents at the top
of each `index.ts` rather than importing them).

## Testing locally

```bash
supabase functions serve delete-account --env-file ./supabase/.env.local
```

`--env-file` needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` for local testing —
the CLI's own `supabase start` prints both. Never put a real
`SUPABASE_SERVICE_ROLE_KEY` in a file that could be committed; the local CLI
provides its own local-only service role key automatically.
