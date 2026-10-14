-- Behavioural tests for rewarded ads. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure; psql stops on the first error.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000b2'),
  ('00000000-0000-0000-0000-0000000000b3');

-- 1. Tokens only for free members who are out of credits.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  reason text;
begin
  perform public.refresh_wallet(u, false);
  begin
    perform public.issue_ad_reward_token(u, false);
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_HAS_CREDITS%', format('a member with credits gets no token, got %s', reason);

  reason := null;
  begin
    perform public.issue_ad_reward_token(u, true);
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NOT_ELIGIBLE%', 'Pro never gets ads';

  update public.credit_wallets set daily = 0 where user_id = u;
  assert (select remaining_today from public.issue_ad_reward_token(u, false)) = 2, 'first token leaves 2 for today';
end $$;

-- 2. A verified callback grants one credit through the ledger, exactly once.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  token uuid;
  r record;
begin
  select k.id into token from public.ad_reward_tokens k where k.user_id = u;
  assert (select outcome from public.ad_reward_status(u, token)) = 'pending', 'pending until AdMob calls back';

  select * into r from public.redeem_ad_reward('tx-ad-1', token, '1406702504', 1, 'credit');
  assert r.outcome = 'granted' and r.credits_remaining = 1, format('expected a granted credit, got %s', row_to_json(r));
  assert (select daily from public.credit_wallets where user_id = u) = 1, 'the credit lands in the daily bucket';
  assert (select count(*) from public.credit_ledger where kind = 'ad_reward' and source_ref = 'admob:tx-ad-1' and daily = 1) = 1,
    'the grant is in the ledger';
  assert (select outcome from public.ad_reward_status(u, token)) = 'granted', 'the app sees the grant';

  -- AdMob retries the same transaction: nothing more.
  select * into r from public.redeem_ad_reward('tx-ad-1', token, '1406702504', 1, 'credit');
  assert r.outcome = 'duplicate', 'a repeated callback is a duplicate';
  -- Another transaction can't reuse the token.
  select * into r from public.redeem_ad_reward('tx-ad-2', token, '1406702504', 1, 'credit');
  assert r.outcome = 'used', 'a token pays once';
  assert (select daily from public.credit_wallets where user_id = u) = 1, 'still exactly one credit';
  assert (select count(*) from public.credit_ledger where kind = 'ad_reward' and user_id = u) = 1;

  select * into r from public.redeem_ad_reward('tx-ad-3', gen_random_uuid(), '1406702504', 1, 'credit');
  assert r.outcome = 'unknown', 'an unknown token pays nothing';
end $$;

-- 3. The spent ad credit is refunded like any other when a job fails.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  j uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j, u, 'magic_edit', 'test', 1);
  assert public.reserve_credits(u, false, 1, j) = 0, 'the ad credit pays for a job';
  assert public.release_credits(j) = 1, 'and comes back on failure';
end $$;

-- 4. At most three a day: live tokens count, so a fourth ad is never shown.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
  first uuid;
  second uuid;
  reason text;
begin
  perform public.refresh_wallet(u, false);
  update public.credit_wallets set daily = 0 where user_id = u;
  select reward_token into first from public.issue_ad_reward_token(u, false);
  select reward_token into second from public.issue_ad_reward_token(u, false);
  assert (select remaining_today from public.issue_ad_reward_token(u, false)) = 0, 'the third token is the last';
  begin
    perform public.issue_ad_reward_token(u, false);
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_DAILY_CAP%', 'no fourth token today';

  -- Closing an ad early gives its place back.
  assert public.release_ad_reward_token(u, second), 'her unused token is released';
  assert not public.release_ad_reward_token('00000000-0000-0000-0000-0000000000b1', first), 'nobody else can release it';
  assert (select remaining_today from public.ad_reward_status(u, first)) = 1, 'one place back';
end $$;

-- 5. The cap holds at grant time too, and expired tokens pay nothing.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b3';
  late uuid;
  extra uuid;
  r record;
begin
  perform public.refresh_wallet(u, false);
  update public.credit_wallets set daily = 0 where user_id = u;
  select reward_token into late from public.issue_ad_reward_token(u, false);
  update public.ad_reward_tokens set expires_at = now() - interval '1 minute' where id = late;
  select * into r from public.redeem_ad_reward('tx-late', late, '1406702504', 1, 'credit');
  assert r.outcome = 'expired' and r.credits_remaining = 0, format('a late callback pays nothing, got %s', row_to_json(r));
  assert (select outcome from public.ad_reward_status(u, late)) = 'expired';

  -- Three rewards already paid today (written directly, as if from earlier tokens).
  insert into public.ad_rewards (transaction_id, user_id, token_id, ad_unit, credits, status, reward_day)
    select 'tx-paid-' || n, u, gen_random_uuid(), '1406702504', 1, 'granted', (now() at time zone 'utc')::date
      from generate_series(1, 3) n;
  insert into public.ad_reward_tokens (id, user_id, expires_at) values (gen_random_uuid(), u, now() + interval '10 minutes')
    returning id into extra;
  select * into r from public.redeem_ad_reward('tx-over', extra, '1406702504', 1, 'credit');
  assert r.outcome = 'capped' and r.credits_remaining = 0, format('a fourth reward is capped, got %s', row_to_json(r));
  assert (select count(*) from public.credit_ledger where kind = 'ad_reward' and user_id = u) = 0, 'nothing granted';
end $$;

-- 6. Housekeeping: old tokens and rewards go.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  update public.ad_reward_tokens set expires_at = now() - interval '2 days' where user_id = u;
  update public.ad_rewards set created_at = now() - interval '31 days' where user_id = '00000000-0000-0000-0000-0000000000b3';
  perform public.sweep_ad_rewards();
  assert (select count(*) from public.ad_reward_tokens where user_id = u) = 0, 'expired tokens are deleted after a day';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b3') = 0,
    'rewards are deleted after 30 days';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b1') = 1,
    'recent rewards stay';
end $$;

-- 7. Clients can't touch any of it.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
do $$
declare
  denied boolean := false;
  visible int := 0;
begin
  -- No grants (production) or no policies (this test database): nothing to see either way.
  begin
    select (select count(*) from public.ad_rewards) + (select count(*) from public.ad_reward_tokens) into visible;
  exception when insufficient_privilege then
    visible := 0;
  end;
  assert visible = 0, 'clients see no rewards or tokens, not even their own';
  begin
    perform public.redeem_ad_reward('forged', gen_random_uuid(), '1406702504', 1, 'credit');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'clients cannot grant ad credits';
  assert not has_table_privilege('authenticated', 'public.ad_rewards', 'insert'), 'clients cannot write rewards';
  assert not has_table_privilege('authenticated', 'public.ad_reward_tokens', 'insert'), 'clients cannot mint tokens';
  assert not has_function_privilege('authenticated', 'public.issue_ad_reward_token(uuid, boolean)', 'execute');
end $$;
reset role;

-- 8. Deleting the account removes its tokens and rewards.
do $$
begin
  delete from auth.users where id = '00000000-0000-0000-0000-0000000000b1';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b1') = 0;
  assert (select count(*) from public.ad_reward_tokens where user_id = '00000000-0000-0000-0000-0000000000b1') = 0;
end $$;

select 'all ad reward tests passed' as result;
