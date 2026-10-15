-- Owner member view. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

do $$
declare
  a uuid := gen_random_uuid();  -- anonymous, bought a pack
  b uuid := gen_random_uuid();  -- signed in with Apple, Pro yearly
  c uuid := gen_random_uuid();  -- Pro monthly that expired
  s jsonb;
  s0 jsonb := public.ops_members_summary();
begin
  assert not has_function_privilege('anon', 'public.ops_members_summary()', 'execute'), 'owner only';
  assert not has_function_privilege('authenticated', 'public.ops_members(int)', 'execute'), 'owner only';
  assert has_function_privilege('service_role', 'public.ops_members(int)', 'execute'), 'the SQL editor runs it';

  insert into auth.users (id, is_anonymous, last_sign_in_at) values (a, true, now()), (b, false, now()), (c, true, null);
  insert into auth.identities (user_id, provider) values (b, 'apple');
  insert into public.credit_wallets (user_id, daily, subscription, purchased) values (a, 2, 0, 30), (b, 0, 80, 0);
  insert into public.credit_ledger (user_id, kind, purchased) values (a, 'grant_pack', 30);
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('t-b', b, 'app.glowlit.pro.yearly', now() + interval '300 days'),
           ('t-c', c, 'app.glowlit.pro.monthly', now() - interval '2 days');

  s := public.ops_members_summary();
  assert ((s #>> '{members,total}')::int - (s0 #>> '{members,total}')::int) = 3, 'three members';
  assert ((s #>> '{members,anonymous}')::int - (s0 #>> '{members,anonymous}')::int) = 2, 'two anonymous';
  assert ((s #>> '{members,signed_in_with_apple}')::int - (s0 #>> '{members,signed_in_with_apple}')::int) = 1, 'one Apple account';
  assert ((s #>> '{pro,active_members}')::int - (s0 #>> '{pro,active_members}')::int) = 1, 'only the unexpired subscription counts';
  assert ((s #>> '{pro,yearly}')::int - (s0 #>> '{pro,yearly}')::int) = 1 and ((s #>> '{pro,monthly}')::int - (s0 #>> '{pro,monthly}')::int) = 0, 'by plan';
  assert ((s #>> '{pro,ever_subscribed}')::int - (s0 #>> '{pro,ever_subscribed}')::int) = 2, 'both subscribed once';
  assert ((s #>> '{credit_packs,buyers}')::int - (s0 #>> '{credit_packs,buyers}')::int) = 1 and ((s #>> '{credit_packs,credits_sold}')::int - (s0 #>> '{credit_packs,credits_sold}')::int) = 30, 'packs';

  assert (select count(*) from public.ops_members(1000) where user_id in (a, b, c)) = 3, 'lists everyone';
  assert (select apple from public.ops_members(1000) where user_id = b), 'Apple flag';
  assert (select pro_product from public.ops_members(1000) where user_id = b) = 'app.glowlit.pro.yearly', 'Pro product';
  assert (select credits from public.ops_members(1000) where user_id = a) = 32, 'balance adds the buckets';
  assert (select packs_bought from public.ops_members(1000) where user_id = a) = 1, 'packs per member';
  assert (select count(*) from public.ops_members(1)) = 1, 'limit applies';

  delete from auth.users where id in (a, b, c);
end $$;

select 'all ops members tests passed' as result;
