# 06 · Roadmap & task breakdown

Legend: ✅ done in this repository · ⏳ next · 🔭 later

## Phase 0 — Research & definition ✅

- ✅ Market & competitor research: 15 apps, user loves and pains, trends, monetization benchmarks → [01](01-market-research.md)
- ✅ Brand & design research: hue map, palettes with WCAG checks, typography, naming, UX patterns, icon → [research](research/brand-and-design.md)
- ✅ AI technology & compliance research: models, fal.ai, Supabase, Apple frameworks, App Review, EU AI Act → [research](research/tech-and-compliance.md)
- ✅ Name decision: **Aybuke** (domain screen) · palette **Blush** (pink, replacing the original Golden Hour amber) with **Aura** accents · **Poppins** + New York Italic accents (Bricolage Grotesque until Oct 2026) · icon **Glow Gem** (Oct 2026; was Glow Print, before that Sunrise Split) → [02](02-brand-identity.md)
- ✅ Product spec: positioning, features, flows, pricing, unit economics, KPIs → [03](03-product-spec.md)

## Phase 1 — Foundation ✅

- ✅ Xcode 16+ project (synchronized folder), shared scheme, StoreKit test configuration
- ✅ `AppCore` package
  - API contract, credit wallet, catalogs, prompt builder, content policy, polling
  - 170 unit tests (incl. the age defaults, provenance, the look suggester, crop geometry, retro overlay maths, developer-mode AI providers with xAI, the legal Markdown parser, widget/deep-link helpers, notification and rating rules, accounts, the prompt policy in every app language, Auto adjust and silence cutting), run on Linux and macOS
- ✅ Design system
  - Tokens: palette, type, metrics
  - Components: buttons, chips, badges, cards, aurora background, generating overlay, before/after slider, template card, toast, share sheet
- ✅ Bundled fonts: Poppins Medium, SemiBold, Bold and ExtraBold, OFL licence included
- ✅ App icon (1024 px) + accent color + privacy manifest + `AppConfig.json`

## Phase 2 — MVP features ✅

- ✅ Onboarding: value pages, interests, **free on-device "try Digicam '04 on your photo"** that opens in the editor or saves to My Works, then the soft paywall (adults) and the tour
- ✅ Explicit AI consent (5.1.2(i)), revocable
- ✅ Explore: hero, quick tools, personalised template rows
- ✅ Editor
  - Tools: Magic Edit, Styles, Enhance, Remove BG (on-device), Erase (brush mask), Adjust (on-device), Crop (on-device: posting shapes, rotate, mirror, straighten)
  - Undo/redo, hold-to-compare, before/after slider, pinch and double-tap zoom on the canvas
  - 🔭 Zoom in Erase's brush canvas (two fingers pan and zoom, one finger paints)
  - Free "Retry" (Likeness Lock), save and share with provenance
- ✅ Create: prompt, styles, aspect ratios, multi-image (Pro), "Surprise me", "Enhance prompt", "Inspire me" and "Make it magic" from the on-device writer, Create with Image Playground, results with a develop reveal, report
- ✅ My Works library (SwiftData + protected files)
- ✅ Paywall
  - Plans: annual with trial (preselected) and monthly; credit packs
  - Trial timeline and reminder notification; restore
  - Compliant copy (3.1.2)
- ✅ Settings: membership, credits, consent, delete creations, delete account, legal, acknowledgements
- ✅ Demo mode: the full app works offline with simulated, clearly labelled results
- ✅ Motion and details: staggered reveals, springy buttons, twinkling hearts and sparkles, orbiting charms while generating, a before/after "peek"; all respect Reduce Motion
- ✅ Widgets: Today's trend and My glow (Home and Lock Screen), App Group snapshot, `glowlit://` deep links
- ✅ Live Activity: Dynamic Island (compact, expanded, minimal) and Lock Screen progress for cloud jobs
- ✅ Audit → [07](07-audit-and-differentiators.md): sharp lookbook collection pages, double-tap to heart, opt-in notifications with quiet and school hours, happy-moment rating prompts
- ✅ Differentiators: likeness check, Best shot, Which vibe?, kindness reminder, visible AI-edited label
- ✅ Optional Sign in with Apple: account merge (`merge_accounts`), Apple token revocation on deletion

## Phase 3 — Backend ✅ (code) / ⏳ (deploy)

- ✅ Supabase schema
  - Tables: wallets, append-only ledger, jobs, entitlements
  - RLS; atomic `reserve`/`release`/`grant` functions; sweeper
