-- Group scripture: who may read it, who may write it, what it may be, and
-- what a walk is handed.
--
--   npx supabase test db

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(23);

create schema if not exists tests;
grant usage on schema tests to authenticated;

-- Both claim settings: `auth.uid()` reads `request.jwt.claims` on a current
-- stack and `request.jwt.claim.sub` on an older one.
create or replace function tests.login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims',
                     json_build_object('sub', uid, 'role', 'authenticated')::text,
                     true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.logout() returns void
language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;
grant execute on all functions in schema tests to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'alice@test'),  -- admin of St Anne
  ('00000000-0000-4000-8000-0000000000b1', 'bob@test'),    -- member of St Anne
  ('00000000-0000-4000-8000-0000000000c1', 'carol@test'),  -- in nothing
  ('00000000-0000-4000-8000-0000000000d1', 'dave@test'),   -- admin of St Brigid
  ('00000000-0000-4000-8000-0000000000e1', 'erin@test'),   -- app admin
  ('00000000-0000-4000-8000-0000000000f1', 'pam@test');    -- waiting to join

update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000000e1';

-- One global verse, as the seed would leave it.
insert into public.scripture_prompts (reference, body, translation, status, is_published)
values ('Psalm 121:1', 'I will lift up my eyes to the hills.', 'WEBBE', 'approved', true);

select tests.login('00000000-0000-4000-8000-0000000000a1');
create temp table anne as
  select * from public.create_church_group('St Anne', '', '', true, 'open');
create temp table quiet as
  select * from public.create_church_group('St Anne Vigil', '', '', true, 'request');
grant select on anne, quiet to authenticated;

select tests.login('00000000-0000-4000-8000-0000000000d1');
create temp table brigid as
  select * from public.create_church_group('St Brigid', '', '', true, 'open');
grant select on brigid to authenticated;

select tests.login('00000000-0000-4000-8000-0000000000b1');
insert into public.church_group_members (group_id, user_id)
values ((select id from anne), '00000000-0000-4000-8000-0000000000b1');

select tests.login('00000000-0000-4000-8000-0000000000f1');
insert into public.church_group_members (group_id, user_id, status)
values ((select id from quiet), '00000000-0000-4000-8000-0000000000f1', 'pending');

-- ------------------------------------------------------------- writing ---

select tests.login('00000000-0000-4000-8000-0000000000a1');

select lives_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
     values ('Isaiah 40:31', 'Those who wait for Yahweh will renew their strength.', 'WEBBE',
             (select id from anne), auth.uid(), auth.uid(), 'approved', true) $$,
  'a group admin publishes public-domain scripture to their group'
);

select lives_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, kind, group_id, published_by, rights_attested_by, status, is_published)
     values ('For our streets', 'Keep us kind to whoever we pass.', '', 'prayer',
             (select id from anne), auth.uid(), auth.uid(), 'approved', true) $$,
  'and a prayer of their own, which quotes nobody'
);

select throws_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
     values ('John 3:16', 'licensed text', 'NLT',
             (select id from anne), auth.uid(), auth.uid(), 'approved', true) $$,
  '23514', null,
  'a licensed translation is refused for group scripture'
);

select throws_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, published_by, status, is_published)
     values ('Psalm 23:1', 'Yahweh is my shepherd.', 'WEBBE',
             (select id from anne), auth.uid(), 'approved', true) $$,
  '42501', null,
  'publishing without confirming the right to is refused'
);

select is(
  (select rights_attested_by from public.scripture_prompts where reference = 'Isaiah 40:31'),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'who confirmed the right to publish is on the row'
);

