-- Polls (20261103000001): attempts without a verified install share a small
-- daily cap; blocked questions and unreadable pictures count apart from
-- today's polls for everyone; picture loads count once per picture, address
-- and day toward the cap for everyone, and every load toward a backstop;
-- "Edited with AI" labels; a taken-down poll its maker deletes stays for
-- review until it ends. Run with backend/scripts/test-db.sh. Each block raises
-- (ASSERT) on failure and cleans up after itself.
\set ON_ERROR_STOP on

-- Server only, and the numbers.
do $$
declare
  fn text;
  pol record;
  more record;
begin
  foreach fn in array array[
    'public.poll_backstops()',
    'public.create_poll(uuid, text, text, text, text, int, int, int, int, text[], text, text)',
    'public.create_poll(uuid, text, text, text, text, int, int, int, int, text, text)',
    'public.admit_poll(uuid, text, text, text, text)',
    'public.poll_image(text, text, text)',
    'public.delete_poll(text, uuid)',
    'public.ops_restore_poll(text)'
  ] loop
    assert not has_function_privilege('anon', fn, 'execute'), fn || ': server only (anon)';
    assert not has_function_privilege('authenticated', fn, 'execute'), fn || ': server only (authenticated)';
    assert has_function_privilege('service_role', fn, 'execute'), fn || ': the function calls it';
  end loop;
  assert not has_function_privilege('authenticated', 'private.poll_bump(text, bigint)', 'execute'), 'private';
  assert not has_table_privilege('anon', 'private.poll_image_loads', 'select'), 'no client reads the loads';
  assert (select relrowsecurity from pg_class where oid = 'private.poll_image_loads'::regclass), 'RLS is on';

  select * into pol from public.poll_policy();
  assert (pol.image_loads_per_ip_hourly, pol.image_loads_per_poll, pol.image_loads_daily) = (60, 600, 2000),
    format('picture loads: %s', row_to_json(pol));
  assert (pol.lifetime_hours, pol.polls_per_user_daily, pol.polls_per_install_daily, pol.polls_per_ip_hourly,
          pol.polls_all_daily, pol.votes_per_ip_hourly, pol.views_per_ip_hourly, pol.reports_per_ip_hourly,
          pol.takedown_reports, pol.report_retention_days) = (24, 3, 3, 10, 300, 120, 600, 10, 3, 30),
    format('the rest as 20261102000000 set it: %s', row_to_json(pol));
  select * into more from public.poll_backstops();
  assert (more.polls_unverified_daily, more.rejected_attempts_daily, more.image_loads_raw_daily) = (30, 600, 4000),
    format('backstops: %s', row_to_json(more));
end $$;

create or replace function pg_temp.picture(p_fill text default 'x') returns text language sql as $$
  select translate(encode(convert_to(repeat(p_fill, 300), 'UTF8'), 'base64'), E'\n', '')
$$;
create or replace function pg_temp.make_poll(p_user uuid, p_sides text[] default '{}') returns text
language sql as $$
  select public.create_poll(p_user, 'Which vibe?', 'en', pg_temp.picture('a'), pg_temp.picture('b'),
                            540, 720, 720, 540, p_sides) ->> 'poll_id'
$$;

