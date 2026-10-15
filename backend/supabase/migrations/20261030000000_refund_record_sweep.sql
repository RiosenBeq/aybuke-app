-- The daily sweep deletes expired refund records too (20261025000002).
-- ----------------------------------------------------------------------------
-- The privacy policy (section 14, EN and TR) keeps the record of a refunded
-- subscription period until 30 days after the later of the refund and the
-- period's end, the record of a reversed refund until 30 days after the
-- reversal, and a refunded credit pack's record with no end date. Only
-- record_app_store_notification pruned private.refunded_transactions, so a
-- record that fell due stayed until the next notification arrived, however
-- long that took. The daily cron job 'sweep-app-store-notifications' (03:23
-- UTC) ran one inline delete of old notification records; it now calls
-- public.sweep_app_store_notifications(), which deletes both.

create function public.sweep_app_store_notifications()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_cutoff timestamptz := now() - interval '30 days';
begin
  delete from private.app_store_notifications where received_at < v_cutoff;

  -- Rows a notification holds are left for tomorrow's sweep (or that
  -- notification's own prune): waiting for them could deadlock with it, as in
  -- 20261025000003.
  delete from private.refunded_transactions t
   where (t.kind, t.transaction_id) in (
     select o.kind, o.transaction_id from private.refunded_transactions o
      where
        -- A reversed refund: 30 days after the reversal. A refund that came
        -- after it would have cleared reversed_at, so it is the newest event.
        (o.reversed_at is not null and greatest(o.refunded_at, o.reversed_at) < v_cutoff)
        -- A refunded subscription period: 30 days after the later of the
        -- refund and the period's end. Without a known end (Apple always
        -- sends one) it covers every period and stays, like the dispatcher.
        or (o.reversed_at is null and o.kind = 'pro' and o.refunded_at < v_cutoff and o.period_end < v_cutoff)
        -- A refunded pack that stays refunded is never due: its signed
        -- transaction never expires.
        for update skip locked);
end $$;

revoke execute on function public.sweep_app_store_notifications() from public, anon, authenticated;
grant execute on function public.sweep_app_store_notifications() to service_role;

-- Point the job at it. Same name and time: pg_cron updates the job in place.
-- Without pg_cron (a local or test database) nothing is scheduled; the
-- backend README's setup step 6 has the command.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cmd$select cron.schedule('sweep-app-store-notifications', '23 3 * * *',
                                      'select public.sweep_app_store_notifications()')$cmd$;
  end if;
end $$;
