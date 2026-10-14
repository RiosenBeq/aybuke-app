-- Behavioural tests for the credit ledger. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure; psql stops on the first error.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-000000000005'),
  ('00000000-0000-0000-0000-000000000006');

-- 1. The policy: the numbers, a pinned search_path, service role only.
do $$
declare
  pol record;
begin
  select * into pol from public.credit_policy();
  assert pol.free_daily = 2 and pol.pro_monthly = 80 and pol.pro_rollover_cap = 160, format('policy %s', row_to_json(pol));
  assert pol.trial_credits = 20 and pol.free_retries_daily = 3, format('policy %s', row_to_json(pol));
  assert (select proconfig::text from pg_proc where oid = 'public.credit_policy()'::regprocedure) like '%search_path=%',
    'credit_policy() pins its search_path (Security Advisor)';
  assert not has_function_privilege('anon', 'public.credit_policy()', 'execute'), 'anon cannot read the limits';
  assert not has_function_privilege('authenticated', 'public.credit_policy()', 'execute'), 'nor can users';
end $$;

-- 2. Free credits belong to the verified App Store install, not to the account.
do $$
declare
  a uuid := '00000000-0000-0000-0000-000000000001';
  b uuid := '00000000-0000-0000-0000-000000000002';
  state jsonb;
  admitted jsonb;
begin
  state := public.wallet_state(a);
  assert (state->>'credits_remaining')::int = 0 and state->>'free_credits' = 'unverified',
    format('no AppTransaction, no free credits: %s', state);
  assert (state->'policy'->>'free_daily')::int = 2 and (state->'policy'->>'trial_credits')::int = 20, 'policy numbers ride along';

  state := public.wallet_state(a, 'atid-shared', 'verified', 'Sandbox');
  assert (state->>'credits_remaining')::int = 2 and state->>'free_credits' = 'ok', format('a verified install: %s', state);

  admitted := public.admit_job(a, 'magic_edit', 'test', p_input_images => 1,
                               p_app_transaction_id => 'atid-shared', p_install_status => 'verified');
  assert (admitted->>'ok')::boolean and (admitted->>'credits_remaining')::int = 1, format('first job: %s', admitted);
  assert (select free from public.jobs where id = (admitted->>'job_id')::uuid), 'paid with free credits';
  assert (select install_key from public.jobs where id = (admitted->>'job_id')::uuid) is not null, 'the job names its install';

  -- A second anonymous account made by the same Apple Account shares the allowance.
  state := public.wallet_state(b, 'atid-shared', 'verified', 'Sandbox');
  assert (state->>'credits_remaining')::int = 1, format('shared allowance: %s', state);
  admitted := public.admit_job(b, 'text_to_image', 'test', p_app_transaction_id => 'atid-shared', p_install_status => 'verified');
  assert (admitted->>'ok')::boolean and (admitted->>'credits_remaining')::int = 0, format('second account: %s', admitted);
  admitted := public.admit_job(a, 'text_to_image', 'test', p_app_transaction_id => 'atid-shared', p_install_status => 'verified');
  assert admitted->>'code' = 'insufficient_credits' and (admitted->>'status')::int = 402, format('used up: %s', admitted);
  assert (select count(*) from public.jobs where user_id = a) = 1, 'a refused job is never booked';

  -- Another Apple Account has its own.
  state := public.wallet_state(b, 'atid-other', 'verified', 'Production');
  assert (state->>'credits_remaining')::int = 2, 'another install has its own allowance';

  -- The raw id is never stored; the key is a salted hash.
  assert not exists (select 1 from private.app_installs where key like '%atid%'), 'no raw appTransactionId';
  assert (select length(key) from private.app_installs limit 1) = 64, 'SHA-256 hex';
end $$;

-- 3. Without a valid AppTransaction there are no free credits, but packs work.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000005';
  admitted jsonb;
