# AI-TODO: ordered work for future AI sessions

Status as of 14 October 2026. Start with [`AGENTS.md`](../AGENTS.md) (section 6) and [`NEXT-STEPS.md`](NEXT-STEPS.md). The order inside each section is the order to work in. Items come from [`06-roadmap.md`](06-roadmap.md) (only the items still open, kept in the roadmap's order), the open follow-ups, and the known risks in section 5. The owner's list is in [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md), which may not exist yet.

Rules for every item: read the code before you change a claim; grep each number you write; do not edit an applied migration (add a new file with a later timestamp); never commit or print a key; do not commit `.claude/`.

## 1. Before launch (agent-doable, no Mac needed)

1. **Re-run every check on the current head** (`NEXT-STEPS.md`, section 4). Reconcile the AppCore count: `func test` declarations number 319, and the last reported run passed 315 (before the rename).
   *Settles:* the run is green and the counts match.
   **Done (14 October 2026):** every check passes on the current head; AppCore runs all 319 tests on Linux.
2. **Fix stale backend text:** `backend/README.md` "Reports" says 20 a day, while `credit_policy()` (`reports_per_day` = 10, migration `20261020000000`) and the runbook say 10.
   *Settles:* `grep -rn "20 reports" backend docs` finds nothing.
   **Done (14 October 2026):** `backend/README.md` says 10 reports a day, like `reports_per_day`.
3. **Point the app at aybuke.org:** `ios/App/Resources/AppConfig.json` (`websiteURL`, `privacyPolicyURL`, `termsURL`) still uses `riosenbeq.github.io`. The release check requests the `.html` form (`/legal/en/privacy-policy.html`). Confirm which form the live site serves, and make the values match.
   *Settles:* `python3 scripts/check-release-config.py --online` passes against the live site.
   **Done (14 October 2026):** `AppConfig.json` uses `https://aybuke.org`, `/legal/en/privacy-policy` and `/legal/en/terms-of-use`. The `--online` run still needs a machine that can reach the site.
4. **One website source:** this repository's `web/` and `.github/workflows/website.yml` (GitHub Pages) duplicate the Vercel repository `RiosenBeq/aybuke`.
   *Settles:* `web/README.md` names the single source, and the other copy is retired or synced by a workflow.
   **Done (14 October 2026):** `web/README.md` names `RiosenBeq/aybuke` (Vercel, aybuke.org) as the live site and this folder as a GitHub Pages fallback.
5. **Independent output check, drafted but not enabled** (roadmap `server-moderation-stack`, "must ship before launch"). The fail-closed check exists (`_shared/moderation.ts`, `checkOutputs`). What is missing is the consent path: fal.ai must be in `aiProcessors` (`AppConfig.json`) in an app release, and in the privacy policies (`legal/`, then `scripts/build-legal.py`), before `FAL_KEY` is set. Draft both changes for review.
   *Settles:* `moderation_test.ts` covers the fal path, and the legal texts build and check.
6. **App Store Server Notifications V2 endpoint** (roadmap `abuse-ops-reports-bans`, launch blocker). A refunded or revoked Pro subscription keeps Pro until `expires_at` (`public.record_entitlement`, migration `20261024000002`). Add a route that verifies the signed notification with Apple's library and marks the entitlement revoked. The owner then sets the URL in App Store Connect.
   *Settles:* a test covers a refund and a revocation, and `deno test _shared/ ad-reward/` passes.
   **Done (14 October 2026):** `functions/app-store-notifications` with migrations `20261025000000` (revoke, restore, pack take-back), `20261025000002` (a refund that arrives before the purchase is redeemed is remembered, so the purchase is refused later) and `20261025000003` (prune without deadlocks). Left for the owner: deploy, the cron job `sweep-app-store-notifications`, and the URL in App Store Connect. Follow-ups: `resolveEntitlement` in `_shared/apple.ts` still computes Pro from the JWS when `record_entitlement` fails (treat a save error as no Pro); a pack refunded, reversed and refunded again takes nothing back the second time (`refund_pack` is once per transaction); the website's support and pricing FAQ could add one line on refunds.
7. **Number drift check:** `CreditPolicy.standard` (AppCore), `creditPolicy` in `ios/App/Resources/AppConfig.json` and the values in `public.credit_policy()` must agree (2, 80, 160, 20, 3). Add a small script under `scripts/` that reads the three places and fails on a mismatch, then run it in CI.
   *Settles:* the script passes on the current values and fails when one value is changed.
   **Done (14 October 2026):** `scripts/check-credit-policy.py` compares `credit_policy()`, `ad_reward_policy()`, `AppConfig.json` and AppCore, and runs in CI.
8. **SQL gaps** (each in a new migration with a test in `backend/supabase/tests`):
   - Likeness retries: refunded and timed-out retries count against the daily 3 (`admit_job`, `free_retries_daily`).
   - `public.flag_job` may count a strike for a job the user cancelled.
   - The balance endpoint (`ai-image/index.ts`) does not pass the client address, so address cool-downs do not show in the balance (owner decision 6).
   *Settles:* `backend/scripts/test-db.sh` passes with a new test for each.
   **Done (14 October 2026):** migration `20261025000001_sql_gaps.sql`: refunded, failed and cancelled retries give their daily slot back; `flag_job` adds no strike for a cancelled job; `wallet_state` takes the client address (a 5-argument form, the old form kept), and `GET /ai-image` passes it. New cases in `abuse_test.sql` (19–21) and `credits_test.sql` (13); `test-db.sh` passes.
9. **Swift tests must not skip silently.** Tests skip with `XCTSkip` when `policy-vectors.json` is not found.
   *Settles:* `swift test --package-path ios/Packages/AppCore` reports zero skips on CI.
   **Done (14 October 2026):** `RepositoryFile` (AppCore tests) fails a missing shared file when `CI` is set and skips only locally; every former `XCTSkip` goes through it. 323 tests, 0 skipped with `CI=true`.
10. **Policy vectors:** a Greek final sigma (Swift and JavaScript lowercase it differently) and a CJK line break that can join two words into a blocked term (`ContentPolicy.swift` and `policy.ts`).
    *Settles:* both are in `_shared/policy-vectors.json`, `scripts/export-catalog.sh` has been run, and `swift test` and `deno test _shared/` pass.
   **Done (14 October 2026):** both sides fold ς to σ, and a control character next to a CJK character splits words like a space (so '女性\n感谢你' passes; a CJK term broken by a line break passes too, as it already did with a space). New verdict vectors and a shared `words` section in `policy-vectors.json`; `deno test _shared/` and `swift test` pass.
11. **Photo-check failure copy:** the likeness-check failure text says the result was not shown, which reads oddly for a photo check.
    *Settles:* the copy is reworded in every catalogue, and `TranslationTests` passes.
    **Done (14 October 2026):** the server fails the photo check with `photo_check_failed`, and the app says the photo couldn't be checked and no credit was used (12 languages); `BackendAPITests` checks every failure code has its own translated sentence.
12. **Translate the ~360 strings** added on 14 October 2026 (roadmap Phase 7, open). Catalogues are synced; the App Store locales follow the en-US text.
    *Settles:* `TranslationTests` and the catalogue checks pass for all eleven languages.
   **Done (14 October 2026):** every key in `Localizable.xcstrings` has all eleven translations except two format-only keys. A native speaker review is still open (section 3).
13. **Recapture the App Store metadata for other locales** (roadmap Phase 4, open): only `en/` and `tr/` exist under `docs/marketing/app-store/`.
    *Settles:* the paths listed in `marketing/app-store-connect-setup.md` section 5 exist for the agreed locales, or the owner has dropped them.

## 2. Needs a Mac (Xcode, a Mac, or a device)

1. **Build and run:** iOS Release (`generic/platform=iOS`), Mac Catalyst (`generic/platform=macOS,variant=Mac Catalyst`), and the simulator build (see `AGENTS.md`, section 3). No new warnings.
2. **Export-catalog Swift side:** `scripts/export-catalog.sh` was made atomic, but its Swift side has not been checked on a Mac.
3. **Mac type residuals:** about 92 chained caption and footnote font calls keep SwiftUI's Mac size, and 12 hard-coded literal sizes do not scale. The Typography Mac helpers apply only to the exact `.font(.caption)` forms.
   *Settles:* the Mac screenshots at 960×660 and 1600×1000 show the same type scale as iPhone.
4. **Mac ⌘W in the editor and Retro Cam:** neither registers a close handler (`AppModel.closeActiveCover` is set only by the collage and the video editor), so ⌘W does nothing there.
   *Settles:* ⌘W closes or saves-then-closes in both, or the menu item is disabled there.
5. **Mac context menus:** the See-all page and the editor's Styles panel have no template context menu (`Try this look`).
   *Settles:* both show the menu on right-click, with the same entries as elsewhere.
6. **Cover-aware toolbar hiding:** `hidesMacToolbar(covered)` (`MacSupport.swift`) is not proven inside every section stack (`MacShell.swift`, `MacSections`).
   *Settles:* each cover on each section hides the toolbar, and the toolbar returns after the cover closes.
7. **App Attest and DeviceCheck** (roadmap `abuse-ops-reports-bans`, Hardening). App Attest binds free credits to a real device, beyond the App Store install key, so it needs a device to test.
   *Settles:* a device build sends an attestation that the server verifies, and a reinstall or a script cannot farm free credits.
8. **Credits sheet shows the owner pause:** `CreditsSheet` cannot show an owner pause yet (`ai-image` balance reports `ai_status`).
   *Settles:* a paused account sees the pause message and no paywall.
9. **Build with the latest SDK** (roadmap Phase 4, open): iOS 26/27 SDK, and an Icon Composer `.icon` with clear variants.
   *Settles:* the build is green on the new SDK, and the icon shows the dark and tinted variants.
10. **Recapture the screenshots with real AI results** (roadmap Phase 4, open): needs an AI key and a device. Include the new effects and Cover star scenes in `screenshot-captions.json`. Mac captures at 960×660 (the current minimum; not 900×640), 1600×1000 and 2200×1400.
    *Settles:* `scripts/marketing-images.py` output for each language and device size, with no stale file.
11. **Large-text survey** (accessibility): Dynamic Type at the largest size on onboarding, the paywall, the consent sheet and the editor toolbar.
    *Settles:* no clipped or shifted button, recorded in a screenshot set.
12. **Real speech recognition for captions:** the simulator has no speech models. Check the Mac build (`-GLVideoSpeech YES`).
    *Settles:* captions match the speech in `video -GLVideoSpeech YES` on the Mac.
13. **Performance check:** `-GLPerfBench <photo>` and `-GLPerfOpen <photo>` (`PerfProbe`) after any change to decoding or rendering.
    *Settles:* the numbers in `docs/04-architecture.md` (Performance) are not worse.

## 3. Needs the owner

Each decision below is an owner call. The agent prepares the facts and the code, then waits.

1. **Trial roll-in:** unused trial credits (20) add to the first paid month (80), capped at 160 (`private.refresh_subscription`). Confirm, or make the trial credits expire.
2. **Refunds and revocations:** keep Pro until `expires_at` until the notifications endpoint (section 1, item 6) exists, or stop Pro on the refund signal. Recommended before launch: the endpoint.
3. **Shared addresses:** three strikes from one address without a verified install cool down every user on that address. Set a higher threshold for address keys, or accept the risk for schools and carriers (`private.add_strike`).
4. **xAI Zero Data Retention:** the privacy texts say it is on, but the repository cannot prove it. Confirm it in the xAI console.
5. **Company registry line:** `legal/config.json` says "None (individual developer)" for `COMPANY_REGISTRY`. Keep it, or change it, and rebuild the legal pages.
6. **Balance endpoint and address cool-downs:** the owner needs address-level cool-downs in the balance (section 1, item 8). Confirm the change is wanted.
7. **FAL_KEY and XAI_SAFETY_MODEL:** whether to turn on the independent output check (section 1, item 5), and whether to test `XAI_SAFETY_MODEL` against the live API. Both are off by default.
8. **Email Address in App Privacy:** `PrivacyInfo.xcprivacy` lists it, and the setup doc says it can stay undeclared while sign-in is off. Decide, and make the two agree.
9. **App Store Connect and launch:** builds, screenshots, the Paid Apps Agreement, the subscriptions and packs attached to the version, the review phone number, and the final submit decision (`NEXT-STEPS.md`, section 3).
10. **Legal and brand:** lawyer review; the trademark search for "Aybuke" (roadmap Phase 4, open); the domain (`glowlit.app` is in the roadmap, but the brand is now Aybuke and the site is aybuke.org).
11. **Native-speaker review** of the translations (roadmap Phase 6, open).

## 4. After launch (roadmap, Phase 5 and later)

These follow the roadmap's order. Items marked "backend" need the live backend.

1. Likeness Lock v2: 3–5 selfie profile with an identity-similarity check before results show (roadmap Phase 5). It is a product decision first; the owner agrees the scope before any design note.
2. Packs: Headshot pack (20 photos), Restore pack, seasonal trend packs.
3. Motion: short video versions of templates (figurine → spin, polaroid → develop).
4. Remote template catalogue with thumbnails, a kill switch, A/B tests and a "Trending this week" feed (backlog `backend-ai-looks`; backend).
5. C2PA Content Credentials, server-signed, and an imperceptible watermark, with a free verify page (backlog `c2pa-trustmark`; backend).
6. Webhooks or Realtime push instead of polling; push-updated Live Activities (backend).
7. Interactive widgets, iOS 17+ (backlog `widgets-interactive-accented`).
8. Steal the look (reference photo) with Likeness Lock; one look across a whole photo dump; alternate app icons.
9. Optional iCloud sync of My Works (the user's own iCloud, never our servers).
10. iPhone Duo adaptive layouts.
11. Swift 6 strict concurrency; UI tests; snapshot tests.
12. Privacy-friendly product analytics, paywall experiments, Apple Ads.
13. Optional Meta App ID for direct Instagram Stories sharing (`instagramAppID`); Stories already works through the share sheet.
14. Backend adapters for OpenAI and Gemini, if production moves off xAI and fal.ai.
15. Later backlog (roadmap table), in its order: `share-and-photos-extensions`; `tipkit-and-short-tour` (remaining part: a three-step tour); `full-res-export-heic-hdr`; `cloud-erase-enhance-compositing` (backend); `cloud-job-resume-and-push` (backend); `library-bulk-trash` (stored originals); `create-results-polish` (localised prompt enhancement); `collage-carousel-scrapbook` (photocard, Fit Check, movie poster); `batch-and-recipes`; `on-device-upscale-and-eraser`; `widgets-interactive-accented`; `spotlight-focus-album`; `live-photo-and-video-captions`; `universal-links-try-this-look`; `store-retention-pricing-ops`; `trial-credit-cap-family-sharing` (backend); `funnel-measurement` (backend); `server-moderation-stack` (backend, see section 1 item 5); `abuse-ops-reports-bans` (backend, see section 1 item 6); `c2pa-trustmark` (backend); `storefront-compliance`; `subject-consent-step` (backend); `backend-ai-looks` (backend); `ipad-scene-model`; `a11y-dynamic-type-labels`; `weekly-theme-and-recaps`; `app-clip-invite`; `promo-offers-signed` (backend); `translation-policy-precheck`.

## 5. Known risks

Each risk names its file or function and what would settle it.

1. **Install records survive account deletion for up to 30 days.** `account/index.ts` deletes the user, but `private.app_installs`, `private.strikes` and `private.cooldowns` keep hashed install keys with no user link until retention ends (`install_retention_days`). The privacy policy says so. *Settles:* the owner accepts the wording, and the RELEASE checklist §9.4 is re-run.
2. **Refunded Pro keeps Pro until `expires_at`.** `public.record_entitlement` (`20261024000002`); no notifications endpoint yet. *Settles:* section 1, item 6, and a sandbox refund test. **Settled (14 October 2026):** section 1, item 6, once deployed.
3. **Shared-address cool-downs.** `private.add_strike` (address key) can block many users at once. *Settles:* section 3, item 3.
4. **Balance hides address cool-downs.** `ai-image/index.ts` does not pass the address to the balance call. *Settles:* section 1, item 8. **Settled (14 October 2026):** migration `20261025000001`, `wallet_state` with the address.
5. **Trial roll-in.** `private.refresh_subscription` adds trial credits to the first paid month. *Settles:* section 3, item 1.
6. **xAI Zero Data Retention is unverified.** Owner console only. *Settles:* section 3, item 4.
7. **Likeness retries count against the daily 3 when refunded or timed out.** `admit_job`, `free_retries_daily`. *Settles:* section 1, item 8, with a test. **Settled (14 October 2026):** migration `20261025000001`, `abuse_test.sql` case 19.
8. **`flag_job` can count a cancelled job's strike.** `public.flag_job` (migration `20261022000000`). *Settles:* section 1, item 8, with a test. **Settled (14 October 2026):** migration `20261025000001`, `abuse_test.sql` case 20.
9. **Swift tests skip silently** when `policy-vectors.json` is not found (`XCTSkip` in the AppCore tests). *Settles:* section 1, item 9. **Settled (14 October 2026):** `RepositoryFile`, section 1 item 9.
10. **Greek final sigma** may lowercase differently in Swift and JavaScript (`ContentPolicy.swift`, `policy.ts`). *Settles:* section 1, item 10. **Settled (14 October 2026):** both sides fold ς to σ.
11. **CJK line break can join two words into a blocked term** (`ContentPolicy.swift`, `policy.ts`). *Settles:* section 1, item 10. **Settled (14 October 2026):** a control character next to CJK splits words.
12. **Shared test fixtures:** `ad_rewards_test.sql` and `unclaimed_test.sql` share a fixture user, so `backend/scripts/test-db.sh` keeps their order (`ORDER`). *Settles:* the tests use separate fixture ids.
13. **Photo-check failure copy** says the result was not shown. *Settles:* section 1, item 11. **Settled (14 October 2026):** section 1, item 11.
14. **Mac type, menus, sections and ⌘W:** section 2, items 3 to 6. **Partly settled (14 October 2026):** ⌘W closes the editor and Retro Cam, look cards have a Try this look menu, and the chained caption and footnote fonts use the legible Mac sizes; a Mac capture still has to confirm nothing is clipped.
15. **Export-catalog Swift side unchecked** (`scripts/export-catalog.sh`). *Settles:* section 2, item 2.
16. **Test counts disagree:** 319 `func test` declarations against 315 reported passing. *Settles:* section 1, item 1. **Settled (14 October 2026):** AppCore runs 319 tests.
17. **Website sources disagree:** `web/` and `website.yml` here, and `RiosenBeq/aybuke` on Vercel. *Settles:* section 1, item 4. **Settled (14 October 2026):** `web/README.md` names `RiosenBeq/aybuke` as the live source.
18. **App configuration still points at GitHub Pages:** `AppConfig.json` URLs. *Settles:* section 1, item 3. **Settled (14 October 2026):** `AppConfig.json` points at aybuke.org.
19. **Email in the privacy manifest but not in App Privacy.** *Settles:* section 3, item 8.
20. **`XAI_SAFETY_MODEL` is untested against the live API.** `_shared/safety.ts`; off by default. *Settles:* section 3, item 7.
21. **The keep-alive workflow only runs from the default branch,** and GitHub pauses scheduled workflows in a public repository after 60 days without commits (`.github/workflows/keepalive.yml`). *Settles:* the workflow's last run is green in GitHub Actions after each push to `main`.
22. **Free credits need `APPLE_APP_ID`.** Without it, production AppTransactions are rejected (`_shared/apple.ts`), so free credits stay off for App Store installs. *Settles:* `APPLE_APP_ID` = `6822716008` is set, and a TestFlight install shows 2 credits.
23. **Local `main` is stale.** `origin/main` is at `d007a8b` (PR #1). Work continues on `pink-girls-redesign`. *Settles:* the branch policy is written in `AGENTS.md`.
