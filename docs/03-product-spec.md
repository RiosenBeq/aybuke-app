# 03 · Product spec — the expanded brief

> **Original brief (TR):** "Bir mobil uygulama: AI ile fotoğraf düzenleme ve AI ile fotoğraf oluşturma. Piyasadaki en rağbet görenlere bak; uygulama İngilizce; kullanıcıların neyi sevdiğini, rengi, fontu, ismi araştır; aşama aşama ilerle; Swift."
>
> In English: a mobile app for AI photo editing and AI image generation, built after studying the most popular apps on the market. The app is in English. Research what users love, the colours, the font and the name, then build it step by step, in Swift.

This document turns that brief into a product definition grounded in the research:
- [market](research/market-research.md)
- [brand & design](research/brand-and-design.md)
- [tech & compliance](research/tech-and-compliance.md)

---

## 1. One-liner and positioning

**Glowlit is the AI photo studio for trend-ready, true-to-you photos.** You can edit by describing the change, restyle in one tap, or create anything from text. Pricing is honest and face data is private by default.

> For people who want to join every photo trend and look their best without looking fake, Glowlit is the AI photo studio that turns their photos into trend-ready, true-to-you results in seconds — with honest pricing and face data that's private by default.

### Why this can win in late 2026

| Market reality | Glowlit's answer |
|---|---|
| ChatGPT and Gemini made generic image generation **free**. a16z: "the bar for standalone image products rose sharply." | Don't compete on the model. Compete on **finished outcomes**: one-tap templates, likeness, speed to trend and polish. |
| The #1 complaint is **weekly-trial traps and surprise charges**. Annual plans earn about **5×** more per install than weekly ones, and weekly plans keep only 1–2% of subscribers after a year (RevenueCat 2026). | **Fair-Price Promise**: no weekly plan, a visible trial timeline, a reminder before billing, automatic refunds and credits that roll over. |
| The #4 complaint is **"it doesn't look like me"** (identity drift). | **Likeness Lock**: identity-preserving prompts, plus "Doesn't look like you? Retry free". |
| Trends drive installs: Ghibli → action figure → figurine → caricature → World Cup. | **48-hour trend engine**: server-side template recipes, so new trends ship without an app release. |
| Privacy fears about face data; regulation is tightening (EU AI Act, Apple 5.1.2(i)). | **Private by default**: explicit consent, on-device tools, no input storage, 1-hour output expiry, AI-provenance metadata. |

## 2. Target users (beachhead)

- **Who:** 18–34-year-olds in English-speaking markets, posting on Instagram and TikTok. Monetize in the US first, then the UK, Canada and Australia.
- **Jobs-to-be-done**, all "photos of me":
  1. **Trend selfies**: "Put my face in today's trend, now." (figurine, action figure, anime film, polaroid, seasonal)
  2. **Glow-up that still looks like me**: retouch, enhance, glam.
  3. **Pro headshots** for LinkedIn and dating.
  4. **Restore old photos**: emotional, giftable.
  5. **Create from text**: ideas, wallpapers, posts.
  6. **Quick fixes**: remove background, erase objects, light and colour.

## 3. Feature set

### MVP (built in this repository)

| Area | Feature | Where |
|---|---|---|
| Onboarding | 3 value pages → interests ("What will you create first?") → **free on-device "try it on your photo"** before/after → soft paywall | `Features/Onboarding` |
| Consent | Explicit **AI data-sharing consent**, asked in context before the first cloud job (App Review 5.1.2(i)); revocable in Settings | `AIConsentView` |
| Explore (home) | Magic Edit hero, quick tools, template rows personalised by onboarding interests, "Create from text" | `Features/Home` |
| Magic Edit | Prompt-based edit with suggestion chips ("Golden hour light", "Put me in a black suit"…) | `Features/Edit` |
| Styles (templates) | 19 one-tap templates in 6 categories (trending, seasonal, portraits, fun, art, business); server-side recipes | `AppCore/TemplateCatalog` |
| Enhance | Cloud generative upscale/restore | Edit |
| Remove background | **On-device** (Vision), free and private | `OnDeviceImageService` |
| Erase | Brush mask → AI object removal | `MaskCanvas` |
| Adjust | Brightness, contrast, saturation, warmth, sharpness, vignette (on-device, free) | `AdjustPanel` |
| Editor | Undo/redo, hold-to-see-original, before/after compare slider, save, share | `EditorView` |
| Create | Text-to-image with 13 styles, 5 aspect ratios, 1–4 images (2+ is Pro), "Surprise me", "Enhance prompt" | `Features/Create` |
| Library ("My Works") | Every creation saved on-device (SwiftData + protected files); detail view with save/share/edit/delete | `Features/Library` |
| Paywall | Annual (7-day trial, preselected) + monthly; trial timeline; credit-pack downsell; restore; legal copy | `Features/Paywall` |
| Settings | Membership, credits, consent toggle, delete creations, **delete account & data**, legal, acknowledgements | `Features/Settings` |
| Trust | Exact refunds on failure, free retry, trial reminder notification, report image, no fake timers | across |
| Provenance | IPTC `DigitalSourceType` XMP on every AI export (EU AI Act Art. 50) | `ImageExporter` |
| Demo mode | The whole app runs offline with simulated AI when no backend is configured | `DemoAIImageService` |

### Next (see [roadmap](06-roadmap.md))

