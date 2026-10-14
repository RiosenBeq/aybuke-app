-- Rewarded ads: one credit for a watched ad, at most 2 a day (UTC).
-- ----------------------------------------------------------------------------
-- The flow (functions/ad-reward):
--   1. A free member who is out of credits asks for a reward token
--      (issue_ad_reward_token). The app hands AdMob only this random token,
--      as the server-side verification custom data, never her user id.
--   2. AdMob calls ad-reward with a signed query string. The function checks
--      the ECDSA signature against Google's published keys and the ad unit
--      against ADMOB_REWARDED_AD_UNIT, then redeem_ad_reward() maps the token
--      to the user and grants one credit through the ledger (kind
--      'ad_reward'), once per AdMob transaction id.
--   3. The app polls ad_reward_status() until the credit lands.
--
-- Ad credits go into the daily bucket: like the free daily credits they're
-- spent first and don't carry over to the next UTC day.
--
-- ad_reward_tokens  single-use, valid for 30 minutes; deleted a day after
--                   they expire (sweep_ad_rewards, or when she asks again).
-- ad_rewards        one row per verified AdMob transaction: idempotency and
--                   the daily cap. Deleted after 30 days (sweep_ad_rewards).
-- Service role only: RLS on, no policies, and no grants to clients.

alter table public.credit_ledger drop constraint if exists credit_ledger_kind_check;
alter table public.credit_ledger add constraint credit_ledger_kind_check
  check (kind in ('hold', 'release', 'grant_pack', 'admin', 'ad_reward'));

-- Change these numbers to retune ads without an app update; the app's copy
-- reads the cap from the server ("2 left today").
create or replace function public.ad_reward_policy(out daily_cap int, out credits int, out token_ttl interval)
language sql immutable set search_path = '' as $$
  select 2, 1, interval '30 minutes'
$$;

create table public.ad_reward_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz
);
create index ad_reward_tokens_user_idx on public.ad_reward_tokens (user_id, created_at desc);
create index ad_reward_tokens_expiry_idx on public.ad_reward_tokens (expires_at);

create table public.ad_rewards (
  transaction_id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- One reward per token. Not a foreign key: tokens are swept sooner.
  token_id uuid not null unique,
  ad_unit text not null,
  reward_amount int,
  reward_item text,
  credits int not null default 0 check (credits >= 0),
  status text not null check (status in ('granted', 'capped', 'expired')),
  -- The UTC day the token was issued: the day the cap counts it on.
  reward_day date not null,
  created_at timestamptz not null default now()
);
create index ad_rewards_user_day_idx on public.ad_rewards (user_id, reward_day);
create index ad_rewards_created_idx on public.ad_rewards (created_at);

-- No policies: only the service role (Edge Functions) can read or write them.
alter table public.ad_reward_tokens enable row level security;
alter table public.ad_rewards enable row level security;
revoke all on table public.ad_reward_tokens, public.ad_rewards from public, anon, authenticated;
grant all on table public.ad_reward_tokens, public.ad_rewards to service_role;

-- Ad credits granted on today's UTC day plus tokens still waiting for AdMob,
-- so she's never shown an ad that can't pay any more.
create or replace function public.ad_rewards_used_today(p_user uuid)
returns int
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.ad_rewards r
      where r.user_id = p_user and r.status = 'granted' and r.reward_day = (now() at time zone 'utc')::date)
    + (select count(*) from public.ad_reward_tokens k
      where k.user_id = p_user and k.redeemed_at is null and k.expires_at > now()
        and k.created_at >= ((now() at time zone 'utc')::date::timestamp at time zone 'utc'))
  )::int
$$;

-- A single-use token for the next rewarded ad: free members only, only when
-- they're out of credits, and only while today's cap allows another. The
-- wallet stays locked until the transaction ends, so the checks can't race.
create or replace function public.issue_ad_reward_token(p_user uuid, p_is_pro boolean)
returns table (reward_token uuid, valid_until timestamptz, remaining_today int)
language plpgsql security definer set search_path = public as $$
declare
  pol record;
  w public.credit_wallets;
  used int;
  t public.ad_reward_tokens;
begin
  if p_is_pro then
    raise exception 'AD_NOT_ELIGIBLE' using errcode = 'P0001';
  end if;
  select * into pol from public.ad_reward_policy();
  w := public.refresh_wallet(p_user, false);
  if w.daily + w.subscription + w.purchased > 0 then
    raise exception 'AD_HAS_CREDITS' using errcode = 'P0001';
  end if;
  delete from public.ad_reward_tokens k where k.user_id = p_user and k.expires_at < now() - interval '1 day';
  used := public.ad_rewards_used_today(p_user);
  if used >= pol.daily_cap then
    raise exception 'AD_DAILY_CAP' using errcode = 'P0001';
  end if;
  insert into public.ad_reward_tokens (user_id, expires_at)
    values (p_user, now() + pol.token_ttl)
    returning * into t;
  return query select t.id, t.expires_at, pol.daily_cap - used - 1;
end $$;

