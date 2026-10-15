-- The safety check's circuit breaker (20261029000001): three checks that
-- couldn't run within ten minutes pause AI for everyone, so an Anthropic outage
-- stops new jobs before xAI bills them. Run with backend/scripts/test-db.sh.
-- Each block raises (ASSERT) on failure. now() is fixed inside a block, so the
-- times are moved by hand.
\set ON_ERROR_STOP on

do $$
begin
  assert not has_function_privilege('anon', 'public.note_safety_check_error(text)', 'execute'), 'server only';
  assert not has_function_privilege('authenticated', 'public.note_safety_check_error(text)', 'execute'), 'server only';
  assert not has_function_privilege('authenticated', 'public.ops_safety_breaker()', 'execute'), 'owner only';
  assert has_function_privilege('service_role', 'public.note_safety_check_error(text)', 'execute'), 'ai-image reports';
  assert has_function_privilege('service_role', 'public.ops_safety_breaker()', 'execute'), 'the owner reads it';
  assert not has_table_privilege('authenticated', 'private.safety_breaker', 'select'), 'no client reads it';
  assert (select relrowsecurity from pg_class where oid = 'private.safety_breaker'::regclass), 'RLS is on';
end $$;

-- Three errors trip it: AI pauses for five minutes, before anything is charged.
do $$
declare
  u uuid := gen_random_uuid();
  v_until timestamptz;
  r jsonb;
  s jsonb;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker set recent_errors = '{}', tripped_at = null, pause_minutes = null, trips = 0;
  insert into auth.users (id) values (u);
  perform public.grant_pack(u, 5, 'tx-safety-breaker-' || u);

  assert public.note_safety_check_error('HTTP 529 overloaded_error') is null, 'one error is not an outage';
  assert public.note_safety_check_error('timeout') is null, 'nor are two';
  r := public.admit_job(u, 'text_to_image', 'xai/grok-imagine-image-2.0');
  assert (r ->> 'ok')::boolean, format('jobs still run: %s', r);

  v_until := public.note_safety_check_error('HTTP 529 overloaded_error');
  assert v_until = now() + interval '5 minutes', format('the third pauses AI for five minutes: %s', v_until);
  assert (select (paused_until, note) = (v_until, 'safety_check_errors') from private.ai_switches where scope = 'all'),
    'the all switch, with its reason';
  r := public.admit_job(u, 'text_to_image', 'xai/grok-imagine-image-2.0');
  assert r ->> 'code' = 'ai_paused' and (r ->> 'status')::int = 503 and (r ->> 'retry_after')::int between 1 and 300,
    format('new jobs stop at admission: %s', r);
  assert (select count(*) from public.jobs where user_id = u) = 1, 'nothing was booked or charged';
  assert (select purchased from public.credit_wallets where user_id = u) = 4, 'only the job before the pause paid';

  -- Jobs that were already running report errors while paused: they don't count.
  assert public.note_safety_check_error('timeout') is null, 'no second pause';
  s := public.ops_safety_breaker();
  assert (s ->> 'recent_errors')::int = 0 and (s ->> 'trips')::int = 1, format('the state: %s', s);
  assert s ->> 'last_error' = 'timeout' and (s ->> 'paused_until')::timestamptz = v_until, format('the owner sees: %s', s);

  -- The owner can end it like any pause.
  assert public.ops_resume_ai() -> 'resumed' @> '["all"]'::jsonb, 'resumed';
  r := public.admit_job(u, 'text_to_image', 'xai/grok-imagine-image-2.0');
  assert (r ->> 'ok')::boolean, format('back to normal: %s', r);

  delete from auth.users where id = u;
end $$;

-- The window is ten minutes; a trip soon after the last pause doubles it, up to an hour.
do $$
declare
  v_until timestamptz;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker
     set recent_errors = array[now() - interval '11 minutes', now() - interval '12 minutes'],
         tripped_at = null, pause_minutes = null, trips = 0;
  assert public.note_safety_check_error('timeout') is null, 'errors older than ten minutes are forgotten';
  assert (select cardinality(recent_errors) from private.safety_breaker) = 1, 'only the new one is kept';
  update private.safety_breaker set recent_errors = array[now() - interval '9 minutes', now() - interval '4 minutes'];
  assert public.note_safety_check_error('timeout') = now() + interval '5 minutes', 'three within ten minutes trip it';

  -- Its pause ended a minute ago, and the errors go on: ten minutes this time.
  update private.ai_switches set paused_until = now() - interval '1 minute' where scope = 'all';
  update private.safety_breaker
     set tripped_at = now() - interval '6 minutes', recent_errors = array[now(), now()];
  v_until := public.note_safety_check_error('deadline');
  assert v_until = now() + interval '10 minutes', format('doubled: %s', v_until);
  assert (select paused_until from private.ai_switches where scope = 'all') = v_until, 'the expired pause is replaced';

  update private.ai_switches set paused_until = now() - interval '1 minute' where scope = 'all';
  update private.safety_breaker
     set tripped_at = now() - interval '61 minutes', pause_minutes = 60, recent_errors = array[now(), now()];
  assert public.note_safety_check_error('deadline') = now() + interval '60 minutes', 'never longer than an hour';

  -- Long after the last pause, it starts again at five minutes.
  update private.ai_switches set paused_until = now() - interval '1 minute' where scope = 'all';
  update private.safety_breaker
     set tripped_at = now() - interval '3 hours', pause_minutes = 60, recent_errors = array[now(), now()];
  assert public.note_safety_check_error('deadline') = now() + interval '5 minutes', 'back to five minutes';
  assert (select trips from private.safety_breaker) = 4, 'every trip counted';

  perform public.ops_resume_ai();
end $$;

-- It never shortens or replaces a pause that is already on.
do $$
declare
  v_owner timestamptz;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker set recent_errors = '{}', tripped_at = null, pause_minutes = null, trips = 0;
  v_owner := (public.ops_pause_ai('all', 2, 'maintenance') ->> 'paused_until')::timestamptz;
  for i in 1..3 loop
    assert public.note_safety_check_error('timeout') is null, 'already paused';
  end loop;
  assert (select (paused_until, note) = (v_owner, 'maintenance') from private.ai_switches where scope = 'all'),
    'the owner''s pause stays as it was';
  assert (select trips from private.safety_breaker) = 0, 'no trip';

  -- And the provider billing pause still starts after the breaker's pause ends.
  perform public.ops_resume_ai();
  update private.safety_breaker set recent_errors = array[now(), now()];
  assert public.note_safety_check_error('timeout') is not null, 'tripped';
  assert not public.pause_ai_for_provider('provider_billing'), 'a running pause is kept';
  update private.ai_switches set paused_until = now() - interval '1 second' where scope = 'all';
  assert public.pause_ai_for_provider('provider_billing'), 'then billing pauses as before';

  perform public.ops_resume_ai();
  update private.safety_breaker set recent_errors = '{}', tripped_at = null, pause_minutes = null, trips = 0,
                                   last_error = null, last_error_at = null;
end $$;

select 'all safety breaker tests passed' as result;
