# Aybuke backend (Supabase + xAI)

The iOS app never talks to an AI provider directly and never ships provider
keys. This backend authenticates each (anonymous) user, verifies purchases with
Apple, meters credits in Postgres, moderates prompts and outputs, and forwards
an allow-listed set of operations to [xAI](https://docs.x.ai) (Grok Imagine),
or to [fal.ai](https://fal.ai) with `AI_PROVIDER=fal`. With `ANTHROPIC_API_KEY`
set, [Anthropic](https://platform.claude.com/docs)'s Claude checks each photo
before an edit and every result, independently of the image model, and works
as a text-only helper: it checks and rewrites each Magic Edit and Create
request before admission (the prompt polish) and writes prompt ideas, prompt
rewrites, caption ideas and makeup picks (`functions/assist`). It never gets
a photo for that. Text help can use a key of its own (`ANTHROPIC_ASSIST_API_KEY`,
from a Claude Console workspace with its own limits) and always stays under
global ceilings, so it can never take the capacity the safety checks need.

```
iOS app ──► Supabase Auth (anonymous JWT; optional Sign in with Apple ID token)
   │
   ├─► POST   /functions/v1/ai-image            enqueue job  ──► xAI request in the background (or fal's queue)
   ├─► GET    /functions/v1/ai-image?job_id=…   poll job     ──► job status / results (+ output safety checks, delivery recorded)
   ├─► DELETE /functions/v1/ai-image?job_id=…   cancel job   ──► exact credit refund (&intent=cancel); on a delivered job, a plain DELETE is the "got it": results cleared
   ├─► GET    /functions/v1/ai-image            balance
   ├─► POST   /functions/v1/credits-redeem      credit pack  ──► Apple JWS verification → grant once
   ├─► POST   /functions/v1/report              "Report this image" (reason, job id) → public.reports
   ├─► POST   /functions/v1/assist              writing help ──► Claude, text only → ideas, rewrites, captions, makeup picks
   ├─► POST   /functions/v1/account/link        after Sign in with Apple: merge the anonymous user in
   ├─► DELETE /functions/v1/account             revoke the Apple token, delete user and all data (cascades)
   ├─► POST   /functions/v1/ad-reward           single-use token before a rewarded ad (free: a credit, or a Pro try)
   ├─► GET    /functions/v1/ad-reward?token=…   has AdMob confirmed it? (+ "N left today")
   ├─► DELETE /functions/v1/ad-reward?token=…   the ad closed early: the token's place comes back
   ├─► POST   /functions/v1/polls               "Which vibe?" poll ──► pictures re-encoded → Claude checks both → private link
   ├─► GET    /functions/v1/polls/mine          her live polls with their counts
   └─► DELETE /functions/v1/polls?id=…          deletes a poll now

aybuke.org/p/<id> (anon key) ──► GET /functions/v1/polls?id=…, /polls/image?…, POST /polls/vote, /polls/report

AdMob ──► GET /functions/v1/ad-reward?…&signature=…&key_id=…   signed reward callback (SSV) → 1 credit or one Pro try, once
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
| **No input storage** | Photos are passed to the provider as data URIs and never written to our database or storage. xAI results come back as base64, are held on the job only until the app confirms the download (then cleared; `sweep_jobs()` clears any left after an hour). With xAI Zero Data Retention on, xAI deletes requests within an hour and never trains on them. fal outputs expire after 1 hour (`X-Fal-Object-Lifecycle-Preference`) and request I/O history is disabled (`X-Fal-Store-IO: 0`). The safety check sends the photo and each result to Anthropic's API for the length of the request, and the prompt polish and writing help send her words (text only); Anthropic deletes API inputs and outputs within 30 days (content its systems flag for a usage-policy violation up to 2 years) and doesn't train on them by default. Neither the polished text nor her words for writing help are stored. |
| **Layered safety** | Prompt policy (client + server) → Claude's prompt check before admission (the prompt polish, below; it never blocks for an outage) → provider moderation (fal's strict `safety_tolerance`) → one output check on every result that fails closed (`_shared/moderation.ts`): xAI's own moderation verdict, or fal.ai's NSFW classifier when `FAL_KEY` is set (it stays unset); a flag, an error or a missing verdict blocks the result and refunds it, and there's no switch to turn it off → the independent check (`_shared/safety.ts`, with `ANTHROPIC_API_KEY`): Claude classifies the photo before an edit and every result into the same categories, and results also for alcohol, tobacco, vaping, drugs and weapons (the age rating says the app shows none of them; her photo isn't checked for them), on top of the output check, never instead; a flag, an error, a timeout, a refusal or an answer outside the schema blocks the job and refunds it (a flagged result is a strike, a flagged photo isn't, nor is a result of her photo flagged only for substances or weapons); result checks that can't run trip a circuit breaker that pauses AI for a few minutes → in-app reporting. Documented for EU AI Act Art. 5(1)(ba) (from 2 Dec 2026). |
| **Ad rewards only from Google's signature** | The app never grants an ad reward. It gets a random single-use token, AdMob sends it back in an ECDSA-signed callback, and `redeem_ad_reward` grants what the token was issued for, once per AdMob transaction id: one credit (at most 2 a day) or one try of a Pro look or style (at most 1 a day), per user and per App Store download in SQL. The token, not the user id, is all AdMob sees of the account. |
| **Free credits per App Store download** | The free daily credits (and ad credits) belong to the App Store download, not the anonymous user: the app sends its StoreKit `AppTransaction` (JWS), `_shared/apple.ts` verifies Apple's signature, and SQL keys the allowance by a salted hash of `appTransactionId`, which stays the same across reinstalls and devices of one Apple Account. A new anonymous user on the same download shares the same daily credits. |
| **One admission step** | Before it, the prompt polish asks Claude about a Magic Edit's or a creation's words once (below). `admit_job()` checks blocks and cool-downs, the owner's pause switch and the hard breaker, per-user and per-IP rate limits, then the prompt policy (a blocked prompt is a strike and a free, failed attempt that still counts toward the limits), the free-retry allowance, the free breakers and the balance, then holds the credits and inserts the job, all in one transaction. A free member's job with a Pro look or style goes through `admit_unlocked_job()`, which wraps it in the same transaction and spends her Pro try (see "Rewarded unlock"). |

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

**Safety check (Anthropic, `ANTHROPIC_API_KEY`).** `claude-haiku-5-5` (override with `ANTHROPIC_SAFETY_MODEL`) through the official TypeScript SDK, pinned in `_shared/safety.ts`: thinking off, low effort, a strict JSON verdict, one retry, 20 s at most for a check, its retry included. Supabase's Free plan stops a function 150 s after the request arrived, background work included, so an xAI job's work ends by 140 s: the photo check, then the image request (at most 110 s, less after a slow photo check: `requestTimeout()` in `_shared/xai.ts`), then 20 s for the result check, leaving 10 s to store the result or fail and refund it. The app waits 180 s. Haiku 5.5 costs $0.10 / $0.50 per million input / output tokens. An image costs ⌈width / 28⌉ × ⌈height / 28⌉ tokens: about 1,400 for a 1k result and up to about 3,000 for a 1,536 px photo, plus some 250 tokens of instructions and a 15-token answer, so roughly **$0.0002 per check** (an edit is two checks, the photo and its result; a creation one per image). Only JPEG, PNG and WebP of at most 10 MB as base64 are sent; anything else fails closed. Without `ANTHROPIC_API_KEY`, `XAI_SAFETY_MODEL` can name an xAI vision model for the same check instead (not tested against the live API). A model that refuses thinking turned off at low effort (Claude Opus 5.5, Sonnet 5.5) would fail every check, closed. Set a monthly spending limit in the Claude Console: an empty balance blocks every cloud job until it's topped up, and refunds each one.

**Prompt polish (`ai-image`, `ANTHROPIC_ASSIST_API_KEY` or `ANTHROPIC_API_KEY`).** A Magic Edit's or a creation's words, after the keyword policy allowed them and before `admit_job()`, go to Claude once (`ai-image/polish.ts`, through `_shared/claude-text.ts`: `claude-haiku-5-5` or `ANTHROPIC_ASSIST_MODEL`, the safety check's client setup, thinking off at low effort, a strict JSON answer, 6 s with its one retry), but only for a job `admit_job()` could take right now: `job_admissible()` (migration `20261103000000`, read-only: it writes nothing, not even the install) answers first whether she's blocked or resting, AI is paused, a breaker or rate limit stands, and whether a credit, a free daily credit or a free retry pays for it; when it says no, Claude isn't asked and nothing is counted. Text only: her words without the guards the app adds, never the photo. Claude classifies the request (the keyword policy's categories plus hate, self-harm, graphic violence, substances and weapons, which the result check would otherwise block after xAI billed the image) and writes it as one clear English instruction of at most 600 characters that keeps her face, identity, skin tone, body and age. A refusal answers `content_blocked` like a keyword block: in a category the keyword policy applies to that operation (sexual, sexualMinor and revealingClothing always; humiliation and appearanceChange for edits) it goes to `admit_job()` as the blocked category, so it's a strike exactly as a keyword block; any other category is refused before admission, without a strike or a charge. An allowed request goes on as Claude's instruction, with "Only edit me" and the edit guard put back after it; the polished text must pass the keyword policy too. Polish never blocks a job by failing: when `job_admissible()` says no, over a limit or a ceiling of `admit_assist(…, 'polish')` (shared with writing help, see "Assist"), while AI is paused, a result check failed in the last 5 minutes or she's resting, on an error, a timeout, a refusal or an answer outside the schema, the job goes on with her own words, and the keyword policy, the edit guard and the fail-closed photo and result checks still apply. Templates (`restyle`) keep their catalog prompts and makeup requests (they end with `MakeupStudio.skinGuard`) aren't polished. `PROMPT_POLISH=off` turns it off; the start-up log says `prompt polish: anthropic:claude-haiku-5-5 (ANTHROPIC_ASSIST_API_KEY)` (or `ANTHROPIC_API_KEY`, the key's secret, never the key) or `off`, and each job logs `prompt polish (magic_edit): polished in 900 ms`, `blocked weapons`, `skipped: not admissible` or `skipped: timeout`, never the text. About $0.0002 a request (some 700 input and 150 output tokens).

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
   supabase functions deploy ai-image credits-redeem account report assist   # JWT verification on
   # AdMob's callback has no JWT: the function checks Google's signature (and the app's session) itself.
   supabase functions deploy ad-reward --no-verify-jwt
   # Apple's notifications have no JWT either: the function checks Apple's signature itself.
   supabase functions deploy app-store-notifications --no-verify-jwt
   # The owner's daily digest: JWT check on, plus its own secret (see "Owner alerts").
   supabase functions deploy owner-digest
   # "Which vibe?" polls: JWT check on (the poll page sends the anon key; see "Polls").
   supabase functions deploy polls
   ```
   Then send Apple's notifications to it. App Store Connect takes one URL per environment, and this app's Production and Sandbox URLs (App Store Connect › App Information › App Store Server Notifications, Version 2) already point at RevenueCat. Leave them there and, in RevenueCat › Apps › Aybuke (App Store), set **Apple Server Notification Forwarding URL** to `https://<project-ref>.supabase.co/functions/v1/app-store-notifications`: RevenueCat passes each signed notification on unchanged, so both receive it, and the function checks Apple's signature as usual. Without RevenueCat, set that URL as the Production and Sandbox URLs in App Store Connect instead.
6. **Schedule the sweepers** (`sweep_jobs` fails and refunds stuck jobs, refunds results the app never received, clears job outputs after 1 hour, deletes job rows after 30 days and reports after 12 months, App Store download hashes 30 days after last use (unless blocked), strikes and cool-downs after 30 days, IP counters and the writing-help counts (`private.assist_usage`, `private.assist_ceilings`) after a day and usage counters after 90 days, and polls (pictures, question, votes) once their 24 hours are up, poll report records after 30 days, poll counters after 2 days and per-address picture loads after a day (daily poll numbers after 90); `sweep_ad_rewards` deletes reward tokens a day after they expire, reward records after 30 days and Pro tries (`private.ad_unlocks`) a day after they end; `sweep_app_store_notifications` deletes App Store notification records after 30 days and refund records in `private.refunded_transactions` as section 14 of the privacy policy says: a refunded subscription period 30 days after the later of the refund and the period's end, a reversed refund 30 days after the reversal, a refunded credit pack never): enable the `pg_cron` extension, then run
   ```sql
   select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
   select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');
   -- Notification and refund records, as the privacy policy says (migration 20261030000000 sets this when pg_cron is on)
   select cron.schedule('sweep-app-store-notifications', '23 3 * * *', 'select public.sweep_app_store_notifications()');
   ```
   **And the RevenueCat deletion queue** (deletions wait in `public.pending_revenuecat_deletions` until `REVENUECAT_SECRET_KEY` is set; this retries them every hour). With the key set and `pg_net` off (as here), the daily digest works through the queue instead (at most 20 a day, 30 s); without the key, it lists them for deletion by hand (Accounts, item 4). To retry hourly, enable `pg_net`, keep the project URL and the service role key in Vault once, then schedule the call:
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

Everyone starts anonymous, so nobody has to sign up. Signing in is optional, and the app offers it only with `signInWithApple` set in `ios/App/Resources/AppConfig.json` (on since 1.0; it needs `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` so deletion can revoke the token). It's meant mainly for Pro members and credit-pack buyers, so their credits follow them to another device (Pro itself follows the Apple Account that bought it):

1. The app gets an identity token from Apple and signs in with Supabase's native Apple provider (`POST /auth/v1/token?grant_type=id_token`).
2. It then calls `POST /account/link` with the new session, the previous anonymous session and Apple's one-time authorization code. `merge_accounts()` moves purchased credits, the subscription, jobs and reports into the account (daily free credits never move), and the anonymous user is deleted. Running it twice is safe.
3. The code is exchanged first (it lasts five minutes and works once) and Apple's refresh token is kept in `public.apple_accounts` (service role only, no grants to `anon` or `authenticated`), so `DELETE /account` can revoke it, as Apple requires for account deletion. A refused code is logged with Apple's error code (`invalid_grant`…) and the reply's `token_stored` says whether a token is kept. For a Sign in with Apple account without one, `DELETE /account` answers 409 `apple_reauth_required` and deletes nothing; the app asks Apple for a fresh code and sends it as `authorization_code` (or `skip_apple_revoke` when Apple can't answer, logged).
4. `link` also records the merged anonymous id in `public.merged_users` (service role only). RevenueCat keeps a purchase made while anonymous on that anonymous customer, so `DELETE /account` deletes the RevenueCat customers for the account and every merged id (`REVENUECAT_SECRET_KEY`, plus `REVENUECAT_PROJECT_ID` for a v2 key). The ids are queued first in `public.pending_revenuecat_deletions` (service role only, no link to the deleted user) and the queue is worked through at every account deletion and by the hourly `POST /account/revenuecat-deletions` (step 6); a row goes as soon as RevenueCat deletes that customer or never had it. Without the key nothing is skipped: the deletions wait, with a warning in the logs, and go through once the key is set. RevenueCat then queues the deletion on its side. Until then the daily digest lists the waiting App User IDs (see "Owner alerts"): delete each customer in the RevenueCat dashboard (Project Aybuke › Customers), then run the line the digest gives, `select public.ops_mark_revenuecat_deleted(array['<App User ID>', …]);` (service role; `select public.ops_revenuecat_pending();` shows the queue).

The app creates the anonymous user only when it's first needed (a cloud AI job after consent, or a purchase), never at launch, and configures RevenueCat only for people who buy. Deleting the account never signs up first: without a stored session there is nothing on the server to delete.

Photos are not synced: the library stays on each iPhone.

## Owner alerts

Mails to the owner, sent with [Resend](https://resend.com) (`_shared/owner-mail.ts`): counts, plans and times only, never a user id, email, token, transaction id or prompt. The one exception is the daily digest's list of RevenueCat App User IDs of accounts already deleted (random ids), so the owner can delete those customers as the privacy policy promises.

- **New Pro member:** the first time the backend stores a subscription (`resolveEntitlement` in `_shared/apple.ts`, an `original_transaction_id` it had never seen), and **Credit pack sold** the first time `credits-redeem` grants a transaction. Plan, Production or Sandbox (a sandbox purchase is marked `[TEST]`), the time in UTC and Istanbul, and the totals from `ops_members_summary()`. The mail goes out after the database work, in the background (`EdgeRuntime.waitUntil`), so it never delays or fails a purchase; a renewal, a restore or a subscription moving to another account sends nothing. Two requests racing on the very first purchase can rarely mail twice.
- **xAI balance about $2 left:** the server can't read xAI's balance, so it estimates it (migration `20261028000000`): the owner records the balance after each top-up with `select public.ops_set_provider_balance('xai', <cents>);` (seeded with 1000, about $10 on 15 October 2026), `select public.ops_provider_budget();` subtracts the `est_cost_cents` of every billed job since then (`ops_daily_summary()`'s filter), and after each billed job `ai-image` mails once when $2 or less is left (`_shared/provider-alerts.ts`) until a new balance is recorded. Jobs are kept 30 days, so record the balance at least monthly.
- **Daily digest:** `functions/owner-digest` mails yesterday's `ops_daily_summary()` (jobs, failures, cost, breakers, strikes, reports) with `ops_members_summary()`, the xAI balance estimate (`ops_provider_budget()`) and the RevenueCat customers of deleted accounts still waiting (`ops_revenuecat_pending()`, migration `20261029000002`): the count, the oldest date, up to 20 App User IDs, what to do and the `ops_mark_revenuecat_deleted(...)` line for them. With `REVENUECAT_SECRET_KEY` set it first deletes up to 20 itself (30 s at most) and shows how many went. The GitHub workflow `.github/workflows/owner-digest.yml` calls it at 06:00 UTC (pg_net is off here), and it can be run by hand under Actions › Owner digest › Run workflow. The anon key passes the JWT check; the `x-digest-secret` header must equal `DIGEST_SECRET` (compared in constant time). Without `DIGEST_SECRET` every call gets a 503.

Secrets (without `RESEND_API_KEY` every alert is skipped with one log line, never an error):

```bash
cd backend
read -s RESEND_API_KEY && supabase secrets set RESEND_API_KEY="$RESEND_API_KEY" && unset RESEND_API_KEY
read -s DIGEST_SECRET && supabase secrets set DIGEST_SECRET="$DIGEST_SECRET" && unset DIGEST_SECRET   # e.g. from: openssl rand -hex 32
supabase secrets set OWNER_ALERT_TO=hello@buaze.com                    # optional; comma-separated for more
supabase secrets set OWNER_ALERT_FROM='Aybuke <alerts@buaze.com>'      # optional; only after buaze.com is verified
```

Then add the same `DIGEST_SECRET` as a repository secret on GitHub (Settings › Secrets and variables › Actions, or `gh secret set DIGEST_SECRET`). Resend's default sender `onboarding@resend.dev` only delivers to the address of the Resend account itself; to send to another address or from your own, verify `buaze.com` under Resend › Domains and set `OWNER_ALERT_FROM`.

## Reports

`POST /report` stores a user's "Report this image" in `public.reports` (reason, optional details, the user's own job id) with a limit of 10 reports a day per user (`reports_per_day`). Review open reports in the Supabase dashboard (`status = 'open'`) and set `status` to `reviewed`, `actioned` or `dismissed`. Reports are deleted after 12 months by `sweep_jobs()`, or with the account.

Reports from a poll page are separate: see "Polls" (`ops_poll_reports()`).

## Rewarded ads (AdMob server-side verification)

Free members 13+ who are out of credits can watch a rewarded ad for 1 credit, at most 2 a day (UTC); with a credit to spend, they can watch one for a one-time try of a Pro look or style instead, 1 a day ("Rewarded unlock", below). Pro never sees ads. The credit comes only from AdMob's signed callback, never from the app:

1. The app loads the ad, then calls `POST /ad-reward` (with her session and, like the balance call, `X-Entitlement-JWS`). `issue_ad_reward_token()` refuses Pro members (`not_eligible`), anyone with credits left (`has_credits`) and a third ad today (`daily_cap`; tokens still waiting for AdMob count), and otherwise returns a random token valid for 30 minutes.
2. The app sets the token as the ad's server-side verification **custom data** (never the user id) and shows the ad.
3. AdMob calls `GET /ad-reward?ad_network=…&ad_unit=…&custom_data=<token>&reward_amount=1&reward_item=credit&timestamp=…&transaction_id=…&signature=…&key_id=…`. `_shared/admob.ts` verifies the ECDSA (P-256, SHA-256, DER) signature over the query string up to `&signature=` with Google's keys from `https://www.gstatic.com/admob/reward/verifier-keys.json` (cached for at most 12 hours, fetched again for an unknown `key_id`), and the function checks `ad_unit` against `ADMOB_REWARDED_AD_UNIT`. `redeem_ad_reward()` then maps the token to the user and grants the credit through the ledger (kind `ad_reward`, `source_ref` `admob:<transaction_id>`), once per transaction and once per token, re-checking the daily cap under the wallet lock. Verified callbacks answer 200, granted or not (duplicates, other ad units, expired or unknown tokens grant nothing, and AdMob stops retrying); a bad signature answers 403, and unreachable keys or a missing `ADMOB_REWARDED_AD_UNIT` 503 (AdMob retries a few times).
4. The app polls `GET /ad-reward?token=…` until the status is `granted`, or calls `DELETE /ad-reward?token=…` when the ad closed before its reward.

Ad credits go into the daily bucket: spent first, refunded like any credit, gone at 00:00 UTC like the free daily credits. The cap and the credit per ad are in `ad_reward_policy()`.

**AdMob console** (Apps › Glowlit › Ad units): a **Rewarded** ad unit (`ca-app-pub-2292230772061554/1406702504`) with reward amount **1** and reward item **credit**; under *Server-side verification*, the callback URL `https://<project-ref>.supabase.co/functions/v1/ad-reward` (no query string; for this project `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward`), then **Verify URL** (the test callback carries no token, so it answers 200 and grants nothing). Set `ADMOB_REWARDED_AD_UNIT` to the same unit id; empty refuses every reward.

### Rewarded unlock (a one-time try of a Pro look or style)

Instead of a credit, a free member (13+, iPhone and iPad, not Pro) can watch a rewarded ad to try **one** Pro-only look (a `restyle` template) or Pro Create style **once**. Same ad unit, same server-side verification, same rule: only AdMob's signed callback grants it, never the app. Migration `20261101000000`; the numbers are in `ad_reward_policy()` (`unlock_daily_cap` 1, `unlock_ttl` 30 minutes). Shared code: `_shared/unlocks.ts`.

**Contract** (the app's side goes in `ios/Packages/AppCore/Sources/AppCore/Ads.swift`; errors are the usual `{ "error": { "code", "message", … } }`):

1. **Token.** `POST /ad-reward` with the credit ad's headers (session, `X-Entitlement-JWS`, `X-App-Transaction`) and the body `{ "kind": "unlock", "template_id": "<Pro look id>" }` or `{ "kind": "unlock", "style_id": "<Pro style id>" }`. No body, `{}` or `{ "kind": "credit" }` is the +1 credit ad, unchanged (every credit answer now also says `"kind": "credit"`).
   → `201 { "token", "kind": "unlock", "template_id" | "style_id", "expires_at", "remaining_today", "daily_cap" }`. `token` goes to AdMob as the SSV custom data, exactly as for a credit; `expires_at` is the token's (30 minutes to show the ad); `remaining_today` and `daily_cap` count tries, not credit ads.
   Refusals: 400 `not_unlockable` (a free look, an unknown id, one kind's id as the other) or `bad_request` (not exactly one id, bad JSON, an unknown `kind`); 403 `not_eligible` (Pro, no verified App Store install, a block or a cool-down); 409 `no_credits` with `credits_remaining: 0` (the try's job costs a credit, so there's no ad without one: offer the credit ad first); 409 `daily_cap` (today's try is used, per account and per App Store install); 503 `ai_paused` (AI is paused for everyone or the day's hard breaker tripped, so the try couldn't start a job).
2. **Grant.** The app shows the ad. AdMob calls `GET /ad-reward?…&custom_data=<token>&…&signature=…&key_id=…`; after the signature and ad unit checks, `redeem_ad_reward()` pays by the token's kind: for a try it records one unused try of that id for her (`private.ad_unlocks`), valid for 30 minutes from the callback, and adds no credit. The cap is checked again under the lock (a second try for the install that day is `capped`); duplicates, used, expired and unknown tokens grant nothing.
3. **Poll.** `GET /ad-reward?token=…` → `{ "token", "kind": "unlock", "status", "template_id" | "style_id", "remaining_today", "daily_cap", "credits_remaining" }`, plus `"expires_at"` (when the try can no longer start a job) once `status` is `granted`. Statuses as for a credit: `pending`, `granted`, `capped`, `expired`, `unknown`. `DELETE /ad-reward?token=…` (the ad closed before its reward) → `{ "released", "kind", "remaining_today", "daily_cap" }`, and the try's place comes back. `GET /ad-reward` adds `"unlock": { "remaining_today", "daily_cap", "eligible", "active": [{ "template_id" | "style_id", "expires_at" }] }` to today's credit ads: `eligible` means a free member with a verified install, at least one credit, under today's cap and AI not paused; `active` lists her unused, live tries (after a relaunch, say).
4. **Use.** `POST /ai-image` exactly as a Pro member would send it (`"operation": "restyle"` with `template_id`, or a creation with `style_id`); nothing else changes. For a non-Pro member with a Pro look or style, ai-image asks `ad_unlock_available()` first: without a try of exactly that id it answers 402 `pro_required` as before (nothing booked, no prompt check, no Claude call). With one, `admit_unlocked_job()` runs `admit_job()` with every gate (blocks, cool-downs, pauses, rate limits, the prompt policy and its strikes, the credit) and spends the try on the job it admits, in the same transaction; a refusal spends nothing. The job costs 1 credit like any look, at the free tier's quality. If the try ended or was spent in between, admission answers 402 `pro_required` too.
5. **Retry and refunds.** The Likeness Lock retry (`retry_of`) of a job a try paid for needs no new try. A job refunded for any reason (`release_credits()`: a failure, a safety block, a timeout, a cancel, a result never delivered) gives the try back for what is left of its 30 minutes. One try covers one look or style; several images at once stays Pro-only.

**Caps and records:** 1 try a day (UTC) per user and per App Store install, counted apart from the 2 credit ads (`ad_rewards_used_today(…, 'unlock')`; tokens waiting for AdMob count). `ad_reward_tokens.kind` and `ad_rewards.kind` tell the two kinds apart (a try's reward row has 0 credits), so the owner's summaries count both as rewarded ads granted while `ops_members_summary()`'s `credits` stays the credits. `private.ad_unlocks` (service role only, RLS on) keeps the user, the look or style, the AdMob transaction, the times and the job that spent the try; `sweep_ad_rewards()` deletes it a day after the try ends, and deleting the account deletes it at once.

**AdMob policy** (Google's "Policies for ad units that offer rewards", AdMob Help, read 16 October 2026, paraphrased). Rewards must be non-monetary, usable only inside the publisher's own app and not transferable; Google's examples include free trials and in-game items, and cash, gift cards, crypto or anything transferable are prohibited. A one-time try of a Pro look is an in-app feature reward of that kind, like a credit. The page also sets what the app must keep doing: say what the ad gives before each ad (for example "Watch a short ad to try Doll Box once"), show a rewarded ad only after she chooses to watch it, let her skip or close it, keep the app working when she says no (free looks and her credits stay), give the promised reward once the ad played to the end (the server does, and a refunded job gives it back), never push her with misleading wording, and never suggest that Google grants or vouches for the reward. The ad unit's own reward setting (1 `credit`) is only what AdMob signs and reports; the server pays by the token's kind, so the one unit serves both rewards. A second rewarded unit can be added to `ADMOB_REWARDED_AD_UNIT` (comma-separated) for separate reporting without a code change.

**Deploy** the migration first: the deployed 1.0 functions keep working on the new database (every function and answer they use keeps its arguments and fields), while the new ones need it.

```bash
cd backend
psql "$SUPABASE_DB_URL" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261101000000_rewarded_unlocks.sql   # live since 16 Oct 2026
supabase functions deploy ai-image                # JWT verification on, as before
supabase functions deploy ad-reward --no-verify-jwt
```

## Assist (Claude text helper)

`functions/assist` (deployed with JWT verification; it also requires a user session through `_shared/auth.ts`) is the app's writing help: Claude, text only, never a photo, at no credit cost. The app's side of the contract is `ios/Packages/AppCore/Sources/AppCore/Assist.swift`. Headers: her session and, from 1.1, `X-App-Transaction` (StoreKit's signed AppTransaction, verified exactly as `ai-image` verifies it, `_shared/apple.ts`); without it, or when Apple's signature doesn't check out (DEBUG and Simulator builds), she counts as unverified.

```
POST /functions/v1/assist
{ "task": "inspire" | "magic" | "captions" | "makeup",
  "text": "…",            her words, at most 400 characters (grapheme clusters); optional for inspire only
  "locale": "tr",          en, tr, es, pt-BR, fr, de, it, ru, ja, ko, zh-Hans, id (any case; "pt"/"zh-…" map)
  "context": { "style": "…", "format": "story", "look": "softGlam" } }   optional, each at most 100 characters

inspire  → 200 { "suggestions": [ …up to 4 ideas for a new picture, ≤ 120 characters, today's date in mind ] }
magic    → 200 { "suggestions": [ …1–2 richer rewrites of her Create prompt, ≤ 300 characters ] }
captions → 200 { "suggestions": [ …up to 4 captions about the vibe, never her looks, ≤ 120 characters,
                                   1–3 hashtags; context.format: story, cover, strip, beforeAfter, pick, … ] }
makeup   → 200 { "makeup": { "look", "lips", "eyes", "cheeks", "extras": [], "hair", "intensity" }, "note": "…" }
```

- **Makeup ids** come only from catalog.json's `makeup` (looks, lips, eyes, cheeks, extras, hair colors and intensities, exported from `MakeupStudio.swift` by `scripts/export-catalog.sh`; run it after changing the catalog). The JSON schema holds Claude to them, and the server drops any other id. Every field is the final pick: a look comes with its whole recipe, with any part Claude chose on top and its extras added to the look's; `null` means as is. `note` is one line in her language, or `""` when it failed the checks (the picks stay).
- **Safety:** her words (raw and cleaned up) and each context value pass the prompt policy first, with Create's rules for `inspire` and `magic` and a photo's for `captions` and `makeup`: a block is 422 `content_blocked` with its `category`, before anything is counted, and never a strike. The system prompt keeps everything teen-safe (nothing sexual or revealing, no reshaping, skin lightening, weight talk or rating looks, no hate, self-harm, violence, weapons or substances, no real people or brands) and treats her words as material, never instructions. Every line Claude writes passes the same policy again, is at most the length above and appears once; the rest are dropped.
- **Limits** (`admit_assist()` and its numbers in `assist_policy()`, migrations `20261031000000` and `20261103000000`), checked in this order, writing help and the polish alike:
  1. AI paused for everyone (`ops_pause_ai('all', …)`, the provider billing pause, the safety breaker), or **a result safety check failed in the last 5 minutes** (`private.safety_breaker.last_error_at`, set by `note_safety_check_error()`): 503 `assist_unavailable` until then. Claude's capacity goes to the safety checks first.
  2. A block or cool-down of her account, or of her verified install (her address without one, as `admit_job()` keys them): 503 `assist_unavailable`.
  3. **60 an hour per user**, **60 an hour per verified App Store install** (across its accounts) and **200 an hour per address**, per kind and UTC hour → 429 `rate_limited` with `retry_after`. A refused request still counts here.
  4. Ceilings, counting only what they admit: callers **without a verified install share 30 an hour**, both kinds together; then **everyone: 20 a minute, 200 an hour and 1,000 a UTC day**, writing help and the polish together → 503 `assist_unavailable` with `retry_after` until that minute, hour or day ends. 20 a minute leaves at least 98% of Claude Haiku 5.5's 1,000 requests a minute (the Start tier on Anthropic's rate-limits page, October 2026) to the safety checks, and 60% of a 50-a-minute limit; 1,000 a day is about $0.30 of Claude at most, so a flood can't eat the monthly spend limit the checks share.
  The counts are salted hashes or plain totals (the address hash is `ip_usage`'s key, the install hash `app_installs`'): `private.assist_usage` per user, install and address, `private.assist_ceilings` for the ceilings, both deleted after a day by `sweep_jobs()`. Today's numbers: `select kind, sum(requests) from private.assist_usage where hour > now() - interval '1 day' group by kind;` and `select scope, period, requests from private.assist_ceilings order by period desc limit 10;`. Retune them in a new migration that replaces `assist_policy()`.
- **Fallbacks:** 503 `assist_unavailable` when no Anthropic key is set, AI is paused, a result check just failed, she or her install is blocked or in a cool-down, a ceiling is reached, Claude errors, refuses or takes over 8 s (its one retry included), or nothing it wrote passes the checks. The app then uses Apple's on-device writer or its own lists. 400 `bad_request` for a body outside the contract (16 KB at most).
- **Model, key and cost:** `claude-haiku-5-5` (`ANTHROPIC_ASSIST_MODEL` to change it; it must take thinking turned off at low effort), through `_shared/claude-text.ts` with the safety check's client setup: a strict JSON schema, 400–900 output tokens at most. Text help (writing help and the polish) uses **`ANTHROPIC_ASSIST_API_KEY` when it's set**, else `ANTHROPIC_API_KEY`; the safety checks (photos, results, poll pictures) always use `ANTHROPIC_API_KEY`. The start-up logs say which (`assist: anthropic:claude-haiku-5-5 (ANTHROPIC_ASSIST_API_KEY)`). About **$0.0003 a call** (some 600–1,000 input tokens with the rules and, for makeup, the catalog, and 100–400 output tokens at $0.10 / $0.50 per million).
- **Its own workspace (owner, recommended):** in the Claude Console, create a workspace for writing help (Settings › Workspaces), give it a monthly spend limit and lower rate limits (for example 50 requests a minute; workspace limits can't go above the organization's, and the default workspace can't have its own), create an API key in it, and set it as `ANTHROPIC_ASSIST_API_KEY` (`supabase secrets set ANTHROPIC_ASSIST_API_KEY=…`; the functions read it on every request, and the start-up log lines of `assist` and `ai-image` name the secret in use). The safety checks keep `ANTHROPIC_API_KEY` in the other workspace, so writing help reaching its limits can't stop them. The organization's prepaid balance is still shared: keep it topped up.
- **Privacy:** nothing is stored; the logs carry the task, the language, the outcome, counts and the time taken (`{"fn":"assist","task":"magic","outcome":"ok","ms":850,"kept":2,…}`), never her words or Claude's. Anthropic keeps API inputs and outputs up to 30 days (flagged content up to 2 years), as the privacy policies say.

## Polls ("Which vibe?" with friends)

She shares two of her own pictures (A and B) and an optional question as a private link; friends open `https://aybuke.org/p/<poll_id>` in any browser and tap A or B; she sees the counts in the app. Link-only by design: no feed, no listing, no profiles, no comments, no names, `noindex` on the page. A poll lives **24 hours**, then the link answers 404 and `sweep_jobs()` deletes it (pictures, question, votes) within 5 minutes; she can delete it sooner, and deleting her account deletes her polls at once (`on delete cascade`). Polls aren't offered under 13 (the app's gate: the server can't know her age, so it requires a session and relies on the app). `functions/polls`, migration `20261102000000_polls.sql`; the page lives in the website repo (`RiosenBeq/aybuke`, `src/pages/p.html`, `public/assets/js/poll.js`).

**Auth.** JWT verification stays on at the gateway (`supabase functions deploy polls`, no flag). The app sends her session; the page sends the public anon key (`supabaseAnonKey` in `ios/App/Resources/AppConfig.json`) as `Authorization: Bearer` and `apikey`. Routes that need her (`POST /polls`, `GET /polls/mine`, `DELETE /polls`) check the session with `requireUser`; a poll's picture URLs are signed by the function (HMAC-SHA256 keyed by the service role key, so nobody else can make or stretch one).

**Contract** (the app's side is coded against this; errors are the usual `{ "error": { "code", "message", … } }`, with `retry_after` and `Retry-After` on 429/503 when known):

```
POST /functions/v1/polls                       her session; optional X-App-Transaction (as for credits)
{ "question": "Which vibe for Friday?" | null,  at most 80 characters (grapheme clusters; emoji stay whole)
  "images": ["data:image/jpeg;base64,…", "data:image/png;base64,…"],   exactly two: A, then B
  "locale": "tr",                               en, tr, es, pt-BR, fr, de, it, ru, ja, ko, zh-Hans, id (else en)
  "ai_sides": ["b"] }                           optional: the pictures edited with AI (their Provenance), each of
                                                "a" and "b" at most once; absent, null or [] for neither
→ 201 { "poll_id": "Ab3_Xy9-Kq2LmN0p", "share_url": "https://aybuke.org/p/Ab3_Xy9-Kq2LmN0p",
        "expires_at": "…", "remaining_today": 2 }

GET /functions/v1/polls?id=<poll_id>           anon key or her session; optional X-Poll-Voter: <voter code>
→ 200 { "poll_id", "question", "locale", "created_at", "expires_at",
        "images": { "a": "<signed URL>", "b": "<signed URL>" },
        "image_sizes": { "a": { "width", "height" }, "b": { … } }, "urls_expire_at",
        "ai": { "a": false, "b": true },        the page says "Edited with AI" under each true side
        "is_creator": false, "my_vote": "a" | "b" | null, "votes": { "a": 3, "b": 5 } | null }
   votes: only once this voter code has voted, or for the creator's own session.

GET <signed URL> = /functions/v1/polls/image?id=…&side=a|b&exp=…&sig=…   same headers (the gateway needs them)
→ 200 image/jpeg, Cache-Control: private, max-age=<until exp>. URLs end on the next full hour but one (or
   when the poll ends), so they stay the same within an hour and browsers cache the pictures.

POST /functions/v1/polls/vote   { "poll_id", "choice": "a" | "b", "voter": "<16–128 of A–Z a–z 0–9 - _>" }
→ 200 { "votes": { "a", "b" }, "my_vote" }      voting again with the same code changes the vote

POST /functions/v1/polls/report { "poll_id", "reason": "sexual" | "minor" | "bullying" | "privacy" | "harmful" | "other" }
→ 200 { "reported": true, "taken_down": bool }

GET /functions/v1/polls/mine                   her session; optional X-App-Transaction
→ 200 { "polls": [ { "poll_id", "share_url", "question", "locale", "created_at", "expires_at",
                     "status": "live" | "taken_down", "ai": { "a", "b" }, "votes": { "a", "b" } } ],
        "remaining_today", "daily_cap" }

DELETE /functions/v1/polls?id=<poll_id>        her session → 200 { "deleted": true }; 404 not_found when it isn't hers
   (or already deleted). A poll taken down after a report leaves her list at once but is kept, closed to everyone,
   until its 24 hours end, for the owner's review (see Reports).
```

Errors: 400 `bad_request` (a body or id outside the contract, a question over 80 characters, `ai_sides` that isn't an array of "a" and "b" each at most once); 401 `unauthorized`; 403 `install_blocked` (an owner block of her account or download); 403 `url_expired` (a picture URL that expired or was changed: fetch the poll again); 404 `not_found` (never made, ended, deleted or taken down: one answer for all); 413 `too_large` with `side` (a picture over 1.5 MB, 4,096 px a side or 6 MP; or a body over 4.5 MB); 422 `image_invalid` with `side` (not a JPEG or PNG, or unreadable; WebP and HEIC aren't accepted: send JPEG); 422 `content_blocked` with `category` (the question failed the prompt policy, with an edit's rules, so no rating or reshaping looks; counted, never a strike); 422 `image_blocked` with `sides` (Claude flagged a picture or wouldn't look at it); 429 `rate_limited`, 429 `cooldown` with `until`; 503 `safety_unavailable` (the check couldn't run, Claude isn't configured, or AI is paused for everyone: the attempt is given back).

**Creating** (`handler.ts`): the body and the question are checked first (nothing counted for a 400, 413 or 422 `image_invalid` from the header), then `admit_poll()` refuses a block, a cool-down, AI paused for everyone, and the limits below, and counts the attempt (a blocked question too, apart from today's polls for everyone). `ai_sides` is stored with the poll (`ai_a`, `ai_b`): the server's re-encode drops the picture's IPTC "made with AI" marking, so the app says which pictures were edited with AI and the page labels them. Each picture is then decoded (jpeg-js 0.4.4, or `polls/png.ts`), turned upright from its EXIF orientation, put on white where transparent, shrunk to **720 px** on the long side (area average) and re-encoded as a baseline JPEG, 4:2:0, quality 78 (`polls/jpeg.ts`): no EXIF, no location, no XMP, and no colour profile unless it's Display P3 or sRGB IEC61966-2.1 byte for byte as Apple ships them (`KNOWN_PROFILES` in `polls/picture.ts`, matched by SHA-256; the bytes are in `polls/test_profiles.ts`). Any other profile is dropped, so the picture is read as sRGB: a crafted profile could otherwise make browsers show colours, or a picture, Claude never saw. The 1.1 app converts pictures to sRGB before upload. About 45–85 KB each and 0.1–0.3 s of CPU. Claude (`_shared/safety.ts`, the new `share` subject: a result's categories, substances and weapons included) checks each re-encoded picture on its own, fail closed: a flag or a refusal is 422 `image_blocked` (the attempt stays used; no strike, as for her photo before an edit, and never reported to the circuit breaker, since the sender picks the pictures), an error or a timeout 503 `safety_unavailable` (given back with `finish_poll_attempt()`). Only `anthropic` counts: without `ANTHROPIC_API_KEY` no poll is made (the `XAI_SAFETY_MODEL` fallback doesn't apply, because the privacy policies name Anthropic for polls). What Claude saw is what `create_poll()` stores. Logs: the route, the outcome, sizes and timings, the flagged categories; never a question, a poll id, a voter code or an address.

**Limits** (`poll_policy()` and `poll_backstops()`, migrations `20261102000000` and `20261103000001`; change them in a new migration): **3 polls a day** (UTC) per account and per App Store download, 10 creations an hour per address, **300 a day for everyone**, of which attempts **without a verified App Store download share 30** (like `admit_job()`'s unverified breaker; blocked questions included). A blocked question or an unreadable picture never reaches the safety check, so it counts apart from the 300, toward its own **600 a day** (`blocked_question + invalid_image`; past it a blocked question is refused with 429, and it still counts per account, download and address). 600 poll views, **60 picture loads** and 120 votes an hour per address (60 is 30 polls' two pictures; it was 200); **600 picture loads per poll**; **2,000 a day for everyone, counting each picture once per network address and day** (`private.poll_image_loads`, a salted hash of poll, side and address kept only while the poll exists), so one visitor reloading can't use it up; and every load, reloads included, toward a **4,000-a-day backstop** for the free plan's egress. 10 reports an hour per address. A refused request leaves its counts as they were. A load sends about 60 KB to the browser and about 80 KB from Postgres to the function (base64), so 2,000 loads are roughly 0.3 GB and 4,000 about 0.55 GB.

**Why a table, not Storage.** The pictures are `bytea` in `private.polls` (`storage external`). SQL can create a Storage bucket but can't delete its files (deleting `storage.objects` rows leaves the file behind, or is refused), and `pg_net` is off, so the 5-minute cron couldn't call the Storage API; in a table, the existing `sweep-jobs` cron and the account cascade delete everything on time, at the cost of the extra database hop above.

**Votes and privacy.** The page makes a random voter code once and keeps it in localStorage (no cookie). The server keeps only `keyed_hash('poll_voter', poll id:code)`, so the same code can't be linked across polls, plus the choice and times. Addresses are salted hashes in counters (`private.poll_usage`, 2 days), never stored raw.

**Reports.** `sexual` or `minor` take a poll down at once; any reason from 3 different addresses too (`private.poll_reporters`, salted, deleted with the poll). A taken-down poll answers 404 to everyone and shows as `taken_down` in her list; it's kept only until its 24 hours end, for review, then deleted like every poll. If she deletes it meanwhile, it leaves her list at once (`private.polls.hidden_at`) but stays for review until its 24 hours end; deleting her account still deletes it at once. The owner's record (`private.poll_reports`: poll id, reason, time, the creator's user id and download hash, whether it took the poll down, a status) is kept 30 days, or deleted with her account; the reporter isn't in it.

**Owner tools** (SQL editor, service role): `select public.ops_polls_summary();` (yesterday: made, attempts without a verified download, blocked and rejected, votes, reports, takedowns, picture loads once per picture and address and all of them against their caps, MB, live now; the daily digest shows the same), `select * from public.ops_poll_reports(7);` (reported polls with reasons, state and creator), `select public.ops_poll_image('<poll_id>', 'a');` (a data URI to look at while it exists), `ops_take_down_poll('<poll_id>')`, `ops_restore_poll('<poll_id>')` (a mistaken takedown: reporters reset, open reports dismissed; a poll she deleted while it was down is deleted instead, and the answer is false), `ops_set_poll_report_status('<poll_id>', 'reviewed' | 'actioned' | 'dismissed')`, and `ops_block(p_user => '<user id>')` or `ops_block(p_install => '<install key>')` for repeated abuse (a block stops new polls too).

**Deploy** (the migration first; nothing else changes for the 1.0 app):

```bash
cd backend
psql "$SUPABASE_DB_URL" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261102000000_polls.sql   # live since 16 Oct 2026; replaces sweep_jobs and merge_accounts too
supabase functions deploy polls        # JWT verification on
supabase functions deploy owner-digest # the digest's poll section
```

**Security review fixes (16 October 2026).** The migrations first, in this order; the deployed functions keep working on them (every function and answer they use keeps its arguments and fields: the three-argument `admit_assist()` counts as a request without install proof, and the old `create_poll()` stores no AI labels), and the new functions need them:

```bash
cd backend
psql "$SUPABASE_DB_URL" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261103000000_assist_ceilings.sql  # admit_assist ceilings, job_admissible, sweep_jobs
psql "$SUPABASE_DB_URL" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261103000001_poll_limits.sql     # poll caps, AI labels, delete_poll, sweep_jobs
supabase functions deploy assist ai-image polls owner-digest   # JWT verification on, as before
```

`ANTHROPIC_ASSIST_API_KEY` is optional (see "Assist"); `PROMPT_POLISH` stays `off`.

## Which AI key goes where

- **Production (this backend):** the provider keys live only in Edge Function secrets (`XAI_API_KEY`, or `FAL_KEY`, and `ANTHROPIC_API_KEY` for the safety checks and, unless `ANTHROPIC_ASSIST_API_KEY` is set, the prompt polish and writing help, in `.env`, then `supabase secrets set --env-file .env`; or paste them under Edge Functions → Secrets in the dashboard). They never ship in the app.
- **Trying a key before the backend exists:** put it in `ios/Config/Secrets.xcconfig` (git-ignored, DEBUG builds only), for example `GL_AI_PROVIDER = xai`. The app then calls xAI, fal.ai, OpenAI or Google Gemini directly. See the repository README, "Connect an AI provider".
- The backend runs jobs on xAI or fal.ai. OpenAI and Gemini work in the app's developer mode; add a backend adapter for them in `_shared/` before using them in production.

## Credit rules

Defined once in SQL (`public.credit_policy()`) and mirrored in the app (`CreditPolicy.standard`):

- Free: **2 credits per day**, refilled at 00:00 UTC, never accumulating.
- Pro: **80 credits per month**, unused credits roll over one month (cap 160). The free trial week gives **20 credits** instead (`trial_credits`).
- Credit packs: never expire (App Review Guideline 3.1.1).
- Rewarded ads (free members out of credits): **1 credit per ad, at most 2 a day** (`ad_reward_policy()`), added to the daily bucket.
- Rewarded Pro tries (free members with a credit to spend): **one try of a Pro look or style per ad, at most 1 a day**, for one job started within 30 minutes; the job costs 1 credit like any look, and a refund gives the try back ("Rewarded unlock").
- Likeness Lock: one free retry per result within 15 minutes, **3 a day** (`free_retries_daily`). A retry that was refunded (it failed, timed out or was cancelled) gives its daily slot back.
- Spending order: daily → subscription → purchased (expiring credits first).
- Any failure, cancellation, safety block or timeout is refunded exactly once, and so is a result that never reached the app. The poll that hands the results over records the delivery (`deliver_outputs()`); a finished job that was never handed over is refunded when its hour is up, or at once when the app cancels it, and one that was handed over but never confirmed (a download that broke) is refunded at most once a day per user and per App Store install, so skipping the confirmation can't keep both the images and the credit. Clients can't read job rows through the Data API: results reach the app only through `ai-image`, which records the delivery.

Change the numbers in `credit_policy()` (new migration) to retune pricing without an app update; update `CreditPolicy.standard` so the app's copy matches.

## Abuse runbook

Every cloud job goes through `admit_job()`, which applies the numbers in `public.credit_policy()`:

- **Strikes:** a prompt the policy blocks, or an output the moderation or the safety check flags, is a strike (not when she cancelled the job before its result came back). **3** strikes in **24 hours** start a **24-hour** cool-down (no cloud AI, nothing charged, no paywall). **3** cool-downs in **30 days** block the install until the owner lifts it. An install without a verified App Store transaction is kept to its network address instead: a salted hash of the address (`private.keyed_hash('ip', …)`), the same key the rate limit uses. The balance (`GET /ai-image`, `wallet_state()`) gets the same address, so it shows a cool-down or block on it too.
- **Rate limits:** per user, free **6 a minute, 30 an hour, 100 a day**; Pro **20, 60 and 200**. Per address, **120 requests an hour**. Reports: **10 a day** per user. Writing help (`assist`) and the prompt polish: **60 an hour** per user and per verified install and **200 an hour** per address each, 30 an hour shared by everyone without a verified install, and **20 a minute, 200 an hour and 1,000 a day** for everyone together; none while a result safety check failed in the last 5 minutes (`admit_assist()`, `assist_policy()`; past a polish limit a job goes on unpolished, and a job `admit_job()` couldn't take is never polished).
- **Breakers** (UTC day): free credits pause at **60** free jobs (`free_jobs_daily_cap`), the unverified allowance at **10** (`unverified_jobs_daily_cap`, part of the 60), and all AI at **400** jobs (`all_jobs_daily_cap`), so paid jobs always keep at least 340 a day. Paid users keep working when only the free breaker trips. (Launch budget: 20261027000001 lowered them from 1,500, 200 and 8,000; 20261029000000 raised the hard cap from 120 to 400.)

Owner tools run in the SQL editor (the service role). Clients have no access to any of them.

1. **Read the day:** `select public.ops_daily_summary();` (or pass a date). It shows jobs and failures by code, the estimated provider cost, the breakers against their caps, strikes, cool-downs, blocks, open reports, and the top installs and addresses (hashed, shortened).
2. **Find the strikes:** `select * from public.ops_strikes(7);` lists each install key (or `user:<id>`) with its strikes, categories, cool-down and whether it is blocked. Check `user_ids` before you block an address: one address can serve many people (a school, a mobile carrier).
3. **Reports:** `select * from public.ops_reports('open');` lists the newest, with the operation and what the system knows about the sender. Mark each with `select public.ops_set_report_status('<report id>', 'reviewed' | 'actioned' | 'dismissed');`.
4. **Block:** `select public.ops_block(p_job => '<job id>', p_reason => '…');` blocks the install and the user behind a job. Name `p_install` or `p_user` instead when you have the key. Blocks stop cloud AI at once.
5. **Lift a block or cool-down:** `select public.ops_unblock(p_install => '<install key>');` or `p_user => '<user id>'`. It lifts the block and any running cool-down and clears the cool-down history for that install or user, so the next cool-down starts from none. It returns `blocks_lifted` and `cooldowns_lifted`. Lifting an address lifts every account on it.
6. **Pause and resume AI:** `select public.ops_pause_ai('all', 2, 'why');` stops every job for 2 hours (`'free'` stops only the free credits, and paid users keep working). A paused request is refused before the prompt check, so blocked prompts get no strike while paused. `select public.ops_resume_ai();` resumes everything (or `ops_resume_ai('all')`). A pause also ends by itself at `paused_until`. When xAI refuses a job because the team's credit or spending limit ran out (HTTP 402, or a 403/429 that says so: `provider_billing`), the job is refunded, `ai-image` turns the `'all'` pause on itself (`pause_ai_for_provider()`, note `provider_billing`, 30 days) and mails the owner once per pause ("Aybuke AI paused: xAI balance"): top up at console.x.ai, run `select public.ops_resume_ai();`, then record the new balance.
7. **Retune the caps:** the rate limits, strikes, cool-downs, breakers and retention all live in `public.credit_policy()`. Change them in a new migration that replaces the function (copy it, change the numbers, keep the comment), then update `CreditPolicy.standard` in the app for the credit numbers. No app release is needed for the rest.
8. **Safety check failures:** many `photo_check_failed` or `safety_check_failed` jobs in `ops_daily_summary()` mean the independent check couldn't run (Anthropic balance or spending limit, a revoked key, an outage). Every one is refunded. The `ai-image` logs give the short reason (`HTTP 401 authentication_error`, `HTTP 400 invalid_request_error`, `timeout`, `deadline` for a check that hit its 20 s cap); never the key or the image. `refused` is different: Claude declined to look at that image, which points at the content, not an outage (Anthropic's vision API doesn't process explicit images). It stays a refunded failure, never a strike, because a false strike on a teen is worse than a refund. Each log line names the job: if refusals keep coming from one sender, look at those jobs before you block anything (`ops_block(p_job => …)`). **Circuit breaker** (migration `20261029000001`): result checks that couldn't run (not verdicts, refusals or images the model can't take) are reported to `note_safety_check_error()`; photo checks never are, because the sender picks the photo (a few broken files would let one person pause AI for everyone) and a failed photo check stops the edit before xAI anyway; **3** within **10 minutes** turn the `'all'` pause on (note `safety_check_errors`) for **5 minutes**, doubling up to an hour when it trips again within 15 minutes of the last pause, so an Anthropic outage stops new jobs at `admit_job()` (`ai_paused`) before xAI bills creations whose results would be refunded anyway. It never shortens or replaces a pause already on; `select public.ops_safety_breaker();` shows its state and `select public.ops_resume_ai();` ends it early.
9. **Check the address after a deploy:** the address is the last `x-forwarded-for` entry (`_shared/input.ts`). Send a generation request from a known network with a made-up `X-Forwarded-For: 1.2.3.4` header, then in the SQL editor compare `select ip_key, requests from private.ip_usage where hour = date_trunc('hour', now());` with `select private.keyed_hash('ip', '<your address>');` (IPv4 as is; IPv6 as its /64, for example `2001:db8:0:0::/64`). Your address must match a row, and `private.keyed_hash('ip', '1.2.3.4')` must not.

**Never:**

- Edit a migration the project has applied (`supabase db push` has run it), or change one in `supabase/migrations` after it is published. Add a new file with a later timestamp instead; only comments may change in an old one.
- Grant `execute` on the `ops_*`, `admit_job`, `flag_job` or `private` functions to `anon` or `authenticated`, or put the service role key in the app or in a ticket.
- Store a prompt, a photo or a raw IP address in a table, or paste one into a report.

## Local checks

```bash
# Type-check, lint and format-check the Edge Functions (Deno 2)
cd backend/supabase/functions && deno check */index.ts && deno lint && deno fmt --check && deno test _shared/ ad-reward/ app-store-notifications/ account/ owner-digest/ ai-image/ credits-redeem/ assist/ polls/

# Run the migration + ledger tests on a throwaway PostgreSQL 14+
backend/scripts/test-db.sh
```

Both run in CI (`.github/workflows/ci.yml`).

## Before launch

Live since 15 October 2026 (migrations through `20261029000002`, seven functions; Aybuke 1.0 is in App Review).

- [x] Set `APPLE_APP_ID` so production purchases verify (sandbox works without it).
- [x] Ship the independent safety check: `ANTHROPIC_API_KEY` set (Anthropic listed in the consent sheet, `consentVersion` 2, and the privacy policies); the `ai-image` start-up log says `output check in force: xai + anthropic:claude-haiku-5-5`, and a real edit passed both checks on the live API (15 October 2026).
- [x] Add an App Store Server Notifications V2 endpoint to mark refunds/revocations (`entitlements.revoked`) immediately: `functions/app-store-notifications` (migration `20261025000000`), deployed and set as RevenueCat's Apple Server Notification Forwarding URL (setup step 5; in App Store Connect only without RevenueCat).
- [x] Sign in with Apple: `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` set and checked against Apple, `signInWithApple` on in 1.0.
- [ ] For 1.1 (Rewarded unlock): apply migration `20261101000000_rewarded_unlocks.sql`, then deploy `ai-image` and `ad-reward --no-verify-jwt`, before the app that offers Pro tries ships.
- [ ] For 1.1 (Polls): apply migration `20261102000000_polls.sql`, then deploy `polls` (JWT verification on) and `owner-digest`, and check that `https://aybuke.org/p/<id>` opens a test poll, before the app that offers polls ships.
- [ ] For 1.1 (security review, 16 October 2026): apply `20261103000000_assist_ceilings.sql`, then `20261103000001_poll_limits.sql`, and deploy `assist`, `ai-image`, `polls` and `owner-digest` (JWT verification on). The 1.1 app sends `X-App-Transaction` to `/assist`, converts poll pictures to sRGB before upload and sends `ai_sides`. Optional, recommended: `ANTHROPIC_ASSIST_API_KEY` from a Claude Console workspace of its own ("Assist").
- [ ] Add App Attest + DeviceCheck to stop free-credit farming across reinstalls (see research doc §3.4).
- [ ] Confirm fal accepts data-URI inputs for every endpoint above; otherwise upload to a private bucket and pass 10-minute signed URLs.
- [ ] Move polling to fal webhooks (Ed25519-signed) when traffic grows.
- [ ] Sign C2PA manifests server-side (`c2pa-rs`) in addition to the IPTC metadata the app writes.
