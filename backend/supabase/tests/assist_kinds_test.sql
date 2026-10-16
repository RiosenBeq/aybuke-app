-- Aybik's new tasks in their own buckets (20261104000000): each kind's own
-- hourly limits per user, per verified install and per address, every kind
-- under the same shared ceilings and unverified cap, unknown kinds refused.
-- Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on failure
-- and cleans up after itself.
\set ON_ERROR_STOP on

-- Server only, the numbers, and the kinds the counts accept.
do $$
declare
  lim record;
  k text;
begin
  assert not has_function_privilege('anon', 'public.assist_kind_policy(text)', 'execute'), 'server only (anon)';
  assert not has_function_privilege('authenticated', 'public.assist_kind_policy(text)', 'execute'),
    'server only (authenticated)';
  assert has_function_privilege('service_role', 'public.assist_kind_policy(text)', 'execute'), 'admit_assist reads it';
  assert not has_function_privilege('authenticated', 'public.admit_assist(uuid, text, text, text, text)', 'execute'),
    'admit_assist stays server only';
  assert has_function_privilege('service_role', 'public.admit_assist(uuid, text, text, text, text)', 'execute'),
    'the assist function calls it';

  foreach k in array array['assist', 'polish', 'looks', 'poll_questions', 'card_text', 'help'] loop
    select * into lim from public.assist_kind_policy(k);
    assert lim.user_per_hour > 0 and lim.install_per_hour > 0 and lim.ip_per_hour >= lim.user_per_hour,
      format('%s has limits: %s', k, row_to_json(lim));
  end loop;
  select * into lim from public.assist_kind_policy('assist');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (60, 60, 200), 'writing help unchanged';
  select * into lim from public.assist_kind_policy('polish');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (60, 60, 200), 'the polish unchanged';
  select * into lim from public.assist_kind_policy('looks');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (30, 30, 120), format('looks: %s', row_to_json(lim));
  select * into lim from public.assist_kind_policy('poll_questions');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (20, 20, 100),
    format('poll questions: %s', row_to_json(lim));
  select * into lim from public.assist_kind_policy('card_text');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (40, 40, 150),
    format('card text: %s', row_to_json(lim));
  select * into lim from public.assist_kind_policy('help');
  assert (lim.user_per_hour, lim.install_per_hour, lim.ip_per_hour) = (20, 20, 100), format('help: %s', row_to_json(lim));
  select * into lim from public.assist_kind_policy('images');
  assert lim.user_per_hour is null, 'no limits for an unknown kind';

  begin
    insert into private.assist_usage (kind, bucket, hour) values ('images', 'x', date_trunc('hour', now()));
    assert false, 'the counts take only known kinds';
  exception when check_violation then
    null;
  end;
end $$;

-- Each kind counts on its own: a full help hour leaves the other kinds alone,
-- per user, per verified install and per address.
do $$
declare
  u uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  tx text := 'atid-kinds-' || gen_random_uuid();
  r jsonb;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker set last_error_at = null;
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into auth.users (id) values (u), (other);

  -- Per user: 20 help questions an hour.
  for i in 1..20 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(u, '203.0.113.200', 'help', tx, 'verified');
    assert r = '{"ok": true}'::jsonb, format('help, request %s: %s', i, r);
  end loop;
  delete from private.assist_ceilings;
  r := public.admit_assist(u, '203.0.113.200', 'help', tx, 'verified');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429
     and (r->>'until')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    format('the 21st help question this hour: %s', r);
  foreach r in array array[
    public.admit_assist(u, '203.0.113.200', 'looks', tx, 'verified'),
    public.admit_assist(u, '203.0.113.200', 'poll_questions', tx, 'verified'),
    public.admit_assist(u, '203.0.113.200', 'card_text', tx, 'verified'),
    public.admit_assist(u, '203.0.113.200', 'assist', tx, 'verified')
  ] loop
    assert (r->>'ok')::boolean, format('the other kinds have their own hour: %s', r);
  end loop;
  assert (select requests from private.assist_usage
           where kind = 'help' and bucket = private.keyed_hash('assist_user', u::text)) = 21,
    'counted in the help bucket, the refused one too';
  assert (select requests from private.assist_usage
           where kind = 'looks' and bucket = private.keyed_hash('app_transaction', tx)) = 1,
    'the install''s count is per kind too';

  -- Per verified install: the install's 20 poll-question requests, across its accounts.
  delete from private.assist_usage;
  for i in 1..20 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(case when i % 2 = 0 then u else other end, '203.0.113.' || (200 + i), 'poll_questions',
                             tx, 'verified');
    assert (r->>'ok')::boolean, format('poll questions, request %s: %s', i, r);
  end loop;
  delete from private.assist_ceilings;
  r := public.admit_assist(other, '203.0.113.240', 'poll_questions', tx, 'verified');
  assert r->>'code' = 'rate_limited', format('the 21st on one install from a fresh address: %s', r);
  r := public.admit_assist(other, '203.0.113.240', 'poll_questions', 'atid-kinds-other', 'verified');
  assert (r->>'ok')::boolean, format('another install: %s', r);

  -- Per address: 150 card-text requests an hour across accounts and installs.
  delete from private.assist_usage;
  insert into private.assist_usage (kind, bucket, hour, requests)
    values ('card_text', private.keyed_hash('ip', '198.51.100.200'), date_trunc('hour', now()), 150);
  delete from private.assist_ceilings;
  r := public.admit_assist(u, '198.51.100.200', 'card_text', 'atid-kinds-card', 'verified');
  assert r->>'code' = 'rate_limited', format('the 151st card text from one address: %s', r);
  delete from private.assist_ceilings;
  r := public.admit_assist(u, '198.51.100.200', 'looks', 'atid-kinds-card', 'verified');
  assert (r->>'ok')::boolean, format('the finder from that address: %s', r);

  -- The looks bucket: 30 an hour per user.
  delete from private.assist_usage;
  insert into private.assist_usage (kind, bucket, hour, requests)
    values ('looks', private.keyed_hash('assist_user', other::text), date_trunc('hour', now()), 30);
  delete from private.assist_ceilings;
  r := public.admit_assist(other, '203.0.113.250', 'looks');
  assert r->>'code' = 'rate_limited', format('the 31st look finder this hour: %s', r);

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id in (u, other);
end $$;

