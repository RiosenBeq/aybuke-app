-- Rewarded ads, per App Store install (see 20261019 for the flow).
-- ----------------------------------------------------------------------------
-- Since 20261021 free credits live on the hashed App Store install, not on
-- the anonymous account, and ad credits follow them:
--
--   * "Out of credits" means the balance she sees: today's free credits on
--     her install, her subscription's credits and her packs, all used up.
--   * A token needs a verified install (the app sends X-App-Transaction, as
--     for jobs): without one nothing can be capped per Apple Account, so the
--     server offers no ad ('not_eligible').
--   * ad_reward_policy().daily_cap (2 a day) counts per user and per install,
--     so new anonymous accounts made by one Apple Account share it.
--   * The credit lands in the install's daily bucket: spent first, gone at the
--     next UTC midnight like the free credits, and refunded like them (the
--     day's ceiling includes it). No ad during a cool-down or a block.

alter table public.ad_reward_tokens add column install_key text;
alter table public.ad_rewards add column install_key text;
create index ad_reward_tokens_install_idx on public.ad_reward_tokens (install_key, created_at desc)
  where install_key is not null;
create index ad_rewards_install_day_idx on public.ad_rewards (install_key, reward_day) where install_key is not null;

-- Today's ceiling: the allowance plus the ad credits granted to the install today.
create or replace function private.daily_ceiling(p_key text)
returns int
language sql stable
set search_path = ''
as $$
  select p.free_daily + coalesce((
    select sum(r.credits)::int from public.ad_rewards r
     where r.install_key = p_key and r.status = 'granted'
       and r.created_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc'), 0)
    from public.credit_policy() p
$$;
revoke all on function private.daily_ceiling(text) from public;

-- Ads paid today plus tokens still waiting for AdMob, per user and per
-- install; the larger counts, so she's never shown an ad that can't pay.
drop function if exists public.ad_rewards_used_today(uuid);
create function public.ad_rewards_used_today(p_user uuid, p_install text default null)
returns int
language sql stable security definer
set search_path = ''
as $$
  select greatest(
    (select count(*) from public.ad_rewards r
      where r.user_id = p_user and r.status = 'granted' and r.reward_day = (now() at time zone 'utc')::date)
    + (select count(*) from public.ad_reward_tokens k
        where k.user_id = p_user and k.redeemed_at is null and k.expires_at > now()
          and k.created_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc'),
    case when p_install is null then 0 else
      (select count(*) from public.ad_rewards r
        where r.install_key = p_install and r.status = 'granted' and r.reward_day = (now() at time zone 'utc')::date)
      + (select count(*) from public.ad_reward_tokens k
          where k.install_key = p_install and k.redeemed_at is null and k.expires_at > now()
            and k.created_at >= ((now() at time zone 'utc')::date)::timestamp at time zone 'utc')
    end
  )::int
$$;

-- A single-use token for the next rewarded ad: free members with a verified
-- install, out of credits, not resting or blocked, under today's cap. The
-- wallet and the install stay locked until the transaction ends.
drop function if exists public.issue_ad_reward_token(uuid, boolean);
create function public.issue_ad_reward_token(
  p_user uuid, p_is_pro boolean,
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
  if f.daily_credits + f.subscription_credits + f.purchased_credits > 0 then
    raise exception 'AD_HAS_CREDITS' using errcode = 'P0001';
  end if;
  delete from public.ad_reward_tokens k where k.user_id = p_user and k.expires_at < now() - interval '1 day';
  used := public.ad_rewards_used_today(p_user, v_key);
  if used >= pol.daily_cap then
    raise exception 'AD_DAILY_CAP' using errcode = 'P0001';
  end if;
  insert into public.ad_reward_tokens (user_id, install_key, expires_at)
    values (p_user, v_key, now() + pol.token_ttl)
    returning * into t;
  return query select t.id, t.expires_at, pol.daily_cap - used - 1;
end $$;

-- AdMob's verified callback (outcomes as in 20261019). The credit goes to
-- the token's install, under the cap per user and per install.
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
        where r.user_id = t.user_id and r.status = 'granted' and r.reward_day = token_day),
      (select count(*) from public.ad_rewards r
        where r.install_key = t.install_key and r.status = 'granted' and r.reward_day = token_day))
      into granted_that_day;
    result := case when granted_that_day >= pol.daily_cap then 'capped' else 'granted' end;
  end if;

  insert into public.ad_rewards
      (transaction_id, user_id, token_id, ad_unit, reward_amount, reward_item, credits, status, reward_day, install_key)
    values (p_transaction_id, t.user_id, t.id, p_ad_unit, p_reward_amount, p_reward_item,
            case when result = 'granted' then pol.credits else 0 end, result, token_day, t.install_key);
  update public.ad_reward_tokens set redeemed_at = now() where id = t.id;
  if result = 'granted' then
    insert into public.credit_ledger (user_id, kind, daily, source_ref, install_key)
      values (t.user_id, 'ad_reward', pol.credits, 'admob:' || p_transaction_id, t.install_key)
      on conflict (kind, source_ref) where source_ref is not null do nothing;
    if found then
      update private.app_installs set daily = daily + pol.credits where key = t.install_key;
    end if;
  end if;
  return query select result, private.balance_of(t.user_id, t.install_key);
end $$;

-- The app's poll after an ad (see 20261019), now with the balance the reward
-- landed in and today's ads left for her install.
drop function if exists public.ad_reward_status(uuid, uuid);
create function public.ad_reward_status(p_user uuid, p_token uuid)
returns table (outcome text, remaining_today int, credits_remaining int)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  pol record;
  t public.ad_reward_tokens;
  v_key text;
  reward_status text;
  result text;
begin
  select * into pol from public.ad_reward_policy();
  select r.status, r.install_key into reward_status, v_key
    from public.ad_rewards r where r.token_id = p_token and r.user_id = p_user;
  if reward_status is not null then
    result := reward_status;
  else
    select * into t from public.ad_reward_tokens k where k.id = p_token and k.user_id = p_user;
    if not found then
      result := 'unknown';
    else
      v_key := t.install_key;
      result := case when t.expires_at < now() then 'expired' else 'pending' end;
    end if;
  end if;
  return query select result,
                      greatest(0, pol.daily_cap - public.ad_rewards_used_today(p_user, v_key)),
                      private.balance_of(p_user, v_key);
end $$;

-- GET /ad-reward: today's ads for her and her install, and whether one is on offer.
create function public.ad_reward_overview(
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
  v_credits int;
begin
  select * into pol from public.ad_reward_policy();
  v_key := private.touch_install(p_user, p_app_transaction_id, p_install_status, p_install_environment);
  select * into f from private.funds(p_user, v_key, true);
  v_remaining := greatest(0, pol.daily_cap - public.ad_rewards_used_today(p_user, v_key));
  v_credits := f.daily_credits + f.subscription_credits + f.purchased_credits;
  return jsonb_build_object(
    'remaining_today', v_remaining,
    'daily_cap', pol.daily_cap,
    'credits_remaining', v_credits,
    'eligible', not p_is_pro and not f.is_pro and v_key is not null and v_credits <= 0 and v_remaining > 0
                and not private.active_block(p_user, v_key) and private.cooldown_until(p_user, v_key) is null
  );
end $$;

-- The ad closed before it paid out: the token goes, and so does its place in
-- today's cap. Only her own unredeemed tokens. Returns today's ads left.
drop function if exists public.release_ad_reward_token(uuid, uuid);
create function public.release_ad_reward_token(p_user uuid, p_token uuid)
returns table (released boolean, remaining_today int)
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_key text;
begin
  select * into pol from public.ad_reward_policy();
  delete from public.ad_reward_tokens k
   where k.id = p_token and k.user_id = p_user and k.redeemed_at is null
  returning k.install_key into v_key;
  return query select found, greatest(0, pol.daily_cap - public.ad_rewards_used_today(p_user, v_key));
end $$;

revoke execute on function public.ad_rewards_used_today(uuid, text) from public, anon, authenticated;
revoke execute on function public.issue_ad_reward_token(uuid, boolean, text, text, text) from public, anon, authenticated;
revoke execute on function public.redeem_ad_reward(text, uuid, text, int, text) from public, anon, authenticated;
revoke execute on function public.ad_reward_status(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.ad_reward_overview(uuid, boolean, text, text, text) from public, anon, authenticated;
revoke execute on function public.release_ad_reward_token(uuid, uuid) from public, anon, authenticated;
grant execute on function public.ad_rewards_used_today(uuid, text),
  public.issue_ad_reward_token(uuid, boolean, text, text, text), public.redeem_ad_reward(text, uuid, text, int, text),
  public.ad_reward_status(uuid, uuid), public.ad_reward_overview(uuid, boolean, text, text, text),
  public.release_ad_reward_token(uuid, uuid)
  to service_role;
