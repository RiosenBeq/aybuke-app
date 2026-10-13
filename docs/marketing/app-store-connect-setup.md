# App Store Connect setup — Glowlit 1.0

Every value needed to create Glowlit in App Store Connect, in the order the forms ask for it. Listing text for 13 locales: [`app-store-metadata.json`](app-store-metadata.json) (all limits checked). Screenshots: `docs/marketing/app-store/<lang>/` (iPhone 6.9", 1290×2796) and `…/<lang>/ipad/` (iPad 13", 2064×2752), made by `scripts/marketing-images.py`.

> Submit for review only after the backend is live ([`docs/SUPABASE-TODO.md`](../SUPABASE-TODO.md)); without it AI runs in demo mode.

## 1. New app

| Field | Value |
|---|---|
| Platform | iOS |
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
| Privacy Policy URL | `https://riosenbeq.github.io/furkan/legal/en/privacy-policy.html` (needs GitHub Pages; until then the repository's `main` copy of `docs/legal/en/privacy-policy.md` works) |
| Localizations | Add every locale in `app-store-metadata.json`: en-US, tr, es-ES, es-MX, pt-BR, fr-FR, de-DE, it, ru, ja, ko, zh-Hans, id |

**Age rating:** answer honestly — no violence, sexual content, profanity, gambling, horror, drugs, medical content or unrestricted web access; no chat between users. Generated images are filtered (prompt policy in all languages, provider moderation, output check) and can be reported. Set the rating to **13+** to match the Terms (minimum age 13).

## 3. Pricing and availability

- Price: **Free**.
- Availability: all countries and regions **except China mainland** (generative-AI apps need a government licence there).

## 4. In-app purchases

**Subscription group** `Glowlit Pro` (display name "Glowlit Pro"). Both plans at the same level, so switching is a crossgrade.

| Product ID | Reference name | Duration | Price (USD) | Introductory offer |
|---|---|---|---|---|
| `app.glowlit.pro.yearly` | Pro Yearly | 1 year | $39.99 | Free trial, 1 week, new subscribers |
| `app.glowlit.pro.monthly` | Pro Monthly | 1 month | $5.99 | Pay as you go, 1 month at $1.99 |

Localized description for both: "100 credits a month, every template, best-quality AI" (translate per locale). Review screenshot: the paywall (`docs/marketing/app-store/en/09-paywall.jpg`).

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
| Photos or Videos | No | App Functionality (only photos the user sends to cloud AI; deleted after download, ≤ 1 hour) |
| Other User Content (prompts) | No | App Functionality |
| User ID (anonymous account ID) | Yes | App Functionality, Analytics (RevenueCat) |
| Purchase History | Yes | App Functionality, Analytics (RevenueCat) |
| Email Address (only with optional Sign in with Apple) | Yes | App Functionality |

## 6. Version 1.0

| Field | Value |
|---|---|
| Promotional text, description, keywords, What's New | `app-store-metadata.json` |
| Support URL | `https://riosenbeq.github.io/furkan/` (landing page with the support email) |
| Marketing URL | same as Support URL |
| Copyright | `2026 Glowlit` |
| App Review information | Contact name, phone and email of the owner; no demo account needed; notes from [`app-store-listing.md`](app-store-listing.md) ("App Review notes") |
| Build | Upload from Xcode (Product › Archive › Distribute) or `xcodebuild -exportArchive` with an App Store Connect API key. `ITSAppUsesNonExemptEncryption` is `NO` (HTTPS only), so no export-compliance documents are needed |
| Release | Manual release after approval |

## 7. Before pressing "Submit for Review"

- [ ] Backend live and AppConfig.json pointing to it (real AI results in TestFlight)
- [ ] GitHub Pages on, so the Privacy Policy and Support URLs open
- [ ] Paid Apps Agreement, tax and banking complete (Business section)
- [ ] All in-app purchases "Ready to Submit" and attached to the version
- [ ] The owner's final go-ahead
