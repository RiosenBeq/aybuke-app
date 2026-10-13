-- Optional accounts: Sign in with Apple keeps Pro and credits on every iPhone.
-- ----------------------------------------------------------------------------
-- Everyone still starts as an anonymous user (no sign-up wall). Signing in
-- with Apple (Supabase's native Apple provider) returns a permanent user;
-- merge_accounts() then moves the previous anonymous user's paid credits,
-- subscriptions, jobs and reports into it, and the `account` Edge Function
-- deletes the anonymous user. Daily free credits never move, so new anonymous
-- users can't be farmed for credits.
--
-- apple_accounts  Apple's refresh token for a signed-in user, kept only so that
--                 deleting the account can revoke it, as Apple requires.

create table public.apple_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);
-- No policies: only the service role (Edge Functions) can read or write it.
alter table public.apple_accounts enable row level security;

-- Moves everything that belongs to p_from into p_to. Idempotent: a second run
-- finds nothing left to move. Returns p_to's wallet.
create or replace function public.merge_accounts(p_from uuid, p_to uuid)
returns public.credit_wallets
language plpgsql security definer set search_path = public as $$
declare
  pol record;
  src public.credit_wallets;
  dst public.credit_wallets;
  new_subscription int;
begin
  if p_from = p_to then
    raise exception 'cannot merge an account into itself';
  end if;
  select * into pol from public.credit_policy();
  insert into public.credit_wallets (user_id, daily, daily_period)
    values (p_to, pol.free_daily, (now() at time zone 'utc')::date)
    on conflict (user_id) do nothing;
  -- Lock both wallets in a fixed order so concurrent merges can't deadlock.
  perform 1 from public.credit_wallets where user_id in (p_from, p_to) order by user_id for update;
  select * into src from public.credit_wallets where user_id = p_from;
  select * into dst from public.credit_wallets where user_id = p_to;

  if src.user_id is not null and (src.purchased > 0 or src.subscription > 0) then
    -- Purchased packs add up. Subscription credits belong to the subscription,
    -- which moves too, so keep the larger balance instead of doubling it.
    new_subscription := least(greatest(dst.subscription, src.subscription), pol.pro_rollover_cap);
    update public.credit_wallets
       set purchased = purchased + src.purchased,
           subscription = new_subscription,
           subscription_period_start = coalesce(subscription_period_start, src.subscription_period_start),
           updated_at = now()
     where user_id = p_to;
    insert into public.credit_ledger (user_id, kind, subscription, purchased, source_ref)
      values (p_to, 'admin', new_subscription - dst.subscription, src.purchased, 'merge:' || p_from)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    update public.credit_wallets set purchased = 0, subscription = 0, updated_at = now() where user_id = p_from;
  end if;

  update public.entitlements set user_id = p_to, updated_at = now() where user_id = p_from;
  update public.jobs set user_id = p_to where user_id = p_from;
  update public.credit_ledger set user_id = p_to where user_id = p_from;
  update public.reports set user_id = p_to where user_id = p_from;

  select * into dst from public.credit_wallets where user_id = p_to;
  return dst;
end $$;

revoke execute on function public.merge_accounts(uuid, uuid) from public, anon, authenticated;