- Selfie profile for Likeness Lock (3–5 selfies, identity check).
- Packs: Headshot pack and Restore pack.
- Short motion versions of templates (photo → video).
- C2PA manifests.
- App Attest.
- Remote template catalog with thumbnails.
- Localization.
- iPhone Duo layouts.
- Declared Age Range API.

### Non-goals (for now)

- No social feed: it would trigger UGC obligations (1.2, TAKE IT DOWN Act).
- No face recognition or embeddings: GDPR Art. 9 and BIPA risk.
- No celebrity, studio or artist-named templates: IP risk.
- No Android.

## 4. Key flows

1. **First launch.** Onboarding (about 30 s). The user picks interests, optionally tries the free on-device glow on their own photo, sees the soft paywall, and either closes it or starts a trial. They land on Explore with categories ordered by their interests.
2. **One-tap template.** Tap a card → photo picker → editor opens and the template starts immediately (consent sheet first time) → result with before/after → Save / Share / "Retry free".
3. **Magic Edit.** Pick a photo → type or choose a suggestion → result → keep editing (undo/redo) → Save.
4. **Create.** Type an idea → pick a style and size → Generate → results (paged) → Save / Share / Edit.
5. **Out of credits.**
   - Free user → paywall (or a credit pack).
   - Pro user → friendly fair-use message: credits refill monthly and packs never expire.

## 5. Monetization — the Fair-Price Promise

| Tier | Price (US) | Includes |
|---|---|---|
| **Free** | $0 | 3 credits every day (standard 1K resolution, small corner wordmark on exports). Unlimited on-device tools: background removal and adjustments. |
| **Pro Yearly** *(default)* | **$59.99/yr** (≈ $1.15/week), **7-day free trial** for eligible users | 100 credits/month with one month of rollover, every template and style, HD (2K) output, up to 4 images at once, no watermark |
| **Pro Monthly** | **$9.99/mo**, no trial | Same as yearly |
| **Credit packs** (consumable) | 30 credits **$4.99**, 100 credits **$12.99** | Never expire; for occasional users who don't want a subscription |

**Rules**
- 1 credit = 1 cloud creation or edit. Background removal and adjustments are free.
- Expiring credits are spent first: daily → subscription → packs.
- Failed, cancelled, blocked or timed-out jobs are **refunded exactly**.
- One **free retry** per people edit, within 15 minutes.
- The paywall makes the **billed amount the most prominent price** (Apple 3.1.2). The weekly equivalent is subordinate. There is no free-trial toggle; Apple has rejected these since January 2026.
- A trial-end **reminder notification** fires 24 hours before billing.

**Pricing rationale**
- Competitor annual prices: Picsart $57, Meitu $59.99, Hypic $69.99, YouCam $69.99, Facetune $77.99, Remini $79.99, Photoroom $79.99.
- The RevenueCat North-American medians ($39.99/yr, $9.99/mo) span all categories, and AI apps cost more to run.

### Unit economics (from [tech research §3.9](research/tech-and-compliance.md#39-rough-cost-per-active-user))

- Blended cloud cost is about **$0.06 per operation**, including retries. Infrastructure is ≲ $0.01 per monthly active user.
- **Free user**, worst case: 3 operations/day ≈ $0.18/day. Mitigations: rate limits, DeviceCheck/appTransactionID binding (planned) and lower free resolution. Typical usage is far lower.
- **Pro Monthly** ($9.99, about $8.49 net): 100 credits × $0.06 = **$6.00 worst case** (71% of net). The expected cost at typical utilisation (30–40%) is about $2.
- **Pro Yearly** ($59.99, about $51 net, ≈ $4.25/mo): a heavy user who spends the full 100/month costs about $6/mo and is unprofitable. RevenueCat calls Photo & Video "one-off project apps", and median annual renewal is 23%, so most annual users use far less.
- **Monitor `credits used ÷ allowance`.** Allowances live in SQL (`credit_policy()`) and can be retuned without an app release.
- Route free users and default templates to Flash-class models; reserve Pro-class models for an explicit "premium" option at 3–5× credits.

## 6. Success metrics

| Stage | Metric | Target (first 90 days) |
|---|---|---|
| Activation | % of new users completing a first AI result on Day 0 | ≥ 60% |
| Aha | % of onboarding users who try the free glow | ≥ 35% |
| Conversion | Install → trial start (Day 0) | ≥ 6% (annual-default paywall) |
| Conversion | Trial → paid | ≥ 30% (category median 22.2%) |
| Trust | Refund rate | ≤ 4% (AI-app median 4.2%) |
| Quality | "Retry free" usage per people edit | ≤ 15% (identity-quality proxy) |
| Retention | D7 / D30 | ≥ 20% / ≥ 8% |
| Economics | Cloud cost ÷ net revenue | ≤ 35% |
| Store | Rating | ≥ 4.6 (category ratings are 4.3–4.8) |

## 7. Launch plan (summary)

1. **TestFlight**: real backend; QA identity fidelity across skin tones and hair textures; red-team the safety filters and keep the logs for EU AI Act evidence.
2. **US soft launch**: Apple Ads on job keywords (headshot, restore, figurine) plus trend keywords; one Custom Product Page per trend.
3. **Trend ops**: monitor TikTok, Instagram, X and South/South-East-Asian creators daily; ship a new template within **24–48 hours** of a trend breaking.
4. **Ratings**: ask only after a successful save on the 2nd or 3rd session; never after a failure or a paywall dismissal.
5. **Expand**: UK, CA and AU, then localized metadata (about 92% of top apps localize).
