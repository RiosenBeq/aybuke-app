# App Store Connect setup — Aybuke 1.0

Every value needed to create Aybuke in App Store Connect, in the order the forms ask for it. Listing text for 13 locales: [`app-store-metadata.json`](app-store-metadata.json) (all limits checked). Screenshots: `docs/marketing/app-store/<lang>/` (iPhone 6.9", 1290×2796) and `…/<lang>/ipad/` (iPad 13", 2064×2752), plus `…/<lang>/mac/` (Mac, 2880×1800, see section 8), made by `scripts/marketing-images.py`.

> **Status (15 October 2026):** done. iOS 1.0 (build 20261015.1225) and macOS 1.0 (build 20261015.1233) were submitted with the values below and wait for review, release type AFTER_APPROVAL on both. This page now records what was entered; follow it again for a new record or a change. Submit a version for review only while the backend is live ([`docs/SUPABASE-TODO.md`](../SUPABASE-TODO.md)); without it AI runs in demo mode.

## 1. New app

| Field | Value |
|---|---|
| Platform | iOS (add macOS to the same record later, see section 8) |
| Name | `Aybuke: AI Photo Editor` |
| Primary language | English (U.S.) |
| Bundle ID | `app.glowlit.ios` (register it first in Certificates, Identifiers & Profiles with **App Groups** `group.app.glowlit.shared` and **Sign in with Apple**; the widget extension is `app.glowlit.ios.widgets` with the same App Group). Team `CBTKNY3LFC` |
| SKU | `glowlit-ios-001` |
| User access | Full access |

## 2. App Information

| Field | Value |
|---|---|
| Category | Primary **Photo & Video**, secondary **Graphics & Design** |
| Content rights | Doesn't contain, show or access third-party content |
| Privacy Policy URL | English: `https://aybuke.org/legal/en/privacy-policy`; Turkish localization: `https://aybuke.org/legal/tr/gizlilik-politikasi`. The site is the `RiosenBeq/aybuke` repository on Vercel; confirm both pages answer before submitting |
| Localizations | Add every locale in `app-store-metadata.json`: en-US, tr, es-ES, es-MX, pt-BR, fr-FR, de-DE, it, ru, ja, ko, zh-Hans, id |

**Age rating:** answer honestly — no violence, sexual content, profanity, gambling, horror, drugs, medical content or unrestricted web access; no chat between users. Generated images are filtered (prompt policy in all languages, provider moderation, output check, and an independent Claude safety check of the photo before an edit and of every result) and can be reported. Set the rating to **13+** to match the Terms (cloud AI, accounts and purchases from 13) with **Override to Higher Age Rating**, which is needed while the Terms keep a minimum age above the calculated rating. Under In-App Controls, tick **Age Assurance** only once a build with the age step is live. Under Capabilities, tick **Advertising**: free members see ads (section "Ads (AdMob)" below). The app uses the **Declared Age Range** capability (`com.apple.developer.declared-age-range`; no approval needed): turn it on for the app id `app.glowlit.ios` if automatic signing doesn't.

## 3. Pricing and availability

- Price: **Free**.
- Availability: all countries and regions **except China mainland** (generative-AI apps need a government licence there).

## 4. In-app purchases

**Subscription group** `Aybuke Pro` (display name "Aybuke Pro"). Both plans at the same level, so switching is a crossgrade.

| Product ID | Reference name | Duration | Price (USD) | Introductory offer |
|---|---|---|---|---|
| `app.glowlit.pro.yearly` | Pro Yearly | 1 year | $39.99 | Free trial, 1 week, new subscribers |
| `app.glowlit.pro.monthly` | Pro Monthly | 1 month | $5.99 | Pay as you go, 1 month at $1.99 |