insert into public.scripture_prompts
  (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
values ('Micah 6:8', 'Draft, not yet out.', 'WEBBE',
        (select id from anne), auth.uid(), auth.uid(), 'approved', false);

insert into public.scripture_prompts
  (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
values ('Psalm 46:10', 'Be still, and know that I am God.', 'WEBBE',
        (select id from quiet), auth.uid(), auth.uid(), 'approved', true);

-- ------------------------------------------------------------- reading ---

select tests.login('00000000-0000-4000-8000-0000000000b1');
select is(
  (select count(*)::int from public.scripture_prompts where group_id = (select id from anne)),
  2,
  'a member reads their group''s published scripture, and not its drafts'
);
select is(
  (select count(*)::int from public.walk_scripture_library()),
  3,
  'a member''s walk draws on the global library plus their group'
);

select tests.login('00000000-0000-4000-8000-0000000000c1');
select is(
  (select count(*)::int from public.scripture_prompts where group_id is not null),
  0,
  'a non-member cannot read any group''s scripture'
);
select is(
  (select count(*)::int from public.walk_scripture_library()),
  1,
  'a non-member''s walk gets the global library only'
);

select tests.login('00000000-0000-4000-8000-0000000000f1');
select is(
  (select count(*)::int from public.scripture_prompts where group_id = (select id from quiet)),
  0,
  'someone still waiting to be let in does not receive the group''s scripture'
);

select tests.login('00000000-0000-4000-8000-0000000000e1');
select is(
  (select count(*)::int from public.scripture_prompts where group_id = (select id from anne)),
  3,
  'an app admin can read a group''s scripture, drafts included, to moderate it'
);
select is(
  (select count(*)::int from public.walk_scripture_library()),
  1,
  'but an app admin''s walk is not handed churches they do not belong to'
);

-- -------------------------------------------------- another group's rows ---

select tests.login('00000000-0000-4000-8000-0000000000d1');
select throws_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
     values ('Psalm 1:1', 'x', 'WEBBE', (select id from anne), auth.uid(), auth.uid(), 'approved', true) $$,
  '42501', null,
  'a group admin cannot publish into another group'
);

update public.scripture_prompts set body = 'defaced' where reference = 'Isaiah 40:31';
delete from public.scripture_prompts where reference = 'Isaiah 40:31';
select tests.logout();
select is(
  (select body from public.scripture_prompts where reference = 'Isaiah 40:31'),
  'Those who wait for Yahweh will renew their strength.',
  'a group admin cannot edit or delete another group''s scripture'
);

-- ------------------------------------------------- members are not admins ---

select tests.login('00000000-0000-4000-8000-0000000000b1');
select throws_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, published_by, rights_attested_by, status, is_published)
     values ('Psalm 1:1', 'x', 'WEBBE', (select id from anne), auth.uid(), auth.uid(), 'approved', true) $$,
  '42501', null,
  'a plain member cannot publish to their group'
);
select throws_ok(
  $$ insert into public.scripture_prompts
       (reference, body, translation, group_id, submitted_by, status, is_published, contributor_note)
     values ('Psalm 1:1', '', '', (select id from anne), auth.uid(), 'pending', false, 'please') $$,
  '42501', null,
  'the member submissions path cannot be aimed at a group'
);

-- --------------------------------------------------- attestation, honestly ---

select tests.login('00000000-0000-4000-8000-0000000000a1');
update public.church_group_members set role = 'admin'
 where group_id = (select id from anne)
   and user_id = '00000000-0000-4000-8000-0000000000b1';

select tests.login('00000000-0000-4000-8000-0000000000b1');
update public.scripture_prompts set is_published = false where reference = 'Isaiah 40:31';
select tests.logout();
select is(
  (select rights_attested_by from public.scripture_prompts where reference = 'Isaiah 40:31'),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'unpublishing does not re-attribute who vouched for the text'
);

select tests.login('00000000-0000-4000-8000-0000000000b1');
select throws_ok(
  $$ update public.scripture_prompts set body = 'Rewritten.' where reference = 'Isaiah 40:31' $$,
  '42501', null,
  'changing the text without confirming the right to it is refused'
);
select lives_ok(
  $$ update public.scripture_prompts
        set body = 'Rewritten.', rights_attested_by = auth.uid(), is_published = true
      where reference = 'Isaiah 40:31' $$,
  'changing it while confirming is accepted'
);

select tests.login('00000000-0000-4000-8000-0000000000e1');
select throws_ok(
  $$ update public.scripture_prompts
        set translation = 'NLT', rights_attested_by = auth.uid()
      where reference = 'Isaiah 40:31' $$,
  '23514', null,
  'not even an app admin can turn a group''s verse into a licensed one'
);

-- ------------------------------------------------------------- leaving ---

select tests.login('00000000-0000-4000-8000-0000000000c1');
insert into public.church_group_members (group_id, user_id)
values ((select id from anne), '00000000-0000-4000-8000-0000000000c1');
select is(
  (select count(*)::int from public.walk_scripture_library()),
  3,
  'joining a group adds its scripture to the next walk'
);
delete from public.church_group_members
 where group_id = (select id from anne)
   and user_id = '00000000-0000-4000-8000-0000000000c1';
select is(
  (select count(*)::int from public.walk_scripture_library()),
  1,
  'leaving takes it away again'
);

-- Alice deletes her account. What she posted stays with the group; the record
-- of who vouched for it loses her name, and the deletion is not refused.
select tests.logout();
delete from auth.users where id = '00000000-0000-4000-8000-0000000000a1';
select is(
  (select count(*)::int from public.scripture_prompts
    where reference = 'Psalm 46:10' and rights_attested_by is null
      and rights_attested_at is not null),
  1,
  'an attesting admin''s account deletion keeps the verse and the date, not the name'
);

select * from finish();
rollback;
