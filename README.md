# Glowlit — AI Photo Editor & Generator for iOS

![Glowlit](docs/assets/brand/brand-board.png)

**Glowlit** is an iPhone app for AI photo editing and AI image generation, **made for girls who glow**.

- **Say it, see it:** "give me pink hair", "add soft glam makeup", "put me in a pink dress".
- **One-tap looks:** 30 trends such as Doll Box, Y2K Digicam, Ballet Core, Fairy Princess and Restore Old Photo.
- **Dream it, create it:** turn any idea into art with 14 styles, from Pastel Dream and Kawaii to Watercolor.
- **Made to share:** one tap to Instagram Stories, before/after collages, 9:16 story cards and ready-made captions.
- **Free on your iPhone:** background removal and adjustments run on-device.

| Promise | What it means |
|---|---|
| **Likeness Lock** | Every look keeps the face, skin tone and body as they are, plus *"Doesn't look like you? Retry free."* No body-reshaping or skin-lightening features. |
| **Fair-Price Promise** | No weekly plan. Annual (7-day trial) or monthly plans, credit packs that never expire, rollover credits, exact refunds when a generation fails, and a reminder before the trial bills. |
| **Private by default** | Explicit consent before any cloud AI, high-privacy defaults designed with teens in mind, photos never used to train AI and deleted from servers within an hour. |
| **48-hour trend engine** | Template recipes live on the server, so new trends ship without an app update. |

> 🇹🇷 Türkçe özet: [docs/00-ozet-TR.md](docs/00-ozet-TR.md)

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/home.jpg" width="200" alt="Explore screen with Magic Edit and trend templates"><br><sub>Explore</sub></td>
    <td align="center"><img src="docs/assets/screenshots/create.jpg" width="200" alt="Create screen with a prompt, styles and sizes"><br><sub>Create from text</sub></td>
    <td align="center"><img src="docs/assets/screenshots/result.jpg" width="200" alt="Before and after comparison slider"><br><sub>Before / after</sub></td>
    <td align="center"><img src="docs/assets/screenshots/share.jpg" width="200" alt="Share sheet with Stories, collage and story card"><br><sub>Share your glow</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/editor.jpg" width="200" alt="Editor with the Magic Edit prompt panel"><br><sub>Magic Edit</sub></td>
    <td align="center"><img src="docs/assets/screenshots/library.jpg" width="200" alt="My Works gallery with favorites"><br><sub>My Works</sub></td>
    <td align="center"><img src="docs/assets/screenshots/paywall.jpg" width="200" alt="Paywall with yearly and monthly plans"><br><sub>Paywall</sub></td>
    <td align="center"><img src="docs/assets/screenshots/onboarding.jpg" width="200" alt="Onboarding first page"><br><sub>Onboarding</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/consent.jpg" width="200" alt="AI processing consent sheet"><br><sub>AI consent</sub></td>
    <td align="center"><img src="docs/assets/screenshots/settings.jpg" width="200" alt="Settings with appearance, privacy and legal"><br><sub>Settings</sub></td>
    <td align="center"><img src="docs/assets/screenshots/legal.jpg" width="200" alt="Privacy Policy shown in the app"><br><sub>Privacy Policy</sub></td>
    <td align="center"><img src="docs/assets/screenshots/edit.jpg" width="200" alt="Edit hub listing the editing tools"><br><sub>Edit hub</sub></td>
  </tr>
</table>

