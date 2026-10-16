-- The owner's admin page on aybuke.org (functions/admin, backend/README.md
-- "Admin API"): the gate that counts its requests and wrong tokens, the
-- actions it may take, and their audit.
-- ----------------------------------------------------------------------------
-- The page sends the public anon key (the gateway's JWT check) and the owner's
-- token in x-admin-token. The function compares SHA-256(token) with the secret
-- ADMIN_TOKEN_SHA256 in constant time, then asks admin_gate() whether this
-- address may go on: at most 60 requests a minute, and after 5 wrong or
-- missing tokens within 15 minutes nothing at all for 15 minutes, not even the
-- right token. Addresses are counted under a salted hash
-- (private.keyed_hash), never stored as they came.
--
-- What the page sees names nobody. Installs show as 'i-' and the first 12 hex
-- characters of their key (already a salted hash; ops_daily_summary() and
-- ops_poll_reports() shorten them the same way), users as 'u-' and 12 of a
-- salted hash of the id, addresses as 'a-' and 12 of their salted hash (the
-- rate limits' key). Block and unblock take those tags and find the install
-- or user again here, among those with strikes, cool-downs, blocks, reports,
-- poll reports or jobs.
--
-- Every action is written to private.admin_audit (time, action, the target's
-- tag, the address's tag, the outcome) and kept one year:
-- sweep_app_store_notifications(), the daily sweep, deletes older rows and
-- the gate's old counters.

-- MARK: Numbers

create function public.admin_policy(
  out requests_per_minute int,
  out failed_tokens int,
  out failure_window_minutes int,
  out lockout_minutes int,
  out pause_hours int,
  out audit_days int
)
language sql immutable
set search_path = ''
as $$
  select 60, 5, 15, 15, 24, 365
$$;

-- MARK: Tables

-- Requests per address and minute (a salted hash of the address).
create table private.admin_requests (
  ip_key text not null,
  minute timestamptz not null,
  requests int not null default 0 check (requests >= 0),
  primary key (ip_key, minute)
);
create index admin_requests_minute_idx on private.admin_requests (minute);

-- Wrong or missing tokens per address: the window they count in and the lock.
create table private.admin_failures (
  ip_key text primary key,
  window_started_at timestamptz not null,
  failures int not null default 0 check (failures >= 0),
  locked_until timestamptz
);

-- What the owner did from the page. Tags only: no id, key, address or token.
create table private.admin_audit (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  action text not null
    check (action in ('pause_ai', 'resume_ai', 'take_down_poll', 'restore_poll', 'block', 'unblock')),
  target_tag text check (target_tag ~ '^([iu]-[0-9a-f]{12}|p-[A-Za-z0-9_-]{6}|all|free)$'),
  address_tag text not null check (address_tag ~ '^a-([0-9a-f]{12}|unknown)$'),
  outcome text not null check (outcome in ('done', 'no_change', 'not_found'))
);
create index admin_audit_at_idx on private.admin_audit (at);

alter table private.admin_requests enable row level security;
alter table private.admin_failures enable row level security;
alter table private.admin_audit enable row level security;
revoke all on table private.admin_requests, private.admin_failures, private.admin_audit
  from public, anon, authenticated;

-- MARK: Tags

create function private.admin_install_tag(p_key text)
returns text
language sql immutable
set search_path = ''
as $$
  select case when p_key ~ '^[0-9a-f]{12}' then 'i-' || left(p_key, 12) end
$$;

create function private.admin_user_tag(p_user uuid)
returns text
language sql stable
set search_path = ''
as $$
  select case when p_user is not null then 'u-' || left(private.keyed_hash('admin_user', p_user::text), 12) end
$$;

-- The same key as the rate limits (and ops_daily_summary()'s top_ips), shortened.
create function private.admin_address_tag(p_ip text)
returns text
language sql stable
set search_path = ''
as $$
  select case when coalesce(p_ip, '') = '' then 'a-unknown' else 'a-' || left(private.keyed_hash('ip', p_ip), 12) end
$$;

-- The install or user behind a tag, among those the page can show. o_matches
-- is how many there were: anything but 1 means the tag can't be acted on.
create function private.admin_find(p_tag text, out o_install text, out o_user uuid, out o_matches int)
language plpgsql stable
set search_path = ''
as $$
begin
  o_matches := 0;
  if p_tag ~ '^i-[0-9a-f]{12}$' then
    select count(*)::int, (array_agg(k))[1] into o_matches, o_install
      from (select s.install_key as k from private.strikes s
            union select c.install_key from private.cooldowns c
            union select b.install_key from private.blocks b
            union select r.install_key from private.poll_reports r
            union select j.install_key from public.jobs j) keys
     where k is not null and left(k, 12) = substr(p_tag, 3);
  elsif p_tag ~ '^u-[0-9a-f]{12}$' then
    select count(*)::int, (array_agg(u))[1] into o_matches, o_user
      from (select s.user_id as u from private.strikes s
            union select c.user_id from private.cooldowns c
            union select b.user_id from private.blocks b
            union select r.user_id from public.reports r
            union select p.user_id from private.poll_reports p) users
     where u is not null and private.admin_user_tag(u) = p_tag;
  end if;
end $$;

-- MARK: Gate

-- One call per request, after the function checked the token. Answers
-- { ok: true }, or { ok: false, code, status, retry_after? }: 'locked_out'
-- (429) while a lock runs, 'rate_limited' (429) past 60 requests in the
-- minute, 'unauthorized' (401) for a wrong or missing token, whose 5th within
-- 15 minutes starts the lock. The right token forgives earlier misses.
create function public.admin_gate(p_ip text, p_token_ok boolean)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_now timestamptz := now();
  v_minute timestamptz := date_trunc('minute', now());
  v_key text := private.keyed_hash('admin_ip', coalesce(nullif(p_ip, ''), 'unknown'));
  v_window interval;
  v_locked timestamptz;
  v_requests int;
  v_failures int;
begin
  select * into pol from public.admin_policy();
  v_window := make_interval(mins => pol.failure_window_minutes);

  select f.locked_until into v_locked from private.admin_failures f where f.ip_key = v_key;
  if v_locked > v_now then
    return jsonb_build_object('ok', false, 'code', 'locked_out', 'status', 429,
                              'retry_after', greatest(1, ceil(extract(epoch from v_locked - v_now)))::int);
  end if;

  delete from private.admin_requests where minute < v_minute - interval '5 minutes';
  insert into private.admin_requests as r (ip_key, minute, requests) values (v_key, v_minute, 1)
    on conflict (ip_key, minute) do update set requests = r.requests + 1
  returning r.requests into v_requests;
  if v_requests > pol.requests_per_minute then
    return jsonb_build_object('ok', false, 'code', 'rate_limited', 'status', 429,
                              'retry_after', greatest(1, ceil(extract(epoch from v_minute + interval '1 minute' - v_now)))::int);
  end if;

  if p_token_ok then
    delete from private.admin_failures where ip_key = v_key;
    return jsonb_build_object('ok', true);
  end if;

  insert into private.admin_failures as f (ip_key, window_started_at, failures) values (v_key, v_now, 1)
    on conflict (ip_key) do update
      set failures = case when f.window_started_at <= v_now - v_window then 1 else f.failures + 1 end,
          window_started_at = case when f.window_started_at <= v_now - v_window then v_now else f.window_started_at end,
          locked_until = null
  returning f.failures into v_failures;
  if v_failures >= pol.failed_tokens then
    update private.admin_failures set locked_until = v_now + make_interval(mins => pol.lockout_minutes)
     where ip_key = v_key;
  end if;
  return jsonb_build_object('ok', false, 'code', 'unauthorized', 'status', 401);
end $$;

-- MARK: Reading

-- Whether AI is paused now, why and until when: the 'all' switch first, then
-- 'free' (free credits only). The reason is the switch's note: 'admin_page',
-- 'provider_billing', 'safety_check_errors' or the owner's own words.
create function public.admin_ai_state()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('paused', true, 'scope', s.scope, 'reason', coalesce(left(s.note, 120), 'owner'),
                               'until', s.paused_until)
       from private.ai_switches s
      where s.paused_until > now()
      order by (s.scope = 'all') desc
      limit 1),
    jsonb_build_object('paused', false))
$$;

-- Reported polls, content reports and strikes of the last p_days days (1–30),
-- from ops_poll_reports(), ops_reports() and ops_strikes(), with tags in place
-- of user ids and install keys. Poll ids stay: the page acts on them.
create function public.admin_moderation(p_days int default 7)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 7), 30));
begin
  return jsonb_build_object(
    'poll_reports', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'poll_id', r.poll_id, 'reports', r.reports, 'open_reports', r.open_reports,
               'reasons', to_jsonb(r.reasons), 'first_report_at', r.first_report_at,
               'last_report_at', r.last_report_at, 'took_down', r.took_down, 'poll_state', r.poll_state,
               'expires_at', r.expires_at, 'user', private.admin_user_tag(r.user_id),
               'install', private.admin_install_tag(r.install_key))
             order by r.last_report_at desc), '[]'::jsonb)
        from public.ops_poll_reports(v_days) r),
    'reports', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'created_at', r.created_at, 'reason', r.reason, 'details', r.details, 'status', r.status,
               'operation', r.operation, 'template_id', r.template_id, 'user', private.admin_user_tag(r.user_id),
               'install', private.admin_install_tag(r.install_key), 'user_strikes_30d', r.user_strikes_30d,
               'install_strikes_30d', r.install_strikes_30d, 'install_blocked', r.install_blocked)
             order by r.created_at desc), '[]'::jsonb)
        from public.ops_reports(null, 50) r
       where r.created_at > now() - make_interval(days => v_days)),
    'strikes', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'install', private.admin_install_tag(s.install_key),
               'users', (select coalesce(jsonb_agg(private.admin_user_tag(u)), '[]'::jsonb)
                           from unnest(s.user_ids[1:10]) u),
               'user_count', coalesce(cardinality(s.user_ids), 0), 'strikes', s.strikes,
               'prompt_strikes', s.prompt_strikes, 'output_strikes', s.output_strikes,
               'categories', to_jsonb(s.categories), 'last_strike_at', s.last_strike_at,
               'cooldowns', s.cooldowns, 'cooldown_until', s.cooldown_until, 'blocked', s.blocked)
             order by s.strikes desc, s.last_strike_at desc), '[]'::jsonb)
        from (select * from public.ops_strikes(v_days) limit 100) s));
