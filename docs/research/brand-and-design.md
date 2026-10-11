# Brand & Design Research: AI Photo Editor + AI Image Generator (iOS, English)

Prepared 2026-10-11 (AI-assisted desk research). The final brand decisions are in [../02-brand-identity.md](../02-brand-identity.md).

**Legend.** Each claim carries a tag:
- **[V]**: verified during this research against a first-party or primary source, or computed locally.
- **[S]**: taken from web-search results (secondary or vendor sources; figures are as those sources report them).
- **[P]**: prior knowledge that was **not** re-verified during this research. Check it before relying on it.

**Companion files** (images in [`docs/assets/research/`](../assets/research/); contrast tables in [brand-contrast-tables.md](brand-contrast-tables.md)):

| File | What it is |
|---|---|
| `palettes.png` | The 3 palette directions mocked on dark UI (headline, compare card, gradient CTA, outline button, swatches) |
| `contrast_tables.md` | Full WCAG 2.x contrast tables for every token pair |
| `specimen.png` | Real-font specimens: Bricolage Grotesque, Funnel Display, Instrument Serif, Unbounded, Space Grotesk, Syne. Includes Turkish glyphs (Ğğ Şş İı) |
| `icon_concepts.png` | Rough sketches of icon concepts A, B and C at 1024/120/60/29 px, plus a mono preview |
| `icon_concept_A_variants.png` | Three tile treatments of concept A, shown on a light backdrop |

---

## 0. Executive summary

1. **Hue map.** The crowded territories are violet ("AI purple"), blue/cyan, magenta-pink and monochrome black.
   - Of 34 AI image/video brands whose official logo colour assets were inspected, 11 are monochrome, 7 contain or lead with violet, 5 are blue/cyan, 5 are multicolour, 5 are yellow/lime and 1 is red. **None leads with orange or amber.**
   - Verified consumer-competitor datapoints follow the same pattern: Picsart magenta, Photoroom navy, Meitu red, FaceApp violet-led multicolour, Captions/Mirage blue→peach.
   - **Whitespace: warm amber/apricot as the primary brand hue.**
   - *Caveat:* icons of 15 of the 21 named competitors could not be verified during this research. Run the 15-minute audit in §1.5 before locking the brand.
2. **Recommended palette: "Golden Hour".**
   - UI chrome is neutral near-black: `#0C0C0E` (background), `#17171B` (surface), `#222228` (surface 2).
   - Amber CTA `#FF9A3D`, gradient `#FFC25C → #FF7A3D`, dark label `#1A1206`. Label contrast is 7.15–11.58:1.
   - Secondary "blue hour" accent `#5B8CFF`; warm off-white text `#F5F3EE` (17.62:1 on the background).
   - Every text token passes AA (≥4.5:1) on every surface. **Never put white text on amber** (2.11:1).
3. **Dark UI first.**
   - Apple explicitly allows a permanently dark appearance for immersive-media apps [V].
   - About 79% of Photo & Video paywalls use dark backgrounds [S, Lazyweb, n=67].
   - Still ship light colour variants: Apple says they are needed for Liquid Glass adaptivity [V].
