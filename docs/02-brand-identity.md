# 02 · Brand identity — Aybuke

![Aybuke brand board](assets/brand/brand-board.png)

| | |
|---|---|
| **Name** | **Aybuke** |
| **Tagline** | *Make it glow* |
| **App Store title** | `Aybuke: AI Photo Editor` (24/30 characters) |
| **Subtitle (draft)** | `AI Headshots & Photo Trends` (27/30) |
| **Positioning** | The AI photo studio made for girls who glow: trend-ready, true-to-you photos, with honest pricing and private-by-default face data. |
| **Palette** | "Blush": blush pink `#F7C1D9` and petal `#F8E0EA` with ink `#121212`, charcoal `#24272A`, paper `#F8F8F6` and white; light-first. Decorative "Aura" accents (pink `#FF5CA1`, lilac `#A78BFA`, peach `#FFAA78`, butter `#FFDE6E`, mint `#78E1CD`) for the icon, share cards and template art only |
| **Display type** | Poppins (SIL OFL 1.1) + New York Italic accents + SF Pro |
| **Icon** | "Aura Lens" — a liquid-glass lens glowing white-hot through blush to magenta in a thin iridescent ring, with a sparkle on its rim, on a deep plum-to-peach Aura tile |

Full evidence: [research/brand-and-design.md](research/brand-and-design.md).

---

## 1. Name

### Brief