Captured on an iPhone simulator in demo mode (AI results are simulated). The [Screenshots workflow](.github/workflows/screenshots.yml) refreshes the full-resolution set on the [`screenshots` branch](https://github.com/RiosenBeq/furkan/tree/screenshots); `scripts/screenshot-gallery.py` rebuilds this gallery.

## Quick start

**Requirements:** Xcode 16 or newer, iOS 17+ simulator or device.

1. Open `ios/Glowlit.xcodeproj` and run the **Glowlit** scheme.
2. With no AI key or backend configured, the app runs in **demo mode**: every screen works offline and AI results are simulated on-device and stamped "DEMO PREVIEW".
3. Subscriptions are testable locally: the scheme uses `ios/StoreKit/Products.storekit`.

## Connect an AI provider

There are two places for an AI key. Neither is ever committed to git.

**1. Try it in the simulator (developer mode, DEBUG builds only)**

1. Copy `ios/Config/Secrets.example.xcconfig` to `ios/Config/Secrets.xcconfig` (git-ignored; an empty one already exists on the development Mac).
2. Fill in `GL_AI_PROVIDER` (`fal`, `openai` or `gemini`) and `GL_AI_API_KEY`. Model overrides are optional.
3. Run the app. Explore shows "Developer mode", and Magic Edit, Styles, Enhance, Erase and Create use the provider directly. Credits stay local.

Release builds never contain the key, because `Release.xcconfig` blanks it and the code only reads it in DEBUG. Use a paid API tier: some free tiers may use your requests to improve their models, which would break the app's privacy promise.

**2. Production (backend)**

Deploy the Supabase backend ([backend/README.md](backend/README.md)) and set `FAL_KEY` as an Edge Function secret. Then set `backendBaseURL` and `supabaseAnonKey` in `ios/App/Resources/AppConfig.json`. The backend meters credits, moderates prompts and outputs, and keeps the provider key off devices.

> 🇹🇷 **API anahtarı nereye?** Simülatörde denemek için `ios/Config/Secrets.xcconfig` dosyasına `GL_AI_PROVIDER` (fal, openai veya gemini) ve `GL_AI_API_KEY` değerlerini yazın. Canlı sürüm için anahtar yalnızca backend'de `FAL_KEY` olarak durur. Bu dosyalar git'e girmez.

## Sharing and promotion

- **In the app:** the share composer (`ios/App/Features/Share/`) exports a photo, a before/after collage or a 9:16 story card. Free exports carry a small "Made with Glowlit" mark, which Pro removes. Every export keeps the IPTC "made with AI" metadata. The composer suggests a caption with hashtags and sends to Instagram Stories directly once `instagramAppID` (a Meta App ID) is set in `AppConfig.json`; otherwise it uses the system share sheet.
- **Marketing kit:** [docs/marketing/](docs/marketing/README.md) contains App Store copy (EN/TR) with measured character counts, a social media kit, a 30-day launch plan, generated App Store screenshots and social images.
- **Website:** [web/](web/README.md) is a static landing page with the legal pages, ready for GitHub Pages (`.github/workflows/website.yml`).

## Legal

Terms of Use, Privacy Policy, Acceptable Use & AI Content Policy (English and Turkish) and the KVKK Aydınlatma Metni are in [legal/](legal/README.md). `scripts/build-legal.py` renders them into the app (shown natively in Settings, onboarding, the paywall and the consent screen), to [docs/legal/](docs/legal/) and to `web/legal/`. **They are drafts for legal review.** Fill in `legal/config.json` and follow the checklist in `legal/README.md` before publishing.

## Repository

```
ios/        SwiftUI app (Glowlit.xcodeproj) + AppCore Swift package (business logic, 65 tests)
  Config/   Info.plist additions and xcconfigs (developer AI key slot: Secrets.xcconfig)
backend/    Supabase: Postgres schema, credit ledger and reports; Edge Functions (fal.ai, Apple JWS, reports); SQL tests
legal/      Source texts of the legal documents (EN/TR) and their config
docs/       Research, brand, product spec, architecture, compliance, roadmap, marketing kit, published legal copies
web/        Static landing page and legal pages
scripts/    Tooling: catalog export, legal build, brand assets, marketing images, README gallery
.github/    CI (AppCore, Deno, SQL, legal sync, Xcode), simulator screenshots, website deploy
```

## Stack

| Layer | Technology |
|---|---|
| iOS app | SwiftUI · Observation · SwiftData · StoreKit 2 · Vision · Core Image · PhotosUI · iOS 17+ |
| Design | "Blush" palette (blush `#F7C1D9`, petal `#F8E0EA`, ink `#121212`) · Bricolage Grotesque (OFL) with New York Italic accents · light-first, with Dark and Automatic appearances |
| AI | Backend: fal.ai (Nano Banana 2, SeedVR2, object removal). Developer mode: fal.ai, OpenAI Images or Google Gemini directly |
| Backend | Supabase (anonymous Auth, Postgres with RLS, Edge Functions/Deno) · Apple App Store Server Library |
| Quality | XCTest (Linux and macOS) · `deno check`/`lint`/`fmt` · PostgreSQL ledger and report tests · legal sync check · `xcodebuild` |

## Running the checks locally

```bash
swift test --package-path ios/Packages/AppCore                 # business logic (works on Linux too)
backend/scripts/test-db.sh                                     # migrations + ledger and report tests (PostgreSQL 14+)
python3 scripts/build-legal.py --check                         # legal copies match legal/
cd backend/supabase/functions && deno check ai-image/index.ts  # Edge Functions
```

## Docs

Start with [docs/README.md](docs/README.md). Highlights:
- [Market research](docs/01-market-research.md)
- [Brand identity](docs/02-brand-identity.md)
- [Product spec](docs/03-product-spec.md)
- [Architecture](docs/04-architecture.md)
- [Compliance](docs/05-compliance.md)
- [Roadmap](docs/06-roadmap.md)
- [Marketing kit](docs/marketing/README.md)

## Licences

- Code: all rights reserved by the repository owner unless stated otherwise.
- Bricolage Grotesque: SIL Open Font License 1.1 (`ios/App/Resources/Fonts/BricolageGrotesque-OFL.txt`).
