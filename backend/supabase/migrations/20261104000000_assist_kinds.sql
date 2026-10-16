-- Aybik's new text tasks get buckets of their own (16 October 2026).
-- ----------------------------------------------------------------------------
-- functions/assist answers four more tasks, all text only and free: the look
-- finder ("Describe your vibe" on Explore), poll question ideas, card text for
-- the share composer, and answers to questions about the app (Settings ›
-- Help). Each counts in its own kind, so a busy one can't use up another's
-- hour:
--
--   'assist'          prompt ideas, prompt rewrites, caption ideas, makeup picks
--                     (unchanged: 60 / 60 / 200 an hour);
--   'polish'          ai-image's prompt polish (unchanged: 60 / 60 / 200);
--   'looks'           the look finder: 30 per user, 30 per verified install,
--                     120 per address an hour;
--   'poll_questions'  question ideas for a poll (3 polls a day): 20 / 20 / 100;
--   'card_text'       options for the share card's words, a request per tap
--                     of "Write it for me": 40 / 40 / 150;
--   'help'            questions about the app: 20 / 20 / 100.
--
-- assist_kind_policy() holds these numbers. Everything else in admit_assist()
-- stays as 20261103000000 made it, and shared: the pause, the quiet time after
-- a failed result check, blocks and cool-downs, the 30 an hour shared by
-- callers without a verified install, and everyone's ceilings (20 a minute,
-- 200 an hour, 1,000 a UTC day) count every kind together, so Claude's
-- capacity still goes to the safety checks first. assist_policy() keeps its
-- numbers (its user, install and address columns are the 'assist' kind's).
--
-- Deploy order: apply this migration before deploying the assist function
-- that sends the new kinds. Until then admit_assist() raises 'unknown kind',
-- the function answers 503 assist_unavailable and the app falls back.

-- MARK: The kinds

alter table private.assist_usage drop constraint assist_usage_kind_check;
alter table private.assist_usage add constraint assist_usage_kind_check
  check (kind in ('assist', 'polish', 'looks', 'poll_questions', 'card_text', 'help'));

-- Per kind: requests an hour per account, per verified App Store install and
-- per network address. No row (nulls) for an unknown kind. Change the numbers
-- here (a new migration that replaces the function) to retune them without an
-- app update.
create function public.assist_kind_policy(
  p_kind text,
  out user_per_hour int,
  out install_per_hour int,
  out ip_per_hour int
)
language sql immutable
set search_path = ''
as $$
  select v.user_per_hour, v.install_per_hour, v.ip_per_hour
    from (values
      ('assist', 60, 60, 200),
      ('polish', 60, 60, 200),
      ('looks', 30, 30, 120),
      ('poll_questions', 20, 20, 100),
      ('card_text', 40, 40, 150),
      ('help', 20, 20, 100)
    ) as v(kind, user_per_hour, install_per_hour, ip_per_hour)
   where v.kind = p_kind
$$;

-- MARK: Admission

-- As 20261103000000, with step 3 counted in the kind's own bucket and limits:
--   1. AI paused for everyone, or a result check failed within
--      quiet_after_check_error_minutes: 503 assist_unavailable until it ends;
--   2. a block or a running cool-down of the user, or of her verified install
--      (her address without one): 503 assist_unavailable;
--   3. per user, per verified install and per address, per kind and UTC hour
--      (assist_kind_policy()): 429 rate_limited until the hour ends (a refused
--      request still counts);
--   4. without a verified install, the shared hourly cap; then everyone's
--      ceilings a minute, an hour and a UTC day, every kind together: 503
--      assist_unavailable until that period ends. These count only the
--      requests they admit.
-- Nothing is counted in 1 and 2. An unknown kind raises.
create or replace function public.admit_assist(
  p_user uuid,
  p_ip text,
  p_kind text,
  p_app_transaction_id text,
  p_install_status text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  lim record;
  v_now timestamptz := now();
  v_minute timestamptz := date_trunc('minute', now());
  v_hour timestamptz := date_trunc('hour', now());
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text;
  v_abuse text;
  v_until timestamptz;
  v_count int;
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  select * into lim from public.assist_kind_policy(p_kind);
  if p_kind is null or lim.user_per_hour is null then
    raise exception 'unknown kind %', p_kind;
  end if;
  select * into pol from public.assist_policy();
  -- The verified install's key, as touch_install() and admit_poll() make it;
  -- strikes, cool-downs and blocks fall back to the address, as in admit_job().
  v_install := case when p_install_status = 'verified' and coalesce(p_app_transaction_id, '') <> ''
                    then private.keyed_hash('app_transaction', p_app_transaction_id) end;
  v_abuse := coalesce(v_install, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);

  -- 1. Paused, or the safety check is struggling: Claude is for the checks now.
  select max(s.paused_until) into v_until from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now;
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;
  select b.last_error_at + make_interval(mins => pol.quiet_after_check_error_minutes) into v_until
    from private.safety_breaker b;
  if v_until > v_now then
    return private.error('assist_unavailable', 503, v_until);
  end if;

  -- 2. Blocked or resting: no cloud AI, so no Claude either.
  if private.active_block(p_user, v_abuse) then
    return private.error('assist_unavailable', 503);
  end if;
  v_until := private.cooldown_until(p_user, v_abuse);
  if v_until is not null then
    return private.error('assist_unavailable', 503, v_until);
  end if;

  -- 3. Per user, per install, then per address, for this hour, in the kind's bucket.
  insert into private.assist_usage as u (kind, bucket, hour, requests)
    values (p_kind, private.keyed_hash('assist_user', p_user::text), v_hour, 1)
    on conflict (kind, bucket, hour) do update set requests = u.requests + 1
    returning u.requests into v_count;
  if v_count > lim.user_per_hour then
    return private.error('rate_limited', 429, v_hour + interval '1 hour');
  end if;
  if v_install is not null then
    insert into private.assist_usage as u (kind, bucket, hour, requests)
      values (p_kind, v_install, v_hour, 1)
      on conflict (kind, bucket, hour) do update set requests = u.requests + 1
      returning u.requests into v_count;
    if v_count > lim.install_per_hour then
      return private.error('rate_limited', 429, v_hour + interval '1 hour');
    end if;
  end if;
  if coalesce(p_ip, '') <> '' then
    insert into private.assist_usage as u (kind, bucket, hour, requests)
      values (p_kind, private.keyed_hash('ip', p_ip), v_hour, 1)
      on conflict (kind, bucket, hour) do update set requests = u.requests + 1
      returning u.requests into v_count;
    if v_count > lim.ip_per_hour then
      return private.error('rate_limited', 429, v_hour + interval '1 hour');
    end if;
  end if;

  -- 4. The ceilings, every kind together. A place one of them took is given back when a later one refuses.
  if v_install is null and not private.assist_take('unverified_hour', v_hour, pol.unverified_per_hour) then
    return private.error('assist_unavailable', 503, v_hour + interval '1 hour');
  end if;
  if not private.assist_take('all_minute', v_minute, pol.all_per_minute) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    return private.error('assist_unavailable', 503, v_minute + interval '1 minute');
  end if;
  if not private.assist_take('all_hour', v_hour, pol.all_per_hour) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    perform private.assist_give_back('all_minute', v_minute);
    return private.error('assist_unavailable', 503, v_hour + interval '1 hour');
  end if;
  if not private.assist_take('all_day', v_day, pol.all_per_day) then
    if v_install is null then
      perform private.assist_give_back('unverified_hour', v_hour);
    end if;
    perform private.assist_give_back('all_minute', v_minute);
    perform private.assist_give_back('all_hour', v_hour);
    return private.error('assist_unavailable', 503, private.next_utc_day());
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- MARK: Privileges

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.assist_kind_policy(text)',
    'public.admit_assist(uuid, text, text, text, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
