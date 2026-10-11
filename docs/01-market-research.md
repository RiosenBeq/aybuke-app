# 01 · Market research — summary & implications

**Full report, with about 230 sourced data points and their dates:** [research/market-research.md](research/market-research.md).

**Method**
- Desk research on 2026-10-11, using web search only.
- The App Store and Reddit could not be fetched directly, so ratings and prices are search-index snapshots. Verify key numbers before quoting them externally.

## The market in one page

- **Demand is at an all-time high.**
  - Generative-AI app downloads doubled to **3.8B in 2025**, and in-app revenue tripled to **more than $5B** (Sensor Tower).
  - Image and video model launches drive **6.5×** more incremental downloads than other model releases (Appfigures).
- **The money goes to "make me / my photo better" apps.** AppMagic's 2025 revenue:

  | App | 2025 revenue |
  |---|---|
  | FaceApp | $150M |
  | Meitu | $121M |
  | Facetune | $113M |
  | Hypic | $88M (disputed) |
  | Picsart | $79M |
  | Remini | $75M |
  | Photoroom | $47M |

- **Free platforms raised the bar.** ChatGPT (with an Images tab and presets) and Gemini (Nano Banana) are now the biggest "image apps". A paid app must win on finished outcomes, likeness, speed to trend and trust, not on the model.
- **North America is 11% of downloads but 40% of in-app revenue.** India and South-East Asia start the trends, such as the figurine (Thailand) and the saree (India).

## Competitors (15 analysed)

| App | Core promise | Monetization signal |
|---|---|---|
| Remini | Enhance / unblur / "photos of you" | Weekly $9.99, yearly $79.99, 7-day trial |
| Lensa | Retouch + Magic Avatars | Weekly pass $2.99, avatar packs |
| Picsart | All-in-one editor | $57/yr; Pro includes 500 credits/month, no rollover |
| Photoroom | Product photos for sellers | Annual preselected; on all three a16z lists |
| Facetune | Selfie retouch | $77.99/yr, 7-day trial |
| Hypic (ByteDance) | Beauty + AI art | $69.99/yr |
| FaceApp | Face transforms | Top earner ($150M) |
| YouCam AI Pro | AI headshots | Subscription + credit packs |
| Glam AI | Trend templates (photo + video) | Coins for video; no-trial paywall with a countdown |
| Retake | Selfie regeneration | 7-day trial on a weekly plan, shown early |
| Others | Meitu, EPIK, Dawn, Wonder, PhotoAI | — |

**Pattern:** titles follow "Brand + AI Photo Editor / Enhancer / Art Generator". AI-native apps default to **weekly** plans; incumbents push annual plans plus credits.

## What users love vs. hate

| ❤️ Love | 💔 Hate |
|---|---|
| 1. One-tap "wow" (before/after, restore, unblur) | 1. **Weekly subscriptions, trial auto-renewals, charges after cancelling** |
| 2. "Looks like me, only better" | 2. Free features moved behind the paywall |
| 3. Trend-ready templates | 3. Credits on top of subscriptions; failed attempts burn credits |
| 4. Emotional and nostalgic value (restore, "hug my younger self") | 4. **Faces that stop looking like the user** (identity drift) |
| 5. A usable free tier | 5. Bias and unwanted sexualisation |
| 6. Speed, with no prompting skill needed | 6. Privacy fears about face data |
| 7. All-in-one breadth | 7. Watermarks, low-res exports, daily caps |
| 8. Practical results (headshots, product photos) | 8. Ads, failed generations, poor refunds |

## Trend timeline (what moved downloads)

- **2025**
  - Ghibli-style images: March, GPT-4o; 700M images in week one.
  - AI action figure / "starter pack": April.
  - **Nano Banana 3D figurine**: Aug–Sep; 23M new Gemini users.
  - Retro saree, celebrity polaroid, hug-my-younger-self.
  - ChatGPT Images presets: December.
- **2026**
  - "2026 is the new 2016" nostalgia.
  - Caricature of me and my job: February.
  - GPT Image 2: April.
  - Film-grain "imperfection", toy-ification.
  - World Cup sticker cards: Jun–Jul.

**"Me, transformed" identity templates are the dominant viral format.** Templates with a practical payoff (headshots, product photos) monetise better than pure novelty.

## Monetization benchmarks

| Benchmark | Value | Source |
|---|---|---|
| Photo & Video median trial → paid | **22.2%** (lowest category) | RevenueCat 2026 |
| Photo & Video median annual renewal | 23% | RevenueCat |
| Hard vs freemium paywall, download → paid by Day 35 | **10.7% vs 2.1%** | RevenueCat 2026 |
| Revenue per install, annual vs weekly | **≈ 5×** | RevenueCat 2026 |
| Year-one retention: yearly / monthly / weekly | 20–40% / 6–14% / **1–2%** | RevenueCat 2026 |
| Trial starts on Day 0 (Photo & Video) | **91.2%** | Adapty 2026 |
| Trial conversion by length: ≤ 4 days vs 5–9 days | 25.5% vs **37.4%** | RevenueCat 2026 |
| AI apps vs non-AI | +41% revenue per payer, but annual subscribers churn ~30% faster | RevenueCat 2026 |
| Per-image API cost | $0.03–0.05 (Flash-class) to $0.13–0.24 (Pro-class) | Provider pricing |

## Implications we built in

1. **Fair-Price Promise.** Annual (7-day trial, preselected) plus monthly plans, **no weekly plan**, credit packs that never expire, credits that roll over, exact refunds, a trial timeline and a reminder. This turns complaint #1 into the brand promise and follows the 5× revenue-per-install economics.
2. **Likeness Lock.** Identity clauses in every people template, plus "Doesn't look like you? Retry free" (complaint #4).
3. **Aha before paywall.** A free, on-device "see the glow on your own photo" step in onboarding: 91% of trials start on Day 0.
4. **Trend engine.** Template recipes live on the server so new trends ship in 24–48 hours without an app release.
5. **Private by default.** Explicit consent, on-device background removal and adjustments, no input storage, 1-hour output expiry (complaint #6).
6. **No fake urgency, no hidden limits.** Credits are visible everywhere, and failures are free.

→ Turned into the product definition in [03-product-spec.md](03-product-spec.md).
