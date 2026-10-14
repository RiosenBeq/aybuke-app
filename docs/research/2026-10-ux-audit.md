# UX audit and first fixes (14 October 2026)

A pass over every main flow of Aybuke, after the October feature audit and the "sharpen the corners" redesign, with one question: is the app easy to use, does it feel made for her, and does it ask for money honestly? This document lists what we found, what changed in this pass and what we recommend next.

For the earlier research see [2026-10-feature-audit.md](2026-10-feature-audit.md) (competitors, trends, wellbeing, compliance; what was built, deferred or rejected). Nothing here reopens a rejected idea: no streaks, feeds or likes, no beauty scores, no urgency, and under-18s never see a paywall on their own.

## 1. How we looked

- **Screens:** every DEBUG screenshot scene in English at the default text size (`ScreenshotScenes.swift`: onboarding pages, age, try-it, Explore, a collection, Create, results, recent prompts, the editor with each tool, Retro Cam, collage, video, Best shot, share, invite, My Works with select mode and Recently deleted, paywall, out of credits, consent, Settings, Feel good, legal, tips, tour).
- **Code:** each flow end to end, from the entry point to the last toast, including the gates in `AppModel.requestAccess`, the age rules in `AgeDefaults`, the credit wallet, the widgets and the tips.
- **Lens:** unclear copy, dead ends, missing empty and error states, hard-to-find features, extra taps, inconsistent words, the first-run "aha", how credits and Pro are explained, accessibility (labels, hints, Dynamic Type, targets) and the honest moments to offer more.

Work on the editor's tool list and Magic Edit panel (a Makeup Studio tool), the template and style catalogs, collage layouts, stickers, effects, captions and My Works' select mode was going on in parallel, so findings there are recommendations only.

## 2. What we found

The ten that mattered most, in order:

1. **Credits were a number with no explanation.** Explore's credit pill only showed a count. Tapping it opened the paywall for free members and Settings for Pro, so the first explanation of credits a teen got was a sales page. Create showed what Generate costs but never what she had left. The widgets explained credits better than the app ("3 free credits today", "New credits in …").
2. **The paywall never said why it was there.** Running out of free credits, tapping a Pro look, choosing a Pro style or more than one image, and "Remove it with Pro" all opened the same screen.
3. **The paywall overstated Pro.** "Aybuke Pro unlocks every tool and trend", but every on-device tool is free for everyone; Pro unlocks the Pro looks and styles, more images at once, the best-quality AI and no mark. Nothing on it said what stays free.
4. **One-tap looks spend a credit with no price on the way.** A look card opens the photo picker and the look runs as soon as she picks a photo. No card, collection page or the editor's Styles panel mentions the credit (Magic Edit, Enhance and Erase all show theirs).
5. **"What's free" changed from screen to screen.** Settings named background removal and adjustments; the Pro out-of-credits sheet, the consent sheet and the offline note named four tools each. None mentioned Retro Cam, collages, Crop, Hide faces or Text & Stickers.
6. **Create results were kept silently.** Every result goes to My Works as it arrives, but the results screen didn't say so; Save (to Photos) looked like the only way to keep a picture.
7. **A dead end under 13.** My Works' empty state says "Create something" and switches to the Create tab, which doesn't exist under 13 (nor when Apple's age range is required and declined): the tab bar lands on nothing.
8. **Half the editor is out of sight on iPhone.** The tool bar shows five of ten tools and scrolls, with no partial tool or fade to say there is more (`EditorToolBar.swift:34`). Cut out, Erase, Adjust, Crop and Hide are easy to miss.
9. **Three words for two things.** The editor's tool for one-tap looks is "Styles" (`EditorTool.swift:21`), Create's art styles are "Style", Explore calls the looks "looks"; background removal is "Remove BG" on the hub, "Cut out" in the bar and "background removal" in copy.
10. **A long first run.** After the try-it photo (and, for adults, the paywall) comes a seven-step tour. The roadmap already plans a shorter one (`tipkit-and-short-tour`).

### By flow

| Flow | Finding | Evidence | Status |
|---|---|---|---|
| First run | The age step on iOS 26 is a headline, one line and Continue; nothing says Apple's sheet comes next | `AgeStepView.swift:60`, scene `age` | Recommended (compliance-sensitive wording) |
| First run | The try-it result offers Keep editing and Save, but no Share at the happiest moment | `OnboardingView.swift:149` | Recommended |
| First run | Seven tour steps after onboarding; Settings' step adds little | `GuidedTour.swift:6` | Recommended (`tipkit-and-short-tour`) |
| Explore | Credit pill opened a paywall or Settings; VoiceOver heard "3 credits left" with no hint | `HomeView.swift` (old `HomeCreditPill`) | **Fixed** |
| Explore | Look cards don't say a tap asks for a photo and then runs the look | `TemplateCard.swift`, `HomeView.swift:254` | **Fixed** for VoiceOver (hint) |
| Collections | No price before a one-tap look spends a credit | `CategoryView.swift` | **Fixed** |
| Explore | "NEW" badges on Retro Cam, Best shot, collage and video never expire | `EditHubView.swift:76`, `:110`, `RetroCamView.swift:475`, `CollageView.swift:735` | Recommended (date-limit them) |
| Create | Balance not shown; cost only | `CreateView.swift` | **Fixed** |
| Create | A locked Pro style or image count can be picked; Generate then opens an unexplained paywall | `CreateViewModel.swift`, `AppModel.requestAccess` | **Fixed** (paywall says which) |
| Create | Generate is dimmed with an empty prompt and nothing says why (the placeholder only) | `CreateView.swift:303` | Recommended (hint or caption) |
| Results | Kept in My Works without saying so | `ResultsView.swift` | **Fixed** |
| Editor | Tool bar overflow has no visual cue | `EditorToolBar.swift:34` | Recommended |
| Editor | Styles panel shows no credit cost, unlike Magic Edit, Enhance and Erase | `EditorPanels.swift:91` | Recommended |
| Editor | "Styles" vs Create's "Style"; "Remove BG" vs "Cut out" | `EditorTool.swift:21`, `:25` | Recommended (call them Looks and Cut out) |
| Editor | Save says "Saved to Photos" but also adds the photo to My Works | `EditorView.swift:604` | Recommended (minor) |
| Best shot | Every tile but the first is read as "Photo" | `BestShotView.swift:264` | Recommended ("Photo 3 of 6") |
| My Works | Empty state sends under-13s to a missing Create tab | `LibraryView.swift:191`, `:632` | **Fixed** at the model; the button still says "Create something" (recommended: "Edit a photo" under 13, and a second "Edit a photo" button for everyone) |
| Paywall | No reason shown | `PaywallView.swift` | **Fixed** |
| Paywall | "Unlocks every tool and trend" | `PaywallView.swift` | **Fixed** |
| Paywall | What stays free not stated | `PaywallView.swift` | **Fixed** |
| Out of credits (Pro) | Free list named four tools | `OutOfCreditsSheet.swift` | **Fixed** |
| Settings | Credits footer named two free tools | `SettingsView.swift` | **Fixed** |
| Everywhere | Offline note names four free tools, not Retro Cam or collages | `OfflineNotice.swift:11` | Recommended |
| Design | Radii left from before the sharpening: toast 18, preview banner 16, paywall pending card and pack rows 18 | `Toast.swift`, `HomeView.swift`, `PaywallView.swift` | **Fixed** |
| Design | Quick tool tiles 20, collage glass panel 18, Retro Cam capsules | `HomeView.swift:397`, `CollageView.swift:343`, `RetroCamView.swift:385` | Recommended (owned by parallel work, or camera chrome) |

What already works well and should stay: the on-device try-it before any paywall; the consent sheet's equal buttons and named processors; the trial timeline with the billed price beside the button; "No weekly plans, ever."; packs offered to Pro members who run out; the kindness note with Hide their faces; Ideas for this photo and Surprise me; empty and error states in Retro Cam, collage and video; 44 pt targets, VoiceOver announcements and Reduce Motion across the editor.

## 3. What changed in this pass

| # | Change | Where |
|---|---|---|
| 1 | **"Your credits" sheet.** The credit pill (free and Pro) and the balance under Create's Generate open it: the balance, when free credits are back (a relative time, only once some are used) or Pro's next refill when known, the daily or monthly rule, what uses a credit ("AI tools use 1 credit per picture: Magic Edit, looks, Enhance, Erase and Create") and what is always free, then one quiet "Get more credits" (the plans for free members, packs for Pro). No more paywall from a tap on a number | `Features/Paywall/CreditsSheet.swift` (new), `HomeView.swift` (`HomeCreditPill`), `CreateView.swift` (`creditsLink`) |
| 2 | **Balance under Generate** ("3 credits left", crown for Pro) | `CreateView.swift` |
| 3 | **The paywall says why it opened**: "You've used today's free credits" with "Free credits are back in 5 hr", "Doll Box is part of Pro", "Fantasy is part of Pro", "Creating several images at once is part of Pro", or that Pro removes the mark. Create and the editor pass the reason through `requestAccess(proSource:)` | `PaywallView.swift` (`PaywallReason`, `ReasonCard`), `AppModel.swift`, `CreateViewModel.swift`, `EditorViewModel.swift` |
| 4 | **Honest paywall subtitle**: "Aybuke Pro unlocks every look and style." | `PaywallView.swift` |
| 5 | **What stays free, on the paywall**: "Always free: every on-device tool and 3 AI credits a day." next to "No weekly plans, ever." | `PaywallView.swift` |
| 6 | **Price before one-tap looks**: "1 credit per look · failed looks are refunded" on collection pages | `CategoryView.swift` |
| 7 | **One free list everywhere**: the credits sheet and the Pro out-of-credits sheet say "Always free: effects, Retro Cam, Cut out, Adjust, Crop, Hide faces, Text & Stickers, collages and videos."; Settings uses the tour's rule ("Free tools never use credits, and failed edits are always refunded") | `CreditsSheet.swift`, `OutOfCreditsSheet.swift`, `SettingsView.swift` |
| 8 | **"Saved to My Works"** under Create's results; a tap opens My Works | `ResultsView.swift` |
| 9 | **No dead-end tab under 13**: any request for the Create tab lands on Edit when cloud AI isn't offered | `AppModel.swift` (`selectedTab`) |
| 10 | **VoiceOver hints**: the credit pill and Create's balance ("Shows your credits and how they work"), look cards on Explore and collection pages ("Choose a photo to try this look", or "Upgrade to Aybuke Pro" for a Pro look), and the saved note ("Opens My Works") | `HomeView.swift`, `CategoryView.swift`, `CreateView.swift`, `ResultsView.swift` |
| 11 | **Shared corners** for the toast, the preview-build banner and the paywall's pending card and pack rows | `Toast.swift`, `HomeView.swift`, `PaywallView.swift` |

Every new string (15) is translated into all 11 languages in `Localizable.xcstrings`, reusing the catalog's words for each tool and its informal tone; existing strings were reused where they already said the right thing ("%lld credits left", "Next refill: %@", the tour's credit rules, "Saved to My Works", "Upgrade to %@ Pro").