-- The ceilings and the unverified cap are shared by every kind, and the
-- pause, the quiet time and blocks apply to the new kinds too.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
  places text;
begin
  perform public.ops_resume_ai();
  update private.safety_breaker set last_error_at = null;
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into auth.users (id) values (u);

  -- 20 a minute for everyone, whatever the kind.
  for i in 1..20 loop
    r := public.admit_assist(u, '192.0.2.' || (100 + i),
                             (array['looks', 'poll_questions', 'card_text', 'help', 'assist'])[1 + i % 5],
                             'atid-kinds-ceiling-' || i, 'verified');
    assert (r->>'ok')::boolean, format('request %s this minute: %s', i, r);
  end loop;
  r := public.admit_assist(u, '192.0.2.150', 'help', 'atid-kinds-ceiling-50', 'verified');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503
     and (r->>'until')::timestamptz = date_trunc('minute', now()) + interval '1 minute',
    format('the 21st this minute, a help question: %s', r);
  r := public.admit_assist(u, '192.0.2.151', 'polish', 'atid-kinds-ceiling-51', 'verified');
  assert r->>'code' = 'assist_unavailable', format('the polish shares it: %s', r);
  select string_agg(scope || '=' || requests, ' ' order by scope) into places from private.assist_ceilings;
  assert places = 'all_day=20 all_hour=20 all_minute=20', format('one count for every kind: %s', places);

  -- 30 an hour without a verified install, every kind together.
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  insert into private.assist_ceilings (scope, period, requests) values ('unverified_hour', date_trunc('hour', now()), 30);
  r := public.admit_assist(u, '192.0.2.160', 'looks');
  assert r->>'code' = 'assist_unavailable', format('the finder without a verified install, cap reached: %s', r);
  r := public.admit_assist(u, '192.0.2.160', 'card_text', 'atid-kinds-verified', 'verified');
  assert (r->>'ok')::boolean, format('a verified install still gets in: %s', r);

  -- Paused, quiet after a failed check, blocked: nothing for the new kinds either, and nothing counted.
  delete from private.assist_ceilings;
  delete from private.assist_usage;
  perform public.ops_pause_ai('all', 1, 'test');
  r := public.admit_assist(u, '192.0.2.170', 'help', 'atid-kinds-quiet', 'verified');
  assert r->>'code' = 'assist_unavailable', format('paused: %s', r);
  perform public.ops_resume_ai();
  update private.safety_breaker set last_error_at = now() - interval '1 minute';
  r := public.admit_assist(u, '192.0.2.170', 'looks', 'atid-kinds-quiet', 'verified');
  assert r->>'code' = 'assist_unavailable', format('quiet after a failed check: %s', r);
  update private.safety_breaker set last_error_at = null;
  insert into private.blocks (user_id, reason) values (u, 'test');
  r := public.admit_assist(u, '192.0.2.170', 'poll_questions', 'atid-kinds-quiet', 'verified');
  assert r->>'code' = 'assist_unavailable', format('blocked: %s', r);
  assert not exists (select 1 from private.assist_usage) and not exists (select 1 from private.assist_ceilings),
    'nothing counted';

  begin
    perform public.admit_assist(u, '192.0.2.170', 'images', null, 'missing');
    assert false, 'an unknown kind must raise';
  exception when raise_exception then
    null;
  end;
  begin
    perform public.admit_assist(u, '192.0.2.170', null, null, 'missing');
    assert false, 'no kind must raise';
  exception when raise_exception then
    null;
  end;

  delete from private.blocks where user_id = u;
  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = u;
end $$;

select 'all assist kind tests passed' as result;
