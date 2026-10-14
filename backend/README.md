# Glowlit backend (Supabase + xAI)

The iOS app never talks to an AI provider directly and never ships provider
keys. This backend authenticates each (anonymous) user, verifies purchases with
Apple, meters credits in Postgres, moderates prompts and outputs, and forwards
an allow-listed set of operations to [xAI](https://docs.x.ai) (Grok Imagine),
or to [fal.ai](https://fal.ai) with `AI_PROVIDER=fal`.

```
iOS app ──► Supabase Auth (anonymous JWT; optional Sign in with Apple ID token)
   │
   ├─► POST   /functions/v1/ai-image            enqueue job  ──► xAI request in the background (or fal's queue)
   ├─► GET    /functions/v1/ai-image?job_id=…   poll job     ──► job status / results (+ output safety check)
   ├─► DELETE /functions/v1/ai-image?job_id=…   cancel job   ──► exact credit refund; on a finished job: results cleared
   ├─► GET    /functions/v1/ai-image            balance
   ├─► POST   /functions/v1/credits-redeem      credit pack  ──► Apple JWS verification → grant once
   ├─► POST   /functions/v1/report              "Report this image" (reason, job id) → public.reports
   ├─► POST   /functions/v1/account/link        after Sign in with Apple: merge the anonymous user in
   └─► DELETE /functions/v1/account             revoke the Apple token, delete user and all data (cascades)
```

The wire contract is defined (and unit-tested) in
`ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift`.

## Why it's shaped like this

| Decision | Reason |
|---|---|
| **Async jobs + polling** | Edge Functions time out after ~150 s idle; generations take 5–40 s. The function answers in < 1 s and the app polls (1 s → 3 s back-off). xAI requests run in the background (`EdgeRuntime.waitUntil`); fal jobs sit on fal's durable queue. |
| **Operations, not endpoints** | The app sends `operation` + `template_id`; the server picks the model (`_shared/xai.ts`, `_shared/fal.ts`) and the prompt recipe (`_shared/catalog.json`). Models can be swapped without an app release, and nobody can use our keys for arbitrary models. |
| **Server-side credit ledger** | `reserve_credits` → job → `release_credits` on any failure, cancel or timeout. Exact per-bucket refunds, idempotent, append-only audit trail (`credit_ledger`). |
| **Apple-verified entitlements** | Pro status comes from a StoreKit 2 signed transaction verified with Apple's App Store Server Library, then bound to one user at a time. |
| **No input storage** | Photos are passed to the provider as data URIs and never written to our database or storage. xAI results come back as base64, are held on the job only until the app confirms the download (then cleared; `sweep_jobs()` clears any left after an hour). With xAI Zero Data Retention on, xAI deletes requests within an hour and never trains on them. fal outputs expire after 1 hour (`X-Fal-Object-Lifecycle-Preference`) and request I/O history is disabled (`X-Fal-Store-IO: 0`). |
| **Layered safety** | Prompt policy (client + server) → provider moderation (fal's strict `safety_tolerance`) → one output check on every result that fails closed (`_shared/moderation.ts`): fal.ai's NSFW classifier when `FAL_KEY` is set, otherwise xAI's own moderation verdict; a flag, an error or a missing verdict blocks the result and refunds it, and there's no switch to turn it off → in-app reporting. Documented for EU AI Act Art. 5(1)(ba) (from 2 Dec 2026). |

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

Prices, latency and alternatives: [`docs/research/tech-and-compliance.md`](../docs/research/tech-and-compliance.md).
**Verify current prices on fal before launch** — several were unverified at research time.

## Setup

1. **Create a Supabase project** and install the [Supabase CLI](https://supabase.com/docs/guides/cli).
2. **Enable anonymous sign-ins**: Authentication → Sign In / Providers → Anonymous. Turn on CAPTCHA (Turnstile) protection for sign-ups to limit abuse.
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
   ```
6. **Schedule the sweeper** (fails and refunds stuck jobs, clears job outputs after 1 hour, deletes job rows after 30 days and reports after 12 months): enable the `pg_cron` extension, then run
   ```sql
   select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
   ```
7. **Point the app at it** — in `ios/App/Resources/AppConfig.json` set `backendBaseURL` to `https://<project-ref>.supabase.co` and `supabaseAnonKey` to the project's publishable (anon) key. Both are public by design; access is enforced by JWTs, RLS and the functions themselves.

## Accounts (Sign in with Apple)

Everyone starts anonymous, so nobody has to sign up. Signing in is optional and is offered mainly to Pro members and credit-pack buyers, so their membership and credits follow them to another iPhone:

1. The app gets an identity token from Apple and signs in with Supabase's native Apple provider (`POST /auth/v1/token?grant_type=id_token`).
2. It then calls `POST /account/link` with the new session, the previous anonymous session and Apple's one-time authorization code. `merge_accounts()` moves purchased credits, the subscription, jobs and reports into the account (daily free credits never move), and the anonymous user is deleted. Running it twice is safe.
3. Apple's refresh token is kept in `public.apple_accounts` (service role only), so `DELETE /account` can revoke it, as Apple requires for account deletion.
4. `link` also records the merged anonymous id in `public.merged_users` (service role only). RevenueCat keeps a purchase made while anonymous on that anonymous customer, so `DELETE /account` deletes the RevenueCat customers for the account and every merged id (`REVENUECAT_SECRET_KEY`, plus `REVENUECAT_PROJECT_ID` for a v2 key; skipped with a warning when unset). RevenueCat queues the deletion.

The app creates the anonymous user only when it's first needed (a cloud AI job after consent, or a purchase), never at launch, and configures RevenueCat only for people who buy. Deleting the account never signs up first: without a stored session there is nothing on the server to delete.

Photos are not synced: the library stays on each iPhone.

## Reports

`POST /report` stores a user's "Report this image" in `public.reports` (reason, optional details, the user's own job id) with a limit of 20 reports a day. Review open reports in the Supabase dashboard (`status = 'open'`) and set `status` to `reviewed`, `actioned` or `dismissed`. Reports are deleted after 12 months by `sweep_jobs()`, or with the account.

## Which AI key goes where

- **Production (this backend):** the provider key lives only in Edge Function secrets (`XAI_API_KEY`, or `FAL_KEY`, in `.env`, then `supabase secrets set --env-file .env`; or paste it under Edge Functions → Secrets in the dashboard). It never ships in the app.
- **Trying a key before the backend exists:** put it in `ios/Config/Secrets.xcconfig` (git-ignored, DEBUG builds only), for example `GL_AI_PROVIDER = xai`. The app then calls xAI, fal.ai, OpenAI or Google Gemini directly. See the repository README, "Connect an AI provider".
- The backend runs jobs on xAI or fal.ai. OpenAI and Gemini work in the app's developer mode; add a backend adapter for them in `_shared/` before using them in production.

## Credit rules

Defined once in SQL (`public.credit_policy()`) and mirrored in the app (`CreditPolicy.standard`):

- Free: **3 credits per day**, refilled at 00:00 UTC, never accumulating.
- Pro: **100 credits per month**, unused credits roll over one month (cap 200).
- Credit packs: never expire (App Review Guideline 3.1.1).
- Spending order: daily → subscription → purchased (expiring credits first).
- Any failure, cancellation, safety block or timeout is refunded exactly once.

Change the numbers in `credit_policy()` (new migration) to retune pricing without an app update; update `CreditPolicy.standard` so the app's copy matches.

## Local checks

```bash
# Type-check, lint and format-check the Edge Functions (Deno 2)
cd backend/supabase/functions && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts report/index.ts && deno lint && deno fmt --check

# Run the migration + ledger tests on a throwaway PostgreSQL 14+
backend/scripts/test-db.sh
```

Both run in CI (`.github/workflows/ci.yml`).

## Before launch

- [ ] Set `APPLE_APP_ID` so production purchases verify (sandbox works without it).
- [ ] Add an App Store Server Notifications V2 endpoint to mark refunds/revocations (`entitlements.revoked`) immediately.
- [ ] Add App Attest + DeviceCheck to stop free-credit farming across reinstalls (see research doc §3.4).
- [ ] Confirm fal accepts data-URI inputs for every endpoint above; otherwise upload to a private bucket and pass 10-minute signed URLs.
- [ ] Move polling to fal webhooks (Ed25519-signed) when traffic grows.
- [ ] Sign C2PA manifests server-side (`c2pa-rs`) in addition to the IPTC metadata the app writes.