- ✅ Edge Functions: `ai-image` (create/poll/cancel/balance), `credits-redeem`, `account`
- ✅ xAI integration (default provider): Grok Imagine `grok-imagine-image-2.0` at 1k, low quality for free users and medium for Pro; requests run in the background (`EdgeRuntime.waitUntil`); results are returned inline and cleared once the app confirms the download
- ✅ fal.ai integration (alternative, `AI_PROVIDER=fal`)
  - Queue API; one model per operation; outputs expire after 1 hour; no request history
- ✅ Apple JWS verification (App Store Server Library); entitlement binding
- ✅ Safety
  - Server prompt policy; server-only template recipes; strict model safety; output NSFW check
- ✅ CI: Deno fmt/lint/check plus SQL ledger tests on PostgreSQL
- ⏳ Create the Supabase project, set secrets (`XAI_API_KEY`), deploy, and schedule `sweep_jobs` → [backend/README.md](../backend/README.md)
- ⏳ Switch on **Zero Data Retention** for the team in the xAI console (selfies are personal data)
- ⏳ Point `AppConfig.json` at the project; run end-to-end on TestFlight
- ⏳ Check xAI's current prices and latency; if fal is used, verify it accepts data-URI inputs on every endpoint

## Phase 4 — Launch readiness ⏳

**Legal and brand**
- ⏳ Clear the name **Aybuke**: App Store/Play search; USPTO/EUIPO classes 9 and 42; social handles
- ⏳ Register `glowlit.app`
- ✅ Drafted Terms of Use (EULA), Privacy Policy, Acceptable Use Policy (EN/TR) and the KVKK notice, bundled in the app and published under `docs/legal/` → [legal/README.md](../legal/README.md)
- ⏳ Lawyer review, fill in `legal/config.json`, publish at stable URLs, sign DPAs and KVKK standard contracts

**App Store**
- ⏳ App Store Connect setup
  - Bundle id `app.glowlit.ios`
  - Products: `app.glowlit.pro.yearly` ($39.99, 7-day free trial), `app.glowlit.pro.monthly` ($5.99, first month $1.99 introductory offer), `app.glowlit.credits.30` ($2.99), `app.glowlit.credits.100` ($7.99)
  - Set `APPLE_APP_ID`
- ✅ RevenueCat project created; public SDK key in `AppConfig.json` (observer mode, on in builds)
- ⏳ Upload the App Store Connect in-app purchase key (.p8) in RevenueCat (owner)
- ⏳ App Store Server Notifications V2 endpoint for refunds, revocations and Texas consent revocation (backlog `abuse-ops-reports-bans`)
- ⏳ Turn on Sign in with Apple for the app id, enable the Apple provider in Supabase, set `APPLE_TEAM_ID` / `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY`, set `signInWithApple` to true in `AppConfig.json` (off in 1.0), and test sign-in and the merge on two devices
- ✅ Age step with the Declared Age Range API and teen defaults (on-device only under 13, no automatic paywall under 18, guardian step in the consent sheet)
- ⏳ Age rating questionnaire (target 13+ with the override; "Age Assurance" once shipped)
- ✅ "Glow Gem" app icon (Oct 14, replacing Glow Print) with dark and tinted variants and Mac sizes (`scripts/render-brand-assets.py`; concepts in [brand/icon-concepts](brand/icon-concepts/concepts.png))
- ⏳ Build with the latest SDK (iOS 26/27); Icon Composer `.icon` with clear variants
- ✅ App Store copy (EN/TR), 8 generated screenshots per language, social images → [marketing](marketing/README.md)
- ⏳ Recapture the screenshots with real AI results (needs an AI key), including the new effects and Cover star scenes in `screenshot-captions.json`; header asset, Custom Product Pages
- ⏳ Localized App Store metadata and screenshots for the app's other languages

**Hardening and quality**
- ⏳ App Attest + DeviceCheck + `appTransactionID` binding against free-credit farming (backlog `abuse-ops-reports-bans`)
- ⏳ QA identity fidelity across skin tones and hair textures; red-team the safety filters and keep evidence logs
- ⏳ Replace the template card art with real before/after thumbnails (diverse casting)
- ✅ Backend `report` endpoint + `reports` table (12-month retention) wired to "Report this image"
- ⏳ Ban list and an abuse inbox/review routine (1.2) (backlog `abuse-ops-reports-bans`)
- ✅ Independent, fail-closed safety check before the backend goes live (backlog `server-moderation-stack`): Anthropic's Claude checks the photo before an edit and every result, on top of xAI's own moderation (`_shared/safety.ts`; consent version 2 names Anthropic). ⏳ Confirm it on the live API after the deploy
- ✅ Release guard: `scripts/check-release-config.py` stops demo-mode and placeholder builds; `scripts/check-honest-copy.py` in CI

