# 04 · Architecture

```
┌──────────────────────────── iOS app (SwiftUI, iOS 17+, iPhone and iPad) ───────────────────┐
│  Features: Onboarding · Tour · Explore · Create · Edit/Editor · Video · Share · My Works · │
│            Paywall · Settings   (12 languages · Liquid Glass on iOS 26)                    │
│  AppModel (@Observable): navigation + gates (Pro → consent → credits)                      │
│  Services                                                                                  │
│   ├─ AIServiceRouter ──► OnDeviceImageService (Vision cut-out, Core Image)                 │
│   │                 └──► RemoteAIImageService (jobs: submit → poll → download → confirm)   │
│   │                      or DemoAIImageService (offline, labelled "DEMO")                  │
│   ├─ RetroEffect · AutoDevelop: 80s/90s/Y2K effects, Auto, RAW development (Core Image)    │
│   ├─ VideoEngine (AVFoundation): loudness → SilenceCutter → stitch → effect → .mp4         │
│   ├─ ShareRenderer · ShareDesigns: share formats, Cover star (Vision person mask), invite  │
│   ├─ AuthSessionManager (actor): Supabase anonymous session in Keychain                    │
│   ├─ PurchaseManager: StoreKit 2 subscriptions + consumable credit packs                   │
│   │   └─ RevenueCatBridge: observer mode, records purchases for analytics                  │
│   ├─ CreditsManager: local ledger (demo) / server balance (production)                     │
│   ├─ ImageExporter: IPTC DigitalSourceType XMP + free-tier wordmark                        │
│   ├─ GlowActivityController / GlowWidgetBridge: Live Activity + widget snapshot            │
│   └─ SwiftData `Creation` + ImageStore (Application Support, file protection)              │
│  AppCore (Swift package, Linux-testable): API contract, credits, catalogs, policy,         │
│            SilenceCutter, AutoAdjust, L10n.core                                            │
│  GlowlitWidgets (extension): widgets + Live Activity, reads the App Group snapshot         │
└───────────────┬────────────────────────────────────────────────────────────────────────────┘
                │ HTTPS (anonymous JWT, optional X-Entitlement-JWS)
┌───────────────▼───────────── Supabase ─────────────────────────────────────────────────────┐
│  Auth (anonymous,     Edge Functions (Deno)                    Postgres (RLS)              │
│  Sign in with Apple)  ├─ ai-image: create/poll/cancel/balance  credit_wallets              │
│                       ├─ credits-redeem: Apple JWS → pack      credit_ledger (append-only) │
│                       ├─ report: "Report this image"           jobs · entitlements         │
│                       └─ account: link (merge) · delete user   reports · apple_accounts    │
└───────────────┬────────────────────────────────┬────────────────────────────────┬──────────┘
                │ api.x.ai (Bearer key)          │ queue.fal.run, NSFW check      │ JWS verification
          ┌─────▼──────┐                   ┌─────▼──────┐                   ┌─────▼──────┐
          │    xAI     │  Grok Imagine     │   fal.ai   │  Nano Banana 2,   │   Apple    │
          │ (default)  │  image 2.0, 1k    │ (optional) │  SeedVR2, object  │  root CAs  │
          └────────────┘                   └────────────┘  removal          └────────────┘
```

## Repository layout

```
ios/
  Glowlit.xcodeproj         Xcode 16+ project; the App/ folder is synchronized (new files auto-included)
  App/                      app target sources and resources
    App/                    entry point, AppModel, RootView, AppConfig, AppPresentations, CoreStrings (generated)
    DesignSystem/           Palette (Blush + Aura accents), Typography (Poppins), Metrics, Brand, LiquidGlass, Components/
    Features/               Onboarding, Tour, Home, Create, Edit, Video, Share, Library, Paywall, Settings, Account, Legal
    Services/               AI (incl. RetroEffects, AutoDevelop), Video, Auth, Store (incl. RevenueCatBridge),
                            Persistence, Photos, Sharing, Notifications, Widgets, Support
    Resources/              Assets.xcassets, Fonts/, Legal/, Localizable.xcstrings, InfoPlist.xcstrings,
                            AppConfig.json, PrivacyInfo.xcprivacy
  Packages/AppCore/         platform-independent logic + 100 unit tests (runs on Linux too)
  GlowlitWidgets/           widget extension: Today's trend, My glow, GlowLiveActivity (Dynamic Island + Lock Screen),
                            its own Localizable.xcstrings and CoreStrings (generated)
  Config/                   Info.plist additions, xcconfigs, entitlements (App Group group.app.glowlit.shared)
  StoreKit/Products.storekit local StoreKit testing configuration (scheme-linked)
backend/
  supabase/migrations/      schema, RLS, credit functions
  supabase/functions/       ai-image, credits-redeem, account, report, _shared/ (xai.ts, fal.ts, policy.ts, …)
  supabase/tests/           ledger tests (plain PostgreSQL)
  scripts/test-db.sh        runs migration + tests on a throwaway Postgres
scripts/export-catalog.sh   regenerates the backend template recipes from the iOS catalog
scripts/export-core-strings.py  registers AppCore's English strings for translation (writes CoreStrings.swift)
docs/                       research, brand, spec, architecture, compliance, roadmap
.github/workflows/          CI (AppCore tests, backend checks, legal and core-strings sync, Xcode build) + simulator screenshots
```

