-- The church column, while 1.0 and 1.1 share a database.
--
--   npx supabase test db
--
-- 1.0 reads and writes the old column; 1.1 reads and writes `church`. Each has
-- to see the other's edit, and every profile-shaped read has to carry both
-- JSON keys, until the deferred 1.2 migration retires the old one.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

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
grant execute on all functions in schema tests to authenticated;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000001a1', 'ana@test', '{"full_name":"Ana Villanueva"}'),
  ('00000000-0000-4000-8000-0000000001b1', 'ben@test', '{"full_name":"Ben Cruz"}'),
  ('00000000-0000-4000-8000-0000000001e1', 'eve@test', '{"full_name":"Eve Admin"}');
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000001e1';

select has_column('public', 'profiles', 'church', 'profiles.church exists');

-- 1.1 writes church; 1.0 still reads the old column and sees it.
select tests.login('00000000-0000-4000-8000-0000000001a1');
update public.profiles set church = 'San Roque, Antipolo'
 where id = '00000000-0000-4000-8000-0000000001a1';
select is(
  (select parish from public.profiles where id = '00000000-0000-4000-8000-0000000001a1'),
  'San Roque, Antipolo',
  'a 1.1 edit is visible to a 1.0 client'
);

-- 1.0 writes the old column; 1.1 reads church and sees it.
update public.profiles set parish = 'Our Lady of Peace'
 where id = '00000000-0000-4000-8000-0000000001a1';
select is(
  (select church from public.profiles where id = '00000000-0000-4000-8000-0000000001a1'),
  'Our Lady of Peace',
  'a 1.0 edit is visible to a 1.1 client'
);

update public.profiles set church = 'St Joseph', parish = 'stale'
 where id = '00000000-0000-4000-8000-0000000001a1';
select is(
  (select parish from public.profiles where id = '00000000-0000-4000-8000-0000000001a1'),
  'St Joseph',
  'if one write somehow carries both, church wins'
);

-- Every profile-shaped read carries both keys, equal.
select tests.login('00000000-0000-4000-8000-0000000001b1');
select is(
  (select (profile ->> 'church') || '|' || (profile ->> 'parish')
     from public.search_members('ana', auth.uid())),
  'St Joseph|St Joseph',
  'search results carry church and the 1.0 key, equal'
);
select is(
  (select count(*)::int from public.search_members('joseph', auth.uid())),
  1,
  'search matches on church'
);

-- An admin still may not rewrite a member's own words, under either name.
select tests.login('00000000-0000-4000-8000-0000000001e1');
select throws_ok(
  $$ update public.profiles set church = 'rewritten'
      where id = '00000000-0000-4000-8000-0000000001a1' $$,
  '42501', null,
  'an admin cannot edit another member''s church'
);
select throws_ok(
  $$ update public.profiles set parish = 'rewritten'
      where id = '00000000-0000-4000-8000-0000000001a1' $$,
  '42501', null,
  'nor through the old column'
);
select is(
  (select church from public.admin_members('joseph')),
  'St Joseph',
  'the console reads church, and searches it'
);

select * from finish();
rollback;