-- Without a verified install: 30 attempts a day for all of them together,
-- blocked questions included. A verified install isn't held by it.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  perform public.ops_resume_ai();
  delete from private.poll_daily;
  delete from private.poll_usage;
  insert into auth.users (id) values (u);
  r := public.admit_poll(u, null, 'missing', '203.0.113.200');
  assert (r->>'ok')::boolean, format('%s', r);
  r := public.admit_poll(u, null, 'missing', '203.0.113.200', 'sexual');
  assert r->>'code' = 'content_blocked', format('%s', r);
  assert (select (attempts, unverified_attempts, blocked_question) = (1, 2, 1)
            from private.poll_daily where day = private.poll_today()),
    'both count as unverified; only the first toward today''s polls';

  update private.poll_daily set unverified_attempts = 30 where day = private.poll_today();
  r := public.admit_poll(u, null, 'invalid', '203.0.113.200');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(),
    format('the 31st without a verified install: %s', r);
  r := public.admit_poll(u, null, 'missing', '203.0.113.200', 'sexual');
  assert r->>'code' = 'rate_limited', format('a blocked question too: %s', r);
  assert (select count from private.poll_usage where kind = 'create_user'
           and bucket = private.keyed_hash('poll_user', u::text)) = 2, 'refused before counting her';
  r := public.admit_poll(u, 'atid-poll-limits', 'verified', '203.0.113.200');
  assert (r->>'ok')::boolean, format('a verified install still gets in: %s', r);
  assert (select (attempts, unverified_attempts) = (2, 30) from private.poll_daily where day = private.poll_today()),
    'counted toward today''s polls, not the unverified ones';

  -- A check that couldn't run gives the unverified place back too.
  perform public.finish_poll_attempt(u, 'unavailable', null, 'missing', '203.0.113.200');
  assert (select (attempts, unverified_attempts) = (1, 29) from private.poll_daily where day = private.poll_today()),
    'given back';

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
end $$;

-- Blocked questions and unreadable pictures never reach the check: they
-- count apart from today's polls for everyone, against their own cap.
do $$
declare
  v_users uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  r jsonb;
begin
  delete from private.poll_daily;
  delete from private.poll_usage;
  insert into auth.users (id) select unnest(v_users);
  insert into private.poll_daily (day, attempts) values (private.poll_today(), 300);
  r := public.admit_poll(v_users[1], 'atid-rejected-1', 'verified', '198.51.100.200');
  assert r->>'code' = 'rate_limited', format('today''s polls are full: %s', r);
  r := public.admit_poll(v_users[1], 'atid-rejected-1', 'verified', '198.51.100.200', 'revealingClothing');
  assert r->>'code' = 'content_blocked' and r->>'category' = 'revealingClothing',
    format('a blocked question is still answered as such: %s', r);
  assert (select (attempts, blocked_question) = (300, 1) from private.poll_daily where day = private.poll_today()),
    'and counted apart';

  update private.poll_daily set attempts = 10, blocked_question = 400, invalid_image = 200 where day = private.poll_today();
  r := public.admit_poll(v_users[2], 'atid-rejected-2', 'verified', '198.51.100.201', 'sexual');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(),
    format('600 rejected today: %s', r);
  r := public.admit_poll(v_users[2], 'atid-rejected-2', 'verified', '198.51.100.201');
  assert (r->>'ok')::boolean, format('a real attempt isn''t held by them: %s', r);
  assert (select (attempts, blocked_question) = (11, 400) from private.poll_daily where day = private.poll_today()),
    'the refused question counted nowhere';

  -- An unreadable picture leaves today's polls for everyone (but stays used for her).
  perform public.finish_poll_attempt(v_users[2], 'image_invalid', 'atid-rejected-2', 'verified', '198.51.100.201');
  assert (select (attempts, invalid_image) = (10, 201) from private.poll_daily where day = private.poll_today()),
    'moved to the rejected count';
  assert (select count from private.poll_usage where kind = 'create_install'
           and bucket = private.keyed_hash('app_transaction', 'atid-rejected-2')) = 1, 'still one of her 3 today';
  -- A picture Claude flagged did reach the check: it stays.
  r := public.admit_poll(v_users[3], 'atid-rejected-3', 'verified', '198.51.100.202');
  perform public.finish_poll_attempt(v_users[3], 'image_blocked', 'atid-rejected-3', 'verified', '198.51.100.202');
  assert (select (attempts, blocked_image) = (11, 1) from private.poll_daily where day = private.poll_today()),
    'a flagged picture counts toward today''s polls';

  r := public.ops_polls_summary(private.poll_today());
  assert (r->>'rejected')::int = 601 and (r->>'rejected_cap')::int = 600 and (r->>'unverified_cap')::int = 30
     and (r->>'image_loads_raw_cap')::int = 4000 and (r->>'image_loads_cap')::int = 2000
     and r ? 'unverified_attempts' and r ? 'image_loads_unique', format('the summary: %s', r);

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = any (v_users);
end $$;

