-- Behavioural tests for merging an anonymous user into a signed-in account.
-- Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-0000000000a3');

-- 1. Paid credits, the subscription, jobs and reports move; free daily credits
--    belong to the App Store install, not to either account.
do $$
declare
  anon uuid := '00000000-0000-0000-0000-0000000000a1';
  account uuid := '00000000-0000-0000-0000-0000000000a2';
  w public.credit_wallets;
  j uuid := gen_random_uuid();
begin
  perform public.wallet_state(anon, 'atid-merge', 'verified', 'Sandbox');
  perform public.grant_pack(anon, 30, 'tx-merge-1');
  insert into public.entitlements (original_transaction_id, user_id, product_id) values ('otx-merge-1', anon, 'app.glowlit.pro.yearly');
  insert into public.jobs (id, user_id, operation, endpoint, cost) values (j, anon, 'magic_edit', 'test', 1);
  insert into public.reports (user_id, job_id, reason) values (anon, j, 'mismatch');
  perform public.wallet_state(account, 'atid-merge', 'verified', 'Sandbox');

  w := public.merge_accounts(anon, account);
  assert w.purchased = 30, 'purchased packs move to the account';
  assert (public.wallet_state(account, 'atid-merge', 'verified', 'Sandbox')->>'credits_remaining')::int = 32,
    'the pack plus the install''s own free credits, never doubled';
  assert (select user_id from public.entitlements where original_transaction_id = 'otx-merge-1') = account, 'subscription moves';
  assert (select user_id from public.jobs where id = j) = account, 'jobs move';
  assert (select count(*) from public.reports where user_id = account) = 1, 'reports move';
  assert (select purchased + subscription from public.credit_wallets where user_id = anon) = 0, 'nothing left behind';
  assert (select count(*) from public.credit_ledger where kind = 'admin' and source_ref = 'merge:' || anon) = 1, 'merge is audited';

  -- Running it again changes nothing.
  w := public.merge_accounts(anon, account);
  assert w.purchased = 30, 'merging twice does not double credits';
end $$;

-- 2. Subscription credits live on the subscription, so they move with it and never double.
do $$
declare
  first_phone uuid := '00000000-0000-0000-0000-0000000000a3';
  account uuid := '00000000-0000-0000-0000-0000000000a2';
begin
  insert into public.entitlements (original_transaction_id, user_id, product_id, expires_at, credits, credits_period_start)
    values ('otx-merge-2', first_phone, 'app.glowlit.pro.monthly', now() + interval '1 month', 150, now());
  perform public.merge_accounts(first_phone, account);
  assert (select user_id from public.entitlements where original_transaction_id = 'otx-merge-2') = account;
  assert (select credits from public.entitlements where original_transaction_id = 'otx-merge-2') = 150, 'the same 150, not more';
  assert (public.wallet_state(account)->>'credits_remaining')::int = 180, 'subscription credits plus the pack';
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

-- 4. Merged anonymous ids (for RevenueCat deletion) are private and go with the account.
do $$
declare
  account uuid := '00000000-0000-0000-0000-0000000000a2';
begin
  insert into public.merged_users (account_id, anonymous_id) values (account, '00000000-0000-0000-0000-0000000000a1');
  assert not has_table_privilege('authenticated', 'public.merged_users', 'insert'), 'clients cannot record merges';
  delete from auth.users where id = account;
  assert (select count(*) from public.merged_users where account_id = account) = 0, 'merged ids are deleted with the account';
end $$;

\echo 'accounts tests passed'
