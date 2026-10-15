-- Room for paid jobs under the launch breakers.
-- ----------------------------------------------------------------------------
-- 20261027000001 set the day's hard breaker (all_jobs_daily_cap) to 120 jobs of
-- any kind, so free jobs and the paid jobs behind them could stop Pro members
-- and pack buyers for the rest of the UTC day. It is now 400: free jobs still
-- stop at 60 (unverified installs at 10, part of the 60), so paid jobs always
-- have at least 340 a day before the hard breaker, which stays the ceiling on
-- a day's jobs (the provider balance estimate and the billing pause of
-- 20261028000000 guard the money). Every other number is unchanged.

create or replace function public.credit_policy(
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
    60,    -- free_jobs_daily_cap
    10,    -- unverified_jobs_daily_cap
    400,   -- all_jobs_daily_cap (free jobs stop at 60, so paid jobs keep 340+)
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

revoke execute on function public.credit_policy() from public, anon, authenticated;
grant execute on function public.credit_policy() to service_role;