## Phase 5 — Growth 🔭

- 🔭 Likeness Lock v2: 3–5 selfie profile with an identity-similarity check before showing results
- 🔭 Packs: Headshot pack (20 photos), Restore pack, seasonal trend packs
- 🔭 Motion: short video versions of templates (figurine → spin, polaroid → develop)
- 🔭 Remote template catalog with thumbnails, a kill switch, A/B tests and a "Trending this week" CPP feed (backlog `backend-ai-looks`); date-windowed seasonal looks shipped in Phase 7
- 🔭 C2PA Content Credentials (server-signed) and an imperceptible watermark (backlog `c2pa-trustmark`; the optional visible "AI-edited" label has shipped)
- 🔭 Webhooks or Realtime push instead of polling; push-updated Live Activities
- 🔭 Interactive widgets (iOS 17+) (backlog `widgets-interactive-accented`)
- 🔭 Steal the look (reference photo) with Likeness Lock; one look across a whole photo dump; alternate app icons
- 🔭 Optional iCloud sync of My Works (the user's own iCloud, never our servers)
- 🔭 iPhone Duo adaptive layouts (12 languages and iPad shipped in Phase 6)
- 🔭 Swift 6 strict concurrency; UI tests; snapshot tests
- 🔭 Privacy-friendly product analytics, paywall experiments, Apple Ads (subscription analytics shipped with RevenueCat in Phase 6)

## Phase 5 — Girls-first redesign and growth ✅ (October 2026)

- ✅ Pink "Blush" palette (sampled from the owner's reference brand), light-first with Dark and Automatic appearances
- ✅ Girls-first catalog: 36 year-round looks in Trending, Glow-up looks, Aesthetic edits, Dreamy portraits, Art, Pet portraits and For your shop, plus seasonal looks (Halloween, winter, Galentine's) promoted on Home in season; 14 styles incl. Pastel Dream and Kawaii; identity clause now protects body shape too
- ✅ Content pack: 51 year-round looks (Bow Era, Soft Film, Sticker Sheet, Holo Card, Grad Day, Manga Panel, three more pet looks and a Bestie pics collection with Sleepover, Bracelet Club, Twinning and Concert Night); 20 styles (Sticker, Storybook, Pop Art, Cozy Knit, Paper Craft, Diorama); more Inspire me, caption and Magic Edit ideas that vary by photo; four collage arrangements; all translated and policy-tested in 11 languages
- ✅ Share composer: Instagram Stories, before/after collage, 9:16 story card, caption and hashtags, copy image, AI-label tip
- ✅ Favorites in My Works, sparkle celebration, editorial serif accents, Settings › Appearance and "Spread the glow"
- ✅ Developer AI key slot (`ios/Config/Secrets.xcconfig`, DEBUG only) with direct xAI, fal.ai, OpenAI and Gemini adapters
- ✅ Landing page (`web/`) with legal pages and a manual GitHub Pages workflow
- ⏳ Add the owner's AI key and verify real results end to end; recapture marketing screenshots
- 🔭 Optional: Meta App ID for direct Instagram Stories sharing (`instagramAppID`); Stories already works through the share sheet without it
- ✅ Typeface: display font switched to Poppins (SIL OFL)
- 🔭 Backend adapters for OpenAI/Gemini if production moves off xAI and fal.ai

## Phase 6 — Video, retro effects, xAI and 12 languages ✅ (October 2026)

- ✅ Simple on-device video editor: auto-cut silences (jump cut), retro effects with their date stamps, trim, save to Photos or share; free, no watermark, no ending clip, clips up to 5 minutes (`Features/Video`, `VideoEngine`, AppCore `SilenceCutter`)
- ✅ Free on-device retro photo effects (VHS '86, Disposable '98, Kira Kira, Digicam '04, Instant '82, Glamour '92, Neon '84, Throwback '16, Camcorder '06, Film Still) with an optional date stamp, border, letterbox or camcorder display; one-tap Auto adjust; RAW photos developed automatically (`AutoDevelop`, AppCore `AutoAdjust`)
- ✅ xAI Grok Imagine as the default AI provider, fal.ai as the alternative; Pro's benefit is now "Our best-quality AI, no watermark"
- ✅ New prices: Pro Yearly $39.99 with a 7-day free trial (≈ $3.33/month), Pro Monthly $5.99 (first month $1.99 if eligible), packs 30 for $2.99 and 100 for $7.99
- ✅ Share formats: Cover star magazine cover (masthead behind the head with Vision person segmentation) and date-stamped Photo strip; Instagram Stories without a Meta App ID; "Glow together" invite card with a QR code
- ✅ Poppins display font; colorful Aura edition of the Glow Print icon; Aura accents for the icon, share cards and sticker-style template art (UI text and controls stay Blush)
- ✅ iOS 26 Liquid Glass tab bar and editor toolbar with a frosted fallback on iOS 17–18; universal iPhone and iPad app
- ✅ First-run guided tour: 7 spotlight steps, shown once after onboarding, replayable from Settings → "Show me around"
- ✅ 12 languages via String Catalogs, a Settings "Language" row, `L10n.core` for AppCore strings and `scripts/export-core-strings.py` (checked in CI); the prompt policy blocks sexual requests in every app language
- ✅ RevenueCat in observer mode for subscription analytics
- ✅ Control Center controls on iOS 18 (Magic Edit, Retro effects, Edit a video), also for the Lock Screen and the Action button; the "My glow" widget's shortcuts are now Magic, Effects and Video
- ✅ Free on-device edits (effects, adjustments, cut-outs) save without a watermark; free cloud AI results keep the small mark
- ⏳ Native-speaker review of the 11 translations
- ✅ App Store screenshots in English and Turkish for iPhone 6.9" and iPad 13" (Magic Edit, trends, effects, Cover star, sharing, gallery, privacy, pricing)
- ⏳ Refresh the README gallery with the new screens (video editor, invite card, tour)


## Phase 7 — Feature audit: safety, honesty and free tools ✅ (14 October 2026)

Seven audits (code, UX and accessibility, platform, competitors, trends, wellbeing and monetization, compliance) became a 66-item backlog; the 26 "implement-now" items shipped in three waves the same day. Research, sources and decisions → [research/2026-10-feature-audit.md](research/2026-10-feature-audit.md)

**Wave 1**
- ✅ Teen-safety prompt policy: reshaping, skin lightening and smoothing, revealing clothing and humiliation blocked in all 12 languages (client and server, shared test vectors); every Magic Edit ends with the edit guard (`people-edit-safety-policy`)
- ✅ Date-windowed seasonal looks (Halloween, winter, Galentine's), the 80s Throwback looks, Plushie Me, Bag Charm Mini and Pet portraits (`seasonal-windows-and-trend-pack`)
- ✅ Throwback '16, Camcorder '06 (photo and video) and Film Still effects (`retro-effects-pack-2`; the Tiny World tilt-shift followed later in October 2026)
- ✅ Honest copy everywhere, checked in CI (`honest-copy-sweep`); truthful Pro credits and packs when Pro runs out (`pro-credits-truth`); release guard and honest demo mode (`release-readiness-guard`); Ask to Buy, load errors and billed terms at the CTA (`store-flows`)
- ✅ On-device writer for Inspire me and Make it magic (`ai-on-device-writer`); Create with Image Playground (`image-playground-free-create`); the develop reveal (`ai-reveal-moment`)
- ✅ Save what the editor shows; Retry free keeps the paid result (`editor-save-correctness`); Crop, rotate, straighten and canvas zoom (`editor-crop-rotate-zoom`)

**Wave 2**
- ✅ AI provenance through re-edits and share paths; no watermark or AI hashtags on on-device edits (`provenance-and-watermark-integrity`)
- ✅ Caption ideas in the share composer (`ai-share-captions`)
- ✅ Which vibe? only between two variations, Best shot without ranks, a Feel good page (`comparison-safe-sharing-and-feel-good`)
- ✅ No account or RevenueCat until a cloud job or purchase; complete deletion (`deferred-identity-and-clean-delete`)
- ✅ Neutral age step with Declared Age Range; on-device only under 13; no automatic paywall under 18; guardian step (`age-assurance-teen-defaults`)
- ✅ Hide faces (`hide-faces`); Cut out with subject picking, backgrounds and stickers (`cutout-backdrops-subject-stickers`)
- ✅ Ideas for this photo and Surprise me in the editor (`ai-smart-suggestions`)

**Wave 3**
- ✅ Video editor: progress and Cancel, background protection, discard prompt, accessible trim (`video-editor-robustness`)
- ✅ Consent, onboarding and pack sheets readable at every text size; equal-weight consent; versioned consent record (`consent-sheet-and-ax-layouts`)
- ✅ First run ends with a real creation before the paywall and tour (`onboarding-first-success`)
- ✅ Notifications outside nights and school hours, no prompts on the Lock Screen, free non-makeup push pool (`notifications-lockscreen-privacy`)
- ✅ ImageIO decoding, memory handling, lock-safe files, SwiftData recovery, offline note, one iPad window (`durability-memory-offline`)
- ✅ VoiceOver, keyboard, Reduce Motion, 44 pt targets, plurals (`a11y-core`)
- ⏳ Translate the ~360 new strings (catalogs synced, other App Store locales follow the en-US text)

**More to play with**
- ✅ Twelve stickers drawn in code (sparkle burst, moon and stars, ribbon bow, crown, daisy, rainbow, cloud, music notes, camera, film strip and the "main character" and "yay" bubbles); the Toy Cam '09 and Rainbow '17 effects, live in Retro Cam, on video, in Shortcuts and in Ideas for this photo; the Candy caption style; all translated into the 11 other app languages
- ✅ A bigger sticker sheet: thirty more stickers, among them (pearls, a gingham bow, a heart locket, a chrome star, a holo heart, a butterfly clip, a flip cell, a CD, strawberry, mushroom, bunny, kitty, teddy bear, a heart cloud, bubble tea, beauty objects such as lip gloss and nail polish, love letters, a rose, the sun, a shooting star, a planet and the "it girl", "vibes" and "core memory" bubbles), the older ones redrawn with gradients, shine and a keyline, and the tray sorted into sections

## Later backlog from the October 2026 audit

🔭 Ranked "later" items from the audit. Backend = needs the live Supabase backend.

| Id | Item | Why | Backend |
|---|---|---|---|
| `retro-camera-photo-booth` | ✅ Shipped in October 2026: Retro Cam with live effects, self-timer and flash + Photo Booth (4-shot countdown, strip and 2×2 four-cut prints) | Strongest teen trend that needs no server (Dazz Cam, 1998 Cam, Huji, Korean four-cut booths); first after this round | No |
| `app-intents-shortcuts` | ✅ Shipped in October 2026: App Intents and App Shortcuts for the free tools (Apply a Retro Effect, Open Retro Cam, Start Photo Booth, Make a Collage, Edit a Photo) in Siri, Spotlight, Shortcuts and the Action button, plus Retro Cam and Photo Booth controls | Surfaces the free tools system-wide; today only the controls use App Intents | No |
| `share-and-photos-extensions` | "Edit in Aybuke" share extension and a Photos editing extension | Meets her where her photos are; needs new targets and a shared image package | No |
| `tipkit-and-short-tour` | Tips for Hold to compare, Retry free and the widget; a 3-step tour instead of 7 (TipKit tips for Retro Cam, collages, Text & Stickers, Surprise me and captions shipped in October 2026) | Hold to compare, Retry free and the widget are hard to discover | No |
| `full-res-export-heic-hdr` | Full-resolution re-render on Save; HEIC; HDR-preserving Adjust | Photos open at 2048 px, so a 48 MP RAW exports at about 3 MP | No |
| `cloud-erase-enhance-compositing` | Composite cloud Erase inside the mask; blend Enhance detail into the original | xAI returns a regenerated 1k frame, so areas outside the brush can change | Yes |
| `cloud-job-resume-and-push` | Resume cloud jobs after suspend or kill; push-updated Live Activity with tap and Cancel | Jobs the server finishes and charges are lost on suspend | Yes |
| `library-bulk-trash` | Stored originals for Before/After, editor drafts (multi-select and the 30-day Recently deleted shipped in October 2026) | Paid results aren't auto-saved, and Before/After needs the original | No |
| `create-results-polish` | Localized prompt enhancement (Save all, Regenerate, recent prompts and drafts shipped in October 2026) | Enhance prompt adds English cues | No |
| `collage-carousel-scrapbook` | Photocard, Fit Check and movie poster formats (the photo dump and seamless carousel maker with grid, mosaic, film strip, instant print, scrapbook and moodboard layouts shipped in October 2026) | SCRL is #11 in Photo & Video; every rival has collages | No |
| `text-stickers-doodles` | ✅ Shipped in October 2026: Text & Stickers in the photo editor (text, bundled stickers, pasted cut-outs and PencilKit doodles) | Every mass-market rival has an overlay layer | No |
| `batch-and-recipes` | Batch effects, Auto and cut-out; shareable recipes | VSCO, EPIK, Hypic and Photoroom batch-edit | No |
| `on-device-upscale-and-eraser` | On-device HD upscale (Real-ESRGAN) and LaMa eraser with tap-to-select | Free and private Enhance and Erase; large models need on-demand download | No |
| `widgets-interactive-accented` | Interactive and configurable widgets; iOS 26 accented and clear rendering | Widgets are static; the photo vanishes in accented mode | No |
| `spotlight-focus-album` | Spotlight indexing, a Focus filter, an optional Aybuke album | System integration for discovery and privacy | No |
| `live-photo-and-video-captions` | Live Photo effects, 9:16 reframe, speed, mute, Hide faces for video (✅ on-device automatic captions shipped: Pop, Bubble, Candy, Karaoke and Typewriter, burned into the export) | Video gaps against Edits, Wink and Meitu; captions were already planned | No |
| `universal-links-try-this-look` | Universal links, a "Try this look" card with QR, in-app events | "Add Yours" chains spread the 80s trend; needs a live domain | No |
| `store-retention-pricing-ops` | Win-back offers, Retention Messaging, regional prices, billing-issue banner | Mostly App Store Connect setup once the app record exists | No |
| `trial-credit-cap-family-sharing` | Cap credits during the trial; Family Sharing with a smaller allowance | A trial grants 20 credits in the category with the highest refund rate | Yes |
| `funnel-measurement` | Private funnel measurement: paywall source, peer benchmarks, anonymous counters | The spec's KPIs can't be measured today | Yes |
| `server-moderation-stack` | Fail-closed output moderation, input nudity screening, multilingual classifier | ✅ Shipped (15 October 2026) with Claude as the independent check of the photo and every result, instead of fal.ai; left: confirm it on the live API | Yes |
| `abuse-ops-reports-bans` | Ban list, reviewable reports, CSAM/NCII runbook with legal hold, App Attest, App Store Server Notifications, PermissionKit | Apple 1.2 and Texas consent revocation; reports have no image today | Yes |
| `c2pa-trustmark` | Signed C2PA manifests, imperceptible watermark, a free verify page | The EU Code of Practice expects signed metadata plus a watermark | Yes |
| `storefront-compliance` | India and Korea visible labels, Brazil ECA Digital, Russia decision, DPIA, red-team safety case, BIPA review | Legal decisions that need counsel and the owner | No |
| `subject-consent-step` | Per-photo "It's me / someone else, they said yes" for cloud edits | A single classmate's photo gets no prompt today | Yes |
| `backend-ai-looks` | Remote catalog with kill switch, Hair studio, Outfit vibes, two-photo looks, Chibi stickers, photoshoot packs, Collector Card, Main Character poster, Retro Cinema, Pinterest 2026 pack, Squad sets, photo-to-video presets | High trend value; needs the backend and some wire-format changes | Yes |
| `ipad-scene-model` | Per-window SceneModel for iPad multi-window | Multi-window is off until UI state is per scene | No |
| `a11y-dynamic-type-labels` | Dynamic Type containers, Large Content Viewer, haptics, review-prompt timing, Accessibility Nutrition Labels | Polish after the core accessibility work | No |
| `weekly-theme-and-recaps` | Private weekly theme, opt-in Sunday recap, monthly recap card | A healthier recurring hook than streaks | No |
| `app-clip-invite` | App Clip for invites: one free effect without installing | Growth lever; needs a live domain and a 15 MB budget | No |
| `promo-offers-signed` | Server-signed promotional offers | Low value now; needs a signing key | Yes |
| `translation-policy-precheck` | Translate prompts in other languages before the client policy check | Low value; server moderation is the real gate | No |

Rejected in the audit (never build): celebrity likeness, beauty retouch and reshaping, feeds, likes and streaks, ratings of people, open virtual try-on and AI dance, pet-to-human and future-baby looks, dark-pattern monetization, and unsafe platform shortcuts. Reasons → [the research doc](research/2026-10-feature-audit.md#9-rejected).
