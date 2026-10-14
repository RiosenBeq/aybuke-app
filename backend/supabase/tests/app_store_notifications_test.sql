-- App Store Server Notifications V2: refunds and revocations. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000e1'),
  ('00000000-0000-0000-0000-0000000000e2'),
  ('00000000-0000-0000-0000-0000000000e3');

-- 1. A refunded or revoked Pro subscription stops Pro and its credits at once.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000e1';
  period_end timestamptz := now() + interval '20 days';
  state jsonb;
begin
  assert public.record_entitlement(u, 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end, false, 'Production', false);
  state := public.wallet_state(u);
  assert (state->>'is_pro')::boolean and (state->>'credits_remaining')::int = 80, format('Pro before: %s', state);

  assert public.revoke_entitlement('otx-asn-refund', period_end), 'the refunded period is revoked';
  assert (select revoked from public.entitlements where original_transaction_id = 'otx-asn-refund');
  state := public.wallet_state(u);
  assert not (state->>'is_pro')::boolean and (state->>'credits_remaining')::int = 0,
    format('no Pro and no subscription credits after the refund: %s', state);
  assert public.revoke_entitlement('otx-asn-refund', period_end), 'a repeat keeps it revoked';

  -- The signed transaction from before the refund can't bring it back.
  assert not public.record_entitlement(u, 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end, false, 'Production', false),
    'the stale transaction is refused';
  assert (select revoked from public.entitlements where original_transaction_id = 'otx-asn-refund'), 'still revoked';

  assert not public.revoke_entitlement('otx-asn-unknown', period_end), 'nothing to revoke for an unknown subscription';
end $$;

-- 2. A refund of an older period leaves the current, paid one alone; a refund of a
-- period the server hadn't seen yet still revokes, and its stale copy can't undo it.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000e2';
  later timestamptz := now() + interval '31 days';
  e public.entitlements;
begin
  assert public.record_entitlement(u, 'otx-asn-renewed', 'app.glowlit.pro.monthly', now() + interval '25 days', false, 'Production', false);
  assert not public.revoke_entitlement('otx-asn-renewed', now() - interval '5 days'), 'last month''s refund';
  assert not (select revoked from public.entitlements where original_transaction_id = 'otx-asn-renewed'), 'this month stays Pro';

  assert public.record_entitlement(u, 'otx-asn-ahead', 'app.glowlit.pro.yearly', now() + interval '1 day', false, 'Sandbox', false);
  assert public.revoke_entitlement('otx-asn-ahead', later), 'the renewal the app never sent is refunded';
  select * into e from public.entitlements where original_transaction_id = 'otx-asn-ahead';
  assert e.revoked and e.expires_at = later, format('revoked up to the refunded period: %s', row_to_json(e));
  assert not public.record_entitlement(u, 'otx-asn-ahead', 'app.glowlit.pro.yearly', later, false, 'Sandbox', false),
    'the refunded renewal from before the refund is refused';
end $$;

-- 3. REFUND_REVERSED gives Pro back while the period lasts, and only for the period it covers.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000e1';
  period_end timestamptz;
begin
  select expires_at into period_end from public.entitlements where original_transaction_id = 'otx-asn-refund';
  assert not public.restore_entitlement('otx-asn-refund', period_end - interval '1 month'), 'an older period''s reversal';
  assert public.restore_entitlement('otx-asn-refund', period_end), 'the reversal restores it';
  assert not (select revoked from public.entitlements where original_transaction_id = 'otx-asn-refund');
  assert (public.wallet_state(u)->>'is_pro')::boolean, 'Pro is back';
  assert not public.restore_entitlement('otx-asn-refund', period_end), 'nothing to restore twice';

  assert public.record_entitlement(u, 'otx-asn-ended', 'app.glowlit.pro.monthly', now() - interval '1 day', true, 'Production', false);
  assert not public.restore_entitlement('otx-asn-ended', now() - interval '1 day'), 'an ended period stays ended';
  assert not public.restore_entitlement('otx-asn-unknown', now() + interval '1 day');
end $$;

-- 4. A refunded credit pack takes its credits back once, never below zero, through the ledger.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000e3';
  admitted jsonb;
  l public.credit_ledger;
