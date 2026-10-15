-- A circuit breaker for the independent safety check (_shared/safety.ts).
-- ----------------------------------------------------------------------------
-- The check fails closed, so while Anthropic is down every job is refunded.
-- An edit stops at the photo check before the image model, but a creation has
-- no photo: xAI makes (and bills) the image, then the result check fails and
-- the job is refunded. A long outage would drain the xAI balance for nothing.
--
-- So ai-image reports every safety check that couldn't run (an error, a
-- timeout, an answer we can't read; never a verdict, a refusal or an image the
-- model can't take) with note_safety_check_error(). Three of them within ten
-- minutes turn the 'all' pause on (private.ai_switches, as ops_pause_ai()
-- sets it, note 'safety_check_errors'), so admit_job() refuses new jobs with
-- ai_paused before anything is charged or sent to xAI. The pause lasts five
-- minutes; when the breaker trips again within 15 minutes of the last pause
-- ending, it doubles, up to an hour. After a pause the next jobs run normally
-- (and three more errors trip it again). Errors reported while AI is paused
-- (jobs that were already running) don't count.
--
-- It never shortens or replaces a pause that is already on (the owner's, or
-- the provider billing pause), and select public.ops_resume_ai(); ends it like
-- any other pause.

create table private.safety_breaker (
  id boolean primary key default true check (id),
  -- The latest errors in the window, newest first, at most three.
  recent_errors timestamptz[] not null default '{}',
  last_error text,
  last_error_at timestamptz,
  tripped_at timestamptz,
  pause_minutes int,
  trips int not null default 0
);

alter table private.safety_breaker enable row level security;
revoke all on table private.safety_breaker from public, anon, authenticated;

insert into private.safety_breaker default values on conflict (id) do nothing;

-- One safety check couldn't run. Returns the end of the pause this call
-- started, or null when it started none.
create function public.note_safety_check_error(p_detail text default null)
returns timestamptz
language plpgsql security definer
set search_path = ''
as $$
declare
  c_errors constant int := 3;
  c_window constant interval := interval '10 minutes';
  c_first_pause constant int := 5;
  c_longest_pause constant int := 60;
  c_again_within constant interval := interval '15 minutes';
  v_now timestamptz := now();
  b private.safety_breaker;
  v_minutes int;
  v_until timestamptz;
begin
  insert into private.safety_breaker default values on conflict (id) do nothing;
  -- One caller at a time, so concurrent errors count exactly once each.
  select * into b from private.safety_breaker for update;
  update private.safety_breaker set last_error = left(p_detail, 200), last_error_at = v_now;

  if exists (select 1 from private.ai_switches s where s.scope = 'all' and s.paused_until > v_now) then
    return null;
  end if;

  b.recent_errors := array(
    select t from unnest(array_prepend(v_now, b.recent_errors)) t
     where t > v_now - c_window
     order by t desc
     limit c_errors);
  if cardinality(b.recent_errors) < c_errors then
    update private.safety_breaker set recent_errors = b.recent_errors;
    return null;
  end if;

  v_minutes := case
    when b.tripped_at is not null
         and b.tripped_at + make_interval(mins => coalesce(b.pause_minutes, c_first_pause)) + c_again_within > v_now
      then least(coalesce(b.pause_minutes, c_first_pause) * 2, c_longest_pause)
    else c_first_pause
  end;
  v_until := v_now + make_interval(mins => v_minutes);
  insert into private.ai_switches as s (scope, paused_until, note, updated_at)
    values ('all', v_until, 'safety_check_errors', v_now)
    on conflict (scope) do update
      set paused_until = excluded.paused_until, note = excluded.note, updated_at = excluded.updated_at
      where s.paused_until <= v_now;
  update private.safety_breaker
     set recent_errors = '{}', tripped_at = v_now, pause_minutes = v_minutes, trips = trips + 1;
  return v_until;
end $$;

-- The breaker's state for the owner (SQL editor): the errors in the window,
-- the last one, the last trip and whether the pause is on now.
create function public.ops_safety_breaker()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'recent_errors', cardinality(b.recent_errors),
    'last_error', b.last_error,
    'last_error_at', b.last_error_at,
    'tripped_at', b.tripped_at,
    'pause_minutes', b.pause_minutes,
    'trips', b.trips,
    'paused_until', (select s.paused_until from private.ai_switches s
                      where s.scope = 'all' and s.note = 'safety_check_errors' and s.paused_until > now()))
  from private.safety_breaker b
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.note_safety_check_error(text)',
    'public.ops_safety_breaker()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
