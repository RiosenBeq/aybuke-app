# 06 · Roadmap & task breakdown

Legend: ✅ done in this repository · ⏳ next · 🔭 later

## Phase 0 — Research & definition ✅

- ✅ Market & competitor research: 15 apps, user loves and pains, trends, monetization benchmarks → [01](01-market-research.md)
- ✅ Brand & design research: hue map, palettes with WCAG checks, typography, naming, UX patterns, icon → [research](research/brand-and-design.md)
- ✅ AI technology & compliance research: models, fal.ai, Supabase, Apple frameworks, App Review, EU AI Act → [research](research/tech-and-compliance.md)
- ✅ Name decision: **Glowlit** (domain screen) · palette **Golden Hour** · **Bricolage Grotesque** · icon **Sunrise Split** → [02](02-brand-identity.md)
- ✅ Product spec: positioning, features, flows, pricing, unit economics, KPIs → [03](03-product-spec.md)

## Phase 1 — Foundation ✅

- ✅ Xcode 16+ project (synchronized folder), shared scheme, StoreKit test configuration
- ✅ `AppCore` package
  - API contract, credit wallet, catalogs, prompt builder, content policy, polling
  - 48 unit tests, run on Linux and macOS
- ✅ Design system
  - Tokens: palette, type, metrics
  - Components: buttons, chips, badges, cards, aurora background, generating overlay, before/after slider, template card, toast, share sheet
- ✅ Bundled fonts: static cuts from the variable font, OFL licence included
- ✅ App icon (1024 px) + accent color + privacy manifest + `AppConfig.json`

## Phase 2 — MVP features ✅

- ✅ Onboarding: value pages, interests, **free on-device "try it on your photo"**, soft paywall
- ✅ Explicit AI consent (5.1.2(i)), revocable
- ✅ Explore: hero, quick tools, personalised template rows
- ✅ Editor
  - Tools: Magic Edit, Styles, Enhance, Remove BG (on-device), Erase (brush mask), Adjust (on-device)
  - Undo/redo, hold-to-compare, before/after slider
  - Free "Retry" (Likeness Lock), save and share with provenance
- ✅ Create: prompt, styles, aspect ratios, multi-image (Pro), "Surprise me", "Enhance prompt", results, report
- ✅ My Works library (SwiftData + protected files)
- ✅ Paywall
  - Plans: annual with trial (preselected) and monthly; credit packs
  - Trial timeline and reminder notification; restore
  - Compliant copy (3.1.2)
- ✅ Settings: membership, credits, consent, delete creations, delete account, legal, acknowledgements
- ✅ Demo mode: the full app works offline with simulated, clearly labelled results

## Phase 3 — Backend ✅ (code) / ⏳ (deploy)

- ✅ Supabase schema
  - Tables: wallets, append-only ledger, jobs, entitlements
  - RLS; atomic `reserve`/`release`/`grant` functions; sweeper
- ✅ Edge Functions: `ai-image` (create/poll/cancel/balance), `credits-redeem`, `account`
- ✅ fal.ai integration
  - Queue API; one model per operation; outputs expire after 1 hour; no request history
- ✅ Apple JWS verification (App Store Server Library); entitlement binding
- ✅ Safety
  - Server prompt policy; server-only template recipes; strict model safety; output NSFW check
- ✅ CI: Deno fmt/lint/check plus SQL ledger tests on PostgreSQL
- ⏳ Create the Supabase project, set secrets, deploy, and schedule `sweep_jobs` → [backend/README.md](../backend/README.md)
- ⏳ Point `AppConfig.json` at the project; run end-to-end on TestFlight
- ⏳ Verify fal accepts data-URI inputs on every endpoint, and check current prices and latency

## Phase 4 — Launch readiness ⏳

**Legal and brand**
- ⏳ Clear the name **Glowlit**: App Store/Play search; USPTO/EUIPO classes 9 and 42; social handles
- ⏳ Register `glowlit.app`
- ⏳ Publish Privacy Policy, Terms of Use (EULA) and the support email

**App Store**
- ⏳ App Store Connect setup
  - Bundle id `app.glowlit.ios`
  - Products: `app.glowlit.pro.yearly` ($59.99, 7-day trial), `app.glowlit.pro.monthly` ($9.99), `app.glowlit.credits.30` ($4.99), `app.glowlit.credits.100` ($12.99)
  - Set `APPLE_APP_ID`
- ⏳ App Store Server Notifications V2 endpoint for refunds and revocations
- ⏳ Age rating questionnaire (target 13+/16+) and the Declared Age Range API
- ⏳ Build with the latest SDK (iOS 26/27); Icon Composer icon with dark, clear and tinted variants
- ⏳ App Store assets: title, subtitle, keywords, 6 screenshots, header asset, Custom Product Pages

**Hardening and quality**
- ⏳ App Attest + DeviceCheck + `appTransactionID` binding against free-credit farming
- ⏳ QA identity fidelity across skin tones and hair textures; red-team the safety filters and keep evidence logs
- ⏳ Replace the template card art with real before/after thumbnails (diverse casting)
- ⏳ Backend `report` endpoint, ban list and abuse inbox (1.2)

## Phase 5 — Growth 🔭

- 🔭 Likeness Lock v2: 3–5 selfie profile with an identity-similarity check before showing results
- 🔭 Packs: Headshot pack (20 photos), Restore pack, seasonal trend packs
- 🔭 Motion: short video versions of templates (figurine → spin, polaroid → develop)
- 🔭 Remote template catalog with thumbnails, A/B tests and a "Trending this week" CPP feed
- 🔭 C2PA Content Credentials (server-signed); optional visible "AI-edited" label
- 🔭 Fal webhooks instead of polling; Realtime push to the app
- 🔭 Localization (ES, PT-BR, DE, FR, TR); iPhone Duo adaptive layouts; iPad
- 🔭 Swift 6 strict concurrency; UI tests; snapshot tests
- 🔭 Analytics (privacy-friendly), paywall experiments, Apple Ads
