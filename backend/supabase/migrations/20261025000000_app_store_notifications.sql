-- App Store Server Notifications V2: refunds and revocations.
-- ----------------------------------------------------------------------------
-- Until now a refunded or revoked Pro subscription kept Pro until expires_at,
-- and a refunded credit pack kept its credits. Apple now tells the server
-- (functions/app-store-notifications, which verifies Apple's signature):
--
--   * REFUND or REVOKE (Family Sharing) of a Pro subscription revokes its
--     entitlement. Every reader filters on revoked, so Pro and the
--     subscription's credits stop at once. A refund of an older period
--     leaves a newer, paid one alone.
--   * REFUND_REVERSED gives it back while the period lasts.
--   * REFUND of a credit pack takes its credits back from the purchased
--     bucket, never below zero (credits she already used stay used), once
--     per transaction; REFUND_REVERSED returns exactly what was taken.
--   * Each notification counts once by its notificationUUID: Apple sends it
--     again until it gets a 200, and a repeat changes nothing.

-- MARK: Ledger

alter table public.credit_ledger drop constraint if exists credit_ledger_kind_check;
alter table public.credit_ledger add constraint credit_ledger_kind_check
  check (kind in ('hold', 'release', 'grant_pack', 'admin', 'ad_reward', 'refund_pack', 'restore_pack'));

-- MARK: Notifications received

-- Only what deduplication and the owner's review need: no transaction or
-- user id, so the record links to no one. Kept 30 days (Apple stops
-- retrying after about a week).
create table private.app_store_notifications (
  notification_uuid uuid primary key,
  notification_type text not null,
  subtype text,
  environment text,
  product_id text,
  action text not null check (action in ('revoke', 'restore', 'refund_pack', 'restore_pack', 'none')),
  outcome text not null check (outcome in ('pending', 'applied', 'no_match', 'ignored')),
  received_at timestamptz not null default now()
);
create index app_store_notifications_received_idx on private.app_store_notifications (received_at);
alter table private.app_store_notifications enable row level security;
revoke all on table private.app_store_notifications from public, anon, authenticated, service_role;

-- MARK: Subscriptions

-- REFUND or REVOKE. p_period_end is the refunded transaction's expiry: a
-- refund of an older period leaves the newer one stored here alone. The
-- stored expiry moves up to it, so the signed transaction from before the
-- refund, which has that expiry, can't undo this (record_entitlement refuses
-- a revoked row's own expiry). True when the subscription is revoked.
create function public.revoke_entitlement(p_original_transaction_id text, p_period_end timestamptz default null)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.entitlements e
     set revoked = true,
         expires_at = greatest(e.expires_at, p_period_end),
         updated_at = now()
   where e.original_transaction_id = p_original_transaction_id
     and (p_period_end is null or e.expires_at is null or e.expires_at <= p_period_end);
  return found;
end $$;

-- REFUND_REVERSED: Pro comes back for the period the reversal covers, while it lasts.
create function public.restore_entitlement(p_original_transaction_id text, p_period_end timestamptz default null)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.entitlements e
     set revoked = false, updated_at = now()
   where e.original_transaction_id = p_original_transaction_id
     and e.revoked
     and e.expires_at > now()
     and (p_period_end is null or e.expires_at <= p_period_end);
  return found;
end $$;

-- MARK: Credit packs

-- REFUND of a pack: takes back what's left of it from the purchased bucket,
-- never below zero, once per Apple transaction id, written to the ledger like
-- grant_pack. Returns the credits taken, or null when there's nothing to take
-- (no grant, or taken already).
create function public.refund_pack(p_transaction_id text)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  g public.credit_ledger;
  v_taken int;
begin
  select * into g from public.credit_ledger where kind = 'grant_pack' and source_ref = p_transaction_id;
  if not found then
    return null;
  end if;
  -- The wallet lock orders this against a job's hold.
  select least(g.purchased, greatest(w.purchased, 0)) into v_taken
    from public.credit_wallets w where w.user_id = g.user_id for update;
  v_taken := coalesce(v_taken, 0);
  insert into public.credit_ledger (user_id, kind, purchased, source_ref)
    values (g.user_id, 'refund_pack', -v_taken, p_transaction_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if not found then
    return null;
  end if;
  update public.credit_wallets set purchased = purchased - v_taken, updated_at = now() where user_id = g.user_id;
  return v_taken;
end $$;

-- REFUND_REVERSED of a pack: returns exactly what the refund took, once.
-- Returns the credits returned, or null when there's nothing to return.
create function public.restore_pack(p_transaction_id text)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  r public.credit_ledger;
begin
  select * into r from public.credit_ledger where kind = 'refund_pack' and source_ref = p_transaction_id;
  if not found then
    return null;
  end if;
  perform 1 from public.credit_wallets w where w.user_id = r.user_id for update;
  insert into public.credit_ledger (user_id, kind, purchased, source_ref)
    values (r.user_id, 'restore_pack', -r.purchased, p_transaction_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if not found then
    return null;
  end if;
  update public.credit_wallets set purchased = purchased - r.purchased, updated_at = now() where user_id = r.user_id;
  return -r.purchased;
end $$;

-- MARK: One notification

-- Records a verified notification and applies its action in one transaction,
-- so a failure leaves nothing recorded and Apple's retry applies it. The
-- Edge Function picks the action (see app-store-notifications/handler.ts).
-- Returns 'duplicate' for a UUID seen before, 'ignored' for 'none',
-- otherwise 'applied' or 'no_match'.
create function public.record_app_store_notification(
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
language plpgsql security definer
set search_path = ''
as $$
declare
  v_applied boolean;
  v_outcome text;
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

  v_applied := case p_action
    when 'revoke' then public.revoke_entitlement(p_original_transaction_id, p_period_end)
    when 'restore' then public.restore_entitlement(p_original_transaction_id, p_period_end)
    when 'refund_pack' then public.refund_pack(p_transaction_id) is not null
    when 'restore_pack' then public.restore_pack(p_transaction_id) is not null
  end;
  v_outcome := case when p_action = 'none' then 'ignored' when v_applied then 'applied' else 'no_match' end;
  update private.app_store_notifications set outcome = v_outcome where notification_uuid = p_notification_uuid;

  delete from private.app_store_notifications where received_at < now() - interval '30 days';
  return v_outcome;
end $$;

-- MARK: Privileges

revoke execute on function public.revoke_entitlement(text, timestamptz) from public, anon, authenticated;
revoke execute on function public.restore_entitlement(text, timestamptz) from public, anon, authenticated;
revoke execute on function public.refund_pack(text) from public, anon, authenticated;
revoke execute on function public.restore_pack(text) from public, anon, authenticated;
revoke execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.revoke_entitlement(text, timestamptz) to service_role;
grant execute on function public.restore_entitlement(text, timestamptz) to service_role;
grant execute on function public.refund_pack(text) to service_role;
grant execute on function public.restore_pack(text) to service_role;
grant execute on function public.record_app_store_notification(uuid, text, text, text, text, text, text, text, timestamptz)
  to service_role;
