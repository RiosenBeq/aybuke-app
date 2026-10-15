# Handoff prompt: finish and ship Aybuke 1.0

Paste everything below the line into a new Claude Code session. It covers all
remaining work as of 14 October 2026. Some steps need a Mac with Xcode
(builds, screenshots, uploads) or the owner's logged-in browser (Supabase,
AdMob, App Store Connect UI); a cloud session should do the rest and leave
those steps clearly listed for a Mac session.

---

You are finishing **Aybuke** (code name Aybuke), an iPhone/iPad/Mac (Mac Catalyst) AI photo editor for girls and young women 13+, and shipping version 1.0 to the App Store. Repo: `RiosenBeq/aybuke-app`, branch `pink-girls-redesign` (PR #1 into `main`). Read `AGENTS.md` first and follow its rules, plus these:

- Never print, commit or paste secrets or API keys. Never use a key pasted into chat; secrets go into the service's own secret store, set by the owner.
- Don't commit `.claude/`. Every commit message: imperative summary, short body, and the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Push after every finished step, so nothing is lost if the session ends.
- Copy must match the code (`scripts/check-honest-copy.py`). Owner's rule: no decorative full stop at the end of a headline, title or tagline in any language; a two-part headline takes a comma ("Say the change, watch it glow"); body sentences keep their periods.
- 12 app languages (en, tr, es, pt-BR, fr, de, it, ru, ja, ko, zh-Hans, id); 13 App Store locales (es-ES and es-MX). Translate new strings yourself, short and natural, same placeholders.
- The owner writes Turkish; answer in Turkish. Do everything you can yourself; hand back only what really needs the owner (payments, private keys, identity checks).
- **Never press "Submit for Review" without asking the owner "Her şey hazır. Gönderelim mi?" with a short summary, and waiting for a clear yes.**

## Where things stand

Done and pushed on `pink-girls-redesign`:

- The app: Magic Edit, Makeup Studio, 50+ looks, Create, effects, Retro Cam, collage, video captions, Text & Stickers, My Works, widgets, Siri, 12 languages, iPad and Mac builds.
- App Review fixes: fail-closed output safety check, refunds for undelivered results, honest balances, Sign in with Apple hidden in this version (`signInWithApple: false`).
- Rewarded and interstitial AdMob ads for free members 13+ on iPhone and iPad. Never for Pro, under 13, the Mac or preview builds; non-personalised; teens get child-directed G-rated ads. Google Mobile Ads 13.11.0 and UMP 3.1.0 are pinned.
- The App Store screenshot design (`scripts/marketing-images.py`, captions in `docs/marketing/screenshot-captions.json`) and AI-made sample photos for captures (`docs/marketing/samples/`, see its README).
- The legal texts name **Okan Berk Manavoğlu (individual developer)** as operator and controller, because the Apple Developer account is an individual one in his name. Contact: hello@buaze.com. `build-legal.py` hides lines whose value is empty (no KEP address).
- A daily keep-alive (`.github/workflows/keepalive.yml` + migration `20261019500000_keepalive.sql`). It keeps the Free Supabase project from pausing. The owner does not want a paid Supabase plan; the job runs only once it's on `main`.
- Helper scripts: `scripts/asc/` (App Store Connect API, see its README) and `scripts/tools/`:
  - `rename-brand.py`: Aybuke → Aybuke.
  - `merge_xcstrings.py`: a git merge driver for String Catalogs; enable it as its README says.
  - `merge_json_words.py`: resolves conflicted JSON.

Live backend (Supabase project `efapupjvidyqhqdevmcu`, Frankfurt, Free plan):

- **Applied migrations:** `20261011…` through `20261018…`, plus `20261019500000_keepalive`.
- **Deployed functions:** `ai-image`, `account`, `credits-redeem` and `report` (from commit 47b5c6f).
- **Auth:** anonymous sign-ins are limited to 15 an hour per IP; the Email provider is off; Apple and anonymous sign-in stay on.
- **Secrets set:** `XAI_API_KEY`, `APPLE_APP_ID`, `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID`, and since 15 October `ANTHROPIC_API_KEY` (the Claude safety check, `docs/AI-TODO.md` §1.5).
- **Not deployed yet:** migration `20261019000000_ad_rewards.sql`, the security/credits migrations, and the `ad-reward` function.
- **The project isn't `supabase link`ed:** migrations go through the dashboard SQL Editor (wrap each in `begin; … commit;`), and functions through `supabase functions deploy <name> --project-ref efapupjvidyqhqdevmcu --use-api`.

**xAI:** the team's credits or monthly spending limit ran out. The owner said he will top it up. Until then every AI job fails, and the failure is refunded.

App Store Connect, already done:

- **The record:**
  - App id `6822716008`, name "Aybuke: AI Photo Editor", bundle id `app.glowlit.ios`, team `CBTKNY3LFC`.
  - iOS 1.0 version id `f3e190c1-151c-4828-a349-b2c348d4ec20`, macOS 1.0 version id `62d912cf-8fd9-4165-a5ea-03529fd63aba`, appInfo id `8ac32843-da8f-4dc6-9e9f-f2eb04392678`.
- **Purchases:**
  - Subscription group `22475412` "Aybuke Pro": Yearly `6822722945` ($39.99, 7-day free trial), Monthly `6822727359` ($5.99, first month $1.99). The descriptions say "80 credits a month" in 13 locales.
  - Packs `6822730949` (30 credits, $2.99) and `6822730794` (100 credits, $7.99), both READY_TO_SUBMIT.
  - The subscriptions show MISSING_METADATA, which is normal for a first subscription. They must be added to the 1.0 version on its page, under "In-App Purchases and Subscriptions".
- **Other settings:**
  - Age rating: 13+ override, `advertising: true`, `ageAssurance: true`.
  - Content rights: no third-party content. Copyright: "2026 Okan Berk Manavoğlu". Release type: AFTER_APPROVAL. Price: free. Available in 174 regions (mainland China excluded).
  - Paid Apps Agreement active. Review contact filled.
- **URLs:** privacy, support and marketing URLs currently point to `https://riosenbeq.github.io/aybuke-app/…`. Move them to aybuke.org, see step 6.
- **Still missing:** no build uploaded, no final screenshots.

Other services:

- **AdMob:**
  - App `ca-app-pub-2292230772061554~5236020895`, rewarded unit `…/1406702504` ("Out of credits reward").
  - The interstitial unit exists since 15 October 2026: "After save interstitial" `ca-app-pub-2292230772061554/6797438012`, capped at 3 a day, in `ads.interstitialUnitID` (`ios/App/Resources/AppConfig.json`).
  - The AdSense payment account shows "action required"; that's the owner's step.
- **RevenueCat:** project `3e7e4f4a`, observer mode only, `pro` entitlement, `default` offering. Nothing is required for release.
- **Website:**
  - aybuke.org is a separate repo, `RiosenBeq/aybuke` (static site; `python3 scripts/build.py`, and `--check`; Vercel deploys `main` to production). Read its README.
  - Branch `ads-and-credits` has the new credit and ads copy in 12 languages, `public/app-ads.txt`, local prices restored, and the Sign in with Apple claims removed. Not merged.

## Unfinished branches to complete and merge (in this order)

1. **`worktree-agent-a6acce03ae5d2fa55`: credits retune and abuse protection.**
   - It contains WIP commits `0199319` (backend), a merge of `pink-girls-redesign` and `17e538d` (WIP, may not build).
   - Finish it to this spec, then merge it into `pink-girls-redesign` with `--no-ff`.
   - **Economics (server-authoritative, numbers in SQL `credit_policy()`):**
     - Free: 2 credits a day.
     - Pro: 80 a month, rollover cap 160.
     - The 7-day trial grants 20 credits; detect it from Apple's signed transaction (`offerType` / `offerDiscountType` FREE_TRIAL) and store it on the entitlement. The full 80 starts with the first paid period; the $1.99 intro month gets 80.
     - At most 3 free Likeness Lock retries per user per day.
     - Packs unchanged.
     - **Rewarded ads: 2 a day.** Change `ad_reward_policy()` in `20261019000000_ad_rewards.sql` (not live yet, so editing it is fine), the `?? 3` in `functions/ad-reward/index.ts`, `ads.dailyCap` in AppConfig.json, the defaults in `AppConfig.swift`, AppCore `AdRewardPolicy` and its tests, parts 4 and 5 of `ad_rewards_test.sql`, and every legal, web and docs sentence about it. Interstitial pacing stays at 3 a day.
     - The server returns its policy numbers with the balance; the app caches them, with defaults in AppConfig.json, and uses plural-aware strings.
     - The paywall states the trial credits, and the billed price stays the most prominent price.
     - Update every place that states numbers: app strings, App Store metadata (13 locales, mind the limits), `web/`, `legal/` (they may avoid exact numbers), `ios/StoreKit/Products.storekit`, docs (`docs/03-product-spec.md` §5 unit economics).
   - **Abuse protection:**
     - **(a) Free credits bound to a genuine App Store install.** The app sends `AppTransaction.shared.jwsRepresentation`.
       - The server verifies the chain against Apple Root CA G3, bundle `app.glowlit.ios`, and the environment. Accept Production and Sandbox (TestFlight and App Review use Sandbox); reject Xcode except on a dev backend.
       - Key the free daily allowance and the ad-credit cap by a salted hash of `appTransactionId`. The salt lives in a non-exposed table, so no new owner secret.
       - Privacy policies (EN, TR, KVKK) say what is kept and for how long, also after Delete my data.
       - A fresh reviewer install must get free credits on the first try.
     - **(b) SQL circuit breakers:** a daily cap on free jobs (about 1500) and a hard cap on all jobs (about 8000), retunable. When one is hit, show a friendly translated message; nothing is charged.
     - **(c) Rate limits:** keep 6 a minute free and 20 Pro; add hourly and daily per-user caps, a per-IP cap and a report limit.
     - **(d) Strikes:** server-side policy blocks count per user and per install. 3 in 24 hours means a 24-hour cool-down; repeated cool-downs block the install until the owner lifts it. Messages are kind to teens and translated. Add service-role SQL tools for the owner and an "Abuse runbook" in `backend/README.md`.
     - **(e) Input hardening:**
       - A decoded-size cap on images, a magic-byte check and maximum dimensions.
       - A prompt length cap.
       - NFKC normalization, then stripping zero-width, control and bidi characters, then leetspeak and separator folding. Do this in both `policy.ts` and `ContentPolicy.swift`, with vectors in `_shared/policy-vectors.json`, including false-positive guards ("slim gold necklace", "Sussex", "class", "assistant"). Then run `scripts/export-catalog.sh`.
     - **(f) Optional xAI vision safety check** behind `XAI_SAFETY_MODEL`: off unless set, fail-closed when on.
     - **(g) Keep `public.keepalive()` executable by anon.**
     - **(h) The client** handles the new errors: cool-down, paused, rate-limited, install blocked.
   - **New migrations:** timestamps from `20261020000000`.
   - **Before merging:** run the SQL tests (`backend/scripts/test-db.sh`), the Deno checks and AppCore tests, and confirm the app builds.
2. **`worktree-agent-a9b1c4b8c9e51e4d3`: Mac app made native.** WIP `e30a814`, based on 47b5c6f, may not build; merge `pink-girls-redesign` into it first.
   - **Goal:**
     - A sidebar (Explore, Create, Edit, My Works, a Tools group, Settings and credits), plus View › Show/Hide Sidebar ⌃⌘S, keeping ⌘1–⌘4.
     - Content that uses the window: a max of about 1200–1280 pt with 28–40 pt gutters, adaptive grids instead of clipped carousels, and two-column Create.
     - The editor's tools in a right-hand inspector on wide windows.
     - `.help()` tooltips, hover effects, right-click menus, the Delete key in My Works select mode, and "Click" wording on the Mac.
     - Complete menus.
     - Legible type at the 77% scaling.
     - Every template card draws: the "80s Studio Portrait" card rendered blank on the Mac.
   - **Constraints:** iPhone must not change; no ads on the Mac; full-window covers still hide navigation.
   - **Checks (needs a Mac):** build ad hoc and capture at 900×640, 1600×1000 and about 2200×1400 UIKit points (AGENTS.md §3).
3. **Website `RiosenBeq/aybuke`, branch `ads-and-credits`:** WIP `6469b5b` (operator as the individual developer, "one purchase covers iPhone, iPad and Mac" true for Pro only). Finish it:
   - **`legal/config.json`:** the same operator values as the app's `legal/config.json`, with `HOSTING_REGION` "EU (Frankfurt)" / "AB (Frankfurt)".
   - **Remove company details:** no NextGen, MERSİS, tax number or street address anywhere; the JSON-LD publisher is a Person.
   - **Sync the legal texts:** copy `legal/en/*.md` and `legal/tr/*.md` from the app repo after steps 1 and 4.
   - **Build, `--check`, merge to `main`:** Vercel deploys production.
   - **Afterwards:** check `https://aybuke.org/app-ads.txt` returns the AdMob line, resubmit the sitemap in Search Console and ping IndexNow (key file in `public/`).

## Remaining steps after the merges

4. **Rename Aybuke → Aybuke** everywhere users see it: `python3 scripts/tools/rename-brand.py . --write`. It keeps bundle ids, the App Group, `glowlit://`, type names, and the Xcode project and scheme.
   - **Then:** `python3 scripts/export-core-strings.py`, `python3 scripts/build-legal.py`, `scripts/export-catalog.sh` if policy reason texts change.
   - **Also update:** the share hashtags, the website `<title>`, AdMob's app name (owner's browser), and the RevenueCat display names (optional).
   - **Check:** review the diff, and grep the remaining "Aybuke" for anything user-facing.
