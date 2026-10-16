-- The admin page's API (20261105100000): server only, RLS on its tables, a
-- fixed search_path; the gate's rate limit and lockout; tags in place of ids,
-- keys and addresses; the actions and their audit; the yearly sweep.
-- Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on failure
-- and cleans up after itself. A DO block is one transaction, so now() stays
-- the same inside it: the minute and the windows can't roll over mid-test.
\set ON_ERROR_STOP on

-- Server only, RLS on, search_path set, and the numbers.
do $$
declare
  fn text;
  t text;
  pol record;
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
    assert not has_function_privilege('anon', fn, 'execute'), fn || ': server only (anon)';
    assert not has_function_privilege('authenticated', fn, 'execute'), fn || ': server only (authenticated)';
    assert has_function_privilege('service_role', fn, 'execute'), fn || ': the function calls it';
  end loop;
  foreach fn in array array[
    'private.admin_install_tag(text)',
    'private.admin_user_tag(uuid)',
    'private.admin_address_tag(text)',
    'private.admin_find(text)'
  ] loop
    assert not has_function_privilege('anon', fn, 'execute'), fn || ': private (anon)';
    assert not has_function_privilege('authenticated', fn, 'execute'), fn || ': private (authenticated)';
  end loop;
  foreach t in array array['private.admin_requests', 'private.admin_failures', 'private.admin_audit'] loop
    assert (select relrowsecurity from pg_class where oid = t::regclass), t || ': RLS is on';
    assert not has_table_privilege('anon', t, 'select'), t || ': no client reads it (anon)';
    assert not has_table_privilege('authenticated', t, 'select'), t || ': no client reads it (authenticated)';
    assert not has_table_privilege('authenticated', t, 'insert'), t || ': no client writes it';
  end loop;
  assert not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.proname like 'admin\_%'
       and not coalesce(p.proconfig @> array['search_path=""'], false)),
    'every admin function sets search_path';
  assert (select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('admin_gate', 'admin_ai_state', 'admin_moderation',
                                                        'admin_audit_recent', 'admin_action')),
    'the public ones run as their owner (the private tables)';

  select * into pol from public.admin_policy();
  assert (pol.requests_per_minute, pol.failed_tokens, pol.failure_window_minutes, pol.lockout_minutes,
          pol.pause_hours, pol.audit_days) = (60, 5, 15, 15, 24, 365), format('numbers: %s', row_to_json(pol));
end $$;

-- Wrong tokens: 5 within 15 minutes, then nothing for 15 minutes; the right
-- token forgives earlier misses; addresses are keyed, never stored.
do $$
declare
  r jsonb;
  i int;
