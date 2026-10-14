# 06 · Roadmap & task breakdown

Legend: ✅ done in this repository · ⏳ next · 🔭 later

## Phase 0 — Research & definition ✅

- ✅ Market & competitor research: 15 apps, user loves and pains, trends, monetization benchmarks → [01](01-market-research.md)
- ✅ Brand & design research: hue map, palettes with WCAG checks, typography, naming, UX patterns, icon → [research](research/brand-and-design.md)
- ✅ AI technology & compliance research: models, fal.ai, Supabase, Apple frameworks, App Review, EU AI Act → [research](research/tech-and-compliance.md)
- ✅ Name decision: **Glowlit** (domain screen) · palette **Blush** (pink, replacing the original Golden Hour amber) with **Aura** accents · **Poppins** + New York Italic accents (Bricolage Grotesque until Oct 2026) · icon **Glow Print**, colorful Aura edition (Oct 2026; was Sunrise Split) → [02](02-brand-identity.md)
- ✅ Product spec: positioning, features, flows, pricing, unit economics, KPIs → [03](03-product-spec.md)

## Phase 1 — Foundation ✅

- ✅ Xcode 16+ project (synchronized folder), shared scheme, StoreKit test configuration
- ✅ `AppCore` package
  - API contract, credit wallet, catalogs, prompt builder, content policy, polling
  - 110 unit tests (incl. crop geometry, developer-mode AI providers with xAI, the legal Markdown parser, widget/deep-link helpers, notification and rating rules, accounts, the prompt policy in every app language, Auto adjust and silence cutting), run on Linux and macOS
- ✅ Design system
  - Tokens: palette, type, metrics
  - Components: buttons, chips, badges, cards, aurora background, generating overlay, before/after slider, template card, toast, share sheet
- ✅ Bundled fonts: Poppins Medium, SemiBold, Bold and ExtraBold, OFL licence included
- ✅ App icon (1024 px) + accent color + privacy manifest + `AppConfig.json`

## Phase 2 — MVP features ✅

- ✅ Onboarding: value pages, interests, **free on-device "try it on your photo"**, soft paywall
- ✅ Explicit AI consent (5.1.2(i)), revocable
- ✅ Explore: hero, quick tools, personalised template rows
- ✅ Editor
  - Tools: Magic Edit, Styles, Enhance, Remove BG (on-device), Erase (brush mask), Adjust (on-device), Crop (on-device: posting shapes, rotate, mirror, straighten)
  - Undo/redo, hold-to-compare, before/after slider, pinch and double-tap zoom on the canvas
  - 🔭 Zoom in Erase's brush canvas (two fingers pan and zoom, one finger paints)
  - Free "Retry" (Likeness Lock), save and share with provenance
- ✅ Create: prompt, styles, aspect ratios, multi-image (Pro), "Surprise me", "Enhance prompt", results, report
- ✅ My Works library (SwiftData + protected files)
- ✅ Paywall
  - Plans: annual with trial (preselected) and monthly; credit packs
  - Trial timeline and reminder notification; restore
  - Compliant copy (3.1.2)
- ✅ Settings: membership, credits, consent, delete creations, delete account, legal, acknowledgements
- ✅ Demo mode: the full app works offline with simulated, clearly labelled results
- ✅ Motion and details: staggered reveals, springy buttons, twinkling hearts and sparkles, orbiting charms while generating, a before/after "peek"; all respect Reduce Motion
- ✅ Widgets: Today's trend and My glow (Home and Lock Screen), App Group snapshot, `glowlit://` deep links
- ✅ Live Activity: Dynamic Island (compact, expanded, minimal) and Lock Screen progress for cloud jobs
- ✅ Audit → [07](07-audit-and-differentiators.md): sharp lookbook collection pages, double-tap to heart, opt-in notifications with quiet and school hours, happy-moment rating prompts
- ✅ Differentiators: likeness check, Best shot, Help me pick, kindness reminder, visible AI-edited label
- ✅ Optional Sign in with Apple: account merge (`merge_accounts`), Apple token revocation on deletion

## Phase 3 — Backend ✅ (code) / ⏳ (deploy)

- ✅ Supabase schema
  - Tables: wallets, append-only ledger, jobs, entitlements
  - RLS; atomic `reserve`/`release`/`grant` functions; sweeper
