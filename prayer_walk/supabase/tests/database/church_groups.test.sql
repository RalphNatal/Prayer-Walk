-- Church groups: membership, roles and visibility, asserted against the real
-- policies rather than the app's idea of them.
--
--   npx supabase test db
--
-- Every assertion below is made as a signed-in member (`authenticated`, with
-- their id in the JWT claims), the way PostgREST runs a request. The UI hiding
-- a button is not the test; the database refusing the write is.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(38);

-- ------------------------------------------------------------- harness ---

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
  ('00000000-0000-4000-8000-00000000000a', 'alice@test'),  -- founds St Anne
  ('00000000-0000-4000-8000-00000000000b', 'bob@test'),    -- joins St Anne
  ('00000000-0000-4000-8000-00000000000c', 'carol@test'),  -- in nothing
  ('00000000-0000-4000-8000-00000000000d', 'dave@test'),   -- founds a hidden group
  ('00000000-0000-4000-8000-00000000000e', 'erin@test'),   -- app admin
  ('00000000-0000-4000-8000-00000000000f', 'fay@test');    -- suspended

update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-00000000000e';
update public.profiles set status = 'suspended'
 where id = '00000000-0000-4000-8000-00000000000f';

-- ------------------------------------------------------------ founding ---

select tests.login('00000000-0000-4000-8000-00000000000a');
create temp table st_anne as
  select * from public.create_church_group('St Anne', 'Antipolo', 'Morning walkers.', true, 'open');
grant select on st_anne to authenticated;