begin
  assert public.grant_pack(u, 30, 'apple-pack-asn-a') = 30;
  assert public.grant_pack(u, 100, 'apple-pack-asn-b') = 130;
  admitted := public.admit_job(u, 'magic_edit', 'test', p_install_status => 'invalid');
  assert (admitted->>'ok')::boolean and (admitted->>'credits_remaining')::int = 129, format('one paid job: %s', admitted);

  assert public.refund_pack('apple-pack-asn-a') = 30, 'the whole pack comes back';
  assert (select purchased from public.credit_wallets where user_id = u) = 99;
  select * into l from public.credit_ledger where kind = 'refund_pack' and source_ref = 'apple-pack-asn-a';
  assert l.user_id = u and l.purchased = -30 and l.daily = 0 and l.subscription = 0, format('ledger: %s', row_to_json(l));
  assert public.refund_pack('apple-pack-asn-a') is null, 'once per transaction';
  assert (select purchased from public.credit_wallets where user_id = u) = 99, 'a repeat takes nothing';

  -- She already used most of the 100: only what's left goes.
  update public.credit_wallets set purchased = 7 where user_id = u;
  assert public.refund_pack('apple-pack-asn-b') = 7, 'never below zero';
  assert (select purchased from public.credit_wallets where user_id = u) = 0;
  assert (select purchased from public.credit_ledger where kind = 'refund_pack' and source_ref = 'apple-pack-asn-b') = -7;

  assert public.refund_pack('apple-pack-asn-never-granted') is null, 'no grant, nothing to take';

  -- REFUND_REVERSED gives back exactly what was taken, once.
  assert public.restore_pack('apple-pack-asn-b') = 7;
  assert (select purchased from public.credit_wallets where user_id = u) = 7;
  assert public.restore_pack('apple-pack-asn-b') is null, 'once';
  assert public.restore_pack('apple-pack-asn-never-refunded') is null;
  assert (select purchased from public.credit_ledger where kind = 'restore_pack' and source_ref = 'apple-pack-asn-b') = 7;
  -- The ledger still explains the wallet: grants, the job's hold, take-backs and the return.
  assert (select sum(purchased) from public.credit_ledger where user_id = u)
       = (select purchased from public.credit_wallets where user_id = u) + 92,
    'only the test''s direct wallet edit (99 → 7) is missing from the ledger';
end $$;

-- 5. Each notification counts once by its UUID; the same UUID again changes nothing.
do $$
declare
  n1 uuid := '6f0a1c55-0000-4000-8000-0000000000e1';
  n2 uuid := '6f0a1c55-0000-4000-8000-0000000000e2';
  n3 uuid := '6f0a1c55-0000-4000-8000-0000000000e3';
  n4 uuid := '6f0a1c55-0000-4000-8000-0000000000e4';
  period_end timestamptz;
  denied boolean := false;
begin
  select expires_at into period_end from public.entitlements where original_transaction_id = 'otx-asn-refund';
  assert public.record_app_store_notification(n1, 'REFUND', null, 'Production', 'revoke',
    'tx-1', 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end) = 'applied';
  assert (select revoked from public.entitlements where original_transaction_id = 'otx-asn-refund');
  assert public.record_app_store_notification(n2, 'REFUND_REVERSED', null, 'Production', 'restore',
    'tx-1', 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end) = 'applied';
  -- Apple sends the refund again (our 200 got lost): it was handled already.
  assert public.record_app_store_notification(n1, 'REFUND', null, 'Production', 'revoke',
    'tx-1', 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end) = 'duplicate';
  assert not (select revoked from public.entitlements where original_transaction_id = 'otx-asn-refund'), 'the replay changed nothing';

  assert public.record_app_store_notification(n3, 'DID_RENEW', null, 'Sandbox', 'none',
    'tx-2', 'otx-asn-refund', 'app.glowlit.pro.monthly', period_end + interval '1 month') = 'ignored';
  assert public.record_app_store_notification(n4, 'REFUND', null, 'Production', 'revoke',
    'tx-3', 'otx-asn-unknown', 'app.glowlit.pro.monthly', period_end) = 'no_match';
  assert (select count(*) from private.app_store_notifications where notification_uuid in (n1, n2, n3, n4)) = 4;
  assert (select outcome from private.app_store_notifications where notification_uuid = n3) = 'ignored';
  assert not exists (
    select 1 from information_schema.columns
     where table_schema = 'private' and table_name = 'app_store_notifications'
       and column_name in ('transaction_id', 'original_transaction_id', 'user_id')
  ), 'the record holds no transaction or user id';

  begin
    perform public.record_app_store_notification(gen_random_uuid(), 'REFUND', null, 'Production', 'grant_everything',
      null, null, null, null);
  exception when others then
    denied := true;
  end;
  assert denied, 'an unknown action is an error, not a silent no-op';
