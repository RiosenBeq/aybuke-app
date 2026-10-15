-- Launch budget: the owner keeps the image provider (xAI) on its current small
-- balance, so the day's hard breakers are lowered to keep spend to a few dollars a
-- day: 60 free jobs, 10 from unverified installs and 120 in all (were 1,500, 200
-- and 8,000). Every other number is unchanged. Raise them again with a new
-- migration once revenue funds the provider.

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
    120,   -- all_jobs_daily_cap
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
