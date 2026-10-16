-- "Which vibe?" polls with friends (functions/polls, Aybuke 1.1).
-- ----------------------------------------------------------------------------
-- She shares two of her own pictures (A and B) and an optional question as a
-- private link (https://aybuke.org/p/<id>); friends open it in a browser and
-- tap A or B; she sees the counts in the app. Link-only by design: no feed,
-- no listing, no profiles, no comments, no names.
--
--   1. POST /polls: the function checks the body and the question (the
--      prompt policy), then admit_poll() refuses a block, a cool-down, a
--      pause of AI for everyone ('all' in private.ai_switches: the check needs
--      Claude) and the limits in poll_policy(): 3 polls a day (UTC) per user
--      and per App Store install, 10 an hour per network address, 300 a day
--      for everyone. Every admitted attempt counts, a blocked question
--      included (no strike: polls never write strikes). The function then
--      re-encodes both pictures (at most 720 px, JPEG, no metadata), Claude
--      checks both (fail closed), and create_poll() stores them. A check that
--      couldn't run gives the attempt back (finish_poll_attempt()).
--   2. GET /polls?id=: poll_view(); the counts only for a voter who voted
--      (her voter code) or the creator. The pictures come from poll_image()
--      through short-lived signed URLs; each load counts per address, per
--      poll and per day, so one poll (or one address) can't use up the
--      project's egress.
--   3. POST /polls/vote: cast_poll_vote(), one vote per voter code and poll
--      (voting again changes it). Only a salted hash of the code is kept,
--      salted with the poll id too, so votes in two polls can't be linked.
--   4. POST /polls/report: report_poll(). 'sexual' or 'minor' takes the poll
--      down at once, any reason from 3 different addresses too. A poll taken
--      down answers 404 to everyone and is kept until its 24 hours end, so
--      the owner can review it (ops_poll_reports(), ops_poll_image()), then
--      it goes like every poll.
--   5. GET /polls/mine and DELETE /polls?id=: my_polls() and delete_poll().
--
-- Storage: the pictures live in private.polls (bytea, a re-encoded JPEG of
-- about 40–120 KB each), not in Supabase Storage: SQL can create a bucket but
-- can't delete its files (deleting storage.objects rows leaves the file
-- behind, or is refused), and pg_net is off, so the 5-minute cron couldn't
-- call the Storage API. In a table, sweep_jobs() deletes a poll with its
-- pictures and votes within 5 minutes of its end, and deleting the account
-- deletes them at once (on delete cascade).
--
-- Retention: a poll and its votes 24 hours (poll_policy().lifetime_hours);
-- report records 30 days (or with the creator's account); the per-address,
-- per-user and per-install counters (salted hashes) 2 days; the daily counts
-- (no ids) 90 days.

-- MARK: Policy

-- The numbers. Change them here (a new migration that replaces the function)
-- to retune polls without an app update. The egress budget is the reason for
-- the picture-load caps: each load sends about 60 KB to the browser, and about
-- 80 KB more from the database to the function (backend/README.md, "Polls").
create function public.poll_policy(
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
  select 24, 3, 3, 10, 300, 120, 600, 200, 600, 2000, 10, 3, 30
$$;

-- MARK: Tables

create table private.polls (
  -- 12 random bytes as base64url: the link's only secret.
  id text primary key check (id ~ '^[A-Za-z0-9_-]{16}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- private.keyed_hash('app_transaction', …) of a verified install, or null.
  install_key text,
  -- At most 80 characters as she counts them (emoji sequences are one each).
  question text check (question is null or char_length(question) between 1 and 1000),
  locale text not null default 'en' check (locale ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  -- Re-encoded JPEGs (at most 720 px, no metadata); never compressed again.
  image_a bytea not null check (octet_length(image_a) between 100 and 1048576),
  image_b bytea not null check (octet_length(image_b) between 100 and 1048576),
  a_width int not null check (a_width between 1 and 720),
  a_height int not null check (a_height between 1 and 720),
  b_width int not null check (b_width between 1 and 720),
  b_height int not null check (b_height between 1 and 720),
  image_loads int not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  taken_down_at timestamptz
);
alter table private.polls alter column image_a set storage external;
alter table private.polls alter column image_b set storage external;
create index polls_user_idx on private.polls (user_id);
create index polls_expires_idx on private.polls (expires_at);

create table private.poll_votes (
  poll_id text not null references private.polls (id) on delete cascade,
  -- private.keyed_hash('poll_voter', poll id || ':' || voter code).
  voter text not null,
  choice text not null check (choice in ('a', 'b')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (poll_id, voter)
);

-- Who reported a poll while it lives (a salted address hash), to count
-- different reporters. Deleted with the poll.
create table private.poll_reporters (
  poll_id text not null references private.polls (id) on delete cascade,
  reporter text not null,
  created_at timestamptz not null default now(),
  primary key (poll_id, reporter)
);

-- The owner's record of reports, kept 30 days: no reporter, no content.
create table private.poll_reports (
  id uuid primary key default gen_random_uuid(),
  -- No foreign key: the record outlives the poll (deleted after 24 hours).
  poll_id text not null,
  -- The creator, so the owner can act on repeated abuse (ops_block()).
  user_id uuid references auth.users (id) on delete cascade,
  install_key text,
  reason text not null check (reason in ('sexual', 'minor', 'bullying', 'privacy', 'harmful', 'other')),
  took_down boolean not null default false,
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);
create index poll_reports_poll_idx on private.poll_reports (poll_id);
create index poll_reports_created_idx on private.poll_reports (created_at);
create index poll_reports_user_idx on private.poll_reports (user_id);

-- Rate limit counters under salted hashes (private.keyed_hash): never a raw
-- user id or address. Deleted after 2 days by sweep_jobs().
create table private.poll_usage (
  kind text not null check (kind in ('create_user', 'create_install', 'create_ip', 'view_ip', 'image_ip', 'vote_ip',
                                     'report_ip')),
  bucket text not null,
  -- The UTC day (create_user, create_install) or hour (the rest).
  period timestamptz not null,
  count int not null default 0 check (count >= 0),
  primary key (kind, bucket, period)
);
create index poll_usage_period_idx on private.poll_usage (period);

-- The owner's daily numbers (ops_polls_summary(), the daily digest). No ids.
create table private.poll_daily (
  day date primary key,
  attempts int not null default 0,
  created int not null default 0,
  blocked_question int not null default 0,
  blocked_image int not null default 0,
  invalid_image int not null default 0,
  unavailable int not null default 0,
  deleted int not null default 0,
  votes int not null default 0,
  reports int not null default 0,
  takedowns int not null default 0,
  image_loads int not null default 0,
  image_bytes bigint not null default 0
);

alter table private.polls enable row level security;
alter table private.poll_votes enable row level security;
alter table private.poll_reporters enable row level security;
alter table private.poll_reports enable row level security;
alter table private.poll_usage enable row level security;
alter table private.poll_daily enable row level security;
revoke all on table private.polls, private.poll_votes, private.poll_reporters, private.poll_reports,
  private.poll_usage, private.poll_daily from public, anon, authenticated;

-- MARK: Helpers

-- 12 random bytes (pg_strong_random through gen_random_uuid(): its first 6
-- and last 6 bytes carry no version or variant bits) as 16 base64url
-- characters, 96 bits nobody can guess.
create function private.new_poll_id()
returns text
language sql volatile
set search_path = ''
as $$
  select translate(encode(substring(b from 1 for 6) || substring(b from 11 for 6), 'base64'), '+/', '-_')
    from (select decode(replace(gen_random_uuid()::text, '-', ''), 'hex') as b) s
$$;

-- The verified install's key, as touch_install() makes it (and blocks use it).
create function private.poll_install_key(p_app_transaction_id text, p_install_status text)
returns text
language sql stable
set search_path = ''
as $$
  select case when p_install_status = 'verified' and coalesce(p_app_transaction_id, '') <> ''
              then private.keyed_hash('app_transaction', p_app_transaction_id) end
$$;

create function private.poll_today()
returns date
language sql stable
set search_path = ''
as $$
  select (now() at time zone 'utc')::date
$$;

-- Adds p_by to a counter and returns its new value (never below 0).
create function private.poll_count(p_kind text, p_bucket text, p_period timestamptz, p_by int default 1)
returns int
language sql volatile
set search_path = ''
as $$
  insert into private.poll_usage as u (kind, bucket, period, count)
    values (p_kind, p_bucket, p_period, greatest(p_by, 0))
    on conflict (kind, bucket, period) do update set count = greatest(u.count + p_by, 0)
    returning u.count
$$;

-- Adds to one of today's numbers.
create function private.poll_bump(p_field text, p_by bigint default 1)
returns void
language plpgsql volatile
set search_path = ''
as $$
begin
  if p_field not in ('attempts', 'created', 'blocked_question', 'blocked_image', 'invalid_image', 'unavailable',
                     'deleted', 'votes', 'reports', 'takedowns', 'image_loads', 'image_bytes') then
    raise exception 'unknown poll number %', p_field;
  end if;
  insert into private.poll_daily (day) values (private.poll_today()) on conflict (day) do nothing;
  execute format('update private.poll_daily set %1$I = greatest(%1$I + $1, 0) where day = $2', p_field)
    using p_by, private.poll_today();
end $$;

-- A live poll: made, not ended, not taken down.
create function private.poll_live(p_poll text)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from private.polls where id = p_poll and expires_at > now() and taken_down_at is null)
$$;

create function private.poll_counts(p_poll text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object('a', count(*) filter (where choice = 'a'), 'b', count(*) filter (where choice = 'b'))
    from private.poll_votes where poll_id = p_poll
$$;

create function private.poll_not_found()
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_build_object('ok', false, 'code', 'not_found', 'status', 404)
$$;

-- An hourly per-address limit: the new count, or null without an address.
create function private.poll_ip_count(p_kind text, p_ip text)
returns int
language sql volatile
set search_path = ''
as $$
  select case when coalesce(p_ip, '') <> ''
              then private.poll_count(p_kind, private.keyed_hash('ip', p_ip), date_trunc('hour', now())) end
$$;

create function private.poll_hour_limited()
returns jsonb
language sql stable
set search_path = ''
as $$
  select private.error('rate_limited', 429, date_trunc('hour', now()) + interval '1 hour')
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'private.new_poll_id()',
    'private.poll_install_key(text, text)',
    'private.poll_today()',
    'private.poll_count(text, text, timestamptz, int)',
    'private.poll_bump(text, bigint)',
    'private.poll_live(text)',
    'private.poll_counts(text)',
    'private.poll_not_found()',
    'private.poll_ip_count(text, text)',
    'private.poll_hour_limited()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;

-- MARK: Creating a poll

-- Before the pictures are decoded or checked. In this order: a block (403
-- install_blocked) or a cool-down (429 cooldown) of the user or her install
-- (or, without a verified install, her address, as admit_job() keys them);
-- AI paused for everyone (503 safety_unavailable: the check needs Claude);
-- today's polls for everyone; 3 a day per user and per install; 10 an hour
-- per address (429 rate_limited). A refused request leaves every count as it
-- was. Then the attempt counts, and a question the prompt policy blocked
-- (p_blocked_category) answers 422 content_blocked, counted but never a strike.
create function public.admit_poll(
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
  v_today date := private.poll_today();
  v_day timestamptz := private.next_utc_day() - interval '1 day';
  v_install text := private.poll_install_key(p_app_transaction_id, p_install_status);
  v_abuse text;
  v_until timestamptz;
  v_attempts int;
  v_user int;
  v_install_count int;
  v_ip int;
begin
  if p_user is null then
    raise exception 'no user';
  end if;
  select * into pol from public.poll_policy();
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
  select attempts into v_attempts from private.poll_daily where day = v_today for update;
  if v_attempts >= pol.polls_all_daily then
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

  update private.poll_daily set attempts = attempts + 1 where day = v_today;
  if p_blocked_category is not null then
    update private.poll_daily set blocked_question = blocked_question + 1 where day = v_today;
    return jsonb_build_object('ok', false, 'code', 'content_blocked', 'status', 422, 'category', p_blocked_category);
  end if;
  return jsonb_build_object(
    'ok', true,
    'remaining_today', greatest(0, least(pol.polls_per_user_daily - v_user,
                                         coalesce(pol.polls_per_install_daily - v_install_count, pol.polls_per_user_daily)))
  );
end $$;

-- How an admitted attempt ended without a poll: 'image_blocked' (the safety
-- check flagged a picture) and 'image_invalid' (a picture couldn't be read)
-- keep the attempt; 'unavailable' (the check couldn't run, or the poll
-- couldn't be stored) gives it back to the user, install and address.
create function public.finish_poll_attempt(
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
  elsif p_outcome = 'unavailable' then
    perform private.poll_bump('unavailable');
    perform private.poll_bump('attempts', -1);
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

-- Stores an admitted poll whose pictures passed the safety check. The
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
  select * into pol from public.poll_policy();
  v_expires := now() + make_interval(hours => pol.lifetime_hours);
  loop
    v_id := private.new_poll_id();
    begin
      insert into private.polls (id, user_id, install_key, question, locale, image_a, image_b,
                                 a_width, a_height, b_width, b_height, expires_at)
        values (v_id, p_user, private.poll_install_key(p_app_transaction_id, p_install_status),
                nullif(p_question, ''), coalesce(nullif(p_locale, ''), 'en'),
                decode(p_image_a, 'base64'), decode(p_image_b, 'base64'),
                p_a_width, p_a_height, p_b_width, p_b_height, v_expires);
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

-- MARK: Viewing and voting

-- The poll as the page shows it, or 404 not_found (never made, ended, deleted
-- or taken down: one answer for all). p_voter is the visitor's code, p_user
-- the caller's session (the creator sees the counts without voting). 600
-- views an hour per address.
create function public.poll_view(
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
  select p.user_id, p.question, p.locale, p.created_at, p.expires_at, p.a_width, p.a_height, p.b_width, p.b_height
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
    'is_creator', v_creator,
    'my_vote', v_vote,
    'votes', case when v_creator or v_vote is not null then private.poll_counts(p_poll) end
  );
end $$;

-- One picture of a live poll, as base64. Every load counts: 200 an hour per
-- address, 600 per poll, image_loads_daily for everyone (429 rate_limited).
create function public.poll_image(p_poll text, p_side text, p_ip text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_loads int;
  v_image bytea;
  v_today int;
begin
  if p_side is null or p_side not in ('a', 'b') then
    return private.error('bad_request', 400);
  end if;
  select * into pol from public.poll_policy();
  if private.poll_ip_count('image_ip', p_ip) > pol.image_loads_per_ip_hourly then
    return private.poll_hour_limited();
  end if;
  select d.image_loads into v_today from private.poll_daily d where d.day = private.poll_today();
  if coalesce(v_today, 0) >= pol.image_loads_daily then
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
  perform private.poll_bump('image_loads');
  perform private.poll_bump('image_bytes', octet_length(v_image));
  return jsonb_build_object('ok', true, 'image', translate(encode(v_image, 'base64'), E'\n', ''),
                            'bytes', octet_length(v_image));
end $$;

-- A visitor's vote: one per voter code and poll, and voting again changes it.
-- 120 an hour per address.
create function public.cast_poll_vote(p_poll text, p_voter text, p_choice text, p_ip text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_new boolean;
begin
  if p_choice is null or p_choice not in ('a', 'b') or p_voter is null or p_voter !~ '^[A-Za-z0-9_-]{16,128}$' then
    return private.error('bad_request', 400);
  end if;
  select * into pol from public.poll_policy();
  if private.poll_ip_count('vote_ip', p_ip) > pol.votes_per_ip_hourly then
    return private.poll_hour_limited();
  end if;
  if not private.poll_live(p_poll) then
    return private.poll_not_found();
  end if;
  begin
    insert into private.poll_votes as v (poll_id, voter, choice)
      values (p_poll, private.keyed_hash('poll_voter', p_poll || ':' || p_voter), p_choice)
      on conflict (poll_id, voter) do update set choice = excluded.choice, updated_at = now()
      returning (xmax = 0) into v_new;
  exception when foreign_key_violation then
    -- Deleted in between.
    return private.poll_not_found();
  end;
  if v_new then
    perform private.poll_bump('votes');
  end if;
  return jsonb_build_object('ok', true, 'votes', private.poll_counts(p_poll), 'my_vote', p_choice);
end $$;

-- MARK: Her polls

-- Her polls that haven't ended, newest first, with today's polls left.
create function public.my_polls(
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
           'votes', private.poll_counts(p.id)
         ) order by p.created_at desc), '[]'::jsonb)
    into v_list
    from private.polls p
   where p.user_id = p_user and p.expires_at > now();
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

-- She deletes her poll now: the pictures, the question and the votes.
create function public.delete_poll(p_poll text, p_user uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  delete from private.polls where id = p_poll and user_id = p_user;
  if not found then
    return jsonb_build_object('deleted', false);
  end if;
  perform private.poll_bump('deleted');
  return jsonb_build_object('deleted', true);
end $$;

-- MARK: Reports

-- A visitor's report (anonymous; 10 an hour per address). 'sexual' or
-- 'minor' takes the poll down at once, any reason from takedown_reports
-- different addresses too. The owner's record keeps the creator, not the
-- reporter.
create function public.report_poll(p_poll text, p_reason text, p_ip text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v record;
  v_report uuid;
  v_reporters int;
  v_down boolean := false;
begin
  if p_reason is null or p_reason not in ('sexual', 'minor', 'bullying', 'privacy', 'harmful', 'other') then
    return private.error('bad_request', 400);
  end if;
  select * into pol from public.poll_policy();
  if private.poll_ip_count('report_ip', p_ip) > pol.reports_per_ip_hourly then
    return private.poll_hour_limited();
  end if;
  select p.user_id, p.install_key into v
    from private.polls p
   where p.id = p_poll and p.expires_at > now() and p.taken_down_at is null
     for update;
  if not found then
    return private.poll_not_found();
  end if;
  insert into private.poll_reports (poll_id, user_id, install_key, reason)
    values (p_poll, v.user_id, v.install_key, p_reason)
    returning id into v_report;
  insert into private.poll_reporters (poll_id, reporter)
    values (p_poll, coalesce(case when coalesce(p_ip, '') <> '' then private.keyed_hash('ip', p_ip) end,
                             'unknown:' || gen_random_uuid()))
    on conflict do nothing;
  perform private.poll_bump('reports');
  select count(*) into v_reporters from private.poll_reporters where poll_id = p_poll;
  if p_reason in ('sexual', 'minor') or v_reporters >= pol.takedown_reports then
    update private.polls set taken_down_at = now() where id = p_poll;
    update private.poll_reports set took_down = true where id = v_report;
    perform private.poll_bump('takedowns');
    v_down := true;
  end if;
  return jsonb_build_object('ok', true, 'reported', true, 'taken_down', v_down);
end $$;

-- MARK: Owner tools (SQL editor, service role)

-- A day's numbers (yesterday by default, UTC) and what is live now.
create function public.ops_polls_summary(p_day date default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_day date := coalesce(p_day, private.poll_today() - 1);
  v jsonb;
begin
  select * into pol from public.poll_policy();
  select to_jsonb(d) - 'day' into v from private.poll_daily d where d.day = v_day;
  v := coalesce(v, jsonb_build_object('attempts', 0, 'created', 0, 'blocked_question', 0, 'blocked_image', 0,
                                      'invalid_image', 0, 'unavailable', 0, 'deleted', 0, 'votes', 0, 'reports', 0,
                                      'takedowns', 0, 'image_loads', 0, 'image_bytes', 0));
  return v || jsonb_build_object(
    'day', v_day,
    'image_mb', round((v->>'image_bytes')::numeric / 1048576, 1),
    'live_now', (select count(*) from private.polls where expires_at > now() and taken_down_at is null),
    'taken_down_now', (select count(*) from private.polls where expires_at > now() and taken_down_at is not null),
    'reports_open', (select count(*) from private.poll_reports where status = 'open'),
    'polls_cap', pol.polls_all_daily,
    'image_loads_cap', pol.image_loads_daily
  );
end $$;

-- Reported polls of the last p_days days, newest report first. poll_state is
-- 'live', 'taken_down' (still reviewable with ops_poll_image() until
-- expires_at) or 'gone'. Act with ops_take_down_poll(), ops_restore_poll(),
-- ops_set_poll_report_status() and ops_block(p_user => …) or ops_block(p_install => …).
create function public.ops_poll_reports(p_days int default 7)
returns table (
  poll_id text,
  reports int,
  open_reports int,
  reasons text[],
  first_report_at timestamptz,
  last_report_at timestamptz,
  took_down boolean,
  poll_state text,
  expires_at timestamptz,
  user_id uuid,
  install_key text
)
language sql stable security definer
set search_path = ''
as $$
  select r.poll_id,
         count(*)::int,
         (count(*) filter (where r.status = 'open'))::int,
         array_agg(distinct r.reason),
         min(r.created_at),
         max(r.created_at),
         bool_or(r.took_down),
         case when p.id is null then 'gone' when p.taken_down_at is not null then 'taken_down' else 'live' end,
         p.expires_at,
         (array_agg(r.user_id))[1],
         left((array_agg(r.install_key))[1], 12)
    from private.poll_reports r
    left join private.polls p on p.id = r.poll_id
   where r.created_at > now() - make_interval(days => p_days)
   group by r.poll_id, p.id, p.taken_down_at, p.expires_at
   order by max(r.created_at) desc
$$;

-- A picture of a poll that still exists, as a data URI to review a report.
create function public.ops_poll_image(p_poll text, p_side text)
returns text
language sql stable security definer
set search_path = ''
as $$
  select 'data:image/jpeg;base64,' || translate(encode(case p_side when 'a' then image_a else image_b end, 'base64'),
                                                E'\n', '')
    from private.polls where id = p_poll and p_side in ('a', 'b')
$$;

create function public.ops_take_down_poll(p_poll text)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  update private.polls set taken_down_at = now()
   where id = p_poll and taken_down_at is null and expires_at > now();
  if not found then
    return false;
  end if;
  perform private.poll_bump('takedowns');
  return true;
end $$;

-- Undoes a takedown that was a mistake: the poll answers again until its
-- 24 hours end, its reporters start from none and its open reports are dismissed.
create function public.ops_restore_poll(p_poll text)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  update private.polls set taken_down_at = null
   where id = p_poll and taken_down_at is not null and expires_at > now();
  if not found then
    return false;
  end if;
  delete from private.poll_reporters where poll_id = p_poll;
  update private.poll_reports set status = 'dismissed' where poll_id = p_poll and status = 'open';
  return true;
end $$;

create function public.ops_set_poll_report_status(p_poll text, p_status text)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if p_status not in ('open', 'reviewed', 'actioned', 'dismissed') then
    raise exception 'unknown status %', p_status;
  end if;
  update private.poll_reports set status = p_status where poll_id = p_poll;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- MARK: Housekeeping

-- The 20261031000000 cleanup, plus polls: a poll (pictures, question, votes,
-- reporters) within 5 minutes of its end, report records after 30 days, the
-- counters after 2 days and the daily numbers after 90 days.
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
  delete from private.ai_usage_daily where day < (now() at time zone 'utc')::date - 90;
  delete from private.ai_switches where paused_until < now() - interval '1 day';

  delete from private.polls where expires_at <= now();
  delete from private.poll_reports
   where created_at < now() - make_interval(days => (select p.report_retention_days from public.poll_policy() p));
  delete from private.poll_usage where period < now() - interval '2 days';
  delete from private.poll_daily where day < (now() at time zone 'utc')::date - 90;
end $$;

-- MARK: Accounts

-- The 20261101000000 merge, plus her polls and their report records: after
-- Sign in with Apple, the anonymous user is deleted, and her live polls would
-- go with it.
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
  update private.polls set user_id = p_to where user_id = p_from;
  update private.poll_reports set user_id = p_to where user_id = p_from;
  if not exists (select 1 from private.blocks where user_id = p_to and lifted_at is null) then
    update private.blocks set user_id = p_to where user_id = p_from and lifted_at is null;
  end if;

  select * into dst from public.credit_wallets where user_id = p_to;
  return dst;
end $$;

-- MARK: Privileges

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.poll_policy()',
    'public.admit_poll(uuid, text, text, text, text)',
    'public.finish_poll_attempt(uuid, text, text, text, text)',
    'public.create_poll(uuid, text, text, text, text, int, int, int, int, text, text)',
    'public.poll_view(text, text, uuid, text)',
    'public.poll_image(text, text, text)',
    'public.cast_poll_vote(text, text, text, text)',
    'public.my_polls(uuid, text, text)',
    'public.delete_poll(text, uuid)',
    'public.report_poll(text, text, text)',
    'public.ops_polls_summary(date)',
    'public.ops_poll_reports(int)',
    'public.ops_poll_image(text, text)',
    'public.ops_take_down_poll(text)',
    'public.ops_restore_poll(text)',
    'public.ops_set_poll_report_status(text, text)',
    'public.sweep_jobs()',
    'public.merge_accounts(uuid, uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
