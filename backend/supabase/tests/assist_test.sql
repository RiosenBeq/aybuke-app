-- Limits for Claude's text help and the prompt polish (20261031000000):
-- admit_assist() refuses while AI is paused or the user is blocked or resting,
-- allows 60 an hour per user and 200 an hour per address for each kind, and
-- keeps only salted hashes, which sweep_jobs() deletes after a day. Run with
-- backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
--
-- Since 20261103000000 the three-argument form is a request without install
-- proof, under everyone's ceilings and the shared unverified cap: these tests
-- clear those counts (private.assist_ceilings) before each request, so they
-- check the per-user and per-address limits alone. assist_ceilings_test.sql
-- checks the ceilings, the install buckets and the safety check's quiet time.
\set ON_ERROR_STOP on
update private.safety_breaker set last_error_at = null;

do $$
begin
  assert not has_function_privilege('anon', 'public.admit_assist(uuid, text, text)', 'execute'), 'server only';
  assert not has_function_privilege('authenticated', 'public.admit_assist(uuid, text, text)', 'execute'), 'server only';
  assert has_function_privilege('service_role', 'public.admit_assist(uuid, text, text)', 'execute'), 'assist calls it';
  assert has_function_privilege('service_role', 'public.sweep_jobs()', 'execute'), 'the sweep still runs';
  assert not has_function_privilege('authenticated', 'public.sweep_jobs()', 'execute'), 'the sweep stays server only';
  assert not has_table_privilege('authenticated', 'private.assist_usage', 'select'), 'no client reads the counts';
  assert not has_table_privilege('anon', 'private.assist_usage', 'select'), 'no client reads the counts';
  assert (select relrowsecurity from pg_class where oid = 'private.assist_usage'::regclass), 'RLS is on';
end $$;

-- 60 an hour per user; the polish has its own count; only hashes are kept.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  perform public.ops_resume_ai();
  insert into auth.users (id) values (u);
  for i in 1..60 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(u, '203.0.113.9', 'assist');
    assert r = '{"ok": true}'::jsonb, format('request %s: %s', i, r);
  end loop;
  r := public.admit_assist(u, '203.0.113.9', 'assist');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('61st in an hour: %s', r);
  assert (r->>'retry_after')::int between 1 and 3600, format('until the hour ends: %s', r);
  assert (r->>'until')::timestamptz = date_trunc('hour', now()) + interval '1 hour', format('the next hour: %s', r);
  r := public.admit_assist(u, '203.0.113.9', 'assist');
  assert r->>'code' = 'rate_limited', 'a refused request still counts';

  delete from private.assist_ceilings;
  r := public.admit_assist(u, '203.0.113.9', 'polish');
  assert (r->>'ok')::boolean, format('the polish counts on its own: %s', r);
  r := public.admit_assist(u, null);
  assert r->>'code' = 'rate_limited', format('the default kind is assist: %s', r);

  assert (select requests from private.assist_usage
           where kind = 'assist' and bucket = private.keyed_hash('assist_user', u::text)) = 63,
    'counted under the hashed user id';
  assert (select requests from private.assist_usage
           where kind = 'assist' and bucket = private.keyed_hash('ip', '203.0.113.9')) = 60,
    'requests the user limit refused never reach the address count';
  assert not exists (select 1 from private.assist_usage where bucket in (u::text, '203.0.113.9')),
    'no raw user id or address';

  -- Last hour's requests don't count now.
  update private.assist_usage set hour = hour - interval '1 hour'
   where bucket = private.keyed_hash('assist_user', u::text);
  delete from private.assist_ceilings;
  r := public.admit_assist(u, '203.0.113.9', 'assist');
  assert (r->>'ok')::boolean, format('a new hour: %s', r);

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = u;
end $$;

-- 200 an hour per address, across users; no address, no address limit.
do $$
declare
  r jsonb;
  u uuid;
  v_users uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
