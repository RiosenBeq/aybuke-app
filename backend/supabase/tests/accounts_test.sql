-- Behavioural tests for merging an anonymous user into a signed-in account.
-- Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-0000000000a3');

-- 1. Paid credits, the subscription, jobs and reports move; daily credits don't.
do $$
declare
  anon uuid := '00000000-0000-0000-0000-0000000000a1';
  account uuid := '00000000-0000-0000-0000-0000000000a2';
  w public.credit_wallets;
  j uuid := gen_random_uuid();
begin
  perform public.refresh_wallet(anon, false);
  perform public.grant_pack(anon, 30, 'tx-merge-1');
  insert into public.entitlements (original_transaction_id, user_id, product_id) values ('otx-merge-1', anon, 'app.glowlit.pro.yearly');
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j, anon, 'magic_edit', 'test', 1);
  insert into public.reports (user_id, job_id, reason) values (anon, j, 'mismatch');
  perform public.refresh_wallet(account, false);

  w := public.merge_accounts(anon, account);
  assert w.purchased = 30, 'purchased packs move to the account';
  assert w.daily = 3, 'the account keeps only its own daily credits';
  assert (select user_id from public.entitlements where original_transaction_id = 'otx-merge-1') = account, 'subscription moves';
  assert (select user_id from public.jobs where id = j) = account, 'jobs move';
  assert (select count(*) from public.reports where user_id = account) = 1, 'reports move';
  assert (select purchased + subscription from public.credit_wallets where user_id = anon) = 0, 'nothing left behind';
  assert (select count(*) from public.credit_ledger where kind = 'admin' and source_ref = 'merge:' || anon) = 1, 'merge is audited';

  -- Running it again changes nothing.
  w := public.merge_accounts(anon, account);
  assert w.purchased = 30, 'merging twice does not double credits';
end $$;

-- 2. Subscription credits never double, and the rollover cap holds.
do $$
declare
  first_phone uuid := '00000000-0000-0000-0000-0000000000a3';
  account uuid := '00000000-0000-0000-0000-0000000000a2';
  w public.credit_wallets;
begin
  perform public.refresh_wallet(first_phone, true);
  update public.credit_wallets set subscription = 150 where user_id = first_phone;
  update public.credit_wallets set subscription = 120 where user_id = account;
  w := public.merge_accounts(first_phone, account);
  assert w.subscription = 150, 'keeps the larger subscription balance';
end $$;

-- 3. An account can't be merged into itself, and clients can't call it.
do $$
declare
  account uuid := '00000000-0000-0000-0000-0000000000a2';
  rejected boolean := false;
begin
  begin
    perform public.merge_accounts(account, account);
  exception when others then
    rejected := true;
  end;
  assert rejected, 'self-merge is rejected';
  assert not has_function_privilege('authenticated', 'public.merge_accounts(uuid, uuid)', 'execute'), 'clients cannot merge';
  assert not has_table_privilege('authenticated', 'public.apple_accounts', 'insert'), 'clients cannot write Apple tokens';
end $$;

\echo 'accounts tests passed'
