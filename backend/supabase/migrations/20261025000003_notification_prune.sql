-- The dispatcher's prune (20261025000002) could deadlock two notifications
-- that arrive together: each deleted an old refunded_transactions row the
-- other was about to lock, so one of them answered 500 and waited for
-- Apple's retry. The prune now deletes only rows it can lock at once
-- (for update skip locked); a row another notification holds is left for a
-- later prune. Everything else is as in 20261025000002.

create or replace function public.record_app_store_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_action text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_period_end timestamptz,
  p_signed_at timestamptz
)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_applied boolean;
  v_outcome text;
  v_refund boolean := p_action in ('revoke', 'refund_pack');
  v_kind text;
  v_ref text;
  v_lock text;
  r private.refunded_transactions;
begin
  if p_action is null or p_action not in ('revoke', 'restore', 'refund_pack', 'restore_pack', 'none') then
    raise exception 'unknown notification action %', p_action;
  end if;
  insert into private.app_store_notifications
    (notification_uuid, notification_type, subtype, environment, product_id, action, outcome)
    values (p_notification_uuid, p_notification_type, p_subtype, p_environment, p_product_id, p_action, 'pending')
    on conflict (notification_uuid) do nothing;
  if not found then
    return 'duplicate';
  end if;

  -- The refunded transaction: a pack, or one period of a subscription (the
  -- first period's transaction id is the original one).
  if p_action in ('revoke', 'restore') and p_original_transaction_id is not null then
    v_kind := 'pro';
    v_ref := coalesce(p_transaction_id, p_original_transaction_id);
    v_lock := p_original_transaction_id;
  elsif p_action in ('refund_pack', 'restore_pack') and p_transaction_id is not null then
    v_kind := 'pack';
    v_ref := p_transaction_id;
    v_lock := p_transaction_id;
  end if;

  if v_ref is not null then
    perform private.lock_refund(v_kind, v_lock);
    select * into r from private.refunded_transactions t where t.kind = v_kind and t.transaction_id = v_ref;
    -- Signed before the opposite notification already applied here: stale.
    if p_signed_at < (case when v_refund then r.reversal_signed_at else r.refund_signed_at end) then
      v_outcome := 'stale';
    end if;
  end if;

  if v_outcome is null then
    v_applied := case p_action
      when 'revoke' then public.revoke_entitlement(p_original_transaction_id, p_period_end)
      when 'restore' then public.restore_entitlement(p_original_transaction_id, p_period_end)
      when 'refund_pack' then public.refund_pack(p_transaction_id) is not null
      when 'restore_pack' then public.restore_pack(p_transaction_id) is not null
    end;
    v_outcome := case when p_action = 'none' then 'ignored' when v_applied then 'applied' else 'no_match' end;

    if v_ref is not null and v_refund then
      insert into private.refunded_transactions as t
        (kind, transaction_id, original_transaction_id, period_end, refunded_at, refund_signed_at)
        values (v_kind, v_ref, case when v_kind = 'pro' then p_original_transaction_id end,
                case when v_kind = 'pro' then p_period_end end, now(), p_signed_at)
        on conflict (kind, transaction_id) do update
          set original_transaction_id = coalesce(excluded.original_transaction_id, t.original_transaction_id),
              period_end = coalesce(excluded.period_end, t.period_end),
              refunded_at = excluded.refunded_at,
              reversed_at = null,
              refund_signed_at = greatest(t.refund_signed_at, excluded.refund_signed_at);
    elsif v_ref is not null then
      -- Also when no refund was seen yet: a late refund signed before this
      -- reversal is then recognised as stale.
      insert into private.refunded_transactions as t
        (kind, transaction_id, original_transaction_id, period_end, reversed_at, reversal_signed_at)
        values (v_kind, v_ref, case when v_kind = 'pro' then p_original_transaction_id end,
                case when v_kind = 'pro' then p_period_end end, now(), p_signed_at)
        on conflict (kind, transaction_id) do update
          set reversed_at = excluded.reversed_at,
              reversal_signed_at = greatest(t.reversal_signed_at, excluded.reversal_signed_at);
    end if;
  end if;
  update private.app_store_notifications set outcome = v_outcome where notification_uuid = p_notification_uuid;

  delete from private.app_store_notifications where received_at < now() - interval '30 days';
  -- Untouched for 30 days, and either reversed or a Pro period that ended 30
  -- days ago. Refunded packs stay (see the table). Rows another notification
  -- holds are left for a later prune: waiting for them could deadlock with it.
  delete from private.refunded_transactions t
   where (t.kind, t.transaction_id) in (
     select o.kind, o.transaction_id from private.refunded_transactions o
      where greatest(o.refunded_at, o.reversed_at) < now() - interval '30 days'
        and (o.reversed_at is not null or (o.kind = 'pro' and o.period_end < now() - interval '30 days'))
        for update skip locked);
  return v_outcome;
end $$;

revoke execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz, timestamptz)
  to service_role;