## Key design decisions

| Decision | Why |
|---|---|
| **SwiftUI + Observation (`@Observable`), iOS 17 minimum** | Covers about 95% of active iPhones. Gives SwiftData, `VNGenerateForegroundInstanceMaskRequest`, `symbolEffect` and `.onChange(of:_:)` with two parameters. |
| **Swift 5 language mode** | Keeps the build reliable across Xcode 16/26/27. Migrating to Swift 6 strict concurrency is on the roadmap. |
| **Synchronized Xcode folder** | No merge conflicts in `project.pbxproj` when adding files. |
| **AppCore package** | The contract, credits, catalog and policy are unit-tested on Linux and macOS without a simulator. The backend's template recipes are generated from it, and a sync test keeps the two aligned. |
| **Async job API** | Generations take 5–40 s, but Edge Functions shouldn't hold connections open. The function answers 202 at once: an xAI request then runs in the background (`EdgeRuntime.waitUntil`), while a fal job waits on fal's queue. The app polls with back-off (1 s → 3 s, 180 s deadline) and cancels server-side if the user leaves. |
| **Server-authoritative credits** | The client mirrors the rules for instant UI and demo mode. In production the server reserves, captures and refunds credits atomically in SQL. |
| **Operations, not models** | The app sends `operation` + `template_id`; the server picks the provider, model and prompt (`_shared/xai.ts`, `_shared/fal.ts`). Models can be hot-swapped without an app update, and provider keys can't be misused. |
| **xAI by default, fal.ai as the alternative** | Grok Imagine (`grok-imagine-image-2.0` at 1k; low quality for free users, medium for Pro) is the best quality for the price, about $0.06 per cloud operation. `AI_PROVIDER=fal` switches back without an app release. |
| **On-device first** | Background removal (Vision), adjustments and Auto, the 80s/90s/Y2K effects and RAW development (Core Image), Best shot (Vision) and video editing (AVFoundation) are free, instant and private. They need neither consent nor credits. |
| **On-device video** | `VideoEngine` reads loudness in 50 ms windows from a 16 kHz mono copy of the sound; `SilenceCutter` (AppCore, unit-tested) picks the parts to keep with a threshold that adapts to each clip and keeps short pauses. The kept ranges are stitched into an `AVMutableComposition`, every frame gets the retro effect through Core Image, and the result is exported as .mp4. Clips up to 5 minutes; no watermark, no ending clip. |
| **Liquid Glass with a fallback** | `liquidGlass(in:)`, `GlassGroup` and `minimizingTabBar()` use the iOS 26 APIs only when built with the iOS 26 SDK (Swift 6.2) and running on iOS 26; otherwise a frosted material, so iOS 17–18 look right too. |
| **Universal app** | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`): adaptive grids, readable widths (820 pt, or 620 pt for forms, panels and flows) and page-sized sheets on iOS 18+. |
| **String Catalogs + `L10n.core`** | UI text lives in `.xcstrings` catalogs (12 languages). AppCore stays plain English so it builds on Linux; the app translates its strings at runtime with `L10n.core(_:)`, and `scripts/export-core-strings.py` registers them through generated `CoreStrings.swift` files (CI runs it with `--check`). |
| **RevenueCat in observer mode** | StoreKit 2 and the backend stay the source of truth for purchases and entitlements. `RevenueCatBridge` only records purchases (`recordPurchase`) and identifies the customer by our account ID, for subscription analytics. It needs `revenueCatAPIKey` (a public `appl_…` key, set now), and it's configured only for buyers: at the first purchase tap (`AppModel.appAccountToken()`), or at launch when the Apple Account already has our transactions (so renewals and Ask to Buy approvals are recorded). "Delete my data" and signing out log it out; the backend deletes the RevenueCat customers of a deleted account (`_shared/revenuecat.ts`). |
| **Demo mode** | With no backend configured, `DemoAIImageService` simulates results with Core Image and clearly stamps them "DEMO PREVIEW". Design, QA and App Review previews work without keys. |
| **Anonymous auth** | No sign-up wall (Guideline 5.1.1(v)). The anonymous user is created lazily (the first consented cloud job or a purchase), never at launch, and the balance is fetched only for an existing session. Purchases bind to the user through `appAccountToken`. Account deletion is in-app: server first (never signing up just to delete), then a full local reset. |

## AI job lifecycle

```
App                          ai-image (Edge)                         Postgres                 xAI
 │ POST {operation,…}  ──────► validate · policy · rate limit
 │                             insert job ──────────────────────────► jobs(queued)
 │                             reserve_credits ─────────────────────► wallet −cost, ledger hold
 │ ◄──── 202 {job_id, queued, credits_remaining}
 │                             in the background (waitUntil) ───────► jobs(processing)
 │                             POST /v1/images/{generations|edits} ─────────────────────────► Grok Imagine
 │                             b64 results, moderated by xAI ◄──────────────────────────────┘
 │                             NSFW check (when FAL_KEY is set) ────► jobs(completed, outputs)
 │ GET ?job_id (1s, 1s, 1.5s…) ► read job
 │ ◄──── {completed, outputs:[base64]}                 (failure → jobs(failed) + release_credits)
 │ DELETE ?job_id ("got it") ─► clear the results ──────────────────► outputs = null
 │ editor/result → export with IPTC provenance