5. **Full verification:**
   - `swift test --package-path ios/Packages/AppCore`.
   - The Deno checks for every function, including `ad-reward`, then `deno test _shared/`.
   - `backend/scripts/test-db.sh`.
   - `build-legal.py --check`, `export-core-strings.py --check`, `check-honest-copy.py`, `check-release-config.py --report`.
   - **On a Mac:** Debug simulator, Release `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO`, and Mac Catalyst. Fix every error and new warning.
   - **Large-text survey:** EN/DE/RU at the largest accessibility sizes on iPhone 17e.
   - Push, get CI green, then merge PR #1 into `main` (this also starts the keep-alive schedule).
6. **Backend deploy** (the owner approved deploying all migrations and functions):
   - Apply `20261019000000_ad_rewards.sql` and the new security migrations in the SQL Editor, in order, each in one transaction.
   - Deploy `ai-image`, `account`, `credits-redeem`, `report`, and `ad-reward` with `--no-verify-jwt`.
   - Set the secret `ADMOB_REWARDED_AD_UNIT=ca-app-pub-2292230772061554/1406702504`.
   - Schedule `select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()')`.
   - Smoke-test with a throwaway anonymous user (sign up with the public anon key, `GET /functions/v1/ai-image` for the balance, `DELETE /functions/v1/account`), and check the Security Advisor.
