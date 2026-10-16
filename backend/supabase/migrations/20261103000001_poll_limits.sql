-- Polls: limits one person can't use up, "Edited with AI" labels, and a
-- taken-down poll kept for review when its maker deletes it (security review,
-- 16 October 2026). Replaces functions of 20261102000000 in place; the 1.0
-- app never calls them, and every signature the deployed polls function uses
-- keeps working.
--
--   1. Attempts without a verified App Store install share one small daily
--      cap (poll_backstops().polls_unverified_daily, part of today's polls
--      for everyone), like admit_job()'s unverified breaker.
--   2. A question the prompt policy blocked, or a picture that couldn't be
--      read, never reaches the safety check: it no longer counts toward
--      today's polls for everyone (polls_all_daily) but toward its own daily
--      cap (rejected_attempts_daily: blocked_question + invalid_image).
--   3. Picture loads: today's cap for everyone (image_loads_daily, still
--      2,000) counts each picture once per network address and day
--      (private.poll_image_loads, salted hashes kept only while the poll
--      exists), so one visitor reloading can't use it up; every load still
--      counts per poll (600) and per address (now 60 an hour, from 200: two
--      pictures a poll is far less), and a higher backstop on every load
--      (image_loads_raw_daily, 4,000, about 0.55 GB of egress) protects the
--      free plan. ops_polls_summary() and the daily digest show both.
--   4. ai_sides: the app says which pictures were edited with AI (their
--      Provenance; the re-encode drops the IPTC marking), and the poll page
--      says "Edited with AI" under them. create_poll() takes p_ai_sides in a
--      new form; poll_view() and my_polls() answer "ai": { "a", "b" }.
--   5. delete_poll() of a poll taken down after a report: gone from her list
--      at once, kept for the owner's review until its 24 hours end, then
--      deleted by sweep_jobs() like every poll. Deleting her account still
--      deletes it at once (on delete cascade).

-- MARK: Policy

-- 20261102000000's numbers; a load per address an hour is now 60, and
-- image_loads_daily counts each picture once per address and day.
create or replace function public.poll_policy(
  out lifetime_hours int,
  out polls_per_user_daily int,
  out polls_per_install_daily int,
  out polls_per_ip_hourly int,
  out polls_all_daily int,
  out votes_per_ip_hourly int,
  out views_per_ip_hourly int,
  out image_loads_per_ip_hourly int,
  out image_loads_per_poll int,
  out image_loads_daily int,
  out reports_per_ip_hourly int,
  out takedown_reports int,
  out report_retention_days int
)
language sql immutable
set search_path = ''
as $$
  select 24, 3, 3, 10, 300, 120, 600, 60, 600, 2000, 10, 3, 30
$$;

-- The backstops for everyone: attempts without a verified install, attempts
-- that never reached the check, and every picture load (the free plan's
-- egress: a load sends about 60 KB to the browser and about 80 KB from the
-- database to the function, so 4,000 loads are about 0.55 GB).
create function public.poll_backstops(
  out polls_unverified_daily int,
  out rejected_attempts_daily int,
  out image_loads_raw_daily int
)
language sql immutable
set search_path = ''
as $$
  select 30, 600, 4000
$$;

-- MARK: Tables

alter table private.polls
  -- The app's word (each picture's Provenance): the page says "Edited with AI".
  add column ai_a boolean not null default false,
  add column ai_b boolean not null default false,
  -- She deleted it while it was taken down: out of her list, kept for review until it ends.
  add column hidden_at timestamptz;

alter table private.poll_daily
  add column unverified_attempts int not null default 0,
  add column image_loads_unique int not null default 0;

-- One row per picture, network address and UTC day while the poll exists:
-- keyed_hash('poll_load', poll id:side:address), different for every poll.
create table private.poll_image_loads (
  poll_id text not null references private.polls (id) on delete cascade,
  day date not null,
  viewer text not null,
  primary key (poll_id, day, viewer)
);
create index poll_image_loads_day_idx on private.poll_image_loads (day);

alter table private.poll_image_loads enable row level security;
revoke all on table private.poll_image_loads from public, anon, authenticated;

-- MARK: Helpers