begin
  admitted := public.admit_job(u, 'magic_edit', 'test');
  assert admitted->>'code' = 'app_transaction_required' and (admitted->>'status')::int = 428, format('missing: %s', admitted);
  admitted := public.admit_job(u, 'magic_edit', 'test', p_install_status => 'invalid');
  assert admitted->>'code' = 'app_transaction_invalid', format('invalid: %s', admitted);
  assert public.grant_pack(u, 30, 'apple-tx-1') = 30, 'pack adds 30';
  assert public.grant_pack(u, 30, 'apple-tx-1') = 30, 'redelivery must not double-grant';
  assert public.grant_pack('00000000-0000-0000-0000-000000000006', 30, 'apple-tx-1') = 0, 'another user cannot replay it';
  admitted := public.admit_job(u, 'magic_edit', 'test', p_install_status => 'invalid');
  assert (admitted->>'ok')::boolean and (admitted->>'credits_remaining')::int = 29, format('paid credits still work: %s', admitted);
  assert not (select free from public.jobs where id = (admitted->>'job_id')::uuid), 'a paid job';
  -- A pack bought with a verified install reports today's free credits too.
  assert public.grant_pack(u, 100, 'apple-tx-2', 'atid-five', 'verified', 'Sandbox') = 131, 'pack plus free credits';
end $$;

-- 4. Refunds go back exactly where they came from, once; free credits refill daily and never pile up.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000005';
  j uuid := gen_random_uuid();
  v_key text := private.keyed_hash('app_transaction', 'atid-five');
  hold public.credit_ledger;
begin
  -- 2 free + 129 purchased: a 4-image job spends the free ones first.
  assert public.reserve_credits(u, 4, j, v_key) = 127, 'reserve returns the balance';
  select * into hold from public.credit_ledger where job_id = j and kind = 'hold';
  assert hold.daily = -2 and hold.subscription = 0 and hold.purchased = -2 and hold.install_key = v_key, format('bad split %s', row_to_json(hold));
  assert public.release_credits(j) = 131, 'release restores both buckets';
  assert public.release_credits(j) = 131, 'a second release is a no-op';
  assert (select count(*) from public.credit_ledger where job_id = j and kind = 'release') = 1;

  update private.app_installs set daily = 1, daily_period = (now() at time zone 'utc')::date - 3 where key = v_key;
  assert (public.wallet_state(u, 'atid-five', 'verified', 'Sandbox')->>'credits_remaining')::int = 131,
    'a new day starts over at 2, never more';
  -- A refund after the refill is capped at the allowance.
  j := gen_random_uuid();
  perform public.reserve_credits(u, 1, j, v_key);
  update private.app_installs set daily = 2 where key = v_key;
  perform public.release_credits(j);
  assert (select daily from private.app_installs where key = v_key) = 2, 'refunds never exceed the daily allowance';
end $$;

-- 5. Pro: the subscription's monthly credits, spent before packs, refunded exactly.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
  j uuid := gen_random_uuid();
  state jsonb;
  hold public.credit_ledger;
begin
  perform public.grant_pack(u, 30, 'apple-tx-pro-1');
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at)
    values ('otx-1', u, 'app.glowlit.pro.monthly', now() + interval '1 month');
  state := public.wallet_state(u, 'atid-shared', 'verified', 'Sandbox');
  assert (state->>'credits_remaining')::int = 110 and (state->>'is_pro')::boolean and state->>'free_credits' = 'pro',
    format('80 a month plus the pack, no free daily credits on Pro: %s', state);
  assert (select credits from public.entitlements where original_transaction_id = 'otx-1') = 80;
  assert public.reserve_credits(u, 85, j, private.keyed_hash('app_transaction', 'atid-shared')) = 25;
  select * into hold from public.credit_ledger where job_id = j and kind = 'hold';
  assert hold.daily = 0 and hold.subscription = -80 and hold.purchased = -5 and hold.entitlement_id = 'otx-1',
    format('bad split %s', row_to_json(hold));
  assert public.release_credits(j) = 110;
