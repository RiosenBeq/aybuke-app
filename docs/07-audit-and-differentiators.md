# 07 · Audit: girl-first details and what competitors don't have

October 2026. We audited our own ideas against user reviews and competitor apps (Facetune, Remini, Lensa, Picsart, Meitu, BeautyPlus, YouCam, Hypic, GlowUp/Glam AI, Retake, EPIK, B612, SNOW, Ulike, AirBrush, Peachy, Wink, Dazz, Huji, Tezza, VSCO). Ideas were shipped in this order: design, then technical, then features. Anything a competitor already does well, or that adds little, was cut.

## What users complain about (2024–2026)

1. **"Doesn't look like me."** In August 2026 Tinder paused its AI photo enhancer after users said it lightened skin and changed freckles ([WCAX/CNN](https://www.wcax.com/2026/08/05/tinder-pauses-ai-photo-enhancing-tool-after-users-said-it-drastically-changed-their-appearance-without-their-approval/)). GlowUp reviews report results with "no resemblance" ([App Store](https://apps.apple.com/app/id6736916284)).
2. **Beauty pressure on girls.** In a 2024 survey, 54% of girls aged 11–21 wished they looked like their filtered selves ([Girlguiding](https://www.girlguiding.org.uk/about-us/press-releases/gas-teaser-24)).
3. **Privacy of face photos** ([The Week, Sep 2025](https://www.theweek.in/news/sci-tech/2025/09/16/beware-of-nano-banana-ai-saree-trend-creepy-ai-edits-on-google-gemini-scares-users-how-to-protect-your-privacy.amp.html)).
4. **Picking the best photo is hard.** More than half of respondents said so in a Tinder survey ([Scripps](https://www.scrippsnews.com/science-and-tech/artificial-intelligence/tinders-new-ai-tool-helps-users-choose-pictures-that-are-most-likely-to-get-matches)).
5. **Editing friends without asking** ([BuzzFeed, Jul 2026](https://www.buzzfeed.com/ellendurney/chloe-kim-tiktok-facetune-editing-debate); [Thorn, Mar 2025](https://www.thorn.org/blog/deepfake-nudes-are-a-harmful-reality-for-youth-new-research-from-thorn/)).
6. **Asking for notifications and reviews before showing any value** (GlowUp reviews).
7. **Ads and forced extras when saving** (Remini and Facetune reviews).
8. **Quality loss and walls on export** ([Unstar 2026](https://unstar.app/blog/photo-editing-app-reviews-what-creators-hate-most-2026); Tezza reviews).

## 1. Design (shipped)

| Item | Why |
|---|---|
| **Sharp-edged template cards** (`Metrics.printRadius = 0`): looks read like prints, while controls stay soft | Requested; editorial and fashion-like next to the soft UI |
| **Collection pages** ("See all" on every category): a lookbook grid with numbered cards (N°01…) | Browsing a whole category was impossible before |
| **Double-tap to heart** in My Works, with a heart pop and a two-beat haptic | Instagram muscle memory; faster than the toolbar button |
| **Calmer waiting screen** (more opaque frosting, no grey blobs) | Polish |

## 2. Technical (shipped)

| Item | Why |
|---|---|
| **Opt-in local notifications**: glow ready, free credits back (only after running out), one look a week. All off until switched on; never 21:00–09:00 or during school hours (08:00–15:00 on weekdays); no push server | Pain point 6; UK Children's Code standards 5 and 13; EU DSA minors guidelines and US SB 976 as benchmarks |
| **Permission asked in context**: "Ping me when it's ready" on the waiting screen, and "Remind me when free credits are back" as the free alternative on the out-of-credits paywall | Ask when it relates to what she's doing ([Apple](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)) |
| **Review prompt only at happy moments**: the third save, share or heart, from day 3, once per version, 120+ days apart, never after a failure, report, likeness retry or within 30 minutes of a paywall | [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews), Guideline 5.6.1 |
| **Optional Sign in with Apple** (requested): Pro and credits follow her to another iPhone. The anonymous account merges into the account; Apple tokens are revoked on deletion | Requested; Guideline 5.1.1(v) |
| **Fixes found during the audit**: the app said photos are deleted "within 24 hours" while the policy, website and backend say 1 hour (now consistent); Live Activity ends quietly on cancel; unused badge permission removed | Consistency and compliance |

## 3. Features: gaps no competitor fills (shipped)

| Feature | Competitors | What we built |
|---|---|---|
| **Likeness check** | None found; others rely on users flagging bad results | After a people edit, Vision compares face proportions and skin lightness with the original, on the device. If the result drifted (for example lighter skin), it says so and offers the free retry. Otherwise it shows "Still you ✓" |
| **Which vibe?** | None found among photo editors | A 9:16 "A or B?" card with two variations of one creation (never her original photo against an edit) for Stories or group chats. Needs a multi-image Create, so Pro |
| **Best shot** | None among editors (Tinder has a dating-only version) | Pick up to 12 selfies; Apple's face capture quality sorts them by light, focus and how clearly the face shows, and the top one gets a "Best light & focus" chip (no crown, no rank numbers). Never by looks. Free and on-device |
| **Kindness reminder** | None found | Two or more faces → a gentle, skippable "Ask them first 💗" with **Only edit me** (Magic Edit keeps everyone else as they are) |
| **Visible "AI-edited" label** | None found | An optional corner label in the share composer, on top of the invisible IPTC label |

## Cut, with reasons

| Idea | Why it was cut |
|---|---|
| Steal the look (copy hair, makeup or an outfit from a reference photo) | YouCam, GlowUp and Google Doppl already do it, with likeness complaints. Revisit later with Likeness Lock as the difference |
| Instagram grid preview | Tezza has one, and Instagram now reorders grids natively |
| Photo-dump / carousel builder | BeautyPlus and Picsart have it. A later version could apply one look across a whole dump |
| Birthday perks | Needs a birth date: against data minimisation (ICO standard 8) |
| "How much AI" strength slider | Generative edits aren't pixel-aligned, so blending would ghost |
| Time-of-day greetings, streaks, badges | Low value; streaks are a nudge technique we avoid for teens |
| Alternate app icons | Cheap but low impact; kept for a later update |