end $$;

-- 6. A pack refund through a notification, and records older than 30 days are pruned.
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000e3';
begin
  assert public.grant_pack(u, 30, 'apple-pack-asn-c') = 37;
  insert into private.app_store_notifications (notification_uuid, notification_type, action, outcome, received_at)
    values ('6f0a1c55-0000-4000-8000-0000000000ef', 'TEST', 'none', 'ignored', now() - interval '31 days');
  assert public.record_app_store_notification('6f0a1c55-0000-4000-8000-0000000000e5', 'REFUND', null, 'Production',
    'refund_pack', 'apple-pack-asn-c', 'apple-pack-asn-c', 'app.glowlit.credits.30', null) = 'applied';
  assert (select purchased from public.credit_wallets where user_id = u) = 7;
  assert public.record_app_store_notification('6f0a1c55-0000-4000-8000-0000000000e6', 'REFUND', null, 'Production',
    'refund_pack', 'apple-pack-asn-c', 'apple-pack-asn-c', 'app.glowlit.credits.30', null) = 'no_match',
    'another notification for the same refund takes nothing more';
  assert (select purchased from public.credit_wallets where user_id = u) = 7;
  assert not exists (select 1 from private.app_store_notifications
                      where notification_uuid = '6f0a1c55-0000-4000-8000-0000000000ef'), 'old records are pruned';
end $$;

-- 7. Service role only: clients can neither call the functions nor read the record.
do $$
begin
  assert not has_function_privilege('anon', 'public.revoke_entitlement(text, timestamptz)', 'execute');
  assert not has_function_privilege('authenticated', 'public.revoke_entitlement(text, timestamptz)', 'execute');
  assert not has_function_privilege('anon', 'public.restore_entitlement(text, timestamptz)', 'execute');
  assert not has_function_privilege('authenticated', 'public.restore_entitlement(text, timestamptz)', 'execute');
  assert not has_function_privilege('anon', 'public.refund_pack(text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.refund_pack(text)', 'execute');
  assert not has_function_privilege('anon', 'public.restore_pack(text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.restore_pack(text)', 'execute');
  assert not has_function_privilege('anon',
    'public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)', 'execute');
  assert not has_function_privilege('authenticated',
    'public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)', 'execute');
  assert has_function_privilege('service_role',
    'public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)', 'execute');
  assert has_function_privilege('service_role', 'public.revoke_entitlement(text, timestamptz)', 'execute');
  assert has_function_privilege('service_role', 'public.refund_pack(text)', 'execute');

  assert (select relrowsecurity from pg_class where oid = 'private.app_store_notifications'::regclass), 'RLS is on';
  assert not exists (select 1 from pg_policies where schemaname = 'private' and tablename = 'app_store_notifications'),
    'no policy opens it';
  assert not has_table_privilege('anon', 'private.app_store_notifications', 'select');
  assert not has_table_privilege('authenticated', 'private.app_store_notifications', 'select');
  assert not has_table_privilege('authenticated', 'private.app_store_notifications', 'insert');
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e3', false);
do $$
declare
  denied boolean := false;
begin
  begin
    perform public.restore_pack('apple-pack-asn-c');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'a client cannot give herself the credits back';
  denied := false;
  begin
    perform public.record_app_store_notification(gen_random_uuid(), 'REFUND_REVERSED', null, 'Production', 'restore',
      null, 'otx-asn-refund', 'app.glowlit.pro.monthly', now() + interval '1 year');
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'a client cannot forge a notification';
  denied := false;
  begin
    perform 1 from private.app_store_notifications;
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'the record is closed to clients';
end $$;
reset role;

set role anon;
do $$
declare
  denied boolean := false;
begin
  begin
    perform public.revoke_entitlement('otx-asn-renewed', null);
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'anonymous callers cannot revoke anyone''s Pro';
end $$;
reset role;

-- Clean up the fixtures (the ledger and wallets cascade with the users).
delete from public.entitlements where original_transaction_id like 'otx-asn-%';
delete from private.app_store_notifications where notification_uuid::text like '6f0a1c55-%';
delete from auth.users where id in (
  '00000000-0000-0000-0000-0000000000e1',
  '00000000-0000-0000-0000-0000000000e2',
  '00000000-0000-0000-0000-0000000000e3'
);

select 'all App Store notification tests passed' as result;
