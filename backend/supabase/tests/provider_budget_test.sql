-- The provider balance estimate, its one low-balance mail and the billing pause.
-- Run with backend/scripts/test-db.sh. Each block raises (ASSERT) on failure.
\set ON_ERROR_STOP on

do $$
declare
  u uuid := gen_random_uuid();
  b0 jsonb;
  b jsonb;
  v_old_today boolean :=
    (now() - interval '1 second') >= (now() at time zone 'utc')::date::timestamp at time zone 'utc';
begin
  assert not has_function_privilege('anon', 'public.ops_provider_budget(text)', 'execute'), 'owner only';
  assert not has_function_privilege('authenticated', 'public.ops_set_provider_balance(text, int)', 'execute'), 'owner only';
  assert not has_function_privilege('authenticated', 'public.claim_provider_low_alert(text)', 'execute'), 'server only';
  assert not has_function_privilege('authenticated', 'public.pause_ai_for_provider(text, numeric)', 'execute'), 'server only';
  assert has_function_privilege('service_role', 'public.ops_provider_budget(text)', 'execute'), 'ai-image reads it';
  assert has_function_privilege('service_role', 'public.pause_ai_for_provider(text, numeric)', 'execute'), 'ai-image pauses';

  assert public.ops_provider_budget() ->> 'provider' = 'xai', 'seeded for xAI';
  assert public.ops_provider_budget('nobody') is null, 'no balance recorded for another provider';

  -- A top-up: counted from now, with a fresh low-balance mail.
  b0 := public.ops_set_provider_balance('xai', 1000);
  assert (b0 ->> 'balance_cents')::int = 1000 and (b0 ->> 'spent_cents')::int = 0, format('recorded: %s', b0);
  assert (b0 ->> 'remaining_cents')::int = 1000 and b0 ->> 'low_alert_sent_at' is null, format('fresh: %s', b0);

  insert into auth.users (id) values (u);
  insert into public.jobs (user_id, operation, endpoint, status, error_code, est_cost_cents, created_at) values
    -- What xAI billed: results, blocked ones included.
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'completed', null, 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'content_blocked', 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'safety_check_failed', 4, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'undelivered', 4, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'unconfirmed', 4, now()),
    -- Never billed: failures before a result, cancels, running jobs.
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'provider_failed', 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'failed', 'provider_billing', 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'cancelled', null, 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'queued', null, 5, now()),
    -- Another provider, and a result from before the top-up.
    (u, 'magic_edit', 'fal-ai/flux-pro/kontext', 'completed', null, 5, now()),
    (u, 'magic_edit', 'xai/grok-imagine-image-2.0', 'completed', null, 7, now() - interval '1 second');

  b := public.ops_provider_budget('xai');
  assert (b ->> 'spent_cents')::int = 22, format('billed since the top-up: %s', b);
  assert (b ->> 'remaining_cents')::int = 978, format('what is left: %s', b);
  assert (b ->> 'jobs_today')::int - (b0 ->> 'jobs_today')::int = 9 + case when v_old_today then 1 else 0 end,
    format('xAI jobs today: %s', b);

  -- One low-balance mail per recorded balance.
  assert public.claim_provider_low_alert('xai'), 'the first claim wins';
  assert not public.claim_provider_low_alert('xai'), 'one mail only';
  assert public.ops_provider_budget('xai') ->> 'low_alert_sent_at' is not null, 'the claim shows';
  b := public.ops_set_provider_balance('xai', 2500);
  assert b ->> 'low_alert_sent_at' is null and (b ->> 'remaining_cents')::int = 2500 - 22, format('a top-up: %s', b);
  assert public.claim_provider_low_alert('xai'), 'a new balance gets a new mail';
  assert not public.claim_provider_low_alert('nobody'), 'nothing to claim';

  delete from auth.users where id = u;
end $$;

-- xAI out of credit: AI pauses for everyone once, until the owner resumes it.
do $$
declare
  u uuid := gen_random_uuid();
  r jsonb;
begin
  perform public.ops_resume_ai();
  insert into auth.users (id) values (u);

  assert public.pause_ai_for_provider('provider_billing'), 'the first billing error pauses';
  assert not public.pause_ai_for_provider('provider_billing'), 'already paused: no second mail';
  assert (select note from private.ai_switches where scope = 'all') = 'provider_billing', 'the reason is kept';
  assert (select paused_until from private.ai_switches where scope = 'all') > now() + interval '29 days',
    'paused until the owner resumes';
  r := public.admit_job(u, 'magic_edit', 'xai/grok-imagine-image-2.0', p_input_images => 1);
  assert r ->> 'code' = 'ai_paused' and (r ->> 'status')::int = 503, format('jobs stop at admission: %s', r);
  assert (select count(*) from public.jobs where user_id = u) = 0, 'nothing reached the provider';

  -- After ops_resume_ai() the next billing error pauses (and mails) again.
  perform public.ops_resume_ai();
  assert public.pause_ai_for_provider('provider_billing'), 'a new pause';
  -- An owner's pause that already ended is replaced.
  update private.ai_switches set paused_until = now() - interval '1 minute' where scope = 'all';
  assert public.pause_ai_for_provider('provider_billing'), 'an expired switch is turned on again';

  perform public.ops_resume_ai();
  delete from auth.users where id = u;
end $$;

select 'all provider budget tests passed' as result;