begin
  delete from private.admin_requests;
  delete from private.admin_failures;

  for i in 1..5 loop
    r := public.admin_gate('1.2.3.4', false);
    assert r = '{"ok": false, "code": "unauthorized", "status": 401}'::jsonb, format('miss %s: %s', i, r);
  end loop;
  r := public.admin_gate('1.2.3.4', true);
  assert r ->> 'code' = 'locked_out' and (r ->> 'status')::int = 429, format('locked, even the right token: %s', r);
  assert (r ->> 'retry_after')::int between 1 and 900, format('15 minutes at most: %s', r);
  assert public.admin_gate('1.2.3.4', false) ->> 'code' = 'locked_out', 'a miss while locked changes nothing';
  assert (select failures from private.admin_failures where ip_key = private.keyed_hash('admin_ip', '1.2.3.4')) = 5,
    'misses while locked are not counted';
  assert public.admin_gate('5.6.7.8', true) = '{"ok": true}'::jsonb, 'another address is not locked';
  assert not exists (select 1 from private.admin_failures where ip_key like '%1.2.3.4%'),
    'no raw address in the table';
  assert not exists (select 1 from private.admin_requests where ip_key like '%1.2.3.4%'),
    'no raw address in the counters';

  -- The lock ends: the right token goes through and clears the record.
  update private.admin_failures
     set locked_until = now() - interval '1 second', window_started_at = now() - interval '16 minutes'
   where ip_key = private.keyed_hash('admin_ip', '1.2.3.4');
  assert public.admin_gate('1.2.3.4', true) = '{"ok": true}'::jsonb, 'the lock ended';
  assert not exists (select 1 from private.admin_failures where ip_key = private.keyed_hash('admin_ip', '1.2.3.4')),
    'the right token forgives earlier misses';

  -- Four misses, the right token, four more: never locked.
  for i in 1..4 loop
    perform public.admin_gate('1.2.3.4', false);
  end loop;
  assert public.admin_gate('1.2.3.4', true) = '{"ok": true}'::jsonb, 'four misses are fine';
  for i in 1..4 loop
    assert public.admin_gate('1.2.3.4', false) ->> 'code' = 'unauthorized', format('miss %s after a success', i);
  end loop;

  -- A window that ended starts again from one.
  update private.admin_failures set window_started_at = now() - interval '15 minutes'
   where ip_key = private.keyed_hash('admin_ip', '1.2.3.4');
  assert public.admin_gate('1.2.3.4', false) ->> 'code' = 'unauthorized', 'a fifth miss in a new window';
  assert (select failures from private.admin_failures where ip_key = private.keyed_hash('admin_ip', '1.2.3.4')) = 1,
    'counted from one again';

  -- No address at all shares one bucket.
  assert public.admin_gate(null, true) = '{"ok": true}'::jsonb, 'no address: still answered';
  assert exists (select 1 from private.admin_requests where ip_key = private.keyed_hash('admin_ip', 'unknown')),
    'counted as unknown';

  delete from private.admin_requests;
  delete from private.admin_failures;
end $$;

-- At most 60 requests a minute per address.
do $$
declare
  r jsonb;
  i int;
begin
  delete from private.admin_requests;
  for i in 1..60 loop
    assert public.admin_gate('9.9.9.9', true) = '{"ok": true}'::jsonb, format('request %s', i);
  end loop;
  r := public.admin_gate('9.9.9.9', true);
  assert r ->> 'code' = 'rate_limited' and (r ->> 'status')::int = 429, format('the 61st: %s', r);
  assert (r ->> 'retry_after')::int between 1 and 60, format('until the next minute: %s', r);
  assert public.admin_gate('9.9.9.10', true) = '{"ok": true}'::jsonb, 'another address has its own count';

  -- Old minutes go as the gate runs.
  insert into private.admin_requests (ip_key, minute, requests) values ('old', date_trunc('minute', now()) - interval '10 minutes', 3);
  perform public.admin_gate('9.9.9.10', true);
  assert not exists (select 1 from private.admin_requests where ip_key = 'old'), 'old minutes are dropped';
  delete from private.admin_requests;
end $$;

-- Tags in place of ids, keys and addresses; the actions and their audit.
do $$
declare
  u1 uuid := gen_random_uuid();
  u2 uuid := gen_random_uuid();
  k1 text := private.keyed_hash('app_transaction', 'admin-test-1');
  k2 text := private.keyed_hash('app_transaction', 'admin-test-2');
  t1 text := 'i-' || left(private.keyed_hash('app_transaction', 'admin-test-1'), 12);
  t2 text := 'i-' || left(private.keyed_hash('app_transaction', 'admin-test-2'), 12);
  poll text := 'AdminTestPoll_01';
  j uuid;
  m jsonb;
  s jsonb;
  r jsonb;
  a jsonb;
  v_audit int;
