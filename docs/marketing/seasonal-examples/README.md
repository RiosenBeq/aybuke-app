# Seasonal look examples

Real results of Aybuke's seasonal looks, shown on Explore's season banner, its
Coming soon card and the looks' own cards (downsampled copies in
`ios/App/Resources/Assets.xcassets`, `SeasonExampleHalloween1…3` and
`SeasonExampleWinter1…3`; the mapping is `SeasonalTheme.examples` and
`PhotoTemplate.exampleImageName` in `ios/App/Features/Home/SeasonCards.swift`).

- **Made by the app's own looks**: each one went through the live `ai-image`
  backend on 15 October 2026 (`restyle` with the look's `template_id`, Pro
  quality, xAI Grok Imagine, Claude's photo and result checks), from a test
  account that was deleted afterwards. Nothing was retouched.
- **The people are fictional adults** from [`../samples`](../samples) (made with
  AI for Aybuke). Never replace them with photos of real people, and never with
  minors.
- Kept only results that are fully clothed, cute rather than scary, keep the
  person recognizable and show the look clearly. One more run (Witchy Glam on
  `portrait-c`) was left out because the outfit came back off the shoulder.

| File | Look (`template_id`) | Input sample | Job date | Asset |
|---|---|---|---|---|
| `witchy-portrait-a.jpg` | Witchy Glam (`witchy`) | `portrait-a.jpg` | 2026-10-15 | `SeasonExampleHalloween1` |
| `spooky-portrait-b.jpg` | Spooky Portrait (`spooky`) | `portrait-b.jpg` | 2026-10-15 | `SeasonExampleHalloween2` |
| `spooky-portrait-c.jpg` | Spooky Portrait (`spooky`) | `portrait-c.jpg` | 2026-10-15 | `SeasonExampleHalloween3` |
| `snow-globe-portrait-a.jpg` | Snow Globe Me (`snow-globe`) | `portrait-a.jpg` | 2026-10-15 | `SeasonExampleWinter1` |
| `cozy-sweater-portrait-b.jpg` | Cozy Sweater Digicam (`cozy-sweater`) | `portrait-b.jpg` | 2026-10-15 | `SeasonExampleWinter2` |
| `new-year-portrait-c.jpg` | New Year Confetti (`new-year`) | `portrait-c.jpg` | 2026-10-15 | `SeasonExampleWinter3` |

Galentine's looks have no examples yet, so their banner and card keep the drawn
art. To add some, run the looks the same way, keep the originals here and add
450 × 600 JPEG copies (quality 80) to the asset catalog.