```

With `AI_PROVIDER=fal`, the job goes to fal's queue instead (`queue.fal.run`), each poll asks fal for its status, and the outputs are fal CDN links that expire after an hour.

**Failure modes**
- Provider error, safety block, timeout (3 min for xAI, 10 min for fal, server-side) or user cancel → `release_credits(job)`: an exact, idempotent refund.
- `sweep_jobs()` (pg_cron) refunds jobs whose client disappeared and clears any outputs still stored after an hour.
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
- xAI results come back as base64 and stay on the job row only until the app confirms the download (`DELETE` on the completed job), then they're cleared; `sweep_jobs()` clears any left after an hour. xAI doesn't train on API data without permission. **Before launch, switch on Zero Data Retention in the xAI console** (selfies are personal data). Each request carries a one-way user tag (a shortened SHA-256 of the user id), so xAI can flag abuse without learning who the user is.
- fal outputs expire after 1 hour, and fal's request history is disabled.
- Effects, Auto, RAW development, Best shot and video editing never leave the device.
- RevenueCat receives purchase records, our account ID and basic device and app information, never photos, prompts or results.
- The library lives on the device with `completeFileProtection`. Tokens are in the Keychain (`AfterFirstUnlockThisDeviceOnly`).

**Safety:** a layered stack.
1. Client prompt policy (`ContentPolicy`, all 12 app languages): sexual and undressing requests, revealing clothing, and for photo edits face/body reshaping, skin-tone changes, skin retouching, looks rating and humiliating edits. Checked before the consent sheet or paywall opens.
2. Server prompt policy (`_shared/policy.ts`, the same terms via the generated `_shared/policy-terms.json`; shared test vectors in `_shared/policy-vectors.json`). The server also appends the edit guard (`PromptBuilder.editGuard`: keep faces, body shapes, skin tone, skin texture and age; clothing at least as modest) to every Magic Edit.
3. Server-side template recipes (prompt tampering is impossible).
4. Provider moderation: xAI drops filtered outputs (`respect_moderation: false`); fal runs with `safety_tolerance: "2"`.
5. Output NSFW check (on by default; runs on fal when `FAL_KEY` is set, otherwise xAI's moderation is the output check).
6. "Report this image".

## Testing & CI

| Layer | How | Where |
|---|---|---|
| AppCore (contract, credits, catalog sync, policy in every app language, polling, deep links, widget snapshot, developer-mode providers incl. xAI, Auto adjust, silence cutting) | 100 XCTest cases, run on Linux (Swift 6.1 container) | `ci.yml › core` |
| Edge Functions | `deno fmt --check`, `deno lint`, `deno check` (strict) | `ci.yml › backend` |
| SQL ledger | Migration + behavioural tests on PostgreSQL: holds, refunds, packs, rollover, sweeper, RLS | `ci.yml › backend` |
| Docs and strings | Legal copies match `legal/` (`build-legal.py --check`); AppCore strings registered for translation (`export-core-strings.py --check`) | `ci.yml › docs` |
| iOS app | `xcodebuild build` (unsigned, generic iOS) on macOS | `ci.yml › ios` |
| Visual | Simulator screenshots of every key screen (DEBUG screenshot scenes) | `screenshots.yml` |

## Configuration

`ios/App/Resources/AppConfig.json` holds the backend URL and anon key, the provider name shown in the consent sheet (`aiProviderName`, now "xAI (Grok Imagine)"), the retention hours, the legal URLs, the support email, the App Store ID and `websiteURL` (the invite card's QR code and share captions link to the App Store page, or to the website until it exists), the optional Meta App ID for direct Instagram Stories (`instagramAppID`), the share hashtags and RevenueCat's public SDK key (`revenueCatAPIKey`; empty turns RevenueCat off). With an empty `backendBaseURL` the app runs in **demo mode**.
