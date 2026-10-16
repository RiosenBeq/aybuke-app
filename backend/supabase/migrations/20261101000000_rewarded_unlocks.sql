-- Rewarded unlocks: one try of a Pro look or style for a watched ad.
-- ----------------------------------------------------------------------------
-- Free members (13+, iPhone and iPad, not Pro) can watch a rewarded ad to try
-- one Pro-only look (a restyle template) or Create style once, instead of
-- getting a credit. It reuses the rewarded ad unit and its server-side
-- verification (functions/ad-reward, _shared/admob.ts, 20261019 and 20261023):
-- only AdMob's signed callback grants anything, never the app.
--
--   1. POST /ad-reward { kind: "unlock", template_id | style_id }: ad-reward
--      checks the id is a Pro one in the catalog, then
--      issue_ad_unlock_token() refuses what issue_ad_reward_token() refuses
--      (Pro, no verified install, a block or a cool-down), a member with no
--      credit to spend on the try (it costs one, like any look), a time when
--      AI is paused for everyone, and a try past unlock_daily_cap: 1 a day
--      (UTC) per user and per install, counted apart from the 2 credit ads.
--   2. AdMob's callback: redeem_ad_reward() pays by the token's kind. For an
--      unlock it records one unused try of that id for her (private.ad_unlocks),
--      valid for unlock_ttl (30 minutes) from the grant, and adds no credit.
--   3. ai-image asks ad_unlock_available() before anything else (no prompt
--      check, no booking without a try), then admits the job through
--      admit_unlocked_job(): admit_job() with every gate as usual (blocks,
--      pauses, limits, the prompt policy, the credit), the try spent with the
--      job in the same transaction. A free retry of a result a try paid for
--      needs no new try.
--   4. A refunded job (release_credits(), the only refund path) gives its try
--      back for whatever is left of its 30 minutes.
--
-- private.ad_unlocks keeps the user, the look or style, the AdMob transaction,
-- the times and the job that spent it, and is deleted a day after the try ends
-- (sweep_ad_rewards()), or with the account.

-- MARK: Policy

-- The numbers, as before plus the tries. Change them here (a new migration
-- that replaces the function) to retune ads without an app update.
drop function if exists public.ad_reward_policy();
create function public.ad_reward_policy(
  out daily_cap int,
  out credits int,
  out token_ttl interval,
  out unlock_daily_cap int,
  out unlock_ttl interval
)
language sql immutable
set search_path = ''
as $$
  select
    2,                     -- daily_cap: ads for a credit a day (UTC), per user and per App Store install
    1,                     -- credits: per ad
    interval '30 minutes', -- token_ttl: a token waits this long for AdMob's callback
    1,                     -- unlock_daily_cap: ads for a Pro try a day (UTC), per user and per install
    interval '30 minutes'  -- unlock_ttl: a granted try can start a job for this long
$$;

-- MARK: Tables

-- Which reward a token and a confirmed ad are for. Every older row is a credit.
alter table public.ad_reward_tokens
  add column kind text not null default 'credit' check (kind in ('credit', 'unlock')),
  add column unlock_type text check (unlock_type in ('template', 'style')),
  add column unlock_id text check (char_length(unlock_id) between 1 and 100),
  add constraint ad_reward_tokens_unlock_item
    check ((kind = 'unlock') = (unlock_type is not null and unlock_id is not null));
alter table public.ad_rewards
  add column kind text not null default 'credit' check (kind in ('credit', 'unlock'));

create table private.ad_unlocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The confirmed ad (public.ad_rewards.transaction_id): one try per ad.
  transaction_id text not null unique,
  -- 'template': a Pro one-tap look (restyle). 'style': a Pro Create style.
  unlock_type text not null check (unlock_type in ('template', 'style')),
  unlock_id text not null check (char_length(unlock_id) between 1 and 100),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  -- The job that spent it: null while unused, and again once that job is refunded.
  job_id uuid,
  used_at timestamptz,
  check ((job_id is null) = (used_at is null))
);
create index ad_unlocks_user_item_idx on private.ad_unlocks (user_id, unlock_type, unlock_id);
create index ad_unlocks_job_idx on private.ad_unlocks (job_id) where job_id is not null;
create index ad_unlocks_expiry_idx on private.ad_unlocks (expires_at);
alter table private.ad_unlocks enable row level security;
revoke all on table private.ad_unlocks from public, anon, authenticated;

-- MARK: Helpers