The age rules are unchanged: the credits sheet exists only where credits do (not under 13), its purchase button only where purchases are allowed, and nothing here opens a paywall on its own.

## 4. Recommended next

In rough order of value for effort:

1. **Price on the editor's Styles panel** ("1 credit per look · failed looks are refunded", as on collection pages) and an overflow cue on the editor's tool bar (a partly visible next tool or a fade at the edge). `EditorPanels.swift`, `EditorToolBar.swift`.
2. **One name per thing**: the editor's "Styles" tool becomes "Looks" (Create keeps "Style" for art styles); "Remove BG" becomes "Cut out" everywhere. `EditorTool.swift`, catalogs.
3. **My Works' empty state**: "Edit a photo" (opening the photo picker) next to "Create something", and only "Edit a photo" under 13. `LibraryView.swift:190`, `:631`.
4. **Shorter first run**: three or four tour steps (Magic Edit, credits, free tools, My Works), with tips for the rest, as planned in `tipkit-and-short-tour`.
5. **Share on the try-it result**: the first creation is the moment she wants to show it.
6. **Small copy fixes**: Save in the editor says "Saved to Photos and My Works"; the offline note uses the shared free list; Best shot tiles read "Photo 3 of 6"; Generate explains why it's dimmed; "NEW" badges end a few weeks after a release.
7. **Age step hint** on iOS 26: one line saying Apple's sheet opens next (with counsel, since the wording is part of age assurance).
8. **Last radii**: quick tool tiles, the collage glass panel and Retro Cam's capsule buttons.

## 5. How to check on screen

| What | Launch arguments |
|---|---|
| Credits sheet (free member) | `-GLScreenshotScene home -GLCreditsSheet YES` |
| Paywall reasons | `-GLScreenshotScene paywall -GLPaywallSource out_of_credits` (also `template_doll-box`, `style_fantasy`, `create_count`, `share_watermark`; without it, no reason card) |
| Balance under Generate | `-GLScreenshotScene create` |
| Saved to My Works | `-GLScreenshotScene results` |
| Collection price line | `-GLScreenshotScene collection` |
| Full free list for Pro | `-GLScreenshotScene outOfCredits` |
| Credits footer | `-GLScreenshotScene settings` |
| Under 13 | `-GLScreenshotScene home -GLAgeBand under13`: no credit pill. On a fresh install, `-GLScreenshotScene library -GLKeepLibrary YES -GLAgeBand under13`, then "Create something": Edit opens |

Worth a look at large text sizes and in Turkish and German (the longest strings): the credits sheet scrolls and drops its icon circles at accessibility sizes, and the paywall's reason card wraps.
