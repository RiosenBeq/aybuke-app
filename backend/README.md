# Glowlit backend (Supabase + xAI)

The iOS app never talks to an AI provider directly and never ships provider
keys. This backend authenticates each (anonymous) user, verifies purchases with
Apple, meters credits in Postgres, moderates prompts and outputs, and forwards
an allow-listed set of operations to [xAI](https://docs.x.ai) (Grok Imagine),
or to [fal.ai](https://fal.ai) with `AI_PROVIDER=fal`. With `ANTHROPIC_API_KEY`
set, [Anthropic](https://platform.claude.com/docs)'s Claude checks each photo
before an edit and every result, independently of the image model.

```
iOS app ──► Supabase Auth (anonymous JWT; optional Sign in with Apple ID token)
   │
   ├─► POST   /functions/v1/ai-image            enqueue job  ──► xAI request in the background (or fal's queue)
   ├─► GET    /functions/v1/ai-image?job_id=…   poll job     ──► job status / results (+ output safety checks, delivery recorded)
   ├─► DELETE /functions/v1/ai-image?job_id=…   cancel job   ──► exact credit refund (&intent=cancel); on a delivered job, a plain DELETE is the "got it": results cleared
   ├─► GET    /functions/v1/ai-image            balance
   ├─► POST   /functions/v1/credits-redeem      credit pack  ──► Apple JWS verification → grant once
   ├─► POST   /functions/v1/report              "Report this image" (reason, job id) → public.reports
   ├─► POST   /functions/v1/account/link        after Sign in with Apple: merge the anonymous user in
   ├─► DELETE /functions/v1/account             revoke the Apple token, delete user and all data (cascades)
   ├─► POST   /functions/v1/ad-reward           single-use token before a rewarded ad (free, out of credits)
   ├─► GET    /functions/v1/ad-reward?token=…   has AdMob confirmed it? (+ "N left today")
   └─► DELETE /functions/v1/ad-reward?token=…   the ad closed early: the token's place comes back

AdMob ──► GET /functions/v1/ad-reward?…&signature=…&key_id=…   signed reward callback (SSV) → 1 credit, once
Apple ──► POST /functions/v1/app-store-notifications             signed V2 notification → refund/revoke Pro, take back a refunded pack
```

The wire contract is defined (and unit-tested) in
`ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift`, and for ads in
`ios/Packages/AppCore/Sources/AppCore/Ads.swift`.

## Why it's shaped like this

| Decision | Reason |
|---|---|
| **Async jobs + polling** | Edge Functions time out after ~150 s idle; generations take 5–40 s. The function answers in < 1 s and the app polls (1 s → 3 s back-off). xAI requests run in the background (`EdgeRuntime.waitUntil`); fal jobs sit on fal's durable queue. |
| **Operations, not endpoints** | The app sends `operation` + `template_id`; the server picks the model (`_shared/xai.ts`, `_shared/fal.ts`) and the prompt recipe (`_shared/catalog.json`). Models can be swapped without an app release, and nobody can use our keys for arbitrary models. |
| **Server-side credit ledger** | `reserve_credits` → job → `release_credits` on any failure, cancel, timeout or result the app never received (`cancel_job()`, `sweep_jobs()`). Exact per-bucket refunds, idempotent, append-only audit trail (`credit_ledger`). |
| **Apple-verified entitlements** | Pro status comes from a StoreKit 2 signed transaction verified with Apple's App Store Server Library, then bound to one user at a time. |
| **No input storage** | Photos are passed to the provider as data URIs and never written to our database or storage. xAI results come back as base64, are held on the job only until the app confirms the download (then cleared; `sweep_jobs()` clears any left after an hour). With xAI Zero Data Retention on, xAI deletes requests within an hour and never trains on them. fal outputs expire after 1 hour (`X-Fal-Object-Lifecycle-Preference`) and request I/O history is disabled (`X-Fal-Store-IO: 0`). The safety check sends the photo and each result to Anthropic's API for the length of the request; Anthropic deletes API inputs and outputs within 30 days (content its systems flag for a usage-policy violation up to 2 years) and doesn't train on them by default. |
| **Layered safety** | Prompt policy (client + server) → provider moderation (fal's strict `safety_tolerance`) → one output check on every result that fails closed (`_shared/moderation.ts`): xAI's own moderation verdict, or fal.ai's NSFW classifier when `FAL_KEY` is set (it stays unset); a flag, an error or a missing verdict blocks the result and refunds it, and there's no switch to turn it off → the independent check (`_shared/safety.ts`, with `ANTHROPIC_API_KEY`): Claude classifies the photo before an edit and every result into the same categories, on top of the output check, never instead; a flag, an error, a timeout, a refusal or an answer outside the schema blocks the job and refunds it (a flagged result is a strike, a flagged photo isn't) → in-app reporting. Documented for EU AI Act Art. 5(1)(ba) (from 2 Dec 2026). |
| **Ad credits only from Google's signature** | The app never grants an ad credit. It gets a random single-use token, AdMob sends it back in an ECDSA-signed callback, and `redeem_ad_reward` grants one credit per AdMob transaction id, at most 2 a day per user and per App Store download in SQL. The token, not the user id, is all AdMob sees of the account. |
| **Free credits per App Store download** | The free daily credits (and ad credits) belong to the App Store download, not the anonymous user: the app sends its StoreKit `AppTransaction` (JWS), `_shared/apple.ts` verifies Apple's signature, and SQL keys the allowance by a salted hash of `appTransactionId`, which stays the same across reinstalls and devices of one Apple Account. A new anonymous user on the same download shares the same daily credits. |
| **One admission step** | `admit_job()` checks blocks and cool-downs, the owner's pause switch and the hard breaker, per-user and per-IP rate limits, then the prompt policy (a blocked prompt is a strike and a free, failed attempt that still counts toward the limits), the free-retry allowance, the free breakers and the balance, then holds the credits and inserts the job, all in one transaction. |

## Models (late 2026 picks)

**xAI (default).** Every operation runs on `grok-imagine-image-2.0` at 1k: low quality for free users, medium for Pro (about $0.04 per created image and $0.05–0.07 per edit, input included). Enhance and Erase are edits with a fixed instruction (Erase sends the photo and the brush mask as two images). Background removal stays on the device. Override with `XAI_IMAGE_MODEL` / `XAI_EDIT_MODEL`; `grok-imagine-image` costs about $0.02 but ranks lower. In the [xAI console](https://console.x.ai), turn on **Zero Data Retention** for the team: selfies are personal data, and xAI's terms expect it.

**fal (`AI_PROVIDER=fal`).**

| Operation | fal endpoint | Notes |
|---|---|---|
| `text_to_image` | `fal-ai/nano-banana-2` | 1K for free users, 2K for Pro |
| `magic_edit`, `restyle` | `fal-ai/nano-banana-2/edit` | A/B identity-critical templates against `bytedance/seedream/v5/pro/edit` via `ENDPOINT_OVERRIDES` in `_shared/templates.ts` |
| `enhance` | `fal-ai/seedvr/upscale/image` | ×2 generative restoration |
| `remove_background` | `fal-ai/birefnet/v2` | Server fallback only — the app does this on-device for free |
| `erase_object` | `fal-ai/object-removal/mask` | White mask pixels are removed |

**Safety check (Anthropic, `ANTHROPIC_API_KEY`).** `claude-haiku-5-5` (override with `ANTHROPIC_SAFETY_MODEL`) through the official TypeScript SDK, pinned in `_shared/safety.ts`: thinking off, low effort, a strict JSON verdict, one retry, 20 s at most for a check, its retry included (an xAI job has 180 s, and the photo check, the image request and the result check must fit in about that). Haiku 5.5 costs $0.10 / $0.50 per million input / output tokens. An image costs ⌈width / 28⌉ × ⌈height / 28⌉ tokens: about 1,400 for a 1k result and up to about 3,000 for a 1,536 px photo, plus some 250 tokens of instructions and a 15-token answer, so roughly **$0.0002 per check** (an edit is two checks, the photo and its result; a creation one per image). Only JPEG, PNG and WebP of at most 10 MB as base64 are sent; anything else fails closed. Without `ANTHROPIC_API_KEY`, `XAI_SAFETY_MODEL` can name an xAI vision model for the same check instead (not tested against the live API). A model that refuses thinking turned off at low effort (Claude Opus 5.5, Sonnet 5.5) would fail every check, closed. Set a monthly spending limit in the Claude Console: an empty balance blocks every cloud job until it's topped up, and refunds each one.

Prices, latency and alternatives: [`docs/research/tech-and-compliance.md`](../docs/research/tech-and-compliance.md).
**Verify current prices on fal before launch** — several were unverified at research time.

## Setup

1. **Create a Supabase project** and install the [Supabase CLI](https://supabase.com/docs/guides/cli).
2. **Enable anonymous sign-ins**: Authentication → Sign In / Providers → Anonymous, limited to 15 sign-ins per hour per IP (Authentication → Rate Limits), with the Email provider turned off (`supabase/config.toml` keeps the same settings for local runs). Don't turn on CAPTCHA: the app has no CAPTCHA widget, so every anonymous sign-up would fail. Free credits don't depend on the anonymous user anyway (see "Free credits per App Store download").
   **Enable Sign in with Apple** (optional accounts): Authentication → Sign In / Providers → Apple, and add the bundle id `app.glowlit.ios` under Client IDs. In the Apple Developer account, turn on the Sign in with Apple capability for the app id and create a Sign in with Apple key for `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY`.
3. **Link and migrate**
   ```bash
   cd backend
   supabase link --project-ref <your-project-ref>
   supabase db push            # applies supabase/migrations
   ```
4. **Secrets** — copy `.env.example` to `.env`, fill it in, then:
   ```bash
   supabase secrets set --env-file .env
   ```
5. **Deploy functions**
   ```bash
   supabase functions deploy ai-image credits-redeem account report
   # AdMob's callback has no JWT: the function checks Google's signature (and the app's session) itself.
   supabase functions deploy ad-reward --no-verify-jwt
   # Apple's notifications have no JWT either: the function checks Apple's signature itself.
   supabase functions deploy app-store-notifications --no-verify-jwt
   ```
   Then send Apple's notifications to it. App Store Connect takes one URL per environment, and this app's Production and Sandbox URLs (App Store Connect › App Information › App Store Server Notifications, Version 2) already point at RevenueCat. Leave them there and, in RevenueCat › Apps › Glowlit (App Store), set **Apple Server Notification Forwarding URL** to `https://<project-ref>.supabase.co/functions/v1/app-store-notifications`: RevenueCat passes each signed notification on unchanged, so both receive it, and the function checks Apple's signature as usual. Without RevenueCat, set that URL as the Production and Sandbox URLs in App Store Connect instead.
6. **Schedule the sweepers** (`sweep_jobs` fails and refunds stuck jobs, refunds results the app never received, clears job outputs after 1 hour, deletes job rows after 30 days and reports after 12 months, App Store download hashes 30 days after last use (unless blocked), strikes and cool-downs after 30 days, IP counters after a day and usage counters after 90 days; `sweep_ad_rewards` deletes reward tokens a day after they expire and reward records after 30 days): enable the `pg_cron` extension, then run
   ```sql
   select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
   select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');
   -- App Store notification records: 30 days, as the privacy policy says
   select cron.schedule('sweep-app-store-notifications', '23 3 * * *', $$delete from private.app_store_notifications where received_at < now() - interval '30 days'$$);
   ```
   **And the RevenueCat deletion queue** (deletions wait in `public.pending_revenuecat_deletions` until `REVENUECAT_SECRET_KEY` is set; this retries them every hour). Enable `pg_net`, keep the project URL and the service role key in Vault once, then schedule the call:
   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
   select vault.create_secret('<service role key>', 'service_role_key');
   select cron.schedule('revenuecat-deletions', '17 * * * *', $$
     select net.http_post(
       url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
              || '/functions/v1/account/revenuecat-deletions',
       headers := jsonb_build_object('Authorization', 'Bearer ' ||
         (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'))
     )
   $$);
   ```
7. **Point the app at it** — in `ios/App/Resources/AppConfig.json` set `backendBaseURL` to `https://<project-ref>.supabase.co` and `supabaseAnonKey` to the project's publishable (anon) key. Both are public by design; access is enforced by JWTs, RLS and the functions themselves.

## Accounts (Sign in with Apple)

Everyone starts anonymous, so nobody has to sign up. Signing in is optional, and the app offers it only with `signInWithApple` set in `ios/App/Resources/AppConfig.json` (off in this version, until `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` are set so deletion can revoke the token). It's meant mainly for Pro members and credit-pack buyers, so their credits follow them to another device (Pro itself follows the Apple Account that bought it):

1. The app gets an identity token from Apple and signs in with Supabase's native Apple provider (`POST /auth/v1/token?grant_type=id_token`).
2. It then calls `POST /account/link` with the new session, the previous anonymous session and Apple's one-time authorization code. `merge_accounts()` moves purchased credits, the subscription, jobs and reports into the account (daily free credits never move), and the anonymous user is deleted. Running it twice is safe.
3. Apple's refresh token is kept in `public.apple_accounts` (service role only), so `DELETE /account` can revoke it, as Apple requires for account deletion.
4. `link` also records the merged anonymous id in `public.merged_users` (service role only). RevenueCat keeps a purchase made while anonymous on that anonymous customer, so `DELETE /account` deletes the RevenueCat customers for the account and every merged id (`REVENUECAT_SECRET_KEY`, plus `REVENUECAT_PROJECT_ID` for a v2 key). The ids are queued first in `public.pending_revenuecat_deletions` (service role only, no link to the deleted user) and the queue is worked through at every account deletion and by the hourly `POST /account/revenuecat-deletions` (step 6); a row goes as soon as RevenueCat deletes that customer or never had it. Without the key nothing is skipped: the deletions wait, with a warning in the logs, and go through once the key is set. RevenueCat then queues the deletion on its side.

The app creates the anonymous user only when it's first needed (a cloud AI job after consent, or a purchase), never at launch, and configures RevenueCat only for people who buy. Deleting the account never signs up first: without a stored session there is nothing on the server to delete.

Photos are not synced: the library stays on each iPhone.

## Reports

`POST /report` stores a user's "Report this image" in `public.reports` (reason, optional details, the user's own job id) with a limit of 10 reports a day per user (`reports_per_day`). Review open reports in the Supabase dashboard (`status = 'open'`) and set `status` to `reviewed`, `actioned` or `dismissed`. Reports are deleted after 12 months by `sweep_jobs()`, or with the account.

## Rewarded ads (AdMob server-side verification)

Free members 13+ who are out of credits can watch a rewarded ad for 1 credit, at most 2 a day (UTC). Pro never sees ads. The credit comes only from AdMob's signed callback, never from the app:

1. The app loads the ad, then calls `POST /ad-reward` (with her session and, like the balance call, `X-Entitlement-JWS`). `issue_ad_reward_token()` refuses Pro members (`not_eligible`), anyone with credits left (`has_credits`) and a third ad today (`daily_cap`; tokens still waiting for AdMob count), and otherwise returns a random token valid for 30 minutes.
2. The app sets the token as the ad's server-side verification **custom data** (never the user id) and shows the ad.
3. AdMob calls `GET /ad-reward?ad_network=…&ad_unit=…&custom_data=<token>&reward_amount=1&reward_item=credit&timestamp=…&transaction_id=…&signature=…&key_id=…`. `_shared/admob.ts` verifies the ECDSA (P-256, SHA-256, DER) signature over the query string up to `&signature=` with Google's keys from `https://www.gstatic.com/admob/reward/verifier-keys.json` (cached for at most 12 hours, fetched again for an unknown `key_id`), and the function checks `ad_unit` against `ADMOB_REWARDED_AD_UNIT`. `redeem_ad_reward()` then maps the token to the user and grants the credit through the ledger (kind `ad_reward`, `source_ref` `admob:<transaction_id>`), once per transaction and once per token, re-checking the daily cap under the wallet lock. Verified callbacks answer 200, granted or not (duplicates, other ad units, expired or unknown tokens grant nothing, and AdMob stops retrying); a bad signature answers 403, and unreachable keys or a missing `ADMOB_REWARDED_AD_UNIT` 503 (AdMob retries a few times).
4. The app polls `GET /ad-reward?token=…` until the status is `granted`, or calls `DELETE /ad-reward?token=…` when the ad closed before its reward.

Ad credits go into the daily bucket: spent first, refunded like any credit, gone at 00:00 UTC like the free daily credits. The cap and the credit per ad are in `ad_reward_policy()`.

**AdMob console** (Apps › Glowlit › Ad units): a **Rewarded** ad unit (`ca-app-pub-2292230772061554/1406702504`) with reward amount **1** and reward item **credit**; under *Server-side verification*, the callback URL `https://<project-ref>.supabase.co/functions/v1/ad-reward` (no query string; for this project `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward`), then **Verify URL** (the test callback carries no token, so it answers 200 and grants nothing). Set `ADMOB_REWARDED_AD_UNIT` to the same unit id; empty refuses every reward.

## Which AI key goes where

- **Production (this backend):** the provider keys live only in Edge Function secrets (`XAI_API_KEY`, or `FAL_KEY`, and `ANTHROPIC_API_KEY` for the safety check, in `.env`, then `supabase secrets set --env-file .env`; or paste them under Edge Functions → Secrets in the dashboard). They never ship in the app.
- **Trying a key before the backend exists:** put it in `ios/Config/Secrets.xcconfig` (git-ignored, DEBUG builds only), for example `GL_AI_PROVIDER = xai`. The app then calls xAI, fal.ai, OpenAI or Google Gemini directly. See the repository README, "Connect an AI provider".
- The backend runs jobs on xAI or fal.ai. OpenAI and Gemini work in the app's developer mode; add a backend adapter for them in `_shared/` before using them in production.

## Credit rules

Defined once in SQL (`public.credit_policy()`) and mirrored in the app (`CreditPolicy.standard`):

- Free: **2 credits per day**, refilled at 00:00 UTC, never accumulating.
- Pro: **80 credits per month**, unused credits roll over one month (cap 160). The free trial week gives **20 credits** instead (`trial_credits`).
- Credit packs: never expire (App Review Guideline 3.1.1).
- Rewarded ads (free members out of credits): **1 credit per ad, at most 2 a day** (`ad_reward_policy()`), added to the daily bucket.
- Likeness Lock: one free retry per result within 15 minutes, **3 a day** (`free_retries_daily`). A retry that was refunded (it failed, timed out or was cancelled) gives its daily slot back.
- Spending order: daily → subscription → purchased (expiring credits first).
- Any failure, cancellation, safety block or timeout is refunded exactly once, and so is a result that never reached the app. The poll that hands the results over records the delivery (`deliver_outputs()`); a finished job that was never handed over is refunded when its hour is up, or at once when the app cancels it, and one that was handed over but never confirmed (a download that broke) is refunded at most once a day per user and per App Store install, so skipping the confirmation can't keep both the images and the credit. Clients can't read job rows through the Data API: results reach the app only through `ai-image`, which records the delivery.

Change the numbers in `credit_policy()` (new migration) to retune pricing without an app update; update `CreditPolicy.standard` so the app's copy matches.

## Abuse runbook

Every cloud job goes through `admit_job()`, which applies the numbers in `public.credit_policy()`:

- **Strikes:** a prompt the policy blocks, or an output the moderation or the safety check flags, is a strike (not when she cancelled the job before its result came back). **3** strikes in **24 hours** start a **24-hour** cool-down (no cloud AI, nothing charged, no paywall). **3** cool-downs in **30 days** block the install until the owner lifts it. An install without a verified App Store transaction is kept to its network address instead: a salted hash of the address (`private.keyed_hash('ip', …)`), the same key the rate limit uses. The balance (`GET /ai-image`, `wallet_state()`) gets the same address, so it shows a cool-down or block on it too.
- **Rate limits:** per user, free **6 a minute, 30 an hour, 100 a day**; Pro **20, 60 and 200**. Per address, **120 requests an hour**. Reports: **10 a day** per user.
- **Breakers** (UTC day): free credits pause at **1,500** free jobs (`free_jobs_daily_cap`), the unverified allowance at **200** (`unverified_jobs_daily_cap`), and all AI at **8,000** jobs (`all_jobs_daily_cap`). Paid users keep working when only the free breaker trips.

Owner tools run in the SQL editor (the service role). Clients have no access to any of them.

1. **Read the day:** `select public.ops_daily_summary();` (or pass a date). It shows jobs and failures by code, the estimated provider cost, the breakers against their caps, strikes, cool-downs, blocks, open reports, and the top installs and addresses (hashed, shortened).
2. **Find the strikes:** `select * from public.ops_strikes(7);` lists each install key (or `user:<id>`) with its strikes, categories, cool-down and whether it is blocked. Check `user_ids` before you block an address: one address can serve many people (a school, a mobile carrier).
3. **Reports:** `select * from public.ops_reports('open');` lists the newest, with the operation and what the system knows about the sender. Mark each with `select public.ops_set_report_status('<report id>', 'reviewed' | 'actioned' | 'dismissed');`.
4. **Block:** `select public.ops_block(p_job => '<job id>', p_reason => '…');` blocks the install and the user behind a job. Name `p_install` or `p_user` instead when you have the key. Blocks stop cloud AI at once.
5. **Lift a block or cool-down:** `select public.ops_unblock(p_install => '<install key>');` or `p_user => '<user id>'`. It lifts the block and any running cool-down and clears the cool-down history for that install or user, so the next cool-down starts from none. It returns `blocks_lifted` and `cooldowns_lifted`. Lifting an address lifts every account on it.
6. **Pause and resume AI:** `select public.ops_pause_ai('all', 2, 'why');` stops every job for 2 hours (`'free'` stops only the free credits, and paid users keep working). A paused request is refused before the prompt check, so blocked prompts get no strike while paused. `select public.ops_resume_ai();` resumes everything (or `ops_resume_ai('all')`). A pause also ends by itself at `paused_until`.
7. **Retune the caps:** the rate limits, strikes, cool-downs, breakers and retention all live in `public.credit_policy()`. Change them in a new migration that replaces the function (copy it, change the numbers, keep the comment), then update `CreditPolicy.standard` in the app for the credit numbers. No app release is needed for the rest.
8. **Safety check failures:** many `photo_check_failed` or `safety_check_failed` jobs in `ops_daily_summary()` mean the independent check couldn't run (Anthropic balance or spending limit, a revoked key, an outage). Every one is refunded. The `ai-image` logs give the short reason (`HTTP 401 authentication_error`, `HTTP 400 invalid_request_error`, `timeout`, `deadline` for a check that hit its 20 s cap); never the key or the image. `refused` is different: Claude declined to look at that image, which points at the content, not an outage (Anthropic's vision API doesn't process explicit images). It stays a refunded failure, never a strike, because a false strike on a teen is worse than a refund. Each log line names the job: if refusals keep coming from one sender, look at those jobs before you block anything (`ops_block(p_job => …)`).
9. **Check the address after a deploy:** the address is the last `x-forwarded-for` entry (`_shared/input.ts`). Send a generation request from a known network with a made-up `X-Forwarded-For: 1.2.3.4` header, then in the SQL editor compare `select ip_key, requests from private.ip_usage where hour = date_trunc('hour', now());` with `select private.keyed_hash('ip', '<your address>');` (IPv4 as is; IPv6 as its /64, for example `2001:db8:0:0::/64`). Your address must match a row, and `private.keyed_hash('ip', '1.2.3.4')` must not.

**Never:**

- Edit a migration the project has applied (`supabase db push` has run it), or change one in `supabase/migrations` after it is published. Add a new file with a later timestamp instead; only comments may change in an old one.
- Grant `execute` on the `ops_*`, `admit_job`, `flag_job` or `private` functions to `anon` or `authenticated`, or put the service role key in the app or in a ticket.
- Store a prompt, a photo or a raw IP address in a table, or paste one into a report.

## Local checks

```bash
# Type-check, lint and format-check the Edge Functions (Deno 2)
cd backend/supabase/functions && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts report/index.ts ad-reward/index.ts app-store-notifications/index.ts && deno lint && deno fmt --check && deno test _shared/ ad-reward/ app-store-notifications/

# Run the migration + ledger tests on a throwaway PostgreSQL 14+
backend/scripts/test-db.sh
```

Both run in CI (`.github/workflows/ci.yml`).

## Before launch

- [ ] Set `APPLE_APP_ID` so production purchases verify (sandbox works without it).
- [ ] Ship the independent safety check: `ANTHROPIC_API_KEY` set (Anthropic listed in the consent sheet, `consentVersion` 2, and the privacy policies), then confirm the `ai-image` start-up log says `output check in force: xai + anthropic:claude-haiku-5-5` and run one edit and one creation against the live API (the unit tests mock it).
- [x] Add an App Store Server Notifications V2 endpoint to mark refunds/revocations (`entitlements.revoked`) immediately: `functions/app-store-notifications` (migration `20261025000000`). Left for the owner: deploy it and set its URL as RevenueCat's Apple Server Notification Forwarding URL (setup step 5; in App Store Connect only without RevenueCat).
- [ ] Add App Attest + DeviceCheck to stop free-credit farming across reinstalls (see research doc §3.4).
- [ ] Confirm fal accepts data-URI inputs for every endpoint above; otherwise upload to a private bucket and pass 10-minute signed URLs.
- [ ] Move polling to fal webhooks (Ed25519-signed) when traffic grows.
- [ ] Sign C2PA manifests server-side (`c2pa-rs`) in addition to the IPTC metadata the app writes.