-- AdMob's verified callback. Grants the credit once per transaction id and
-- once per token. Outcomes: 'granted'; 'capped' (today's ad credits were
-- already paid); 'expired' (the token timed out); 'duplicate' (this
-- transaction was handled before); 'used' (the token already paid for
-- another transaction); 'unknown' (no such token).
create or replace function public.redeem_ad_reward(
  p_transaction_id text, p_token uuid, p_ad_unit text, p_reward_amount int, p_reward_item text
)
returns table (outcome text, credits_remaining int)
language plpgsql security definer set search_path = public as $$
declare
  pol record;
  t public.ad_reward_tokens;
  token_day date;
  is_pro boolean;
  granted_that_day int;
  result text;
  balance int;
begin
  select * into pol from public.ad_reward_policy();
  if exists (select 1 from public.ad_rewards r where r.transaction_id = p_transaction_id) then
    return query select 'duplicate'::text, null::int;
    return;
  end if;
  select * into t from public.ad_reward_tokens k where k.id = p_token for update;
  if not found then
    return query select 'unknown'::text, null::int;
    return;
  end if;
  -- A retry that waited for the first callback's lock.
  if exists (select 1 from public.ad_rewards r where r.transaction_id = p_transaction_id) then
    return query select 'duplicate'::text, null::int;
    return;
  end if;
  if t.redeemed_at is not null then
    return query select 'used'::text, null::int;
    return;
  end if;

  token_day := (t.created_at at time zone 'utc')::date;
  is_pro := exists (
    select 1 from public.entitlements e
     where e.user_id = t.user_id and not e.revoked and e.expires_at > now()
  );
  -- Locks the wallet too, so two callbacks for one user can't both pass the cap.
  perform public.refresh_wallet(t.user_id, is_pro);
  if t.expires_at < now() then
    result := 'expired';
  else
    select count(*) into granted_that_day from public.ad_rewards r
     where r.user_id = t.user_id and r.status = 'granted' and r.reward_day = token_day;
    result := case when granted_that_day >= pol.daily_cap then 'capped' else 'granted' end;
  end if;

  insert into public.ad_rewards (transaction_id, user_id, token_id, ad_unit, reward_amount, reward_item, credits, status, reward_day)
    values (p_transaction_id, t.user_id, t.id, p_ad_unit, p_reward_amount, p_reward_item,
            case when result = 'granted' then pol.credits else 0 end, result, token_day);
  update public.ad_reward_tokens set redeemed_at = now() where id = t.id;
  if result = 'granted' then
    insert into public.credit_ledger (user_id, kind, daily, source_ref)
      values (t.user_id, 'ad_reward', pol.credits, 'admob:' || p_transaction_id)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    if found then
      update public.credit_wallets set daily = daily + pol.credits, updated_at = now() where user_id = t.user_id;
    end if;
  end if;
  select w.daily + w.subscription + w.purchased into balance from public.credit_wallets w where w.user_id = t.user_id;
  return query select result, balance;
end $$;

-- The app's poll after an ad: 'pending' until AdMob's callback arrives, then
-- the reward's outcome ('granted', 'capped' or 'expired'); 'expired' also
-- for a token that timed out without one, 'unknown' for someone else's.
create or replace function public.ad_reward_status(p_user uuid, p_token uuid)
returns table (outcome text, remaining_today int)
language plpgsql stable security definer set search_path = public as $$
declare
  pol record;
  t public.ad_reward_tokens;
  reward_status text;
  result text;
begin
  select * into pol from public.ad_reward_policy();
  select r.status into reward_status from public.ad_rewards r where r.token_id = p_token and r.user_id = p_user;
  if reward_status is not null then
    result := reward_status;
  else
    select * into t from public.ad_reward_tokens k where k.id = p_token and k.user_id = p_user;
    if not found then
      result := 'unknown';
    elsif t.expires_at < now() then
      result := 'expired';
    else
      result := 'pending';
    end if;
  end if;
  return query select result, greatest(0, pol.daily_cap - public.ad_rewards_used_today(p_user));
end $$;

-- The ad closed before it paid out: the token goes, and so does its place in
-- today's cap. Only her own unredeemed tokens.
create or replace function public.release_ad_reward_token(p_user uuid, p_token uuid)
returns boolean
language sql security definer set search_path = public as $$
  with gone as (
    delete from public.ad_reward_tokens k
     where k.id = p_token and k.user_id = p_user and k.redeemed_at is null
    returning 1
  )
  select exists (select 1 from gone)
$$;

-- Housekeeping. Schedule with pg_cron next to sweep_jobs, e.g.:
--   select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');
create or replace function public.sweep_ad_rewards()
returns void
language sql security definer set search_path = public as $$
  delete from public.ad_reward_tokens where expires_at < now() - interval '1 day';
  delete from public.ad_rewards where created_at < now() - interval '30 days';
$$;

revoke execute on function public.ad_reward_policy() from public, anon, authenticated;
revoke execute on function public.ad_rewards_used_today(uuid) from public, anon, authenticated;
revoke execute on function public.issue_ad_reward_token(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.redeem_ad_reward(text, uuid, text, int, text) from public, anon, authenticated;
revoke execute on function public.ad_reward_status(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.release_ad_reward_token(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.sweep_ad_rewards() from public, anon, authenticated;
grant execute on function public.ad_reward_policy(), public.ad_rewards_used_today(uuid),
  public.issue_ad_reward_token(uuid, boolean), public.redeem_ad_reward(text, uuid, text, int, text),
  public.ad_reward_status(uuid, uuid), public.release_ad_reward_token(uuid, uuid), public.sweep_ad_rewards()
  to service_role;