Research on the 21 leading apps ([research §4.1](research/brand-and-design.md#41-patterns-in-the-category)):
- The median brand token is 6 letters and 2 syllables.
- Winners are coined or real-word tokens, followed by a keyword title ("Brand: AI Photo Editor").

We wanted a name that:
- evokes **light** (photography's native metaphor) and the user outcome (a "glow-up");
- is spelled exactly as heard;
- is ownable;
- has no negative meaning in EN/ES/PT/FR/DE/TR.

### Screening

The research shortlist was Sunlit, Brilla, Lumora, Liora, Daylit, Aglow, Pixora and Glimmer. Web screening was impossible (search quota exhausted), so we screened by **domain availability**: a free `.app` **and** `.ai` is a strong signal that no tech product is actively using the name. We checked 69 domains on 2026-10-11 (read-only registry lookup).

| Candidate | `.app` | `.ai` | Other | Verdict |
|---|---|---|---|---|
| Sunlit | taken | taken | `sunlitapp.com` taken, `sunlit.co` taken | Crowded dictionary word |
| Brilla | taken | taken | `brillaapp.com` free | `.app`/`.ai` in use |
| Lumora | taken | taken | `lumoraapp.com` and `.photo` taken | Actively used; also "Lum-" cluster (Luma AI, Luminar, Lumo) |
| Daylit | taken | taken | `daylitapp.com` free | `.app`/`.ai` in use |
| Aglow | taken | taken | `aglowapp.com` taken | Actively used |
| Pixora | taken | taken | `pixoraapp.com` taken | Actively used |
| Glimmer | taken | taken | — | Common word |
| **Aybuke** | **free** | **free** | `.com` taken (as is every pronounceable `.com`) | ✅ **chosen** |
| Goldlit | free | free | — | Runner-up; "gold" reads as money |
| Sunlume | free | free | — | Spelling ambiguity (sun-loom?) |
| Sunrae | free | free | — | Spelling ambiguity (sunray?) |

### Why Aybuke

- **Glow** is the category's most emotional outcome word: "glow-up", glowing skin, golden-hour glow. **Lit** means lit by light, and in Gen-Z slang "lit" means great.
- It is a 7-letter, 2-syllable compound (GLOW-lit) that people spell exactly as they hear it.
- It is **coined**, which makes for a stronger trademark than a dictionary word.
- It fits the palette (soft pink light) and the icon (light over ink).
- It has no meaning or negative association in Spanish, Portuguese, French, German or Turkish (French *lit* = bed, which is harmless).

### Before launch (not yet done)

The name has **not** been cleared legally. Before spending on marketing:

1. Search the App Store and Google Play for "Aybuke".
2. Check USPTO and EUIPO trademarks in Nice classes **9** and **42**.
3. Check social handles: @glowlit, @glowlitapp.
4. Register `glowlit.app`, the domain the app's privacy, terms and support URLs already point to.

---

## 2. Color — "Blush"

In October 2026 the owner retargeted Aybuke at **girls and young women** and asked for a fully pink, light look built on six exact swatches. The original "Golden Hour" amber direction (below, for the record) was retired.

| Token | Light (default) | Dark | Use | Contrast |
|---|---|---|---|---|
| `background` | `#F8E0EA` petal | `#121212` ink | App canvas | — |
| `surface` | `#FFFFFF` | `#24272A` charcoal | Cards, sheets | — |
| `surfaceRaised` | `#F8F8F6` paper | `#303337` | Controls, chips | — |
| `primary` | `#F7C1D9` blush | same | Selection, highlights, hero fills, glows | — |
| `onPrimary` | `#121212` | same | Labels on blush | 12.1:1 |
| `accent` / `onAccent` | `#121212` / `#F7C1D9` | `#F7C1D9` / `#121212` | **The one primary action per screen** (ink button with a blush label), links, tints | 12.1:1 |
| `textPrimary` | `#121212` | `#F8F8F6` | Body text | 15.0:1 on petal |
| `textSecondary` | `#5C5457` | `#AAAAA8` | Secondary text | 5.9:1 on petal |
| `textTertiary` | `#645A5E` | `#90908F` | Captions (not over blush or the aurora: 4.3:1 there, so fine print uses `textSecondary`) | 5.3:1 on petal |
| `success` / `warning` / `danger` | `#0B7A54` / `#8A6100` / `#B42318` | `#34D399` / `#FFD43B` / `#FF6B6B` | Feedback, always with an icon | ≥ 4.2:1 |

**Rules**
- **Never put white text on blush** (1.6:1). Labels on blush are ink.
- The primary action is an **ink button with a blush label** in light mode (blush button with an ink label in dark mode). Everything else stays white, petal or blush.
- Artwork without a photo (template cards, style tiles) uses flat `PaletteTone` pairings — blush, ink, white, charcoal — in a steady rhythm.
- Generation and success moments read as **soft pink light**: a rotating blush glow, then a burst of hearts and sparkles.
- Photos keep their own colors: no tinted overlays on images.

Implemented in [`ios/App/DesignSystem/Palette.swift`](../ios/App/DesignSystem/Palette.swift). Settings › Appearance offers Light (default), Dark and Automatic.

<details>
<summary>Retired: "Golden Hour" (dark-first amber, original research)</summary>

The first brand used Golden Hour amber `#FF9A3D` (gradient `#FFC25C → #FF7A3D`) on near-black `#0C0C0E`. Amber was chosen because none of 34 AI image/video brands led with it, and because about 79% of Photo & Video paywalls are dark. The full analysis is in [research/brand-and-design.md](research/brand-and-design.md).

</details>

---

## 3. Typography

| Role | Font | Notes |
|---|---|---|
| Wordmark, hero and screen titles | **Poppins** ExtraBold / Bold | Round, friendly geometric sans; reads well in all 12 app languages that use Latin or Cyrillic script |
| Card titles, buttons | **Poppins** SemiBold / Medium | Calm, even forms at small sizes |
| Everything else (body, prices, legal) | **SF Pro** | Dynamic Type, Bold Text, Apple legibility tuning |
| Editorial accent (one word per headline: "watch it *glow*") | **New York Italic** (Apple system serif) | `Text(styled:size:)` sets `*words*` in the accent; scales with Dynamic Type |

- **Licence:** SIL Open Font License 1.1, with no Reserved Font Name. The licence ships in the app (Settings → Acknowledgements).
- **Implementation:** four static Poppins cuts (Medium, SemiBold, Bold, ExtraBold) ship in the app. Fonts are registered at launch and scale with Dynamic Type (`Font.custom(_:size:relativeTo:)`). Japanese, Korean and Chinese text falls back to the system fonts automatically. Poppins replaced Bricolage Grotesque in October 2026.
  - Fonts: [`ios/App/Resources/Fonts/`](../ios/App/Resources/Fonts/)
  - Code: [`Typography.swift`](../ios/App/DesignSystem/Typography.swift)
- **Rejected:**
  - Space Grotesk and Sora: the generic "AI/web3" look, and Sora collides with OpenAI Sora.
  - Unbounded: crypto association.
  - Inter and Geist: too close to SF Pro to add brand value.
  - Clash Display and Satoshi: not OFL.
- **Sizes:** headlines are set a step below iOS's large title, so Poppins' wide forms don't shout: 30 pt for onboarding and paywall titles, 25–28 pt for screen titles, 23 pt for card headlines, 26 pt for the Home wordmark, 16 pt for buttons and card titles. At accessibility text sizes, layouts stack (the Home header puts its buttons above the name) instead of breaking words.

### Shape

Crisp corners, not bubbles (October 2026): one radius scale in [`Metrics.swift`](../ios/App/DesignSystem/Metrics.swift), with matching shapes (`.card`, `.button`, `.control`, `.chip`, `.tag`) so no view hard-codes a corner.

| Shape | Radius | Used for |
|---|---|---|
| `card` | 14 pt | Cards, panels, sheets' inner cards, the tour card |
| `button` | 12 pt | Primary and secondary buttons (52 pt tall), the editor's tool bar items |
| `control` | 10 pt | Photos on a canvas, fields, tiles, icon squares |
| `chip` | 8 pt | Chips, pills (credits, ideas, idea buttons), toasts |
| `tag` | 5 pt | PRO/NEW badges, Before/After tags, small labels |
| print | 0 | Template cards and collection pages: looks are prints |

Round shapes stay round where roundness is the meaning: icon buttons, the shutter, toggles, page dots and progress bars. Corners inside exported pictures (share cards, captions, stickers, collage captions) belong to the artwork, not to this scale.

---

## 4. App icon — "Aura Lens"

![App icon](assets/brand/app-icon-1024.png)

**The idea:** a liquid-glass lens whose core glows white-hot through blush to magenta, set in a thin iridescent ring (pink, lilac, soft aqua, peach), with a white sparkle glinting on its rim and two small ones beside it. The tile is a deep Aura gradient, plum at the top left through berry and rose to warm peach at the bottom right, with a few out-of-focus lights. The lens is the camera and the photo (Retro Cam, Photo Booth, every edit); the glow is "Make it glow"; the sparkle is the app's AI glyph and success moment. It replaced "Glow Gem" (a faceted pink heart) on 15 October 2026, when the owner asked for something new and more aesthetic, "with effects". Before that it was "Glow Print" and, first, "Sunrise Split".
- **Glass and light:** a specular crescent at the top left, a small bright reflection and faint rim light at the bottom right, an inner shadow where the ring meets the glass, and a soft pink bloom and halo around the lens. The effects are layered over exact paths, so every edge stays crisp.
- **Reads small:** a bright core in a ring with a sparkle, at 29 pt, at 16 px on the Mac and as a favicon; the deep glass around the core keeps the contrast.
- **Not Instagram:** a filled, glowing lens rather than an outline camera, no dot in the upper right, and a peach corner rather than orange and yellow.
- **Variants:** dark (the lens glowing on ink with lilac and pink light) and tinted (a white-hot core and a bright ring on black, so the tint reads strongly) for iOS 18+ Home Screens, and every Mac size on Apple's macOS grid.
- It follows Apple's icon guidance: one centred shape, a gradient background, no text and no photo, and nothing important within 6% of the edges.

**Concepts** — all five, also at 60 and 29 px and with their dark and tinted versions, are in [`brand/icon-concepts/`](brand/icon-concepts/concepts.png):

![Icon concepts](brand/icon-concepts/concepts.png)

- **A, "Spark Cam":** a white digicam whose lens glows pink around a sparkle. Clear, but literal: it reads as a camera app, and camera glyphs are everywhere.
- **B, "Heart Print":** a sharp-cornered white print whose photo is a heart glowing pink on plum. Meaningful, but close to the retired Glow Print.
- **C, "Glow Gem":** the icon from 14 to 15 October 2026. Appealing, with a strong silhouette, but a flat jewel on a pastel tile; the owner wanted more effects.
- **D, "Aura Lens":** chosen. New, says camera and glow at once, and keeps the strongest contrast at small sizes.
- **E, "Holo Heart":** the same glass and glow as a puffy heart with an iridescent rim. The cutest and instantly a heart, but close to the hearts the icon has had; the alternative if the owner would rather keep a heart.

**Files**
- Everything is drawn by [`scripts/render-brand-assets.py`](../scripts/render-brand-assets.py) with Pillow alone (no image generator): exact paths at 4x, with glows, soft light and conic (iridescent) gradients layered over them. It writes `AppIcon.appiconset` (iOS default, dark and tinted at 1024 px; Mac 16–1024 px), `BrandIcon` (invite card), `web/assets/icon.png` (favicon), [`assets/brand/app-icon-1024.png`](assets/brand/app-icon-1024.png), the brand board and a vector copy, [`assets/brand/app-icon.svg`](assets/brand/app-icon.svg) (the ring's sweep as thin wedges, since SVG has no conic gradient).
- `--concept a` … `--concept e` switches every output to another concept; `--concept-sheets` redraws the concept images.
- The link preview `web/assets/og-image.png` shows the icon too; `scripts/marketing-images.py` takes it from `app-icon-1024.png`.

**To do**
- Build an **Icon Composer** `.icon` with Default / Dark / Clear / Tinted appearances (layers: tile, bloom, ring, glass, highlights and sparkles; the SVG is a start). iOS 26+ renders Liquid Glass icons, and the iOS 27 SDK is required from April 2027.
- A/B test it against concept E with Product Page Optimization (the alternate icon has to ship in the app).

Early research concepts (amber era): [`assets/research/icon_concepts.png`](assets/research/icon_concepts.png).

---

## 5. Voice & tone

**Warm, playful, confident, honest.** We talk like a best friend who is good with a camera, not like a tech company. Since the girls-first redesign: celebrate creativity and vibes ("watch it *glow*", "What are we glowing up today?"), never comment on bodies or faces, and never promise "flawless" or "slimmer".

Headlines, titles and taglines never end with a decorative full stop, in any language ("Make it glow", not "Make it glow."). A two-part headline takes a comma ("Say the change, watch it *glow*"); body sentences keep their periods.

| Do | Don't |
|---|---|
| "Describe any change. Watch it happen." | "Leverage our cutting-edge generative AI pipeline" |
| "Failed edits are always refunded." | Hide limits in fine print |
| "You'll be charged $59.99 on Oct 18 unless you cancel." | Fake countdown timers, "only 2 spots left" |
| "Doesn't look like you? Retry free." | Blame the user for bad results |
| Specific progress: "Restoring details…" | "Processing…" |

**Copy rules**
- Sentence case.
- Use ✦ sparingly as the AI glyph.
- Never use third-party brands or artists in template names: "Anime Film", not "Ghibli"; "3D Cartoon", not "Pixar".

---

## 6. App Store presence

The current, character-counted copy for en-US and tr-TR is in [marketing/app-store-listing.md](marketing/app-store-listing.md) (title `Aybuke: AI Photo Editor`, subtitle `AI Glow-Ups, Trends & Edits`). The original research notes follow.

- **Title:** `Aybuke: AI Photo Editor`
  - "ai photo editor" has popularity 70 and difficulty 80; 7 of the top 10 apps use it.
- **Subtitle:** `AI Headshots & Photo Trends`
  - Put the niche terms in the subtitle and don't repeat title words.
- **Keyword field (≤ 100 characters):** `enhancer,restore,old photo,unblur,headshot,retouch,selfie,figurine,polaroid,anime,avatar,background`
- **Screenshot order:**
  1. Before/after of a face — "Still looks like you".
  2. Trending templates — "Trending this week".
  3. Pro headshots.
  4. Old-photo restore.
  5. "Describe any edit" (Magic Edit).
  6. Privacy and pricing promise — "No surprise weekly charges".
- **Custom Product Pages:** one per trend and per job (headshots, restore), tied to Apple Ads keywords.

Sources: [research/market-research.md §7](research/market-research.md#7-app-store-optimization-aso).
