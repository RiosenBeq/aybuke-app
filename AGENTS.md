# Glowlit — guide for agents

> **Türkçe özet:** Glowlit, kız ve genç kadınlar (13+) için bir iPhone/iPad yapay zekâ fotoğraf düzenleyici ve görsel üreticisidir (Mac Catalyst ile Mac'te de çalışır). Bu dosya, projeye sonradan katılan yapay zekâ ajanlarının (ve geliştiricilerin) uygulamayı hızla anlaması için yazıldı: ne olduğu, kodun nerede durduğu, nasıl derlenip test edildiği, kurallar ve kalan işler. Ürün ve iş özeti için ayrıca [`docs/00-ozet-TR.md`](docs/00-ozet-TR.md).

Read this first, then the doc for your area (links below). Keep it current: when you change how something works, update the matching section here in the same change.

## 1. The product

**Glowlit — "Make it glow."** An iPhone and iPad app for girls and young women (13+), also built for the Mac with Mac Catalyst: AI photo editing and image creation, plus free on-device tools.

| Area | What it does |
|---|---|
| **Magic Edit** | "Say the change" ("give me pink hair"), then compare before/after; one free retry if the result doesn't look like you (Likeness Lock + an on-device likeness check) |
| **One-tap looks** | 36 year-round templates (Doll Box, Y2K Digicam, 80s Studio Portrait, Plushie Me, pet portraits…) in collections, plus seasonal looks (Halloween Oct 1–Nov 2, winter Dec 1–Jan 6, Galentine's Feb 1–14) that Home promotes only in season and the editor keeps all year (`SeasonalTheme`; DEBUG `-GLDate yyyy-MM-dd` fakes the day) |
| **Create** | Text to image with 14 styles, 5 sizes, up to 4 images with Pro; "Inspire me" and "Make it magic" written on the device by Apple Intelligence when available; "Create with Image Playground" (Apple's image maker, iOS 18.4+ on supported devices) |
| **Free on-device tools** | Ten retro effects from the 80s to the 2010s (incl. Camcorder '06 with a running timecode on video and Film Still with letterbox and a subtitle), Adjust with one-tap Auto, Crop (posting shapes, rotate, mirror, straighten), RAW auto-develop, Cut out (tap to pick the subject; colour, gradient, blurred-original or own-photo backgrounds; outlined stickers), Hide faces (blur, pixelate or cover other people's faces, with a "Hide their faces" button on the kindness reminder), Best shot (finds the selfie with the best light and focus), simple **video editor** (auto-cut silences, retro effects, trim) |
| **Sharing** | Photo, Before/After, 9:16 Story card, **Cover star** magazine cover, **Photo strip**, Which vibe?; Instagram Stories via the share sheet (no Meta App ID needed); "Glow together" invite card with a QR code |
| **Engagement** | Home/Lock Screen widgets, Dynamic Island Live Activity, iOS 18 Control Center controls, gentle local notifications (never at night or during school hours), first-run guided tour |
| **Accounts** | Anonymous by default; optional Sign in with Apple so Pro and credits follow the user |
| **Money** | Free: 3 AI credits/day. Pro Yearly $39.99 (7-day trial), Pro Monthly $5.99 (first month $1.99), packs 30/$2.99 and 100/$7.99. No weekly plans |
| **Privacy** | Explicit consent before any cloud AI; photos never train AI; results deleted after download (≤ 1 hour); xAI with Zero Data Retention; IPTC "made with AI" metadata on exports |
| **Languages** | English + Turkish, Spanish, Brazilian Portuguese, French, German, Italian, Russian, Japanese, Korean, Simplified Chinese, Indonesian |
| **Mac** | The same app on macOS 14+ (Mac Catalyst, iPad interface scaled to the Mac): menu bar (⌘N New Creation, ⌘O Open Photo…, ⌘1–⌘4 tabs, ⌘, Settings, Help › Contact support), drop a photo file on the window to edit it, Esc and ⌘S in the editors, one resizable window. Not on the Mac: the Live Activity and Instagram Stories sharing |

Brand: "Blush" palette (blush `#F7C1D9`, petal `#F8E0EA`, ink `#121212`) for UI; colorful "Aura" accents only for the icon, share cards and template art. Fonts: Poppins + New York Italic accent words. Details: [`docs/02-brand-identity.md`](docs/02-brand-identity.md).

## 2. Repository map

```
ios/
  App/                    SwiftUI app (iOS 17+, iPhone + iPad)
    App/                  AppModel (state, gates: consent → Pro → credits), RootView, AppConfig,
                          MacSupport (Mac menu bar, window, drag & drop), screenshot scenes (DEBUG),
                          CoreStrings.swift (generated)
    Features/             Home, Create, Edit (editor + panels), Video, Share, Library, Paywall,
                          Settings, Onboarding, Account, Legal, Tour
    Services/             AI (remote/direct/demo/on-device services, RetroEffects, AutoDevelop),
                          Video (VideoEngine), Sharing (renderers, cover/strip/invite), Store
                          (StoreKit 2 + RevenueCatBridge), Auth, Notifications, Persistence, Photos
    DesignSystem/         Palette, Typography (Text(styled:) accent), Metrics (readableWidth),
                          LiquidGlass, Motion, Components (TemplateArt, cards, chips…)
    Resources/            AppConfig.json, Localizable.xcstrings, InfoPlist.xcstrings, Legal/, Fonts/
  GlowlitWidgets/         Widgets, Live Activity, Control Center controls, own string catalog
  Packages/AppCore/       Pure-Foundation logic, tested on Linux: templates, styles, credits,
                          prompt policy, backend + direct-AI wire formats, silence cutter, auto adjust
  Config/                 Info.plist, entitlements (iOS, and *-macOS with the App Sandbox), xcconfigs
                          (Secrets.xcconfig is git-ignored)
  StoreKit/               Products.storekit for local testing
backend/                  Supabase: SQL migrations + tests, Edge Functions (ai-image, credits-redeem,
                          account, report; _shared/xai.ts, fal.ts, policy.ts)
legal/                    Source of truth for Terms, Privacy, AUP, KVKK (EN/TR)
scripts/                  build-legal.py, export-core-strings.py, render-brand-assets.py,
                          marketing-images.py, screenshot-gallery.py
web/                      Landing page + generated legal pages (GitHub Pages)
docs/                     Product, architecture, compliance, roadmap, marketing, SUPABASE-TODO.md
```

Xcode uses file-system-synchronized groups: new files under `ios/App/` or `ios/GlowlitWidgets/` join their target automatically.

## 3. Build, run, test

```bash
# App in the simulator (pass an explicit simulator id)
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug \
  -destination 'id=<simulator-udid>' -quiet

# CI-style device build without signing
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# Mac Catalyst build without signing (also in CI)
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO -quiet

# AppCore unit tests (also run on Linux in CI)
swift test --package-path ios/Packages/AppCore

# Backend: Deno checks (CI) and SQL tests on a throwaway Postgres
(cd backend/supabase/functions && deno fmt --check && deno lint && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts report/index.ts && deno test _shared/)
backend/scripts/test-db.sh

# Generated files must stay in sync (CI checks both)
python3 scripts/build-legal.py --check
python3 scripts/export-core-strings.py --check
python3 scripts/check-honest-copy.py      # no unsupported claims, device-neutral app copy (CI)
python3 scripts/check-release-config.py   # release blockers: demo mode, legal placeholders, website URL
                                          # (CI runs it with --report; upload-app-store.sh with --online)

# Archive and upload to App Store Connect / TestFlight with an API key
# (key file in ~/.appstoreconnect/private_keys/; ids from Users and Access → Integrations)
# It stops on release blockers; GL_PREVIEW_BUILD=1 allows a deliberate preview (never submit it for review)
ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/upload-app-store.sh
PLATFORM=mac ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/upload-app-store.sh   # Mac App Store
```

Running the Mac app without an Apple account in Xcode: sign ad hoc (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`) and point `CODE_SIGN_ENTITLEMENTS` at a scratch copy of `Config/Glowlit-macOS.entitlements` without the App Group and Sign in with Apple keys (they need a provisioning profile; never commit that). Keep the App Sandbox on: unsandboxed, SwiftData would use `~/Library/Application Support/default.store`, which other apps can share. Screenshot scenes work there too: `open <…>/Debug-maccatalyst/Glowlit.app --args -GLScreenshotScene home`.

Deterministic screens for QA and marketing (DEBUG builds): launch with `-GLScreenshotScene <scene>` (see `ScreenshotScenes.swift`; e.g. `home`, `editor`, `effects`, `share -GLShareFormat cover`, `tour`, `invite`, `video -GLEffect camcorder06` on a generated clip), and `-AppleLanguages "(tr)" -AppleLocale tr` for another language; `-GLPrompt <text>` sets Create's prompt in that language. On the Mac add `-GLWindowSize 1600x1000` (UIKit points; a 1232×770 window) so every capture has the same size, and capture the window by id (`screencapture -x -o -l <CGWindowID>`). `scripts/marketing-images.py` turns captures into App Store images (iPhone 1290×2796, iPad 2064×2752, Mac 2880×1800).

## 4. How things work

- **AI modes** (`AppConfig.aiMode`): *backend* (production: Supabase Edge Functions → xAI `grok-imagine-image-2.0`, low quality for free and medium for Pro, 1k), *direct* (DEBUG only, key from `ios/Config/Secrets.xcconfig`, `GL_AI_PROVIDER = xai|fal|openai|gemini`), *demo* (no backend: simulated results stamped "DEMO PREVIEW"; the banner says "Preview build", accounts and reports are hidden or say they aren't on yet, and a demo build installed from the App Store turns purchases off). Jobs are async: POST → poll → download → DELETE to confirm, which clears results server-side.
- **On-device writer** (`Services/AI/OnDeviceWriter.swift`, `app.writer`): Apple's Foundation Models (iOS 26+, Apple Intelligence, supported language) write Create's "Inspire me" ideas and "Make it magic" prompt upgrades, and can write edit ideas and captions (`ideas(_:)`). No consent or credits (nothing leaves the device); every line passes `ContentPolicy`; when the model is unavailable, callers fall back to `CuratedIdeas` and the offline `PromptBuilder.enhance`.
- **Image Playground** (`Features/Create/ImagePlaygroundCreateButton.swift`, iOS 18.4+ and `supportsImagePlayground`): Apple's sheet with Apple's cartoon styles only, personalization off, no source image. It skips Glowlit's consent and credits (Apple's own feature, terms and limits); from iOS 27, where Apple may use Private Cloud Compute, a one-time Apple notice comes first. Results are saved with `Creation.source = imagePlayground`: no Glowlit mark, no report menu, no stored prompt, IPTC AI label on export.
- **Ideas for this photo** (`Features/Edit/EditorIdeasRow.swift`): Vision looks at the photo on device (`PhotoInsightsService`), and `LookSuggester` (AppCore, deterministic, never beauty looks or Glamour '92) picks a free effect, a look, a Magic Edit idea and a second effect. Effects and "Surprise me" apply at once for free; a look asks first and goes through the usual gates; under 13 only effects are offered. Magic Edit idea texts use `idea("…")`, which `export-core-strings.py` picks up. DEBUG: scene `ideas`, `-GLIdeasAction surprise`.
- **Age range** (`AgeBand`/`AgeDefaults` in AppCore, `AgeStepView`): asked once, before interests in onboarding (Apple's Declared Age Range on iOS 26+, otherwise neutral month and year menus); only the band, its source and date are stored, on the device. Under 13: on-device tools only (no Create tab, AI tools, paywall, account or RevenueCat). Under 18 and unknown: no automatic paywall, and the consent sheet's guardian step where `requiresGuardianStep`. A self-declared band can be raised only once a year. DEBUG: `-GLAgeBand <band>`, `-GLAgeMenus YES`, scene `age`.
- **Gates for every AI action:** age range → content policy (client + server, all app languages; checked before the consent sheet or paywall opens) → consent → Pro/credits. Credits are server-authoritative in production; failures are refunded exactly once.
- **Consent record:** `AIConsentRecord` (AppCore) stores the consent version and the processor names the sheet showed; it goes stale when `consentVersion` or `aiProcessors` in `AppConfig.json` change, which asks again. List a new provider there before the backend uses it.
- **Notifications and the Lock Screen:** local only, timed by `NotificationPlanner` (never 21:00–09:00 or in weekday school hours; the trial reminder lands at least 26 h before the trial ends and follows `PurchaseManager.trial`). Notifications, the Live Activity and widget titles never show her prompt, only catalog names. The Friday look and trend widget use `TemplateCatalog.pushPool` (free looks unless Pro, no makeup looks). Under 13 the widget snapshot's `cloudAIAllowed` turns widgets and the Magic Edit control into free on-device tools.
- **First run:** onboarding ends with Digicam '04 on her own photo (on-device); Keep editing opens the editor, Save keeps it, and the adult soft paywall waits for that first success; the tour starts when a paywall, account prompt or editor closes.
- **On-device tools** never need consent or credits and save without a watermark. Free cloud AI results carry a small mark; Pro removes it.
- **Provenance:** `Provenance` (AppCore) decides every export marking: the IPTC DigitalSourceType, the free mark, the AI hashtags and the "AI-edited" label. Pass it along whenever a result is re-opened (`openEditor(with:provenance:)`, `SharePayload.inheritedSourceType`, `Creation.provenance`); photos opened from files keep the marking they already carry (`PhotoDecoder` reads it). A Cut out placed on another photo sets `isComposite` (IPTC `composite`, not generative, so no AI label), which the Library keeps through `storedSourceType`. Export through `ImageExporter` / `PhotoLibrarySaver` only, never `pngData()` or `UIPasteboard.image` for AI content.
- **Localization:** String Catalogs. In SwiftUI use literals or `LocalizedStringKey`; in models use `String(localized:)`; AppCore text is English and translated at runtime with `L10n.core(_:)`, so after changing AppCore strings run `python3 scripts/export-core-strings.py`. Add or update translations with `xcodebuild -exportLocalizations` / `-importLocalizations`. Keep placeholders, `*accent*` pairs and line breaks identical. Legal documents exist in English and Turkish only.
- **Purchases:** StoreKit 2 in `PurchaseManager`; the backend verifies Apple-signed transactions. RevenueCat runs in observer mode for analytics only (project "Glowlit", public key in `AppConfig.json`). A purchase can come back *pending* (Ask to Buy, Texas SB 2420 parental consent): the paywall shows a neutral "Waiting for approval" state kept in memory only (StoreKit never reports a decline), and an approval arrives through `Transaction.updates` (`PurchaseManager.onLatePurchase`). To test it, select `ios/StoreKit/Products.storekit`, choose Editor › Enable Ask to Buy, then approve or decline in Debug › StoreKit › Manage Transactions; never commit the file with Ask to Buy switched on. Load failures are simulated with the file's StoreKit error settings (airplane mode has no effect on a local configuration).
- **Library (My Works):** SwiftData with a versioned schema (`CreationSchemaV1/V2` + `GlowlitMigrationPlan` in `LibraryStore.swift`); never change a stored property of `Creation` without a new frozen schema version and a migration stage. `LibraryStore.open()` never crashes: a damaged store is moved to `Corrupt-<date>/` and rebuilt from the image files (each carries an XMP tag with its operation and AI marking); a full disk falls back to an in-memory library. DEBUG: `-GLLibraryFault corrupt|diskFull`. Files use `completeFileProtectionUnlessOpen`. One window only (`UIApplicationSupportsMultipleScenes = false`).
- **Offline:** `AppModel.isCloudOffline` (NWPathMonitor; never in demo mode) shows a note on Home and Create and stops cloud actions before any overlay. Transport errors map through `NetworkFailure`. DEBUG: `-GLOffline YES` with a screenshot scene.
- **Shared data with widgets:** App Group `group.app.glowlit.shared`; deep links `glowlit://…` (`GlowDeepLink` in AppCore).
- **Layout:** universal; use `.readableWidth()` for wide screens and `pageSheetSizing()` for big sheets; Liquid Glass only behind `#if compiler(>=6.2)` + `#available(iOS 26, *)`. On the Mac the tabs sit in the title bar, so full-window covers (editor, video editor) hide them with `hidesMacTabs`.
- **Mac (Mac Catalyst):** both targets set `SUPPORTS_MACCATALYST` and keep `TARGETED_DEVICE_FAMILY = 1,2` ("Scale Interface to Match iPad", macOS 14+) and the iOS bundle ids (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`, so purchases are universal). macOS signs with `Config/*-macOS.entitlements` (App Sandbox, network client, user-selected files, Photos library, App Group, Sign in with Apple for the app) through `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`. `App/MacSupport.swift` has the menu bar (`GlowlitCommands`, attached on the Mac only), the window setup (no title text, 900×640 minimum), photo drag & drop and Mac-only shortcuts; share sheets go through `.shareSheet(item:)`, a popover on the Mac. Not on the Mac: the Live Activity (ActivityKit is unavailable there, so a finished job uses the opt-in notification) and Instagram Stories (the share menu takes its place); the Control Center controls reach the Mac build only with the Xcode 26 SDK. Use `#if targetEnvironment(macCatalyst)` for APIs, but `Platform.isMac` at runtime for Mac wording ("on your Mac", "System Settings"), so `-exportLocalizations`, which builds for iOS, still extracts it.

## 5. Rules

- **Never commit or print secrets.** AI keys live in Supabase Edge Function secrets or the git-ignored `ios/Config/Secrets.xcconfig`. Public-by-design values (Supabase anon key, RevenueCat `appl_…` key) may go in `AppConfig.json`.
- Don't commit `.claude/`. Don't add personal email addresses to public files.
- **Teen safety:** no sexual, undressing, revealing-clothing, humiliating or body/face/skin-reshaping features or prompts. The prompt policy lives in `ContentPolicy.swift` (terms per category, all app languages, subject-bound so "slim gold necklace" still works); after changing it run `scripts/export-catalog.sh`, which writes `_shared/policy-terms.json` for `policy.ts`, and add cases to `_shared/policy-vectors.json` (run by both `swift test` and `deno test`). Every Magic Edit ends with `PromptBuilder.editGuard` (the server appends it too). Template prompts keep identity, skin tone and body unchanged and outfits age-appropriate.
- **Honest copy:** claims in the app, website, App Store text and legal documents must match the code (example: there is no remote template catalog, so never promise new looks without an app update). Don't name competitors in user-facing copy.
- **Legal:** edit `legal/` only, then run `python3 scripts/build-legal.py`. Adding a data processor means updating the privacy policies (EN, TR, KVKK) in the same change.
- Match the surrounding code style: SwiftUI + Observation, sparse comments that explain *why*, Blush palette tokens, `Text(styled:)` for headlines with one accent word.
- Commit messages: imperative summary, short body, and the co-author trailer used in this repo's history.

## 6. Status (October 2026) and what's next

Done: the app, widgets, Live Activity, controls, video editor, effects, share designs, guided tour, 12 languages, iPad, Mac (Mac Catalyst build: menu bar, drag & drop, App Sandbox, Mac icon sizes), xAI backend code, RevenueCat dashboard (project, App Store app, products, `pro` entitlement, `default` offering), App Store metadata in 13 locales ([`docs/marketing/app-store-metadata.json`](docs/marketing/app-store-metadata.json)). Work happens on branch `pink-girls-redesign` (PR #1 into `main`).

Next, in order:
1. **Supabase** — postponed by the owner; every step is in [`docs/SUPABASE-TODO.md`](docs/SUPABASE-TODO.md). Until it's live, AI runs in demo mode, so don't submit to App Review before it is.
2. **Signing and upload** — Xcode has no Apple account signed in, so builds go up with an App Store Connect API key: `scripts/upload-app-store.sh`, with `PLATFORM=mac` for the Mac build (automatic signing; it registers the bundle ids `app.glowlit.ios` / `app.glowlit.ios.widgets`, the App Group and Sign in with Apple for team `CBTKNY3LFC`). It needs the key's Issuer ID and an existing app record (the API can't create apps). Free disk space first: an archive needs about 2 GB.
3. **App Store Connect** (owner signs in; every field is in [`docs/marketing/app-store-connect-setup.md`](docs/marketing/app-store-connect-setup.md)): app record, subscriptions group "Glowlit Pro" (`app.glowlit.pro.yearly` with a 7-day free trial, `app.glowlit.pro.monthly` with a $1.99 first month), consumables `app.glowlit.credits.30` / `.100`, metadata from the JSON above, screenshots, App Privacy answers, age rating, and exclude mainland China (generative-AI apps need a government licence there). For the Mac: add the macOS platform to the same record, with Mac screenshots and a description without the Lock Screen and Dynamic Island lines. Final "Submit for Review" needs the owner's go-ahead.
4. **Website / legal URLs** — enable GitHub Pages for `web/` (owner approval) so the privacy policy and support URLs resolve; then set `websiteURL`, `privacyPolicyURL`, `termsURL` and, after release, `appStoreID` in `AppConfig.json`.
5. Native-speaker review of translations; a remote template catalog; free on-device captions for videos (see [`docs/06-roadmap.md`](docs/06-roadmap.md)).

## 7. Further reading

- Product spec and unit economics: [`docs/03-product-spec.md`](docs/03-product-spec.md)
- Architecture: [`docs/04-architecture.md`](docs/04-architecture.md)
- Compliance (App Review, GDPR/KVKK, EU AI Act, minors): [`docs/05-compliance.md`](docs/05-compliance.md)
- Backend setup and costs: [`backend/README.md`](backend/README.md)
- Marketing kit and listings: [`docs/marketing/`](docs/marketing/)
