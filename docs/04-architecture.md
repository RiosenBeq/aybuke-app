# 04 · Architecture

```
┌──────────────────────────── iOS app (SwiftUI, iOS 17+) ───────────────────────────┐
│  Features: Onboarding · Explore · Create · Edit/Editor · My Works · Paywall · Settings │
│  AppModel (@Observable): navigation + gates (Pro → consent → credits)               │
│  Services                                                                           │
│   ├─ AIServiceRouter ──► OnDeviceImageService (Vision cut-out, Core Image)          │
│   │                 └──► RemoteAIImageService (jobs: submit → poll → download)      │
│   │                      or DemoAIImageService (offline, labelled "DEMO")            │
│   ├─ AuthSessionManager (actor): Supabase anonymous session in Keychain             │
│   ├─ PurchaseManager: StoreKit 2 subscriptions + consumable credit packs            │
│   ├─ CreditsManager: local ledger (demo) / server balance (production)              │
│   ├─ ImageExporter: IPTC DigitalSourceType XMP + free-tier wordmark                 │
│   └─ SwiftData `Creation` + ImageStore (Application Support, file protection)        │
│  AppCore (Swift package, Linux-testable): API contract, credits, catalogs, policy   │
└───────────────┬─────────────────────────────────────────────────────────────────────┘
                │ HTTPS (anonymous JWT, optional X-Entitlement-JWS)
┌───────────────▼───────────── Supabase ───────────────────────────────────────────────┐
│  Auth (anonymous)   Edge Functions (Deno)                 Postgres (RLS)               │
│                     ├─ ai-image: create/poll/cancel/balance  credit_wallets            │
│                     ├─ credits-redeem: Apple JWS → pack      credit_ledger (append-only)│
│                     └─ account: delete user                  jobs · entitlements        │
└───────────────┬──────────────────────────────┬─────────────────────────────────────────┘
                │ queue.fal.run (Key auth)      │ Apple root CAs (JWS verification)
          ┌─────▼──────┐                   ┌────▼─────┐
          │   fal.ai   │  Nano Banana 2,    │  Apple   │
          │  (models)  │  SeedVR2, BiRefNet │          │
          └────────────┘  object-removal    └──────────┘
```

## Repository layout

```
ios/
  Glowlit.xcodeproj         Xcode 16+ project; the App/ folder is synchronized (new files auto-included)
  App/                      app target sources and resources
    App/                    entry point, AppModel, RootView, AppConfig, AppPresentations
    DesignSystem/           Palette, Typography, Metrics, Brand, Components/
    Features/               Onboarding, Home, Create, Edit, Library, Paywall, Settings
    Services/               AI, Auth, Store, Persistence, Photos, Support
    Resources/              Assets.xcassets, Fonts/, AppConfig.json, PrivacyInfo.xcprivacy
  Packages/AppCore/         platform-independent logic + 48 unit tests (runs on Linux too)
  StoreKit/Products.storekit local StoreKit testing configuration (scheme-linked)
backend/
  supabase/migrations/      schema, RLS, credit functions
  supabase/functions/       ai-image, credits-redeem, account, _shared/
  supabase/tests/           ledger tests (plain PostgreSQL)
  scripts/test-db.sh        runs migration + tests on a throwaway Postgres
scripts/export-catalog.sh   regenerates the backend template recipes from the iOS catalog
docs/                       research, brand, spec, architecture, compliance, roadmap
.github/workflows/          CI (AppCore tests, backend checks, Xcode build) + simulator screenshots
```

## Key design decisions

