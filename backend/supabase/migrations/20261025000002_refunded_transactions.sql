-- Refunds the server hears about before it sees the purchase (20261025000000).
-- ----------------------------------------------------------------------------
-- A REFUND or REVOKE that arrived before the transaction was ever redeemed
-- found no entitlement or pack grant, was recorded as no_match and was then
-- forgotten: the signed transaction captured before the refund could still be
-- redeemed, so grant_pack granted the pack and record_entitlement stored an
-- unrevoked Pro row. Now:
--
--   * Every REFUND or REVOKE is remembered (private.refunded_transactions),
--     whether or not it matched; REFUND_REVERSED marks it reversed.
--   * grant_pack refuses a refunded pack the way it answers a repeat: nothing
--     granted, the balance returned (credits-redeem answers 200 with it).
--   * record_entitlement stores a refunded subscription period as revoked and
--     returns false, so resolveEntitlement grants no Pro for it either. A later
--     period she paid for is not refunded and stays Pro.
--   * Apple doesn't promise the order: a refund signed before the reversal
--     already applied for the same transaction, or a reversal signed before
--     the refund, is stale and changes nothing (outcome 'stale'). Apple's
--     signedDate comes in a new tenth argument; the nine-argument call stays
--     and keeps arrival order.
--   * A notification and a redeem of the same transaction take one lock, so
--     neither misses the other while both are in flight.

-- MARK: Refunded transactions

-- Kept while it can matter. A pack's signed transaction never expires (the
-- server checks Apple's signature, not its age), so a refunded pack stays for
-- good: forgetting it would make a captured copy redeemable again. A row holds
-- no user id, and refunds are few. A Pro period's signed transaction grants
-- nothing once the period has ended, so its row goes 30 days after that. A
-- reversed row goes 30 days after the reversal: Apple stops retrying after
-- about a week, so no stale copy can still arrive.
create table private.refunded_transactions (
  kind text not null check (kind in ('pro', 'pack')),
  -- The refunded transaction: a pack, or one period of a subscription.
  transaction_id text not null,
  -- Pro only: the subscription (what record_entitlement stores) and the
  -- refunded period's expiry. A transaction that expires later is a period she
  -- paid for. No period end: every period, like revoke_entitlement.
  original_transaction_id text,
  period_end timestamptz,
  -- When the newest refund arrived (null when only a reversal came), and the
  -- reversal that undid it (null while the refund stands).
  refunded_at timestamptz,
  reversed_at timestamptz,
  -- Apple's signedDate of the newest refund and reversal applied here, to
  -- spot one that arrives out of order. Null when Apple's payload named none.
  refund_signed_at timestamptz,
  reversal_signed_at timestamptz,
  primary key (kind, transaction_id),
  check (kind = 'pack' or original_transaction_id is not null)
);
create index refunded_transactions_original_idx on private.refunded_transactions (original_transaction_id)
  where kind = 'pro';
alter table private.refunded_transactions enable row level security;
revoke all on table private.refunded_transactions from public, anon, authenticated, service_role;

alter table private.app_store_notifications drop constraint if exists app_store_notifications_outcome_check;
alter table private.app_store_notifications add constraint app_store_notifications_outcome_check
  check (outcome in ('pending', 'applied', 'no_match', 'ignored', 'stale'));

-- One transaction at a time: the notification that refunds it and a redeem
-- of it run one after the other, so neither misses the other's write. Held to
-- the end of the transaction. Pro is locked by the original transaction id.
create function private.lock_refund(p_kind text, p_ref text)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('refund:' || p_kind || ':' || p_ref, 0))
$$;

-- An unreversed refund covers this pack, or this period of the subscription
-- (p_ref is the original transaction id; the period ends at p_expires_at).
create function private.refund_stands(p_kind text, p_ref text, p_expires_at timestamptz default null)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if p_kind = 'pro' then
    return exists (
      select 1 from private.refunded_transactions r
       where r.kind = 'pro' and r.original_transaction_id = p_ref and r.reversed_at is null
         and (r.period_end is null or p_expires_at is null or p_expires_at <= r.period_end));
  end if;
  return exists (
    select 1 from private.refunded_transactions r
     where r.kind = 'pack' and r.transaction_id = p_ref and r.reversed_at is null);
