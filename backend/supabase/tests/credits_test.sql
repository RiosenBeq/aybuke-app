-- Behavioural tests for the credit ledger. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure; psql stops on the first error.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');

-- 1. Free users start with 3 daily credits; holds spend them; insufficient balance raises.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
  j1 uuid := gen_random_uuid();
  left_after int;
  raised boolean := false;
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j1, u, 'magic_edit', 'test', 2);
  left_after := public.reserve_credits(u, false, 2, j1);
  assert left_after = 1, format('expected 1 left, got %s', left_after);
  begin
    perform public.reserve_credits(u, false, 2, gen_random_uuid());
  exception when others then
    raised := sqlerrm like '%INSUFFICIENT_CREDITS%';
  end;
  assert raised, 'expected INSUFFICIENT_CREDITS';

  -- 2. Releasing refunds exactly once.
  assert public.release_credits(j1) = 3, 'release should restore 3';
  assert public.release_credits(j1) = 3, 'second release must be a no-op';
  assert (select count(*) from public.credit_ledger where job_id = j1 and kind = 'release') = 1;
end $$;

-- 3. Packs are granted once per Apple transaction id, even across users.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
  other uuid := '00000000-0000-0000-0000-000000000002';
begin
  assert public.grant_pack(u, 30, 'apple-tx-1') = 33, 'pack should add 30';
  assert public.grant_pack(u, 30, 'apple-tx-1') = 33, 'redelivery must not double-grant';
  assert public.grant_pack(other, 30, 'apple-tx-1') = 3, 'another user cannot replay the transaction';
end $$;

-- 4. Pro: monthly allowance, spending order daily → subscription → purchased, exact refund.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
  j uuid := gen_random_uuid();
  w public.credit_wallets;
  hold public.credit_ledger;
begin
  w := public.refresh_wallet(u, true);
  assert w.subscription = 100 and w.daily = 3 and w.purchased = 30, format('unexpected wallet %s', row_to_json(w));
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j, u, 'text_to_image', 'test', 105);
  assert public.reserve_credits(u, true, 105, j) = 28;
  select * into hold from public.credit_ledger where job_id = j and kind = 'hold';
  assert hold.daily = -3 and hold.subscription = -100 and hold.purchased = -2, format('bad split %s', row_to_json(hold));
  assert public.release_credits(j) = 133;
end $$;

-- 5. Rollover is capped at one extra month; losing Pro expires subscription credits only.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000001';
  w public.credit_wallets;
begin
  update public.credit_wallets set subscription_period_start = now() - interval '1 month 2 days' where user_id = u;
  w := public.refresh_wallet(u, true);
  assert w.subscription = 200, format('expected 200 after one month, got %s', w.subscription);
  update public.credit_wallets set subscription_period_start = now() - interval '3 months 1 day' where user_id = u;
  w := public.refresh_wallet(u, true);
  assert w.subscription = 200, 'rollover must stay capped at 200';
  w := public.refresh_wallet(u, false);
  assert w.subscription = 0 and w.subscription_period_start is null, 'subscription credits expire with Pro';
  assert w.purchased = 30, 'purchased packs never expire';
  assert w.daily = 3, 'back on the free daily allowance';
end $$;

-- 6. Daily credits refill once per UTC day and never accumulate.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000002';
  w public.credit_wallets;
begin
  update public.credit_wallets set daily = 0, daily_period = (now() at time zone 'utc')::date - 3 where user_id = u;
  w := public.refresh_wallet(u, false);
  assert w.daily = 3, format('expected a single refill to 3, got %s', w.daily);
end $$;

-- 7. The sweeper fails stale jobs and refunds them.
do $$
declare
  u uuid := '00000000-0000-0000-0000-000000000002';
  j uuid := gen_random_uuid();
begin
  insert into public.jobs (id, user_id, operation, endpoint, cost, created_at)
    values (j, u, 'enhance', 'test', 1, now() - interval '20 minutes');
  perform public.reserve_credits(u, false, 1, j);
  perform public.sweep_jobs();
  assert (select status from public.jobs where id = j) = 'failed';
  assert (select daily from public.credit_wallets where user_id = u) = 3, 'stale job must be refunded';
end $$;

-- 8. RLS: authenticated users only see their own rows and cannot call ledger functions.
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
end $$;
reset role;

select 'all credit ledger tests passed' as result;
