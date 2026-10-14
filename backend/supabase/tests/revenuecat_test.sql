-- RevenueCat deletions that wait for the key. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000c1');

-- 1. A queued deletion outlives the account it belongs to, and is queued once.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000c1';
begin
  insert into public.pending_revenuecat_deletions (user_id) values (u);
  insert into public.pending_revenuecat_deletions (user_id) values (u) on conflict (user_id) do nothing;
  delete from auth.users where id = u;
  assert (select count(*) from public.pending_revenuecat_deletions where user_id = u) = 1,
    'the deletion request survives the account';
  update public.pending_revenuecat_deletions
     set attempts = attempts + 1, last_attempt_at = now(), last_error = 'HTTP 500'
   where user_id = u;
  assert (select attempts from public.pending_revenuecat_deletions where user_id = u) = 1;
end $$;

-- 2. Clients can neither read nor write the queue.
do $$
begin
  assert not has_table_privilege('authenticated', 'public.pending_revenuecat_deletions', 'insert'), 'clients cannot queue';
  assert not has_table_privilege('authenticated', 'public.pending_revenuecat_deletions', 'delete'), 'clients cannot dequeue';
  assert not has_table_privilege('anon', 'public.pending_revenuecat_deletions', 'select'), 'anonymous callers cannot read it';
  assert (select relrowsecurity from pg_class where oid = 'public.pending_revenuecat_deletions'::regclass), 'RLS is on';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$
declare
  visible int;
begin
  -- The test harness grants SELECT on every table (like a project that exposes
  -- new tables); RLS without policies still shows nothing.
  begin
    select count(*) into visible from public.pending_revenuecat_deletions;
  exception when insufficient_privilege then
    visible := 0;
  end;
  assert visible = 0, 'no rows are visible to clients';
end $$;
reset role;

delete from public.pending_revenuecat_deletions where user_id = '00000000-0000-0000-0000-0000000000c1';

select 'all RevenueCat queue tests passed' as result;