-- Picture loads: once per picture, address and day toward the cap for
-- everyone; every load per poll, per address and toward the backstop.
do $$
declare
  u uuid := gen_random_uuid();
  v_id text;
  r jsonb;
begin
  delete from private.poll_daily;
  delete from private.poll_usage;
  insert into auth.users (id) values (u);
  v_id := pg_temp.make_poll(u);
  for i in 1..3 loop
    assert (public.poll_image(v_id, 'a', '203.0.113.210')->>'ok')::boolean, 'a';
    assert (public.poll_image(v_id, 'b', '203.0.113.210')->>'ok')::boolean, 'b';
  end loop;
  assert (select (image_loads, image_loads_unique) = (6, 2) from private.poll_daily where day = private.poll_today()),
    'six loads, two pictures for one address';
  assert (select image_loads from private.polls where id = v_id) = 6, 'every load counts on the poll';
  assert (select count(*) from private.poll_image_loads where poll_id = v_id) = 2, 'one row per picture and address';
  assert not exists (select 1 from private.poll_image_loads where viewer like '%203.0.113.210%'), 'hashed';
  assert (public.poll_image(v_id, 'a', '203.0.113.211')->>'ok')::boolean, 'another address';
  assert (select image_loads_unique from private.poll_daily where day = private.poll_today()) = 3, 'counted once more';
  assert (public.poll_image(v_id, 'a')->>'ok')::boolean and (public.poll_image(v_id, 'a')->>'ok')::boolean,
    'without an address';
  assert (select image_loads_unique from private.poll_daily where day = private.poll_today()) = 5,
    'without an address every load counts';

  -- Today's cap for everyone: a new picture for this address waits, one it loaded doesn't.
  update private.poll_daily set image_loads_unique = 2000 where day = private.poll_today();
  r := public.poll_image(v_id, 'b', '203.0.113.211');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(), format('cap: %s', r);
  assert not exists (select 1 from private.poll_image_loads
                      where viewer = private.keyed_hash('poll_load', v_id || ':b:203.0.113.211')),
    'a refused load is no viewer';
  assert (public.poll_image(v_id, 'a', '203.0.113.211')->>'ok')::boolean, 'a picture this address has';

  -- The backstop: every load.
  update private.poll_daily set image_loads_unique = 0, image_loads = 4000 where day = private.poll_today();
  r := public.poll_image(v_id, 'a', '203.0.113.210');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = private.next_utc_day(),
    format('4,000 loads today: %s', r);

  -- 60 an hour per address.
  update private.poll_daily set image_loads = 0 where day = private.poll_today();
  update private.poll_usage set count = 59 where kind = 'image_ip' and bucket = private.keyed_hash('ip', '203.0.113.210');
  assert (public.poll_image(v_id, 'a', '203.0.113.210')->>'ok')::boolean, 'the 60th';
  r := public.poll_image(v_id, 'a', '203.0.113.210');
  assert r->>'code' = 'rate_limited' and (r->>'until')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    format('the 61st this hour: %s', r);

  -- The sweep: yesterday's rows go (all of them go with the poll anyway).
  update private.poll_image_loads set day = day - 2 where poll_id = v_id;
  perform public.sweep_jobs();
  assert not exists (select 1 from private.poll_image_loads where poll_id = v_id), 'swept';
  assert exists (select 1 from private.polls where id = v_id), 'the poll stays';

  delete from private.poll_daily;
  delete from private.poll_usage;
  delete from auth.users where id = u;
  assert not exists (select 1 from private.poll_image_loads where poll_id = v_id), 'gone with the poll';
end $$;

-- "Edited with AI": the sides the app marks, in the poll and her list.
do $$
declare
  u uuid := gen_random_uuid();
  v_b text;
  v_both text;
  v_old text;
  r jsonb;
