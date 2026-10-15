-- RevenueCat deletions by hand (20261029000002): the digest's list of what is
-- waiting, and the owner marking customers deleted. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000a0c1';
  b uuid := '00000000-0000-0000-0000-00000000a0c2';
  c uuid := '00000000-0000-0000-0000-00000000a0c3';
  before int := (select count(*) from public.pending_revenuecat_deletions);
  p jsonb;
  r jsonb;
begin
  assert not has_function_privilege('anon', 'public.ops_revenuecat_pending(int)', 'execute'), 'owner only';
  assert not has_function_privilege('authenticated', 'public.ops_revenuecat_pending(int)', 'execute'), 'owner only';
  assert not has_function_privilege('authenticated', 'public.ops_mark_revenuecat_deleted(text[])', 'execute'),
    'owner only';
  assert has_function_privilege('service_role', 'public.ops_revenuecat_pending(int)', 'execute'), 'the digest reads it';
  assert has_function_privilege('service_role', 'public.ops_mark_revenuecat_deleted(text[])', 'execute'),
    'the owner runs it';

  insert into public.pending_revenuecat_deletions (user_id, created_at, attempts) values
    (a, now() - interval '3 days', 0),
    (b, now() - interval '2 days', 2),
    (c, now() - interval '1 day', 0);

  p := public.ops_revenuecat_pending(2);
  assert (p ->> 'count')::int = before + 3, format('every waiting customer counts: %s', p);
  assert (p ->> 'failed')::int >= 1, format('tried and failed: %s', p);
  assert jsonb_array_length(p -> 'app_user_ids') = 2, format('at most the limit: %s', p);
  if before = 0 then
    assert p -> 'app_user_ids' = jsonb_build_array(upper(a::text), upper(b::text)),
      format('oldest first, upper case as the app sends them: %s', p);
    assert (p ->> 'oldest')::timestamptz = now() - interval '3 days', format('the oldest: %s', p);
  end if;
  assert jsonb_array_length(public.ops_revenuecat_pending(0) -> 'app_user_ids') = 0, 'a limit of 0 lists none';
  assert jsonb_array_length(public.ops_revenuecat_pending(null) -> 'app_user_ids') = least(before + 3, 20),
    'null means the default';

  -- Upper case as shown in the digest, lower case, spaces: all the same id. A
  -- typo, a non-id or an id that isn't queued changes nothing.
  r := public.ops_mark_revenuecat_deleted(array[
    upper(a::text), ' ' || b::text || ' ', 'not-an-id', '00000000-0000-0000-0000-00000000ffff', null]);
  assert (r ->> 'removed')::int = 2 and (r ->> 'waiting')::int = before + 1, format('two removed: %s', r);
  assert not exists (select 1 from public.pending_revenuecat_deletions where user_id in (a, b)), 'gone';
  assert exists (select 1 from public.pending_revenuecat_deletions where user_id = c), 'the third still waits';

  r := public.ops_mark_revenuecat_deleted(array[upper(a::text)]);
  assert (r ->> 'removed')::int = 0, format('running it twice is safe: %s', r);
  r := public.ops_mark_revenuecat_deleted(null);
  assert (r ->> 'removed')::int = 0, format('nothing given, nothing removed: %s', r);

  r := public.ops_mark_revenuecat_deleted(array[c::text]);
  assert (r ->> 'removed')::int = 1 and (r ->> 'waiting')::int = before, format('back to where it was: %s', r);
end $$;

select 'all RevenueCat owner queue tests passed' as result;