end $$;

revoke all on function private.lock_refund(text, text) from public;
revoke all on function private.refund_stands(text, text, timestamptz) from public;

-- MARK: One notification

-- As in 20261025000000, with Apple's signedDate (p_signed_at), the memory of
-- refunds and the order check. Returns 'duplicate' for a UUID seen before,
-- 'ignored' for 'none', 'stale' for one that arrived out of order, otherwise
-- 'applied' or 'no_match'.
create function public.record_app_store_notification(
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
  -- days ago. Refunded packs stay (see the table).
  delete from private.refunded_transactions t
   where greatest(t.refunded_at, t.reversed_at) < now() - interval '30 days'
     and (t.reversed_at is not null or (t.kind = 'pro' and t.period_end < now() - interval '30 days'));
  return v_outcome;
end $$;

-- The call without Apple's signedDate (20261025000000): arrival order.
create or replace function public.record_app_store_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_action text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_period_end timestamptz
)
returns text
language sql security definer
set search_path = ''
as $$
  select public.record_app_store_notification(p_notification_uuid, p_notification_type, p_subtype, p_environment,
    p_action, p_transaction_id, p_original_transaction_id, p_product_id, p_period_end, null::timestamptz)
$$;

-- MARK: Redeeming

-- As in 20261021000000; a pack Apple refunded before it was redeemed is
-- answered like a repeat: nothing granted, the balance returned.
create or replace function public.grant_pack(
  p_user uuid, p_credits int, p_transaction_id text,
  p_app_transaction_id text default null, p_install_status text default 'missing', p_install_environment text default null
)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  perform private.lock_refund('pack', p_transaction_id);
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  insert into public.credit_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  if private.refund_stands('pack', p_transaction_id) then
    return private.balance_of(p_user, v_key);
  end if;
  insert into public.credit_ledger (user_id, kind, purchased, source_ref)
    values (p_user, 'grant_pack', p_credits, p_transaction_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if found then
    update public.credit_wallets set purchased = purchased + p_credits, updated_at = now() where user_id = p_user;
  end if;
  return private.balance_of(p_user, v_key);
end $$;

-- As in 20261024000002; a period Apple refunded is stored revoked. Only a
-- revoked signed transaction always lands: one revoked here follows the order
-- check, so a stale copy of a refunded period can't replace a newer one.
create or replace function public.record_entitlement(
  p_user uuid,
  p_original_transaction_id text,
  p_product_id text,
  p_expires_at timestamptz,
  p_revoked boolean,
  p_environment text,
  p_is_trial boolean
)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
  v_refunded boolean;
begin
  perform private.lock_refund('pro', p_original_transaction_id);
  v_refunded := private.refund_stands('pro', p_original_transaction_id, p_expires_at);
  insert into public.entitlements as e
    (original_transaction_id, user_id, product_id, expires_at, revoked, environment, is_trial, updated_at)
    values (p_original_transaction_id, p_user, p_product_id, p_expires_at, p_revoked or v_refunded, p_environment, p_is_trial, now())
    on conflict (original_transaction_id) do update
      set user_id = excluded.user_id,
          product_id = excluded.product_id,
          expires_at = excluded.expires_at,
          revoked = excluded.revoked,
          environment = excluded.environment,
          is_trial = excluded.is_trial,
          updated_at = excluded.updated_at
      where p_revoked
         or not coalesce(
              e.expires_at is not null
              and (excluded.expires_at is null
                   or excluded.expires_at < e.expires_at
                   or (e.revoked and excluded.expires_at = e.expires_at)),
              false);
  -- False when it grants nothing: the stored transaction is newer, or Apple refunded this one.
  return found and not v_refunded;
end $$;

-- MARK: Privileges

revoke execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.grant_pack(uuid, int, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)
  from public, anon, authenticated;
grant execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz, timestamptz)
  to service_role;
grant execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)
  to service_role;
grant execute on function public.grant_pack(uuid, int, text, text, text, text) to service_role;
grant execute on function public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)
  to service_role;
