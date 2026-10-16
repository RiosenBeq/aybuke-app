-- "Which vibe?" polls (20261102000000): admission and its limits, storing,
-- viewing, voting, pictures and their caps, reports and takedowns, her list
-- and deletion, account deletion and merging, the sweep and the owner's
-- tools. Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on
-- failure and cleans up after itself.
\set ON_ERROR_STOP on

-- Server only: no client runs a poll function or reads a poll table.
do $$
declare
  fn text;
  tbl text;
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
    'public.ops_set_poll_report_status(text, text)'
  ] loop
    assert not has_function_privilege('anon', fn, 'execute'), fn || ' is server only (anon)';
    assert not has_function_privilege('authenticated', fn, 'execute'), fn || ' is server only (authenticated)';
    assert has_function_privilege('service_role', fn, 'execute'), fn || ' runs as the service role';
  end loop;
  assert has_function_privilege('service_role', 'public.sweep_jobs()', 'execute'), 'the sweep still runs';
  assert not has_function_privilege('authenticated', 'public.sweep_jobs()', 'execute'), 'the sweep stays server only';
  assert not has_function_privilege('authenticated', 'public.merge_accounts(uuid, uuid)', 'execute'), 'merge too';
  foreach tbl in array array['private.polls', 'private.poll_votes', 'private.poll_reporters', 'private.poll_reports',
                             'private.poll_usage', 'private.poll_daily'] loop
    assert not has_table_privilege('anon', tbl, 'select'), tbl || ': no client reads it (anon)';
    assert not has_table_privilege('authenticated', tbl, 'select'), tbl || ': no client reads it (authenticated)';
    assert (select relrowsecurity from pg_class where oid = tbl::regclass), tbl || ': RLS is on';
  end loop;
  assert (select attstorage from pg_attribute where attrelid = 'private.polls'::regclass and attname = 'image_a') = 'e',
    'pictures are stored as they are, never compressed again';
end $$;

-- The numbers, and the ids: 16 base64url characters, never the same twice.
do $$
declare
  pol record;
  v_ids text[];
begin
  select * into pol from public.poll_policy();
  assert pol.lifetime_hours = 24 and pol.polls_per_user_daily = 3 and pol.polls_per_install_daily = 3, format('%s', pol);
  assert pol.takedown_reports = 3 and pol.report_retention_days = 30, format('%s', pol);
  select array_agg(private.new_poll_id()) into v_ids from generate_series(1, 2000);
  assert (select count(distinct id) from unnest(v_ids) id) = 2000, 'no repeats';
  assert (select bool_and(id ~ '^[A-Za-z0-9_-]{16}$') from unnest(v_ids) id), 'base64url, 16 characters';
end $$;

-- A tiny stand-in for a re-encoded JPEG (the database only checks its size).
create or replace function pg_temp.picture(p_fill text default 'x') returns text language sql as $$
  select translate(encode(convert_to(repeat(p_fill, 300), 'UTF8'), 'base64'), E'\n', '')
$$;
create or replace function pg_temp.make_poll(p_user uuid, p_question text default 'Which vibe?') returns text
language sql as $$
  select public.create_poll(p_user, p_question, 'tr', pg_temp.picture('a'), pg_temp.picture('b'), 540, 720, 720, 540)
         ->> 'poll_id'
$$;