end $$;

-- 6. Rollover is capped at 160; when Pro ends, subscription credits end and packs stay.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
begin
  update public.entitlements set credits_period_start = now() - interval '1 month 2 days' where original_transaction_id = 'otx-1';
  perform public.wallet_state(u);
  assert (select credits from public.entitlements where original_transaction_id = 'otx-1') = 160, 'one month of rollover';
  update public.entitlements set credits_period_start = now() - interval '3 months 1 day' where original_transaction_id = 'otx-1';
  perform public.wallet_state(u);
  assert (select credits from public.entitlements where original_transaction_id = 'otx-1') = 160, 'capped at 160';
  update public.entitlements set expires_at = now() - interval '1 minute' where original_transaction_id = 'otx-1';
  assert (public.wallet_state(u)->>'credits_remaining')::int = 30, 'only the pack is left';
  assert (select credits from public.entitlements where original_transaction_id = 'otx-1') = 0, 'subscription credits expire';
end $$;

-- 7. The yearly plan's free trial: 20 credits once, the full month from the first paid period.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000006';
  e public.entitlements;
begin
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at, is_trial)
    values ('otx-trial', u, 'app.glowlit.pro.yearly', now() + interval '7 days', true);
  assert (public.wallet_state(u)->>'credits_remaining')::int = 20, 'trial week: 20';
  perform public.wallet_state(u);
  assert (select credits from public.entitlements where original_transaction_id = 'otx-trial') = 20, 'granted once';
  -- The trial converts: Apple's renewal is no longer a free trial.
  update public.entitlements set is_trial = false, expires_at = now() + interval '1 year',
         credits = 5 where original_transaction_id = 'otx-trial';
  select * into e from public.entitlements where original_transaction_id = 'otx-trial';
  assert e.trial_granted and e.credits_trial, 'still in the trial period until the paid one is seen';
  assert (public.wallet_state(u)->>'credits_remaining')::int = 85, 'the first paid period brings the full 80';
  select * into e from public.entitlements where original_transaction_id = 'otx-trial';
  assert not e.credits_trial and e.credits_period_start > now() - interval '1 minute';
  -- A trial flag seen again later never grants trial credits twice.
  update public.entitlements set is_trial = true where original_transaction_id = 'otx-trial';
  assert (public.wallet_state(u)->>'credits_remaining')::int = 85, 'no second trial grant';
  update public.entitlements set is_trial = false where original_transaction_id = 'otx-trial';
end $$;

-- 8. Moving a subscription to another anonymous account moves its credits; it never mints a new month.
do $$
declare
  a uuid := '00000000-0000-0000-0000-000000000006';
  b uuid := '00000000-0000-0000-0000-000000000002';
begin
  update public.entitlements set user_id = b where original_transaction_id = 'otx-trial';
  assert (public.wallet_state(b)->>'credits_remaining')::int = 85, 'the credits come along';
  update public.entitlements set user_id = a where original_transaction_id = 'otx-trial';
  assert (public.wallet_state(a)->>'credits_remaining')::int = 85, 'and back, still 85';
  assert (public.wallet_state(b)->>'credits_remaining')::int = 0, 'nothing left behind';
end $$;

-- 9. The sweeper fails stale jobs and refunds them to the install.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000002';
  v_key text := private.keyed_hash('app_transaction', 'atid-other');
  j uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, install_key, created_at)
    values (j, u, 'enhance', 'test', 1, v_key, now() - interval '20 minutes');
  perform public.reserve_credits(u, 1, j, v_key);
  assert (select daily from private.app_installs where key = v_key) = 1;
  perform public.sweep_jobs();
  assert (select status from public.jobs where id = j) = 'failed';
  assert (select daily from private.app_installs where key = v_key) = 2, 'stale job must be refunded';
end $$;

