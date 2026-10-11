# Glowlit backend (Supabase + fal.ai)

The iOS app never talks to an AI provider directly and never ships provider
keys. This backend authenticates each (anonymous) user, verifies purchases with
Apple, meters credits in Postgres, moderates prompts and outputs, and forwards
an allow-listed set of operations to [fal.ai](https://fal.ai).

```
iOS app ──► Supabase Auth (anonymous JWT)
   │
   ├─► POST   /functions/v1/ai-image            enqueue job  ──► fal.ai queue (model per operation)
   ├─► GET    /functions/v1/ai-image?job_id=…   poll job     ──► fal status / result (+ output NSFW check)
   ├─► DELETE /functions/v1/ai-image?job_id=…   cancel job   ──► fal cancel + exact credit refund
   ├─► GET    /functions/v1/ai-image            balance
   ├─► POST   /functions/v1/credits-redeem      credit pack  ──► Apple JWS verification → grant once
   └─► DELETE /functions/v1/account             delete user and all data (cascades)
```

The wire contract is defined (and unit-tested) in
`ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift`.

## Why it's shaped like this

| Decision | Reason |
|---|---|
| **Async jobs + polling** | Edge Functions time out after ~150 s idle; generations take 5–40 s. The function enqueues on fal's durable queue and returns in < 1 s; the app polls (1 s → 3 s back-off). Webhooks are an easy later upgrade. |
| **Operations, not endpoints** | The app sends `operation` + `template_id`; the server picks the model (`_shared/fal.ts`) and the prompt recipe (`_shared/catalog.json`). Models can be swapped without an app release, and nobody can use our fal key for arbitrary models. |
| **Server-side credit ledger** | `reserve_credits` → job → `release_credits` on any failure, cancel or timeout. Exact per-bucket refunds, idempotent, append-only audit trail (`credit_ledger`). |
| **Apple-verified entitlements** | Pro status comes from a StoreKit 2 signed transaction verified with Apple's App Store Server Library, then bound to one user at a time. |
| **No input storage** | Photos are passed to fal as data URIs and never written to our database or storage. fal outputs expire after 1 hour (`X-Fal-Object-Lifecycle-Preference`) and request I/O history is disabled (`X-Fal-Store-IO: 0`). |
| **Layered safety** | Prompt policy (client + server) → strict model `safety_tolerance` → output NSFW check (on by default) → in-app reporting. Documented for EU AI Act Art. 5(1)(ba) (from 2 Dec 2026). |

## Models (late 2026 picks)

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
   supabase functions deploy ai-image credits-redeem account
   ```
6. **Schedule the sweeper** (fails and refunds stuck jobs, deletes job rows after 30 days): enable the `pg_cron` extension, then run
   ```sql
   select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
   ```
7. **Point the app at it** — in `ios/App/Resources/AppConfig.json` set `backendBaseURL` to `https://<project-ref>.supabase.co` and `supabaseAnonKey` to the project's publishable (anon) key. Both are public by design; access is enforced by JWTs, RLS and the functions themselves.

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
cd backend/supabase/functions && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts && deno lint && deno fmt --check

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