Localized description for both: "Monthly credits, every look, best-quality AI" (44 characters; Apple allows 45, so translate per locale within that). It names no number on purpose: the server can retune the allowance (80 a month, 20 in the yearly plan's trial week) without touching App Store Connect, and the paywall shows the current numbers. Review screenshot: the paywall (`docs/marketing/app-store/en/09-paywall.jpg`).

**Consumables**

| Product ID | Reference name | Price (USD) | Description |
|---|---|---|---|
| `app.glowlit.credits.30` | 30 Credits | $2.99 | 30 credits that never expire |
| `app.glowlit.credits.100` | 100 Credits | $7.99 | 100 credits that never expire |

All four went to review with iOS 1.0 on 15 October 2026. The first subscriptions needed a price for China mainland even though the app isn't sold there: CHN ¥298 (yearly) and ¥38 (monthly) were added, availability unchanged. These IDs also exist in RevenueCat (project "Aybuke", renamed from Glowlit; entitlement `pro`, offering `default`) and in `ios/StoreKit/Products.storekit`. Leave **App Store Server Notifications V2** (Production and Sandbox, App Information) pointing at RevenueCat: App Store Connect takes one URL per environment. The backend gets each notification through RevenueCat › Project Aybuke › Apps › Aybuke (App Store) › **Apple Server Notification Forwarding URL** = `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/app-store-notifications`, set on 15 October 2026 (`backend/README.md`, "Setup" 5; `docs/SAHIP-YAPILACAKLAR.md` 2.14).

## 5. App Privacy

Published on 15 October 2026 with the 10 data types below.

"Do you or your third-party partners use data for tracking?" **No.** The app never shows Apple's tracking prompt and never reads the advertising identifier, every ad request is non-personalised (`publisherPrivacyPersonalizationState = .disabled`, Google's restricted data processing on, first-party ad ID off), and teens get child treatment. Matches `ios/App/Resources/PrivacyInfo.xcprivacy` (our own collection; Google's SDKs ship their own manifests).

**Our own collection** (all linked to the anonymous user ID, none used for tracking):

| Data type | Linked to the user | Purposes |
|---|---|---|
| Photos or Videos | Yes | App Functionality (only photos the user sends to cloud AI, which xAI edits and Anthropic's Claude checks for safety; results are kept under the user ID until download, ≤ 1 hour) |
| Other User Content (prompts, reports) | Yes | App Functionality (prompts reach the AI provider with a hashed user tag we can link back; reports are keyed to the user ID) |
| User ID (anonymous account ID) | Yes | App Functionality, Analytics (RevenueCat) |
| Purchase History | Yes | App Functionality, Analytics (RevenueCat) |
| Email Address (only with Sign in with Apple, on in 1.0: `signInWithApple` in `AppConfig.json`; a hidden relay address works) | Yes | App Functionality. Declared because sign-in is on; the privacy manifest lists it too |
| Advertising Data (our record of each confirmed rewarded ad: AdMob transaction id, ad unit, reward, date; 30 days) | Yes | App Functionality |

**New with ads: Google Mobile Ads SDK** (free members 13+ on iPhone and iPad; nothing for Pro, under 13 or the Mac). Declare these with **Third-Party Advertising** and **Analytics** as purposes, **not linked to the user** and **not used for tracking**:

| Data type (App Store Connect) | What the SDK sends Google |
|---|---|
| Location › Coarse Location | Estimated from the IP address (country, city) |
| Identifiers › Device ID | App-scoped identifiers the SDK uses for frequency capping and fraud checks (never the IDFA: no tracking prompt) |
| Usage Data › Product Interaction | Ad views, taps, how much of a video played |
| Usage Data › Advertising Data | Which ads were shown |
| Diagnostics › Performance Data | Load times and other ad performance data |

Two notes for the form: Apple asks "linked to the user" once per data type, so **Advertising Data** is answered **Yes, linked** (because of our own reward records above) with all three purposes (App Functionality, Third-Party Advertising, Analytics); every other new type is **not linked**. Crash Data isn't needed: the app turns the SDK's crash reporting off (`disableSDKCrashReporting()`). Re-check the answers against the privacy report Xcode builds from the SDK manifests (Organizer › Archive › Generate Privacy Report) before submitting.

## Ads (AdMob)

| Step | What to do |
|---|---|
| AdMob app | iOS app "Aybuke", app id `ca-app-pub-2292230772061554~5236020895` (in `Release.xcconfig` as `GL_ADMOB_APP_ID` and in `AppConfig.json` → `ads.appID`; a mismatch turns ads off) |
| Rewarded unit | `ca-app-pub-2292230772061554/1406702504`, reward amount **1**, reward item **credit**. *Server-side verification*: callback URL `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` (no query string), then **Verify URL** (it answers 200 and grants nothing); verified and saved on 15 October 2026. Supabase secret `ADMOB_REWARDED_AD_UNIT` = the same unit id (`backend/README.md`, "Rewarded ads") |
| Interstitial unit | "After save interstitial" `ca-app-pub-2292230772061554/6797438012`, frequency cap 3 per user a day (created 15 October 2026), in `AppConfig.json` → `ads.interstitialUnitID`. Empty: no interstitials |
| Content | Blocking controls › Sensitive categories: all 11 standard sensitive categories (dating, gambling, alcohol, weight loss and the rest) and the restricted ones are blocked (15 October 2026), so adults' PG ads stay teen-friendly too. The block is account-wide, so it also applies to the owner's other apps in the same AdMob account. The app already sets G for teens and PG for adults |
| Privacy & messaging | The **GDPR** message "Aybuke GDPR" (EEA, UK, Switzerland; Aybuke only, the privacy policy URL, a "Do not consent" button in every country, 9 extra languages) is published (15 October 2026). A **US states** message is optional. Teens are tagged as under the age of consent and never see them |
| app-ads.txt | AdMob reads `https://aybuke.org/app-ads.txt`. The line is in the website repository (`RiosenBeq/aybuke`) and in `web/app-ads.txt` here; the live file answers 200 with the line (15 October 2026) |
| Store listing | Once the app is live, link the AdMob app to its App Store listing (id `6822716008`), so AdMob finds app-ads.txt through the listing's website (`docs/SAHIP-YAPILACAKLAR.md` 3.7) |
| Age rating | Under Capabilities, tick **Advertising** (free members see ads; they're never personalised or targeted). It doesn't raise the 13+ rating |

## 6. Version 1.0

| Field | Value |
|---|---|
| Promotional text, description, keywords, What's New | `app-store-metadata.json` |
| Support URL | `https://aybuke.org/support` |
| Marketing URL | `https://aybuke.org` |
| Copyright | `2026 Okan Berk Manavoğlu` |
| App Review information | Contact name, phone and email of the owner; no demo account needed; notes from [`app-store-listing.md`](app-store-listing.md) ("App Review notes"), which say the consent screen names Supabase, xAI and Anthropic, and that the layered safety includes an independent Claude check of the photo and every result |
| Build | `ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh` (App Store Connect API key, automatic signing; `PLATFORM=mac` for the Mac build), or Xcode › Product › Archive › Distribute. The 1.0 builds (iOS 20261015.1225, Mac 20261015.1233) were signed manually and uploaded with altool, because automatic signing failed on the owner's Mac (`AGENTS.md` §6, item 2). The script first runs `scripts/check-release-config.py --online` and stops on release blockers: demo mode (no backend), `[bracketed]` legal placeholders, a missing or GitHub-blob `websiteURL`, a website or privacy page that doesn't answer, mail domains without MX records. For a deliberate TestFlight preview set `GL_PREVIEW_BUILD=1`; never submit such a build for review. Xcode archives skip the check, so run it by hand before submitting one. `ITSAppUsesNonExemptEncryption` is `NO` (HTTPS only), so no export-compliance documents are needed |
| Release | Automatically after approval (AFTER_APPROVAL), iOS and macOS |

## 7. Before pressing "Submit for Review" (every version)

1.0 went through this list on 15 October 2026.

- [ ] Backend live and AppConfig.json pointing to it (real AI results in TestFlight, with `ANTHROPIC_API_KEY` set so the Claude safety check runs)
- [ ] aybuke.org answers, so the Privacy Policy and Support URLs open
- [ ] Paid Apps Agreement, tax and banking complete (Business section)
- [ ] All in-app purchases "Ready to Submit" and attached to the version
- [ ] The owner's final go-ahead

## 8. Mac App Store (Mac Catalyst)

The Mac app is the same app built with Mac Catalyst, with the same bundle IDs (`app.glowlit.ios`, widgets `app.glowlit.ios.widgets`). That makes it a **universal purchase**: one app record, and the subscriptions and credit packs from section 4 cover iPhone, iPad and Mac with no new products.

| Step | What to do |
|---|---|
| Platform | On the app's page in App Store Connect, add the **macOS** platform (the "+" next to the platform names). Pricing, availability (still no China mainland), age rating, App Privacy and in-app purchases are shared with iOS |
| Signing | `PLATFORM=mac ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh`. Automatic signing fails for a Mac archive while the team has no registered Mac, so 1.0 used manual signing with Mac Catalyst profiles for the same App IDs (`AGENTS.md` §6, item 2); the App Group and Sign in with Apple carry over. The Mac build is sandboxed (`ios/Config/*-macOS.entitlements`), as the Mac App Store requires |
| Category | Set once in App Information and shared with iOS. The Mac build also declares `LSApplicationCategoryType` = `public.app-category.photography`, which the Mac App Store requires |
| Version page | The macOS version has its own description, keywords and screenshots. Start from `app-store-metadata.json`, but drop the Lock Screen and Dynamic Island lines and say Mac where it says iPhone or iPad: there is no Live Activity or Instagram Stories sharing on the Mac |
| Screenshots | 16:10 (1280×800, 1440×900, 2560×1600 or 2880×1800; up to 10). Ready: eight per language at 2880×1800 in `docs/marketing/app-store/<lang>/mac/` (home in a MacBook, Makeup Studio, before/after, Create, effects, Cover star, Cut out, Hide faces), made by `scripts/marketing-images.py` from window captures of the Mac app launched with `-GLScreenshotScene <scene> -GLWindowSize 1600x1000`; captions in the `mac` lists of `screenshot-captions.json` |
| Review notes | Add: "On the Mac, Instagram Stories sharing and the Live Activity aren't offered; everything else matches the iOS app." |