-- When cloud AI takes jobs again, or null when it does now: the 'all' pause
-- (the owner's, the provider's billing pause or the safety breaker, as
-- admit_job() reads it) or the day's hard breaker. A try that can't start a
-- job within its 30 minutes isn't offered.
create function private.ai_paused_until()
returns timestamptz
language sql stable
set search_path = ''
as $$
  select coalesce(
    (select max(s.paused_until) from private.ai_switches s where s.scope = 'all' and s.paused_until > now()),
    (select private.next_utc_day()
       from private.ai_usage_daily d, public.credit_policy() p
      where d.day = (now() at time zone 'utc')::date and d.total_jobs >= p.all_jobs_daily_cap))
$$;
revoke all on function private.ai_paused_until() from public;

-- Ads paid today plus tokens still waiting for AdMob, per user and per
-- install, for one kind of reward: 'credit' (the default, as before) or
-- 'unlock'. Each kind has its own cap. The larger count counts, so she's
-- never shown an ad that can't pay.
drop function if exists public.ad_rewards_used_today(uuid, text);
create function public.ad_rewards_used_today(p_user uuid, p_install text default null, p_kind text default 'credit')
returns int
language sql stable security definer
set search_path = ''
as $$
  select greatest(
    (select count(*) from public.ad_rewards r
      where r.user_id = p_user and r.kind = p_kind and r.status = 'granted'
        and r.reward_day = (now() at time zone 'utc')::date)
    + (select count(*) from public.ad_reward_tokens k
        where k.user_id = p_user and k.kind = p_kind and k.redeemed_at is null and k.expires_at > now()
          and k.created_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc'),
    case when p_install is null then 0 else
      (select count(*) from public.ad_rewards r
        where r.install_key = p_install and r.kind = p_kind and r.status = 'granted'
          and r.reward_day = (now() at time zone 'utc')::date)
      + (select count(*) from public.ad_reward_tokens k
          where k.install_key = p_install and k.kind = p_kind and k.redeemed_at is null and k.expires_at > now()
            and k.created_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc')
    end
  )::int
$$;

-- MARK: Tokens

-- A single-use token for the ad that unlocks one try of a Pro look or style.
-- Free members with a verified install who aren't resting or blocked, as for
-- a credit; but she needs a credit to spend on the try, AI must be taking
-- jobs, and the cap is unlock_daily_cap. ad-reward checks the id against the
-- catalog first. The wallet and the install stay locked until the
-- transaction ends, so the checks can't race.
create function public.issue_ad_unlock_token(
  p_user uuid, p_is_pro boolean, p_unlock_type text, p_unlock_id text,
  p_app_transaction_id text default null, p_install_status text default 'missing', p_install_environment text default null
)
returns table (reward_token uuid, valid_until timestamptz, remaining_today int)
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
  f record;
  used int;
  t public.ad_reward_tokens;
begin
  if p_unlock_type is null or p_unlock_type not in ('template', 'style')
     or coalesce(p_unlock_id, '') = '' or char_length(p_unlock_id) > 100 then
    raise exception 'AD_BAD_UNLOCK' using errcode = 'P0001';
  end if;
  if p_is_pro then
    raise exception 'AD_NOT_ELIGIBLE' using errcode = 'P0001';
  end if;
  select * into pol from public.ad_reward_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  if v_key is null then
    raise exception 'AD_NO_INSTALL' using errcode = 'P0001';
  end if;
  select * into f from private.funds(p_user, v_key, true);
  if f.is_pro or private.active_block(p_user, v_key) or private.cooldown_until(p_user, v_key) is not null then
    raise exception 'AD_NOT_ELIGIBLE' using errcode = 'P0001';
  end if;
  if private.ai_paused_until() is not null then
    raise exception 'AD_AI_PAUSED' using errcode = 'P0001';
  end if;
  if f.daily_credits + f.subscription_credits + f.purchased_credits < 1 then
    raise exception 'AD_NO_CREDITS' using errcode = 'P0001';
  end if;
  delete from public.ad_reward_tokens k where k.user_id = p_user and k.expires_at < now() - interval '1 day';
  used := public.ad_rewards_used_today(p_user, v_key, 'unlock');
  if used >= pol.unlock_daily_cap then
    raise exception 'AD_DAILY_CAP' using errcode = 'P0001';
  end if;
  insert into public.ad_reward_tokens (user_id, install_key, expires_at, kind, unlock_type, unlock_id)
    values (p_user, v_key, now() + pol.token_ttl, 'unlock', p_unlock_type, p_unlock_id)
    returning * into t;
  return query select t.id, t.expires_at, pol.unlock_daily_cap - used - 1;
end $$;

-- AdMob's verified callback (outcomes as in 20261019). A credit goes to the
-- token's install as before; a try is recorded for the token's user and its
-- look or style, from now until unlock_ttl, with no credit. Each kind is
-- capped on its own, per user and per install.
create or replace function public.redeem_ad_reward(
  p_transaction_id text, p_token uuid, p_ad_unit text, p_reward_amount int, p_reward_item text
)
returns table (outcome text, credits_remaining int)
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  t public.ad_reward_tokens;
  token_day date;
  v_cap int;
  granted_that_day int;
  result text;
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
  v_cap := case when t.kind = 'unlock' then pol.unlock_daily_cap else pol.daily_cap end;
  -- Locks the user's wallet and the install, so two callbacks can't both pass the cap.
  perform 1 from public.credit_wallets w where w.user_id = t.user_id for update;
  if t.install_key is not null then
    perform private.refresh_install(t.install_key);
  end if;
  if t.expires_at < now() or t.install_key is null then
    -- Late, or a token from before installs counted: nothing to pay into.
    result := 'expired';
  else
    select greatest(
      (select count(*) from public.ad_rewards r
        where r.user_id = t.user_id and r.kind = t.kind and r.status = 'granted' and r.reward_day = token_day),
      (select count(*) from public.ad_rewards r
        where r.install_key = t.install_key and r.kind = t.kind and r.status = 'granted' and r.reward_day = token_day))
      into granted_that_day;
    result := case when granted_that_day >= v_cap then 'capped' else 'granted' end;
  end if;

  insert into public.ad_rewards
      (transaction_id, user_id, token_id, ad_unit, reward_amount, reward_item, credits, status, reward_day,
       install_key, kind)
    values (p_transaction_id, t.user_id, t.id, p_ad_unit, p_reward_amount, p_reward_item,
            case when result = 'granted' and t.kind = 'credit' then pol.credits else 0 end, result, token_day,
            t.install_key, t.kind);
  update public.ad_reward_tokens set redeemed_at = now() where id = t.id;
  if result = 'granted' and t.kind = 'unlock' then
    insert into private.ad_unlocks (user_id, transaction_id, unlock_type, unlock_id, expires_at)
      values (t.user_id, p_transaction_id, t.unlock_type, t.unlock_id, now() + pol.unlock_ttl);
  elsif result = 'granted' then
    insert into public.credit_ledger (user_id, kind, daily, source_ref, install_key)
      values (t.user_id, 'ad_reward', pol.credits, 'admob:' || p_transaction_id, t.install_key)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    if found then
      update private.app_installs set daily = daily + pol.credits where key = t.install_key;
    end if;
  end if;
  return query select result, private.balance_of(t.user_id, t.install_key);
end $$;

-- The app's poll after an ad (see 20261023), now with the token's kind and,
-- for a try, its look or style and, once granted, when the try ends.
-- remaining_today counts the token's kind.
drop function if exists public.ad_reward_status(uuid, uuid);
create function public.ad_reward_status(p_user uuid, p_token uuid)
returns table (
  outcome text, remaining_today int, credits_remaining int,
  reward_kind text, unlock_type text, unlock_id text, unlock_expires_at timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  pol record;
  t public.ad_reward_tokens;
  r public.ad_rewards;
  v_key text;
  v_kind text := 'credit';
  v_type text;
  v_id text;
  v_expires timestamptz;
  result text;
begin
  select * into pol from public.ad_reward_policy();
  select * into t from public.ad_reward_tokens k where k.id = p_token and k.user_id = p_user;
  select * into r from public.ad_rewards x where x.token_id = p_token and x.user_id = p_user;
  if r.transaction_id is not null then
    result := r.status;
    v_key := r.install_key;
    v_kind := r.kind;
    if r.kind = 'unlock' and r.status = 'granted' then
      select u.unlock_type, u.unlock_id, u.expires_at into v_type, v_id, v_expires
        from private.ad_unlocks u where u.transaction_id = r.transaction_id;
    end if;
  elsif t.id is null then
    result := 'unknown';
  else
    v_key := t.install_key;
    result := case when t.expires_at < now() then 'expired' else 'pending' end;
  end if;
  if t.id is not null then
    v_kind := t.kind;
    v_type := coalesce(v_type, t.unlock_type);
    v_id := coalesce(v_id, t.unlock_id);
  end if;
  return query select result,
                      greatest(0, case when v_kind = 'unlock' then pol.unlock_daily_cap else pol.daily_cap end
                                  - public.ad_rewards_used_today(p_user, v_key, v_kind)),
                      private.balance_of(p_user, v_key),
                      v_kind, v_type, v_id, v_expires;
end $$;

-- The ad closed before it paid out: the token goes, and so does its place in
-- today's cap for its kind. Only her own unredeemed tokens.
drop function if exists public.release_ad_reward_token(uuid, uuid);
create function public.release_ad_reward_token(p_user uuid, p_token uuid)
returns table (released boolean, remaining_today int, reward_kind text)
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
  v_kind text;
begin
  select * into pol from public.ad_reward_policy();
  delete from public.ad_reward_tokens k
   where k.id = p_token and k.user_id = p_user and k.redeemed_at is null
  returning k.install_key, k.kind into v_key, v_kind;
  return query select found,
                      greatest(0, case when v_kind = 'unlock' then pol.unlock_daily_cap else pol.daily_cap end
                                  - public.ad_rewards_used_today(p_user, v_key, coalesce(v_kind, 'credit'))),
                      coalesce(v_kind, 'credit');
end $$;

-- GET /ad-reward: today's ads for her and her install (as in 20261023), and
-- the same for tries: how many are left, whether one is on offer, and the
-- tries she holds now, unused and live.
create or replace function public.ad_reward_overview(
  p_user uuid, p_is_pro boolean,
  p_app_transaction_id text default null, p_install_status text default 'missing', p_install_environment text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
  f record;
  v_remaining int;
  v_unlocks int;
  v_credits int;
  v_free boolean;
begin
  select * into pol from public.ad_reward_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  select * into f from private.funds(p_user, v_key, true);
  v_remaining := greatest(0, pol.daily_cap - public.ad_rewards_used_today(p_user, v_key));
  v_unlocks := greatest(0, pol.unlock_daily_cap - public.ad_rewards_used_today(p_user, v_key, 'unlock'));
  v_credits := f.daily_credits + f.subscription_credits + f.purchased_credits;
  -- A free member with a verified install, not resting or blocked.
  v_free := not p_is_pro and not f.is_pro and v_key is not null
            and not private.active_block(p_user, v_key) and private.cooldown_until(p_user, v_key) is null;
  return jsonb_build_object(
    'remaining_today', v_remaining,
    'daily_cap', pol.daily_cap,
    'credits_remaining', v_credits,
    'eligible', v_free and v_credits <= 0 and v_remaining > 0,
    'unlock', jsonb_build_object(
      'remaining_today', v_unlocks,
      'daily_cap', pol.unlock_daily_cap,
      'eligible', v_free and v_credits > 0 and v_unlocks > 0 and private.ai_paused_until() is null,
      'active', (select coalesce(jsonb_agg(jsonb_build_object(
                          case when u.unlock_type = 'template' then 'template_id' else 'style_id' end, u.unlock_id,
                          'expires_at', u.expires_at)
                        order by u.expires_at), '[]'::jsonb)
                   from private.ad_unlocks u
                  where u.user_id = p_user and u.job_id is null and u.expires_at > now())
    )
  );
end $$;

-- MARK: Jobs

-- ai-image, before anything is checked or booked for a non-Pro job with a Pro
-- look or style: does she hold an unused, live try of exactly that one, or,
-- for a free retry, did the original job spend one on it? admit_unlocked_job()
-- asks again under a lock.
create function public.ad_unlock_available(
  p_user uuid, p_unlock_type text, p_unlock_id text, p_retry_of uuid default null
)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select case
    when p_retry_of is not null then exists (
      select 1 from private.ad_unlocks u
       where u.job_id = p_retry_of and u.user_id = p_user
         and u.unlock_type = p_unlock_type and u.unlock_id = p_unlock_id)
    else exists (
      select 1 from private.ad_unlocks u
       where u.user_id = p_user and u.unlock_type = p_unlock_type and u.unlock_id = p_unlock_id
         and u.job_id is null and u.expires_at > now())
  end
$$;

-- admit_job() for a non-Pro job with one Pro look or style, in one transaction:
-- without an unused, live try of exactly that id 'pro_required' (402) before
-- any other check, as ai-image answered before tries existed; with one,
-- admit_job() and all its gates and its charge, and the try is spent on the
-- job it admits (nothing is spent on a refusal). A free retry of a result a
-- try paid for needs no new try. A member who is Pro by now spends none.
create function public.admit_unlocked_job(
  p_user uuid,
  p_unlock_type text,
  p_unlock_id text,
  p_operation text,
  p_endpoint text,
  p_template_id text default null,
  p_outputs int default 1,
  p_input_images int default 0,
  p_retry_of uuid default null,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_install_environment text default null,
  p_ip text default null,
  p_blocked_category text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_unlock uuid;
  v_result jsonb;
begin
  if not exists (select 1 from public.entitlements e
                  where e.user_id = p_user and not e.revoked and e.expires_at > now()) then
    if p_retry_of is not null then
      if not exists (select 1 from private.ad_unlocks u
                      where u.job_id = p_retry_of and u.user_id = p_user
                        and u.unlock_type = p_unlock_type and u.unlock_id = p_unlock_id) then
        return private.error('pro_required', 402);
      end if;
    else
      select u.id into v_unlock from private.ad_unlocks u
       where u.user_id = p_user and u.unlock_type = p_unlock_type and u.unlock_id = p_unlock_id
         and u.job_id is null and u.expires_at > now()
       order by u.expires_at
       limit 1
       for update;
      if v_unlock is null then
        return private.error('pro_required', 402);
      end if;
    end if;
  end if;

  v_result := public.admit_job(
    p_user => p_user,
    p_operation => p_operation,
    p_endpoint => p_endpoint,
    p_template_id => p_template_id,
    p_outputs => p_outputs,
    p_input_images => p_input_images,
    p_retry_of => p_retry_of,
    p_app_transaction_id => p_app_transaction_id,
    p_install_status => p_install_status,
    p_install_environment => p_install_environment,
    p_ip => p_ip,
    p_blocked_category => p_blocked_category
  );
  if v_unlock is not null and coalesce((v_result->>'ok')::boolean, false) then
    update private.ad_unlocks
       set job_id = (v_result->>'job_id')::uuid, used_at = now()
     where id = v_unlock;
  end if;
  return v_result;
end $$;

-- Refunds exactly what a job was charged, to where it came from, at most
-- once, and gives back the try it spent, for what is left of its time
-- (20261021, plus the try). Returns the balance.
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
  update private.ad_unlocks set job_id = null, used_at = null where job_id = p_job;
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
      update private.app_installs
         set daily = least(daily - h.daily, private.daily_ceiling(h.install_key))
       where key = h.install_key;
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

-- MARK: Accounts and cleanup

-- Sign in with Apple (20261022): her tries move with her jobs, so a try a
-- moved job spent still comes back if that job is refunded.
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
  update private.strikes set user_id = p_to where user_id = p_from;
  update private.cooldowns set user_id = p_to where user_id = p_from;
  update private.ad_unlocks set user_id = p_to where user_id = p_from;
  if not exists (select 1 from private.blocks where user_id = p_to and lifted_at is null) then
    update private.blocks set user_id = p_to where user_id = p_from and lifted_at is null;
  end if;

  select * into dst from public.credit_wallets where user_id = p_to;
  return dst;
end $$;

-- Housekeeping (20261019), plus tries a day after they end. Scheduled hourly
-- as 'sweep-ad-rewards' (backend/README.md, setup step 6).
create or replace function public.sweep_ad_rewards()
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.ad_reward_tokens where expires_at < now() - interval '1 day';
  delete from public.ad_rewards where created_at < now() - interval '30 days';
  delete from private.ad_unlocks where expires_at < now() - interval '1 day';
$$;

-- MARK: Privileges

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.ad_reward_policy()',
    'public.ad_rewards_used_today(uuid, text, text)',
    'public.issue_ad_unlock_token(uuid, boolean, text, text, text, text, text)',
    'public.redeem_ad_reward(text, uuid, text, int, text)',
    'public.ad_reward_status(uuid, uuid)',
    'public.release_ad_reward_token(uuid, uuid)',
    'public.ad_reward_overview(uuid, boolean, text, text, text)',
    'public.ad_unlock_available(uuid, text, text, uuid)',
    'public.admit_unlocked_job(uuid, text, text, text, text, text, int, int, uuid, text, text, text, text, text)',
    'public.release_credits(uuid)',
    'public.merge_accounts(uuid, uuid)',
    'public.sweep_ad_rewards()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
