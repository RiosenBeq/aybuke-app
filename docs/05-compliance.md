# 05 · Compliance checklist

*Not legal advice. Have counsel review before launch.* Sources and quotes are in [research/tech-and-compliance.md §5–6](research/tech-and-compliance.md#5-app-store-review-guidelines-relevant-to-ai-photo-apps).

## App Store Review Guidelines (last updated June 8, 2026)

| Rule | Requirement | Status in Glowlit |
|---|---|---|
| **5.1.2(i)** third-party AI (Nov 2025) | Disclose where personal data goes, including third-party AI, and get **explicit permission** first | ✅ `AIConsentView` asks before the first cloud job and names the processors (fal.ai and model providers). It is revocable in Settings. On-device features work without consent. |
| 5.1.1 privacy | Privacy policy; data minimisation; out-of-process picker | ✅ `PhotosPicker` (no library permission); only `NSPhotoLibraryAddUsageDescription`. ✅ Privacy Policy drafted (EN/TR) and bundled in the app; published copy in `docs/legal/`. ⏳ Lawyer review and final URL. |
| 5.1.1(v) accounts | Usable without login; in-app account deletion if accounts exist | ✅ Anonymous auth; Settings → "Delete my data & account" (server `account` function). |
| 5.1.2(vi) | Face/photo data never used for ads or data mining | ✅ Policy and copy: "Never used to train AI models", "Never sold or shared for advertising". |
| **1.1 / 1.1.4** objectionable | No sexual or pornographic content, no mean-spirited edits | ✅ Client and server prompt policy, model safety tolerance, output NSFW check. ⏳ Add harassment phrases ("make her fat", "put X in jail"). |
| **1.2** UGC | Filtering, reporting, blocking, contact info | ✅ Filtering, "Report this image" (results menu and the editor's flag) sent to the backend `report` function and stored in `public.reports`; support contact in Settings and the AUP. ⏳ User ban list and a review routine. |
| **4.3** spam | Must be meaningfully different | ✅ On-device tools, Likeness Lock, Fair-Price Promise, server-side trend engine. Describe these in Review Notes. |
| 4.1(c) / 2.3.7 / 5.2.1 IP | No third-party brands, artists or studios in names, icons, metadata or templates | ✅ "Anime Film", not "Ghibli"; no "Nano Banana" or "ChatGPT" in metadata. |
| **3.1.1** IAP | Digital goods via IAP; purchased credits **may not expire**; restore | ✅ StoreKit 2; packs never expire; Restore on the paywall and in Settings. |
| **3.1.2** subscriptions | Name, duration, price per period, what's included, trial terms, auto-renew text, Terms and Privacy links, visible close; the **billed amount is the most prominent price**; no trial toggles (rejected since Jan 2026) | ✅ `PaywallView`; Terms and Privacy open in-app. ✅ Terms/EULA drafted with Apple's minimum terms. ⏳ Lawyer review and final URL. |
| Age rating (13+/16+/18+) | Answer the new questionnaire honestly; 18+ apps are blocked in AU, BR and SG without age confirmation | ✅ Minimum age 13 stated at onboarding and in the Terms; under-18 guidance in the consent screen, Terms and Privacy Policy. ⏳ Target **13+**, consider the Declared Age Range API. |
| Privacy manifest | Required-reason APIs and collected data types | ✅ `PrivacyInfo.xcprivacy`: UserDefaults `CA92.1`; photos, other user content, user ID and purchase history for app functionality; no tracking. |
| 4.8 login | An equivalent option if social login is added | ✅ Not applicable (anonymous). Add Sign in with Apple before any social login. |
| SDK floor | iOS 26 SDK since Apr 2026; **iOS 27 SDK from Apr 2027** | ⏳ Build with Xcode 26+/27 for submission (the project works with Xcode 16+). |

## EU AI Act

| Article | Obligation | Status |
|---|---|---|
| **Art. 50(2)**, from 2 Aug 2026 (a new app is covered from launch) | AI-generated or manipulated outputs must be **marked in a machine-readable, detectable way** | ✅ IPTC `Iptc4xmpExt:DigitalSourceType` in the XMP of every exported image: `trainedAlgorithmicMedia` for text-to-image and restyles; `compositeWithTrainedAlgorithmicMedia` for edits, erase and generative enhance; `algorithmicallyEnhanced` for the cut-out. Manual adjustments only carry no claim (standard-editing exemption). ⏳ Add C2PA manifests (server-side signing) and keep provider watermarks such as SynthID. |
| Art. 50(4) | Deployers of deep fakes must disclose them (users acting professionally) | ⏳ Optional visible "AI-edited" label on export. |
| **Art. 5(1)(ba)**, from **2 Dec 2026** (Reg. 2026/1744) | Ban on systems that can produce non-consensual intimate imagery of identifiable people **without adequate safeguards** | ✅ Layered safeguards: client and server prompt policy, server-only template recipes, strict model safety, output NSFW check on by default, reporting. ⏳ Red-team the filters and keep the logs as evidence. ⏳ Add an upload-side NSFW check. |

## GDPR / privacy

- **Biometrics:** face photos are not biometric data under Art. 9 unless they are processed for identification. **Never** build face embeddings, matching or "find this person" features.
- **Roles:** we are the controller; fal and the model vendors are processors. ⏳ Sign DPAs and publish a sub-processor list; ⏳ appoint an Art. 27 representative if there is no EU establishment.
- **Lawful basis:** contract, for performing the requested edit, plus the explicit consent screen. ⏳ Run a DPIA.

**Retention, as implemented**

| Data | Retention |
|---|---|
| Inputs | Never stored by us; passed straight to fal |
| Outputs | Expire on the fal CDN after 1 hour; fal request history is off |
| Job rows | Deleted after 30 days (`sweep_jobs`) |
| Library | On the device only |
| Account, ledger, entitlements | Deleted, with all rows, on account deletion (cascade) |

## United States

- **California AI Transparency Act** (in force since 2 Aug 2026; applies above 1M monthly users) and **Washington ESHB 1170** (from 1 Feb 2027) require embedded provenance, and accept C2PA. ⏳ Add C2PA before reaching that scale.
- **TAKE IT DOWN Act:** applies to platforms that host user content publicly. Glowlit has no public sharing; adding a feed would trigger a 48-hour removal process.
- **Age assurance:** Texas SB 2420 (from 4 Jun 2026), Utah and Louisiana. ⏳ Declared Age Range API.
- **BIPA and right of publicity:** no face templates; no celebrity or "real person" templates.

## Girls-first redesign (October 2026)

Glowlit is now designed for girls and young women, so many users will be 13–17.

| Area | Status |
|---|---|
| **Teen-safe design** | ✅ No ads, tracking, profiling, public profiles or feeds; cloud AI off until opt-in; library on device; "Under 16? Check with a parent" on the consent screen; Privacy Policy §3 (plain-language for under-18s) and §18 (UK Children's Code standards applied to everyone). ⏳ DPIA. |
| **Body image** | ✅ Every people template's identity clause also protects **body shape**; no body-reshaping or skin-lightening features; the AUP bans shaming or deceptive body edits. |
| **Templates** | ✅ No brand, celebrity or character names (the doll trend is "Doll Box", text-free packaging); outfits are modest by instruction. |
| **Legal set** | ✅ Terms (EULA + subscriptions + credits + Apple terms), Privacy Policy (GDPR, UK GDPR, KVKK, CCPA/CPRA and other US states, COPPA), Acceptable Use & AI Content Policy, KVKK Aydınlatma Metni, in English and Turkish → [legal/](../legal/README.md). ⏳ Lawyer review and the checklist in `legal/README.md`. |
| **Türkiye (KVKK)** | ✅ Aydınlatma metni; transfers abroad on the Board's standard contracts (Law 7499 amendments); application channels (written, KEP, e-signature, registered email). ⏳ Sign and notify the standard contracts within 5 business days; VERBİS assessment. |
| **Sharing** | ✅ Instagram Stories via the documented pasteboard handoff (needs a Meta App ID); captions remind users to switch on platform AI labels; free exports carry a small brand mark; all exports keep IPTC provenance. |
| **Developer AI keys** | ✅ Only in the git-ignored `ios/Config/Secrets.xcconfig`, read only by DEBUG builds and blanked by `Release.xcconfig`. Production keys stay in backend secrets. |
| **Retention** | ✅ `sweep_jobs` now clears job outputs after 1 hour and deletes reports after 12 months (migration `20261012000000`). |

