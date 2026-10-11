# AI Photo Editor + AI Image Generator for iOS (English): Market Research

**Prepared:** 2026-10-11  ·  **Scope:** global, with the focus on English-language iOS markets (US first)  ·  **Method:** web search only. See §9 for limitations.

> **How to read the numbers.** Every figure has a source link and the date of the data.
> - **Snapshot** means App Store data surfaced through the search index. The capture date is unknown and some snapshots are clearly old.
> - **Derived** means my own arithmetic on sourced figures.
> - **Unknown** means the figure was not found.
>
> Third-party revenue estimates (AppMagic, Appfigures, ScreensDesign) are modelled numbers, not company disclosures, and they sometimes disagree sharply.

---

## 0. Executive summary

1. **Demand is at an all-time high, but the free platforms capture much of it.**
   - Generative-AI app downloads doubled to **3.8B** in 2025 and in-app purchase revenue nearly tripled to **more than $5B** ([Sensor Tower, Jan 2026](https://sensortower.com/blog/state-of-mobile-2026)).
   - Image and video model launches drive **6.5x** more incremental downloads than other model releases ([Appfigures, May 2026](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads)).
   - Google's Nano Banana wave added about **22M** incremental Gemini downloads but only about **$181K** of incremental consumer spend in 28 days. GPT-4o images, by contrast, generated about **$70M** in 28 days ([same source](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads)).
2. **Standalone revenue goes to outcome-specific "make me or my photo better" apps.** AppMagic's 2025 figures: FaceApp **$150M**, Meitu **$121M**, Facetune **$113M**, Hypic **$88M**, Picsart **$79M**, Remini **$75M** and Photoroom **$47M** ([Business of Apps, updated 2026-01-27](https://www.businessofapps.com/data/top-grossing-apps/)). These seven sum to roughly **$673M** (derived).
3. **The free giants raised the bar.**
   - a16z (March 2026) says that as the native image models in ChatGPT and Gemini improved, "the bar for standalone image products rose sharply" ([a16z.news, March 2026](https://www.a16z.news/p/top-100-gen-ai-consumer-apps-march); [The Neuron](https://www.theneuron.ai/explainer-articles/a16z-just-ranked-the-100-most-popular-ai-apps-heres-the-full-list-and-what-it-tells-us-/)).
   - ChatGPT added an **Images tab with preset templates** in December 2025 ([TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpt-images-just-got-a-major-upgrade-and-it-could-change-how-we-all-create)).
   - Users made **1B Nano Banana Pro images in 53 days** ([9to5Google, 2026-01-12](https://9to5google.com/2026/01/12/gemini-nano-banana-pro-milestone/)).
4. **Monetization leans on weekly plans and trials, but the category leaks users.**
   - Photo & Video has the **lowest median trial-to-paid rate of any category, 22.2%** ([RevenueCat SOSA 2026](https://www.revenuecat.com/state-of-subscription-apps)), and a **23% median annual renewal rate** ([RevenueCat, 2026](https://www.revenuecat.com/blog/growth/average-subscription-renewal-rates-by-app-category)).
   - AI apps earn about **41% more per payer** but lose annual subscribers about **30% faster** ([TechCrunch, 2026-03-10](https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows)).
5. **What users love and hate:**
   - **Love:** one-tap transformations that still look like them, trend-ready templates, emotional restorations of old photos, and a free tier that is actually usable.
   - **Hate:** weekly trial traps and charges after cancelling, features moving behind the paywall, credits sold on top of subscriptions, faces that no longer look like them, bias, privacy risk, and watermarks or daily caps (§3).
6. **Trend cadence** (§4):
   - 2025: Ghibli (March) → action figure and "starter pack" (April) → Nano Banana figurine, retro saree, celebrity polaroid and hug-my-younger-self (August–September) → Nano Banana Pro (November) → ChatGPT Images presets (December).
   - 2026: "2026 is the new 2016" nostalgia (January) → caricature of me and my job (February) → GPT Image 2 (April) → World Cup jersey and sticker edits (June–July), alongside the film-grain "imperfection" look.
7. **Opportunity:** a "me photos" studio built on trust, faithful likeness and fast trends. It should price honestly (annual plans plus packs, credits that roll over, refunds for failed generations) and keep face data private by default (§8).

---

## 1. Market overview

### 1.1 Size and growth

| Metric | Value | Period | Source (date) |
|---|---|---|---|
| Generative-AI app downloads (all GenAI) | **3.8B** (about 2x year on year) | 2025 | [Sensor Tower State of Mobile 2026](https://sensortower.com/blog/state-of-mobile-2026) (Jan 2026); [9to5Mac](https://9to5mac.com/2026/01/21/sensor-towers-state-of-mobile-2026-tiktok-dominates-ai-apps-surge-games-lose-ground/) |
| Generative-AI in-app purchase revenue | **More than $5B** (about 3x year on year) | 2025 | same |
| Generative-AI time spent | **48B hours** (about 3.6x 2024) | 2025 | same (via search summary) |
| AI-app in-app purchase revenue | **More than $4B expected**, +36% vs H2 2025 | H1 2026 (projection) | [Sensor Tower State of AI 2026 press release](https://sensortower.com/press/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year) (2026-06-16) |
| AI-app time spent | **36B hours**, vs 17.2B in H1 2025 | H1 2026 (projection) | [PR Newswire](https://www.prnewswire.com/news-releases/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year-302800975.html) |
| Generative-AI downloads and in-app purchase revenue | **1.7B** downloads, **$1.87B** in-app purchase revenue | H1 2025 | [TechCrunch / Sensor Tower](https://techcrunch.com/2025/07/30/gen-ai-apps-doubled-their-revenue-grew-to-1-7b-downloads-in-first-half-of-2025/) (2025-07-30) |
| Regional split | Asia **42.6%** of generative-AI downloads. North America **11%** of downloads but **40%** of in-app purchase revenue | H1 2025 | [Sensor Tower State of AI Apps 2025](https://sensortower.com/blog/state-of-ai-apps-report-2025) |
| Generative-AI mobile app revenue (alternative estimate) | **$3B** (methodology differs from Sensor Tower) | 2025 | [Business of Apps](https://www.businessofapps.com/insights/will-generative-ai-apps-remain-a-revenue-powerhouse-in-2026/) |
| Consumer spend on AI graphic editor and generator apps | about **$110M**. The US is **more than 66%** of global spend | 2023–2024 data | Appfigures via Statista: [segments](https://www.statista.com/statistics/1607386/top-ai-app-segments-by-consumer-spend), [markets](https://www.statista.com/statistics/1607453/top-markets-for-ai-graphic-generators) |
| AI photo and video app baseline | More than **60 new apps per quarter** (vs about 23 in 2022). US downloads **+24%** and Europe **+16%** year on year. Asia **+1%** but over half of downloads. Asia revenue **+65%** | 2023 | [Sensor Tower](https://sensortower.com/blog/rapid-growth-and-competitive-dynamics-the-state-of-ai-photo-and-video-apps) (April 2024) |

**Takeaways:**
- No credible analyst figure exists for the size of an "AI photo editor market". Analyst-style reports are inconsistent and low quality.
- Sizing bottom-up from app revenue is more reliable. The leading AI-forward photo apps generated roughly $0.67B in 2025 (derived from the AppMagic figures below). The wider generative-AI app pool is $3–5B+ depending on the tracker.

### 1.2 Top earners in Photo & Video, 2025 (AppMagic)

| Rank | App | 2025 revenue | Note |
|---|---|---|---|
| 1 | CapCut | $815M | Video editor (context) |
| 2 | **FaceApp** | **$150M** | +$15M vs 2024; about 33M annual users ([Business of Apps FaceApp page](https://www.businessofapps.com/data/faceapp-statistics/)) |
| 3 | **Meitu** | **$121M** | |
| 4 | **Facetune** | **$113M** | |
| 5 | **Hypic** | **$88M** | Conflicts with Appfigures (see below) |
| 6 | **Picsart** | **$79M** | |
| 7 | **Remini** | **$75M** | |
| 8 | Lightroom | $71M | |
| 9 | **Photoroom** | **$47M** | App only. Web and API revenue is extra |
| 10 | Splice | $39M | |

Source: [Business of Apps "Top Grossing Apps (2026)", AppMagic data, updated 2026-01-27](https://www.businessofapps.com/data/top-grossing-apps/). The search result did not show the scope (gross or net, global or single market).

**Cross-checks and other revenue signals:**
- **Remini**
  - Appfigures estimated a pace of about **$93M a year after store fees**; the article's date was not shown ([Appfigures](https://appfigures.com/resources/insights/the-company-squeezing-money-from-apps-you-used-to-love/amp)).
  - Bending Spoons' F-1 says Remini's 2025 revenue was **more than 9x** and its monthly active users **more than 5x** pre-acquisition (2021) levels. Subscriptions rose from **under 43%** of revenue (2021) to **85%** (2023) ([SEC F-1, 2026](https://www.sec.gov/Archives/edgar/data/0002004711/000110465926071170/tm2613674-7_f1.htm)).
  - Bending Spoons as a whole had **$1.31B** in 2025 revenue, up 95% ([Fortune, 2026-06-08](https://fortune.com/2026/06/08/bending-spoons-italian-aol-evernote-wetransfer-files-us-ipo/), via search summary).
- **Hypic**
  - Appfigures shows monthly consumer spend rising from **under $100K** to **$250K (April 2025)**, then **just under $1M (August)** and **$1M+** afterwards. It puts pre-fee 2025 revenue (January–November) at about **$6.7M** ([Appfigures This Week in Apps, 2025-12-19](https://appfigures.com/resources/this-week-in-apps/20251219)).
  - That is more than **10x below** AppMagic's $88M. **Treat Hypic's revenue as uncertain**; the two trackers' scopes may differ (unknown).
  - Appfigures nonetheless frames Hypic as "threatening established editors like Facetune, Picsart, Photoroom, VSCO, and Lightroom".
- **US weekly revenue, 2025** ([Sensor Tower Q1 page](https://sensortower.com/blog/2025-q1-unified-top-5-photography%20apps-revenue-us-600a8192241bc16eb890d396), [Q2 page](https://sensortower.com/blog/2025-q2-unified-top-5-photography%20apps-revenue-us-600a8192241bc16eb890d396)):
  - FaceApp peaked near **$986K a week** (February) and **$968K a week** (mid-May).
  - Picsart was about **$762K a week** and Photoroom about **$379K a week** in early June.
- **US monthly revenue, November 2024** (AppMagic via [Statista](https://statista.com/statistics/1351014/top-grossing-fhoto-and-video-apps-us)): Canva **over $8.5M**, Facetune about **$4.8M**, Remini **over $3.9M**.
- **Meitu Inc.**, all apps and mostly China ([Yahoo Finance, 2026-03-27 results](https://finance.yahoo.com/sectors/technology/articles/meitu-2025-annual-results-adjusted-132500863.html); [HKEX filing](https://www.hkexnews.hk/listedco/listconews/sehk/2026/0327/2026032700842.pdf)):
  - 2025 revenue **RMB 3.86B** (+28.8%) and adjusted net profit **RMB 965M** (+64.7%).
  - **16.91M** paying subscribers (+34.1%).
  - Paying subscribers outside mainland China **more than doubled**, and monthly active users outside mainland China passed **100M**.
- **Photoroom**
  - About **$94M ARR at end-2024** (+89%), per a secondary source covering all channels ([Fueler](https://fueler.io/blog/photoroom-usage-revenue-valuation-growth-statistics)).
  - **$43M Series B at about a $500M valuation** in March 2024 ([Tracxn](https://tracxn.com/d/companies/photoroom/__3Eb7XKd5tPi6IJQFKmZrfp2xHmMSn4DH7M3WdkToYPY/funding-and-investors)).
  - Claims of $150M+ ARR in 2026 are unverified.
- **Higgsfield** (adjacent: AI video templates)
  - Run rate went from about **$200M at end-2025** to **more than $1B annualized in September 2026**. These are company-reported figures; Bloomberg describes the method as the last four weeks of revenue times 13 ([Sacra](https://sacra.com/c/higgsfield/); [Higgsfield blog](https://higgsfield.ai/blog/higgsfield-1b-annualized-revenue-run-rate); [Design Musketeer](https://designmusketeer.com/business/higgsfield-ai-1b-annualized-revenue/)).

### 1.3 Downloads and usage leaders

- **AppTweak, 2025** ([AppTweak](https://www.apptweak.com/en/reports/most-downloaded-photo-video-apps)):
  - CapCut **509.2M** downloads.
  - **Remini 132.6M**, the #2 Photo & Video app, down **24.5%** year on year.
  - Picsart down **2.6%** year on year.
- **Remini scale:**
  - **More than 120M downloads** January–August 2024 ([Sensor Tower](https://sensortower.com/blog/state-of-ai-apps-2024)).
  - **More than 100M monthly users**, a company claim from November 2025 ([PR Newswire](https://www.prnewswire.com/news-releases/bending-spoons-remini-app-hits-1-16-million-weekly-installs-following-integration-of-googles-nano-banana-ai-model-302615284.html)).
  - Google Play: **500M+ installs, 4.1 stars, 5.89M reviews** (snapshot) ([Google Play](https://play.google.com/store/apps/details?id=com.bigwinepot.nwdn.international&hl=en_US)).
- **a16z Top 100, 6th edition** (2026-03-09; mobile list ranked by Sensor Tower monthly active users):
  - **Overall top of the list:** ChatGPT #1, CapCut #2 (**736M monthly active users**), Gemini #3, Canva #4 and AI Gallery #5.
  - **Photo apps:** **Picsart #6**, **Remini #11**, Lightroom #16, **Meitu #22**, **Hypic #24**, B612 #38, **Photoroom #39**, VivaCut #49, **BeautyPlus #50**.
  - These ranks are as reproduced by [The Neuron](https://www.theneuron.ai/explainer-articles/a16z-just-ranked-the-100-most-popular-ai-apps-heres-the-full-list-and-what-it-tells-us-/); verify against [a16z](https://a16z.com/100-gen-ai-apps-6/).
  - Midjourney has fallen to **#46**.
- **a16z Top 100, 7th edition** (2026-10-05):
  - Adds the first **US consumer-spend leaderboard**, based on a YipitData card panel.
  - **Photoroom** is one of only **7 products on all three lists** (web, mobile and spend) and one of only two AI-native apps among them, with Perplexity.
  - The top **1%** of US AI payers account for **19.5%** of observed spend, more than the bottom 50% (**16.6%**).
  - Sources: [a16z](https://a16z.com/100-gen-ai-apps-7/), [The Rundown](https://www.therundown.ai/news/a16z-ai-app-spending-rankings-personal-agents), [Crypto Briefing](https://cryptobriefing.com/a16z-top-100-consumer-ai-apps-seventh-edition/), [AI Weekly](https://aiweekly.co/alerts/a16z-top-1-of-us-ai-payers-drive-195-of-consumer-spend).

### 1.4 The platform layer: indirect competitors are now the biggest "image apps"

| Event | Date | Metric | Source |
|---|---|---|---|
| GPT-4o image generation in ChatGPT | 2025-03-25 | **130M+ users made 700M+ images** in the first week | [The Decoder](https://the-decoder.com/chatgpts-image-generation-explodes-with-700m-creations-in-first-week/) |
| ChatGPT downloads | March 2025 / April 2025 | About **46M** in March (world's most downloaded app); about **52M** in April | [9to5Mac](https://9to5mac.com/2025/04/11/chatgpt-was-the-worlds-most-downloaded-app-last-month/); [Appfigures](https://appfigures.com/resources/insights/20250502?f=3) |
| Gemini Nano Banana (Gemini 2.5 Flash Image) | August 2025 | **23M first-time users** and **500M+ images** by 2025-09-08. **#1 on the US App Store** on 2025-09-12. **12.6M** downloads in the first half of September vs **8.7M** in all of August | [TechCrunch](https://techcrunch.com/2025/09/16/gemini-tops-the-app-store-thanks-to-new-ai-image-model-nano-banana/) (2025-09-16) |
| Gemini monthly active users | Q3 2025 | **650M** (+200M since July), growth credited largely to Nano Banana | [Yahoo / Business Insider](https://tech.yahoo.com/ai/gemini/articles/google-gemini-exec-says-nano-111112810.html) |
| Nano Banana Pro (Gemini 3 Pro Image) | 2025-11-20 | **1B images in 53 days** | [9to5Google](https://9to5google.com/2026/01/12/gemini-nano-banana-pro-milestone/) |
| GPT Image 1.5 plus the ChatGPT **Images tab** | 2025-12-16 | Preset filters and trending prompts (for example "K-pop star" and "1980s VHS"). Up to **4x faster**. Better facial-likeness preservation. API **20% cheaper** | [TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpt-images-just-got-a-major-upgrade-and-it-could-change-how-we-all-create); [PCWorld](https://www.pcworld.com/article/3014153/openai-launches-gpt-image-1-5-with-faster-generation-and-smarter-edits.html); [tech.az](https://tech.az/en/posts/openai-introduces-gpt-image-1-5-and-launches-the-new-images-section-in-chatgpt-6334) |
| Nano Banana 2 (Gemini 3.1 Flash Image) | Preview 2026-02-26; generally available 2026-05-28 | Under-18 users got image generation in March 2026. Editing stays **18+ only** | [Google blog](https://blog.google/innovation-and-ai/technology/ai/nano-banana-2/); [Workspace Updates](https://workspaceupdates.googleblog.com/2026/02/introducing-nano-banana-2-in-gemini-app.html); [Google Cloud docs](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-1-flash-image) |
| GPT Image 2 / ChatGPT Images 2.0 | 2026-04-21 (most sources) | — | [Build Fast with AI](https://www.buildfastwithai.com/blogs/chatgpt-images-2-0-gpt-image-2-2026); [Apiyi](https://help.apiyi.com/en/gpt-image-2-official-launch-beginner-complete-guide-en.html) |
| Google I/O 2026 claim | May 2026 | **900M** Gemini monthly active users; **50B+** Nano Banana images (single source, unverified) | [Glitchwire](https://glitchwire.com/news/google-claims-900-million-gemini-users-and-50-billion-nano-banana-images-at-io-2/) |
| Appfigures analysis | May 2026 | Image and video model updates drive **6.5x** more incremental downloads. Nano Banana: about **22M** incremental downloads and about **$181K** incremental spend in 28 days. GPT-4o image: about **$70M** in 28 days | [Appfigures](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads); [TechCrunch](https://techcrunch.com/2026/05/04/image-ai-models-now-drive-app-growth-beating-chatbot-upgrades/) |

**Implications:**
- Generic text-to-image is a free feature of ChatGPT and Gemini.
- A paid standalone app has to win on:
  1. finished, specific outcomes,
  2. identity fidelity,
  3. speed to each trend, and
  4. a trustworthy price.

### 1.5 Category trends, 2025–2026

1. **Edit-by-instruction models made templates into the product.** Incumbents plug in frontier models. Remini integrated Nano Banana and its weekly installs rose **175% to 1.16M** ([PR Newswire, 2025-11-14](https://www.prnewswire.com/news-releases/bending-spoons-remini-app-hits-1-16-million-weekly-installs-following-integration-of-googles-nano-banana-ai-model-302615284.html)).
2. **Spikes fade quickly.**
   - Business of Apps notes Remini dropped back to its "usual download rate of 8 – 12 million" after a spike. The period was not stated, and the search summary did not identify the exact page ([Business of Apps data hub](https://www.businessofapps.com/data/)).
   - Remini's 2025 downloads fell 24.5% ([AppTweak](https://www.apptweak.com/en/reports/most-downloaded-photo-video-apps)).
3. **Hybrid monetization is now standard: subscription plus credits or coins.**
   - Picsart Pro includes 500 credits a month.
   - YouCam AI Pro and Glam AI sell credit and coin packs (§6.5).
   - At Higgsfield, subscriptions fell from **more than 90% to just over 60%** of revenue as on-demand usage grew ([Higgsfield](https://higgsfield.ai/blog/higgsfield-1b-annualized-revenue-run-rate)).
4. **Video is creeping in.**
   - Glam AI charges coins for video.
   - FaceApp is moving video into a separate app ([App Store](https://apps.apple.com/us/app/faceapp-perfect-face-editor/id1180884341)).
   - Higgsfield's template video business is at a $1B run rate.
5. **"AI" saturates store metadata.** MobileAction's 2026 analysis found "AI" is the **#1 most-used keyword** in Photo & Video metadata, above "photo", "video" and "camera" ([NeoAds / MobileAction](https://neoads.substack.com/p/ai-is-the-most-used-keyword-in-6)).
6. **There is a backlash against the AI look.** Examples are the "2026 is the new 2016" nostalgia trend ([Wikipedia](https://en.wikipedia.org/wiki/2026_is_the_new_2016)) and film-grain "imperfection" edits ([eWeek, 2026-05-19](https://www.eweek.com/news/ai-photo-editing-trends-2026/)).
7. **Safety and regulation are rising.**
   - The Grok "undressing" scandal (January 2026) led Malaysia and Indonesia to block Grok, and the UK, EU and California to open probes ([AP via WTVM, 2026-01-15](https://www.wtvm.com/2026/01/15/grok-blocked-undressing-images-places-where-its-illegal-x-says/)).
   - Gemini restricts Nano Banana 2 editing to users 18 and over ([Workspace Updates](https://workspaceupdates.googleblog.com/2026/02/introducing-nano-banana-2-in-gemini-app.html)).

---

## 2. Competitor landscape (15 apps)

> **About subtitles:** apps.apple.com could not be fetched directly and the search index did not expose the subtitle field, so **App Store subtitles are "unknown" for every app**. The table gives the **title keyword pattern** from the indexed titles. Pull subtitles with AppTweak or Appfigures before doing ASO work.
>
> **About ratings and prices:** these are search-index **snapshots** of the US storefront unless noted. Capture dates are unknown and some are old.

### 2.1 Table A: who they are, what they do, how they position

| # | App (indexed US title) | Developer | Core AI features | Positioning (listing or coverage) | Title keyword pattern |
|---|---|---|---|---|---|
| 1 | **Remini - AI Photo Enhancer** (Canadian title: "Remini - AI Photo Editor") | Bending Spoons (seller: Bending Spoons Apps ApS) | Enhance and unblur; restore old photos; face enhance; generative "photos of you" (headshots, 90s yearbook, anime, future baby, age progression); Nano Banana-powered edits since November 2025 | Turns "old, blurry, or low-resolution photos into clear, high-definition images in one tap" ([mwm.ai listing copy](https://mwm.ai/apps/remini-ai-photo-enhancer/1470373330)) | Brand + "AI Photo Enhancer / Editor" |
| 2 | **Lensa AI: Photo Editor** | Prisma Labs | Selfie retouch, background tools, **Magic Avatars** packs, AI art | Retouch plus avatars; viral in December 2022 ([App Store](https://apps.apple.com/us/app/lensa-ai-photo-editor/id1436732536)) | Brand + "AI: Photo Editor" |
| 3 | **Picsart AI Photo Editor, Video** | Picsart, Inc. | Full editor plus AI enhance, background remove and replace, generation, templates and video. "Earn with Picsart" creator payouts (April 2026) | All-in-one creative platform. **150M+ monthly active users** (company figure) ([TNW](https://thenextweb.com/news/picsart-earn-creator-monetisation-programme)) | Brand + "AI Photo Editor, Video" |
| 4 | **Photoroom: AI Photo Editor** | Photoroom (France) | Background removal, AI backgrounds and shadows, batch editing, marketplace templates, web and API | Product photos for sellers and small businesses. On all three a16z lists in October 2026 ([a16z 7th edition](https://a16z.com/100-gen-ai-apps-7/)) | Brand + "AI Photo Editor" |
| 5 | **Facetune: Photo & Video Editor** (other storefronts: "Facetune AI Photo/Video Editor", "Facetune: Photo Retouch & AI") | Lightricks | Face and body retouch, AI makeup and hair, AI headshots and avatars, video retouch | Selfie and video retouch for creators. Lightricks once said about 30% of users were small businesses ([Glossy](https://www.glossy.co/beauty/the-company-behind-facetune-goes-after-beauty-influencers-and-small-businesses)) | Brand + "Photo & Video Editor" |
| 6 | **Hypic - Photo Editor & AI Art** | Bytedance Pte. Ltd. | Beauty retouch, AI art styles, templates | Appfigures: "threatening" Facetune, Picsart, Photoroom, VSCO and Lightroom ([Appfigures](https://appfigures.com/resources/this-week-in-apps/20251219)) | Brand + "Photo Editor & AI Art" |
| 7 | **Dawn AI - Avatar generator** (newer listing: "Dawn - AI Avatars") | Seller changed from Mosaic S.r.l. to **Splice Video Editor srl**; terms point to bendingspoons.com ([App Store](https://apps.apple.com/us/app/dawn-ai-avatar-generator/id1643890882)). ScreensDesign attributes it to Codeway, which conflicts | AI avatars and profile packs from selfies | Avatar generator; this category has faded | Brand + "Avatar generator" |
| 8 | **Wonder - AI Art Generator** | Codeway (seller shown as Deep Flow Software Services or Codeway Dijital Hizmetler A.Ş., depending on snapshot) | Text-to-image art, styles, avatar packs | Prompt-to-art ([App Store](https://apps.apple.com/us/app/wonder-ai-art-generator/id1621278575)) | Brand + "AI Art Generator" |
| 9 | **FaceApp: Perfect Face Editor** | FaceApp Technology Ltd | Face transforms (age, gender, smile), makeup, hair, retouch. Video is being moved to a separate app | Fun face transformations plus beauty edits ([App Store](https://apps.apple.com/us/app/faceapp-perfect-face-editor/id1180884341)) | Brand + "Perfect Face Editor" |
| 10 | **YouCam Perfect: AI Photo Editor**, plus **YouCam AI Pro** | Perfect Corp. | Beauty retouch, object removal, **"AI Professional Photo"** (LinkedIn-style headshots, "digital twin"), 50+ styles from one selfie, Nano Banana trend templates | Beauty plus AI headshots ([YouCam AI Pro listing](https://apps.apple.com/us/app/-/id6451239387); [Perfect Corp blog](https://www.perfectcorp.com/consumer/blog/generative-AI/nano-banana-trends)) | Brand + "AI Photo Editor" |
| 11 | **Meitu AI Photo & Video Editor** | Meitu | Beauty retouch, AI "digicam" styles, AI expand and art, video | Beauty and retouch, with AI features reserved for VIP ([App Store](https://apps.apple.com/us/app/meitu-ai-photo-video-editor/id416048305)) | Brand + "AI Photo & Video Editor" |
| 12 | **EPIK - AI Photo & Video Editor** | SNOW Corp. (Naver) | AI Yearbook and profile packs, retouch, templates | Viral AI photo packs ([App Store](https://apps.apple.com/us/app/epik-ai-photo-video-editor/id1577705074)) | Brand + "AI Photo & Video Editor" |
| 13 | **Glam AI: Video & Photo Editor** | Glam Labs, Inc. | Trend templates for photo and video, AI hair and outfits, video effects | Studio built around trend templates ([App Store](https://apps.apple.com/us/app/glam-ai-video-photo-editor/id1545593132?see-all=reviews)) | Brand + "Video & Photo Editor" |
| 14 | **Retake AI Face & Selfie Editor** (also listed as "Retake AI: Face & Photo Editor") | Deep Flow Software Services (Codeway, per [ScreensDesign](https://screensdesign.com/showcase/retake-ai-face-selfie-editor)) | Regenerates your selfies at your best (smile, eyes, pose) | Selfie perfection ([App Store](https://apps.apple.com/us/app/retake-ai-face-selfie-editor/id6466298983)) | Brand + "Face & Selfie Editor" |
| 15 | **"PhotoAI"** (ambiguous) | Several small App Store namesakes. Figures for the web leader photoai.com were **not verified** | Headshots and photoshoots | "PhotoAI - AI Photoshoots": credits $0.99–$4.99 ([App Store](https://apps.apple.com/bb/app/photoai-ai-photoshoots/id6471078784)). "PhotoAI Enhancer, Image Editor": 4.3 stars from 240 ratings, $6.99 unlimited ([App Store](https://apps.apple.com/us/app/photoai-enhancer-image-editor/id1563607678)) | Brand + "AI Photoshoots / Enhancer" |

### 2.2 Table B: monetization, ratings and scale

| App | Price signals (US unless noted) | Trial, credits, paywall | US rating (snapshot) | Revenue or scale signal |
|---|---|---|---|---|
| **Remini** | Pro Weekly **$9.99**; Lite Weekly **$3.99–$7.99**; Pro Yearly **$79.99** (App Store in-app purchase snapshots, [App Store](https://apps.apple.com/us/app/remini-ai-photo-enhancer/id1470373330)). Third-party 2026: **$6.99–$9.99 a week**, about **$99.99 a year** ([Magic Memory](https://magic-memory.dev/vs/remini); [Morphed](https://morphed.app/blog/remini-free-limits)) | 7-day trial reported. Paywall offers weekly or yearly with a free trial; an "Other plans" link reveals a cheaper Lite plan as a downsell ([ScreensDesign](https://screensdesign.com/showcase/remini-ai-photo-enhancer)). Free tier has daily caps and watermarks (third-party) | **4.6 (356K)** | AppMagic **$75M** (2025). Appfigures about **$93M a year** after fees. **132.6M** downloads (2025) |
| **Lensa** | In-app purchases from **$2.99** (1-week pass) to **$49.99**; membership about **$35.99** (snapshot). Third-party 2026: about **$3.99 a week** or **$29.99 a year** ([Plisio](https://plisio.net/ai/lensa-ai)) | Avatar packs extra: **$3.99–$11.99**, for example 50 avatars at $3.99 (non-subscriber) or $1.99 (subscriber). Annual subscribers get **50% off** avatars (developer reply) | **4.7 (418K)** | ScreensDesign estimate about **$350K a month** (date unknown) ([ScreensDesign](https://screensdesign.com/apps/lensa-ai-photo-video-editor/)) |
| **Picsart** | Gold Annual **$57.00**, Monthly **$12.99** (snapshot; an older snapshot shows $29.99 a year and $8.99 a month) ([App Store](https://apps.apple.com/us/app/picsart-ai-photo-editor-video/id587366035)) | Gold became **Pro with 500 credits a month, no rollover**. Some AI tools charge credits **on top of** the subscription ([AI Tools Police](https://aitoolspolice.com/reviews/picsart/); [CheckThat](https://checkthat.ai/brands/picsart/reviews)) | **4.7 (1.2M)** | AppMagic **$79M**. a16z mobile #6 |
| **Photoroom** | Web plans (August–September 2026, third-party sources): Pro about **$12.99 a month** (about $7.50 a month billed annually); Max about **$20.99 a month** billed annually (**$34.99** monthly); Ultra **$99 a month** or **$82.50 a month** billed annually ([eesel](https://www.eesel.ai/blog/photoroom-pricing); [promoclock](https://promoclock.co/en/tools/photoroom/)). App Store snapshot: Max Weekly **$4.99**, Max Yearly **$79.99**. Weekly Pro **$2.99** per WearView, which conflicts with other sources ([WearView](https://www.wearview.co/blog/photoroom-pricing)) | 7-day trial (older listing). Free exports (older developer statement: up to 250 a month). Paywall compares weekly and annual with **annual preselected** and a "Start Free Trial" button ([ScreensDesign](https://screensdesign.com/apps/photoroom-ai-photo-editor/?ts=0&vt=1&id=581&av=1816)) | **4.8 (230K)** | AppMagic **$47M** (app only). About **$94M ARR** at end-2024 across all channels (secondary source) |
| **Facetune** | Web (August 2026): **$25 a month**, **$40 a quarter**, **$77.99 a year** ([facetuneapp.com](https://www.facetuneapp.com/pricing)). App Store entries at **$7.99** and **$9.99** ([App Store](https://apps.apple.com/us/app/facetune-photo-video-editor/id1149994032)) | **7-day trial** | **4.6 (379K)** | AppMagic **$113M** |
| **Hypic** | HypicPro **$10.99 a month**, **$69.99 a year** (snapshot; another snapshot shows $6.99 a month) ([App Store](https://apps.apple.com/us/app/hypic-photo-editor-ai-art/id1644042837)) | Watermark removal capped (one review says 30 times) | **4.7 (17K)** | AppMagic **$88M** vs Appfigures about **$6.7M** (January–November 2025): **conflict**. a16z mobile #24 |
| **Dawn AI** | Weekly "Dawn Pro" tiers. One-time "AI Profile Creation" **$1.99** ([App Store](https://apps.apple.com/us/app/dawn-ai-avatar-generator/id1643890882)) | Pack plus subscription | **4.7 (31K)** older listing; **4.6 (1.4K)** newer | ScreensDesign shows **$8K–$65K a month**, internally inconsistent ([ScreensDesign](https://screensdesign.com/apps/dawn-ai-avatar-generator/)) |
| **Wonder** | "Wonder Premium" entries at **$4.99** and **$29.99** (periods not shown); avatar pack **$2.99**; lifetime option offered | Free use capped at **5 a day**. One reviewer says lifetime buyers were later asked to buy credits | **4.3 (65K)** or **4.5 (20.1K)**, depending on snapshot | Unknown |
| **FaceApp** | Pro in-app purchases priced **$10–$100** ([App Pricing Lab tracker, March 2026](https://apppricinglab.com/iap/apple/1180884341)). Third-party estimates of about **$4.99 a week** and **$19.99–$39.99 a year** ([aisotools](https://aisotools.com/blog/faceapp-review-2026)). Lifetime Pro removed | Trial availability varies by country (unconfirmed) | **4.7 (1.8M)** | AppMagic **$150M** (#1 photo app by revenue after CapCut) |
| **YouCam (AI Pro)** | AI Pro: Pro **$69.99 a year** or **$9.99 a week**; Premium **$29.99–$39.99 a year** or **$4.99–$6.99 a week**. YouCam Perfect EU: Pro **€59.99 a year** | **Credit packs:** 90 credits **$6.59**, 600 credits **$23.99** (subscriber prices). Complaint about a "100 times per day" cap | **YouCam Perfect 4.8 (119K)** ([App Store](https://apps.apple.com/us/app/youcam-perfect-ai-photo-editor/id768469908?see-all=reviews)) | Perfect Corp. revenue not researched (unknown) |
| **Meitu** | VIP **$8.99 a week**, **$12.99 a month**, **$59.99 a year** ([App Store](https://apps.apple.com/us/app/meitu-ai-photo-video-editor/id416048305)) | VIP removes watermark and ads; VIP+ covers multiple devices | **4.8 (about 80K)** | AppMagic **$121M**. Meitu Inc. has **16.91M** paying subscribers |
| **EPIK** | PRO **$0.99** (1 week), **$11.99** (1 month), **$51.99** (period not shown). "Yearbook Express" pack **$5.99** (old snapshot) | One-off packs plus subscription | **4.7 (55K)** (old snapshot) | ScreensDesign about **$850K a month** (unverified) |
| **Glam AI** | Glam Lite **$7.99**; several Pro tiers; coins: **+5,000 for $34.99**, **+20,000 for $125.99** | **No-trial soft paywall** at the end of onboarding with a **10-minute countdown** and a weekly price breakdown ([ScreensDesign](https://screensdesign.com/showcase/glam-ai-video-photo-editor)). Image edits are unlimited; **video costs coins** (developer reply) | **4.5 (31K)** | ScreensDesign **$550K–$850K a month** (inconsistent) |
| **Retake AI** | Pro about **$9.99 a week** (reviews); **$59.99 a year** | **7-day trial on a single weekly plan, shown very early in onboarding** ([ScreensDesign](https://screensdesign.com/showcase/retake-ai-face-selfie-editor)) | **4.6 (52K)** | ScreensDesign **$1.75M–$2.3M a month** (inconsistent) |

**Patterns in the competitor set:**
- **Titles** follow "Brand + AI Photo Editor / Enhancer / Art Generator", with "& Video" increasingly added.
- **AI-native apps** (Remini, Retake, Glam, Dawn) default to **weekly plans** with or without a trial. **Incumbents** (Picsart, Photoroom, Facetune web) push monthly or annual plans plus credits.
- **Ratings sit at 4.3–4.8** despite heavy billing complaints, so star ratings don't differentiate apps; review text does.
- **Weekly pricing is 6.5x the annual price** for Remini: $9.99 × 52 = $519 vs $79.99 a year (derived).

### 2.3 Indirect competitors

- **ChatGPT** (GPT Image 1.5 and then GPT Image 2; Images tab with presets).
- **Gemini** (Nano Banana, Nano Banana Pro and Nano Banana 2; about 650M monthly active users in Q3 2025).
- **Meta AI** and **Grok** (Grok is hit by the January 2026 safety scandal).
- **Creative suites:** CapCut and Canva.
- **Template video:** Higgsfield and PixVerse ([Sacra](https://sacra.com/c/higgsfield/); [hixx.ai](https://www.hixx.ai/blog/awesome-ai-tools/pixverse-ai-video-generation)).

---

## 3. What users love and what they hate

**Method:**
- **Reddit was not reachable** with the available tools.
- Evidence comes instead from App Store reviews surfaced via search, Trustpilot, Sikayetvar/Xolvie, Apple Community, G2, review aggregators and press.
- **Rankings reflect how widely a theme recurs across apps and sources**, not a statistical count.
- Quotes are short excerpts as they appeared in the source. Paraphrases are marked "(paraphrase)".

### 3.1 Top 8 love-drivers

| Rank | Driver | Evidence | Representative phrase (source) |
|---|---|---|---|
| 1 | **Instant one-tap "wow"** (before and after, restore, unblur) | Remini's core promise; Fstoppers; Retake and Wonder reviews | "can resurrect images where you missed focus" ([Fstoppers headline](https://fstoppers.com/apps/fstoppers-reviews-remini-ai-photo-enhancing-app-can-resurrect-images-where-you-536459)). "a brilliant tool capable of astounding results" ([Wonder review](https://apps.apple.com/us/app/wonder-ai-art-generator/id1621278575)) |
| 2 | **Looks like me, only better** | Positive headshot reviews. OpenAI marketed GPT Image 1.5 on preserving facial likeness | "looked just like me, just a little better" ([BetterPic, Trustpilot](https://ca.trustpilot.com/review/betterpic.io)). "simply accentuates my best features and removes flaws" ([Retake review](https://apps.apple.com/us/app/retake-ai-face-selfie-editor/id6466298983?see-all=reviews)) |
| 3 | **Trend-ready templates** (be part of the moment) | Ghibli, figurine and caricature waves. Template apps shipped copies within days ([Perfect Corp](https://www.perfectcorp.com/consumer/blog/generative-AI/photo-to-figurine-app)) | "I tried the new ChatGPT caricature trend and was shocked how well the AI chatbot knows me" ([TechRadar headline](https://www.techradar.com/ai-platforms-assistants/chatgpt/i-tried-the-new-chatgpt-caricature-trend-and-was-shocked-how-well-the-ai-chatbot-knows-me)) |
| 4 | **Emotional and nostalgic value** | Old-photo restoration; "hug my younger self"; 2016 nostalgia | "Sometimes we just have to hug our inner 8 year old" (Alia Bhatt, [Republic World](https://www.republicworld.com/entertainment/celebrities/alia-bhatt-reacts-to-gemini-s-hug-my-younger-self-trend-with-heartfelt-message-sometimes-we-just-have-to-hug-our-inner-8-year-old)) |
| 5 | **A usable free tier** | Picsart, Meitu and older EPIK reviews | "easily used and viable for non members" ([Picsart review](https://apps.apple.com/us/app/picsart-ai-photo-editor-video/id587366035)). "you can still get a lot out of it without having to pay" ([Meitu review](https://apps.apple.com/us/app/meitu-ai-photo-video-editor/id416048305)) |
| 6 | **Speed and no learning curve** (no prompting) | A PhotoDirector 3D-figure template delivers results in about 30 seconds. GPT Image 1.5 is up to 4x faster | "delivers the same results in just 30 seconds" ([Perfect Corp](https://www.perfectcorp.com/consumer/blog/generative-AI/photo-to-figurine-app)) |
| 7 | **All-in-one breadth** | Picsart: 82% favorable mentions according to an aggregator ([CheckThat](https://checkthat.ai/brands/picsart/reviews)) | A reviewer called it a huge win "because most apps make you pay for premium features" (paraphrase, [App Store](https://apps.apple.com/us/app/picsart-ai-photo-editor-video/id587366035)) |
| 8 | **Practical results** (headshots, product photos) | Remini's 2023 headshots wave: **22M+ downloads in 30 days** ([TechCrunch, 2023-07-20](https://techcrunch.com/2023/07/20/remini-tops-the-app-store-for-its-viral-ai-headshots-but-its-body-edits-go-too-far-some-say/)). Photoroom is on a16z's spend list. YouCam markets "AI Professional Photo" | (No direct quote collected.) |

### 3.2 Top 8 pain points

| Rank | Pain point | Evidence | Representative phrase (source) |
|---|---|---|---|
| 1 | **Weekly subscriptions, trial auto-conversion, charges after cancelling or deleting** | Remini ([Trustpilot](https://www.trustpilot.com/review/remini.me), [Sikayetvar](https://www.sikayetvar.com/en/remini-us), [Apple Community](https://discussions.apple.com/thread/256170196)); Retake; Facetune; Glam AI. An aggregator says Remini users report charges of **$5.99–$14.99 a week** ([CheckThat](https://checkthat.ai/brands/remini-ai/reviews)). One guide notes "$7.99/week" works out to "over $400 a year" ([Pixtide](https://pixtide.com/guides/photo-cleaner-subscription-trap)) | "charged weekly even though I've cancelled this subscription since may 3rd" (Remini, Trustpilot). "a whopping $9.99 a WEEK so that's roughly $40 a month" and "supposed to notify me before charging me instead I got charged $9.99" ([Retake reviews](https://apps.apple.com/us/app/retake-ai-face-selfie-editor/id6466298983?see-all=reviews)) |
| 2 | **Paywall creep** (free features moved behind the paywall) | Facetune, Hypic, Meitu, EPIK. On Picsart, G2 users say even "Background Remover" is paywalled ([G2](https://www.g2.com/products/picsart/reviews?qs=pros-and-cons)) | "even the makeup settings need a subscription to be used now" ([Hypic review](https://apps.apple.com/us/app/hypic-photo-editor-ai-art/id1644042837?see-all=reviews)) |
| 3 | **Credits or coins on top of subscriptions; failed attempts burn credits; "lifetime" or "unlimited" quietly changed** | Picsart (500 credits, no rollover); Wonder; Glam AI (coins spent on retries, "unlimited" removed) | "purchased a lifetime subscription; they updated their app; now I have to pay for credits" ([Wonder review](https://apps.apple.com/us/app/wonder-ai-art-generator/id1621278575)) |
| 4 | **Identity drift and face distortion** | Remini reviews; headshot apps (vendors call it "identity drift", [GetPhotoShoot](https://www.getphotoshoot.com/blog/ai-headshot-doesnt-look-like-me)); Dawn reviews | "messes up the eyes and teeth a lot" ([JustUseApp, Remini](https://justuseapp.com/en/app/1470373330/remini-ai-photo-enhancer/reviews)). Faces described as "wax figures" or "plastic" ([CheckThat](https://checkthat.ai/brands/remini-ai/reviews)). "none of them, at least for now, can consistently capture a true one-to-one likeness" ([Substack tester](https://jobsearchwithai.substack.com/p/i-spent-almost-80-on-ai-headshots)) |
| 5 | **Bias and unwanted sexualization** | Lensa, December 2022: a reporter got **16 topless avatars out of 100**, and users reported whitened skin ([Business Insider NL](https://www.businessinsider.nl/sex-art-theft-and-privacy-lensa-exploded-overnight-and-now-the-avatar-app-is-dealing-with-public-backlash-heres-what-you-should-know/); [AI Incident DB](https://incidentdatabase.ai/reports/2376)). Glam AI review | Generated images "anglicized features and hair for people of color" (paraphrase, [Glam AI review](https://apps.apple.com/us/app/glam-ai-video-photo-editor/id1545593132?see-all=reviews)) |
| 6 | **Privacy fears** (face data, training, consent, misuse) | Fonehouse study of 20 AI photo apps (December 2023): **more than a third** use user data for AI training, **1 in 4** keep facial data, **75%** require promotional rights to photos, **20%** don't allow deletion; Facetune was named among the worst ([IT Brief](https://itbrief.com.au/story/privacy-concerns-rise-over-popular-ai-photo-apps-study)). Common Sense gave FaceApp **57%, "Warning"** ([Common Sense](https://privacy.commonsense.org/privacy-report/FaceApp-AI-Face-Editor)). Grok scandal (January 2026) | The vintage-saree look is "a bit more dangerous" ([Kerala Kaumudi](https://www.keralakaumudi.com/en/news/news-amp.php?id=1611605)) |
| 7 | **Watermarks, low-resolution exports, daily caps** | Hypic (watermark removal capped at 30). Lensa (watermark; HD download locked for non-subscribers). Remini (free exports watermarked). Wonder (5 a day). YouCam AI Pro ("a few generations per day") | "can only use this feature 100 times per day" ([YouCam review](https://apps.apple.com/us/app/youcam-perfect-ai-photo-editor/id768469908?see-all=reviews)) |
| 8 | **Ads, failed generations, poor support and refunds** | Wonder reviewer ("after watching about 30 adds"). EPIK unskippable ad. Hypic AI fails for paying users. Picsart support says it can't refund App Store purchases. Remini Web allows weekly-plan refund requests within **20 days** of the charge ([Remini Web refund policy](https://remini-web.zendesk.com/hc/en-us/articles/37219108400401-Refund-Policy)) | "Asked for a refund, they want a blood sample for them to give you the money back." ([Remini, Trustpilot](https://www.trustpilot.com/review/remini.me)) |

### 3.3 Design rules that follow

- **Show the result before asking for money:** the "aha" comes before the paywall.
- **Make billing transparent:** send a trial-ending reminder, give a one-tap "how to cancel" deep link, and don't hide the renewal price.
- **Make credits fair:** automatically refund credits for failed or blocked generations, let credits roll over, and never downgrade "lifetime" or "unlimited" retroactively.
- **Protect likeness:** check the user's identity similarity before showing results, and make "make it look more like me" re-rolls free.
- **Test inclusive quality:** check skin tone and hair texture fidelity across demographics, and never use sexualized defaults.
- **Make privacy visible:** auto-delete face data, don't train on user photos, and limit realistic edits to the user's own face.

---

## 4. Viral trends, 2025–2026: what drove downloads

### 4.1 Timeline

| When | Trend | Engine | Measured or reported impact | Source |
|---|---|---|---|---|
| December 2022 | Lensa **Magic Avatars** | Fine-tuned diffusion models | Huge spike, then backlash over sexualization and whitening | [Business Insider NL](https://www.businessinsider.nl/sex-art-theft-and-privacy-lensa-exploded-overnight-and-now-the-avatar-app-is-dealing-with-public-backlash-heres-what-you-should-know/) |
| July 2023 | Remini **AI headshots** (TikTok) | Remini | Downloads **+138%** month on month in July 2023. SNOW's revenue rose about **1400%** after it launched "AI Profile" | [Sensor Tower](https://sensortower.com/blog/rapid-growth-and-competitive-dynamics-the-state-of-ai-photo-and-video-apps); [TechCrunch](https://techcrunch.com/2023/07/20/remini-tops-the-app-store-for-its-viral-ai-headshots-but-its-body-edits-go-too-far-some-say/) |
| From 2025-03-25 | **Studio Ghibli-style** portraits | GPT-4o image generation | **130M users, 700M images** in week 1. ChatGPT was the world's #1 app in March (about 46M downloads). **Remini: 7.3M downloads from March 29 to April 8**, 3.6M more than the same span earlier in March, while bidding on "ghibli" keywords. **ToonMe:** daily downloads rose from **under 15K to nearly 600K** in 10 days | [The Decoder](https://the-decoder.com/chatgpts-image-generation-explodes-with-700m-creations-in-first-week/); [9to5Mac](https://9to5mac.com/2025/04/11/chatgpt-was-the-worlds-most-downloaded-app-last-month/); [Appfigures, 2025-04-04](https://appfigures.com/resources/this-week-in-apps/20250404); [Insightrackr](https://blog.insightrackr.com/en/docs/AI-Image-Apps-Drove-Viral-Growth-with-Ghibli-Style-Trends) |
| April 2025 | **AI action figure / "starter pack"** (boxed doll with props) | ChatGPT | Started on LinkedIn and spread to Instagram, TikTok and Facebook. Brands such as Starbucks and NYX joined. A #StarterPackNoAI backlash followed. ChatGPT had about **52M** downloads in April | [AI News](https://www.artificialintelligence-news.com/news/chatgpt-got-another-viral-moment-with-ai-action-figure-trend/); [Appfigures](https://appfigures.com/resources/insights/20250502?f=3) |
| August–September 2025 | **3D figurine** ("1/7 scale commercialized figurine") | Gemini 2.5 Flash Image (Nano Banana) | Started with an influencer in **Thailand**, then spread to Vietnam and Indonesia. **23M first-time Gemini users and 500M images** by September 8. Gemini reached **#1 on the US App Store** (September 12). About **22M incremental downloads** in 28 days | [Yahoo / Business Insider](https://tech.yahoo.com/ai/gemini/articles/google-gemini-exec-says-nano-111112810.html); [TechCrunch](https://techcrunch.com/2025/09/16/gemini-tops-the-app-store-thanks-to-new-ai-image-model-nano-banana/); [Appfigures](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads) |
| September 2025 | **Retro Bollywood saree**; **polaroid selfies with celebrities** (for example Shah Rukh Khan); **"Hug my younger self"** polaroid | Nano Banana | Strongest in India. Celebrities joined: Alia Bhatt shared one. Storyboard18 covered the celebrity selfies on 2025-09-16 | [Storyboard18: saree](https://www.storyboard18.com/brand-makers/-80942.htm); [celebrity selfies](https://www.storyboard18.com/digital/google-gemini-nano-banana-trend-ai-powered-selfies-with-shah-rukh-khan-spark-frenzy-81018.htm); [hug trend](https://www.storyboard18.com/digital/how-to-follow-hug-my-younger-self-trend-instagrams-latest-viral-ai-fad-80989.htm); [TechCrunch India](https://techcrunch.com/2025/09/17/india-leads-the-way-on-googles-nano-banana-with-a-local-creative-twist) |
| September–November 2025 | **Standalone apps ride the wave** | Nano Banana via API | PhotoDirector shipped a 3D-figure template, and "Nano Banana Trending AI Photo" clones appeared. **Remini integrated Nano Banana: weekly installs +175% to 1.16M** | [Perfect Corp](https://www.perfectcorp.com/consumer/blog/generative-AI/photo-to-figurine-app); [PR Newswire](https://www.prnewswire.com/news-releases/bending-spoons-remini-app-hits-1-16-million-weekly-installs-following-integration-of-googles-nano-banana-ai-model-302615284.html) |
| 2025-11-20 | **Nano Banana Pro** | Gemini 3 Pro Image | **1B images in 53 days** | [9to5Google](https://9to5google.com/2026/01/12/gemini-nano-banana-pro-milestone/) |
| 2025-12-16 | **ChatGPT Images presets** ("K-pop star", "1980s VHS") | GPT Image 1.5 | The platform now offers one-tap templates itself | [TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpt-images-just-got-a-major-upgrade-and-it-could-change-how-we-all-create) |
| January 2026 | **"2026 is the new 2016"** nostalgia (oversaturated, flash-lit "Instagram 2016" look; AI used to recreate it) | Multiple tools | A claim of 1.7M TikTok posts is unverified | [Wikipedia](https://en.wikipedia.org/wiki/2026_is_the_new_2016); [Substack](https://aimeetsgirlboss.substack.com/p/2026-is-the-new-2016-so-i-asked-ai) |
| First week of February 2026 | **"Create a caricature of me and my job based on everything you know about me"** | ChatGPT memory plus image generation | Spread across Instagram, TikTok, X, Facebook and WhatsApp | [Free Press Journal](https://www.freepressjournal.in/amp/tech/chatgpt-caricature-trend-goes-viral-on-social-media-heres-how-to-create-your-own-ai-portrait); [TechRadar](https://www.techradar.com/ai-platforms-assistants/chatgpt/i-tried-the-new-chatgpt-caricature-trend-and-was-shocked-how-well-the-ai-chatbot-knows-me) |
| 2026-02-26 / 2026-04-21 | **Nano Banana 2** / **ChatGPT Images 2.0 (GPT Image 2)** | Platform model upgrades | Each new model release restarts the trend cycle | [Google](https://blog.google/innovation-and-ai/technology/ai/nano-banana-2/); [Build Fast with AI](https://www.buildfastwithai.com/blogs/chatgpt-images-2-0-gpt-image-2-2026) |
| May 2026 | Film-look **"imperfection"** (grain, light leaks), **toy-ification / chibi** in packaging, **cinematic history-hopping**, vintage camcorder, **fake movie posters**, scrapbook collages, Y2K, **pet-to-human** | ChatGPT, Gemini, Meta AI, Qwen, Firefly, FLUX | Editorial roundup, not measured | [eWeek, 2026-05-19](https://www.eweek.com/news/ai-photo-editing-trends-2026/); [TechRepublic](https://www.techrepublic.com/article/news-ai-photo-editing-trends-2026/) |
| June–July 2026 | **FIFA World Cup 2026**: cinematic jersey posters and **Panini-style sticker cards** | Gemini (Nano Banana update) and ChatGPT | Mostly prompt sites; reach unverified | [media.io](https://www.media.io/ai/image-to-image/world-cup-stickers-prompts-chatgpt); [NewsBharat360](https://www.newsbharat360.com/news/sports/how-to-create-your-own-figurine-from-the-2026-world-cup-album-easy-and-free-with-ai-4444) |

### 4.2 Which template types convert best

The first four points are drawn from the evidence above; the last is a hypothesis.

1. **"Me, transformed" identity templates are the dominant viral format.** Figurine, action figure, caricature, celebrity polaroid, hug-my-younger-self, yearbook and headshots all fit it, and every major wave since 2023 was one. Two things drive them: the user's own face in a novel frame creates the urge to share, and the output is instantly comparable with the original.
2. **Templates with a practical payoff monetize better than pure novelty.**
   - Remini's 2023 headshots wave pushed it to #1.
   - Photoroom is the only AI-native image app on a16z's 2026 consumer-spend list ([a16z](https://a16z.com/100-gen-ai-apps-7/)).
3. **Novelty on free platforms doesn't monetize by itself.** Nano Banana's 22M incremental downloads brought about $181K of incremental spend ([Appfigures](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads)). Paid apps captured value by:
   - bidding on trend keywords (Remini bought "ghibli" terms), and
   - packaging the trend as a paid, one-tap template (PhotoDirector, YouCam).
4. **Emotional and nostalgic templates earn shares and celebrity pickup.** Hug-my-younger-self, restoration and the 2016 or retro looks fall here.
5. *Hypothesis; no conversion data was found:* video versions of photo trends (figurine to video; the eWeek "vintage camcorder" format) extend a wave's life. Higgsfield shows how big template-driven video can get.

### 4.3 Why one-tap templates matter

- **They solve the blank-page problem.**
  - a16z describes the approach as "lowering the threshold with templates" ([36Kr summary of a16z's year-end review](https://eu.36kr.com/en/p/3617288649536004)). Earlier a16z writing predicted that generation tools would solve the "blank page" problem ([a16z](https://a16z.com/the-future-of-prosumer-the-rise-of-ai-native-workflows/)).
  - ChatGPT replaced the empty box on its image page with example prompts (holiday cards, sketch portraits, animal costumes) and later with an Images tab of presets.
- **Day 0 is everything.**
  - **91.2%** of Photo & Video trial starts happen on Day 0 ([Adapty 2026](https://adapty.io/state-of-in-app-subscriptions-report/)).
  - Across categories, **82%** of trial starts occur within the first day after install ([RocketShip HQ summary of RevenueCat 2025](https://www.rocketshiphq.com/revenuecat-state-of-subscription-apps-2025-summary/)).
  - A template that delivers a result in the first minute is how users reach the "aha" before the paywall.
- **Templates are both the distribution and the upsell.**
  - Higgsfield's **100+ cinematic templates**, combined with seeding through paid creators, were linked to **20M+ users and 300K paying subscribers** ([Product Growth teardown](https://www.productgrowth.blog/p/higgsfield-growth-teardown)).
  - Templates also nudge users towards longer clips and higher resolutions ([Sacra](https://sacra.com/c/higgsfield/)).
  - **Caveat:** when influencers' template demos looked better than what typical users got, it created backlash ([same teardown](https://www.productgrowth.blog/p/higgsfield-growth-teardown)).
- **Platforms copy quickly.** ChatGPT's presets mean a standalone app must be **faster on trends**, **better at likeness** and **more finished**: correct aspect ratios, motion versions, multi-image consistent sets and print-quality output.

### 4.4 Trend operations playbook (recommendation)

- **Monitoring:** watch TikTok, Instagram and X daily, plus Southeast Asian and Indian creators. The figurine trend began in Thailand and the saree trend in India.
- **Ship fast:** aim for a template **within 24–48 hours** of a trend breaking.
- **Show it everywhere:** put a "Trending now" row at the top of the home screen, and swap App Store Custom Product Pages and Apple Ads keywords to match the trend. Remini's "ghibli" keyword buying is the precedent.
- **Package trends as one-off packs.** For example: "World Cup sticker pack: 6 cards".
- **Stay legal:** avoid third-party trademarks and artist names in store metadata.

---

## 5. Target audience

### 5.1 Demographic evidence (sparse; mostly indirect)

| Signal | Finding | Date | Source |
|---|---|---|---|
| Gemini after Nano Banana | "Huge growth" in the **18–34** cohort; the app shifted from "heavily male-skewed" towards **more female** users | Late 2025 | [Yahoo / Business Insider](https://tech.yahoo.com/ai/gemini/articles/google-gemini-exec-says-nano-111112810.html) |
| Sensor Tower State of Mobile 2025 | People aged **18–24** tend to choose creative categories such as Photo/Video and Graphics/Design. **Women are 2x as likely** to use Graphics & Design apps | Published February 2025 | [BYYD summary](https://www.byyd.me/en/blog/2025/02/state-of-mobile-2025-key-data/) |
| Business of Apps | **Gen Z** spends disproportionately more time in photo and video editing apps | 2026 | [Business of Apps data hub](https://www.businessofapps.com/data/) (via search summary; exact page not identified) |
| Facetune | About **70%** of subscribers are women (Lightricks) | About 2019 (dated) | [Scripps News](https://www.scrippsnews.com/science-and-tech/the-big-business-of-photo-filters) |
| remini.ai website (not the app) | **60% male / 40% female**; largest age group **25–34**; **India** the top desktop-traffic country | October 2025 | [SimilarWeb](https://www.similarweb.com/website/remini.ai/) |
| Teens and filters | **80%** of girls had used a filter or retouching app by age 13 (Dove survey of 556 girls aged 10–17; some sources describe it as a Canadian study) | 2020 | [RCI](https://www.rcinet.ca/en/2021/04/20/most-young-women-changing-their-looks-for-social-media-survey/) |

**Reading:**
- Beauty and selfie retouch skews **female, 18–34**.
- Generative "fun" and enhancement tools are more gender-balanced. Remini's web audience leans male.
- Platform image tools are pulling in **younger and female** users.
- There is a real **minors issue**. Gemini limits Nano Banana 2 editing to 18+. Consider age-gating realistic face edits.

### 5.2 Regions

- **Downloads come from Asia, money from North America.**
  - Asia accounts for **42.6%** of generative-AI downloads.
  - North America accounts for **11%** of downloads but **40%** of in-app purchase revenue (H1 2025) ([Sensor Tower](https://sensortower.com/blog/state-of-ai-apps-report-2025)).
  - The **US** is **more than 66%** of global spend on AI graphic editor and generator apps (2023–24 data, [Statista/Appfigures](https://www.statista.com/statistics/1607453/top-markets-for-ai-graphic-generators)).
- **India** is a trend engine and a source of volume.
  - Sam Altman named India a key driver of the Ghibli wave ([The Decoder](https://the-decoder.com/chatgpts-image-generation-explodes-with-700m-creations-in-first-week/)).
  - Nano Banana trends there (saree, figurines, celebrity polaroids) were local ([TechCrunch](https://techcrunch.com/2025/09/17/india-leads-the-way-on-googles-nano-banana-with-a-local-creative-twist)).
  - India is low-ARPU. RevenueCat's median monthly price is **$9.99 in North America vs $3.75 in India and Southeast Asia**, and the yearly median is **$39.99 vs $18.32** ([PricePush summary of RevenueCat 2026](https://newsletter.pricepush.app/p/i-read-all-336-pages-of-revenuecats)).
- **Southeast Asia** (Thailand, Vietnam, Indonesia) seeded the figurine trend ([Yahoo / Business Insider](https://tech.yahoo.com/ai/gemini/articles/google-gemini-exec-says-nano-111112810.html)).
- **High-ARPU growth regions:** most of Meitu's new overseas payers came from **Europe, the Americas and East Asia** ([Yahoo Finance](https://finance.yahoo.com/sectors/technology/articles/meitu-2025-annual-results-adjusted-132500863.html)).
- **Refund risk in Korea and APAC:** Photo & Video trial refunds run at **14.1% in APAC** vs **6.4%** globally ([Adapty 2026](https://adapty.io/state-of-in-app-subscriptions-report/)).
- **For an English-language iOS launch:**
  - **Monetize** in the US first, then the UK, Canada and Australia. There is no category-specific data for these three; this is a recommendation.
  - **Use India and the Philippines** for virality and ratings volume, with lower-priced packs.

### 5.3 Jobs-to-be-done segments

| Segment | Job | Main incumbents | Willingness-to-pay signal | Fit for a new entrant |
|---|---|---|---|---|
| **Selfie and beauty** | "Make me look my best without looking edited" | Facetune ($113M), FaceApp ($150M), Meitu ($121M), Hypic, YouCam, Retake | High; women-skewed; repeat use | Crowded, but complaints about likeness and paywalls leave room |
| **Social trends and content creators** | "Put my face in today's trend, now" | Glam AI, Picsart, Hypic, plus free ChatGPT and Gemini | Spiky; driven by packs and impulse | Good **if** the app is faster than the platforms and its output is finished |
| **E-commerce sellers** | "Clean product photos that sell" | Photoroom ($47M app; on a16z's spend list), Picsart | High; business use, often web | A different product (B2B workflows); don't lead with it |
| **Old-photo restoration and memories** | "Restore and revive family photos" | Remini ($75M), MyHeritage | One-off and emotional | A great **one-off pack** and gifting use case |
| **Fun, memes and avatars** | "Laugh and share" | FaceApp, Lensa, Dawn, Wonder | Avatar packs faded (Dawn estimated at $8K–$65K a month) | A low-value standalone category; use it to drive acquisition |
| **Professional headshots** | "LinkedIn or dating-ready photo without a photographer" | Remini, YouCam "AI Professional Photo", EPIK, web tools (BetterPic and others) | One-off spend. One tester spent "almost $80" across tools ([Substack](https://jobsearchwithai.substack.com/p/i-spent-almost-80-on-ai-headshots)) | Strong for **packs**. **Likeness is the #1 complaint**, which is where to win |

### 5.4 Recommended beachhead

**Recommended core user:** women and men aged 18–34 in English-speaking markets who post on Instagram and TikTok.

**Lead jobs**, all "photos of me":
1. **Trend selfies**
2. **Glow-up retouch that still looks like me**
3. **Headshot and dating packs**

**Secondary hook:** old-photo restoration as a gifting pack.

---

## 6. Monetization benchmarks

### 6.1 RevenueCat State of Subscription Apps 2026 (released 2026-03-10)

The report covers 115,000+ apps and $16B+ in revenue, per [SaaStr](https://saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps-how-115000-mobile-apps-deliver-16b-in-revenue-whats-working-whats-quietly-killing-growth).

| Benchmark | Value | Source |
|---|---|---|
| **Photo & Video median trial-to-paid** | **22.2%**, the lowest category (top quartile above 33.1%; Travel 43.5%) | [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps); [Tasu](https://tasu.ai/library/trial-to-paid-conversion-rate-benchmark) |
| Photo & Video revenue milestones | **21.4%** of apps reach $1K monthly revenue; **7.3%** reach $10K | [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps) (via search summary) |
| Photo & Video "lifetime combo" usage | **33.0%**, the highest category (definition not visible in the snippet) | same |
| **Photo & Video renewal rates** | Median **annual** renewal **23%** (lower quartile 15%, upper quartile 35%). The post also lists **48% (monthly)** and **45% (weekly)**. It calls these "one-off project apps" with a "structural curse" | [RevenueCat blog](https://www.revenuecat.com/blog/growth/average-subscription-renewal-rates-by-app-category) |
| **Trial length vs conversion** (all categories) | Trials of 4 days or less: **25.5%**. 5–9 days: **37.4%**. 17–32 days: **42.5%** | [RevenueCat blog](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026); [SaaStr](https://saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps-how-115000-mobile-apps-deliver-16b-in-revenue-whats-working-whats-quietly-killing-growth) |
| Share of short trials | Trials of 4 days or less rose from **42.1% (2025)** to **46.5% (2026)** | same |
| Early trial cancellations | **84%** of 3-day-trial cancellations and **64%** of 7-day-trial cancellations happen on Day 0–1 | same |
| **Hard vs freemium** (download to paid by Day 35, median) | **10.7% hard paywall vs 2.1% freemium**, down about 2 points from 12.1% in 2025 | [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps); [RevenueCat blog](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026) |
| **Plan economics** | Annual plans earn about **2x the revenue per install** of monthly plans and about **5x** that of weekly. Weekly plans rarely exceed **30%** of a category's revenue, except Gaming (82%) | [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps); [Airbridge](https://www.airbridge.io/en/blog/weekly-vs-annual-subscription-app) |
| Year-one retention by plan | Yearly **20–40%**, monthly **6–14%**, weekly **1–2%** | [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps) |
| **AI apps vs non-AI apps** | **+41%** revenue per payer. Annual subscribers churn about **30% faster** (RevenueCat's own blog says 36%). 12-month retention **21.1% vs 30.7%**. Monthly **6.1% vs 9.5%**. Weekly **2.5% vs 1.7%**. Trial-to-paid about **52% higher**. Refunds **4.2% vs 3.5%** | [TechCrunch](https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows); [Geoly](https://www.geoly.ai/blog/ai-apps-retention-revenuecat-report); [RevenueCat blog](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026) |
| AI apps with high retention | Among **3,519** AI apps studied, the best keep **30.7%** of annual subscribers after a year, matching non-AI apps | [RevenueCat](https://www.revenuecat.com/blog/growth/ai-app-retention-study) |
| Price medians by region | Monthly: **$9.99** in North America vs **$3.75** in India and Southeast Asia. Yearly: **$39.99** vs **$18.32** | [PricePush](https://newsletter.pricepush.app/p/i-read-all-336-pages-of-revenuecats) |
| Typical price bands (third-party, unverified) | Weekly **$4.99–$6.99**; monthly **$7.99–$9.99**; annual **$29.99–$39.99** | A third-party article citing RevenueCat; attribution uncertain, probably [Airbridge](https://www.airbridge.io/en/blog/weekly-vs-annual-subscription-app) |

**RevenueCat 2025 for comparison** ([RocketShip HQ summary](https://www.rocketshiphq.com/revenuecat-state-of-subscription-apps-2025-summary/); [RevenueCat 2025](https://www.revenuecat.com/state-of-subscription-apps-2025)):
- Download-to-paid was **12.11%** for hard paywalls vs **2.18%** for freemium.
- **82%** of trial starts happen within the first day after install.
- Weekly-plan retention "rarely exceeds 10% at six months".

### 6.2 Adapty State of In-App Subscriptions (2025 and 2026)

- **2026 report** (16,000 apps, $3B) ([Adapty](https://adapty.io/state-of-in-app-subscriptions-report/); [Adapty blog](https://adapty.io/blog/mobile-app-monetization-2026/)):
  - Weekly plans made up **55.5%** of 2025 revenue across all categories. This conflicts with RevenueCat; the datasets differ.
  - **Photo & Video specifics:**
    - Trial refunds **6.4%** globally (**14.1% in APAC**, driven by Korea's refund rules).
    - **91.2%** of trial starts on Day 0.
    - Median one-year install LTV **$0.82**.
  - Install-to-trial at upper-mid prices is **9.8% for weekly vs 1.8% for annual** (cross-category).
- **2025 report** ([Adapty](https://adapty.io/blog/state-of-in-app-subscriptions-2025-in-10-minutes/)):
  - Weekly plans are **more than 50%** of revenue in Photo & Video.
  - Refund rate by plan: annual highest at **4.2%**, weekly lowest at **2.6%**.

**Reading:**
- Weekly plans convert installs to trials best and dominate revenue in this category today.
- Annual plans earn far more per install and retain far better.
- Photo & Video's low trial conversion and low renewals reflect episodic, project-like use. **Pair a subscription with one-off packs** instead of forcing everyone onto weekly plans.

### 6.3 Hard vs soft paywalls and the onboarding paywall

- **Evidence:**
  - Hard paywalls convert about **5x** better on a download-to-paid basis (10.7% vs 2.1%, RevenueCat 2026).
  - In this category, almost all trial starts happen on Day 0 (91.2%, Adapty).
- **Category practice** (ScreensDesign teardowns):
  - **Remini:** onboarding uses example images to show goals → paywall with a **free trial on weekly or yearly** → "Other plans" link reveals **Lite** as a downsell ([ScreensDesign](https://screensdesign.com/showcase/remini-ai-photo-enhancer)).
  - **Retake:** **paywall very early**; **7-day trial** on a **single weekly plan** ([ScreensDesign](https://screensdesign.com/showcase/retake-ai-face-selfie-editor)).
  - **Glam AI:** **no-trial soft paywall** at the end of onboarding with a **10-minute countdown timer** ([ScreensDesign](https://screensdesign.com/showcase/glam-ai-video-photo-editor)).
  - **Photoroom:** weekly vs annual comparison with **annual preselected** and "Start Free Trial"; the onboarding survey asks where the user heard of the app, then requests notification permission ([ScreensDesign](https://screensdesign.com/apps/photoroom-ai-photo-editor/?ts=0&vt=1&id=581&av=1816)).
  - **Most common among all-in-one editors:** a free trial with a soft paywall, according to a ScreensDesign category page seen in a search summary; the closest page found is [ScreensDesign's Facetune showcase](https://screensdesign.com/showcase/facetune-video-photo-editor).
- **Recommendation: a "result-first" hybrid paywall.**
  1. In onboarding, the user picks a trending template and uploads 1–3 selfies.
  2. The app shows a **low-resolution or watermarked preview** (the "aha").
  3. Then it shows the paywall: **annual preselected, with a 7-day trial**, plus monthly with no trial.
  4. A visible "Just this pack" one-time purchase acts as the downsell. This mirrors Remini's Lite downsell but without a weekly plan.
  5. Use **no fake countdown timers**; they feed the trust problems in §3.

### 6.4 Credit models in the category

| App | Model | Detail | Source |
|---|---|---|---|
| Picsart | Subscription plus monthly credits | Pro includes **500 credits a month, no rollover**; some AI tools cost credits on top | [AI Tools Police](https://aitoolspolice.com/reviews/picsart/) |
| YouCam AI Pro | Subscription plus credit packs | 90 credits **$6.59**; 600 credits **$23.99** (subscriber prices) | [App Store](https://apps.apple.com/us/app/-/id6451239387) |
| Glam AI | Subscription plus coins | +5,000 coins **$34.99**; +20,000 coins **$125.99**. Image edits unlimited, video costs coins | [App Store](https://apps.apple.com/us/app/glam-ai-video-photo-editor/id1545593132?see-all=reviews) |
| Lensa | Subscription plus avatar packs | **$3.99–$11.99** packs; subscribers get discounts | [Plisio](https://plisio.net/ai/lensa-ai); [App Store](https://apps.apple.com/us/app/lensa-ai-photo-editor/id1436732536) |
| Dawn | Weekly subscription plus one-time profile | **$1.99** "AI Profile Creation" | [App Store](https://apps.apple.com/us/app/dawn-ai-avatar-generator/id1643890882) |
| EPIK | Subscription plus one-off themed packs | "Yearbook Express" **$5.99** | [App Store](https://apps.apple.com/us/app/epik-ai-photo-video-editor/id1577705074) |
| Higgsfield | Subscription plus on-demand | Subscriptions fell from **more than 90% to just over 60%** of revenue | [Higgsfield](https://higgsfield.ai/blog/higgsfield-1b-annualized-revenue-run-rate) |

### 6.5 Per-image API costs (as of October 2026) and unit economics

| Model | Price per image | Notes | Source |
|---|---|---|---|
| Gemini 2.5 Flash Image (Nano Banana) | **About $0.039** standard; about half in batch | One guide says it retires **2026-10-02** | [MyArchitectAI](https://www.myarchitectai.com/blog/nano-banana-api-pricing); [BenchLM](https://benchlm.ai/media-pricing/nano-banana) |
| Nano Banana Pro (Gemini 3 Pro Image) | **$0.134** (1K or 2K); **$0.24** (4K); batch about half | No free API tier | same |
| Nano Banana 2 (Gemini 3.1 Flash Image) | About **$0.045** (0.5K) to about **$0.151** (4K) | Generally available 2026-05-28 | [BenchLM](https://benchlm.ai/media-pricing/nano-banana); [Google Cloud](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-1-flash-image) |
| Nano Banana 2.1 | **$0.0336** per 1K image (reported 2026-10-06) | **Single source; verify** | [TechAIWire](https://techaiwire.com/articles/nano-banana-2-1-gemini-image-model-half-price/) |
| gpt-image-1.5 | **$0.009 / $0.034 / $0.133** (low / medium / high, 1024×1024). Portrait or landscape about **$0.013 / $0.050 / $0.200** | Marked deprecated; a December 2026 shutdown is reported | [OpenAI](https://developers.openai.com/api/docs/models/gpt-image-1.5); [PricePerToken](https://pricepertoken.com/gpt-image-pricing) |
| GPT Image 2 | Calculator estimates for 1024×1024: about **$0.006 / $0.053 / $0.211** (low / medium / high). Billed at $30 per million image output tokens. Third-party hosts charge **$0.03–$0.08** (1K–4K) | Launched April 2026 | [AIFreeAPI (checked 2026-09-06)](https://www.aifreeapi.com/en/posts/openai-image-generation-api-pricing); [Unifically](https://unifically.com/blogs/gpt-image-2) |
| Seedream 4.0 | About **$0.03** (fal, Together) | | [PricePerToken](https://pricepertoken.com/fal-ai-pricing) |
| FLUX Kontext Pro / Max | **$0.04** / about **$0.08** | | [AnotherWrapper](https://anotherwrapper.com/tools/llm-pricing/image-models/flux-kontext-pro); [PricePerToken](https://pricepertoken.com/fal-ai-pricing) |

**Unit economics** (derived; before Apple's commission, which was not re-verified here):

**Annual plan at the North American median of $39.99 a year** (≈ **$0.77** a week):

| Usage per week | Model price per image | Weekly cost | Share of gross revenue |
|---|---|---|---|
| 10 generations | Flash-class, $0.039 | **$0.39** | **≈ 51%** |
| 10 generations | Pro-class, $0.134 | **$1.34** | **≈ 174%** (a loss) |

**Weekly plan at $6.99:**

| Usage per week | Model price per image | Weekly cost | Share of gross revenue |
|---|---|---|---|
| 40 generations | $0.039 | **$1.56** | **≈ 22%** |
| 40 generations | $0.134 | **$5.36** | **≈ 77%** |

If a template returns 2–4 variations per tap, multiply the cost accordingly.

**Implications:**
- **Route default templates to Flash-class models** ($0.03–$0.05).
- **Charge credits for Pro, 4K or video.**
- **Cap annual plans with a monthly credit allowance.**
- **Cache previews**, and **run classic edits on-device** (enhance, retouch, background) so they cost nothing per use.
- This is why the category converged on subscription plus credits.

### 6.6 Recommended pricing architecture

All price points below are recommendations, anchored to RevenueCat's North American medians.

| Tier | What's included | Price |
|---|---|---|
| **Free** | 3 trend generations a day as watermarked or low-resolution previews; unlimited on-device basic edits | Free |
| **Annual** (default) | 7-day trial; credit allowance of about 150–300 credits a month; credits roll over one month; HD export | $39.99–$49.99 |
| **Monthly** | No trial | $9.99 |
| **"Just this pack"** | One-off purchase with no subscription, for example "Headshot pack (20 photos)", "Trend pack" or "Restore 10 photos" | $2.99–$9.99 |
| **Credit top-ups** | Extra credits | Small packs |

**Trust features to build in:**
- Remind users 24 hours before a trial converts.
- Refund credits automatically when a generation fails.
- Never retire "lifetime" or "unlimited" retroactively.

**Weekly plans:**
- Avoid them, or offer only a **non-renewing 1-week pass**, as Lensa's $2.99 one-week pass does.
- This gives up some install-to-trial conversion (Adapty: weekly 9.8% vs annual 1.8%).
- In return it avoids the #1 complaint and earns about 5x more revenue per install on annual plans (RevenueCat).

---

## 7. App Store optimization (ASO)

### 7.1 Title patterns observed in the leading apps

| Pattern | Examples (indexed US titles) |
|---|---|
| Brand + **"AI Photo Editor"** | Photoroom: AI Photo Editor · Lensa AI: Photo Editor · YouCam Perfect: AI Photo Editor · Picsart AI Photo Editor, Video · Meitu AI Photo & Video Editor · EPIK - AI Photo & Video Editor · Remini - AI Photo Editor (Canada) |
| Brand + **"Enhancer"** | Remini - AI Photo Enhancer (US) |
| Brand + **"AI Art" / "Generator"** | Hypic - Photo Editor & AI Art · Wonder - AI Art Generator · Dawn AI - Avatar generator |
| Brand + **"Face" / "Selfie"** | FaceApp: Perfect Face Editor · Retake AI Face & Selfie Editor · Facetune: Photo & Video Editor |
| **"& Video"** suffix (rising) | Picsart, Meitu, EPIK, Facetune, Glam AI: Video & Photo Editor |
| **Localized titles** | "Facetune: KI Foto Video Editor" (Germany), "Picsart AI: Editor de Fotos IA" and "Photoroom - Editor de Fotos IA" (Spain) |

Subtitles are **unknown**; they were not retrievable (§9).

### 7.2 Keyword data

- **"ai photo editor"** (US, measured 2026-10-06): popularity **70**, difficulty **80** ("Very Hard"). **7 of the top 10** apps already have the phrase in their name ([RespectASO](https://respectaso.com/aso/category/ai-apps/)).
- **"ai photo enhancer free"**: popularity **38**, difficulty **46** ("Moderate"). **None** of the top 10 have it in their name (same source).
- **Head terms vs long-tail:** long-tail phrases have a median difficulty of **46**, head terms **67** (same source).
- **"AI" is the #1 metadata keyword in Photo & Video**, and "AI" phrases carry lower volume than their non-AI equivalents at similar difficulty ([NeoAds / MobileAction 2026](https://neoads.substack.com/p/ai-is-the-most-used-keyword-in-6)). Pair "AI" with a specific job, for example "AI headshot" or "restore old photos".
- **Indexed fields:** title, subtitle and the keyword field. 2026 guides add screenshot captions and Custom Product Page keywords. Apple introduced **AI-generated App Store Tags** at WWDC 2025 ([ASOMobile](https://asomobile.net/en/blog/aso-in-2026-the-complete-guide-to-app-optimization/); [Phiture](https://phiture.com/asostack/aso-trends-in-2026/)).
- **Localization:** about **92%** of top apps localize subtitles and descriptions ([AppTweak 2026](https://www.apptweak.com/en/aso-blog/aso-app-store-trends-benchmarks-report)).
- Avoid reusing the same high-value keyword in both title and subtitle, and across your own apps ([MobileAction](https://www.mobileaction.co/blog/aso-keyword-cannibalization/)).

### 7.3 Screenshot conventions

**From the guides:**
- **Before and after is the native pattern for photo apps**: "Photo editing apps love this pattern because the transformation is immediately visible" ([AppScreenMagic](https://appscreenmagic.com/guides/how-to-create-app-store-screenshots)).
- **Show the output first**, then the creation flow, then templates, effects and sharing ([ScreenshotBro](https://screenshotbro.app/blog/app-store-screenshot-order)).
- **The first three screenshots do most of the work**; users rarely scroll past them ([AppTweak](https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots); [Adapty](https://adapty.io/blog/app-store-screenshots-optimization/)).
- **A/B test the first screenshot and its caption** before anything else ([AppTweak](https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots)).

**Recommended set:**
1. A hero before-and-after of a face with the caption "Still looks like you"; this addresses identity fidelity, the #4 complaint.
2. A collage of trending templates labelled "Trending this week".
3. Headshot pack results.
4. Old-photo restoration.
5. One tap → result in seconds.
6. A privacy and pricing promise ("Face data deleted after processing · No surprise weekly charges").

**Custom Product Pages:** use one per trend and per job (headshots, restoration), tied to Apple Ads keywords.

### 7.4 Timing of the ratings prompt

**Apple's rules:**
- The system shows the review prompt at most **3 times per app in a 365-day window**.
- Apple leaves the timing to the app.
- Apple advises **against calling `requestReview` from a button tap**, because the prompt may not appear ([Apple developer docs](https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requestreview(in:).md)).

**Best practice from the guides:**
- Prompt only **after a moment of success, once the user is clearly engaged**. Never right after install ([Donny Wals](https://www.donnywals.com/optimizing-your-applications-reviews/); [Sonar](https://trysonar.app/blog/how-to-get-app-reviews)).
- Third-party summaries warn that **custom prompts or satisfaction gates** ("Do you like the app?" before the prompt) risk rejection ([vp0](https://vp0.com/blogs/apple-in-app-store-review-prompt-safely)).

**Recommended triggers:**
- After the user **saves or shares** a result they kept, on their **2nd or 3rd successful session**.
- Never after a failed generation, a paywall dismissal or a refund.
- At most once per app version.

### 7.5 Draft metadata (illustrative; validate with a keyword tool)

**Title:** `<Brand>: AI Photo Editor`. This is the strongest head term but very hard (difficulty 80), so pair it with a niche in the subtitle.

**Subtitle options:**
- `Trend Photos, Headshots & Fixes`
- `AI Headshots & Viral Photo Trends`

**Keyword field ideas:** enhancer, restore, old photo, unblur, headshot, linkedin, dating, figurine, polaroid, caricature, yearbook, retouch, selfie, avatar.

Do not include third-party trademarks or artist names.

---

## 8. Positioning gaps and recommendation

### 8.1 Where the incumbents are weak in late 2026

| Gap | Evidence | Opportunity |
|---|---|---|
| **Trust in billing** | The #1 pain point (§3). Weekly plans churn badly (1–2% retained after a year). Annual plans earn about 5x more per install (RevenueCat) | A **fair-pricing promise**: annual and monthly plans plus one-off packs, a trial reminder, and no weekly auto-renew |
| **Likeness and identity fidelity** | The #4 pain point. Headshot vendors call "doesn't look like me" the most common complaint (vendor claim, [HeadshotsByAI](https://headshotsbyai.com/blog/ai-headshots-2026-professional-results)). OpenAI now markets likeness preservation | **Likeness Lock**: build an identity profile from 3–5 selfies, check similarity, and offer free re-rolls |
| **Credits that feel like a trap** | Picsart, Wonder and Glam AI complaints | Credits that are transparent and roll over, with automatic refunds when a generation fails |
| **Privacy and consent** | Fonehouse study; FaceApp's "Warning" rating; Grok scandal; Indian warnings about Nano Banana | **Private by default:** delete face data after processing, never train on user photos, and allow realistic edits only on the user's own face. Age-gate realistic face edits |
| **Inclusive quality** | Lensa skin whitening; Glam AI "anglicized" features | Fidelity QA across skin tones and hair textures; diverse casting in template previews |
| **Occasional users overpaying** | RevenueCat says Photo & Video apps are "one-off project apps" with 23% annual renewal. A Remini reviewer called $10+ a week too much for occasional use (paraphrase) | **Outcome packs** with no subscription (headshots, restoration, World Cup or holiday packs) |
| **Generic output from the platforms** | ChatGPT and Gemini are free and add presets. a16z: "the bar for standalone image products rose sharply" | Win on **speed to trend** (24–48 hours), **finished formats** (correct aspect ratios, motion loops, consistent sets of 6–20 images) and **curation** rather than the underlying model |

### 8.2 Recommended positioning statement (one sentence)

> **For people who want to join every photo trend and look their best without looking fake, [Brand] is the AI photo studio that turns a few selfies into trend-ready, true-to-you photos in seconds, with honest pricing and face data that's private by default.**

### 8.3 Three differentiators

1. **Likeness Lock.**
   - Generation that preserves the user's identity, using a 3–5 selfie profile.
   - A visible "looks like you" check before results appear.
   - A promise: **"Doesn't look like you? Re-roll free."**
   - Credits are refunded automatically when a generation fails.
   - This targets the most emotionally charged quality complaint and the main gap headshot tools leave.
2. **Fair-Price Promise.**
   - No surprise weekly renewals.
   - Annual (default) or monthly plans, **plus "just this pack" one-time purchases**.
   - Credits roll over, a reminder goes out 24 hours before a trial ends, and the cancel path takes one tap.
   - This turns the category's top complaint into the brand promise. It also suits the economics: annual plans earn about 5x more per install than weekly plans, and packs fit Photo & Video's project-like usage.
3. **48-hour Trend Engine, private by default.**
   - New viral templates within 24–48 hours of a trend breaking.
   - Social-ready output: stills, short motion versions and the right aspect ratios.
   - Face data is deleted after processing and never used for training.
   - This matches the 2025–26 reality that model launches and trends drive installs, while competing on trust as regulators tighten.

### 8.4 Risks to plan for

- **The platforms keep improving.** ChatGPT and Gemini add presets, and Gemini restricts editing to users 18 and over.
- **Model deprecations and price swings.** gpt-image-1.5 is deprecated and Gemini 2.5 Flash Image is reportedly retiring on 2026-10-02. Keep a **multi-model router**.
- **Spikes fade.** Remini fell back to its "usual download rate of 8 – 12 million" after its spike (period not stated), and its 2025 downloads were down 24.5%. Retention must come from recurring "me" jobs (seasonal packs, headshots refreshed every few months), not from trends alone.
- **Safety and regulation** for edits of real people and for minors (Grok, January 2026).

---

## 9. Limitations and open questions

- **WebFetch failed** with DNS errors for a16z, Sensor Tower, RevenueCat and others. All figures come from search-result summaries of those pages, so verify the key numbers against the primary pages before quoting them externally.
- **Reddit could not be reached** with the search tool. The love and hate synthesis uses App Store reviews, Trustpilot, Sikayetvar, Apple Community, G2 and press instead.
- **App Store pages could not be fetched directly.**
  - Ratings and prices are search-index snapshots with unknown dates, and some are clearly years old.
  - **Subtitles were not retrievable.**
  - Hypic's revenue conflicts more than 10x between AppMagic and Appfigures.
  - ScreensDesign's revenue estimates are internally inconsistent; use them only to compare paywall patterns.
- **The web-search quota ran out.** The following were **not verified or remain unknown**:
  - App Store subtitles for all 15 apps.
  - Revenue for photoai.com, Glam AI, Retake, Wonder and Perfect Corp's AI apps.
  - A breakdown of AI photo app users by gender and age (only proxies were found).
  - The UK, Canada and Australia share of category revenue.
  - Category-specific RevenueCat price medians for Photo & Video.
  - The exact App Review guideline wording on review prompts and subscription disclosures.
- **Suggested next steps:**
  - Pull live metadata and keyword volumes with AppTweak, Appfigures or Sensor Tower.
  - Scrape the most recent 1,000 US reviews for the top 6 competitors and code the themes.
  - Check current in-app prices on a US device.
  - Run a willingness-to-pay test on packs vs annual plans.

---

## 10. Source index (main sources, by section)

**Market and platforms:**
- [Sensor Tower: State of Mobile 2026](https://sensortower.com/blog/state-of-mobile-2026)
- [Sensor Tower: State of AI 2026 press release](https://sensortower.com/press/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year)
- [Sensor Tower: State of AI Apps 2025](https://sensortower.com/blog/state-of-ai-apps-report-2025)
- [Sensor Tower: AI photo and video apps (2024)](https://sensortower.com/blog/rapid-growth-and-competitive-dynamics-the-state-of-ai-photo-and-video-apps)
- [TechCrunch: GenAI apps in H1 2025](https://techcrunch.com/2025/07/30/gen-ai-apps-doubled-their-revenue-grew-to-1-7b-downloads-in-first-half-of-2025/)
- [Business of Apps: Top Grossing Apps](https://www.businessofapps.com/data/top-grossing-apps/)
- [Business of Apps: FaceApp statistics](https://www.businessofapps.com/data/faceapp-statistics/)
- [AppTweak: most downloaded photo and video apps](https://www.apptweak.com/en/reports/most-downloaded-photo-video-apps)
- [a16z: Top 100, 6th edition](https://a16z.com/100-gen-ai-apps-6/)
- [a16z: Top 100, 7th edition](https://a16z.com/100-gen-ai-apps-7/)
- [The Neuron: a16z list breakdown](https://www.theneuron.ai/explainer-articles/a16z-just-ranked-the-100-most-popular-ai-apps-heres-the-full-list-and-what-it-tells-us-/)
- [Appfigures: image model updates](https://appfigures.com/resources/insights/image-model-updates-drive-more-ai-app-downloads)
- [Appfigures: This Week in Apps, 2025-12-19](https://appfigures.com/resources/this-week-in-apps/20251219)
- [Appfigures: This Week in Apps, 2025-04-04](https://appfigures.com/resources/this-week-in-apps/20250404)
- [TechCrunch: Gemini tops the App Store](https://techcrunch.com/2025/09/16/gemini-tops-the-app-store-thanks-to-new-ai-image-model-nano-banana/)
- [9to5Google: 1B Nano Banana Pro images](https://9to5google.com/2026/01/12/gemini-nano-banana-pro-milestone/)
- [The Decoder: 700M images in week 1](https://the-decoder.com/chatgpts-image-generation-explodes-with-700m-creations-in-first-week/)
- [TechRadar: GPT Image 1.5](https://www.techradar.com/ai-platforms-assistants/chatgpt/chatgpt-images-just-got-a-major-upgrade-and-it-could-change-how-we-all-create)

**Companies:**
- [Bending Spoons F-1](https://www.sec.gov/Archives/edgar/data/0002004711/000110465926071170/tm2613674-7_f1.htm)
- [Remini and Nano Banana press release](https://www.prnewswire.com/news-releases/bending-spoons-remini-app-hits-1-16-million-weekly-installs-following-integration-of-googles-nano-banana-ai-model-302615284.html)
- [Meitu 2025 annual results](https://finance.yahoo.com/sectors/technology/articles/meitu-2025-annual-results-adjusted-132500863.html)
- [Higgsfield: $1B run rate](https://higgsfield.ai/blog/higgsfield-1b-annualized-revenue-run-rate)
- [Facetune pricing](https://www.facetuneapp.com/pricing)
- [Photoroom pricing (eesel)](https://www.eesel.ai/blog/photoroom-pricing)
- App Store listings, linked in §2.

**Users:**
- [Remini on Trustpilot](https://www.trustpilot.com/review/remini.me)
- [Remini on Sikayetvar](https://www.sikayetvar.com/en/remini-us)
- [CheckThat: Remini reviews](https://checkthat.ai/brands/remini-ai/reviews)
- [CheckThat: Picsart reviews](https://checkthat.ai/brands/picsart/reviews)
- [IT Brief: Fonehouse privacy study](https://itbrief.com.au/story/privacy-concerns-rise-over-popular-ai-photo-apps-study)
- [Common Sense: FaceApp privacy rating](https://privacy.commonsense.org/privacy-report/FaceApp-AI-Face-Editor)
- [Business Insider NL: Lensa backlash](https://www.businessinsider.nl/sex-art-theft-and-privacy-lensa-exploded-overnight-and-now-the-avatar-app-is-dealing-with-public-backlash-heres-what-you-should-know/)
- [AP via WTVM: Grok restrictions](https://www.wtvm.com/2026/01/15/grok-blocked-undressing-images-places-where-its-illegal-x-says/)

**Monetization:**
- [RevenueCat: State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps)
- [RevenueCat: 2026 trends and benchmarks](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026)
- [RevenueCat: renewal rates by category](https://www.revenuecat.com/blog/growth/average-subscription-renewal-rates-by-app-category)
- [TechCrunch: AI app retention](https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows)
- [Adapty: In-App Subscription Benchmarks 2026](https://adapty.io/state-of-in-app-subscriptions-report/)
- [Adapty: 2025 report in 10 minutes](https://adapty.io/blog/state-of-in-app-subscriptions-2025-in-10-minutes/)
- [RocketShip HQ: RevenueCat 2025 summary](https://www.rocketshiphq.com/revenuecat-state-of-subscription-apps-2025-summary/)
- [PricePush: RevenueCat 2026 notes](https://newsletter.pricepush.app/p/i-read-all-336-pages-of-revenuecats)
- API pricing: [BenchLM](https://benchlm.ai/media-pricing/nano-banana), [OpenAI](https://developers.openai.com/api/docs/models/gpt-image-1.5), [AIFreeAPI](https://www.aifreeapi.com/en/posts/openai-image-generation-api-pricing), [PricePerToken](https://pricepertoken.com/fal-ai-pricing)

**ASO:**
- [RespectASO](https://respectaso.com/aso/category/ai-apps/)
- [NeoAds / MobileAction](https://neoads.substack.com/p/ai-is-the-most-used-keyword-in-6)
- [AppTweak: 2026 benchmarks report](https://www.apptweak.com/en/aso-blog/aso-app-store-trends-benchmarks-report)
- [AppTweak: screenshots](https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots)
- [ScreenshotBro: screenshot order](https://screenshotbro.app/blog/app-store-screenshot-order)
- [Apple: requestReview](https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requestreview(in:).md)
