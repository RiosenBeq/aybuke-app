-- Free credits belong to a genuine App Store install; Pro credits to the subscription.
-- ----------------------------------------------------------------------------
-- Anonymous sign-ins are cheap, so free credits per anonymous account could
-- be farmed by a script. Now:
--
--   * Free daily credits live on the App Store install: the app sends
--     StoreKit's signed AppTransaction, ai-image verifies it with Apple's
--     library (Production and Sandbox; Xcode only on a local backend with
--     the dev flag) and SQL keys the allowance by a salted SHA-256 of
--     Apple's appTransactionId, which is the same for every download by one
--     Apple Account. Every anonymous account made by that Apple Account shares
--     one allowance. No valid AppTransaction: no free credits (paid credits
--     still work). A valid one without an appTransactionId gets an allowance
--     for that user alone, counted in a stricter breaker (20261022).
--   * The salt is generated here, lives in the `private` schema (not exposed
--     by any API, readable by no API role) and never leaves the database.
--   * Pro credits live on the subscription (public.entitlements, one row per
--     original transaction), so moving a subscription between anonymous
--     accounts moves its credits instead of granting a new month each time.
--     The yearly plan's free trial week brings trial_credits once; the first
--     paid period brings the full pro_monthly. The $1.99 introductory month
--     is a paid period, so it gets the normal allowance.
--   * Purchased packs stay on the user's wallet. credit_wallets.daily,
--     daily_period, subscription and subscription_period_start are no
--     longer used (kept, always 0, until every function is redeployed).
--
-- Spending order is unchanged: free daily → subscription → packs. Holds now
-- record the install and the subscription they spent from, so refunds go
-- back exactly where they came from.

-- MARK: Salt

create schema if not exists private;
revoke all on schema private from public;
comment on schema private is
  'Server-only data. Not exposed through the Data API; only SECURITY DEFINER functions owned by postgres read it.';