4. **Liquid Glass in 2026.**
   - iOS 27 is shipping and adds a system-wide glass transparency slider [S].
   - Building with the iOS 27 SDK ignores the `UIDesignRequiresCompatibility` opt-out [S/Apple forums]. Uploads must use the iOS 27 SDK from April 2027 [V].
   - **iPhone Duo** (Apple's foldable) ships on Oct 23, 2026. Layouts must resize, and from April 2027 Duo screenshots are required [V].
   - Use system bars and controls, and tint only the primary CTA [V].
   - Over photos, use clear glass plus a dimming layer. Apple's 35% is a starting point. Small white text over a pure-white photo needs about 54% dimming to reach 4.5:1 [V computed].
5. **Display font: Bricolage Grotesque.**
   - SIL OFL, in google/fonts. Variable, with opsz 12–96, wdth 75–100 and wght 200–800.
   - Default PostScript name: `BricolageGrotesque-96ptExtraBold` [V].
   - Pair it with SF Pro for body text and Dynamic Type.
   - Alternates: Funnel Display, and Instrument Serif (editorial accent).
6. **Names.** The shortlist is ranked but **not web-screened**, because the web-search quota ran out (§4.4 lists the exact queries to run).
   - Ranked shortlist: **Sunlit, Brilla, Lumora, Liora, Daylit, Aglow, Pixora, Glimmer**.
   - Use the store title format `Name: AI Photo Editor`. The App Store limit is 30 characters [V]; these titles are 21–24.
7. **Paywall.**
   - Weekly plan with a 3-day trial is the top configuration for Photo & Video [S, Adapty 2026].
   - Hard paywalls reach about 5× freemium download-to-paid by day 35 (10.7% vs 2.1%) [S, RevenueCat 2026].
   - Free-trial **toggles have been rejected since January 2026** [S].
   - The billed amount must be the most prominent price element [V, Apple].
   - Only about 3% of paywalls show a "how your trial works" timeline [S, Lazyweb]. That makes it a cheap differentiator: Blinkist reported +23% trial sign-ups from this pattern [S].
8. **Icon.** Concept A, "Sunrise Split", works best: a disc that is half graphite and half light, with a compare-slider handle, on an amber tile. It reads at 29 px and in mono. Test it against B and C with Product Page Optimization [V: PPO supports icon tests].

### 0.1 Method and limitations

- **Web search.** The web-search quota for this research ran out after about 50 queries. Three things were affected:
  - per-app icon colours for 15 of the 21 competitors;
  - the per-name web screen in §4 (30 names × 2 queries);
  - identification of the fonts competitors use.
- **Web fetching.** WebFetch could not resolve most hosts in this sandbox. `curl` worked for three:
  - `developer.apple.com`: HIG JSON, App Review Guidelines, the developer news RSS, product-page/PPO/asset pages, iPhone Duo pages, and the transcript of the WWDC26 Icon Composer lab;
  - `raw.githubusercontent.com`: google/fonts files;
  - `registry.npmjs.org`: Simple Icons 16.34.0 and LobeHub icons 1.95.1, as brand-colour datasets.
- **Contrast** uses WCAG 2.x relative luminance (sRGB threshold 0.03928), computed in python3.
- **Fonts and sketches.** Specimens and icon sketches were rendered with Pillow from the actual OFL TTF files.

---

## 1. Competitor visual identity map

### 1.1 The 21 named competitors

| # | App (developer) | Brand / icon colour evidence found | UI theme evidence | Status |
|---|---|---|---|---|
| 1 | Remini (Bending Spoons [S]) | No official palette found. Web hits for "Remini icon" were fan-made Pinterest variants, which are unusable. In-app, a **red** check-mark control triggers colorize [S: Shotkit] | Not verified. Its paywall is heavily tested: Lazyweb logged 13 experiments, all on the paywall [S] | ❓ audit |
| 2 | Lensa (Prisma Labs [S]) | Nothing found | Not verified | ❓ audit |
| 3 | Picsart | Brand hex **`#C209C1`** (magenta) [V: Simple Icons 16.34.0, whose source field is picsart.com]. App icon described as a gradient pink-purple → pink → teal [S: whatthelogo]. A third-party wordmark page lists `#0086FF/#00C9FF`, which conflicts [S] | Not verified | Partial |
| 4 | Photoroom | Official media page: main logo is the white symbol and wordmark **on navy**; watermarks only in white or black [S: photoroom.com/media] | Not verified | Partial |
| 5 | Facetune (Lightricks) | The Lightricks corporate mark is monochrome (no colour variant in the LobeHub set) [V-data]. App icon not verified | Not verified | ❓ audit |
| 6 | FaceApp | Third-party "FaceApp icon" palette: `#724BCC` violet, `#56C2E6` sky, `#F3246C` pink-red, `#FEDF12` yellow [S: BrandPalettes] | Not verified | Partial |
| 7 | Hypic (Bytedance Pte. Ltd. [S]) | ByteDance corporate blue `#3C8CFF` [V: Simple Icons]. App icon not verified | Not verified | ❓ audit |
| 8 | Meitu | Official 2025 VI guideline: the logo uses "**Meitu Red**" on black or white, and is reversed to white only when red isn't feasible [S: Meitu VI PDF] | Not verified | Partial |
| 9 | Dawn AI | Nothing found; App Store listing exists [S] | Not verified | ❓ audit |
| 10 | Wonder | Nothing found | Not verified | ❓ audit |
| 11 | WOMBO Dream | Nothing found | Not verified | ❓ audit |
| 12 | Imagine (Vyro) | Nothing found | Not verified | ❓ audit |
| 13 | Photoleap (Lightricks) | Nothing found | Not verified | ❓ audit |
| 14 | YouCam Perfect (Perfect Corp [S]) | Nothing found | Not verified | ❓ audit |
| 15 | EPIK (SNOW Corp [S]) | Nothing found | Not verified | ❓ audit |
| 16 | Glam AI (Glam Labs [S]) | Nothing found | Not verified | ❓ audit |
| 17 | PhotoAI | Nothing found | Not verified | ❓ audit |
| 18 | Pixelcut | Nothing found | Not verified | ❓ audit |
| 19 | Fotor | Nothing found | Not verified | ❓ audit |
| 20 | Prisma (Prisma Labs) | Nothing found | Not verified | ❓ audit |
| 21 | Captions (company renamed **Mirage**, Sept 2025; the app keeps the Captions name [S]) | Mirage logo is white on a bright blue → peach gradient [S] | Not verified | Partial |

**Category-level UI-theme evidence [S, Lazyweb Research, July 2026].**
- Photo & Video paywalls: about **79% dark**. Of 67 classified, only 8 are light; the authors call this directional.
- All categories: about **71% dark** (785 dark, 211 light, 111 other).
- Graphics & Design is the exception and does not default to dark (21 dark vs 15 light, n=47).

### 1.2 Adjacent AI image/video model brands: official logo colour assets [V-data]

Source: `@lobehub/icons-static-svg@1.95.1` from npm. Colours were extracted from each brand's `-color.svg`. A brand with no `-color` variant uses a monochrome logo.

| Hue family | Brands (dominant hexes) | Count |
|---|---|---|
| **Monochrome black/white** | Midjourney, OpenAI, Runway, Pika, Krea, Ideogram, Recraft, Flux/BFL, Grok, Hedra, Lightricks | **11** |
| **Violet-led or violet-containing** | Meta AI (`#CA3EFF`…`#AB5CFF`), Bria (`#8900FF`, `#5300C9`), Luma (`#A78DFF` + blues), PixVerse (`#442FBA` + peach/pink), Stability (`#9D39FF` + red), Doubao (`#1E37FC` + `#A569FF`), Hailuo (orange → pink → `#D584EF`) | **7** |
| **Blue / cyan** | Meta (`#0082FB`), Sora (`#6BB6FE`, `#0968DA`), Vidu (`#40EDD8` → `#047FFE`), Hunyuan (`#0055E9`), Civitai (`#1281F4`/`#0821C6`) | **5** |
| **Multicolour** | Gemini (Google 4-colour), DALL·E (5 blocks), Jimeng/Dreamina (orange + cyan/blue), Kling (yellow → green → cyan → blue), CogView (orange/red/blue) | **5** |
| **Yellow / lime** | Nano Banana (`#F9C23C`, `#FCD53F`), Tripo (`#F6D85A`), Kolors (`#CBFF00`), ComfyUI (`#F0FF41`), Meshy (`#C5F955` + pink) | **5** |
| **Red** | Adobe Firefly (`#EB1000`) | **1** |
| **Orange / amber as the lead hue** | — | **0** |

### 1.3 Adjacent photo and social brands [V-data: Simple Icons 16.34.0]

| Brand | Hex | Family |
|---|---|---|
| Instagram | `#FF0069` | Magenta-pink |
| Picsart | `#C209C1` | Magenta |
| Meta AI | `#9844FF` | Violet |
| Google Gemini | `#8E75B2` | Violet |
| ByteDance | `#3C8CFF` | Blue |
| Facebook | `#0866FF` | Blue |
| Pixlr | `#3EBBDF` | Cyan |
| VSCO | `#000000` | Black |
| TikTok | `#000000` | Black |
| Snapchat | `#FFFC00` | Yellow (owned) |
| remove.bg | `#54616C` | Slate |

### 1.4 Tally: saturated hues vs. whitespace

| Territory | Evidence of saturation | Verdict for a newcomer |
|---|---|---|
| Violet / purple / indigo ("AI purple") | 7/34 AI brands; Meta AI, Gemini, FaceApp, Photoroom navy. Design press calls purple gradients plus sparkles the generic "AI look" [S: IndieHackers, uxdesign.cc, Fountain Institute] | **Avoid as the primary hue.** It reads as generic AI and as an "AI-generated UI tell" |
| Blue / cyan | 5/34 AI brands plus Meta, Facebook, ByteDance, Pixlr, Mirage. WGSN names Luminous Blue its 2027 colour, so more will arrive [S] | Crowded; fine as a **secondary** |
| Magenta / pink / red | Picsart, Instagram, Meitu Red; pink ends of Hailuo and Meta AI gradients | Crowded in beauty and photo apps |
| Monochrome black | 11/34 AI brands; VSCO, TikTok; most paywalls are dark | Crowded, and invisible among dark icons |
| Yellow / lime | Nano Banana, Kolors, ComfyUI, Meshy, Tripo; Snapchat owns `#FFFC00` | Emerging in AI developer tools; yellow is Snapchat-adjacent |
| Teal | Only inside multicolour gradients (Kling, Vidu) | Open, but sits next to crowded blue |
| **Warm amber / apricot / orange** | 0/34 AI brands lead with it; none of the verified consumer datapoints use it. WGSN lists **Energy Orange** among its S/S 27 key colours [S] | **Best whitespace.** It owns "light/golden hour", the native metaphor of photography |

**Risk.** Unverified competitors such as Dawn AI or Remini could be warm-coloured. Run §1.5 before finalising.

### 1.5 Fifteen-minute audit to close the gaps (manual; App Store pages were blocked here)

1. On an iPhone, open each of the 21 product pages.
2. Screenshot the icon at 1024 px (use the share sheet or the website artwork) and the first two screenshots.
3. Note three things: the icon's dominant hue (eyedropper), the glyph type (letter, face, abstract or object), and the UI theme from the screenshots (dark or light).
4. Long-press the Home Screen, choose Customize, and check each competitor icon's dark and tinted appearance.
5. Paste the results into the §1.1 table. Re-tally §1.4. If amber appears in two or more of the top 10 grossing apps, consider palette C.

---

## 2. Colour

### 2.1 CTA colour, contrast and conversion: what the evidence actually says

- **There is no "best" CTA hue; contrast with the surroundings wins.**
  - The canonical HubSpot/Performable test (Aug 2011): a red button beat green by 21% [S].
  - Several analyses attribute the win to isolation and contrast: green was already the page's dominant colour, so red was "one of the only red objects on the page" [S: Review42, WordStream, CreativeMarket, Poper].
  - Rule: **reserve one accent hue for the primary action only.** A paywall teardown makes the same recommendation (accent on the primary button; neutral price highlights) [S: BetterLaunch].
- **Apple's Liquid Glass colour rules.**
  - The system applies the app accent colour to the background of prominent buttons [V: HIG Color].
  - Apply colour to the background rather than to symbols or text, and "refrain from adding color to the background of multiple controls" [V].
- **Paywall price hierarchy is regulated.**
  - "The amount that will be billed must be the most prominent pricing element." Per-week or savings breakdowns must be "subordinate in position and size" [V: Apple, Auto-renewable Subscriptions].
  - For trials: "clearly indicate how long the free trial lasts and the price billed once the free trial is over" [V].
- **Contrast thresholds.**
  - Apple: "no lower than 4.5:1… strive for a contrast ratio of 7:1, especially in small text" [V: HIG Dark Mode].
  - WCAG 2.x: 4.5:1 for normal text; 3:1 for large text and UI components [P: standard].
  - Our CTA labels are designed for **≥7:1**.

### 2.2 Why dark UIs suit photo editors

- **Apple's position.** "It can make sense for an app that supports immersive media viewing to use a permanently dark appearance that lets the UI recede and helps people focus on the media" [V: HIG Dark Mode].
- **Market practice.** About 79% of Photo & Video paywalls are dark [S].
- **Perception.** Through simultaneous contrast, a saturated or bright surround biases colour and brightness judgments of the photo. Pro editors use neutral dark-grey chrome for this reason [P: colour-science principle]. **Recommendation:** keep the chrome chroma near 0 (our `#0C0C0E`/`#17171B` have about 8% saturation at 5–10% lightness) and confine colour to controls.
- **Platform details [V: HIG Color / Dark Mode].**
  - "Soften the color of white backgrounds" in images shown in Dark Mode.
  - Photo apps can set a white-point adaptivity style to modulate True Tone (`UIWhitePointAdaptivityStyle`).
  - Use base vs elevated backgrounds for depth.
- **Over photos.** Use **clear** Liquid Glass for controls floating above media. When the content is bright, Apple suggests "a dark dimming layer of 35% opacity" [V: HIG Materials].
  - Our WCAG maths for worst-case white text over a **pure white** photo [V computed]:

    | Dimming | Contrast | Meets |
    |---|---|---|
    | 35% | 2.43:1 | Fails |
    | 42% | 3.03:1 | Icons and large text |
    | 50% | 3.95:1 | Icons and large text |
    | 54% | 4.61:1 | AA small text |
    | 60% | 5.74:1 | AA small text |

  - Use about 40% behind icon-only controls and about 55% behind small text labels, or use the regular glass variant.

### 2.3 Colour associations with "AI magic"

- The convention is starbursts, glow and purple gradients. A UX Collective essay cites Adobe Acrobat's AI button, Microsoft Copilot and Google Gemini [S: uxdesign.cc]. Google uses gradients on Gemini-powered services as an "AI inside" cue [S: Pixso]. ✨ is "synonymous with AI" [S: zeli.app].
- **Downside.** The look is so default that "overly perfect gradients… often purple over a dark background" are listed as a tell of AI-generated UIs [S: Fountain Institute]. One writer predicts the purple gradients will soon look dated [S: uxdesign.cc]. "The AI purple problem: why every AI brand looks the same" [S: IndieHackers].
- **Recommendation.** Keep the meaning, drop the cliché.
  - Use SF Symbols `sparkles` as a small semantic glyph on AI actions, such as "AI Enhance ✦".
  - Render generation moments as **warm light**: a golden glow sweep or a sunrise-gradient progress shimmer, not a purple nebula.

### 2.4 Trends for Gen Z and Millennials, 2025–2027

| Signal | Value | Tag |
|---|---|---|
| Pantone Colour of the Year 2025 | **Mocha Mousse**, PANTONE 17-1230, a warm brown evoking cacao and coffee; announced Dec 2024 | [S] |
| Pantone Colour of the Year 2026 | **Cloud Dancer**, PANTONE 11-4201, a "lofty white neutral… whisper of calm"; announced Thu Dec 4, 2025 | [S] |
| WGSN × Coloro Colour of the Year 2026 | Transformative Teal | [P], not re-verified |
| WGSN × Coloro Colour of the Year 2027 | **Luminous Blue** (Coloro 125-28-38), announced Apr 29, 2025 | [S] |
| WGSN S/S 27 key colours | Luminous Blue, **Energy Orange**, Pop Pink, Meadowland Green, Clay | [S] |

**Reading.** Calm warm neutrals and soft whites as the base, with energetic orange and luminous blue as accents. The Golden Hour palette maps onto this, **in spirit, not as official colour values**:
- Energy-Orange-adjacent amber for action;
- Luminous-Blue-adjacent `#5B8CFF` as secondary;
- Cloud-Dancer-like off-white `#F5F3EE` for text;
- Mocha/Clay-like warm greys for light-mode surfaces.

### 2.5 Liquid Glass (iOS 26 → iOS 27) and new platform realities

Facts:

- **Introduction.** Liquid Glass arrived with iOS 26. The HIG Materials page says to use it for the **controls and navigation layer only**: "Don't use Liquid Glass in the content layer"; "Use Liquid Glass effects sparingly." It comes in regular and clear variants, and clear is for components over photos and video [V].
- **Light and dark variants are mandatory in practice.** "Even if your app ships in a single appearance mode, provide both light and dark colors to support Liquid Glass adaptivity" [V: HIG Color, updated Dec 16, 2025].
- **iOS 27 changes.**
  - A user-facing **Liquid Glass transparency/opacity slider** [S: MacRumors Jun 10, 2026; BGR].
  - Refined rendering, with sharper specular highlights on icons and less translucency in Apple's own icons [V: WWDC26 Icon Composer lab].
  - Clear-mode **icon** glass is pinned and does **not** follow the slider [V: same lab].
- **No more opting out.** `UIDesignRequiresCompatibility` (the Liquid Glass opt-out) is ignored when an app is built with the iOS 27 SDK [S: Apple Developer Forums thread 832543, dev.classmethod]. **New apps should design for glass from day one.**
- **SDK floor.** From April 2027, App Store uploads must be built with the iOS 27 SDK [V: Apple news, Sep 9, 2026].
- **iPhone Duo (foldable)** ships Oct 23, 2026 on iOS 27.1 [V].
  - Apps built with the iOS 27.1 SDK fill the inner display, and **toolbars and tab bars become vertical**.
  - From April 2027, submissions need **iPhone Duo screenshots** [V: Apple news; iPhone Duo "Prepare" page].
- **New App Store creative assets** (iOS 27+): **product page header** and **search-results** image and video assets, plus an Asset Library and a preview tool with Dark Mode [V].

Implications for this brand:

1. **Use system components** (tab bar, toolbars, sheets, prominent button style). Let the system supply glass and its accessibility adaptations, including the transparency slider, Reduce Transparency and Increase Contrast.
2. **Use the amber accent as the tint of the single prominent CTA per screen.** Keep editor toolbars monochrome, because "if your app features colorful backgrounds or visually rich content, prefer a monochromatic appearance for toolbars and tab bars" [V: HIG Color].
3. **Over photos**, use clear glass plus a dimming layer (§2.2). Test both ends of the iOS 27 slider.
4. **Ship light and dark tokens and increased-contrast variants** (§2.6).
5. **Design the compare view and toolbars to reflow on iPhone Duo.** Vertical toolbars on the inner display mean the editor's bottom tool strip must also work as a side rail.
6. **Brand assets must work as wide hero art** (App Store header) as well as a 29 px icon.

### 2.6 Three palette directions (exact hex)

All three use a near-neutral dark base, one primary accent with a 2-stop gradient, and a complementary secondary. Accent fills always carry a **dark** label.

#### A. "Golden Hour" (RECOMMENDED)
Concept: photography is light. This is the warm, sunrise/golden-hour light that flatters skin and owns the empty warm-amber territory. The blue secondary adds a "blue hour" counterpoint.

| Token | Dark (primary) | Light companion | Increased contrast (dark / light) |
|---|---|---|---|
| App background | `#0C0C0E` | `#FAF9F7` | same |
| Elevated surface | `#17171B` | `#FFFFFF` | same |
| Elevated surface 2 / controls | `#222228` | `#F0EEEA` | same |
| Primary accent (CTA fill, tint) | `#FF9A3D` | `#FF9A3D` (fill only) | `#FFB46B` / — |
| Accent as text/link (light mode) | — | `#A64B08` | — / `#7F3905` |
| Gradient stops | `#FFC25C → #FF7A3D` | same | — |
| Label on accent | `#1A1206` | `#1A1206` | same |
| Secondary accent (selection, links, info) | `#5B8CFF` | `#2F5FE0` | `#86A8FF` / `#1F47B8` |
| Success | `#34D399` | `#0B7A54` | — / `#085E41` |
| Warning | `#FFD43B` (always with ⚠ glyph + text) | `#8A6100` | — |
| Error | `#FF5C5C` | `#C42727` | `#FF8080` / `#A01D1D` |
| Text primary | `#F5F3EE` | `#151412` | same |
| Text secondary | `#A9A7A2` | `#5C5A56` | `#C7C5C0` / `#45433F` |
| Text tertiary | `#8E8C87` | `#6E6C67` | `#AAA8A3` / `#55534F` |

Notes:
- In light mode, the amber fill is only 2.01:1 against the page. That is acceptable because the dark label (8.77:1) identifies the button, but add a 1 px `#C96A12` border (3.59:1) for affordance.
- The warning yellow sits 18° of hue away from amber, so always pair it with an icon (HIG: don't rely on colour alone).

#### B. "Acid Lime" (high-energy Gen Z)
Concept: maximum distinctiveness and creator energy. Lime sits at hue 78°, with hot pink as the secondary.

| Token | Hex |
|---|---|
| Background / surface / surface 2 | `#0A0B0A` / `#151715` / `#1F221F` |
| Primary accent | `#C6FF3D` |
| Gradient | `#E6FF5A → #6CF2A0` |
| Label on accent | `#0A0B0A` |
| Secondary | `#FF5CA8` |
| Success / warning / error | `#3DDC97` / `#FFB547` / `#FF5A5F` |
| Text primary / secondary / tertiary | `#F3F6F1` / `#A4AA9F` / `#878C82` |

Rationale: the highest contrast of the three (16.69:1 label on CTA) and very memorable.

Risks:
- Lime is spreading among AI developer tools (Kolors, ComfyUI, Meshy).
- The success colour collides with the accent.
- It reads "techy/neon" more than "beautiful photos", and it makes skin tones look sallow next to the UI.

#### C. "Aurora Teal" (calm-tech, trend-aligned)
Concept: aqua light shading to luminous blue, as in WGSN's teal (2026, [P]) and Luminous Blue (2027, [S]). Coral is the secondary.

| Token | Hex |
|---|---|
| Background / surface / surface 2 | `#0A0C10` / `#141922` / `#1D2430` |
| Primary accent | `#2EE6CF` |
| Gradient | `#46F0D6 → #4D86FF` |
| Label on accent | `#06121A` |
| Secondary | `#FF7A5C` |
| Success / warning / error | `#4ADE80` / `#FFC53D` / `#FF5470` |
| Text primary / secondary / tertiary | `#EEF2F7` / `#9CA6B4` / `#838C9A` |

Rationale: fresh and trustworthy, and it pairs naturally with iOS blue.

Risks:
- It is adjacent to the crowded blue territory.
- At the blue end of the gradient the dark label drops to 5.56:1 (AA, not AAA).

### 2.7 Contrast results (WCAG 2.x, computed with python3) [V]

Key pairs below; every pair is in [brand-contrast-tables.md](brand-contrast-tables.md).

| Palette | Text on background | Secondary text on background / surface 2 | Tertiary text on surface 2 | Label on CTA (accent / lightest stop / darkest stop) | White label on CTA | Accent as text on background |
|---|---|---|---|---|---|---|
| **A dark** | **17.62** | 8.13 / 6.58 | 4.71 | **8.77 / 11.58 / 7.15** | 2.11 ✗ | 9.25 |
| A light | 17.50 | 6.54 / 5.94 | 4.53 | 8.77 / 11.58 / 7.15 | 2.11 ✗ | 2.01 ✗; use `#A64B08` (5.50) |
| B dark | 18.09 | 8.29 / 6.76 | 4.67 | 16.69 / 17.67 / 13.94 | 1.18 ✗ | 16.69 |
| C dark | 17.41 | 7.95 / 6.33 | 4.59 | 12.02 / 13.25 / 5.56 | 1.57 ✗ (3.40 at the blue end) | 12.43 |

Semantic colours on the dark backgrounds:

| Palette | Secondary | Success | Warning | Error |
|---|---|---|---|---|
| A | 6.18 | 10.17 | 13.71 | 6.46 |
| B | 6.90 | 11.16 | 11.22 | 6.46 |
| C | 7.63 | 11.23 | 12.40 | 6.29 |

On surface 2, every semantic colour stays ≥5.0:1. Every text token in every palette passes ≥4.5:1 on all three surfaces.

### 2.8 Recommendation

**Choose A, "Golden Hour".**
- It is the only direction that is simultaneously ownable (no amber-led AI brands found), semantically right (photography = light), flattering to skin tones, and trend-aligned (Energy Orange, warm neutrals, Cloud-Dancer-like whites).
- It is also AAA on its CTA label.
- Keep palette C as the fallback if the audit in §1.5 finds amber in several top competitors.

---

## 3. Typography

### 3.1 Trends and what competitors use

- **Competitor fonts were not identified during this research.** The web-search quota was exhausted, and their sites, CSS and app bundles were unreachable. Treat any per-app font claims as open.
- **Observed direction in 2025–2026 consumer and creative apps [P].**
  - A neutral system or grotesque face for UI.
  - One expressive display face for headlines and marketing.
  - Variable fonts with optical sizes.
  - Editorial serif-italic accents for "human/premium" moments.
  - Space Grotesk and Sora read as 2020–2023 "tech/web3".
- **Apple's rules apply regardless [V: HIG Typography].**
  - Minimise the number of typefaces.
  - Custom fonts must support **Dynamic Type** and respond to **Bold Text**.
  - Default text size 17 pt; minimum 11 pt.
  - Avoid light weights at small sizes.
  - SF also comes in Condensed and Expanded widths and a Rounded variant. That is a zero-cost fallback for headlines, but not distinctive.

**Pairing strategy.**
- SF Pro handles all UI, body text, numerals in prices, legal text and anything Dynamic-Type critical.
- One OFL display face handles brand moments: onboarding headlines, paywall headline, template-gallery section titles, empty states, App Store screenshots and header art, and possibly the wordmark.

### 3.2 Top 3 candidates, verified in google/fonts [V]

All files were fetched with `curl` from `https://raw.githubusercontent.com/google/fonts/main/ofl/<family>/…`. Each returned HTTP 200 and was parsed with a custom `name`/`fvar`/`OS/2`/`cmap` reader. All three cover Latin-ext, including the Turkish, Spanish, Portuguese, French and German test glyphs Ğğ Şş İı Çç Öö Üü ñ ã õ ß œ €. **None declares a Reserved Font Name** in its OFL.txt copyright line.

| | **1. Bricolage Grotesque (recommended)** | 2. Funnel Display | 3. Instrument Serif |
|---|---|---|---|
| `METADATA.pb` | `ofl/bricolagegrotesque/METADATA.pb`: 200 | `ofl/funneldisplay/METADATA.pb`: 200 | `ofl/instrumentserif/METADATA.pb`: 200 |
| Exact TTF files in folder | `BricolageGrotesque[opsz,wdth,wght].ttf` (408,496 B) | `FunnelDisplay[wght].ttf` (53,436 B) | `InstrumentSerif-Regular.ttf` (70,012 B), `InstrumentSerif-Italic.ttf` (71,592 B) |
| Other files | `OFL.txt`, `DESCRIPTION.en_us.html` | `OFL.txt` (no `DESCRIPTION.en_us.html`) | `OFL.txt`, `DESCRIPTION.en_us.html` |
| `post_script_name` in METADATA.pb | `BricolageGrotesque-96ptExtraBold` | `FunnelDisplay-Light` | `InstrumentSerif-Regular`, `InstrumentSerif-Italic` |
| nameID 6 in TTF (what `UIFont(name:)` uses) | `BricolageGrotesque-96ptExtraBold`; variations PS prefix (nameID 25) `BricolageGrotesque` | `FunnelDisplay-Light`; nameID 25 `FunnelDisplay` | Same as METADATA |
| Axes | opsz 12–96 (default 96), wght 200–800 (default 800), wdth 75–100 (default 100) | wght 300–800 (default 300) | Static, 400 only |
| Named instances | ExtraLight…ExtraBold, **all at opsz 14** (text cut); no per-instance PS names in fvar | Light…ExtraBold | n/a |
| Metrics (UPM; x-height / cap-height) | 1000; 528/660 = 0.80 | 1200; 600/810 = 0.74 | 1000; 510/720 = 0.71 |
| Designer · added to Google Fonts | Mathieu Triay · 2023-06-15 | NORD ID, Kristian Möller · 2024-09-25 (sibling **Funnel Sans** exists) | Rodrigo Fuenzalida, Jordan Egstad · 2023-03-22 |
| Character | French/British grotesque "collage". Big optical sizes get "anxious and wonky" compressed forms with ink traps, while text sizes are neutral (designer's description). Warm, crafted, creator-ish | Clean, wide geometric with funnel-cut terminals. Friendly and modern, but closer to generic tech | Condensed old-style display serif "intended for use at large sizes". Editorial, premium, gorgeous italic |
| Fit with SF Pro | **High contrast of personality, same genre.** The wdth axis lets long headlines fit narrow and folded layouts | Medium: geometric vs neo-grotesque, close in feel | High: serif vs sans. Only one weight, so no bold headlines |
| Risk | 408 KB file; variable-axis setup in UIKit (see code) | Less distinctive | One weight; fashion/beauty connotation |

**Rejected [V for the facts quoted].**
- *Unbounded*: its own DESCRIPTION says it was funded via the Polkadot treasury and made with Parity Technologies and Web3 Foundation, so it carries a crypto association. It is also very wide.
- *Space Grotesk* and *Sora*: ubiquitous "AI/web3" look; "Sora" also collides in conversation with OpenAI Sora.
- *Syne*: quirky, and its ExtraBold is very wide.
- *Geist* and *Inter*: too close to SF Pro to add brand value.
- *Clash Display*, *Satoshi*, *General Sans*: **not in google/fonts** (`METADATA.pb` returned 404) and not OFL.

**Recommendation: Bricolage Grotesque** for display, at opsz 96, wght 700–800, wdth 100 (or 80–85 for long lines). Optionally use Instrument Serif Italic for one emphasised word in hero lines ("Make it *glow*"). Never use more than these two plus SF Pro.

**iOS implementation notes.**
- Register the font under `UIAppFonts` in Info.plist.
- Its named instances sit at opsz 14 (the text cut), so set axes explicitly for display use.
- Scale with `UIFontMetrics` so headlines respect Dynamic Type.
- Add about 100 wght when Bold Text is on.
- Bundle `OFL.txt` in Acknowledgements; the OFL requires the notice when redistributing.
- If you instance static cuts with `fontTools varLib.instancer` to save size, that is permitted, and no rename is required because no RFN is declared.

The following is an untested sketch:

```swift
import UIKit
import CoreText

enum BrandFont {
    static let bricolagePS = "BricolageGrotesque-96ptExtraBold"   // nameID 6 of the variable TTF
    // OpenType axis tags as integers: 'wght' 0x77676874, 'wdth' 0x77647468, 'opsz' 0x6F70737A
    static func display(_ size: CGFloat, weight: CGFloat = 760, width: CGFloat = 100,
                        opsz: CGFloat = 96, relativeTo style: UIFont.TextStyle = .largeTitle) -> UIFont {
        let w = min(800, weight + (UIAccessibility.isBoldTextEnabled ? 100 : 0))
        let axes: [Int: CGFloat] = [0x77676874: w, 0x77647468: width, 0x6F70737A: opsz]
        let desc = UIFontDescriptor(name: bricolagePS, size: size).addingAttributes(
            [UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: desc, size: size))
    }
}
// SwiftUI: Text("Make it glow.").font(Font(BrandFont.display(34)))
```

---

## 4. Naming

### 4.1 Patterns in the category

| Pattern | Data |
|---|---|
| Length of the 21 brand tokens (excluding the "AI" suffix) | Median **6 letters** (mean 6.2, range 4–9); 12/21 are ≤6 letters and 19/21 are ≤8 [V computed] |
| Syllables | Median **2** (13/21 have 2; 5 have 3; 2 have 1; 1 has 4) [V computed] |
| Name type | 8 descriptive compounds (Picsart, Photoroom, Facetune, FaceApp, Photoleap, YouCam, PhotoAI, Pixelcut); 7 coined (Remini, Lensa, Hypic, Meitu = 美图 "beautiful picture", WOMBO, Fotor, Epik); 6 real words (Dawn, Wonder, Imagine, Glam, Prisma, Captions) |
| Short real words need "AI" | Dawn **AI**, Glam **AI**, Lensa **AI** — the suffix both disambiguates and adds a keyword |

**Store title format.** The pattern is `Brand` + separator + keyword phrase:
- "Remini - AI Photo Enhancer"
- "Lensa AI: Photo Editor"
- "Hypic - Photo Editor & AI Art"
- "EPIK - AI Photo & Video Editor"
- "Glam AI: Video & Photo Editor"
- "Dawn AI - Avatar generator"
- "FaceApp: Perfect Face Editor"

[S: App Store/Play/listing titles seen in search results]

**Apple's rules [V].**
- Names: ≤30 characters.
- Don't pack trademarked terms or popular app names (2.3.7).
- Don't use another developer's brand in your name or icon (4.1(c)).
- Product-page guidance: "simple, memorable… easy to spell and hints at what your app does. Be distinctive. Avoid… generic terms or… too similar to existing app names."
- The 30-character subtitle carries the value proposition.

**Implication.** Pick a 4–7 letter, 2–3 syllable brandable token. Then use `Name: AI Photo Editor` (21–24 characters) as the title, and the subtitle for the generator angle, e.g. "Enhance, restyle & create".

### 4.2 Thirty candidates, with linguistic and conflict screen

- **Language screen:** EN, ES, PT, FR, DE and TR, from linguistic knowledge [P].
- **Conflicts:** prior knowledge only [P]. **No web screen was possible** (§0.1).

| # | Name | L/Syl | Type | Evokes | Language notes | Known conflicts [P] | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | **Sunlit** | 6/2 | Real word | Sunlight + Gen-Z "lit" | Clean in all 6 | None known; a dictionary word, so expect unrelated businesses | ✅ |
| 2 | **Daylit** | 6/2 | Rare real word | Daylight | Clean | None known | ✅ |
| 3 | **Aglow** | 5/2 | Real word | Glowing | Clean | "Aglow International" (faith organisation) | ✅ |
| 4 | **Brilla** | 6/2 | ES/IT word | "Shines" (ES/IT); FR *brille* = shines; PT *brilha* | DE *Brille* = eyeglasses (neutral, lens-adjacent) | None known | ✅ |
| 5 | **Liora** | 5/3 | Hebrew given name | "My light" | Clean | Personal name; possible jewellery or beauty brands | ✅ |
| 6 | **Lumora** | 6/3 | Coined | Lumen + aurora | Clean | "Lum-" space is crowded (Luma AI, Luminar, Lumo) | ✅ (confusability) |
| 7 | Rayo | 4/2 | ES word | Ray, lightning | ES *¡Rayos!* = mild "darn"; PT *raio* | Rayo Vallecano (football) | ⚠️ RYE-oh / RAY-oh split |
| 8 | Vela | 4/2 | ES/PT word | Candle, sail | Clean | Many "Vela" companies | ⚠️ crowded |
| 9 | Alba | 4/2 | ES/IT word | Dawn | Clean | Alba Botanica, Alba electronics; semantically overlaps **Dawn AI** | ⚠️ |
| 10 | Hikari | 6/3 | JA word | Light | Clean | Hikari (fish-food brand), Shinkansen service name | ⚠️ |
| 11 | **Glimmer** | 7/2 | Real word | Faint light, hope | DE *Glimmer* = mica (neutral) | Common word; Glimmer.js (Ember) | ✅ (weak trademark) |
| 12 | Presto | 6/2 | IT/EN | "Hey presto!" magic, speed | ES *presto* = "I lend"; PT = "I render" | Presto/Trino SQL engine; PRESTO card (Toronto transit) | ⚠️ |
| 13 | Wisp | 4/1 | Real word | Will-o'-the-wisp light | Clean | **Wisp** is a US sexual-health telehealth brand | ❌ association |
| 14 | Lucera | 6/3 | ES word | Skylight | Clean | Spelling ambiguity (Lusera/Lucerna) | ⚠️ |
| 15 | Lumino | 6/3 | Coined (IT word) | Little lamp | IT *lumino* also = votive/cemetery candle | Various | ⚠️ |
| 16 | Radia | 5/3 | ES word | Radiates | FR *radier* = to strike off (passé simple *radia*) | Unknown | ⚠️ |
| 17 | **Pixora** | 6/3 | Coined | Pix + aurora | Clean | Unknown; pix/pics spelling | ✅ |
| 18 | Halora | 6/3 | Coined | Halo + aura | Clean | Unknown | ✅ backup |
| 19 | Vivra | 5/2 | FR word | "Will live" | Clean | Unknown | ⚠️ weak light cue |
| 20 | Glimmo | 6/2 | Coined | Glimmer | Clean; sounds like "gimme" | Unknown | ⚠️ |
| 21 | Lumiva | 6/3 | Coined | Lumi + viva | Clean | "Lum-" crowding | ⚠️ |
| 22 | Glowly | 6/2 | Coined | Glow | Rhymes with "lowly/slowly" | Unknown | ⚠️ |
| 23 | Lumo | 4/2 | Esperanto "light" | Light | Clean | **Proton "Lumo" AI assistant** (2025) | ❌ |
| 24 | Luma | 4/2 | Coined | Light | Clean | **Luma AI** (generative video/image) | ❌ |
| 25 | Lumee | 5/2 | Coined | Light | Clean | **Lumee** light-up selfie phone cases | ❌ |
| 26 | Pixie | 5/2 | Real word | Fairy + pix | Clean | Many apps and devices | ❌ crowded |
| 27 | Flare | 5/1 | Real word | Flash of light | "Lens flare" = photo defect | Flare (crypto network) | ❌ |
| 28 | Glint | 5/1 | Real word | Sparkle | Clean | Glint (LinkedIn HR product) | ❌ |
| 29 | Kira | 4/2 | JA *kira(kira)* | Sparkle | **TR *kira* = rent**; Death Note antagonist alias | — | ❌ |
| 30 | Glaze | 5/1 | Real word | Gloss | Clean | **Glaze** (UChicago tool shielding artists from AI mimicry); reputational clash | ❌ |

Excluded during brainstorming for **near-certain** conflicts [P]:
- Lumix (Panasonic), Lumea and Lumify (Philips), Luminar (Skylum), Eos (Canon), Lumu (iPhone light meter);
- Kaleido (remove.bg maker), Pictory (AI video), Voila (Voila AI Artist), Opal (iOS screen-time app), Dazzle (Dazz Cam);
- Prism/Prisma (competitor), Lens-anything (Lensa), Elio (Pixar 2025);
- Pixa (pixa.com AI image tools [S]).

### 4.3 Ranked top 8 (pending web screen)

| Rank | Name | Store title (characters) | Why | Conflict notes / risks |
|---|---|---|---|---|
| 1 | **Sunlit** | Sunlit: AI Photo Editor (23) | Pure light metaphor, plus a Gen-Z double meaning ("lit"). Spelled exactly as heard, 2 syllables. Matches the Golden Hour palette and icon concept A | A dictionary word, so trademark strength is suggestive rather than fanciful. Expect "Sunlit" businesses in solar or wellness. Must clear app class 9/42 |
| 2 | **Brilla** | Brilla: AI Photo Editor (23) | "Shines" in ES and IT (FR *brille*, PT *brilha*). Positive in 4 of the 6 screened languages; ownable; energetic | Double-L spelling (some will write "Brila"). DE *Brille* = glasses (neutral or even apt) |
| 3 | **Lumora** | Lumora: AI Photo Editor (23) | Coined, so the most ownable. Reads light + aurora (magic) | Sits in the crowded "Lum-" cluster (Luma AI, Luminar, Lumo). Test for recall confusion |
| 4 | **Liora** | Liora: AI Photo Editor (22) | Means "my light"; soft and elegant; strong for the beauty and portrait segment | Also a personal name. Leora/Liora spelling. Slightly feminine-coded |
| 5 | **Daylit** | Daylit: AI Photo Editor (23) | Sibling of Sunlit, rarer and therefore more ownable | Less instantly familiar as a word |
| 6 | **Aglow** | Aglow: AI Photo Editor (22) | The real word for the "glow-up" outcome; 5 letters | "Aglow International" exists (not creative/AI). Some will hear "a glow" |
| 7 | **Pixora** | Pixora: AI Photo Editor (23) | "Pix" signals photo, which Apple says should "hint at what your app does"; "-ora" signals aura | Pix/Pics spelling ambiguity. The coined-name space may contain small apps |
| 8 | **Glimmer** | Glimmer: AI Photo Editor (24) | Magic plus light; a positive idiom ("glimmer of hope") | A common word, so weaker trademark; likely existing small apps |

Alternates: Halora, Hikari, Presto.

### 4.4 Screening still to run

For each top-8 name:
1. Search the web for `"<Name>" app`, `"<Name>" AI`, `"<Name>" photo` and `"<Name>" editor`.
2. Search the App Store and Google Play for the exact name.
3. Check USPTO and EUIPO trademarks in Nice classes **9** (downloadable software) and **42** (SaaS/AI), plus **41** if you plan creator communities [P: class mapping].
4. Check social handles (@name, @nameapp, @name.ai).
5. Run a 5-second "hear it, spell it" test with 10 people.
6. Get a quick native-speaker check in ES, PT, FR, DE and TR.

Domains are handled separately.

---

## 5. UX patterns users love in this category, with evidence

### 5.1 Onboarding

- **The first session is the money moment.** Per RevenueCat's 2025 data, as cited by Airbridge, 82% of trials start on Day 0 [S].
- **Where the paywall sits [S, Lazyweb].**
  - Remini's onboarding has 8 steps, with the first paywall on **step 8, the last one**.
  - 27.5% of tracked flows put the paywall on the final step.
  - Flows with a paywall are longer: 17.2 vs 12.4 steps on average.
  - Photo & Video apps paywall earlier than other verticals (relative position 0.67, n=12, directional).
- **Multi-page beats single-page [S, Superwall, May 2026].** Multi-page onboarding paywalls converted **12.41% vs 9.07%** (+37% relative), measured over 40M+ paywall opens between Feb and May 2026.
- **Apple's guidance [V: HIG Onboarding].**
  - Make onboarding "fast, fun, and optional".
  - "Teach through interactivity."
  - "Prefer letting people experience your app… before prompting them for… purchases."

**Recommended flow (8–10 screens):**
1. Splash.
2. Hero before/after, with an **interactive** compare slider on a sample photo.
3. Two or three personalisation questions. Example: "What do you want to do first?" with options Restore old photos / Glow-up selfies / Create AI art / Product shots. Use the answers to:
   - pre-select templates;
   - choose the paywall hero.

   Superwall argues tailored paywalls beat generic ones [S]. An often-quoted ~15% lift is unverified.
4. Permission plus AI-processing consent. Apple 5.1.2(i): "clearly disclose where personal data will be shared with third parties, **including with third-party AI**, and obtain explicit permission" [V]. Prefer `PHPicker`, which needs no full-library permission [P].
5. **"Try it on your photo"**: one free enhancement preview. This is the "aha" moment; Superwall advises triggering the paywall after it [S].
6. Multi-page paywall (§5.2).
7. Optional notification opt-in, framed as the trial reminder.

### 5.2 Paywall

**Market data**
- **Plan mix [S, Adapty 2026; 16k+ apps, $3B revenue].**
  - Weekly plans account for **55.5%** of app subscription revenue, up from 43.3% two years earlier.
  - In Photo & Video, the **top configuration is weekly + 3-day trial**.
  - Photo & Video install LTV is $0.82.
  - Trial adoption in the category fell from 70.7% to 62.3%, the steepest fall of any category.
  - Trial refund rate is the **highest of any category at 6.4%**, and 14.1% in APAC.
  - Weekly with trial overtakes annual by month 12 (about $46 vs $40) [S].
- **Hard vs freemium [S, RevenueCat 2026; 115k apps, $16B].**
  - Download-to-paid by day 35: 10.7% for hard paywalls vs 2.1% for freemium.
  - Revenue per install by day 60: $3.09 vs $0.38.
  - Annual-subscriber retention after one year is about equal (27% vs 28%).
  - Trials of ≤4 days are now 46.5% of all trials. Median trial conversion ranges from 25.5% (≤4 days) to 42.5% (17–32 days).
  - Photo & Video trial-to-paid is about 22.2%. That figure is secondary and unconfirmed against the PDF.
- **Paywall anatomy [S, Lazyweb, July 2026].**
  - Among paywalls that document a default, **annual** is the most common pre-selected plan (70 annual vs 57 monthly vs 17 weekly).
  - The most common primary CTA is **"Continue"** (350 of 1,886 labelled primary CTAs).
  - Only **~3.2%** of paywalls (39 of 1,204) show a trial-timeline UI, while 44.7% mention a trial.
- **Remini's tests [S, Lazyweb].** Remini moved from a Weekly/Yearly toggle to a single pre-selected Yearly plan with "Try For Free". It also tested putting the price on the CTA ("$5.99/week" instead of "Unlock All").

**Policy constraints**
- **Trial toggles.** Since mid-January 2026, Apple has been rejecting paywalls with a free-trial on/off toggle under 3.1.2, with no announcement [S: Adapty, RevenueCat, Superwall]. Alternatives:
  - an eligibility-based paywall (show the trial only to eligible users);
  - an exit offer;
  - a separate "plan with trial" option, as Flo did in April 2026 [S: RevenueCat].
- **Price prominence.** The billed amount must be the most prominent price element; weekly-equivalent and "save X%" figures go in subordinate size and position. Disclose trial length and the post-trial price [V].
- **Required on the sign-up screen** [V]: subscription name and duration, what's included, the full renewal price, restore/sign-in, and links to Terms and Privacy.
- **Over-emphasised trials.** Developers report 3.1.2(c) rejections when trial text out-shouts the price [S: Apple Developer Forums 841626].
- **New payment options [V].**
  - **Monthly with a 12-month commitment** has been available since iOS 26.5 everywhere **except the US and Singapore**. It is useful as a mid-price anchor outside the US.
  - iOS 27 adds **Bundles/Suites** and **multiseat** purchases.

**Recommended paywall layout (dark, Golden Hour)**
- Top: a personalised before/after (the user's own photo if they tried one) with a live slider.
- Headline in Bricolage Grotesque, e.g. "Your photos, in their best light".
- Three benefit rows with SF Symbols.
- **Plan cards:**
  - **Annual, pre-selected**: "$39.99/year" large; "≈ $0.77/week · Save 89%" small. Example numbers only.
  - **Weekly with a 3-day free trial**: "3 days free, then $6.99/week". This is a separate plan, not a toggle.
- **"How your free trial works" timeline:**
  - Today: full access.
  - Day 2: "We'll remind you".
  - Day 3: "You'll be charged $6.99 on Oct 14 unless you cancel".

  Blinkist's reminder promise: **+23% trial sign-ups** [S: UX Planet / Curtis Herbert]. A 55% drop in complaints is reported secondhand [S].
- **CTA:** amber gradient, dark label. Make it price-specific and plan-aware: "Start 3-day free trial" or "Continue — $39.99/year".
- Below the CTA: Restore · Terms · Privacy; a visible close control; and "Cancel anytime in Settings".
- **A/B priorities:**
  1. Weekly+trial vs annual-default.
  2. Timeline vs no timeline.
  3. Price on the CTA.
  4. Hero = user photo vs stock.
  5. Multi-page vs single page.

### 5.3 Before/after compare slider (signature interaction)

**Conventions** [S: component and vendor docs from Poper, Maglr, City of Calgary design system]:
- Pixel-aligned pairs.
- Explicit "Before"/"After" labels at least on first use.
- Horizontal reveal by default.
- A large, high-contrast handle.
- Fast-loading high-resolution images.

**Additions recommended for this app:**
- **Press-and-hold anywhere** shows the original. **Double-tap** toggles 0/100%. Drag the handle for the split.
- Haptics: `.selection` ticks while dragging at 0/50/100% detents, and a light `.impact` when snapping [V: HIG haptics semantics].
- On iPhone Duo's inner display, offer side-by-side mode. VoiceOver: an adjustable action ("Reveal 60%").
- Make the slider handle the **brand motif**, so it is consistent with icon concept A.

### 5.4 Template galleries

Apple's HIG on generative AI [V; updated Jun 8, 2026]:
- "Offer diverse, predefined example inputs that hint at what's possible."
- Offer **alternate versions** of results, as Image Playground does with multiple options.
- Keep "Edit, Undo, Retry, or Adjust" near generated content.
- Ask people for attributes rather than inferring them, to avoid stereotypes.
- Clearly identify where you use AI.

**Pattern:**
- A masonry grid of short before→after loops, muted and lightweight.
- Rows: "For you" (from onboarding answers), Trending, Restore, Portraits, Styles, Create.
- A "Use on my photo" CTA on every card.
- Pro templates badged with a small amber glyph, not a lock wall.
- The first 1–2 templates per category free, to drive the "aha".

### 5.5 Generation loading states

Apple guidance:
- [V: HIG Generative AI] "Factor processing time into your design… generate in the background while a person uses another part of the app."
- [V: HIG Generative AI] Give "specific, reassuring feedback… instead of 'Processing…', say what's happening."
- [V: HIG Loading] "Show something as soon as possible."
- [V: HIG Loading] Use a determinate indicator when you know the duration.

Practitioner guidance:
- Avoid fake-precise progress bars [S: Chameleon].
- Real waits of 8–15 seconds are common for AI image tools; animated progress shortens perceived wait [S: dev.to case].

**Pattern:**
1. Instantly show the user's photo, softly blurred, with a warm "light sweep" shimmer.
2. Use step labels: "Detecting faces → Restoring details → Upscaling 4× → Final touches".
3. Do a progressive reveal from blurred to sharp.
4. Show an honest ETA only for long jobs (avatar packs).
5. Let users leave the screen and notify them on completion; a Live Activity for multi-minute jobs is legitimate, but it must not be used for promotion (Guideline 4.5.3).
6. On success, fire a `.success` haptic and present 2–4 variations.
7. On failure, use plain language and offer one retry, e.g. "Faces were too small — try a closer photo".

### 5.6 Haptics map [V: HIG Playing haptics]

Use system patterns for their documented meanings, avoid overuse, make haptics optional, and don't let them disturb camera capture.

| Moment | Haptic |
|---|---|
| Slider and picker changes | `.selection` |
| Snap or detent | `.impact(.light)` |
| Generation complete or purchase success | `.notification(.success)` |
| Failure | `.notification(.error)` |

Nothing else: no haptics on every tap, and none during camera shutter or recording.

### 5.7 Sharing: watermark or not

**Evidence (thin):**
- A competitor blog says Remini's free downloads are watermarked or quality-limited, depending on platform [S, low confidence].
- In April 2025, ChatGPT tested watermarking images for free users only; commentators noted major generators didn't watermark at the time [S: TechRadar].
- Apple 3.1.2(a): users must get what they paid for "without performing additional tasks, such as posting on social media" [V]. So never require sharing to unlock paid features.

**Recommendation:**
- **Paid exports never carry a watermark.**
- Free-tier exports carry a small, tasteful corner wordmark, which acts as a viral loop, with a one-tap "Remove watermark" route to the paywall.
- Offer an *opt-in* "Made with ___" badge for paid users who want it.
- Add provenance metadata to AI-generated or AI-edited files: IPTC Digital Source Type and C2PA Content Credentials [P].
- Have counsel confirm EU AI Act Article 50 transparency obligations for AI-generated or manipulated images and their 2026 timing [P, not re-verified].
- **Share UX:**
  - "Save to Photos" as the primary action.
  - Then the system share sheet.
  - Plus quick targets for Stories/TikTok, using a before/after collage or split-reveal video export as the shareable format.

### 5.8 Platform checklist for 2026–27 [V]

- Build with the iOS 27 SDK. Glass is mandatory there, and the SDK is required for uploads from April 2027.
- Support iPhone Duo layouts and provide Duo screenshots by April 2027.
- Design App Store **product page header** and **search-result** creative assets (iOS 27+). Their guidance: one clear idea; video should loop seamlessly and work muted.
- Use Product Page Optimization for icon and header tests (§6.3).

---

## 6. App icon direction

### 6.1 What the evidence says

**Apple HIG App icons** [V; updated Jun 8, 2026]:
- "Embrace simplicity… a minimal number of shapes."
- "Prefer a simple background, such as a solid color or gradient."
- "Prefer illustrations to photos."
- Use text only when essential; a first-letter mnemonic is fine.
- "Let the system handle blurring and other visual effects."
- Layered icons are built in **Icon Composer**.
- Appearances: Default, Dark, Clear light/dark, Tinted light/dark, all at 1024×1024.
- "Keep your icon's features consistent across appearances."
- "Color backgrounds generally offer the greatest contrast in dark icons."
- Alternate icons need their own dark, clear and tinted variants.

**WWDC26 "Icon Composer for Beginners" lab, Apple designers and engineers** [V transcript]:
- iOS 27 renders sharper specular highlights. Apple **reduced translucency** in its own icons to make them "sharper and more legible", and that reduction isn't automatic.
- Avoid complexity, because glass refraction is "very sensitive to the number of shapes".
- Test at the smallest sizes, on a device, outdoors, inside a folder and among random icons.
- Use **solid overlapping shapes instead of eraser paths** so layers feel physical.
- In tinted mode, keep **part of the foreground white or near-white** and prefer system backgrounds over custom gradients.
- Maximise dynamic range in the **mono annotation**. Don't rely on colour, because of colour blindness.

**App Store** [V]: "simple and recognizable… try testing different options." Product Page Optimization can test **icons** with up to 3 treatments, for up to 90 days, at ≥90% confidence. Alternate icons must be in the binary.

**Category read** [§1]: dark and black tiles plus purple sparkles are the norm. A **warm amber tile** is the fastest way to stand out on a Home Screen full of black and purple icons.

### 6.2 Three concepts

Rough Pillow sketches are in `docs/assets/research/icon_concepts.png` and `docs/assets/research/icon_concept_A_variants.png`. They are illustrations of the idea, not final art.

**A. "Sunrise Split" (recommended; variant A2 or A3 on an amber tile)**
- *Idea:* a disc that is half graphite (before) and half light (after), divided by the compare-slider handle. It reads as sunrise/eclipse (light), before→after (enhance) and the app's signature interaction.
- *Icon Composer layers:*
  1. Background: system gradient `#FFC25C → #FF7A3D` (or solid `#FF9A3D` if tinted mode washes out).
  2. Group "before": left half-disc `#2A2622`, glass on, low translucency.
  3. Group "after": right half-disc `#FFF6E8`/white.
  4. Group "handle": a vertical bar about 22–26 px at 1024 plus a knob about 120–140 px, in ink `#1A1206` (A2) or white (A3). Keep strokes thick so they survive at 29 px.
- *Mono annotation:* before = dark grey, after = white, handle = black (A2) or white (A3).
- *Dark variant:* darken the background to deep amber (about `#B85F10 → #7A3A0C`) and keep the glyph.
- *In the sketches:* it reads clearly at 60 px and 29 px, and survives mono.
- *Risks:* the shape resembles the ◐ "contrast/appearance" glyph; the handle and the warm tile differentiate it. The HIG warns against replicating standard UI, but this is a custom metaphor, not a system control.

**B. "Light Aperture"**
- *Idea:* a camera aperture in amber, whose opening is a white 4-point star (light/magic).
- *Layers:* background near-black or deep warm; blade group with amber gradient (glass on, refraction subtle); star (white, glass off for crispness).
- *Risks:* the aperture is a stock camera metaphor, and the star is the AI cliché. In the sketch, the blade seams turn to mush at 29 px. If chosen, use 5 blades with thick seams, or drop the seams.

**C. "Light Monogram"**
- *Idea:* the initial of the chosen name (e.g., **S** for Sunlit) in Bricolage Grotesque 96pt ExtraBold, filled with the amber gradient, with a small white 4-point "flash" at a terminal. The tile is near-black, or amber with a dark letter.
- *Layers:* letter (glass on), flash (glass off), background.
- *Strengths:* the strongest wordmark link and the most legible at 29 px (per the sketch). A first-letter mnemonic is explicitly OK per the HIG.
- *Risks:* the letter is less meaningful for an unknown brand. Letter icons abound, so differentiation rests on colour.

### 6.3 Test plan

1. Build A (A2 and A3), B (simplified) and C as full Icon Composer `.icon` files, with dark, clear and tinted variants for each.
2. Do an internal "glance" test: put each in a Home Screen folder and in a crowded page, then view outdoors (Apple's own advice).
3. Ship the winning two as alternate icons.
4. Run PPO: original A vs C (and B if traffic allows), with ≥90% confidence before applying.
5. Mirror the icon's amber tile in the App Store **header asset** and the first screenshot for recognition, as Apple advises a cohesive palette, iconography and fonts across assets [V].

---

## 7. Open items and next steps

1. **Competitor icon/UI audit** (§1.5): about 15 minutes, manual.
2. **Name screening** (§4.4) for the top 8. Still to do (web, App Store, Google Play). Then run trademark checks in classes 9/42.
3. **Confirm unverified items:**
   - [P] WGSN 2026 = Transformative Teal;
   - EU AI Act Art. 50 timing;
   - the RevenueCat Photo & Video 22.2% figure, against the report PDF;
   - which fonts competitors use.
4. **Prototype:** the onboarding interactive before/after, a multi-page paywall with a trial timeline, and glass over photos at both ends of the iOS 27 transparency slider.

---

## 8. Sources

### First-party, fetched and verified during this research [V]

**Apple HIG**
- App icons (updated Jun 8, 2026): https://developer.apple.com/design/human-interface-guidelines/app-icons
- Dark Mode: https://developer.apple.com/design/human-interface-guidelines/dark-mode
- Color (Liquid Glass colour; Dec 16, 2025): https://developer.apple.com/design/human-interface-guidelines/color
- Materials (Liquid Glass regular/clear, 35% dimming): https://developer.apple.com/design/human-interface-guidelines/materials
- Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- Generative AI (updated Jun 8, 2026): https://developer.apple.com/design/human-interface-guidelines/generative-ai
- Loading: https://developer.apple.com/design/human-interface-guidelines/loading
- Onboarding: https://developer.apple.com/design/human-interface-guidelines/onboarding
- Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- JSON source used: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`

**App Store policy and guidance**
- App Review Guidelines (2.3.7, 3.1.2, 4.1, 5.1.2(i), 5.2.1): https://developer.apple.com/app-store/review/guidelines/
- Auto-renewable subscriptions (billed-amount prominence, trial disclosure): https://developer.apple.com/app-store/subscriptions/
- Creating your product page (name, subtitle, icon): https://developer.apple.com/app-store/product-page/
- Product page optimization (icon tests): https://developer.apple.com/app-store/product-page-optimization/
- App Store asset best practices (header and search-result assets): https://developer.apple.com/app-store/asset-best-practices/
- iPhone Duo, Prepare: https://developer.apple.com/iphone-duo/prepare/

**Apple Developer News**
- iPhone Duo submissions: https://developer.apple.com/news/?id=kkphp5qo
- New App Store assets: https://developer.apple.com/news/?id=ljpl7kyn
- Subscriptions for iOS 27: https://developer.apple.com/news/?id=likeohx4
- Monthly with 12-month commitment: https://developer.apple.com/news/?id=agq42lxe
- iOS 27 design kits: https://developer.apple.com/news/?id=e2lxw9l1
- iOS 27 submissions / April 2027 SDK floor: https://developer.apple.com/news/?id=k1mtkt1k
- Betas / iPhone Duo Oct 23: https://developer.apple.com/news/?id=rfb1rooi

**WWDC26**
- Icon Composer for Beginners Group Lab (transcript): https://developer.apple.com/videos/play/wwdc2026/8012/

**Fonts and brand-colour datasets**
- google/fonts: `https://raw.githubusercontent.com/google/fonts/main/ofl/{bricolagegrotesque,funneldisplay,instrumentserif,unbounded,spacegrotesk,syne,funnelsans,instrumentsans}/METADATA.pb`, plus TTF, OFL.txt and DESCRIPTION files. A 404 for clashdisplay, satoshi and generalsans.
- Brand-colour data: npm `simple-icons@16.34.0` (data/simple-icons.json) and `@lobehub/icons-static-svg@1.95.1` (icons/*-color.svg).

### Web-search sources [S]

**Competitor identity**
- Picsart: https://whatthelogo.com/logo/picsart-icon/180099, https://whatthelogo.com/logo/picsart/9755
- Photoroom media kit: https://www.photoroom.com/media
- Meitu VI PDF: https://corp-static.meitu.com/corp-new/20250930/%E7%BE%8E%E5%9B%BE%E5%93%81%E7%89%8CVI%E8%A7%84%E8%8C%83-202510.pdf
- FaceApp palette: https://brandpalettes.com/faceapp-icon-colors/
- Captions → Mirage: https://www.captions.ai/pt/artigos/new-name-new-chapter-captions-is-now-mirage and https://en.wikipedia.org/wiki/Captions_(app)
- Remini (Shotkit): https://shotkit.com/remini/
- Bending Spoons (Fortune): https://fortune.com/europe/2024/08/01/wetransfer-acquired-bending-spoons-the-italian-software-powerhouse-behind-evernote-and-meetup-vimeo-remini-evernote
- Lensa / Prisma Labs: https://techcrunch.com/2018/12/13/prismas-new-ai-powered-app-lensa-helps-the-selfie-camera-lie
- Hypic: https://www.alternativeto.net/software/hypic--photo-editor-and-ai-art/about/
- EPIK: https://techcrunch.com/2023/10/06/ai-app-epik-hits-no-1-on-the-app-store-for-its-viral-yearbook-photo-feature
- Glam AI: https://alternativeto.net/software/glam-ai/about/

**Store titles seen in results**
- Remini: https://play.google.com/store/apps/details?id=com.bigwinepot.nwdn.international&hl=en_US
- Lensa: https://apps.apple.com/us/app/-/id1436732536
- Hypic: https://apps.apple.com/FR/app/id1644042837
- EPIK: https://apps.apple.com/app/id1577705074
- Glam AI: https://apps.apple.com/us/app/-/id1545593132
- Dawn AI: https://apps.apple.com/DE/app/id1643890882
- FaceApp: https://spark.mwm.ai/en/apps/faceapp-perfect-face-editor/1180884341

**AI-purple / AI aesthetic**
- https://www.indiehackers.com/post/the-ai-purple-problem-why-every-ai-brand-looks-the-same-6cb0aa2a02
- https://uxdesign.cc/the-way-we-design-ai-looks-like-nostalgia-already-aa5dfc01d4c7
- https://pages.thefountaininstitute.com/posts/7-tells-that-a-ui-is-ai-generated
- https://pixso.net/articles/google-icon-redesign/
- https://shapeof.ai/patterns/color
- https://zeli.app/en/story/49117099

**Colour trends**
- Pantone 2026: https://www.nbcnewyork.com/news/national-international/pantone-color-of-the-year-2026/6425913/ and https://www.aol.com/articles/pantone-just-announced-2026-color-133000589.html
- Pantone 2025: https://www.catersource.com/design-decor/pantone-color-of-the-year-2025-mocha-mousse and https://textination.de/en/node/28756
- WGSN 2027: https://www.wgsn.com/en/wgsn/press/press-releases/wgsn-and-coloro-reveal-colour-year-2027-luminous-blue-and-s/s-27-key and https://fashionunited.com/news/fashion/wgsn-and-coloro-name-luminous-blue-colour-of-the-year-2027/2025042965718

**iOS 27 / Liquid Glass**
- https://macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27
- https://bgr.com/2191219/ios-27-liquid-glass-fix-customization/
- https://developer.apple.com/forums/thread/832543
- https://dev.classmethod.jp/en/articles/ios27-xcode27-migration-preparation-guide/

**CTA colour**
- https://resources.review42.com/call-to-action-tips/
- https://www.wordstream.com/blog/ws/2019/02/04/landing-page-design
- https://creativemarket.com/blog/how-to-design-buttons
- https://www.poper.ai/blog/cta-button-color-conversion/
- https://www.betterlaunch.co/playbooks/roast-paywall-aga25-3

**Paywall and onboarding data**
- Adapty:
  - https://adapty.io/state-of-in-app-subscriptions-report/
  - https://adapty.io/blog/mobile-app-monetization-2026/
  - https://adapty.io/blog/photo-video-app-subscription-benchmarks/
  - https://adapty.io/blog/your-toggle-paywall-is-about-to-get-rejected/
- RevenueCat:
  - https://www.revenuecat.com/state-of-subscription-apps
  - https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026
  - https://www.revenuecat.com/blog/growth/rip-toggle-paywall
  - https://www.saastr.com/the-top-10-learnings-from-revenuecats-state-of-subscription-apps/
  - https://thesocialoutline.com/blog/trial-to-paid-conversion-rate-benchmarks
- Superwall:
  - https://superwall.com/blog/new-postmulti-page-onboarding-paywalls-convert-37-better-than-single-page-heres-why
  - https://superwall.com/blog/external-checkout-a-b-testing-and-trial-toggles-confirmed-apples-rules-for-ios
  - https://api.superwall.me/blog/superwall-best-practices-winning-paywall-strategies-and-experiments-to
- Apphud:
  - https://apphud.com/blog/design-high-converting-subscription-app-paywalls
  - https://apphud.com/blog/ab-test-ideas-for-subscription-apps
- Airbridge: https://www.airbridge.io/en/blog/paywall-conversion-structural-decisions
- Apple forum on 3.1.2(c): https://developer.apple.com/forums/thread/841626
- Lazyweb Research:
  - https://www.lazyweb.com/research/photo-video-paywall-dark-or-light-background
  - https://www.lazyweb.com/research/dark-or-light-what-background-do-mobile-paywalls-use
  - https://app.lazyweb.com/research/paywall-trial-timeline-ui-prevalence
  - https://www.lazyweb.com/research/what-is-the-most-common-primary-paywall-cta-text
  - https://www.lazyweb.com/research/what-percent-of-paywalls-preselect-the-annual-plan
  - https://www.lazyweb.com/research/photo-video-apps-paywall-cta-changes
  - https://experiments.lazyweb.com/research/remini-paywall-price-cta-experiments
  - https://www.lazyweb.com/research/what-percent-of-apps-put-the-paywall-on-the-last-onboarding-step
  - https://www.lazyweb.com/research/do-photo-and-video-apps-paywall-early-in-onboarding
  - https://www.lazyweb.com/research/are-onboarding-flows-with-a-paywall-longer
- Blinkist:
  - https://uxplanet.org/how-solving-our-biggest-customer-complaint-at-blinkist-led-to-a-23-increase-in-conversion-b60ad514134b
  - https://blog.curtisherbert.com/slopes-diaries-39-risky-business/
  - https://b2bpricinginsights.substack.com/p/4-min-read-how-blinkists-new-paywall

**Loading, compare slider and watermark**
- https://chameleon.io/patterns/loading-states
- https://dev.to/aon_infotech_3a1b6ff525fc/building-a-loading-state-that-doesnt-feel-slow-lessons-from-an-ai-generation-tool-4ed
- https://support.poper.ai/en/articles/14964745-how-can-i-make-the-before-after-slider-widget-compare-images-clearly-without-confusing-users
- https://help.maglr.com/en/article/beforeafter-slider-1dboicx/
- https://summit.calgary.ca/components/media-overview/before-and-after-slider.html
- https://www.techradar.com/computing/artificial-intelligence/chatgpt-free-users-look-away-now-openai-is-testing-watermarks-on-image-generation-that-could-render-the-feature-redundant-unless-you-pay
- https://morphed.app/blog/remini-free-limits