-- Admission: 3 a day per user, the attempt counts, a blocked question counts
-- too (no strike; since 20261103000001 apart from today's polls for everyone),
-- and only salted hashes are kept.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  perform public.ops_resume_ai();
  delete from private.poll_daily;
  insert into auth.users (id) values (u);
  r := public.admit_poll(u, null, 'missing', '203.0.113.20');
  assert r = '{"ok": true, "remaining_today": 2}'::jsonb, format('first: %s', r);
  r := public.admit_poll(u, null, 'missing', '203.0.113.20', 'sexual');
  assert r->>'code' = 'content_blocked' and (r->>'status')::int = 422 and r->>'category' = 'sexual',
    format('a blocked question: %s', r);
  assert not exists (select 1 from private.strikes where user_id = u), 'never a strike';
  r := public.admit_poll(u, null, 'missing', '203.0.113.20');
  assert r = '{"ok": true, "remaining_today": 0}'::jsonb, format('third: %s', r);
  r := public.admit_poll(u, null, 'missing', '203.0.113.20');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('fourth: %s', r);
  assert (r->>'until')::timestamptz = private.next_utc_day(), format('until tomorrow (UTC): %s', r);
  assert (select count from private.poll_usage
           where kind = 'create_user' and bucket = private.keyed_hash('poll_user', u::text)) = 3,
    'a refused request leaves the count as it was';
  assert (select count from private.poll_usage
           where kind = 'create_ip' and bucket = private.keyed_hash('ip', '203.0.113.20')) = 3, 'the address too';
  assert (select attempts from private.poll_daily where day = private.poll_today()) = 2,
    'two attempts toward today''s polls: the blocked question counts apart (20261103000001)';
  assert (select blocked_question from private.poll_daily where day = private.poll_today()) = 1, 'one blocked';
  assert (select unverified_attempts from private.poll_daily where day = private.poll_today()) = 3,
    'all three without a verified install';
  assert not exists (select 1 from private.poll_usage where bucket in (u::text, '203.0.113.20')),
    'no raw user id or address';

  -- A check that couldn't run gives the attempt back.
  perform public.finish_poll_attempt(u, 'unavailable', null, 'missing', '203.0.113.20');
  r := public.admit_poll(u, null, 'missing', '203.0.113.20');
  assert (r->>'ok')::boolean and (r->>'remaining_today')::int = 0, format('given back: %s', r);
  assert (select unavailable from private.poll_daily where day = private.poll_today()) = 1, 'counted for the owner';
  perform public.finish_poll_attempt(u, 'image_blocked');
  perform public.finish_poll_attempt(u, 'image_invalid');
  assert (select (blocked_image, invalid_image) = (1, 1) from private.poll_daily where day = private.poll_today()),
    'blocked and unreadable pictures counted';
  begin
    perform public.finish_poll_attempt(u, 'whatever');
    assert false, 'unknown outcome';
  exception when raise_exception then
    null;
  end;

  -- Yesterday's polls don't count today.
  update private.poll_usage set period = period - interval '1 day'
   where kind = 'create_user' and bucket = private.keyed_hash('poll_user', u::text);
  r := public.admit_poll(u, null, 'missing', '203.0.113.21');
  assert (r->>'ok')::boolean and (r->>'remaining_today')::int = 2, format('a new day: %s', r);

  delete from private.poll_usage;
  delete from private.poll_daily;
  delete from auth.users where id = u;
end $$;

-- Per App Store install across accounts, per address an hour, and for
-- everyone a day.
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  c uuid := gen_random_uuid();
  r jsonb;
begin
  insert into auth.users (id) values (a), (b), (c);
  r := public.admit_poll(a, 'txn-poll-1', 'verified', '198.51.100.30');
  assert (r->>'remaining_today')::int = 2, format('%s', r);
  r := public.admit_poll(a, 'txn-poll-1', 'verified', '198.51.100.30');
  r := public.admit_poll(b, 'txn-poll-1', 'verified', '198.51.100.30');
  assert (r->>'ok')::boolean and (r->>'remaining_today')::int = 0, format('third on the install: %s', r);
  r := public.admit_poll(b, 'txn-poll-1', 'verified', '198.51.100.30');
  assert r->>'code' = 'rate_limited', format('a new account on the same install: %s', r);
  r := public.my_polls(b, 'txn-poll-1', 'verified');
  assert (r->>'remaining_today')::int = 0 and (r->>'daily_cap')::int = 3, format('her list says so: %s', r);
  r := public.my_polls(b);
  assert (r->>'remaining_today')::int = 2, format('without the install, her own count: %s', r);
  r := public.admit_poll(b, 'txn-poll-1', 'missing', '198.51.100.31');
  assert (r->>'ok')::boolean and (r->>'remaining_today')::int = 1,
    format('an unverified install only counts per user: %s', r);
  delete from private.poll_usage;

  -- 10 an hour per address, whoever asks.
  for i in 1..10 loop
    r := public.admit_poll(gen_random_uuid(), null, 'missing', '192.0.2.40');
    assert (r->>'ok')::boolean, format('request %s: %s', i, r);
  end loop;
  r := public.admit_poll(c, null, 'missing', '192.0.2.40');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    format('11th from one address in an hour: %s', r);
  r := public.admit_poll(c, null, 'missing', '192.0.2.41');
  assert (r->>'ok')::boolean and (r->>'remaining_today')::int = 2,
    format('the refused request gave the user count back: %s', r);
  delete from private.poll_usage;

  -- 300 a day for everyone.
  insert into private.poll_daily (day, attempts) values (private.poll_today(), 300)
    on conflict (day) do update set attempts = 300;
  r := public.admit_poll(c, null, 'missing', '192.0.2.41');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(), format('cap: %s', r);
  assert not exists (select 1 from private.poll_usage where kind = 'create_user'), 'refused before counting her';

  delete from private.poll_usage;
  delete from private.poll_daily;
  delete from auth.users where id in (a, b, c);
end $$;

-- Blocks, cool-downs and an AI pause stop new polls (the check needs Claude).
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  insert into auth.users (id) values (u);
  perform public.ops_pause_ai('all', 1, 'test');
  r := public.admit_poll(u);
  assert r->>'code' = 'safety_unavailable' and (r->>'status')::int = 503 and (r->>'retry_after')::int > 0,
    format('paused: %s', r);
  perform public.ops_resume_ai();
  perform public.ops_pause_ai('free', 1, 'test');
  r := public.admit_poll(u);
  assert (r->>'ok')::boolean, format('a pause of free credits only leaves polls on: %s', r);
  perform public.ops_resume_ai();

  insert into private.cooldowns (user_id, ends_at) values (u, now() + interval '2 hours');
  r := public.admit_poll(u);
  assert r->>'code' = 'cooldown' and (r->>'status')::int = 429, format('resting: %s', r);
  delete from private.cooldowns where user_id = u;

  perform public.ops_block(p_install => private.keyed_hash('app_transaction', 'txn-blocked'), p_reason => 'test');
  r := public.admit_poll(u, 'txn-blocked', 'verified');
  assert r->>'code' = 'install_blocked' and (r->>'status')::int = 403, format('blocked install: %s', r);
  perform public.ops_unblock(p_install => private.keyed_hash('app_transaction', 'txn-blocked'));
  perform public.ops_block(p_user => u, p_reason => 'test');
  r := public.admit_poll(u);
  assert r->>'code' = 'install_blocked', format('blocked user: %s', r);
  perform public.ops_unblock(p_user => u);

  delete from private.poll_usage;
  delete from private.poll_daily;
  delete from private.blocks where user_id = u or install_key = private.keyed_hash('app_transaction', 'txn-blocked');
  delete from auth.users where id = u;
end $$;

-- Storing and viewing: 24 hours, the counts hidden until she or the visitor
-- voted, and one 404 for anything that isn't a live poll.
do $$
declare
  u uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  v_id text;
  r jsonb;
  p private.polls;
begin
  insert into auth.users (id) values (u), (other);
  r := public.create_poll(u, 'Hangisi?', 'tr', pg_temp.picture('a'), pg_temp.picture('b'), 540, 720, 720, 540,
                          'txn-store', 'verified');
  v_id := r->>'poll_id';
  assert v_id ~ '^[A-Za-z0-9_-]{16}$', format('%s', r);
  select * into p from private.polls where id = v_id;
  assert p.user_id = u and p.question = 'Hangisi?' and p.locale = 'tr', format('%s', p);
  assert p.install_key = private.keyed_hash('app_transaction', 'txn-store'), 'the install as a salted hash';
  assert convert_from(p.image_a, 'UTF8') = repeat('a', 300) and convert_from(p.image_b, 'UTF8') = repeat('b', 300),
    'the pictures as sent';
  assert p.expires_at between now() + interval '24 hours' - interval '1 minute' and now() + interval '24 hours',
    format('24 hours: %s', p.expires_at);
  assert (r->>'expires_at')::timestamptz = p.expires_at, 'the answer says when it ends';
  assert (select created from private.poll_daily where day = private.poll_today()) = 1, 'counted';
  r := public.create_poll(u, '', 'en', pg_temp.picture(), pg_temp.picture(), 10, 10, 10, 10);
  assert (select question is null and install_key is null from private.polls where id = r->>'poll_id'),
    'no question, no install';

  r := public.poll_view(v_id, null, null, '203.0.113.50');
  assert (r->>'ok')::boolean and r->>'question' = 'Hangisi?' and r->>'locale' = 'tr', format('%s', r);
  assert r->'sizes' = '{"a": {"width": 540, "height": 720}, "b": {"width": 720, "height": 540}}'::jsonb, format('%s', r);
  assert r->'votes' = 'null'::jsonb and r->'my_vote' = 'null'::jsonb and not (r->>'is_creator')::boolean,
    format('a visitor who hasn''t voted sees no counts: %s', r);
  assert r ? 'votes' and not r ? 'image_a', 'no picture in the view';
  r := public.poll_view(v_id, null, u);
  assert (r->>'is_creator')::boolean and r->'votes' = '{"a": 0, "b": 0}'::jsonb, format('she sees them: %s', r);
  r := public.poll_view(v_id, null, other);
  assert not (r->>'is_creator')::boolean and r->'votes' = 'null'::jsonb, format('another account doesn''t: %s', r);

  assert public.poll_view('AAAAAAAAAAAAAAAA') = '{"ok": false, "code": "not_found", "status": 404}'::jsonb,
    'never made';
  update private.polls set taken_down_at = now() where id = v_id;
  assert public.poll_view(v_id)->>'code' = 'not_found', 'taken down';
  update private.polls set taken_down_at = null, expires_at = now() - interval '1 second' where id = v_id;
  assert public.poll_view(v_id)->>'code' = 'not_found', 'ended (before the sweep)';
  assert public.poll_view(v_id, null, u)->>'code' = 'not_found', 'for her too: her list shows it';

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id in (u, other);
  assert not exists (select 1 from private.polls where user_id in (u, other)), 'deleted with the account';
end $$;

-- Voting: one vote per code and poll, changing it, codes hashed per poll.
do $$
declare
  u uuid := gen_random_uuid();
  v_id text;
  v_id2 text;
  r jsonb;
  v_code text := 'voterCode_123456-abcdef';
begin
  insert into auth.users (id) values (u);
  v_id := pg_temp.make_poll(u);
  v_id2 := pg_temp.make_poll(u);

  assert public.cast_poll_vote(v_id, 'short', 'a')->>'code' = 'bad_request', 'a code of 16 characters or more';
  assert public.cast_poll_vote(v_id, v_code, 'c')->>'code' = 'bad_request', 'only a or b';
  assert public.cast_poll_vote(v_id, 'bad code with spaces!', 'a')->>'code' = 'bad_request', 'base64url only';
  assert public.cast_poll_vote('AAAAAAAAAAAAAAAA', v_code, 'a')->>'code' = 'not_found', 'no such poll';

  r := public.cast_poll_vote(v_id, v_code, 'a', '203.0.113.60');
  assert r = '{"ok": true, "votes": {"a": 1, "b": 0}, "my_vote": "a"}'::jsonb, format('%s', r);
  r := public.cast_poll_vote(v_id, 'anotherVoterCode_99', 'b', '203.0.113.61');
  assert r->'votes' = '{"a": 1, "b": 1}'::jsonb, format('%s', r);
  r := public.cast_poll_vote(v_id, v_code, 'b', '203.0.113.60');
  assert r = '{"ok": true, "votes": {"a": 0, "b": 2}, "my_vote": "b"}'::jsonb, format('changed: %s', r);
  assert (select votes from private.poll_daily where day = private.poll_today()) = 2, 'a change isn''t a new vote';

  r := public.poll_view(v_id, v_code);
  assert r->>'my_vote' = 'b' and r->'votes' = '{"a": 0, "b": 2}'::jsonb, format('the voter sees the counts: %s', r);
  r := public.poll_view(v_id, 'neverVotedCode_0000');
  assert r->'votes' = 'null'::jsonb and r->'my_vote' = 'null'::jsonb, format('another code doesn''t: %s', r);

  perform public.cast_poll_vote(v_id2, v_code, 'a');
  assert (select count(distinct voter) from private.poll_votes where poll_id in (v_id, v_id2)
            and voter in (private.keyed_hash('poll_voter', v_id || ':' || v_code),
                          private.keyed_hash('poll_voter', v_id2 || ':' || v_code))) = 2,
    'the same code is a different hash in each poll';
  assert not exists (select 1 from private.poll_votes where voter like '%' || v_code || '%'), 'never the code itself';

  update private.polls set taken_down_at = now() where id = v_id2;
  assert public.cast_poll_vote(v_id2, v_code, 'b')->>'code' = 'not_found', 'no votes once taken down';

  -- 120 votes an hour per address.
  for i in 1..119 loop
    perform public.cast_poll_vote(v_id, 'loopVoterCode_' || lpad(i::text, 4, '0'), 'a', '198.51.100.62');
  end loop;
  r := public.cast_poll_vote(v_id, 'loopVoterCode_0120', 'a', '198.51.100.62');
  assert (r->>'ok')::boolean, format('120th: %s', r);
  r := public.cast_poll_vote(v_id, 'loopVoterCode_0121', 'a', '198.51.100.62');
  assert r->>'code' = 'rate_limited', format('121st: %s', r);

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
  assert not exists (select 1 from private.poll_votes where poll_id in (v_id, v_id2)), 'votes go with the poll';
end $$;

-- Pictures: as stored, counted, and capped per address, per poll and a day.
do $$
declare
  u uuid := gen_random_uuid();
  v_id text;
  r jsonb;
begin
  insert into auth.users (id) values (u);
  v_id := pg_temp.make_poll(u);
  r := public.poll_image(v_id, 'a', '203.0.113.70');
  assert (r->>'ok')::boolean and r->>'image' = pg_temp.picture('a') and (r->>'bytes')::int = 300, format('%s', r);
  assert position(E'\n' in r->>'image') = 0, 'one line of base64';
  r := public.poll_image(v_id, 'b', '203.0.113.70');
  assert r->>'image' = pg_temp.picture('b'), 'side b';
  assert public.poll_image(v_id, 'c')->>'code' = 'bad_request', 'only a or b';
  assert public.poll_image('AAAAAAAAAAAAAAAA', 'a')->>'code' = 'not_found', 'no such poll';
  assert (select (image_loads, image_bytes) = (2, 600) from private.poll_daily where day = private.poll_today()),
    'loads and bytes counted for the owner';
  assert (select image_loads from private.polls where id = v_id) = 2, 'and on the poll';

  -- 600 per poll.
  update private.polls set image_loads = 600 where id = v_id;
  r := public.poll_image(v_id, 'a');
  assert r->>'code' = 'rate_limited' and (r->>'status')::int = 429, format('poll cap: %s', r);
  update private.polls set image_loads = 0 where id = v_id;

  -- 60 an hour per address (200 until 20261103000001).
  update private.poll_usage set count = 60 where kind = 'image_ip' and bucket = private.keyed_hash('ip', '203.0.113.70');
  assert public.poll_image(v_id, 'a', '203.0.113.70')->>'code' = 'rate_limited', 'address cap';
  assert (public.poll_image(v_id, 'a', '203.0.113.71')->>'ok')::boolean, 'another address';

  -- 2,000 a day for everyone, once per picture and address (20261103000001).
  update private.poll_daily set image_loads_unique = 2000 where day = private.poll_today();
  r := public.poll_image(v_id, 'a', '203.0.113.72');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(), format('day cap: %s', r);
  assert (public.poll_image(v_id, 'a', '203.0.113.71')->>'ok')::boolean, 'a picture this address already loaded';
  update private.poll_daily set image_loads_unique = 0, image_loads = 0 where day = private.poll_today();

  update private.polls set taken_down_at = now() where id = v_id;
  assert public.poll_image(v_id, 'a')->>'code' = 'not_found', 'never once taken down';
  assert public.ops_poll_image(v_id, 'a') = 'data:image/jpeg;base64,' || pg_temp.picture('a'),
    'the owner can still review it';

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
end $$;

-- Reports: sexual or minor take it down at once; other reasons after 3
-- different addresses; the record keeps the creator, never the reporter.
do $$
declare
  u uuid := gen_random_uuid();
  v_one text;
  v_two text;
  r jsonb;
  v_report private.poll_reports;
begin
  insert into auth.users (id) values (u);
  v_one := public.create_poll(u, null, 'en', pg_temp.picture(), pg_temp.picture(), 10, 10, 10, 10,
                              'txn-report', 'verified')->>'poll_id';
  v_two := pg_temp.make_poll(u);

  assert public.report_poll(v_one, 'boring')->>'code' = 'bad_request', 'a known reason';
  assert public.report_poll('AAAAAAAAAAAAAAAA', 'other')->>'code' = 'not_found', 'no such poll';

  r := public.report_poll(v_one, 'sexual', '203.0.113.80');
  assert r = '{"ok": true, "reported": true, "taken_down": true}'::jsonb, format('at once: %s', r);
  assert (select taken_down_at is not null from private.polls where id = v_one), 'taken down';
  select * into v_report from private.poll_reports where poll_id = v_one;
  assert v_report.user_id = u and v_report.install_key = private.keyed_hash('app_transaction', 'txn-report')
     and v_report.took_down and v_report.status = 'open', format('%s', v_report);
  assert public.report_poll(v_one, 'other')->>'code' = 'not_found', 'already down';

  r := public.report_poll(v_two, 'bullying', '203.0.113.81');
  assert r->>'taken_down' = 'false', format('one: %s', r);
  r := public.report_poll(v_two, 'privacy', '203.0.113.81');
  assert r->>'taken_down' = 'false', format('the same address again: %s', r);
  r := public.report_poll(v_two, 'harmful', '203.0.113.82');
  assert r->>'taken_down' = 'false', format('two addresses: %s', r);
  r := public.report_poll(v_two, 'other', '203.0.113.83');
  assert r->>'taken_down' = 'true', format('three addresses: %s', r);
  assert (select count(*) from private.poll_reports where poll_id = v_two) = 4, 'every report recorded';
  assert not exists (select 1 from private.poll_reports where poll_id = v_two and install_key is not null),
    'no install without one';
  assert (select (reports, takedowns) = (5, 2) from private.poll_daily where day = private.poll_today()),
    'counted for the owner';
  assert not exists (select 1 from private.poll_reporters where reporter like '203.0.113.%'), 'addresses hashed';

  -- 10 reports an hour per address.
  update private.polls set taken_down_at = null where id = v_two;
  delete from private.poll_reporters where poll_id = v_two;
  update private.poll_usage set count = 10 where kind = 'report_ip' and bucket = private.keyed_hash('ip', '203.0.113.81');
  assert public.report_poll(v_two, 'other', '203.0.113.81')->>'code' = 'rate_limited', 'address cap';

  -- The owner's list and tools.
  r := (select to_jsonb(x) from public.ops_poll_reports(7) x where x.poll_id = v_one);
  assert r->>'poll_state' = 'taken_down' and (r->>'reports')::int = 1 and r->'reasons' = '["sexual"]'::jsonb
     and (r->>'user_id')::uuid = u and (r->>'took_down')::boolean, format('%s', r);
  r := (select to_jsonb(x) from public.ops_poll_reports(7) x where x.poll_id = v_two);
  assert r->>'poll_state' = 'live' and (r->>'reports')::int = 4 and (r->>'open_reports')::int = 4, format('%s', r);
  assert public.ops_restore_poll(v_one), 'restored';
  assert (public.poll_view(v_one)->>'ok')::boolean, 'answers again';
  assert (select bool_and(status = 'dismissed') from private.poll_reports where poll_id = v_one), 'reports dismissed';
  assert not public.ops_restore_poll(v_one), 'nothing to restore twice';
  assert public.ops_take_down_poll(v_one), 'taken down by the owner';
  assert not public.ops_take_down_poll(v_one), 'once';
  assert public.ops_set_poll_report_status(v_two, 'reviewed') = 4, 'marked reviewed';
  begin
    perform public.ops_set_poll_report_status(v_two, 'lost');
    assert false, 'unknown status';
  exception when raise_exception then
    null;
  end;

  r := public.ops_polls_summary(private.poll_today());
  assert (r->>'created')::int = 2 and (r->>'reports')::int = 5 and (r->>'takedowns')::int = 3
     and (r->>'taken_down_now')::int = 1 and (r->>'live_now')::int = 1, format('summary: %s', r);
  assert (r->>'polls_cap')::int = 300 and (r->>'image_loads_cap')::int = 2000 and r ? 'image_mb', format('%s', r);
  r := public.ops_polls_summary(private.poll_today() - 30);
  assert (r->>'created')::int = 0 and (r->>'live_now')::int = 1, format('a quiet day: %s', r);

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
  assert not exists (select 1 from private.poll_reports where user_id = u), 'reports go with her account';
  assert not exists (select 1 from private.poll_reporters where poll_id in (v_one, v_two)), 'reporters with the poll';
end $$;

-- Her list and deleting a poll.
do $$
declare
  u uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  v_live text;
  v_down text;
  v_old text;
  r jsonb;
begin
  insert into auth.users (id) values (u), (other);
  v_old := pg_temp.make_poll(u, 'old');
  update private.polls set created_at = now() - interval '25 hours', expires_at = now() - interval '1 hour'
   where id = v_old;
  v_down := pg_temp.make_poll(u, 'down');
  update private.polls set taken_down_at = now(), created_at = now() - interval '1 minute' where id = v_down;
  v_live := pg_temp.make_poll(u, 'live');
  perform public.cast_poll_vote(v_live, 'someVoterCode_00001', 'b');
  perform pg_temp.make_poll(other, 'not hers');

  r := public.my_polls(u);
  assert jsonb_array_length(r->'polls') = 2, format('live and taken down, not ended: %s', r);
  assert r->'polls'->0->>'poll_id' = v_live and r->'polls'->0->>'status' = 'live'
     and r->'polls'->0->'votes' = '{"a": 0, "b": 1}'::jsonb and r->'polls'->0->>'question' = 'live',
    format('newest first: %s', r);
  assert r->'polls'->1->>'poll_id' = v_down and r->'polls'->1->>'status' = 'taken_down', format('%s', r);
  assert (r->>'remaining_today')::int = 3, format('made with create_poll only, so nothing admitted: %s', r);
  assert public.my_polls(gen_random_uuid())->'polls' = '[]'::jsonb, 'nobody''s';

  assert public.delete_poll(v_live, other) = '{"deleted": false}'::jsonb, 'only hers';
  assert public.delete_poll(v_live, u) = '{"deleted": true}'::jsonb, 'deleted';
  assert not exists (select 1 from private.polls where id = v_live), 'gone';
  assert not exists (select 1 from private.poll_votes where poll_id = v_live), 'with its votes';
  assert public.delete_poll(v_live, u) = '{"deleted": false}'::jsonb, 'once';
  assert public.delete_poll(v_down, u) = '{"deleted": true}'::jsonb, 'a taken-down one too';
  -- 20261103000001: out of her list, kept for review until its 24 hours end.
  assert exists (select 1 from private.polls where id = v_down and hidden_at is not null), 'kept for review';
  assert public.my_polls(u)->'polls' = '[]'::jsonb, 'not in her list';
  assert public.delete_poll(v_down, u) = '{"deleted": false}'::jsonb, 'once too';

  delete from private.poll_daily;
  delete from auth.users where id in (u, other);
end $$;

-- Sign in with Apple: her polls and their reports move to the account.
do $$
declare
  anon_user uuid := gen_random_uuid();
  account uuid := gen_random_uuid();
  v_id text;
begin
  insert into auth.users (id, is_anonymous) values (anon_user, true), (account, false);
  v_id := pg_temp.make_poll(anon_user);
  perform public.report_poll(v_id, 'bullying', '203.0.113.90');
  perform public.merge_accounts(anon_user, account);
  delete from auth.users where id = anon_user;
  assert (select user_id from private.polls where id = v_id) = account, 'the poll moved';
  assert (select user_id from private.poll_reports where poll_id = v_id) = account, 'its report record too';
  assert (public.my_polls(account)->'polls'->0->>'poll_id') = v_id, 'her list shows it';
  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = account;
  assert not exists (select 1 from private.polls where id = v_id), 'deleted with the account';
end $$;

-- The sweep: a poll within minutes of its end, report records after 30
-- days, counters after 2 days, daily numbers after 90 days.
do $$
declare
  u uuid := gen_random_uuid();
  v_ended text;
  v_live text;
begin
  insert into auth.users (id) values (u);
  v_ended := pg_temp.make_poll(u);
  v_live := pg_temp.make_poll(u);
  perform public.cast_poll_vote(v_ended, 'sweepVoterCode_0001', 'a');
  perform public.report_poll(v_ended, 'other', '203.0.113.95');
  update private.polls set expires_at = now() - interval '1 second' where id = v_ended;
  insert into private.poll_reports (poll_id, user_id, reason, created_at)
    values ('OldOldOldOldOld_', u, 'other', now() - interval '31 days'),
           ('NewNewNewNewNew_', u, 'other', now() - interval '29 days');
  insert into private.poll_usage (kind, bucket, period, count)
    values ('view_ip', 'old', date_trunc('hour', now()) - interval '3 days', 1),
           ('view_ip', 'new', date_trunc('hour', now()) - interval '1 day', 1);
  insert into private.poll_daily (day) values (private.poll_today() - 91), (private.poll_today() - 89);

  perform public.sweep_jobs();

  assert not exists (select 1 from private.polls where id = v_ended), 'the ended poll is gone';
  assert not exists (select 1 from private.poll_votes where poll_id = v_ended), 'with its votes';
  assert not exists (select 1 from private.poll_reporters where poll_id = v_ended), 'and its reporters';
  assert exists (select 1 from private.poll_reports where poll_id = v_ended), 'its report record stays 30 days';
  assert exists (select 1 from private.polls where id = v_live), 'a live poll stays';
  assert not exists (select 1 from private.poll_reports where poll_id = 'OldOldOldOldOld_'), 'old record gone';
  assert exists (select 1 from private.poll_reports where poll_id = 'NewNewNewNewNew_'), 'newer record stays';
  assert not exists (select 1 from private.poll_usage where bucket = 'old'), 'old counters gone';
  assert exists (select 1 from private.poll_usage where bucket = 'new'), 'recent counters stay';
  assert not exists (select 1 from private.poll_daily where day = private.poll_today() - 91), 'old numbers gone';
  assert exists (select 1 from private.poll_daily where day = private.poll_today() - 89), 'recent numbers stay';

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
  assert not exists (select 1 from private.poll_reports where user_id = u), 'records go with the account';
end $$;

select 'all poll tests passed' as result;
