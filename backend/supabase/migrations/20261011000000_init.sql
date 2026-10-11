-- Glowlit backend schema
-- ----------------------------------------------------------------------------
-- credit_wallets  one row per user: daily free credits, Pro monthly allowance
--                 (with one month of rollover) and purchased packs.
-- credit_ledger   append-only audit trail; holds/releases are exact per bucket.
-- jobs            one row per AI job, mirroring the fal.ai queue request.
-- entitlements    Apple subscriptions verified from signed transactions.
--
-- Clients can only SELECT their own rows (RLS). Every write goes through the
-- SECURITY DEFINER functions below, which only the service role (Edge
-- Functions) may execute. Credit rules mirror ios/Packages/AppCore Credits.swift.

create table public.credit_wallets (
  user_id uuid primary key references auth.users (id) on delete cascade,
  daily int not null default 0 check (daily >= 0),
  daily_period date not null default (now() at time zone 'utc')::date,
  subscription int not null default 0 check (subscription >= 0),
  subscription_period_start timestamptz,
  purchased int not null default 0 check (purchased >= 0),
  updated_at timestamptz not null default now()
);

create table public.credit_ledger (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  job_id uuid,
  kind text not null check (kind in ('hold', 'release', 'grant_pack', 'admin')),
  daily int not null default 0,
  subscription int not null default 0,
  purchased int not null default 0,
  source_ref text,
  created_at timestamptz not null default now()
);
create unique index credit_ledger_source_ref_key on public.credit_ledger (kind, source_ref) where source_ref is not null;
create index credit_ledger_job_idx on public.credit_ledger (job_id);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  operation text not null,
  template_id text,
  endpoint text not null,
  cost int not null default 0,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'completed', 'failed', 'cancelled')),
  fal_request_id text unique,
  status_url text,
  response_url text,
  cancel_url text,
  outputs jsonb,
  error_code text,
  error_message text,
  retry_of uuid references public.jobs (id) on delete set null,
  retried boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index jobs_user_created_idx on public.jobs (user_id, created_at desc);
create index jobs_pending_idx on public.jobs (status, created_at) where status in ('queued', 'processing');

create table public.entitlements (
  original_transaction_id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null,
  expires_at timestamptz,
  revoked boolean not null default false,
  environment text,
  updated_at timestamptz not null default now()
);
create index entitlements_user_idx on public.entitlements (user_id);

-- Row-level security: read-only access to your own rows.
alter table public.credit_wallets enable row level security;
alter table public.credit_ledger enable row level security;
alter table public.jobs enable row level security;
alter table public.entitlements enable row level security;

create policy "Users read their wallet" on public.credit_wallets for select using ((select auth.uid()) = user_id);
create policy "Users read their ledger" on public.credit_ledger for select using ((select auth.uid()) = user_id);
create policy "Users read their jobs" on public.jobs for select using ((select auth.uid()) = user_id);
create policy "Users read their entitlements" on public.entitlements for select using ((select auth.uid()) = user_id);

-- ----------------------------------------------------------------------------
-- Credit policy. Change these numbers to retune pricing without an app update.
-- ----------------------------------------------------------------------------
create or replace function public.credit_policy(out free_daily int, out pro_monthly int, out pro_rollover_cap int)
language sql immutable as $$
  select 3, 100, 200
$$;

-- Applies daily refills, monthly Pro grants (with rollover) and expiry. Locks the row.
create or replace function public.refresh_wallet(p_user uuid, p_is_pro boolean)
returns public.credit_wallets
language plpgsql security definer set search_path = public as $$
declare
  w public.credit_wallets;
  pol record;
  today date := (now() at time zone 'utc')::date;
  months int;
begin
  select * into pol from public.credit_policy();
  insert into public.credit_wallets (user_id, daily, daily_period)
    values (p_user, case when p_is_pro then 0 else pol.free_daily end, today)
    on conflict (user_id) do nothing;
  select * into w from public.credit_wallets where user_id = p_user for update;

  if w.daily_period < today then
    -- Daily credits are a free-tier perk and never accumulate.
    w.daily := case when p_is_pro then 0 else pol.free_daily end;
    w.daily_period := today;
  end if;

  if p_is_pro then
    if w.subscription_period_start is null then
      w.subscription := least(w.subscription + pol.pro_monthly, pol.pro_rollover_cap);
      w.subscription_period_start := now();
    else
      months := (extract(year from age(now(), w.subscription_period_start)) * 12
               + extract(month from age(now(), w.subscription_period_start)))::int;
      if months > 0 then
        w.subscription := least(w.subscription + months * pol.pro_monthly, pol.pro_rollover_cap);
        w.subscription_period_start := w.subscription_period_start + make_interval(months => months);
      end if;
    end if;
  elsif w.subscription_period_start is not null then
    -- Subscription credits end with the subscription; purchased packs stay.
    w.subscription := 0;
    w.subscription_period_start := null;
    w.daily := pol.free_daily;
    w.daily_period := today;
  end if;

  update public.credit_wallets
     set daily = w.daily,
         daily_period = w.daily_period,
         subscription = w.subscription,
         subscription_period_start = w.subscription_period_start,
         updated_at = now()
   where user_id = p_user
  returning * into w;
  return w;