| Decision | Why |
|---|---|
| **SwiftUI + Observation (`@Observable`), iOS 17 minimum** | Covers about 95% of active iPhones. Gives SwiftData, `VNGenerateForegroundInstanceMaskRequest`, `symbolEffect` and `.onChange(of:_:)` with two parameters. |
| **Swift 5 language mode** | Keeps the build reliable across Xcode 16/26/27. Migrating to Swift 6 strict concurrency is on the roadmap. |
| **Synchronized Xcode folder** | No merge conflicts in `project.pbxproj` when adding files. |
| **AppCore package** | The contract, credits, catalog and policy are unit-tested on Linux and macOS without a simulator. The backend's template recipes are generated from it, and a sync test keeps the two aligned. |
| **Async job API** | Generations take 5–40 s, but Edge Functions shouldn't hold connections open. The app polls with back-off (1 s → 3 s, 180 s deadline) and cancels server-side if the user leaves. |
| **Server-authoritative credits** | The client mirrors the rules for instant UI and demo mode. In production the server reserves, captures and refunds credits atomically in SQL. |
| **Operations, not models** | The app sends `operation` + `template_id`; the server picks the model and prompt. Models can be hot-swapped without an app update, and the fal key can't be misused. |
| **On-device first** | Background removal (Vision) and adjustments (Core Image) are free, instant and private. They need neither consent nor credits. |
| **Demo mode** | With no backend configured, `DemoAIImageService` simulates results with Core Image and clearly stamps them "DEMO PREVIEW". Design, QA and App Review previews work without keys. |
| **Anonymous auth** | No sign-up wall (Guideline 5.1.1(v)). Purchases bind to the user through `appAccountToken`, and account deletion is available in-app. |

## AI job lifecycle

```
App                          ai-image (Edge)                         Postgres                 fal.ai
 │ POST {operation,…}  ──────► validate · policy · rate limit
 │                              insert job ─────────────────────────► jobs(queued)
 │                              reserve_credits ────────────────────► wallet −cost, ledger hold
 │                              submit ─────────────────────────────────────────────────────► queue
 │ ◄──── 202 {job_id, queued, credits_remaining}
 │ GET ?job_id (1s, 1s, 1.5s…) ► status_url? ──────────────────────────────────────────────► IN_PROGRESS
 │ ◄──── {processing}
 │ GET ?job_id ────────────────► COMPLETED → result → NSFW check ─────► jobs(completed, outputs)
 │ ◄──── {completed, outputs:[url]}                    (failure → jobs(failed) + release_credits)
 │ download outputs (expire after 1h) → editor/result → export with IPTC provenance
```

**Failure modes**
- Provider error, safety block, timeout (10 min server-side) or user cancel → `release_credits(job)`: an exact, idempotent refund.
- `sweep_jobs()` (pg_cron) refunds jobs whose client disappeared.
- A 401 triggers one token refresh and retry.
- Network errors surface as friendly toasts.

## Security & privacy

**Keys and access**
- No provider keys ship in the app. Supabase's anon key is public by design.
- Row-level security: clients can only `SELECT` their own rows. The ledger functions are executable only by the service role, and a test checks that clients can't grant themselves credits.

**Purchases**
- Pro status comes from Apple-signed transactions verified with Apple's App Store Server Library.
- Each original transaction is bound to one user at a time.
- Credit packs are granted once per Apple transaction id.

**Data**
- Photos are uploaded as data URIs (≤ 1536 px, JPEG re-encode, which strips GPS EXIF). They are never stored by us.
- fal outputs expire after 1 hour, and fal's request history is disabled.
- The library lives on the device with `completeFileProtection`. Tokens are in the Keychain (`AfterFirstUnlockThisDeviceOnly`).

**Safety:** a layered stack.
1. Client prompt policy.
2. Server prompt policy.
3. Server-side template recipes (prompt tampering is impossible).
4. Model `safety_tolerance: "2"`.
5. Output NSFW check (on by default).
6. "Report this image".

## Testing & CI

| Layer | How | Where |
|---|---|---|
| AppCore (contract, credits, catalog sync, policy, polling) | 48 XCTest cases, run on Linux (Swift 6.1 container) | `ci.yml › core` |
| Edge Functions | `deno fmt --check`, `deno lint`, `deno check` (strict) | `ci.yml › backend` |
| SQL ledger | Migration + behavioural tests on PostgreSQL: holds, refunds, packs, rollover, sweeper, RLS | `ci.yml › backend` |
| iOS app | `xcodebuild build` (unsigned, generic iOS) on macOS | `ci.yml › ios` |
| Visual | Simulator screenshots of every key screen (DEBUG screenshot scenes) | `screenshots.yml` |

## Configuration

`ios/App/Resources/AppConfig.json` holds the backend URL and anon key, the provider names shown in the consent sheet, the retention hours, the legal URLs and the App Store ID. With an empty `backendBaseURL` the app runs in **demo mode**.
