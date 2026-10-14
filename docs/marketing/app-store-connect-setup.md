# App Store Connect setup — Glowlit 1.0

Every value needed to create Glowlit in App Store Connect, in the order the forms ask for it. Listing text for 13 locales: [`app-store-metadata.json`](app-store-metadata.json) (all limits checked). Screenshots: `docs/marketing/app-store/<lang>/` (iPhone 6.9", 1290×2796) and `…/<lang>/ipad/` (iPad 13", 2064×2752), plus `…/<lang>/mac/` (Mac, 2880×1800, see section 8), made by `scripts/marketing-images.py`.

> Submit for review only after the backend is live ([`docs/SUPABASE-TODO.md`](../SUPABASE-TODO.md)); without it AI runs in demo mode.

## 1. New app

| Field | Value |
|---|---|
| Platform | iOS (add macOS to the same record later, see section 8) |
| Name | `Glowlit: AI Photo Editor` |
| Primary language | English (U.S.) |
| Bundle ID | `app.glowlit.ios` (register it first in Certificates, Identifiers & Profiles with **App Groups** `group.app.glowlit.shared` and **Sign in with Apple**; the widget extension is `app.glowlit.ios.widgets` with the same App Group). Team `CBTKNY3LFC` |
| SKU | `glowlit-ios-001` |
| User access | Full access |

## 2. App Information