7. **AdMob** (owner's browser; ask the owner to approve each change by name if a safety check blocks it):
   - Done on 15 October 2026: the interstitial unit "After save interstitial" (frequency cap 3 a day per user) is created and its id is in `ads.interstitialUnitID`.
   - On the rewarded unit, set server-side verification to `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` and press Verify URL.
   - Block sensitive ad categories.
   - Set up a GDPR message for the EEA, UK and CH.
   - In App Store Connect, set the Marketing URL to `https://aybuke.org` and the Support URL to `https://aybuke.org/support`. The privacy URLs become `https://aybuke.org/legal/en/privacy-policy` and `/legal/tr/gizlilik-politikasi`, once those pages carry the synced texts.
8. **Screenshots (Mac only):**
   - **Devices:** iPhone 17 Pro Max (`50703265-82EF-4CFE-B094-47FFB43025B0`), iPad Pro 13-inch M5 (`0ADBB7F6-481C-4F00-AFD0-182E32E685E2`), and the Mac window (`-GLWindowSize 1600x1000`, `screencapture -l <CGWindowID>`), in 12 languages.
   - **Launch with:** `-GLSamplePhotos docs/marketing/samples`. Sandboxed: copy the samples into the app container on the Mac.
   - **Scene names:** see the header of `scripts/marketing-images.py` (e.g. `makeup.png` from `editor -GLEditorTool makeup -GLMakeupPreset softGlam`, `share-cover.png` from `share -GLShareFormat cover`).
   - **Render:** `python3 scripts/marketing-images.py <captures>`, which writes `docs/marketing/app-store/<lang>/` (iPhone 1290×2796, `ipad/` 2064×2752, `mac/` 2880×1800).
   - **Check:** look at every image; no image may state credit numbers.
9. **Upload builds (Mac):**
   - `ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> scripts/upload-app-store.sh`, then again with `PLATFORM=mac`. The API key is in `~/.appstoreconnect/private_keys/` on the owner's Mac; never commit it.
   - Free about 2 GB of disk per archive first; the disk is nearly full.
   - Wait for processing.
10. **App Store Connect:**
    - Attach both builds.
    - Upload the screenshots: `cd scripts/asc && python3 asc_screenshots.py ../..`.
    - Push the metadata: `python3 asc_metadata.py ../..`. Keep the Mac description free of iPhone-only features.
    - Fill in App Privacy, in the UI:
      - The existing app data.
      - Advertising Data: linked, App Functionality plus Third-Party Advertising plus Analytics.
      - Coarse Location, Device ID, Product Interaction and Performance Data: not linked, Third-Party Advertising and Analytics.
      - The install-key hash: App Functionality / fraud prevention.
      - No tracking.
      - Check against Xcode's privacy report.
    - Update the App Review notes in `docs/marketing/app-store-listing.md` and in App Store Connect. They must cover:
      - the Aybuke name;
      - no login, an anonymous account at the first cloud job;
      - consent first, naming Supabase, xAI and Anthropic;
      - Makeup Studio;
      - ads: free members 13+ only, the optional rewarded ad and occasional interstitials, non-personalised, none for Pro, under 13 or the Mac;
      - free credits tied to the App Store install (Sandbox accepted);
      - Sign in with Apple hidden;
      - the purchases and the sandbox note;
      - the safety layers (including the independent Claude check of the photo and every result) and reporting;
      - Delete my data;
      - Mac differences (no Live Activity, no Instagram Stories).
    - Add both subscriptions and both packs to the 1.0 version.
    - Then ask the owner "Her şey hazır. Gönderelim mi?" with a short summary, and submit only on a clear yes, for iOS and macOS.
11. **Docs:**
    - Update AGENTS.md (§1, §4, §6), `docs/NEXT-STEPS.md`, `docs/SUPABASE-TODO.md`, `docs/RELEASE-CHECKLIST.md` and the backend README.
    - Write `docs/AI-TODO.md`: the ordered work for future AI sessions, from `docs/06-roadmap.md`, open follow-ups and known risks.
    - Write `docs/SAHIP-YAPILACAKLAR.md`, in Turkish: the owner-only list.
    - Finish with a Turkish report to the owner.

## Owner-only items (list them; don't do them)
- Top up the xAI credits or raise the monthly limit. Rotate the xAI key that was once pasted into chat, then update `XAI_API_KEY` in Supabase if it's the same key.
- Resolve the AdSense payment-account "action required" (identity, address, tax).
- Optional, later:
  - A Sign in with Apple key (`APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY`) to turn sign-in on.
  - A RevenueCat v2 secret key (`REVENUECAT_SECRET_KEY`, plus `REVENUECAT_PROJECT_ID=3e7e4f4a`) so account deletion also clears RevenueCat right away. Until then the deletions wait in a queue.
- Legal:
  - A KVKK written-application postal address, if counsel wants one. His home address is shown on EU storefronts anyway because of the DSA; don't publish it without his say-so.
  - A lawyer's review of the legal texts.
  - The KVKK basis for transfers abroad to Google, and other processors.
- A device sandbox test of purchases, Ask to Buy and a rewarded ad on a registered AdMob test device (`docs/RELEASE-CHECKLIST.md`).