end $$;

-- The newest audit rows (at most 200), newest first.
create function public.admin_audit_recent(p_limit int default 50)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'at', a.at, 'action', a.action, 'target', a.target_tag, 'address', a.address_tag, 'outcome', a.outcome))
         order by a.at desc, a.id desc), '[]'::jsonb)
    from (select * from private.admin_audit
           order by at desc, id desc
           limit greatest(1, least(coalesce(p_limit, 50), 200))) a
$$;

-- MARK: Actions

-- One action from the page, through the ops_* tools, and its audit row in the
-- same transaction. Answers { ok: true, result } (result.outcome is 'done' or
-- 'no_change'), or { ok: false, code, status }: 'bad_request' (400, not
-- audited), 'not_found' (404) or 'ambiguous' (409, a tag that matches more
-- than one install or user; audited as not_found).
--   pause_ai        target 'all' (default) or 'free'; 24 hours, never
--                   shortening a longer pause (the provider's 30 days)
--   resume_ai       target 'all', 'free' or none (both)
--   take_down_poll, restore_poll   target a poll id
--   block, unblock  target an 'i-' or 'u-' tag
create function public.admin_action(p_action text, p_target text default null, p_ip text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  pol record;
  v_target text := nullif(p_target, '');
  v_tag text;
  v_outcome text := 'done';
  v_result jsonb;
  v_flag boolean;
  v_until timestamptz;
  v_found record;
  c_bad_request constant jsonb := jsonb_build_object('ok', false, 'code', 'bad_request', 'status', 400);
begin
  select * into pol from public.admin_policy();
  case p_action
    when 'pause_ai', 'resume_ai' then
      if v_target is not null and v_target not in ('all', 'free') then
        return c_bad_request;
      end if;
      if p_action = 'pause_ai' then
        v_tag := coalesce(v_target, 'all');
        select s.paused_until into v_until from private.ai_switches s
         where s.scope = v_tag and s.paused_until >= now() + make_interval(hours => pol.pause_hours);
        if found then
          v_outcome := 'no_change';
          v_result := jsonb_build_object('scope', v_tag, 'paused_until', v_until);
        else
          v_result := public.ops_pause_ai(v_tag, pol.pause_hours, 'admin_page');
        end if;
      else
        v_tag := v_target;
        v_result := public.ops_resume_ai(v_target);
        if jsonb_array_length(v_result -> 'resumed') = 0 then
          v_outcome := 'no_change';
        end if;
      end if;

    when 'take_down_poll', 'restore_poll' then
      if v_target is null or v_target !~ '^[A-Za-z0-9_-]{16}$' then
        return c_bad_request;
      end if;
      v_tag := 'p-' || left(v_target, 6);
      if not exists (select 1 from private.polls p where p.id = v_target and p.expires_at > now()) then
        insert into private.admin_audit (action, target_tag, address_tag, outcome)
          values (p_action, v_tag, private.admin_address_tag(p_ip), 'not_found');
        return jsonb_build_object('ok', false, 'code', 'not_found', 'status', 404);
      end if;
      if p_action = 'take_down_poll' then
        v_flag := public.ops_take_down_poll(v_target);
        v_result := jsonb_build_object('taken_down', v_flag);
      else
        v_flag := public.ops_restore_poll(v_target);
        v_result := jsonb_build_object('restored', v_flag);
      end if;
      if not v_flag then
        v_outcome := 'no_change';
      end if;

    when 'block', 'unblock' then
      if v_target is null or v_target !~ '^[iu]-[0-9a-f]{12}$' then
        return c_bad_request;
      end if;
      v_tag := v_target;
      select * into v_found from private.admin_find(v_target);
      if v_found.o_matches <> 1 then
        insert into private.admin_audit (action, target_tag, address_tag, outcome)
          values (p_action, v_tag, private.admin_address_tag(p_ip), 'not_found');
        return case when v_found.o_matches > 1
                    then jsonb_build_object('ok', false, 'code', 'ambiguous', 'status', 409)
                    else jsonb_build_object('ok', false, 'code', 'not_found', 'status', 404) end;
      end if;
      if p_action = 'block' then
        v_flag := not exists (select 1 from private.blocks b
                               where b.lifted_at is null
                                 and (b.install_key = v_found.o_install or b.user_id = v_found.o_user));
        perform public.ops_block(v_found.o_install, v_found.o_user, null, 'admin_page');
        v_result := jsonb_build_object('blocked', true, 'new_block', v_flag);
        if not v_flag then
          v_outcome := 'no_change';
        end if;
      else
        v_result := public.ops_unblock(v_found.o_install, v_found.o_user);
        if (v_result ->> 'blocks_lifted')::int + (v_result ->> 'cooldowns_lifted')::int = 0 then
          v_outcome := 'no_change';
        end if;
      end if;

    else
      return c_bad_request;
  end case;

  insert into private.admin_audit (action, target_tag, address_tag, outcome)
    values (p_action, v_tag, private.admin_address_tag(p_ip), v_outcome);
  return jsonb_build_object('ok', true, 'result', v_result || jsonb_build_object('outcome', v_outcome));
end $$;

-- MARK: Housekeeping

-- The 20261030000000 sweep, plus the admin page's audit after a year and its
-- gate counters after a day (the gate itself drops minutes older than five).
create or replace function public.sweep_app_store_notifications()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_cutoff timestamptz := now() - interval '30 days';
begin
  delete from private.app_store_notifications where received_at < v_cutoff;

  -- Rows a notification holds are left for tomorrow's sweep (or that
  -- notification's own prune): waiting for them could deadlock with it, as in
  -- 20261025000003.
  delete from private.refunded_transactions t
   where (t.kind, t.transaction_id) in (
     select o.kind, o.transaction_id from private.refunded_transactions o
      where
        -- A reversed refund: 30 days after the reversal. A refund that came
        -- after it would have cleared reversed_at, so it is the newest event.
        (o.reversed_at is not null and greatest(o.refunded_at, o.reversed_at) < v_cutoff)
        -- A refunded subscription period: 30 days after the later of the
        -- refund and the period's end. Without a known end (Apple always
        -- sends one) it covers every period and stays, like the dispatcher.
        or (o.reversed_at is null and o.kind = 'pro' and o.refunded_at < v_cutoff and o.period_end < v_cutoff)
        -- A refunded pack that stays refunded is never due: its signed
        -- transaction never expires.
        for update skip locked);

  delete from private.admin_audit
   where at < now() - make_interval(days => (select p.audit_days from public.admin_policy() p));
  delete from private.admin_requests where minute < now() - interval '1 day';
  delete from private.admin_failures
   where window_started_at < now() - interval '1 day' and (locked_until is null or locked_until < now());
end $$;

-- MARK: Privileges

revoke all on function private.admin_install_tag(text) from public, anon, authenticated;
revoke all on function private.admin_user_tag(uuid) from public, anon, authenticated;
revoke all on function private.admin_address_tag(text) from public, anon, authenticated;
revoke all on function private.admin_find(text) from public, anon, authenticated;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.admin_policy()',
    'public.admin_gate(text, boolean)',
    'public.admin_ai_state()',
    'public.admin_moderation(int)',
    'public.admin_audit_recent(int)',
    'public.admin_action(text, text, text)',
    'public.sweep_app_store_notifications()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
