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

**Aybuke is the AI photo studio for trend-ready, true-to-you photos.** You can edit by describing the change, restyle in one tap, or create anything from text. Pricing is honest and face data is private by default.

> For people who want to join every photo trend and look their best without looking fake, Aybuke is the AI photo studio that turns their photos into trend-ready, true-to-you results in seconds — with honest pricing and face data that's private by default.

### Why this can win in late 2026

| Market reality | Aybuke's answer |
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
  7. **Retro looks and quick videos**: 80s, 90s and Y2K effects, and a talking video with the silences cut out, for Stories and TikTok.

## 3. Feature set

### MVP (built in this repository)

| Area | Feature | Where |
|---|---|---|
| Onboarding | 2 value pages → age step → interests ("What are you here for?") → **free on-device "Try Digicam '04 on your photo"** before/after → Keep editing (editor on Effects) or Save to My Works → soft paywall (adults only, after the editor closes) → tour | `Features/Onboarding` |
| Guided tour | 7 spotlight steps with Next/Skip across the tabs (Magic Edit, daily credits, free tools, Create, photos & videos, private gallery, Settings); shown once after onboarding, replayable from Settings → "Show me around" | `Features/Tour` |
| Consent | Explicit **AI data-sharing consent**, asked in context before the first cloud job (App Review 5.1.2(i)); revocable in Settings | `AIConsentView` |
| Explore (home) | Magic Edit hero, daily credits (a tap opens "Your credits": the balance, when free credits are back, what uses a credit and what is always free), quick tools (Retro Cam, Makeup Studio, then Effects; Makeup Studio leads for "Makeup & hair looks"), template rows personalised by onboarding interests, collection pages with the price per look, "Create from text", "Glow together" invite | `Features/Home`, `CreditsSheet` |
| Magic Edit | Prompt-based edit with suggestion chips ("Golden hour light", "Put me in a black suit"…) | `Features/Edit` |
| Makeup Studio | Makeup as play and self-expression: 20 one-tap looks (Soft Glam, Cherry Cola, Strawberry Girl, Coquette Blush, Cherry Lips, Latte, Mermaid Shimmer, Cold Girl, Glitter Pop, Berry Fairy, Y2K Frost, Graphic Liner, Cobalt Pop, Peachy Doll, Festival Gems, Sweetheart, Ballet Blush, Goth Glam, Rainbow Liner, Sunset Shimmer) or her own mix under Customize: lips (9 colors, each with an optional gloss, matte or shimmer finish), eyes (11 shadows and liners), cheeks (4 blushes and an iridescent shine), up to three extras (face gems, faux freckles, star stickers, glitter, heart freckles, face pearls, rhinestones), an optional hair color (5) and Soft / Medium / Vivid. The app writes the request and sends it as a Magic Edit, so consent, credits (1 per try), Likeness Lock, the free retry and AI marking are the same. Another look right after one starts again from her photo and replaces it, so looks never pile up. Color, shine and sparkle only: her face, features, expression, skin tone, skin texture (freckles, pores, marks) and age stay; no contour, lip plumping, eye enlarging or smoothing; no scores or "better" language. NEW card in Edit, Explore quick tool (first for "Makeup & hair looks"); hidden under 13 | `MakeupPanel`, `AppCore/MakeupStudio` |
| Styles (templates) | 51 year-round one-tap looks in 8 collections (Trending now, Glow-up looks, Aesthetic edits, Bestie pics, Dreamy portraits, Art styles, Pet portraits, For your shop & career), plus seasonal looks in a row named after the season (Spooky season Oct 1–Nov 2, Cozy winter Dec 1–Jan 6, Galentine's Feb 1–14; hidden from Home between seasons, always in the editor); server-side recipes | `AppCore/TemplateCatalog` |
| Effects | Twelve retro effects: VHS '86, Disposable '98, Kira Kira, Digicam '04, Instant '82, Glamour '92, Neon '84, Throwback '16 (optional white square border), Camcorder '06 (REC display; blinking dot and running timecode on video), Toy Cam '09 (cross-processed colour and dark corners), Rainbow '17 (a band of prism light across the top left corner), Film Still (halation, optional letterbox and a one-line subtitle checked by the content policy); optional date stamp; plus **Tiny World** (tilt-shift: a sharp band, blur growing toward the top and bottom, a little more colour; suggested first for city streets); on-device (Core Image), free | `RetroEffects.swift` |
| Enhance | Cloud generative upscale/restore | Edit |
| Remove background | **On-device** (Vision), free and private: tap to pick subjects, **Keep more / Keep less** refine brush over the mask, colour, gradient, blurred-original or own-photo backgrounds with an optional soft contact **Shadow**, outlined stickers | `CutoutTool`, `Cutout.swift`, `OnDeviceImageService` |
| Erase | Brush mask → AI object removal; one finger paints, two fingers pan and pinch-zoom up to 4× (the brush keeps its size on screen, so it paints finer zoomed in) | `MaskCanvas` |
| Adjust | Brightness, contrast, highlights, shadows, saturation, warmth, a pink-to-lilac tint, glow (soft light added on top, never smoothing), fade, film grain, vignette and sharpness, plus one-tap **Auto** (light and colour only) and four vibes above the sliders (Dreamy, Analog, Moody, Golden) that set several sliders she can then tweak (on-device, free; the preview and the saved photo match at any size). RAW photos (ProRAW, DNG) are developed automatically with the best settings when opened | `AdjustPanel`, `AutoDevelop`, `AppCore/Adjustments`, `AppCore/AutoAdjust` |
| Crop | Original, Freeform, 1:1, 4:5, 9:16 and 16:9 (exact pixel ratios), rotate left, mirror, straighten ±15° that enlarges the photo just enough to never show empty corners; uniform scaling only. On-device, free | `CropPanel`, `CropCanvas`, `AppCore/CropGeometry` |
| Editor | Undo/redo, hold-to-see-original, before/after compare slider (lined up after a crop), pinch or double-tap zoom up to 4× with trackpad support, save and share (both apply a pending effect, adjustment or crop first, so they export what's on screen); Liquid Glass tool bar on iOS 26 that keeps every label whole at any text size and in every language (one row on iPad and the Mac, scrolling with the chosen tool in view on iPhone) | `EditorView`, `EditorToolBar`, `ZoomableCanvas` |
| Video | Simple on-device editor: **Auto-cut silences** (jump cut), ten of the retro effects (with their date stamps, letterbox or camcorder display) and Tiny World, trim, save to Photos or share. Free, no watermark, no ending clip, clips up to 5 minutes | `Features/Video`, `VideoEngine`, `AppCore/SilenceCutter` |
| Create | Text-to-image with 20 styles, 5 aspect ratios, 1–4 images (2+ is Pro), "Inspire me" (seasonal ideas) and "Make it magic" (Apple's on-device model when available, otherwise the offline "Enhance prompt"); "Create with Image Playground" on supported devices (iOS 18.4+): Apple's own image maker, Apple's cartoon styles only, no Aybuke credits, under Apple's terms and limits (never called free or unlimited) | `Features/Create` |
| Share | Photo, Before/After, Story card, **Cover star** (4:5 magazine cover; the masthead tucks behind her head with on-device Vision person segmentation), **Photo strip** (date-stamped photo booth), Which vibe? (two variations of one creation, never the original against an edit); caption and hashtags; **Hide other faces** for group photos shared from My Works or Create (keeps the biggest face or the ones she taps and blurs the others, on device, in every format). Stories without a Meta App ID: the system share sheet with just the image and a "Tap Instagram, then Stories" hint | `Features/Share`, `Services/Sharing` |
| Invite | "Glow together": a 9:16 story card with the app icon and a QR code to the App Store page or website, from Settings and Home; never includes her photos | `InviteView` |
| Library ("My Works") | Every creation saved on-device (SwiftData + protected files); detail view with save/share/edit/delete | `Features/Library` |
| Paywall | Annual ($39.99, 7-day trial, preselected) + monthly ($5.99, first month $1.99 if eligible); a card on top says why it opened (out of free credits with when they're back, a Pro look or style, several images, the mark); trial timeline; "Always free" line; credit-pack downsell; restore; legal copy | `Features/Paywall` |
| Settings | Membership, credits, consent toggle, **Language** (opens iOS Settings for the per-app language), "Show me around", delete creations, **delete account & data**, legal, acknowledgements | `Features/Settings` |
| Languages | 12 languages via String Catalogs: English, Turkish, Spanish, Brazilian Portuguese, French, German, Italian, Russian, Japanese, Korean, Simplified Chinese, Indonesian. Follows the iPhone's language; legal documents in English and Turkish only | `Localizable.xcstrings`, `L10n.core` |
| iPhone and iPad | Universal app: adaptive grids and readable widths; iOS 26 Liquid Glass tab bar (minimises on scroll), frosted fallback on iOS 17–18 | `DesignSystem/LiquidGlass.swift` |
| Trust | Exact refunds on failure, free retry, trial reminder notification, report image, no fake timers | across |
| Provenance | IPTC `DigitalSourceType` XMP on every AI export (EU AI Act Art. 50) | `ImageExporter` |
| Analytics | RevenueCat in observer mode for subscription analytics (StoreKit 2 and the backend still sell and verify); on with the public SDK key in `AppConfig.json`, off when it's empty | `RevenueCatBridge` |
| Demo mode | The whole app runs offline with simulated AI when no backend is configured | `DemoAIImageService` |

### Next (see [roadmap](06-roadmap.md))

- Selfie profile for Likeness Lock (3–5 selfies, identity check).
- Packs: Headshot pack and Restore pack.
- Short motion versions of templates (photo → video).
- C2PA manifests.
- App Attest.
- Remote template catalog with thumbnails.
- Native-speaker review of the 11 translations; localized App Store pages.
- iPhone Duo layouts.
- Declared Age Range API.

### Non-goals (for now)

- No social feed: it would trigger UGC obligations (1.2, TAKE IT DOWN Act).
- No face recognition or embeddings: GDPR Art. 9 and BIPA risk.
- No celebrity, studio or artist-named templates: IP risk.
- No Android.

## 4. Key flows

1. **First launch.** Onboarding (about 30 s). The user picks interests, tries the free on-device Digicam '04 effect on their own photo (keeps editing it or saves it to My Works), sees the soft paywall (adults only), and either closes it or starts a trial. They land on Explore with categories ordered by their interests, and a 7-step guided tour points out the essentials (Skip ends it at any step).
2. **One-tap template.** Tap a card → photo picker → editor opens and the template starts immediately (consent sheet first time) → result with before/after → Save / Share / "Retry free".
3. **Magic Edit.** Pick a photo → type or choose a suggestion → result → keep editing (undo/redo) → Save.
4. **Makeup Studio.** Edit tab → Makeup Studio (or the Explore quick tool) → pick a photo → tap a look, or open Customize for lips (and their finish), eyes, cheeks, extras, hair color and intensity → Try it (consent sheet first time) → before/after → "Retry free" if it doesn't look like her → Save / Share.
5. **Create.** Type an idea → pick a style and size → Generate → results (paged) → Save / Share / Edit.
6. **Out of credits.**
   - Free user → paywall (or a credit pack). Its top card says she has used today's free credits and when they're back, and "Remind me when they're back" sits under the plans.
   - Pro user → a sheet (only after she tries an AI action, with a close button): the next monthly refill date when the app knows it (otherwise "within a month"), the credit packs with their real prices ("≈ price per credit" below the billed price), and a reminder that the free tools still work. Not enough for several images → "This needs N credits. You have M."
7. **Video.** Edit tab → "Edit a video" → pick a clip (up to 5 minutes) → toggle "Auto-cut silences", pick an effect, trim → Save to Photos or Share. Everything runs on the iPhone; no credits.
8. **Share.** Result → Share → pick a format (Photo, Before/After, Story card, Cover star, Photo strip, Which vibe?) → edit the caption → Stories, Photos or the share sheet.

## 5. Monetization — the Fair-Price Promise

| Tier | Price (US) | Includes |
|---|---|---|
| **Free** | $0 | 2 credits every day (low AI quality at 1k, small corner wordmark on exports of cloud AI results, also after a re-edit; share cards of them say "Made with Aybuke"). Unlimited on-device tools: effects, Auto and adjustments, background removal, Best shot and video editing (no watermark on anything made only with them). |
| **Pro Yearly** *(default)* | **$39.99/yr** (≈ $3.33/month), **7-day free trial** for eligible users | 80 credits/month with one month of rollover (cap 160), every template and style, our best-quality AI (medium instead of low quality), up to 4 images at once, no watermark |
| **Pro Monthly** | **$5.99/mo**; first month **$1.99** for eligible users (introductory offer), no free trial | Same as yearly |
| **Credit packs** (consumable) | 30 credits **$2.99**, 100 credits **$7.99** | Never expire; for occasional users who don't want a subscription |

The paywall sums it up: *"No weekly plans, ever."* (No price comparison: our own research puts $39.99/year at the North American median.)

**Rules**
- 1 credit = 1 cloud creation or edit. Background removal, adjustments, effects and video editing are free.
- Expiring credits are spent first: daily → subscription → packs.
- Failed, cancelled, blocked or timed-out jobs are **refunded exactly**.
- One **free retry** per people edit, within 15 minutes.
- The paywall makes the **billed amount the most prominent price** (Apple 3.1.2). The yearly plan's monthly equivalent ("just $3.33/month") is subordinate. There is no free-trial toggle; Apple has rejected these since January 2026.
- A trial-end **reminder notification** fires at least 26 hours before the trial ends (earlier when that would fall at night or in school hours).

**Pricing rationale**
- Competitor annual prices: Picsart $57, Meitu $59.99, Hypic $69.99, YouCam $69.99, Facetune $77.99, Remini $79.99, Photoroom $79.99. At $39.99, Aybuke costs about half the typical ~$70.
- $39.99/yr matches the RevenueCat North-American cross-category annual median, and $5.99/mo is well under the $9.99 monthly median.

### Unit economics (from [tech research §3.9](research/tech-and-compliance.md#39-rough-cost-per-active-user))

- Blended cloud cost is about **$0.06 per operation**, including retries: on xAI, about $0.04 per created image and $0.05–0.07 per edit (see [AI provider](#ai-provider)). Infrastructure is ≲ $0.01 per monthly active user.
- **Free user**, worst case: 2 operations/day ≈ $0.12/day. Mitigations: rate limits, DeviceCheck/appTransactionID binding (planned) and low quality for free users. Typical usage is far lower.
- **Pro Monthly** ($5.99, about $5.09 net): 80 credits × $0.06 = **$4.80 worst case**, about 94% of the net price. The expected cost at typical utilisation (30–40%) is about $1.44–1.92 (28–38% of net). The $1.99 first month (about $1.69 net) works as an acquisition cost.
- **Pro Yearly** ($39.99, about $34 net, ≈ $2.83/mo): a heavy user who spends the full 80/month costs about $4.80/mo and is unprofitable. RevenueCat calls Photo & Video "one-off project apps", and median annual renewal is 23%, so most annual users use far less.
- **Credit packs** (about $2.54 and $6.79 net): if every credit is used, 30 × $0.06 = $1.80 (71% of net) and 100 × $0.06 = $6.00 (88% of net).
- **Monitor `credits used ÷ allowance`.** Allowances live in SQL (`credit_policy()`) and can be retuned without an app release.
- Free users already run at low quality and Pro at medium (both 1k); reserve anything costlier for an explicit "premium" option at 3–5× credits.

### AI provider

Cloud jobs run on **xAI Grok Imagine**, chosen as the best quality for the price.
- **Model and cost:** `grok-imagine-image-2.0` at 1k for every cloud operation, low quality for free users and medium for Pro. That's about $0.04 per created image and $0.05–0.07 per edit (input included), so about $0.06 per cloud operation on average, the figure the credit plan is sized for. Enhance and Erase are edits with a fixed instruction; background removal always runs on the device.
- **What Pro buys:** quality, not pixels. The Pro benefit is "Our best-quality AI, no watermark" (no longer "HD exports").
- **Privacy:** each request runs in the background (`EdgeRuntime.waitUntil`). Results come back inline (base64) and are cleared as soon as the app confirms the download, and `sweep_jobs()` clears any left after an hour. xAI doesn't train on API data without permission. **Switch on Zero Data Retention in the xAI console before launch:** selfies are personal data.
- **Safety check:** xAI's own moderation verdict is the output check on every result, and Anthropic's Claude (Haiku 5.5, `claude-haiku-5-5`) is the independent check on top of it: it looks at the photo before an edit and at every result. Both fail closed. Claude can't make images, so it only classifies, at about $0.0002 a check (two for a Magic Edit), which doesn't move the per-operation cost.
- **Alternative:** fal.ai stays available with `AI_PROVIDER=fal` (Nano Banana 2, SeedVR2, object removal; 2K for Pro). Its NSFW classifier would replace xAI's verdict as the output check only with `FAL_KEY`, which stays unset (fal.ai isn't in the consent sheet).
- The server picks the model per operation (`XAI_IMAGE_MODEL` / `XAI_EDIT_MODEL` override it), so the provider or model can change without an app release.

## 6. Success metrics

| Stage | Metric | Target (first 90 days) |
|---|---|---|
| Activation | % of new users completing a first AI result on Day 0 | ≥ 60% |
| Aha | % of onboarding users who try the free Digicam '04 look | ≥ 35% |
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
3. **Trend ops**: monitor TikTok, Instagram, X and South/South-East-Asian creators daily; prepare a new template within **24–48 hours** of a trend breaking and ship it with the next app update (aim: weekly). Prompts of existing looks can be tuned on the server at any time; a remote catalog (new looks without an update) is on the roadmap.
4. **Ratings**: ask only after a successful save on the 2nd or 3rd session; never after a failure or a paywall dismissal.
5. **Expand**: UK, CA and AU, then the markets of the app's 11 other languages with localized metadata (about 92% of top apps localize).