-- Adds to one of today's numbers (20261102000000, plus the two new ones).
create or replace function private.poll_bump(p_field text, p_by bigint default 1)
returns void
language plpgsql volatile
set search_path = ''
as $$
begin
  if p_field not in ('attempts', 'created', 'blocked_question', 'blocked_image', 'invalid_image', 'unavailable',
                     'deleted', 'votes', 'reports', 'takedowns', 'image_loads', 'image_bytes',
                     'unverified_attempts', 'image_loads_unique') then
    raise exception 'unknown poll number %', p_field;
  end if;
  insert into private.poll_daily (day) values (private.poll_today()) on conflict (day) do nothing;
  execute format('update private.poll_daily set %1$I = greatest(%1$I + $1, 0) where day = $2', p_field)
    using p_by, private.poll_today();
end $$;

-- MARK: Creating a poll

-- Before the pictures are decoded or checked. In this order: a block (403
-- install_blocked) or a cool-down (429 cooldown) of the user or her install
-- (or, without a verified install, her address); AI paused for everyone (503
-- safety_unavailable); today's polls for everyone, or for a blocked question
-- today's rejected attempts; without a verified install, today's unverified
-- attempts; 3 a day per user and per install; 10 an hour per address (429
-- rate_limited). A refused request leaves every count as it was. Then the
-- attempt counts: a blocked question (p_blocked_category) as rejected, 422
-- content_blocked, never a strike; any other toward today's polls.
create or replace function public.admit_poll(
  p_user uuid,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_ip text default null,
  p_blocked_category text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  more record;
  v_today date := private.poll_today();
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text := private.poll_install_key(p_app_transaction_id, p_install_status);
  v_abuse text;
  v_until timestamptz;
  v_daily private.poll_daily;
  v_user int;
  v_install_count int;
  v_ip int;
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  select * into pol from public.poll_policy();
  select * into more from public.poll_backstops();
  v_abuse := coalesce(v_install, case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end);

  if private.active_block(p_user, v_abuse) then
    return private.error('install_blocked', 403);
  end if;
  v_until := private.cooldown_until(p_user, v_abuse);
  if v_until is not null then
    return private.error('cooldown', 429, v_until);
  end if;
  select max(s.paused_until) into v_until from private.ai_switches s where s.scope = 'all' and s.paused_until > now();
  if v_until is not null then
    return private.error('safety_unavailable', 503, v_until);
  end if;

  insert into private.poll_daily (day) values (v_today) on conflict (day) do nothing;
  select * into v_daily from private.poll_daily where day = v_today for update;
  -- A blocked question never reaches the check: it has its own cap, with
  -- unreadable pictures, and leaves today's polls for everyone alone.
  if p_blocked_category is null then
    if v_daily.attempts >= pol.polls_all_daily then
      return private.error('rate_limited', 429, private.next_utc_day());
    end if;
  elsif v_daily.blocked_question + v_daily.invalid_image >= more.rejected_attempts_daily then
    return private.error('rate_limited', 429, private.next_utc_day());
  end if;
  -- Without a verified install: one small cap for all of them together.
  if v_install is null and v_daily.unverified_attempts >= more.polls_unverified_daily then
    return private.error('rate_limited', 429, private.next_utc_day());
  end if;

  -- Each count goes up, and back down when this request is refused (the
  -- upsert holds the counter's row until the end, so racing requests queue).
  v_user := private.poll_count('create_user', private.keyed_hash('poll_user', p_user::text), v_day);
  if v_user > pol.polls_per_user_daily then
    perform private.poll_count('create_user', private.keyed_hash('poll_user', p_user::text), v_day, -1);
    return private.error('rate_limited', 429, private.next_utc_day());
  end if;
  if v_install is not null then
    v_install_count := private.poll_count('create_install', v_install, v_day);
    if v_install_count > pol.polls_per_install_daily then
      perform private.poll_count('create_user', private.keyed_hash('poll_user', p_user::text), v_day, -1);
      perform private.poll_count('create_install', v_install, v_day, -1);
      return private.error('rate_limited', 429, private.next_utc_day());
    end if;
  end if;
  v_ip := private.poll_ip_count('create_ip', p_ip);
  if v_ip > pol.polls_per_ip_hourly then
    perform private.poll_count('create_user', private.keyed_hash('poll_user', p_user::text), v_day, -1);
    if v_install is not null then
      perform private.poll_count('create_install', v_install, v_day, -1);
    end if;
    perform private.poll_count('create_ip', private.keyed_hash('ip', p_ip), date_trunc('hour', now()), -1);
    return private.poll_hour_limited();
  end if;

  if v_install is null then
    update private.poll_daily set unverified_attempts = unverified_attempts + 1 where day = v_today;
  end if;
  if p_blocked_category is not null then
    update private.poll_daily set blocked_question = blocked_question + 1 where day = v_today;
    return jsonb_build_object('ok', false, 'code', 'content_blocked', 'status', 422, 'category', p_blocked_category);
  end if;
  update private.poll_daily set attempts = attempts + 1 where day = v_today;
  return jsonb_build_object(
    'ok', true,
    'remaining_today', greatest(0, least(pol.polls_per_user_daily - v_user,
                                         coalesce(pol.polls_per_install_daily - v_install_count, pol.polls_per_user_daily)))
  );
end $$;

-- How an admitted attempt ended without a poll: 'image_blocked' (the safety
-- check flagged a picture) keeps the attempt; 'image_invalid' (a picture
-- couldn't be read, so it never reached the check) keeps it for the user,
-- install and address but moves it from today's polls to the rejected count;
-- 'unavailable' (the check couldn't run, or the poll couldn't be stored)
-- gives it back to the user, install, address and today's counts.
create or replace function public.finish_poll_attempt(
  p_user uuid,
  p_outcome text,
  p_app_transaction_id text default null,
  p_install_status text default 'missing',
  p_ip text default null
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text := private.poll_install_key(p_app_transaction_id, p_install_status);
begin
  if p_outcome = 'image_blocked' then
    perform private.poll_bump('blocked_image');
  elsif p_outcome = 'image_invalid' then
    perform private.poll_bump('invalid_image');
    perform private.poll_bump('attempts', -1);
  elsif p_outcome = 'unavailable' then
    perform private.poll_bump('unavailable');
    perform private.poll_bump('attempts', -1);
    if v_install is null then
      perform private.poll_bump('unverified_attempts', -1);
    end if;
    perform private.poll_count('create_user', private.keyed_hash('poll_user', p_user::text), v_day, -1);
    if v_install is not null then
      perform private.poll_count('create_install', v_install, v_day, -1);
    end if;
    if coalesce(p_ip, '') <> '' then
      perform private.poll_count('create_ip', private.keyed_hash('ip', p_ip), date_trunc('hour', now()), -1);
    end if;
  else
    raise exception 'unknown outcome %', p_outcome;
  end if;
end $$;

-- Stores an admitted poll whose pictures passed the safety check, with the
-- sides the app says were edited with AI ('a', 'b'; empty for neither). The
-- pictures arrive as base64 (the function re-encoded them).
create function public.create_poll(
  p_user uuid,
  p_question text,
  p_locale text,
  p_image_a text,
  p_image_b text,
  p_a_width int,
  p_a_height int,
  p_b_width int,
  p_b_height int,
  p_ai_sides text[],
  p_app_transaction_id text default null,
  p_install_status text default 'missing'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_id text;
  v_expires timestamptz;
  v_tries int := 0;
begin
  if p_ai_sides is null or array_position(p_ai_sides, null) is not null
     or not (p_ai_sides <@ array['a', 'b']::text[]) then
    raise exception 'unknown sides %', p_ai_sides;
  end if;
  select * into pol from public.poll_policy();
  v_expires := now() + make_interval(hours => pol.lifetime_hours);
  loop
    v_id := private.new_poll_id();
    begin
      insert into private.polls (id, user_id, install_key, question, locale, image_a, image_b,
                                 a_width, a_height, b_width, b_height, expires_at, ai_a, ai_b)
        values (v_id, p_user, private.poll_install_key(p_app_transaction_id, p_install_status),
                nullif(p_question, ''), coalesce(nullif(p_locale, ''), 'en'),
                decode(p_image_a, 'base64'), decode(p_image_b, 'base64'),
                p_a_width, p_a_height, p_b_width, p_b_height, v_expires,
                'a' = any (p_ai_sides), 'b' = any (p_ai_sides));
      exit;
    exception when unique_violation then
      v_tries := v_tries + 1;
      if v_tries >= 3 then
        raise;
      end if;
    end;
  end loop;
  perform private.poll_bump('created');
  return jsonb_build_object('poll_id', v_id, 'expires_at', v_expires);
end $$;

-- The 20261102000000 form, as the deployed polls function calls it: no AI labels.
create or replace function public.create_poll(
  p_user uuid,
  p_question text,
  p_locale text,
  p_image_a text,
  p_image_b text,
  p_a_width int,
  p_a_height int,
  p_b_width int,
  p_b_height int,
  p_app_transaction_id text default null,
  p_install_status text default 'missing'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  return public.create_poll(p_user, p_question, p_locale, p_image_a, p_image_b, p_a_width, p_a_height,
                            p_b_width, p_b_height, '{}'::text[], p_app_transaction_id, p_install_status);
end $$;

-- MARK: Viewing

-- 20261102000000, plus "ai": which pictures the app says were edited with AI.
create or replace function public.poll_view(
  p_poll text,
  p_voter text default null,
  p_user uuid default null,
  p_ip text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v record;
  v_creator boolean;
  v_vote text;
begin
  select * into pol from public.poll_policy();
  if private.poll_ip_count('view_ip', p_ip) > pol.views_per_ip_hourly then
    return private.poll_hour_limited();
  end if;
  -- Not the pictures: they come one at a time from poll_image().
  select p.user_id, p.question, p.locale, p.created_at, p.expires_at, p.a_width, p.a_height, p.b_width, p.b_height,
         p.ai_a, p.ai_b
    into v
    from private.polls p
   where p.id = p_poll and p.expires_at > now() and p.taken_down_at is null;
  if not found then
    return private.poll_not_found();
  end if;
  v_creator := p_user is not null and p_user = v.user_id;
  if coalesce(p_voter, '') <> '' then
    select choice into v_vote from private.poll_votes
     where poll_id = p_poll and voter = private.keyed_hash('poll_voter', p_poll || ':' || p_voter);
  end if;
  return jsonb_build_object(
    'ok', true,
    'poll_id', p_poll,
    'question', v.question,
    'locale', v.locale,
    'created_at', v.created_at,
    'expires_at', v.expires_at,
    'sizes', jsonb_build_object(
      'a', jsonb_build_object('width', v.a_width, 'height', v.a_height),
      'b', jsonb_build_object('width', v.b_width, 'height', v.b_height)),
    'ai', jsonb_build_object('a', v.ai_a, 'b', v.ai_b),
    'is_creator', v_creator,
    'my_vote', v_vote,
    'votes', case when v_creator or v_vote is not null then private.poll_counts(p_poll) end
  );
end $$;

-- One picture of a live poll, as base64. Every load counts toward 60 an hour
-- per address, 600 per poll and the day's backstop (image_loads_raw_daily);
-- today's cap for everyone (image_loads_daily) counts each picture once per
-- address and day. Any of them: 429 rate_limited.
create or replace function public.poll_image(p_poll text, p_side text, p_ip text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  more record;
  v_today date := private.poll_today();
  v_daily private.poll_daily;
  v_loads int;
  v_image bytea;
  v_viewer text;
  v_new boolean := true;
begin
  if p_side is null or p_side not in ('a', 'b') then
    return private.error('bad_request', 400);
  end if;
  select * into pol from public.poll_policy();
  select * into more from public.poll_backstops();
  if private.poll_ip_count('image_ip', p_ip) > pol.image_loads_per_ip_hourly then
    return private.poll_hour_limited();
  end if;
  select * into v_daily from private.poll_daily d where d.day = v_today;
  if coalesce(v_daily.image_loads, 0) >= more.image_loads_raw_daily then
    return private.error('rate_limited', 429, private.next_utc_day());
  end if;
  update private.polls p
     set image_loads = p.image_loads + 1
   where p.id = p_poll and p.expires_at > now() and p.taken_down_at is null
  returning p.image_loads, case p_side when 'a' then p.image_a else p.image_b end into v_loads, v_image;
  if not found then
    return private.poll_not_found();
  end if;
  if v_loads > pol.image_loads_per_poll then
    return private.error('rate_limited', 429);
  end if;
  -- Once per picture, address and day toward the cap for everyone; without an
  -- address every load counts.
  if coalesce(p_ip, '') <> '' then
    v_viewer := private.keyed_hash('poll_load', p_poll || ':' || p_side || ':' || p_ip);
    insert into private.poll_image_loads (poll_id, day, viewer) values (p_poll, v_today, v_viewer)
      on conflict do nothing;
    v_new := found;
  end if;
  if v_new and coalesce(v_daily.image_loads_unique, 0) >= pol.image_loads_daily then
    if v_viewer is not null then
      delete from private.poll_image_loads where poll_id = p_poll and day = v_today and viewer = v_viewer;
    end if;
    return private.error('rate_limited', 429, private.next_utc_day());
  end if;
  perform private.poll_bump('image_loads');
  perform private.poll_bump('image_bytes', octet_length(v_image));
  if v_new then
    perform private.poll_bump('image_loads_unique');
  end if;
  return jsonb_build_object('ok', true, 'image', translate(encode(v_image, 'base64'), E'\n', ''),
                            'bytes', octet_length(v_image));
end $$;

-- MARK: Her polls

-- Her polls that haven't ended, newest first, with today's polls left. A
-- taken-down poll she deleted isn't hers to see any more.
create or replace function public.my_polls(
  p_user uuid,
  p_app_transaction_id text default null,
  p_install_status text default 'missing'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text := private.poll_install_key(p_app_transaction_id, p_install_status);
  v_user int;
  v_install_count int;
  v_list jsonb;
begin
  select * into pol from public.poll_policy();
  select coalesce(jsonb_agg(jsonb_build_object(
           'poll_id', p.id,
           'question', p.question,
           'locale', p.locale,
           'created_at', p.created_at,
           'expires_at', p.expires_at,
           'status', case when p.taken_down_at is null then 'live' else 'taken_down' end,
           'ai', jsonb_build_object('a', p.ai_a, 'b', p.ai_b),
           'votes', private.poll_counts(p.id)
         ) order by p.created_at desc), '[]'::jsonb)
    into v_list
    from private.polls p
   where p.user_id = p_user and p.expires_at > now() and p.hidden_at is null;
  select coalesce(sum(u.count), 0) into v_user from private.poll_usage u
   where u.kind = 'create_user' and u.bucket = private.keyed_hash('poll_user', p_user::text) and u.period = v_day;
  if v_install is not null then
    select coalesce(sum(u.count), 0) into v_install_count from private.poll_usage u
     where u.kind = 'create_install' and u.bucket = v_install and u.period = v_day;
  end if;
  return jsonb_build_object(
    'polls', v_list,
    'remaining_today', greatest(0, least(pol.polls_per_user_daily - v_user,
                                         coalesce(pol.polls_per_install_daily - v_install_count,
                                                  pol.polls_per_user_daily))),
    'daily_cap', pol.polls_per_user_daily
  );
end $$;

-- She deletes her poll now: the pictures, the question and the votes. One
-- taken down after a report leaves her list at once, but stays (closed to
-- everyone) until its 24 hours end, so the owner can review it; then
-- sweep_jobs() deletes it like every poll. Deleting her account deletes it at
-- once.
create or replace function public.delete_poll(p_poll text, p_user uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  update private.polls set hidden_at = now()
   where id = p_poll and user_id = p_user and hidden_at is null
     and taken_down_at is not null and expires_at > now();
  if not found then
    delete from private.polls where id = p_poll and user_id = p_user and hidden_at is null;
    if not found then
      return jsonb_build_object('deleted', false);
    end if;
  end if;
  perform private.poll_bump('deleted');
  return jsonb_build_object('deleted', true);
end $$;

-- MARK: Owner tools (SQL editor, service role)

-- A day's numbers (yesterday by default, UTC) and what is live now, with the
-- caps: today's polls and, apart, attempts without a verified install and
-- rejected ones (blocked questions and unreadable pictures); picture loads
-- once per picture and address (image_loads_unique) and all of them
-- (image_loads) against the backstop.
create or replace function public.ops_polls_summary(p_day date default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  more record;
  v_day date := coalesce(p_day, private.poll_today() - 1);
  v jsonb;
begin
  select * into pol from public.poll_policy();
  select * into more from public.poll_backstops();
  select to_jsonb(d) - 'day' into v from private.poll_daily d where d.day = v_day;
  v := coalesce(v, jsonb_build_object('attempts', 0, 'created', 0, 'blocked_question', 0, 'blocked_image', 0,
                                      'invalid_image', 0, 'unavailable', 0, 'deleted', 0, 'votes', 0, 'reports', 0,
                                      'takedowns', 0, 'image_loads', 0, 'image_bytes', 0,
                                      'unverified_attempts', 0, 'image_loads_unique', 0));
  return v || jsonb_build_object(
    'day', v_day,
    'image_mb', round((v->>'image_bytes')::numeric / 1048576, 1),
    'live_now', (select count(*) from private.polls where expires_at > now() and taken_down_at is null),
    'taken_down_now', (select count(*) from private.polls where expires_at > now() and taken_down_at is not null),
    'reports_open', (select count(*) from private.poll_reports where status = 'open'),
    'polls_cap', pol.polls_all_daily,
    'unverified_cap', more.polls_unverified_daily,
    'rejected', (v->>'blocked_question')::int + (v->>'invalid_image')::int,
    'rejected_cap', more.rejected_attempts_daily,
    'image_loads_cap', pol.image_loads_daily,
    'image_loads_raw_cap', more.image_loads_raw_daily
  );
end $$;

-- Undoes a takedown that was a mistake: the poll answers again until its 24
-- hours end, its reporters start from none and its open reports are
-- dismissed. If she deleted it while it was down, her deletion stands: it's
-- deleted now, and the answer is false.
create or replace function public.ops_restore_poll(p_poll text)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
  v_hidden timestamptz;
begin
  select hidden_at into v_hidden from private.polls
   where id = p_poll and taken_down_at is not null and expires_at > now()
     for update;
  if not found then
    return false;
  end if;
  update private.poll_reports set status = 'dismissed' where poll_id = p_poll and status = 'open';
  if v_hidden is not null then
    delete from private.polls where id = p_poll;
    raise notice 'poll % was deleted by its maker while it was down: deleted now, not restored', p_poll;
    return false;
  end if;
  update private.polls set taken_down_at = null where id = p_poll;
  delete from private.poll_reporters where poll_id = p_poll;
  return true;
end $$;

-- MARK: Housekeeping

-- The 20261103000000 cleanup, plus the per-address picture loads of earlier
-- days (each also goes with its poll).
create or replace function public.sweep_jobs()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  j record;
begin
  select * into pol from public.credit_policy();
  for j in
    update public.jobs
       set status = 'failed', error_code = 'timeout', error_message = 'The job timed out.', updated_at = now()
     where status in ('queued', 'processing') and created_at < now() - interval '15 minutes'
    returning id, retry_of
  loop
    perform public.release_credits(j.id);
    if j.retry_of is not null then
      update public.jobs set retried = false where id = j.retry_of;
    end if;
  end loop;

  for j in
    select id
      from public.jobs
     where status = 'completed' and outputs is not null and updated_at < now() - interval '1 hour'
     order by updated_at
       for update skip locked
  loop
    perform public.settle_unconfirmed(j.id);
  end loop;

  update public.jobs set outputs = null
   where outputs is not null and status <> 'completed' and updated_at < now() - interval '1 hour';
  delete from public.jobs where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '12 months';

  delete from private.blocks
   where (lifted_at is not null and lifted_at < now() - interval '30 days')
      or created_at < now() - interval '12 months';
  delete from private.app_installs i
   where i.last_seen_at < now() - make_interval(days => pol.install_retention_days)
     and not exists (select 1 from private.blocks b where b.install_key = i.key and b.lifted_at is null);
  delete from private.strikes
   where created_at < now() - make_interval(days => pol.cooldown_window_days)
      or (user_id is null and install_key is null);
  delete from private.cooldowns
   where coalesce(lifted_at, ends_at) < now() - make_interval(days => pol.cooldown_window_days)
      or (user_id is null and install_key is null);
  delete from private.ip_usage where hour < now() - interval '1 day';
  delete from private.assist_usage where hour < now() - interval '1 day';
  delete from private.assist_ceilings where period < now() - interval '1 day';
  delete from private.ai_usage_daily where day < (now() at time zone 'utc')::date - 90;
  delete from private.ai_switches where paused_until < now() - interval '1 day';

  delete from private.polls where expires_at <= now();
  delete from private.poll_reports
   where created_at < now() - make_interval(days => (select p.report_retention_days from public.poll_policy() p));
  delete from private.poll_usage where period < now() - interval '2 days';
  delete from private.poll_image_loads where day < (now() at time zone 'utc')::date - 1;
  delete from private.poll_daily where day < (now() at time zone 'utc')::date - 90;
end $$;

-- MARK: Privileges

revoke all on function private.poll_bump(text, bigint) from public, anon, authenticated;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.poll_policy()',
    'public.poll_backstops()',
    'public.admit_poll(uuid, text, text, text, text)',
    'public.finish_poll_attempt(uuid, text, text, text, text)',
    'public.create_poll(uuid, text, text, text, text, int, int, int, int, text[], text, text)',
    'public.create_poll(uuid, text, text, text, text, int, int, int, int, text, text)',
    'public.poll_view(text, text, uuid, text)',
    'public.poll_image(text, text, text)',
    'public.my_polls(uuid, text, text)',
    'public.delete_poll(text, uuid)',
    'public.ops_polls_summary(date)',
    'public.ops_restore_poll(text)',
    'public.sweep_jobs()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