begin
  perform public.ops_resume_ai();
  delete from private.admin_audit;
  insert into auth.users (id) values (u1), (u2);
  insert into private.strikes (user_id, install_key, source, category) values
    (u1, k1, 'prompt', 'sexual'), (u1, k1, 'prompt', 'sexual');
  insert into public.jobs (user_id, operation, endpoint, status, install_key)
    values (u2, 'magic_edit', 'xai/grok-imagine-image-2.0', 'completed', k2) returning id into j;
  insert into public.reports (user_id, job_id, reason, details) values (u2, j, 'offensive', 'not nice');
  insert into private.polls (id, user_id, install_key, image_a, image_b, a_width, a_height, b_width, b_height, expires_at)
    values (poll, u1, k1, decode(repeat('ff', 128), 'hex'), decode(repeat('ff', 128), 'hex'), 1, 1, 1, 1,
            now() + interval '1 hour');
  insert into private.poll_reports (poll_id, user_id, install_key, reason) values (poll, u1, k1, 'other');

  -- Moderation: tags only.
  m := public.admin_moderation(7);
  for s in select * from jsonb_array_elements(m -> 'strikes') loop
    exit when s ->> 'install' = t1;
  end loop;
  assert s ->> 'install' = t1, format('the strikes, by install tag: %s', m -> 'strikes');
  assert s -> 'users' = jsonb_build_array(private.admin_user_tag(u1)) and (s ->> 'strikes')::int = 2,
    format('with the user as a tag: %s', s);
  assert private.admin_user_tag(u1) ~ '^u-[0-9a-f]{12}$', 'a user tag is short';
  assert private.admin_user_tag(u1) <> 'u-' || left(replace(u1::text, '-', ''), 12), 'and salted, not the id';
  assert m -> 'reports' -> 0 ->> 'install' = t2 and m -> 'reports' -> 0 ->> 'user' = private.admin_user_tag(u2),
    format('reports: %s', m -> 'reports');
  assert m -> 'reports' -> 0 ->> 'details' = 'not nice', 'what she wrote';
  assert m -> 'poll_reports' -> 0 ->> 'poll_id' = poll and m -> 'poll_reports' -> 0 ->> 'install' = t1
     and m -> 'poll_reports' -> 0 ->> 'user' = private.admin_user_tag(u1), format('poll reports: %s', m -> 'poll_reports');
  assert position(u1::text in m::text) = 0 and position(u2::text in m::text) = 0 and position(j::text in m::text) = 0,
    'no user or job id';
  assert position(k1 in m::text) = 0 and position(k2 in m::text) = 0, 'no whole install key';

  -- Block and unblock by tag.
  r := public.admin_action('block', t1, '7.7.7.7');
  assert r = jsonb_build_object('ok', true, 'result', jsonb_build_object('blocked', true, 'new_block', true,
                                                                          'outcome', 'done')), format('block: %s', r);
  assert exists (select 1 from private.blocks where install_key = k1 and lifted_at is null and reason = 'admin_page'),
    'the install is blocked';
  assert public.admin_action('block', t1, '7.7.7.7') -> 'result' ->> 'outcome' = 'no_change', 'already blocked';
  r := public.admin_action('unblock', t1, '7.7.7.7');
  assert r -> 'result' ->> 'outcome' = 'done' and (r -> 'result' ->> 'blocks_lifted')::int = 1, format('unblock: %s', r);
  assert public.admin_action('unblock', t1, '7.7.7.7') -> 'result' ->> 'outcome' = 'no_change', 'nothing left to lift';
  r := public.admin_action('block', private.admin_user_tag(u2), '7.7.7.7');
  assert r -> 'result' ->> 'new_block' = 'true', format('a user: %s', r);
  assert exists (select 1 from private.blocks where user_id = u2 and lifted_at is null), 'the user is blocked';
  assert position(u2::text in r::text) = 0, 'the answer names nobody';
  perform public.admin_action('unblock', private.admin_user_tag(u2), '7.7.7.7');
  assert not exists (select 1 from private.blocks where user_id = u2 and lifted_at is null), 'and unblocked';
  r := public.admin_action('block', t2, '7.7.7.7');
  assert r -> 'result' ->> 'outcome' = 'done', format('an install seen only in jobs: %s', r);
  perform public.admin_action('unblock', t2, '7.7.7.7');

  r := public.admin_action('block', 'i-000000000000', '7.7.7.7');
  assert r = '{"ok": false, "code": "not_found", "status": 404}'::jsonb, format('unknown tag: %s', r);
  insert into private.strikes (install_key, source) values ('abcdef012345aaaa', 'prompt'), ('abcdef012345bbbb', 'prompt');
  r := public.admin_action('block', 'i-abcdef012345', '7.7.7.7');
  assert r = '{"ok": false, "code": "ambiguous", "status": 409}'::jsonb, format('two installs share it: %s', r);
  assert not exists (select 1 from private.blocks where install_key like 'abcdef012345%'), 'nobody blocked';

  -- Bad requests change nothing and aren't audited.
  select count(*) into v_audit from private.admin_audit;
  assert public.admin_action('nuke', null, '7.7.7.7') ->> 'code' = 'bad_request', 'unknown action';
  assert public.admin_action('block', 'x', '7.7.7.7') ->> 'code' = 'bad_request', 'not a tag';
  assert public.admin_action('block', null, '7.7.7.7') ->> 'code' = 'bad_request', 'no target';
  assert public.admin_action('block', k1, '7.7.7.7') ->> 'code' = 'bad_request', 'never a whole key';
  assert public.admin_action('pause_ai', 'everything', '7.7.7.7') ->> 'code' = 'bad_request', 'unknown scope';
  assert public.admin_action('take_down_poll', 'short', '7.7.7.7') ->> 'code' = 'bad_request', 'not a poll id';
  assert (select count(*) from private.admin_audit) = v_audit, 'not audited';

  -- Pause and resume.
  r := public.admin_action('pause_ai', null, '7.7.7.7');
  assert r -> 'result' ->> 'scope' = 'all' and r -> 'result' ->> 'outcome' = 'done', format('pause: %s', r);
  assert (select note from private.ai_switches where scope = 'all') = 'admin_page', 'noted';
  assert (select paused_until from private.ai_switches where scope = 'all')
         between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute', '24 hours';
  a := public.admin_ai_state();
  assert a ->> 'paused' = 'true' and a ->> 'scope' = 'all' and a ->> 'reason' = 'admin_page' and a ? 'until',
    format('state: %s', a);
  r := public.admin_action('resume_ai', null, '7.7.7.7');
  assert r -> 'result' -> 'resumed' = '["all"]'::jsonb and r -> 'result' ->> 'outcome' = 'done', format('resume: %s', r);
  assert public.admin_ai_state() = '{"paused": false}'::jsonb, 'running';
  assert public.admin_action('resume_ai', 'all', '7.7.7.7') -> 'result' ->> 'outcome' = 'no_change', 'nothing paused';
  perform public.admin_action('pause_ai', 'free', '7.7.7.7');
  assert public.admin_ai_state() ->> 'scope' = 'free', 'free credits only';
  perform public.admin_action('resume_ai', 'free', '7.7.7.7');

  -- Never shortens the provider's 30-day pause.
  perform public.pause_ai_for_provider('provider_billing');
  r := public.admin_action('pause_ai', 'all', '7.7.7.7');
  assert r -> 'result' ->> 'outcome' = 'no_change', format('a longer pause stays: %s', r);
  assert (select paused_until from private.ai_switches where scope = 'all') > now() + interval '29 days', 'still 30 days';
  assert (select note from private.ai_switches where scope = 'all') = 'provider_billing', 'and its reason';
  assert public.admin_ai_state() ->> 'reason' = 'provider_billing', 'the page shows why';
  perform public.admin_action('resume_ai', 'all', '7.7.7.7');

  -- Polls.
  r := public.admin_action('take_down_poll', poll, '7.7.7.7');
  assert r -> 'result' = '{"taken_down": true, "outcome": "done"}'::jsonb, format('take down: %s', r);
  assert (select taken_down_at from private.polls where id = poll) is not null, 'down';
  assert public.admin_action('take_down_poll', poll, '7.7.7.7') -> 'result' ->> 'outcome' = 'no_change', 'already down';
  r := public.admin_action('restore_poll', poll, '7.7.7.7');
  assert r -> 'result' = '{"restored": true, "outcome": "done"}'::jsonb, format('restore: %s', r);
  assert (select taken_down_at from private.polls where id = poll) is null, 'up again';
  r := public.admin_action('take_down_poll', 'ZZZZZZZZZZZZZZZZ', '7.7.7.7');
  assert r = '{"ok": false, "code": "not_found", "status": 404}'::jsonb, format('no such poll: %s', r);

  -- The audit: tags only, newest first.
  assert (select count(*) from private.admin_audit) = 21, format('every action: %s', (select count(*) from private.admin_audit));
  assert not exists (select 1 from private.admin_audit where address_tag <> private.admin_address_tag('7.7.7.7')),
    'the address as a tag';
  assert private.admin_address_tag('7.7.7.7') = 'a-' || left(private.keyed_hash('ip', '7.7.7.7'), 12),
    'the rate limits'' key, shortened';
  assert not exists (select 1 from private.admin_audit a
                      where a.address_tag like '%7.7.7.7%' or a.target_tag like '%' || k1 || '%'
                         or a.target_tag = poll), 'no address, key or poll id';
  assert (select target_tag from private.admin_audit where action = 'take_down_poll' order by id limit 1)
         = 'p-AdminT', 'a poll as its first six characters';
  a := public.admin_audit_recent(50);
  assert jsonb_array_length(a) = 21, format('all of them: %s', jsonb_array_length(a));
  assert a -> 0 ->> 'action' = 'take_down_poll' and a -> 0 ->> 'outcome' = 'not_found'
     and a -> 0 ->> 'target' = 'p-ZZZZZZ', format('newest first: %s', a -> 0);
  assert a -> 0 ? 'at' and a -> 0 ->> 'address' = private.admin_address_tag('7.7.7.7'), format('fields: %s', a -> 0);
  assert jsonb_array_length(public.admin_audit_recent(3)) = 3, 'a limit';
  assert jsonb_array_length(public.admin_audit_recent(100000)) = 21, 'at most 200, here all';
  assert public.admin_action('resume_ai', null, null) -> 'result' ->> 'outcome' = 'no_change', 'no address';
  assert (select address_tag from private.admin_audit order by id desc limit 1) = 'a-unknown', 'tagged unknown';

  delete from private.strikes where install_key in (k1, 'abcdef012345aaaa', 'abcdef012345bbbb');
  delete from private.blocks where install_key in (k1, k2) or user_id in (u1, u2);
  delete from private.poll_reports where poll_id = poll;
  update private.poll_daily set takedowns = takedowns - 1 where day = private.poll_today();
  delete from auth.users where id in (u1, u2);
  delete from private.admin_audit;
  perform public.ops_resume_ai();
end $$;

-- The audit is kept one year; the gate's counters a day.
do $$
begin
  delete from private.admin_audit;
  insert into private.admin_audit (at, action, target_tag, address_tag, outcome) values
    (now() - interval '366 days', 'pause_ai', 'all', 'a-unknown', 'done'),
    (now() - interval '364 days', 'resume_ai', 'all', 'a-unknown', 'done');
  insert into private.admin_requests (ip_key, minute, requests) values ('old', now() - interval '2 days', 1),
                                                                       ('new', date_trunc('minute', now()), 1);
  insert into private.admin_failures (ip_key, window_started_at, failures, locked_until) values
    ('old', now() - interval '2 days', 5, now() - interval '2 days'),
    ('new', now(), 1, null);
  perform public.sweep_app_store_notifications();
  assert (select array_agg(action) from private.admin_audit) = array['resume_ai'], 'a year';
  assert (select array_agg(ip_key) from private.admin_requests) = array['new'], 'counters a day';
  assert (select array_agg(ip_key) from private.admin_failures) = array['new'], 'misses a day';
  delete from private.admin_audit;
  delete from private.admin_requests;
  delete from private.admin_failures;
end $$;