end $$;

-- Reserves credits for a job, spending expiring credits first
-- (daily → subscription → purchased). Returns the remaining balance.
create or replace function public.reserve_credits(p_user uuid, p_is_pro boolean, p_cost int, p_job uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  w public.credit_wallets;
  remaining int := p_cost;
  d int;
  s int;
  p int;
begin
  w := public.refresh_wallet(p_user, p_is_pro);
  if p_cost <= 0 then
    return w.daily + w.subscription + w.purchased;
  end if;
  if w.daily + w.subscription + w.purchased < p_cost then
    raise exception 'INSUFFICIENT_CREDITS' using errcode = 'P0001';
  end if;
  d := least(w.daily, remaining);        remaining := remaining - d;
  s := least(w.subscription, remaining); remaining := remaining - s;
  p := least(w.purchased, remaining);
  update public.credit_wallets
     set daily = daily - d, subscription = subscription - s, purchased = purchased - p, updated_at = now()
   where user_id = p_user;
  insert into public.credit_ledger (user_id, job_id, kind, daily, subscription, purchased)
    values (p_user, p_job, 'hold', -d, -s, -p);
  return w.daily + w.subscription + w.purchased - p_cost;
end $$;

-- Refunds exactly what a job was charged, at most once. Returns the balance.
create or replace function public.release_credits(p_job uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  h public.credit_ledger;
  pol record;
  balance int;
begin
  select * into h from public.credit_ledger where job_id = p_job and kind = 'hold' limit 1;
  if not found then
    return null;
  end if;
  select * into pol from public.credit_policy();
  insert into public.credit_ledger (user_id, job_id, kind, daily, subscription, purchased, source_ref)
    values (h.user_id, p_job, 'release', -h.daily, -h.subscription, -h.purchased, p_job::text)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if found then
    update public.credit_wallets
       set daily = least(daily - h.daily, pol.free_daily),
           subscription = least(subscription - h.subscription, pol.pro_rollover_cap),
           purchased = purchased - h.purchased,
           updated_at = now()
     where user_id = h.user_id;
  end if;
  select daily + subscription + purchased into balance from public.credit_wallets where user_id = h.user_id;
  return balance;
end $$;

-- Grants a consumable credit pack once per Apple transaction id. Returns the balance.
create or replace function public.grant_pack(p_user uuid, p_credits int, p_transaction_id text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  pol record;
  balance int;
begin
  select * into pol from public.credit_policy();
  insert into public.credit_wallets (user_id, daily, daily_period)
    values (p_user, pol.free_daily, (now() at time zone 'utc')::date)
    on conflict (user_id) do nothing;
  insert into public.credit_ledger (user_id, kind, purchased, source_ref)
    values (p_user, 'grant_pack', p_credits, p_transaction_id)
    on conflict (kind, source_ref) where source_ref is not null do nothing;
  if found then
    update public.credit_wallets set purchased = purchased + p_credits, updated_at = now() where user_id = p_user;
  end if;
  select daily + subscription + purchased into balance from public.credit_wallets where user_id = p_user;
  return balance;
end $$;

-- Fails jobs that never finished (client gone, provider stuck) and refunds them;
-- deletes job rows after 30 days (outputs on the provider CDN expire after 1 hour).
-- Schedule with pg_cron, e.g.: select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
create or replace function public.sweep_jobs()
returns void
language plpgsql security definer set search_path = public as $$
declare
  j record;
begin
  for j in
    update public.jobs
       set status = 'failed', error_code = 'timeout', error_message = 'The job timed out.', updated_at = now()
     where status in ('queued', 'processing') and created_at < now() - interval '15 minutes'
    returning id
  loop
    perform public.release_credits(j.id);
  end loop;
  delete from public.jobs where created_at < now() - interval '30 days';
end $$;

revoke execute on function public.refresh_wallet(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.reserve_credits(uuid, boolean, int, uuid) from public, anon, authenticated;
revoke execute on function public.release_credits(uuid) from public, anon, authenticated;
revoke execute on function public.grant_pack(uuid, int, text) from public, anon, authenticated;
revoke execute on function public.sweep_jobs() from public, anon, authenticated;