select is(
  (select role from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000a'),
  'admin',
  'the founder is the group''s first admin, written by the server'
);

select is((select slug from st_anne), 'st-anne', 'the slug is generated from the name');

select isnt(
  (select code from public.church_group_invites where group_id = (select id from st_anne)),
  null,
  'the founder can read the invite code the server minted'
);

select tests.login('00000000-0000-4000-8000-00000000000d');
create temp table hidden as
  select * from public.create_church_group('Quiet Chapel', '', '', false, 'request');
grant select on hidden to authenticated;

-- --------------------------------------------------------------- joining ---

select tests.login('00000000-0000-4000-8000-00000000000b');

select throws_ok(
  $$ insert into public.church_group_members (group_id, user_id, role, status)
     values ((select id from st_anne), '00000000-0000-4000-8000-00000000000b', 'admin', 'active') $$,
  '42501', null,
  'a member cannot insert themselves as a group admin'
);

select lives_ok(
  $$ insert into public.church_group_members (group_id, user_id, role, status)
     values ((select id from st_anne), '00000000-0000-4000-8000-00000000000b', 'member', 'active') $$,
  'a member can join an open, discoverable group as themselves'
);

select is(
  (select joined_at > now() - interval '1 minute' from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000b'),
  true,
  'joined_at is the server''s clock, not the client''s'
);

select is(
  (select code from public.church_group_invites where group_id = (select id from st_anne)),
  null,
  'a plain member cannot read the invite code'
);

-- ---------------------------------------------------- self-promotion, no ---

update public.church_group_members
   set role = 'admin'
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000b';

select tests.logout();
select is(
  (select role from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000b'),
  'member',
  'a member cannot promote themselves to group admin'
);

-- ------------------------------------------------------ hidden groups ---

select tests.login('00000000-0000-4000-8000-00000000000c');

select is(
  (select count(*)::int from public.church_groups where id = (select id from hidden)),
  0,
  'a non-member cannot see a non-discoverable group'
);

select is(
  (select count(*)::int from public.search_church_groups('quiet')),
  0,
  'a hidden group is not in search'
);

select throws_ok(
  $$ insert into public.church_group_members (group_id, user_id)
     values ((select id from hidden), '00000000-0000-4000-8000-00000000000c') $$,
  '42501', null,
  'a hidden group cannot be joined without its code'
);

select throws_ok(
  $$ insert into public.church_group_members (group_id, user_id, status)
     values ((select id from st_anne), '00000000-0000-4000-8000-00000000000c', 'pending') $$,
  '42501', null,
  'the client cannot choose its own status — the group''s policy does'
);

select tests.logout();
create temp table hidden_code as
  select code from public.church_group_invites where group_id = (select id from hidden);
grant select on hidden_code to authenticated;

select tests.login('00000000-0000-4000-8000-00000000000c');
select is(
  (select my_status from public.join_church_group_with_code((select code from hidden_code))),
  'pending',
  'the code admits you to a request-only group as pending, not active'
);

select is(
  (select count(*)::int from public.church_groups where id = (select id from hidden)),
  1,
  'someone waiting can see the group they asked to join'
);

select is(
  (select count(*)::int from public.church_group_members where group_id = (select id from hidden)),
  1,
  'someone waiting sees only their own row, not the roster'
);

-- ------------------------------------------------- one group, not another ---

select tests.login('00000000-0000-4000-8000-00000000000d');

update public.church_groups set description = 'taken over'
 where id = (select id from st_anne);
delete from public.church_group_members
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000b';

select tests.logout();
select is(
  (select description from public.church_groups where id = (select id from st_anne)),
  'Morning walkers.',
  'a group admin cannot edit another group'
);
select is(
  (select count(*)::int from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000b'),
  1,
  'a group admin cannot remove members of another group'
);

select tests.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select count(*)::int from public.church_group_members where group_id = (select id from st_anne)),
  0,
  'a group admin cannot read another group''s roster'
);
select is(
  public.is_admin(),
  false,
  'a group admin is not an app admin'
);
select throws_ok(
  $$ select * from public.admin_members() $$,
  '42501', null,
  'a group admin cannot reach the admin console'
);

-- ---------------------------------------------------- approving, roles ---

select tests.login('00000000-0000-4000-8000-00000000000d');
update public.church_group_members set status = 'active'
 where group_id = (select id from hidden)
   and user_id = '00000000-0000-4000-8000-00000000000c';
select is(
  (select status from public.church_group_members
    where group_id = (select id from hidden)
      and user_id = '00000000-0000-4000-8000-00000000000c'),
  'active',
  'a group admin approves a pending request in their own group'
);

select throws_ok(
  $$ update public.church_group_members set role = 'member'
      where group_id = (select id from hidden)
        and user_id = '00000000-0000-4000-8000-00000000000d' $$,
  '42501', null,
  'a group admin cannot demote themselves'
);

select tests.login('00000000-0000-4000-8000-00000000000a');
update public.church_group_members set status = 'banned'
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000b';

select tests.login('00000000-0000-4000-8000-00000000000b');
delete from public.church_group_members
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000b';
select is(
  (select status from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000b'),
  'banned',
  'a banned member cannot leave and rejoin to shed the ban'
);

select tests.logout();
create temp table anne_code as
  select code from public.church_group_invites where group_id = (select id from st_anne);
grant select on anne_code to authenticated;
select tests.login('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$ select * from public.join_church_group_with_code((select code from anne_code)) $$,
  '42501', null,
  'a banned member cannot rejoin with the invite code either'
);

-- --------------------------------------------------- profiles, counted ---

select tests.login('00000000-0000-4000-8000-00000000000a');
update public.church_group_members set status = 'active'
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000b';

select tests.login('00000000-0000-4000-8000-00000000000c');
select is(
  (select member_count from public.search_church_groups('anne')),
  2,
  'a non-member sees how many people are in a discoverable group'
);
select is(
  (select count(*)::int from public.church_group_members where group_id = (select id from st_anne)),
  0,
  'a non-member does not see who they are'
);
select is(
  (select count(*)::int from public.church_groups_for_member('00000000-0000-4000-8000-00000000000b')),
  1,
  'a member''s discoverable groups are listed on their profile'
);

select tests.login('00000000-0000-4000-8000-00000000000a');
select is(
  (select count(*)::int from public.church_groups_for_member('00000000-0000-4000-8000-00000000000c')),
  0,
  'a hidden group is not listed on a profile to someone outside it'
);
select tests.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select count(*)::int from public.church_groups_for_member('00000000-0000-4000-8000-00000000000c')),
  1,
  'but it is to a fellow member'
);

-- ------------------------------------------------------------- oversight ---

select tests.login('00000000-0000-4000-8000-00000000000e');
select is(
  (select count(*)::int from public.church_groups where id = (select id from hidden)),
  1,
  'an app admin can read a hidden group, to act on a report about it'
);

select tests.login('00000000-0000-4000-8000-00000000000f');
select throws_ok(
  $$ select * from public.create_church_group('Fay''s', '', '', true, 'open') $$,
  '42501', null,
  'a suspended member cannot start a group'
);

-- ------------------------------------------------------------ succession ---

select tests.login('00000000-0000-4000-8000-00000000000a');
delete from public.church_group_members
 where group_id = (select id from st_anne)
   and user_id = '00000000-0000-4000-8000-00000000000a';

select tests.logout();
select is(
  (select role from public.church_group_members
    where group_id = (select id from st_anne)
      and user_id = '00000000-0000-4000-8000-00000000000b'),
  'admin',
  'when the last admin leaves, the longest-tenured member is promoted'
);

-- Bob deletes his account. He was the last admin and the last member.
delete from auth.users where id = '00000000-0000-4000-8000-00000000000b';
select isnt(
  (select deleted_at from public.church_groups where id = (select id from st_anne)),
  null,
  'a group left with nobody in it is soft-deleted'
);

select tests.login('00000000-0000-4000-8000-00000000000c');
select is(
  (select count(*)::int from public.church_groups where id = (select id from st_anne)),
  0,
  'a soft-deleted group disappears for members'
);

-- Dave, admin of the hidden group, deletes his account; Carol is still in it.
select tests.logout();
delete from auth.users where id = '00000000-0000-4000-8000-00000000000d';
select is(
  (select role from public.church_group_members
    where group_id = (select id from hidden)
      and user_id = '00000000-0000-4000-8000-00000000000c'),
  'admin',
  'account deletion by the last admin hands the group on rather than orphaning it'
);
select is(
  (select created_by from public.church_groups where id = (select id from hidden)),
  null,
  'a founder''s account deletion clears the founder, and is not refused for it'
);

-- Alice is in neither group now. Carol really is the hidden group's admin;
-- the function must not say so to her.
select tests.login('00000000-0000-4000-8000-00000000000a');
select is(
  (select is_group_admin((select id from hidden), '00000000-0000-4000-8000-00000000000c')),
  false,
  'is_group_admin answers nothing about another member to an outsider'
);

select tests.login('00000000-0000-4000-8000-00000000000c');
select is(
  public.pw_is_group_admin_folder('not-a-uuid/x.jpg'),
  false,
  'a malformed storage folder is a refusal, not a cast error'
);

select * from finish();
rollback;