begin
  insert into auth.users (id) values (u);
  v_b := pg_temp.make_poll(u, array['b']);
  v_both := pg_temp.make_poll(u, array['b', 'a']);
  v_old := public.create_poll(u, 'Old form', 'en', pg_temp.picture('a'), pg_temp.picture('b'), 540, 720, 720, 540)
           ->> 'poll_id';
  assert public.poll_view(v_b)->'ai' = '{"a": false, "b": true}'::jsonb, format('%s', public.poll_view(v_b));
  assert public.poll_view(v_both)->'ai' = '{"a": true, "b": true}'::jsonb, 'both';
  assert public.poll_view(v_old)->'ai' = '{"a": false, "b": false}'::jsonb, 'the 20261102000000 form: none';
  r := public.my_polls(u);
  assert (select jsonb_agg(p->'ai' order by p->>'poll_id') from jsonb_array_elements(r->'polls') p)
         = (select jsonb_agg(ai order by id) from (values (v_b, '{"a": false, "b": true}'::jsonb),
                                                          (v_both, '{"a": true, "b": true}'::jsonb),
                                                          (v_old, '{"a": false, "b": false}'::jsonb)) v(id, ai)),
    format('her list: %s', r);
  for i in 1..3 loop
    begin
      perform pg_temp.make_poll(u, case i when 1 then array['c'] when 2 then array[null]::text[] else null end);
      assert false, format('unknown sides must raise (%s)', i);
    exception when raise_exception then
      null;
    end;
  end loop;
  delete from private.poll_daily;
  delete from auth.users where id = u;
end $$;

-- She deletes a poll taken down after a report: gone from her list at once,
-- kept (closed to everyone) for review until its 24 hours end, then swept.
-- A restore can't bring it back; her account's deletion deletes it at once.
do $$
declare
  u uuid := gen_random_uuid();
  v_down text;
  v_restore text;
  r jsonb;
begin
  insert into auth.users (id) values (u);
  v_down := pg_temp.make_poll(u);
  r := public.report_poll(v_down, 'sexual', '203.0.113.220');
  assert (r->>'taken_down')::boolean, format('%s', r);
  assert public.delete_poll(v_down, u) = '{"deleted": true}'::jsonb, 'deleted, as far as she can tell';
  assert (select hidden_at is not null and taken_down_at is not null from private.polls where id = v_down),
    'kept for review';
  assert public.my_polls(u)->'polls' = '[]'::jsonb, 'not in her list';
  assert public.poll_view(v_down)->>'code' = 'not_found', 'closed to everyone';
  assert public.ops_poll_image(v_down, 'a') = 'data:image/jpeg;base64,' || pg_temp.picture('a'), 'the owner can review it';
  assert (select poll_state from public.ops_poll_reports(1) where poll_id = v_down) = 'taken_down', 'listed for review';
  assert public.delete_poll(v_down, u) = '{"deleted": false}'::jsonb, 'once';

  -- Restoring it after she deleted it: her deletion stands.
  assert public.ops_restore_poll(v_down) = false, 'not restored';
  assert not exists (select 1 from private.polls where id = v_down), 'deleted now';
  assert (select bool_and(status = 'dismissed') from private.poll_reports where poll_id = v_down), 'reports dismissed';

  -- A live poll is deleted at once, as before; a restored one is live again.
  v_restore := pg_temp.make_poll(u);
  perform public.ops_take_down_poll(v_restore);
  assert public.ops_restore_poll(v_restore), 'a mistaken takedown, restored';
  assert (public.poll_view(v_restore)->>'ok')::boolean, 'live again';
  assert public.delete_poll(v_restore, u) = '{"deleted": true}'::jsonb, 'a live poll';
  assert not exists (select 1 from private.polls where id = v_restore), 'goes at once';

  -- Its 24 hours end: the sweep deletes it like every poll.
  v_down := pg_temp.make_poll(u);
  perform public.ops_take_down_poll(v_down);
  perform public.delete_poll(v_down, u);
  update private.polls set expires_at = now() - interval '1 minute' where id = v_down;
  perform public.sweep_jobs();
  assert not exists (select 1 from private.polls where id = v_down), 'swept when it ends';

  -- Her account's deletion deletes a kept one at once.
  v_down := pg_temp.make_poll(u);
  perform public.ops_take_down_poll(v_down);
  perform public.delete_poll(v_down, u);
  delete from private.poll_daily;
  delete from auth.users where id = u;
  assert not exists (select 1 from private.polls where id = v_down), 'deleted with her account';
end $$;

select 'all poll limit tests passed' as result;