- ✅ Edge Functions: `ai-image` (create/poll/cancel/balance), `credits-redeem`, `account`
- ✅ xAI integration (default provider): Grok Imagine `grok-imagine-image-2.0` at 1k, low quality for free users and medium for Pro; requests run in the background (`EdgeRuntime.waitUntil`); results are returned inline and cleared once the app confirms the download
- ✅ fal.ai integration (alternative, `AI_PROVIDER=fal`)
  - Queue API; one model per operation; outputs expire after 1 hour; no request history
- ✅ Apple JWS verification (App Store Server Library); entitlement binding
- ✅ Safety
  - Server prompt policy; server-only template recipes; strict model safety; output NSFW check
- ✅ CI: Deno fmt/lint/check plus SQL ledger tests on PostgreSQL
- ⏳ Create the Supabase project, set secrets (`XAI_API_KEY`), deploy, and schedule `sweep_jobs` → [backend/README.md](../backend/README.md)
- ⏳ Switch on **Zero Data Retention** for the team in the xAI console (selfies are personal data)
- ⏳ Point `AppConfig.json` at the project; run end-to-end on TestFlight
- ⏳ Check xAI's current prices and latency; if fal is used, verify it accepts data-URI inputs on every endpoint

## Phase 4 — Launch readiness ⏳

**Legal and brand**
- ⏳ Clear the name **Glowlit**: App Store/Play search; USPTO/EUIPO classes 9 and 42; social handles
- ⏳ Register `glowlit.app`
- ✅ Drafted Terms of Use (EULA), Privacy Policy, Acceptable Use Policy (EN/TR) and the KVKK notice, bundled in the app and published under `docs/legal/` → [legal/README.md](../legal/README.md)
- ⏳ Lawyer review, fill in `legal/config.json`, publish at stable URLs, sign DPAs and KVKK standard contracts

**App Store**
- ⏳ App Store Connect setup
  - Bundle id `app.glowlit.ios`
  - Products: `app.glowlit.pro.yearly` ($39.99, 7-day free trial), `app.glowlit.pro.monthly` ($5.99, first month $1.99 introductory offer), `app.glowlit.credits.30` ($2.99), `app.glowlit.credits.100` ($7.99)
  - Set `APPLE_APP_ID`
- ✅ RevenueCat project created; public SDK key in `AppConfig.json` (observer mode, on in builds)
- ⏳ Upload the App Store Connect in-app purchase key (.p8) in RevenueCat (owner)
- ⏳ App Store Server Notifications V2 endpoint for refunds and revocations
- ⏳ Turn on Sign in with Apple for the app id, enable the Apple provider in Supabase, set `APPLE_TEAM_ID` / `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY`, and test sign-in and the merge on two devices
- ⏳ Age rating questionnaire (target 13+/16+) and the Declared Age Range API
- ✅ "Glow Print" app icon, colorful Aura edition, with dark and tinted variants (`scripts/render-brand-assets.py`)
- ⏳ Build with the latest SDK (iOS 26/27); Icon Composer `.icon` with clear variants
- ✅ App Store copy (EN/TR), 8 generated screenshots per language, social images → [marketing](marketing/README.md)
- ⏳ Recapture the screenshots with real AI results (needs an AI key), including the new effects and Cover star scenes in `screenshot-captions.json`; header asset, Custom Product Pages
- ⏳ Localized App Store metadata and screenshots for the app's other languages

**Hardening and quality**
- ⏳ App Attest + DeviceCheck + `appTransactionID` binding against free-credit farming
- ⏳ QA identity fidelity across skin tones and hair textures; red-team the safety filters and keep evidence logs
- ⏳ Replace the template card art with real before/after thumbnails (diverse casting)
- ✅ Backend `report` endpoint + `reports` table (12-month retention) wired to "Report this image"
- ⏳ Ban list and an abuse inbox/review routine (1.2)

## Phase 5 — Growth 🔭

