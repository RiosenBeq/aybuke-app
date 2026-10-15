-- Sign in with Apple's tables are out of the clients' reach. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

-- What Supabase's default privileges give every new public table (test-db.sh
-- grants select too), then the migration again: it must take all of it away.
grant all on table public.apple_accounts, public.merged_users to anon, authenticated;
\ir ../migrations/20261027000000_account_tables_private.sql

do $$
declare
  t text;
  r text;
  p text;
begin
  foreach t in array array['public.apple_accounts', 'public.merged_users'] loop
    foreach r in array array['anon', 'authenticated'] loop
      foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        assert not has_table_privilege(r, t, p), format('%s has %s on %s', r, p, t);
      end loop;
    end loop;
    assert (select relrowsecurity from pg_class where oid = t::regclass), format('RLS is on for %s', t);
    assert not exists (select 1 from pg_policies where schemaname || '.' || tablename = t), format('%s has no policies', t);
  end loop;
end $$;

select 'all account table tests passed' as result;
