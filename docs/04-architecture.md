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
└───────────┬──────────────────────┬──────────────────────┬──────────────────────┬───────────┘
            │ api.x.ai             │ api.anthropic.com    │ queue.fal.run,       │ JWS
            │ (Bearer key)         │ (safety check)       │ NSFW check           │ verification
      ┌─────▼──────┐         ┌─────▼──────┐         ┌─────▼──────┐         ┌─────▼──────┐
      │    xAI     │         │ Anthropic  │         │   fal.ai   │         │   Apple    │
      │ (default)  │         │  Claude    │         │ (optional) │         │  root CAs  │
      └────────────┘         └────────────┘         └────────────┘         └────────────┘
      Grok Imagine           Haiku 5.5 checks       Nano Banana 2,
      image 2.0, 1k          photos to edit         SeedVR2, object
                             and every result       removal
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
| **Async job API** | Generations take 5–40 s, but Edge Functions shouldn't hold connections open. The function answers 202 at once: an xAI request then runs in the background (`EdgeRuntime.waitUntil`), while a fal job waits on fal's queue. The app polls with back-off (1 s → 3 s, 180 s deadline), keeps polling through dropped connections (2 s → 13 s, for up to two minutes without an answer) and cancels server-side if the user leaves or the job runs past the deadline. |
| **Server-authoritative credits** | The client mirrors the rules for instant UI and demo mode. In production the server reserves, captures and refunds credits atomically in SQL. |
| **Operations, not models** | The app sends `operation` + `template_id`; the server picks the provider, model and prompt (`_shared/xai.ts`, `_shared/fal.ts`). Models can be hot-swapped without an app update, and provider keys can't be misused. |
| **xAI by default, fal.ai as the alternative** | Grok Imagine (`grok-imagine-image-2.0` at 1k; low quality for free users, medium for Pro) is the best quality for the price, about $0.06 per cloud operation. `AI_PROVIDER=fal` switches back without an app release. |
| **Claude as the independent safety check** | A second vendor's model catches what the image model's own filter misses, and checks the photo before an edit is paid for at the image model. Claude can't make or edit images, so it only classifies: Haiku 5.5 (`claude-haiku-5-5`) at $0.10 / $0.50 per million tokens, about $0.0002 a check, through the official TypeScript SDK with structured JSON output and thinking off. It replaced the plan to use fal.ai's classifier (no third image vendor, no `FAL_KEY`). |
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
App                          ai-image (Edge)                         Postgres                 xAI · Anthropic
 │ POST {operation,…}  ──────► validate · policy · rate limit
 │                             insert job ──────────────────────────► jobs(queued)
 │                             reserve_credits ─────────────────────► wallet −cost, ledger hold
 │ ◄──── 202 {job_id, queued, credits_remaining}
 │                             in the background (waitUntil) ───────► jobs(processing)
 │                             edits: Claude checks the photo (fails closed) ───────────────► Anthropic
 │                             POST /v1/images/{generations|edits} ─────────────────────────► Grok Imagine
 │                             b64 results, moderated by xAI ◄──────────────────────────────┘
 │                             output check, then Claude on every result ───────────────────► Anthropic
 │                             both pass (each fails closed) ───────► jobs(completed, outputs)
 │ GET ?job_id (1s, 1s, 1.5s…) ► read job
 │ ◄──── {completed, outputs:[base64], credits_remaining} ─ deliver_outputs() ─► delivered_at
 │                                                       (failure → jobs(failed) + release_credits)
 │ DELETE ?job_id ("got it") ─► clear the results ──────────────────► outputs = null
 │ editor/result → export with IPTC provenance