-- 10. RLS: users see only their own rows and can call none of the functions.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$
declare
  denied boolean := false;
begin
  assert (select count(*) from public.credit_wallets) = 1, 'should only see own wallet';
  assert (select count(*) from public.jobs where user_id = '00000000-0000-0000-0000-000000000001') = 0, 'must not see other users'' jobs';
  begin
    perform public.grant_pack('00000000-0000-0000-0000-000000000002', 1000, 'forged');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'clients must not be able to grant credits';
  denied := false;
  begin
    perform 1 from private.app_installs;
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'the private schema is closed to clients';
end $$;
reset role;

do $$
begin
  assert not has_function_privilege('authenticated', 'public.reserve_credits(uuid, int, uuid, text, boolean)', 'execute');
  assert not has_function_privilege('anon', 'public.wallet_state(uuid, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.job_balance(uuid, uuid)', 'execute');
  assert not has_schema_privilege('anon', 'private', 'usage') and not has_schema_privilege('authenticated', 'private', 'usage')
     and not has_schema_privilege('service_role', 'private', 'usage'), 'no API role can use the private schema';
end $$;

-- 11. A subscription only moves forward: an older signed transaction never replaces the stored one
-- with an earlier expiry, and a revocation can be undone only by a later purchase.
do $$
declare
  a uuid := '00000000-0000-0000-0000-000000000001';
  b uuid := '00000000-0000-0000-0000-000000000002';
  e public.entitlements;
begin
  assert public.record_entitlement(a, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '1 month', false, 'Production', false),
    'a new subscription is stored';
  assert not public.record_entitlement(b, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '1 week', false, 'Production', false),
    'an older transaction never replaces a newer one';
  select * into e from public.entitlements where original_transaction_id = 'otx-order';
  assert e.user_id = a and e.expires_at > now() + interval '3 weeks', format('the newer row is untouched: %s', row_to_json(e));
  assert public.record_entitlement(a, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '2 months', false, 'Production', false),
    'a renewal replaces it';
  assert public.record_entitlement(b, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '2 months', true, 'Production', false),
    'a revocation always lands, even with the same expiry';
  assert not public.record_entitlement(a, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '2 months', false, 'Production', false),
    'the transaction from before the refund cannot undo it';
  select * into e from public.entitlements where original_transaction_id = 'otx-order';
  assert e.revoked and e.user_id = b, format('still revoked: %s', row_to_json(e));
  assert public.record_entitlement(a, 'otx-order', 'app.glowlit.pro.monthly', now() + interval '3 months', false, 'Production', false),
    'a later purchase is stored';
end $$;

-- 12. Row level security is on for every private table, and no policy opens one (the definer functions own them).
do $$
begin
  assert exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'private' and c.relkind = 'r'), 'the private schema has tables';
  assert not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                      where n.nspname = 'private' and c.relkind = 'r' and not c.relrowsecurity),
    'every private table has row level security on';
  assert not exists (select 1 from pg_policies where schemaname = 'private'), 'no policy on the private schema';
end $$;

-- 13. The balance with the client address (20261025000001): service role only, and
-- the older call without it gives the same answer.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000005';
begin
  assert not has_function_privilege('anon', 'public.wallet_state(uuid, text, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.wallet_state(uuid, text, text, text, text)', 'execute');
  assert has_function_privilege('service_role', 'public.wallet_state(uuid, text, text, text, text)', 'execute');
  assert has_function_privilege('service_role', 'public.wallet_state(uuid, text, text, text)', 'execute');
  perform public.wallet_state(u, 'atid-five', 'verified', 'Sandbox');
  assert public.wallet_state(u, 'atid-five', 'verified', 'Sandbox')
       = public.wallet_state(u, 'atid-five', 'verified', 'Sandbox', '198.51.100.20'),
    'the address changes nothing without a cool-down or block on it';
end $$;

select 'all credit ledger tests passed' as result;
