# Prayer-Walk

## Database setup

Migrations go through the Supabase CLI against the linked project:

```
npx supabase db push
```

Remote history lives in `supabase_migrations.schema_migrations`; `npx supabase
migration list` shows local against remote and is the first thing to run when
the app and the database disagree.

Most migrations are also written to be safe to re-run by hand
(`create table if not exists`, `create or replace`, `drop policy if exists …
create policy`). Two are not: `20260726010000_activities.sql` and
`20260727020000_scripture_prompts.sql` create their policies unguarded, so
re-applying either against a database that already has them fails with `42710
policy already exists`. Both are long since applied — this only matters if you
rebuild from scratch or repair history.

**`20260725000000_profiles_retro_captured.sql` is deliberately out of order.**
It was written after the migrations that follow it, and carries an earlier
timestamp because every other table references `profiles(id)` and a rebuild in
filename order has to create it first. `db push` refuses to insert a migration
before the last one on remote, so on a project that already has the later files
recorded it reports:

```
Found local migration files to be inserted before the last migration on remote
database. Rerun the command with --include-all flag to apply these migrations:
supabase/migrations/20260725000000_profiles_retro_captured.sql
```

`npx supabase db push --include-all` is the answer. That file is written to be a
no-op against a live project — the only things it touches rather than skips are
the two `profiles` policies and `handle_new_user()`, which it recreates from the
file's version.

The app never creates or alters schema at runtime. If something is missing, a
human runs the migration.

### Migrations — `supabase/migrations/`, in this order

| # | File | What it does |
|---|------|--------------|
| 1 | `20260725000000_profiles_retro_captured.sql` | `profiles`, the signup trigger and the original RLS policies, written down after the fact. Sign-in reads `profiles.role`, so nothing works without this. |
| 2 | `20260726000000_profiles_member_fields.sql` | Adds the columns a member edits themselves. No new policies — the existing self-update policy already covers them. |
| 3 | `20260726010000_activities.sql` | `activities` — the recorded walk, with route, waypoints and intentions as JSONB on the row. |
| 4 | `20260727000000_activity_place_name.sql` | Adds `activities.place_name`, the reverse-geocoded caption. Nullable, no backfill. |
| 5 | `20260727010000_social_graph.sql` | `follows`, `encouragements`, `comments`, plus the RPCs `feed_for`, `activities_for`, `activity_detail` and `member_stats`. |
| 6 | `20260727020000_scripture_prompts.sql` | `scripture_prompts` — the glance-length text delivered mid-walk. |
| 7 | `20260728010000_admin_role_rules.sql` | ⚠️ **Changes existing security rules.** Rewrites the `prevent_self_role_change` trigger so an admin acting as `authenticated` can administer at all, and adds `is_admin()`. Read the file header before applying. |
| 8 | `20260728020000_devotionals.sql` | `devotionals` — the reader-length shelf, and the `touch_updated_at` trigger. |
| 9 | `20260728030000_moderation_reports.sql` | `moderation_reports` — what members flag. `target_id` is intentionally unconstrained. |
| 10 | `20260728040000_announcements.sql` | `announcements` — console broadcasts, with `recipient_count` frozen at send time. |
| 11 | `20260728050000_admin_functions.sql` | The console's reads, one round trip each: `admin_metrics`, `admin_members`, `admin_reports`, `admin_resolve_report`, `audience_size`. Each raises `42501` for a non-admin. |
| 12 | `20260728060000_suspension_enforcement.sql` | ⚠️ **Changes existing security rules.** Adds six RESTRICTIVE policies so `profiles.status = 'suspended'` actually blocks writes. They are ANDed with the Phase-2 policies rather than replacing them — drop these six and the old rules stand unchanged. |

**The two marked ⚠️ are the ones to read before running.** Everything else adds
objects; those two change how existing ones behave.

### Seeds — `supabase/seed/`, applied by hand

Content, not schema — which is why they live outside `supabase/migrations/` and
why `db push` does not run them. Paste each into the Supabase SQL editor once,
after its migration has landed. Both are idempotent (a row with the same title,
or the same reference and body, is skipped), so running one twice does not
duplicate anything, and both are a starting library an admin is expected to edit
and prune from the console.

| File | Run after | Contents |
|------|-----------|----------|
| `scripture_prompts_seed.sql` | migration 6 | The starting scripture library. Public-domain WEBBE text only. |
| `devotionals_seed.sql` | migration 8 | The starting devotional shelf. |

### After applying anything: reload the schema cache

PostgREST answers from a cached copy of the schema, so a table can exist in the
database and still be missing from the API for a few seconds — which surfaces in
the app as:

```
code: PGRST205
message: Could not find the table 'public.devotionals' in the schema cache
```

If that persists after the SQL has landed, reload the cache explicitly:

```sql
NOTIFY pgrst, 'reload schema';
```

### Checking what a database is missing

Debug and internal builds probe every expected table and RPC once at startup and
log a single block naming what is absent and which file creates it:

```
adb logcat | grep PW-SCHEMA
```

The probes run concurrently, read no rows, never block startup, and are compiled
out of release builds. The preflight only reports — applying the SQL is still a
human's job.