-- The daily sweep keeps the privacy policy's promise on refund records
-- (20261030000000), with no App Store notification arriving. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

-- Fixtures: one row per case, 29 and 31 days either side of the 30-day line.
insert into private.refunded_transactions
  (kind, transaction_id, original_transaction_id, period_end, refunded_at, reversed_at) values
  -- A refunded pack that stays refunded: kept with no end date.
  ('pack', 'rrs-pack-refunded', null, null, now() - interval '400 days', null),
  -- A reversed refund: 30 days after the reversal.
  ('pack', 'rrs-pack-reversed-due', null, null, now() - interval '60 days', now() - interval '31 days'),
  ('pack', 'rrs-pack-reversed-recent', null, null, now() - interval '60 days', now() - interval '29 days'),
  ('pack', 'rrs-pack-reversal-only-due', null, null, null, now() - interval '31 days'),
  ('pro', 'rrs-pro-reversed-due', 'otx-rrs-a', now() + interval '20 days', now() - interval '40 days', now() - interval '31 days'),
  ('pro', 'rrs-pro-reversed-recent', 'otx-rrs-a', now() - interval '60 days', now() - interval '90 days', now() - interval '29 days'),
  -- A refunded subscription period: 30 days after the later of the refund and the period's end.
  ('pro', 'rrs-pro-both-due', 'otx-rrs-b', now() - interval '31 days', now() - interval '35 days', null),
  ('pro', 'rrs-pro-refund-later-due', 'otx-rrs-b', now() - interval '60 days', now() - interval '31 days', null),
  ('pro', 'rrs-pro-refund-recent', 'otx-rrs-b', now() - interval '60 days', now() - interval '29 days', null),
  ('pro', 'rrs-pro-period-ended-recently', 'otx-rrs-c', now() - interval '29 days', now() - interval '60 days', null),
  ('pro', 'rrs-pro-period-running', 'otx-rrs-c', now() + interval '10 days', now() - interval '400 days', null),
  -- No known period end: covers every period, so it stays (as in the dispatcher's prune).
  ('pro', 'rrs-pro-no-end', 'otx-rrs-d', null, now() - interval '400 days', null);
insert into private.app_store_notifications (notification_uuid, notification_type, action, outcome, received_at) values
  ('7a1b2c3d-0000-4000-8000-0000000000a1', 'TEST', 'none', 'ignored', now() - interval '31 days'),
  ('7a1b2c3d-0000-4000-8000-0000000000a2', 'TEST', 'none', 'ignored', now() - interval '29 days');

-- 1. One sweep, no notification: the due records go, the others stay.
do $$
begin
  perform public.sweep_app_store_notifications();
  assert (select array_agg(transaction_id order by transaction_id) from private.refunded_transactions
           where transaction_id like 'rrs-%')
       = array['rrs-pack-refunded', 'rrs-pack-reversed-recent', 'rrs-pro-no-end', 'rrs-pro-period-ended-recently',
               'rrs-pro-period-running', 'rrs-pro-refund-recent', 'rrs-pro-reversed-recent'],
    format('kept: %s', (select array_agg(transaction_id order by transaction_id) from private.refunded_transactions
                         where transaction_id like 'rrs-%'));
  assert not exists (select 1 from private.app_store_notifications
                      where notification_uuid = '7a1b2c3d-0000-4000-8000-0000000000a1'), 'old notification records go';
  assert exists (select 1 from private.app_store_notifications
                  where notification_uuid = '7a1b2c3d-0000-4000-8000-0000000000a2'), 'recent ones stay';

  -- What stays still counts: the standing refunds still refuse a redeem.
  assert private.refund_stands('pack', 'rrs-pack-refunded');
  assert private.refund_stands('pro', 'otx-rrs-c', now() + interval '5 days');
  assert private.refund_stands('pro', 'otx-rrs-d', now() + interval '1 year');
  assert not private.refund_stands('pack', 'rrs-pack-reversed-recent'), 'a reversed refund doesn''t';

  perform public.sweep_app_store_notifications();
  assert (select count(*) from private.refunded_transactions where transaction_id like 'rrs-%') = 7, 'a second run deletes nothing more';
end $$;

-- Due, but held by a notification in flight during block 2.
insert into private.refunded_transactions (kind, transaction_id, refunded_at, reversed_at)
  values ('pack', 'rrs-pack-held-due', now() - interval '60 days', now() - interval '31 days');

-- 2. A row a notification holds is skipped, not waited for, and goes the next
-- day. Needs dblink (part of the PostgreSQL server packages); skipped without.
do $$
declare
  conn text := format('dbname=%s user=%s host=%s port=%s', current_database(), current_user,
                      split_part(current_setting('unix_socket_directories'), ',', 1), current_setting('port'));
begin
  if not exists (select 1 from pg_available_extensions where name = 'dblink') then
    raise notice 'dblink is not installed: the sweep lock test (2) is skipped';
    return;
  end if;
  create schema sweep_lock_test;
  create extension dblink schema sweep_lock_test;
  perform sweep_lock_test.dblink_connect('held', conn);
  perform sweep_lock_test.dblink_exec('held', 'begin');
  perform sweep_lock_test.dblink_exec('held',
    'update private.refunded_transactions set reversal_signed_at = now() where transaction_id = ''rrs-pack-held-due''');

  perform set_config('lock_timeout', '100ms', true);
  perform public.sweep_app_store_notifications();
  perform set_config('lock_timeout', '0', true);
  assert exists (select 1 from private.refunded_transactions where transaction_id = 'rrs-pack-held-due'),
    'the held row is left alone';

  perform sweep_lock_test.dblink_exec('held', 'commit');
  perform sweep_lock_test.dblink_disconnect('held');
  perform public.sweep_app_store_notifications();
  assert not exists (select 1 from private.refunded_transactions where transaction_id = 'rrs-pack-held-due'),
    'and goes once it is free';
  drop extension dblink;
  drop schema sweep_lock_test;
end $$;

-- 3. Closed like the other sweepers: the service role (and pg_cron's owner)
-- only, security definer with an empty search_path.
do $$
begin
  assert not has_function_privilege('anon', 'public.sweep_app_store_notifications()', 'execute');
  assert not has_function_privilege('authenticated', 'public.sweep_app_store_notifications()', 'execute');
  assert has_function_privilege('service_role', 'public.sweep_app_store_notifications()', 'execute');
  assert (select prosecdef and proconfig = array['search_path=""'] from pg_proc
           where oid = 'public.sweep_app_store_notifications()'::regprocedure),
    'security definer, search_path = ''''';
end $$;

-- Clean up the fixtures.
delete from private.refunded_transactions where transaction_id like 'rrs-%';
delete from private.app_store_notifications where notification_uuid::text like '7a1b2c3d-%';

select 'all refund record sweep tests passed' as result;