create table private.install_salt (
  singleton boolean primary key default true check (singleton),
  salt bytea not null,
  created_at timestamptz not null default now()
);
-- 32 bytes from pg_strong_random (two v4 UUIDs, 244 random bits).
insert into private.install_salt (salt)
  values (decode(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex'))
  on conflict (singleton) do nothing;
revoke all on table private.install_salt from public;

-- One-way, salted: the same input always gives the same key, and nobody
-- without the salt can tell which input it was.
create function private.keyed_hash(p_kind text, p_value text)
returns text
language sql stable
set search_path = ''
as $$
  select encode(sha256(s.salt || convert_to(p_kind || ':' || p_value, 'UTF8')), 'hex')
    from private.install_salt s
$$;
revoke all on function private.keyed_hash(text, text) from public;

-- MARK: Installs

create table private.app_installs (
  key text primary key,
  -- 'app_store': keyed by the appTransactionId. 'unverified': Apple vouched
  -- for the install but sent no appTransactionId, so it's keyed by the user.
  kind text not null check (kind in ('app_store', 'unverified')),
  environment text,
  daily int not null default 0 check (daily >= 0),
  daily_period date not null default (now() at time zone 'utc')::date,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index app_installs_last_seen_idx on private.app_installs (last_seen_at);
revoke all on table private.app_installs from public;

-- The install for a request, recorded and touched. p_status is ai-image's
-- verdict on the AppTransaction: 'verified', 'missing' or 'invalid'. Null
-- unless Apple vouched for it.
create function private.touch_install(p_user uuid, p_app_transaction_id text, p_status text, p_environment text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
  v_kind text;
begin
  if p_status is distinct from 'verified' then
    return null;
  end if;
  if coalesce(p_app_transaction_id, '') <> '' then
    v_key := private.keyed_hash('app_transaction', p_app_transaction_id);
    v_kind := 'app_store';
  else
    v_key := private.keyed_hash('user', p_user::text);
    v_kind := 'unverified';
  end if;
  insert into private.app_installs as i (key, kind, environment, daily, daily_period)
    values (v_key, v_kind, p_environment, (select p.free_daily from public.credit_policy() p),
            (now() at time zone 'utc')::date)
    on conflict (key) do update
      set last_seen_at = now(), environment = coalesce(excluded.environment, i.environment);
  return v_key;
end $$;
revoke all on function private.touch_install(uuid, text, text, text) from public;

-- Locks the install and refills its free credits on a new UTC day. They
-- never accumulate.
create function private.refresh_install(p_key text)
returns private.app_installs
language plpgsql
set search_path = ''
as $$
declare
  v private.app_installs;
  v_today date := (now() at time zone 'utc')::date;
begin
  select * into v from private.app_installs where key = p_key for update;
  if not found then
    return null;
  end if;
  if v.daily_period < v_today then
    v.daily := (select p.free_daily from public.credit_policy() p);
    v.daily_period := v_today;
    update private.app_installs set daily = v.daily, daily_period = v.daily_period where key = p_key;
  end if;
  return v;
end $$;
revoke all on function private.refresh_install(text) from public;

-- MARK: Subscription credits

alter table public.entitlements
  add column is_trial boolean not null default false,
  add column credits int not null default 0 check (credits >= 0),
  add column credits_period_start timestamptz,
  add column credits_trial boolean not null default false,
  add column trial_granted boolean not null default false;

comment on column public.entitlements.is_trial is
  'The latest verified transaction is the free trial (offerDiscountType FREE_TRIAL).';
comment on column public.entitlements.credits is
  'Subscription credits. They belong to the subscription and move with it.';
comment on column public.entitlements.credits_trial is
  'The current credit period is the free trial week (trial_credits instead of pro_monthly).';
comment on column public.entitlements.trial_granted is
  'Trial credits were granted for this subscription (once ever).';

-- Grants what the subscription is due and locks it: trial credits once for
-- the trial week, the full month from the first paid period, then one month
-- at a time up to the rollover cap. Null when the user has no active
-- subscription; then any credits left on an ended one expire.
create function private.refresh_subscription(p_user uuid)
returns public.entitlements
language plpgsql
set search_path = ''
as $$
declare
  pol record;
  e public.entitlements;
  v_months int;
begin
  select * into pol from public.credit_policy();
  select * into e from public.entitlements
   where user_id = p_user and not revoked and expires_at > now()
   order by expires_at desc
   limit 1
   for update;
  if not found then
    update public.entitlements
       set credits = 0, credits_period_start = null, credits_trial = false, updated_at = now()
     where user_id = p_user and (credits > 0 or credits_period_start is not null);
    return null;
  end if;

  if e.is_trial then
    if not e.trial_granted then
      e.credits := least(e.credits + pol.trial_credits, pol.pro_rollover_cap);
      e.trial_granted := true;
      e.credits_trial := true;
      e.credits_period_start := now();
    end if;
  elsif e.credits_period_start is null or e.credits_trial then
    -- The first paid period, also right after the trial: a full month.
    e.credits := least(e.credits + pol.pro_monthly, pol.pro_rollover_cap);
    e.credits_period_start := now();
    e.credits_trial := false;
  else
    v_months := (extract(year from age(now(), e.credits_period_start)) * 12
               + extract(month from age(now(), e.credits_period_start)))::int;
    if v_months > 0 then
      e.credits := least(e.credits + v_months * pol.pro_monthly, pol.pro_rollover_cap);
      e.credits_period_start := e.credits_period_start + make_interval(months => v_months);
    end if;
  end if;

  update public.entitlements
     set credits = e.credits,
         credits_period_start = e.credits_period_start,
         credits_trial = e.credits_trial,
         trial_granted = e.trial_granted
   where original_transaction_id = e.original_transaction_id;
  return e;
end $$;
revoke all on function private.refresh_subscription(uuid) from public;

-- MARK: Ledger and jobs

alter table public.credit_ledger
  add column install_key text,
  add column entitlement_id text;

alter table public.jobs
  add column install_key text,
  -- Paid (in part) with free daily credits, or a free retry of such a job.
  add column free boolean not null default false,
  add column est_cost_cents int not null default 0;
create index jobs_created_idx on public.jobs (created_at);
create index jobs_install_created_idx on public.jobs (install_key, created_at) where install_key is not null;

-- MARK: Balances

-- What she can spend right now: today's free credits (free tier), her
-- subscription's credits and her packs. Doesn't lock or refill anything.
create function private.balance_of(p_user uuid, p_install text)
returns int
language plpgsql stable
set search_path = ''
as $$
declare
  v_subscription int;
  v_purchased int;
  v_daily int;
begin
  select e.credits into v_subscription from public.entitlements e
   where e.user_id = p_user and not e.revoked and e.expires_at > now()
   order by e.expires_at desc limit 1;
  select w.purchased into v_purchased from public.credit_wallets w where w.user_id = p_user;
  if v_subscription is null and p_install is not null then
    select case when i.daily_period < (now() at time zone 'utc')::date
                then (select p.free_daily from public.credit_policy() p)
                else i.daily end
      into v_daily
      from private.app_installs i where i.key = p_install;
  end if;
  return coalesce(v_daily, 0) + coalesce(v_subscription, 0) + coalesce(v_purchased, 0);
end $$;
revoke all on function private.balance_of(uuid, text) from public;

-- Locks and refreshes everything a job could be paid from. Free daily
-- credits count only on the free tier, with an install and p_allow_daily.
create function private.funds(
  p_user uuid, p_install text, p_allow_daily boolean,
  out daily_credits int, out subscription_credits int, out purchased_credits int,
  out entitlement text, out is_pro boolean, out install_daily int
)
language plpgsql
set search_path = ''
as $$
declare
  e public.entitlements;
  i private.app_installs;
begin
  insert into public.credit_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  select w.purchased into purchased_credits from public.credit_wallets w where w.user_id = p_user for update;
  e := private.refresh_subscription(p_user);
  is_pro := e.original_transaction_id is not null;
  entitlement := e.original_transaction_id;
  subscription_credits := coalesce(e.credits, 0);
  install_daily := 0;
  if p_install is not null and not is_pro then
    i := private.refresh_install(p_install);
    install_daily := coalesce(i.daily, 0);
  end if;
  daily_credits := case when p_allow_daily then install_daily else 0 end;
end $$;
revoke all on function private.funds(uuid, text, boolean) from public;

-- Spends p_cost (the caller checked it's covered): free daily → subscription
-- → packs, and records the hold with where it came from.
create function private.hold(
  p_user uuid, p_job uuid, p_cost int, p_install text, p_daily int, p_subscription int, p_entitlement text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  d int := least(greatest(p_daily, 0), p_cost);
  s int;
  p int;
begin
  s := least(greatest(p_subscription, 0), p_cost - d);
  p := p_cost - d - s;
  if d > 0 then
    update private.app_installs set daily = daily - d where key = p_install;
  end if;
  if s > 0 then
    update public.entitlements set credits = credits - s, updated_at = now() where original_transaction_id = p_entitlement;
  end if;
  if p > 0 then
    update public.credit_wallets set purchased = purchased - p, updated_at = now() where user_id = p_user;
  end if;
  insert into public.credit_ledger (user_id, job_id, kind, daily, subscription, purchased, install_key, entitlement_id)
    values (p_user, p_job, 'hold', -d, -s, -p, p_install, p_entitlement);
  return jsonb_build_object('daily', d, 'subscription', s, 'purchased', p);
end $$;
revoke all on function private.hold(uuid, uuid, int, text, int, int, text) from public;

-- The old per-user daily wallet and reservation.
drop function if exists public.refresh_wallet(uuid, boolean);
drop function if exists public.reserve_credits(uuid, boolean, int, uuid);
drop function if exists public.grant_pack(uuid, int, text);

-- Reserves credits for a job and returns the balance left, or raises
-- INSUFFICIENT_CREDITS. ai-image admits jobs with admit_job() (20261022),
-- which does the same after its checks.
create function public.reserve_credits(
  p_user uuid, p_cost int, p_job uuid, p_install text default null, p_allow_daily boolean default true
)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  f record;
begin
  select * into f from private.funds(p_user, p_install, p_allow_daily);
  if p_cost > 0 then
    if f.daily_credits + f.subscription_credits + f.purchased_credits < p_cost then
      raise exception 'INSUFFICIENT_CREDITS' using errcode = 'P0001';
    end if;
    perform private.hold(p_user, p_job, p_cost, p_install, f.daily_credits, f.subscription_credits, f.entitlement);
  end if;
  return private.balance_of(p_user, p_install);
end $$;

-- Refunds exactly what a job was charged, to where it came from, at most
-- once. Returns the balance.
create or replace function public.release_credits(p_job uuid)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  h public.credit_ledger;
  pol record;
  v_entitlement text;
begin
  select * into h from public.credit_ledger where job_id = p_job and kind = 'hold' limit 1;
  if not found then
    return null;
  end if;
  select * into pol from public.credit_policy();
  insert into public.credit_ledger (user_id, job_id, kind, daily, subscription, purchased, source_ref, install_key, entitlement_id)
    values (h.user_id, p_job, 'release', -h.daily, -h.subscription, -h.purchased, p_job::text, h.install_key, h.entitlement_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if found then
    if h.daily <> 0 and h.install_key is not null then
      update private.app_installs set daily = least(daily - h.daily, pol.free_daily) where key = h.install_key;
    end if;
    if h.subscription <> 0 then
      -- Holds from before this migration name no subscription: the newest one.
      v_entitlement := coalesce(h.entitlement_id, (
        select e.original_transaction_id from public.entitlements e
         where e.user_id = h.user_id order by e.expires_at desc nulls last limit 1));
      update public.entitlements
         set credits = least(credits - h.subscription, pol.pro_rollover_cap), updated_at = now()
       where original_transaction_id = v_entitlement;
    end if;
    if h.purchased <> 0 then
      update public.credit_wallets set purchased = purchased - h.purchased, updated_at = now() where user_id = h.user_id;
    end if;
  end if;
  return private.balance_of(h.user_id, h.install_key);
end $$;

-- Grants a consumable credit pack once per Apple transaction id. Returns the
-- balance, with today's free credits when the request named its install.
create function public.grant_pack(
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
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  insert into public.credit_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  insert into public.credit_ledger (user_id, kind, purchased, source_ref)
    values (p_user, 'grant_pack', p_credits, p_transaction_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if found then
    update public.credit_wallets set purchased = purchased + p_credits, updated_at = now() where user_id = p_user;
  end if;
  return private.balance_of(p_user, v_key);
end $$;

-- The balance after a job, for the poll that finishes it: the job's install.
create function public.job_balance(p_job uuid, p_user uuid)
returns int
language sql stable security definer
set search_path = ''
as $$
  select private.balance_of(p_user, (select j.install_key from public.jobs j where j.id = p_job and j.user_id = p_user))
$$;

-- DELETE /ai-image?job_id=… (see 20261017): unchanged, but the balance it
-- reports includes the job's install.
create or replace function public.cancel_job(p_job uuid, p_user uuid, p_cancel boolean default false)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  j public.jobs;
begin
  select * into j from public.jobs where id = p_job and user_id = p_user for update;
  if not found then
    return null;
  end if;
  if j.status in ('queued', 'processing') or (j.status = 'completed' and j.delivered_at is null) then
    update public.jobs set status = 'cancelled', outputs = null, updated_at = now() where id = p_job;
    perform public.release_credits(p_job);
  elsif j.status = 'completed' and p_cancel then
    perform public.settle_unconfirmed(p_job);
  elsif j.status = 'completed' then
    update public.jobs set outputs = null, updated_at = now() where id = p_job;
  end if;
  return jsonb_build_object(
    'status', (select status from public.jobs where id = p_job),
    'credits_remaining', private.balance_of(p_user, j.install_key)
  );
end $$;

-- MARK: Accounts

-- Sign in with Apple (see 20261013): purchased packs add up; subscription
-- credits ride along with the subscription; free daily credits belong to
-- the App Store install, not to either account.
create or replace function public.merge_accounts(p_from uuid, p_to uuid)
returns public.credit_wallets
language plpgsql security definer
set search_path = ''
as $$
declare
  src public.credit_wallets;
  dst public.credit_wallets;
begin
  if p_from = p_to then
    raise exception 'cannot merge an account into itself';
  end if;
  insert into public.credit_wallets (user_id) values (p_to) on conflict (user_id) do nothing;
  -- Lock both wallets in a fixed order so concurrent merges can't deadlock.
  perform 1 from public.credit_wallets where user_id in (p_from, p_to) order by user_id for update;
  select * into src from public.credit_wallets where user_id = p_from;

  if src.user_id is not null and src.purchased > 0 then
    update public.credit_wallets set purchased = purchased + src.purchased, updated_at = now() where user_id = p_to;
    insert into public.credit_ledger (user_id, kind, purchased, source_ref)
      values (p_to, 'admin', src.purchased, 'merge:' || p_from)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    update public.credit_wallets set purchased = 0, updated_at = now() where user_id = p_from;
  end if;

  update public.entitlements set user_id = p_to, updated_at = now() where user_id = p_from;
  update public.jobs set user_id = p_to where user_id = p_from;
  update public.credit_ledger set user_id = p_to where user_id = p_from;
  update public.reports set user_id = p_to where user_id = p_from;

  select * into dst from public.credit_wallets where user_id = p_to;
  return dst;
end $$;

-- MARK: Existing balances

-- Subscription credits move from the wallet to the subscription they came
-- from (the newest one), capped at the new rollover cap.
update public.entitlements e
   set credits = least(w.subscription, (select p.pro_rollover_cap from public.credit_policy() p)),
       credits_period_start = coalesce(w.subscription_period_start, now())
  from public.credit_wallets w
 where w.user_id = e.user_id
   and w.subscription > 0
   and e.original_transaction_id = (
     select x.original_transaction_id from public.entitlements x
      where x.user_id = e.user_id order by x.expires_at desc nulls last limit 1);
-- Daily credits now come from the install, at the new allowance.
update public.credit_wallets
   set daily = 0, subscription = 0, subscription_period_start = null, updated_at = now()
 where daily <> 0 or subscription <> 0 or subscription_period_start is not null;

comment on column public.credit_wallets.daily is 'Unused since 20261021 (free credits live on private.app_installs); always 0.';
comment on column public.credit_wallets.daily_period is 'Unused since 20261021.';
comment on column public.credit_wallets.subscription is 'Unused since 20261021 (subscription credits live on public.entitlements); always 0.';
comment on column public.credit_wallets.subscription_period_start is 'Unused since 20261021.';

-- MARK: Privileges

revoke execute on function public.reserve_credits(uuid, int, uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public.release_credits(uuid) from public, anon, authenticated;
revoke execute on function public.grant_pack(uuid, int, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.job_balance(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.cancel_job(uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.merge_accounts(uuid, uuid) from public, anon, authenticated;
grant execute on function public.reserve_credits(uuid, int, uuid, text, boolean) to service_role;
grant execute on function public.release_credits(uuid) to service_role;
grant execute on function public.grant_pack(uuid, int, text, text, text, text) to service_role;
grant execute on function public.job_balance(uuid, uuid) to service_role;
grant execute on function public.cancel_job(uuid, uuid, boolean) to service_role;
grant execute on function public.merge_accounts(uuid, uuid) to service_role;
