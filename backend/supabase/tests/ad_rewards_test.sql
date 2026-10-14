-- Behavioural tests for rewarded ads. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure; psql stops on the first error.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000b2'),
  ('00000000-0000-0000-0000-0000000000b3'),
  ('00000000-0000-0000-0000-0000000000b4');

-- 1. Tokens only for free members with a verified install who are out of credits.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  reason text;
begin
  assert (select daily_cap from public.ad_reward_policy()) = 2, 'two a day';
  begin
    perform public.issue_ad_reward_token(u, false);
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NO_INSTALL%', format('no verified install, no ad, got %s', reason);

  reason := null;
  begin
    perform public.issue_ad_reward_token(u, false, 'atid-ad-1', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_HAS_CREDITS%', format('a member with free credits gets no token, got %s', reason);

  reason := null;
  begin
    perform public.issue_ad_reward_token(u, true, 'atid-ad-1', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NOT_ELIGIBLE%', 'Pro never gets ads';

  -- (The refusals above rolled back with their exception blocks: record the install for real.)
  perform public.wallet_state(u, 'atid-ad-1', 'verified', 'Sandbox');
  update private.app_installs set daily = 0 where key = private.keyed_hash('app_transaction', 'atid-ad-1');
  assert (public.ad_reward_overview(u, false, 'atid-ad-1', 'verified', 'Sandbox')->>'eligible')::boolean,
    'out of credits: an ad is on offer';
  assert (select remaining_today from public.issue_ad_reward_token(u, false, 'atid-ad-1', 'verified', 'Sandbox')) = 1,
    'first token leaves 1 for today';
end $$;

-- 2. A verified callback grants one credit to the install, through the ledger, exactly once.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  k text := private.keyed_hash('app_transaction', 'atid-ad-1');
  token uuid;
  r record;
begin
  select t.id into token from public.ad_reward_tokens t where t.user_id = u;
  assert (select outcome from public.ad_reward_status(u, token)) = 'pending', 'pending until AdMob calls back';

  select * into r from public.redeem_ad_reward('tx-ad-1', token, '1406702504', 1, 'credit');
  assert r.outcome = 'granted' and r.credits_remaining = 1, format('expected a granted credit, got %s', row_to_json(r));
  assert (select daily from private.app_installs where key = k) = 1, 'the credit lands in the install''s daily bucket';
  assert (select count(*) from public.credit_ledger
           where kind = 'ad_reward' and source_ref = 'admob:tx-ad-1' and daily = 1 and install_key = k) = 1,
    'the grant is in the ledger';
  select * into r from public.ad_reward_status(u, token);
  assert r.outcome = 'granted' and r.credits_remaining = 1 and r.remaining_today = 1, format('the app sees it: %s', row_to_json(r));

  -- AdMob retries the same transaction: nothing more.
  select * into r from public.redeem_ad_reward('tx-ad-1', token, '1406702504', 1, 'credit');
  assert r.outcome = 'duplicate', 'a repeated callback is a duplicate';
  select * into r from public.redeem_ad_reward('tx-ad-2', token, '1406702504', 1, 'credit');
  assert r.outcome = 'used', 'a token pays once';
  assert (select daily from private.app_installs where key = k) = 1, 'still exactly one credit';
  select * into r from public.redeem_ad_reward('tx-ad-3', gen_random_uuid(), '1406702504', 1, 'credit');
  assert r.outcome = 'unknown', 'an unknown token pays nothing';
end $$;

-- 3. The spent ad credit is refunded like any other when a job fails, above the free allowance too.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b1';
  k text := private.keyed_hash('app_transaction', 'atid-ad-1');
  j uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, install_key) values (j, u, 'magic_edit', 'test', 1, k);
  assert public.reserve_credits(u, 1, j, k) = 0, 'the ad credit pays for a job';
  assert public.release_credits(j) = 1, 'and comes back on failure';
  assert private.daily_ceiling(k) = 3, 'today''s ceiling: 2 free credits and the ad''s';
end $$;

-- 4. At most two a day per user: live tokens count, so a third ad is never shown.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
  first uuid;
  second uuid;
  reason text;
begin
  perform public.wallet_state(u, 'atid-ad-2', 'verified', 'Sandbox');
  update private.app_installs set daily = 0 where key = private.keyed_hash('app_transaction', 'atid-ad-2');
  select reward_token into first from public.issue_ad_reward_token(u, false, 'atid-ad-2', 'verified', 'Sandbox');
  select reward_token, remaining_today into second, reason from public.issue_ad_reward_token(u, false, 'atid-ad-2', 'verified', 'Sandbox');
  assert reason = '0', 'the second token is the last';
  reason := null;
  begin
    perform public.issue_ad_reward_token(u, false, 'atid-ad-2', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_DAILY_CAP%', 'no third token today';

  -- Closing an ad early gives its place back.
  assert (select released from public.release_ad_reward_token(u, second)), 'her unused token is released';
  assert not (select released from public.release_ad_reward_token('00000000-0000-0000-0000-0000000000b1', first)),
    'nobody else can release it';
  assert (select remaining_today from public.ad_reward_status(u, first)) = 1, 'one place back';
end $$;

-- 5. ...and per install: another anonymous account made by the same Apple Account shares the cap.
do $$
declare
  sibling uuid := '00000000-0000-0000-0000-0000000000b4';
  reason text;
begin
  assert (select remaining_today from public.issue_ad_reward_token(sibling, false, 'atid-ad-2', 'verified', 'Sandbox')) = 0,
    'one left for the whole install';
  begin
    perform public.issue_ad_reward_token(sibling, false, 'atid-ad-2', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_DAILY_CAP%', format('a new account can''t farm a third, got %s', reason);
  assert not (public.ad_reward_overview(sibling, false, 'atid-ad-2', 'verified', 'Sandbox')->>'eligible')::boolean;
end $$;

-- 6. The cap holds at grant time too, and expired tokens pay nothing.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b3';
  k text := private.keyed_hash('app_transaction', 'atid-ad-3');
  late uuid;
  extra uuid;
  r record;
begin
  perform public.wallet_state(u, 'atid-ad-3', 'verified', 'Sandbox');
  update private.app_installs set daily = 0 where key = k;
  select reward_token into late from public.issue_ad_reward_token(u, false, 'atid-ad-3', 'verified', 'Sandbox');
  update public.ad_reward_tokens set expires_at = now() - interval '1 minute' where id = late;
  select * into r from public.redeem_ad_reward('tx-late', late, '1406702504', 1, 'credit');
  assert r.outcome = 'expired' and r.credits_remaining = 0, format('a late callback pays nothing, got %s', row_to_json(r));
  assert (select outcome from public.ad_reward_status(u, late)) = 'expired';

  -- Two rewards already paid today to this install (another account), as if from earlier tokens.
  insert into public.ad_rewards (transaction_id, user_id, token_id, ad_unit, credits, status, reward_day, install_key)
    select 'tx-paid-' || n, '00000000-0000-0000-0000-0000000000b2', gen_random_uuid(), '1406702504', 1, 'granted',
           (now() at time zone 'utc')::date, k
      from generate_series(1, 2) n;
  insert into public.ad_reward_tokens (id, user_id, install_key, expires_at)
    values (gen_random_uuid(), u, k, now() + interval '10 minutes')
    returning id into extra;
  select * into r from public.redeem_ad_reward('tx-over', extra, '1406702504', 1, 'credit');
  assert r.outcome = 'capped' and r.credits_remaining = 0, format('a third reward for the install is capped, got %s', row_to_json(r));
  assert (select count(*) from public.credit_ledger where kind = 'ad_reward' and user_id = u) = 0, 'nothing granted';
end $$;

-- 7. No ad while cloud AI rests after repeated safety blocks.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b3';
  reason text;
begin
  delete from public.ad_rewards where install_key = private.keyed_hash('app_transaction', 'atid-ad-3');
  insert into private.cooldowns (user_id, install_key, ends_at)
    values (u, private.keyed_hash('app_transaction', 'atid-ad-3'), now() + interval '1 hour');
  begin
    perform public.issue_ad_reward_token(u, false, 'atid-ad-3', 'verified', 'Sandbox');
  exception when others then
    reason := sqlerrm;
  end;
  assert reason like '%AD_NOT_ELIGIBLE%', format('resting, got %s', reason);
  delete from private.cooldowns where user_id = u;
end $$;

-- 8. Housekeeping: old tokens and rewards go.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  update public.ad_reward_tokens set expires_at = now() - interval '2 days' where user_id = u;
  update public.ad_rewards set created_at = now() - interval '31 days' where user_id = '00000000-0000-0000-0000-0000000000b2';
  perform public.sweep_ad_rewards();
  assert (select count(*) from public.ad_reward_tokens where user_id = u) = 0, 'expired tokens are deleted after a day';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b2') = 0,
    'rewards are deleted after 30 days';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b1') = 1,
    'recent rewards stay';
end $$;

-- 9. Clients can't touch any of it.
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
  assert not has_function_privilege('authenticated', 'public.issue_ad_reward_token(uuid, boolean, text, text, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.ad_reward_overview(uuid, boolean, text, text, text)', 'execute');
end $$;
reset role;

-- 10. Deleting the account removes its tokens and rewards.
do $$
begin
  delete from auth.users where id = '00000000-0000-0000-0000-0000000000b1';
  assert (select count(*) from public.ad_rewards where user_id = '00000000-0000-0000-0000-0000000000b1') = 0;
  assert (select count(*) from public.ad_reward_tokens where user_id = '00000000-0000-0000-0000-0000000000b1') = 0;
end $$;

select 'all ad reward tests passed' as result;
