-- Credit policy v2: every number the server enforces, in one place.
-- ----------------------------------------------------------------------------
-- Retune by replacing this function (copy it from here, change a number, run
-- it in the SQL editor); no app release is needed. The app shows the five
-- numbers that `GET /ai-image` returns (free_daily, pro_monthly,
-- rollover_cap, trial_credits, free_retries_daily) and keeps the last ones it
-- saw, with bundled defaults in ios/App/Resources/AppConfig.json.
--
--   free_daily              free credits per App Store install (Apple Account)
--                           per UTC day; the 20261021 migration keys them by
--                           a salted hash of Apple's appTransactionId
--   pro_monthly             credits per subscription month
--   pro_rollover_cap        most credits a subscription can bank (one month of rollover)
--   trial_credits           credits for the yearly plan's 7-day free trial;
--                           the first paid period then brings pro_monthly
--   free_retries_daily      Likeness Lock free retries per user per UTC day
--                           (still one per result, within 15 minutes)
--   *_daily_cap             spending circuit breakers, all users, per UTC day:
--                           jobs paid with free credits, the part of those from
--                           installs Apple sent no appTransactionId for, and
--                           every job (paid users keep working until this one)
--   jobs_per_*              per-user rate limits (free / Pro)
--   ip_jobs_per_hour        job requests per client IP across users (0 = off)
--   reports_per_day         "Report this image" per user per rolling day
--   strikes_* / cooldown_*  server-side safety blocks: strikes_for_cooldown
--                           within strike_window_hours pause cloud AI for
--                           cooldown_hours; cooldowns_for_block cool-downs
--                           within cooldown_window_days block the install
--                           until the owner lifts it
--   install_retention_days  hashed install rows are deleted after this many
--                           days without use (unless blocked)
--   cost_*_cents            xAI list prices, for the ops summary's estimate
--
-- Fixes the Security Advisor's "Function Search Path Mutable" warning
-- (search_path is pinned), and only the service role may call it: the rate
-- limits are nobody else's business.

drop function if exists public.credit_policy();

create function public.credit_policy(
  out free_daily int,
  out pro_monthly int,
  out pro_rollover_cap int,
  out trial_credits int,
  out free_retries_daily int,
  out free_jobs_daily_cap int,
  out unverified_jobs_daily_cap int,
  out all_jobs_daily_cap int,
  out jobs_per_minute_free int,
  out jobs_per_minute_pro int,
  out jobs_per_hour_free int,
  out jobs_per_hour_pro int,
  out jobs_per_day_free int,
  out jobs_per_day_pro int,
  out ip_jobs_per_hour int,
  out reports_per_day int,
  out strikes_for_cooldown int,
  out strike_window_hours int,
  out cooldown_hours int,
  out cooldowns_for_block int,
  out cooldown_window_days int,
  out install_retention_days int,
  out cost_low_cents int,
  out cost_medium_cents int,
  out cost_input_image_cents int
)
language sql stable
set search_path = ''
as $$
  select
    2,     -- free_daily
    80,    -- pro_monthly
    160,   -- pro_rollover_cap
    20,    -- trial_credits
    3,     -- free_retries_daily
    1500,  -- free_jobs_daily_cap
    200,   -- unverified_jobs_daily_cap
    8000,  -- all_jobs_daily_cap
    6,     -- jobs_per_minute_free
    20,    -- jobs_per_minute_pro
    30,    -- jobs_per_hour_free
    60,    -- jobs_per_hour_pro
    100,   -- jobs_per_day_free
    200,   -- jobs_per_day_pro
    120,   -- ip_jobs_per_hour
    10,    -- reports_per_day
    3,     -- strikes_for_cooldown
    24,    -- strike_window_hours
    24,    -- cooldown_hours
    3,     -- cooldowns_for_block
    30,    -- cooldown_window_days
    30,    -- install_retention_days
    4,     -- cost_low_cents (free tier, per image)
    6,     -- cost_medium_cents (Pro, per image)
    1      -- cost_input_image_cents (per photo sent to an edit)
$$;

comment on function public.credit_policy() is
  'Every number the server enforces (credits, breakers, rate limits, strikes). Replace it to retune; see the 20261020000000 migration.';

revoke execute on function public.credit_policy() from public, anon, authenticated;
grant execute on function public.credit_policy() to service_role;
