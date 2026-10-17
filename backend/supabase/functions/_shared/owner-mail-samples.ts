// Every owner mail with sample numbers, for the tests (owner-mail-samples_test.ts)
// and the previews (backend/scripts/owner-mail-previews.ts). Not imported by any
// function. The summaries carry fields that must never reach a mail (an email,
// ids, a token, a prompt): the tests check they don't.
import { digestMail } from "../owner-digest/handler.ts";
import { purchaseMail } from "./owner-alerts.ts";
import type { OwnerMail } from "./owner-mail.ts";
import { billingPauseMail, lowBalanceMail, parseBudget } from "./provider-alerts.ts";

/** What must never appear in a mail. */
export const PRIVATE_VALUES = [
  "buyer@example.com",
  "8d2f6a10-5c4e-4b7a-9f00-000000000abc",
  "2000000999999999",
  "eyJhbGciOiJFUzI1NiJ9.secret-token",
  "make me look older",
  "abcdef123456",
];
const [EMAIL, USER_ID, TRANSACTION_ID, TOKEN, PROMPT, INSTALL] = PRIVATE_VALUES;

export const SAMPLE_AT = new Date(Date.UTC(2026, 9, 17, 6, 0));
export const SAMPLE_DAY = "2026-10-16";

/** The RevenueCat App User IDs of deleted accounts: the one kind of id the digest may show. */
export const SAMPLE_APP_USER_IDS = ["0B7C1E2A-1111-4C2B-9D3E-0123456789AB", "5F00D1E2-2222-4A1B-8C2D-ABCDEF012345"];

export const SAMPLE_MEMBERS = {
  at: "2026-10-17T06:00:00+00:00",
  members: {
    total: 1234,
    anonymous: 1100,
    signed_in_with_apple: 134,
    new_today: 7,
    new_7_days: 96,
    new_30_days: 410,
    active_7_days: 512,
    email: EMAIL,
  },
  pro: { active_members: 12, yearly: 9, monthly: 3, ever_subscribed: 15, revoked_or_refunded: 1, user_id: USER_ID },
  credit_packs: { buyers: 4, packs_sold: 5, credits_sold: 330, last_30_days: 3, transaction_id: TRANSACTION_ID },
  ad_rewards: { granted: 88, viewers: 41, credits: 88 },
  ai_jobs: { total: 9_870, completed: 9_100, last_7_days: 2_104 },
  token: TOKEN,
};

export const SAMPLE_DAILY = {
  day: SAMPLE_DAY,
  jobs: { total: 312, free: 240, paid: 60, retries: 12, completed: 290, failed: 18, cancelled: 4, users: 140 },
  failures_by_code: { content_blocked: 9, timeout: 5, provider_error: 3, output_blocked: 1 },
  estimated_cost_usd: { billed: 6.84, admitted_upper_bound: 7.4 },
  breakers: {
    all_jobs: 312,
    all_jobs_cap: 400,
    free_jobs: 52,
    free_jobs_cap: 60,
    unverified_jobs: 3,
    unverified_jobs_cap: 10,
    switches: {},
  },
  safety: { strikes: 6, cooldowns_started: 1, cooldowns_active: 1, blocks_new: 0, blocks_active: 2 },
  reports: { new: 2, open: 1 },
  top_installs: [{ install: INSTALL, jobs: 9 }],
  last_prompt: PROMPT,
};

export const SAMPLE_BUDGET = {
  provider: "xai",
  balance_cents: 1000,
  as_of: "2026-10-15T08:00:00+00:00",
  spent_cents: 804,
  remaining_cents: 196,
  low_alert_sent_at: "2026-10-16T21:10:00+00:00",
  jobs_today: 37,
};

export const SAMPLE_POLLS = {
  day: SAMPLE_DAY,
  created: 12,
  polls_cap: 300,
  unverified_attempts: 4,
  unverified_cap: 30,
  blocked_question: 2,
  blocked_image: 1,
  invalid_image: 0,
  unavailable: 0,
  votes: 87,
  reports: 3,
  takedowns: 1,
  image_loads: 240,
  image_loads_unique: 180,
  image_loads_cap: 2000,
  image_loads_raw_cap: 4000,
  image_mb: 14.5,
  live_now: 9,
  taken_down_now: 1,
  reports_open: 2,
};

export const SAMPLE_PENDING = {
  count: 3,
  oldest: "2026-10-12T09:30:00+00:00",
  failed: 0,
  app_user_ids: SAMPLE_APP_USER_IDS,
};

/** Every mail the backend sends the owner, by preview name. */
export function sampleMails(): Record<string, OwnerMail> {
  const budget = parseBudget(SAMPLE_BUDGET)!;
  return {
    "pro-member": purchaseMail(
      { kind: "pro", productId: "app.glowlit.pro.yearly", environment: "Production", trial: true },
      SAMPLE_MEMBERS,
      SAMPLE_AT,
    ),
    "pro-member-sandbox": purchaseMail(
      { kind: "pro", productId: "app.glowlit.pro.monthly", environment: "Sandbox", trial: false },
      SAMPLE_MEMBERS,
      SAMPLE_AT,
    ),
    "credit-pack": purchaseMail(
      { kind: "pack", productId: "app.glowlit.credits.100", environment: "Production", credits: 100 },
      SAMPLE_MEMBERS,
      SAMPLE_AT,
    ),
    "ai-paused": billingPauseMail("xai", { ...budget, remainingCents: -12, spentCents: 1012 }, SAMPLE_AT),
    "balance-low": lowBalanceMail(budget, SAMPLE_AT),
    "digest": digestMail(
      SAMPLE_DAY,
      SAMPLE_MEMBERS,
      SAMPLE_DAILY,
      SAMPLE_AT,
      SAMPLE_BUDGET,
      SAMPLE_PENDING,
      undefined,
      SAMPLE_POLLS,
    ),
    "digest-quiet": digestMail(
      SAMPLE_DAY,
      SAMPLE_MEMBERS,
      { ...SAMPLE_DAILY, breakers: { ...SAMPLE_DAILY.breakers, free_jobs: 20 }, reports: { new: 0, open: 0 } },
      SAMPLE_AT,
      { ...SAMPLE_BUDGET, remaining_cents: 2_450, balance_cents: 3_000, spent_cents: 550 },
      { count: 0, oldest: null, app_user_ids: [] },
      { deleted: 2, failed: 0, waiting: false },
      { ...SAMPLE_POLLS, reports_open: 0 },
    ),
    "digest-unreadable": digestMail(SAMPLE_DAY, undefined, undefined, SAMPLE_AT),
  };
}