| Field | Value |
|---|---|
| Category | Primary **Photo & Video**, secondary **Graphics & Design** |
| Content rights | Doesn't contain, show or access third-party content |
| Privacy Policy URL | `https://riosenbeq.github.io/aybuke-app/legal/en/privacy-policy.html` (needs GitHub Pages; until then the repository's `main` copy of `docs/legal/en/privacy-policy.md` works) |
| Localizations | Add every locale in `app-store-metadata.json`: en-US, tr, es-ES, es-MX, pt-BR, fr-FR, de-DE, it, ru, ja, ko, zh-Hans, id |

**Age rating:** answer honestly — no violence, sexual content, profanity, gambling, horror, drugs, medical content or unrestricted web access; no chat between users. Generated images are filtered (prompt policy in all languages, provider moderation, output check) and can be reported. Set the rating to **13+** to match the Terms (cloud AI, accounts and purchases from 13) with **Override to Higher Age Rating**, which is needed while the Terms keep a minimum age above the calculated rating. Under In-App Controls, tick **Age Assurance** only once a build with the age step is live. The app uses the **Declared Age Range** capability (`com.apple.developer.declared-age-range`; no approval needed): turn it on for the app id `app.glowlit.ios` if automatic signing doesn't.

## 3. Pricing and availability

- Price: **Free**.
- Availability: all countries and regions **except China mainland** (generative-AI apps need a government licence there).

## 4. In-app purchases

**Subscription group** `Glowlit Pro` (display name "Glowlit Pro"). Both plans at the same level, so switching is a crossgrade.

| Product ID | Reference name | Duration | Price (USD) | Introductory offer |
|---|---|---|---|---|
| `app.glowlit.pro.yearly` | Pro Yearly | 1 year | $39.99 | Free trial, 1 week, new subscribers |
| `app.glowlit.pro.monthly` | Pro Monthly | 1 month | $5.99 | Pay as you go, 1 month at $1.99 |

Localized description for both: "100 credits a month, every template, best-quality AI" (translate per locale). Review screenshot: the paywall (`docs/marketing/app-store/en/10-paywall.jpg`).

**Consumables**

| Product ID | Reference name | Price (USD) | Description |
|---|---|---|---|
| `app.glowlit.credits.30` | 30 Credits | $2.99 | 30 credits that never expire |
| `app.glowlit.credits.100` | 100 Credits | $7.99 | 100 credits that never expire |

These IDs already exist in RevenueCat (project "Glowlit", entitlement `pro`, offering `default`) and in `ios/StoreKit/Products.storekit`. Set **App Store Server Notifications V2** later to the backend (see `backend/README.md`, "Before launch").

## 5. App Privacy

No tracking. Matches `ios/App/Resources/PrivacyInfo.xcprivacy`.

| Data type | Linked to the user | Purposes |
|---|---|---|
| Photos or Videos | Yes | App Functionality (only photos the user sends to cloud AI; results are kept under the user ID until download, ≤ 1 hour) |
| Other User Content (prompts, reports) | Yes | App Functionality (prompts reach the AI provider with a hashed user tag we can link back; reports are keyed to the user ID) |
| User ID (anonymous account ID) | Yes | App Functionality, Analytics (RevenueCat) |
| Purchase History | Yes | App Functionality, Analytics (RevenueCat) |
| Email Address (only with optional Sign in with Apple) | Yes | App Functionality |

## 6. Version 1.0

| Field | Value |
|---|---|
| Promotional text, description, keywords, What's New | `app-store-metadata.json` |
| Support URL | `https://riosenbeq.github.io/aybuke-app/` (landing page with the support email) |
| Marketing URL | same as Support URL |
| Copyright | `2026 Glowlit` |
| App Review information | Contact name, phone and email of the owner; no demo account needed; notes from [`app-store-listing.md`](app-store-listing.md) ("App Review notes") |
| Build | `ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh` (App Store Connect API key, automatic signing; `PLATFORM=mac` for the Mac build), or Xcode › Product › Archive › Distribute. The script first runs `scripts/check-release-config.py --online` and stops on release blockers: demo mode (no backend), `[bracketed]` legal placeholders, a missing or GitHub-blob `websiteURL`, a website or privacy page that doesn't answer, mail domains without MX records. For a deliberate TestFlight preview set `GL_PREVIEW_BUILD=1`; never submit such a build for review. Xcode archives skip the check, so run it by hand before submitting one. `ITSAppUsesNonExemptEncryption` is `NO` (HTTPS only), so no export-compliance documents are needed |
| Release | Manual release after approval |

## 7. Before pressing "Submit for Review"

- [ ] Backend live and AppConfig.json pointing to it (real AI results in TestFlight)
- [ ] GitHub Pages on, so the Privacy Policy and Support URLs open
- [ ] Paid Apps Agreement, tax and banking complete (Business section)
- [ ] All in-app purchases "Ready to Submit" and attached to the version
- [ ] The owner's final go-ahead

## 8. Mac App Store (Mac Catalyst)

The Mac app is the same app built with Mac Catalyst, with the same bundle IDs (`app.glowlit.ios`, widgets `app.glowlit.ios.widgets`). That makes it a **universal purchase**: one app record, and the subscriptions and credit packs from section 4 cover iPhone, iPad and Mac with no new products.

| Step | What to do |
|---|---|
| Platform | On the app's page in App Store Connect, add the **macOS** platform (the "+" next to the platform names). Pricing, availability (still no China mainland), age rating, App Privacy and in-app purchases are shared with iOS |
| Signing | `PLATFORM=mac ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh`. Automatic signing makes the Mac Catalyst profiles for the same App IDs; the App Group and Sign in with Apple carry over. The Mac build is sandboxed (`ios/Config/*-macOS.entitlements`), as the Mac App Store requires |
| Category | Set once in App Information and shared with iOS. The Mac build also declares `LSApplicationCategoryType` = `public.app-category.photography`, which the Mac App Store requires |
| Version page | The macOS version has its own description, keywords and screenshots. Start from `app-store-metadata.json`, but drop the Lock Screen and Dynamic Island lines and say Mac where it says iPhone or iPad: there is no Live Activity or Instagram Stories sharing on the Mac |
| Screenshots | 16:10 (1280×800, 1440×900, 2560×1600 or 2880×1800; up to 10). Ready: eight per language at 2880×1800 in `docs/marketing/app-store/<lang>/mac/` (home in a MacBook, Makeup Studio, before/after, Create, effects, Cover star, Cut out, Hide faces), made by `scripts/marketing-images.py` from window captures of the Mac app launched with `-GLScreenshotScene <scene> -GLWindowSize 1600x1000`; captions in the `mac` lists of `screenshot-captions.json` |
| Review notes | Add: "On the Mac, Instagram Stories sharing and the Live Activity aren't offered; everything else matches the iOS app." |
