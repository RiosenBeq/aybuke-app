# 02 · Brand identity — Glowlit

![Glowlit brand board](assets/brand/brand-board.png)

| | |
|---|---|
| **Name** | **Glowlit** |
| **Tagline** | *Make it glow.* |
| **App Store title** | `Glowlit: AI Photo Editor` (24/30 characters) |
| **Subtitle (draft)** | `AI Headshots & Photo Trends` (27/30) |
| **Positioning** | The AI photo studio for trend-ready, true-to-you photos — with honest pricing and private-by-default face data. |
| **Primary hue** | Golden Hour amber `#FF9A3D` (gradient `#FFC25C → #FF7A3D`) on near-black `#0C0C0E` |
| **Display type** | Bricolage Grotesque (SIL OFL 1.1) + SF Pro |
| **Icon** | "Sunrise Split" — a half-dark/half-light disc divided by a compare handle, on an amber tile |

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
| **Glowlit** | **free** | **free** | `.com` taken (as is every pronounceable `.com`) | ✅ **chosen** |
| Goldlit | free | free | — | Runner-up; "gold" reads as money |
| Sunlume | free | free | — | Spelling ambiguity (sun-loom?) |
| Sunrae | free | free | — | Spelling ambiguity (sunray?) |

### Why Glowlit

- **Glow** is the category's most emotional outcome word: "glow-up", glowing skin, golden-hour glow. **Lit** means lit by light, and in Gen-Z slang "lit" means great.
- It is a 7-letter, 2-syllable compound (GLOW-lit) that people spell exactly as they hear it.
- It is **coined**, which makes for a stronger trademark than a dictionary word.
- It fits the palette ("Golden Hour") and the icon (light on dark).
- It has no meaning or negative association in Spanish, Portuguese, French, German or Turkish (French *lit* = bed, which is harmless).

### Before launch (not yet done)

The name has **not** been cleared legally. Before spending on marketing:

1. Search the App Store and Google Play for "Glowlit".
2. Check USPTO and EUIPO trademarks in Nice classes **9** and **42**.
3. Check social handles: @glowlit, @glowlitapp.
4. Register `glowlit.app`, the domain the app's privacy, terms and support URLs already point to.

---

## 2. Color — "Golden Hour"

**Why amber?**
- Of 34 AI image/video brands whose official logo colours were checked, **none leads with orange or amber**. Violet ("AI purple"), blue, magenta and black are saturated ([research §1.4](research/brand-and-design.md#14-tally-saturated-hues-vs-whitespace)).
- Amber also *means* something here: golden-hour light is the light that flatters skin.
- It matches 2026–27 trend signals: WGSN's *Energy Orange*, warm neutrals and Pantone's *Cloud Dancer* whites.

**Why dark-first?**
- Apple's HIG explicitly allows a permanently dark appearance for immersive-media apps.
- About 79% of Photo & Video paywalls are dark.
- Near-neutral graphite chrome keeps photos true-to-colour.

| Token | Hex | Use | Contrast |
|---|---|---|---|
| `background` | `#0C0C0E` | App background | — |
| `surface` | `#17171B` | Cards, sheets | — |
| `surfaceRaised` | `#222228` | Controls, chips | — |
| `primary` | `#FF9A3D` | **The one primary action per screen**, tints | 9.25:1 as text on background |
| `gradientStart → gradientEnd` | `#FFC25C → #FF7A3D` | CTA fills, badges, hero card | — |
| `onPrimary` (ink) | `#1A1206` | Labels on amber | 7.15–11.58:1 (AAA) |
| `secondary` | `#5B8CFF` | "Blue hour": selection, info | 6.18:1 |
| `textPrimary` | `#F5F3EE` | Body text | 17.62:1 |
| `textSecondary` | `#A9A7A2` | Secondary text | 8.13:1 |
| `textTertiary` | `#8E8C87` | Captions | 4.71:1 on surface 2 |
| `success` / `warning` / `danger` | `#34D399` / `#FFD43B` / `#FF5C5C` | Feedback, always paired with an icon | ≥ 5:1 |

**Rules**
- **Never put white text on amber.** It measures 2.1:1; always use ink `#1A1206`.
- Use only one amber element per screen. Toolbars over photos stay monochrome (HIG: content-rich apps should prefer monochrome bars).
- Generation moments read as **warm light**: a golden glow sweep, not a purple nebula.
- Light-mode and increased-contrast variants are defined in the [research](research/brand-and-design.md#a-golden-hour-recommended). Liquid Glass adaptivity needs them even for a dark-only app.

Implemented in [`ios/App/DesignSystem/Palette.swift`](../ios/App/DesignSystem/Palette.swift).

---

## 3. Typography

| Role | Font | Notes |
|---|---|---|
| Wordmark, hero and screen titles | **Bricolage Grotesque Display** (opsz 96) ExtraBold / Bold | Characterful "collage" grotesque; ink traps at display sizes |
| Card titles, buttons | **Bricolage Grotesque Text** (opsz 24) SemiBold | Calmer forms at small sizes |
| Everything else (body, prices, legal) | **SF Pro** | Dynamic Type, Bold Text, Apple legibility tuning |

- **Licence:** SIL Open Font License 1.1, with no Reserved Font Name. The licence ships in the app (Settings → Acknowledgements).
- **Implementation:** the variable font (`opsz 12–96, wdth 75–100, wght 200–800`) was cut into three static TTFs (~90 KB each) with `fontTools.varLib.instancer` so iOS can address each weight by PostScript name. Fonts are registered at launch and scale with Dynamic Type (`Font.custom(_:size:relativeTo:)`), falling back to SF Pro Rounded if missing.
  - Fonts: [`ios/App/Resources/Fonts/`](../ios/App/Resources/Fonts/)
  - Code: [`Typography.swift`](../ios/App/DesignSystem/Typography.swift)
- **Rejected:**
  - Space Grotesk and Sora: the generic "AI/web3" look, and Sora collides with OpenAI Sora.
  - Unbounded: crypto association.
  - Inter and Geist: too close to SF Pro to add brand value.
  - Clash Display and Satoshi: not OFL.

---

## 4. App icon — "Sunrise Split"

![App icon](assets/brand/app-icon-1024.png)

**The idea:** the left half of a disc is graphite (*before*), the right half is warm light (*after*), and the app's signature **compare-slider handle** divides them.
- It reads as a sunrise or eclipse (light), as before → after (enhance), and as the app's core interaction.
- The amber tile stands out on a Home Screen full of black and purple AI icons.
- It stays legible at 29 px.
- It follows Apple's icon guidance: a minimal number of shapes, a solid gradient background, no text and no photo.

**Files**
- Source: [`assets/brand/app-icon.svg`](assets/brand/app-icon.svg)
- 1024 px PNG (no alpha): in `Assets.xcassets/AppIcon.appiconset`

**To do**
- Build an **Icon Composer** `.icon` with Default / Dark / Clear / Tinted appearances. iOS 26+ renders Liquid Glass icons, and the iOS 27 SDK is required from April 2027.
- A/B test it against concept C ("Light Monogram") with Product Page Optimization.

Concepts considered: [`assets/research/icon_concepts.png`](assets/research/icon_concepts.png).

---

## 5. Voice & tone

**Warm, direct, honest.** We talk like a friend who is good with a camera, not like a tech company.

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

## 6. App Store presence (draft)

- **Title:** `Glowlit: AI Photo Editor`
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
