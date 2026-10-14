-- Keep-alive heartbeat. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

do $$
begin
  assert has_function_privilege('anon', 'public.keepalive()', 'execute'), 'the daily job calls it with the anon key';
  assert not has_function_privilege('authenticated', 'public.keepalive()', 'execute'), 'signed-in users have no reason to';
  assert not has_table_privilege('anon', 'public.ops_heartbeat', 'select'), 'nobody reads the heartbeat through the API';
  assert not has_table_privilege('anon', 'public.ops_heartbeat', 'update'), 'only the function stamps it';
  assert (select relrowsecurity from pg_class where oid = 'public.ops_heartbeat'::regclass), 'RLS is on';
  perform public.keepalive();
  perform public.keepalive();
  assert (select count(*) from public.ops_heartbeat) = 1, 'one row, stamped again';
end $$;

select 'all keep-alive tests passed' as result;
