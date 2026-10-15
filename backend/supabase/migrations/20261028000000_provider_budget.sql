-- The image provider's balance, estimated, and an automatic pause when it runs out
-- (backend/README.md, "Owner alerts").
-- ----------------------------------------------------------------------------
-- The server can't read xAI's real balance (that takes a management key), so
-- the owner records it after each top-up and the server subtracts what the jobs
-- since then most likely cost: est_cost_cents of every job the provider billed,
-- with ops_daily_summary()'s filter (results, blocked ones included). Jobs are
-- kept 30 days, so record the balance again at least once a month.
--
--   select public.ops_provider_budget();                       -- the estimate
--   select public.ops_set_provider_balance('xai', 2500);      -- after topping up $25
--
-- ai-image reads the estimate after each billed job and mails the owner once
-- when $2 or less is left (claim_provider_low_alert()). When xAI itself refuses
-- a job because the credit or the spending limit ran out, ai-image pauses AI
-- for everyone (pause_ai_for_provider(), the 'all' switch ops_pause_ai() sets)
-- and mails the owner once; admit_job() then refuses jobs with ai_paused until
-- the owner runs select public.ops_resume_ai();

create table private.provider_balances (
  provider text primary key,
  balance_cents int not null check (balance_cents >= 0),
  as_of timestamptz not null default now(),
  low_alert_sent_at timestamptz
);

alter table private.provider_balances enable row level security;
revoke all on table private.provider_balances from public;

-- About $10 was left on 15 October 2026 (the owner).
insert into private.provider_balances (provider, balance_cents, as_of) values ('xai', 1000, now())
  on conflict (provider) do nothing;

-- After a top-up: the new balance, counted from now, and a new low-balance mail.
create function public.ops_set_provider_balance(p_provider text, p_cents int)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into private.provider_balances (provider, balance_cents, as_of, low_alert_sent_at)
    values (p_provider, p_cents, now(), null)
    on conflict (provider) do update
      set balance_cents = excluded.balance_cents, as_of = excluded.as_of, low_alert_sent_at = null;
  return public.ops_provider_budget(p_provider);
end $$;

-- The estimate: the recorded balance, what billed jobs since then cost, what's
-- left, whether the low-balance mail went out, and today's jobs (UTC).
create function public.ops_provider_budget(p_provider text default 'xai')
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  b private.provider_balances;
  v_spent bigint;
  v_today timestamptz := (now() at time zone 'utc')::date::timestamp at time zone 'utc';
begin
  select * into b from private.provider_balances where provider = p_provider;
  if not found then
    return null;
  end if;
  select coalesce(sum(j.est_cost_cents), 0) into v_spent
    from public.jobs j
   where j.created_at >= b.as_of
     and j.endpoint like p_provider || '/%'
     and (j.status = 'completed'
          or j.error_code in ('content_blocked', 'safety_check_failed', 'undelivered', 'unconfirmed'));
  return jsonb_build_object(
    'provider', b.provider,
    'balance_cents', b.balance_cents,
    'as_of', b.as_of,
    'spent_cents', v_spent,
    'remaining_cents', b.balance_cents - v_spent,
    'low_alert_sent_at', b.low_alert_sent_at,
    'jobs_today', (select count(*) from public.jobs j
                    where j.created_at >= v_today and j.endpoint like p_provider || '/%'));
end $$;

-- The one low-balance mail per recorded balance: true for exactly one caller.
create function public.claim_provider_low_alert(p_provider text)
returns boolean
language sql security definer
set search_path = ''
as $$
  with claimed as (
    update private.provider_balances set low_alert_sent_at = now()
     where provider = p_provider and low_alert_sent_at is null
    returning 1
  )
  select exists (select 1 from claimed)
$$;

-- The provider refused a job for billing: the 'all' switch, as ops_pause_ai()
-- sets it, for p_hours (until the owner resumes, in practice). True only for
-- the call that turned the pause on, so the owner gets one mail per pause.
create function public.pause_ai_for_provider(p_note text, p_hours numeric default 720)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
  v_started boolean;
begin
  insert into private.ai_switches as s (scope, paused_until, note, updated_at)
    values ('all', now() + make_interval(secs => (p_hours * 3600)::double precision), p_note, now())
    on conflict (scope) do update
      set paused_until = excluded.paused_until, note = excluded.note, updated_at = now()
      where s.paused_until <= now()
  returning true into v_started;
  return coalesce(v_started, false);
end $$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.ops_set_provider_balance(text, int)',
    'public.ops_provider_budget(text)',
    'public.claim_provider_low_alert(text)',
    'public.pause_ai_for_provider(text, numeric)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