```

With `AI_PROVIDER=fal`, the job goes to fal's queue instead (`queue.fal.run`), each poll asks fal for its status, and the outputs are fal CDN links that expire after an hour.

**Failure modes**
- Provider error, safety block, timeout (3 min for xAI, 10 min for fal, server-side) or user cancel → `release_credits(job)`: an exact, idempotent refund.
- `sweep_jobs()` (pg_cron) refunds jobs whose client disappeared and clears any outputs still stored after an hour. A finished job whose results were never handed to the app is refunded then (or at once if the app cancels it); a delivered one the app never confirmed is refunded at most once a day per user.
- A 401 triggers one token refresh and retry.
- Network errors surface as friendly toasts. When the app stops waiting through a lost connection, it says the result didn't arrive and that an undelivered one is refunded automatically, and it sends no DELETE (one could read as "got it" if the results had been handed over in an answer that never arrived).

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
- With `ANTHROPIC_API_KEY` set, the photo of an edit and every result also go to Anthropic for the safety check, base64 or as the provider's link, and nothing else (no prompt, no user id). Anthropic deletes API inputs and outputs within 30 days, may keep content its systems flag for a usage-policy violation up to 2 years, and doesn't train on API data by default.
- fal outputs expire after 1 hour, and fal's request history is disabled.
- Effects, Auto, RAW development, Best shot and video editing never leave the device.
- RevenueCat receives purchase records, our account ID and basic device and app information, never photos, prompts or results.
- The library lives on the device with `completeFileProtectionUnlessOpen`, so a job that finishes after the device locks still saves; closed files stay unreadable until unlock (thumbnails retry when the app becomes active). The Mac uses `completeFileProtectionUntilFirstUserAuthentication` instead: FileVault encrypts its disk, and a locked screen would otherwise leave My Works blank. Each file carries a small XMP tag (operation, source, IPTC DigitalSourceType) so `LibraryStore` can rebuild My Works if the SwiftData store is damaged (versioned schema + migration plan; a damaged store is moved to `Corrupt-<date>/` and deleted after 30 days or with Delete my data; a full disk falls back to an in-memory library instead). Tokens are in the Keychain (`AfterFirstUnlockThisDeviceOnly`).

**Safety:** a layered stack.
1. Client prompt policy (`ContentPolicy`, all 12 app languages): sexual and undressing requests, revealing clothing, and for photo edits face/body reshaping, skin-tone changes, skin retouching, looks rating and humiliating edits. Checked before the consent sheet or paywall opens.
2. Server prompt policy (`_shared/policy.ts`, the same terms via the generated `_shared/policy-terms.json`; shared test vectors in `_shared/policy-vectors.json`). The server also appends the edit guard (`PromptBuilder.editGuard`: keep faces, body shapes, skin tone, skin texture and age; clothing at least as modest) to every Magic Edit.
3. Server-side template recipes (prompt tampering is impossible).
4. Provider moderation: xAI withholds the image data of anything it filters (`respect_moderation: false`); fal runs with `safety_tolerance: "2"`.
5. One output check on every result, failing closed (`_shared/moderation.ts`, no off switch): xAI's own verdict, where a filtered or missing image blocks the whole job (fal.ai's NSFW classifier instead only if `FAL_KEY` is set; it stays unset, and fal.ai isn't in the consent sheet). A flag, an error, a timeout or an unreadable answer blocks the result and refunds it.
6. An independent safety model on top of it, never instead (`_shared/safety.ts`): Claude when `ANTHROPIC_API_KEY` is set (`ANTHROPIC_SAFETY_MODEL`, default `claude-haiku-5-5`), else an xAI vision model when `XAI_SAFETY_MODEL` is set, else off; `ai-image` logs which checks are in force when it starts (`output check in force: xai + anthropic:claude-haiku-5-5`). It looks at the photo before an edit reaches the image model, and at every result after the output check, for nudity, sexual content, sexualised minors, graphic violence, self-harm and hate (text inside an image is part of the image, never an instruction). It fails closed: an error, a timeout (one retry, 20 s at most for a check, its retry included), a refusal, a cut-off answer, JSON that doesn't match the schema, or an image Claude isn't sent (only JPEG, PNG and WebP up to 10 MB as base64, the type read from the bytes; a HEIC photo, say) blocks the job and refunds it (`photo_check_failed` for the photo, `safety_check_failed` for results). A flagged photo is refunded without a strike (`input_blocked`: it can be an ordinary holiday snap); a flagged result is a strike.
7. "Report this image".

## Performance

Measured with `PerfProbe` (`App/PerfProbe.swift`, DEBUG builds, or Release with the `GL_PERF` condition): every launch prints process start → Explore's first frame; `-GLPerfBench <photo>` times decoding, effects, the encoders, Vision and the widget work on a 12 MP HEIC (4032 × 3024, Display P3), and `-GLPerfOpen <photo>` times a photo opening in the editor. Numbers below are from the iPhone 17 Pro simulator and the Mac Catalyst app on an M1 Mac (8 GB) that was building other branches at the same time, so they are relative, medians of several runs, and only comparable within a row. The bench also keeps every output's pixels and checks later builds against them.

| | Before | After |
|---|---|---|
| Launch → Explore's first frame (Release, simulator / Mac) | ~1.7 s / ~2.1 s | unchanged within noise |
| Memory at Explore's first frame (Release, simulator) | ~88 MB | ~59 MB |
| Open a 12 MP HEIC: decode + downsample (off the main actor) | 97 ms | 235 ms (one extra copy, see below) |
| Preview copy (1200 px) on the main actor when a tool opens | 146 ms | 18 ms, usually 0 (made in the background) |
| Effect at preview size (1200 px) | ~65 ms | ~65 ms (unchanged) |
| Effect at full size (2048 px), simulator / Mac | ~300 ms / 24 ms | ~125 ms / 34 ms |
| Effects strip (11 thumbnails) | 429 ms | 178 ms |
| One edit: preview, full-size effect, save to Photos and My Works (simulator / Mac) | 1065 ms / 632 ms | 352 ms / 193 ms |
| Saved file of an effect, filter or share design | PNG 2.8–6.8 MB (16 MB with the AI label) | JPEG 0.6–1.7 MB |
| Encoding a save (JPEG of a decoded photo / an effect) | 232 ms / 173 ms (PNG) | 38 ms / 27 ms |
| Editor step bitmaps (crop, hide faces, text, watermark) | 24 MB (16-bit float) | 12 MB (8-bit) |
| Vision when the editor opens (ideas / kindness check) | 337 ms / 161 ms | 114 ms / 14 ms |
| Main-actor work for the widgets after a save | ~200 ms | ~33 ms (SwiftData fetches only) |
| Peak memory of one edit (bench) | 158 MB | 174 MB |
| App bundle (simulator Release; the executable is 35 MB of it) | 41 MB | 41 MB |

What changed, in order of effect:

- **One plain copy of every decoded photo.** ImageIO's downsampled HEIC (and RGBA PNG/JPEG on the Mac) is converted again every time anything reads it: the canvas on the main thread, previews, Vision, effects, encoders. `ImageUtilities.decodedImage` now copies it once into an 8-bit bitmap off the main actor; AI results (`RemoteAIImageService`) and photos opened from My Works (`ImageStore.decoded`) go the same way. Opening costs one copy more; everything after it is 2–9× cheaper.
- **Opaque results are opaque.** Core Image and `UIGraphicsImageRenderer` hand back opaque pictures with an alpha channel (and 16-bit floats for wide colour), so effects, the AI label, cut-out backdrops and other steps were saved as large PNGs. Opaque results are drawn with `ImageUtilities.draw(…, opaque: true)` (8-bit, the photo's colour space, no alpha), Core Image renders known-opaque output with `settingAlphaOne`, and the encoders drop an alpha channel no pixel uses (`droppingUnusedAlpha`). Cut-outs and stickers stay PNG. Pixels are identical except the last part-pixel row of framed effects (now frame colour instead of see-through) and sub-level resampling differences in 8-bit steps (mean < 0.5 levels).
- **8-bit downscaling** in the photo's colour space (`ImageUtilities.redraw`): half the memory and no colour conversion.
- **Editor work off the main actor:** the preview copy is made in the background after each step and shared by Effects, Adjust, Crop and Hide faces; the strip's thumbnails render side by side; a stale strip is dropped.
- **Widgets:** the snapshot, the widget picture's JPEG and the WidgetKit reloads run in order on a utility queue.
- **Two Core Image contexts** for the whole app (`ImageFilters.context`, `ImageFilters.measuringContext`), instead of one per feature and one per call in the photo insights and QR codes.
- **Explore:** each template card's art is one flattened layer (`drawingGroup`), rows build their cards lazily, cards compare by value, and the credit pill observes credits itself (a `_printChanges` pass showed all forty cards rebuilt after launch when the storefront and wallet arrived).
- **Memory:** the photo insights cache no longer keeps closed photos alive (weak keys).

What didn't improve, or wasn't changed: launch time is dominated by loading system frameworks (~0.5 s before `main` in the simulator), SwiftData (~90 ms) and SwiftUI building the first screen, and stayed the same within the noise of this shared machine; `xctrace` hung when recording the simulator headless, so there is no Time Profiler breakdown. Explore's looping decorations (aurora, twinkles, glow sweep) use about 6% of one core while it sits idle; the aurora is 1–2 points of that and was kept as it looks. Opening the editor shows its first frame at about the same time (the extra copy moves work off the main thread rather than removing it). The bench's peak memory rose about 15 MB (the extra decoded copy while opening). Video export, captions and the app's size weren't changed; the probe can time an export with `-GLPerfVideo <clip>`.

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

`ios/App/Resources/AppConfig.json` holds the backend URL and anon key, the processors the consent sheet names (`aiProcessors`: Supabase, xAI (Grok Imagine) and Anthropic (Claude), with `consentVersion` 2), the retention hours, the legal URLs, the support email, the App Store ID and `websiteURL` (the invite card's QR code and share captions link to the App Store page, or to the website until it exists), the optional Meta App ID for direct Instagram Stories (`instagramAppID`), the share hashtags, RevenueCat's public SDK key (`revenueCatAPIKey`; empty turns RevenueCat off) and the AdMob ids (`ads`: the app id, the rewarded unit and the "After save interstitial" unit `ca-app-pub-2292230772061554/6797438012`, which the app shows at most 3 times a day (`InterstitialPacing`); an empty `interstitialUnitID` turns interstitials off). With an empty `backendBaseURL` the app runs in **demo mode**.

The consent sheet (`AIConsentView`) names no single company in its lead sentence: "we send the photo and text you choose to our servers and to the companies listed below, who process them for us", followed by the points (deleted from our servers within the retention hours; with a `safety` processor listed, deleted by our safety-check provider within 30 days unless flagged for breaking its rules; never used to train AI; never sold or shared for advertising; the on-device tools) and the list of the three processors with their roles: Supabase (our servers: AI jobs and credits), xAI (Grok Imagine) (creates and edits the images) and Anthropic (Claude) (checks photos she edits and every result for safety). A DEBUG developer key lists only its own provider.