- 🔭 Likeness Lock v2: 3–5 selfie profile with an identity-similarity check before showing results
- 🔭 Packs: Headshot pack (20 photos), Restore pack, seasonal trend packs
- 🔭 Motion: short video versions of templates (figurine → spin, polaroid → develop)
- 🔭 Remote template catalog with thumbnails, A/B tests and a "Trending this week" CPP feed
- 🔭 C2PA Content Credentials (server-signed) (the optional visible "AI-edited" label has shipped)
- 🔭 Webhooks or Realtime push instead of polling; push-updated Live Activities
- 🔭 Interactive widgets (iOS 17+)
- 🔭 Steal the look (reference photo) with Likeness Lock; one look across a whole photo dump; alternate app icons
- 🔭 Optional iCloud sync of My Works (the user's own iCloud, never our servers)
- 🔭 iPhone Duo adaptive layouts (12 languages and iPad shipped in Phase 6)
- 🔭 Swift 6 strict concurrency; UI tests; snapshot tests
- 🔭 Privacy-friendly product analytics, paywall experiments, Apple Ads (subscription analytics shipped with RevenueCat in Phase 6)

## Phase 5 — Girls-first redesign and growth ✅ (October 2026)

- ✅ Pink "Blush" palette (sampled from the owner's reference brand), light-first with Dark and Automatic appearances
- ✅ Girls-first catalog: 36 year-round looks in Trending, Glow-up looks, Aesthetic edits, Dreamy portraits, Art, Pet portraits and For your shop, plus seasonal looks (Halloween, winter, Galentine's) promoted on Home in season; 14 styles incl. Pastel Dream and Kawaii; identity clause now protects body shape too
- ✅ Share composer: Instagram Stories, before/after collage, 9:16 story card, caption and hashtags, copy image, AI-label tip
- ✅ Favorites in My Works, sparkle celebration, editorial serif accents, Settings › Appearance and "Spread the glow"
- ✅ Developer AI key slot (`ios/Config/Secrets.xcconfig`, DEBUG only) with direct xAI, fal.ai, OpenAI and Gemini adapters
- ✅ Landing page (`web/`) with legal pages and a manual GitHub Pages workflow
- ⏳ Add the owner's AI key and verify real results end to end; recapture marketing screenshots
- 🔭 Optional: Meta App ID for direct Instagram Stories sharing (`instagramAppID`); Stories already works through the share sheet without it
- ✅ Typeface: display font switched to Poppins (SIL OFL)
- 🔭 Backend adapters for OpenAI/Gemini if production moves off xAI and fal.ai

## Phase 6 — Video, retro effects, xAI and 12 languages ✅ (October 2026)

- ✅ Simple on-device video editor: auto-cut silences (jump cut), retro effects with their date stamps, trim, save to Photos or share; free, no watermark, no ending clip, clips up to 5 minutes (`Features/Video`, `VideoEngine`, AppCore `SilenceCutter`)
- ✅ Free on-device retro photo effects (VHS '86, Disposable '98, Kira Kira, Digicam '04, Instant '82, Glamour '92, Neon '84, Throwback '16, Camcorder '06, Film Still) with an optional date stamp, border, letterbox or camcorder display; one-tap Auto adjust; RAW photos developed automatically (`AutoDevelop`, AppCore `AutoAdjust`)
- ✅ xAI Grok Imagine as the default AI provider, fal.ai as the alternative; Pro's benefit is now "Our best-quality AI, no watermark"
- ✅ New prices: Pro Yearly $39.99 with a 7-day free trial (≈ $3.33/month), Pro Monthly $5.99 (first month $1.99 if eligible), packs 30 for $2.99 and 100 for $7.99
- ✅ Share formats: Cover star magazine cover (masthead behind the head with Vision person segmentation) and date-stamped Photo strip; Instagram Stories without a Meta App ID; "Glow together" invite card with a QR code
- ✅ Poppins display font; colorful Aura edition of the Glow Print icon; Aura accents for the icon, share cards and sticker-style template art (UI text and controls stay Blush)
- ✅ iOS 26 Liquid Glass tab bar and editor toolbar with a frosted fallback on iOS 17–18; universal iPhone and iPad app
- ✅ First-run guided tour: 7 spotlight steps, shown once after onboarding, replayable from Settings → "Show me around"
- ✅ 12 languages via String Catalogs, a Settings "Language" row, `L10n.core` for AppCore strings and `scripts/export-core-strings.py` (checked in CI); the prompt policy blocks sexual requests in every app language
- ✅ RevenueCat in observer mode for subscription analytics
- ✅ Control Center controls on iOS 18 (Magic Edit, Retro effects, Edit a video), also for the Lock Screen and the Action button; the "My glow" widget's shortcuts are now Magic, Effects and Video
- ✅ Free on-device edits (effects, adjustments, cut-outs) save without a watermark; free cloud AI results keep the small mark
- ⏳ Native-speaker review of the 11 translations
- ✅ App Store screenshots in English and Turkish for iPhone 6.9" and iPad 13" (Magic Edit, trends, effects, Cover star, sharing, gallery, privacy, pricing)
- ⏳ Refresh the README gallery with the new screens (video editor, invite card, tour)