begin
  insert into auth.users (id) select unnest(v_users);
  for k in 1..4 loop
    for i in 1..50 loop
      delete from private.assist_ceilings;
      r := public.admit_assist(v_users[k], '198.51.100.7', 'assist');
      assert (r->>'ok')::boolean, format('user %s, request %s: %s', k, i, r);
    end loop;
  end loop;
  r := public.admit_assist(v_users[5], '198.51.100.7', 'assist');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('201st from one address: %s', r);
  delete from private.assist_ceilings;
  r := public.admit_assist(v_users[5], '198.51.100.8', 'assist');
  assert (r->>'ok')::boolean, format('another address: %s', r);
  r := public.admit_assist(v_users[5], '198.51.100.7', 'polish');
  assert (r->>'ok')::boolean, format('the polish has its own address count: %s', r);

  u := v_users[1];
  for i in 1..10 loop
    delete from private.assist_ceilings;
    r := public.admit_assist(u, '', 'assist');
    assert (r->>'ok')::boolean, format('no address: %s', r);
  end loop;
  assert not exists (select 1 from private.assist_usage where bucket = private.keyed_hash('ip', '')),
    'an empty address is never counted';

  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = any (v_users);
end $$;

-- Paused, blocked or resting: assist_unavailable, and nothing is counted.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  insert into auth.users (id) values (u);

  perform public.ops_pause_ai('all', 1, 'test');
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503, format('paused: %s', r);
  assert (r->>'retry_after')::int between 3500 and 3600, format('until the pause ends: %s', r);
  r := public.admit_assist(u, '203.0.113.10', 'polish');
  assert r->>'code' = 'assist_unavailable', format('no polish while paused: %s', r);
  perform public.ops_resume_ai();
  perform public.ops_pause_ai('free', 1, 'test');
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert (r->>'ok')::boolean, format('a pause of free credits only leaves writing help on: %s', r);
  perform public.ops_resume_ai();

  insert into private.blocks (user_id, reason) values (u, 'test');
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert r->>'code' = 'assist_unavailable' and (r->>'status')::int = 503 and r->>'retry_after' is null,
    format('blocked: %s', r);
  update private.blocks set lifted_at = now() where user_id = u;
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert (r->>'ok')::boolean, format('lifted: %s', r);

  insert into private.cooldowns (user_id, ends_at) values (u, now() + interval '2 hours');
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert r->>'code' = 'assist_unavailable' and (r->>'retry_after')::int between 7000 and 7200,
    format('resting: %s', r);
  update private.cooldowns set ends_at = now() - interval '1 minute' where user_id = u;
  r := public.admit_assist(u, '203.0.113.10', 'assist');
  assert (r->>'ok')::boolean, format('rested: %s', r);

  assert (select requests from private.assist_usage
           where bucket = private.keyed_hash('assist_user', u::text) and kind = 'assist') = 3,
    'only the admitted requests were counted';

  begin
    perform public.admit_assist(u, '203.0.113.10', 'images');
    assert false, 'an unknown kind must raise';
  exception when raise_exception then
    null;
  end;

  delete from private.cooldowns where user_id = u;
  delete from private.blocks where user_id = u;
  delete from private.assist_usage;
  delete from private.assist_ceilings;
  delete from auth.users where id = u;
end $$;

-- sweep_jobs() deletes counts older than a day and keeps the rest.
do $$
begin
  insert into private.assist_usage (kind, bucket, hour, requests) values
    ('assist', 'old', date_trunc('hour', now()) - interval '25 hours', 3),
    ('polish', 'recent', date_trunc('hour', now()) - interval '2 hours', 4);
  perform public.sweep_jobs();
  assert not exists (select 1 from private.assist_usage where bucket = 'old'), 'a day old: gone';
  assert exists (select 1 from private.assist_usage where bucket = 'recent'), 'recent: kept';
  delete from private.assist_usage;
end $$;

select 'all assist limit tests passed' as result;
