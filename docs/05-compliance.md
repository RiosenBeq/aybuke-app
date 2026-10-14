# 05 · Compliance checklist

*Not legal advice. Have counsel review before launch.* Sources and quotes are in [research/tech-and-compliance.md §5–6](research/tech-and-compliance.md#5-app-store-review-guidelines-relevant-to-ai-photo-apps).

## App Store Review Guidelines (last updated June 8, 2026)

| Rule | Requirement | Status in Glowlit |
|---|---|---|
| **5.1.2(i)** third-party AI (Nov 2025) | Disclose where personal data goes, including third-party AI, and get **explicit permission** first | ✅ `AIConsentView` asks before the first cloud job and names the processor: "xAI (Grok Imagine)" (`aiProviderName` in `AppConfig.json`; developer mode names its own provider). It is revocable in Settings. On-device features (effects, video editing, background removal, adjustments, Best shot) work without consent. |
| 5.1.1 privacy | Privacy policy; data minimisation; out-of-process picker | ✅ `PhotosPicker` (no library permission); only `NSPhotoLibraryAddUsageDescription`. ✅ Privacy Policy drafted (EN/TR) and bundled in the app; published copy in `docs/legal/`. ⏳ Lawyer review and final URL. |
| 5.1.1(v) accounts | Usable without login; in-app account deletion if accounts exist | ✅ Anonymous auth; Settings → "Delete my data & account" (server `account` function). |
| 5.1.2(vi) | Face/photo data never used for ads or data mining | ✅ Policy and copy: "Never used to train AI models", "Never sold or shared for advertising". |
| **1.1 / 1.1.4** objectionable | No sexual or pornographic content, no mean-spirited edits | ✅ Client and server prompt policy (sexual requests blocked in all 12 app languages), provider moderation (xAI filters outputs; fal's safety tolerance), output NSFW check. ⏳ Add harassment phrases ("make her fat", "put X in jail"). |
| **1.2** UGC | Filtering, reporting, blocking, contact info | ✅ Filtering, "Report this image" (results menu and the editor's flag) sent to the backend `report` function and stored in `public.reports`; support contact in Settings and the AUP. ⏳ User ban list and a review routine. |
| **4.3** spam | Must be meaningfully different | ✅ On-device tools, Likeness Lock, Fair-Price Promise, server-side trend engine. Describe these in Review Notes. |
| 4.1(c) / 2.3.7 / 5.2.1 IP | No third-party brands, artists or studios in names, icons, metadata or templates | ✅ "Anime Film", not "Ghibli"; no "Nano Banana" or "ChatGPT" in metadata. |
| **3.1.1** IAP | Digital goods via IAP; purchased credits **may not expire**; restore | ✅ StoreKit 2; packs never expire; Restore on the paywall and in Settings. |
| **3.1.2** subscriptions | Name, duration, price per period, what's included, trial terms, auto-renew text, Terms and Privacy links, visible close; the **billed amount is the most prominent price**; no trial toggles (rejected since Jan 2026) | ✅ `PaywallView`; Terms and Privacy open in-app. ✅ Terms/EULA drafted with Apple's minimum terms. ⏳ Lawyer review and final URL. |
| Age rating (13+/16+/18+) | Answer the new questionnaire honestly; 18+ apps are blocked in AU, BR and SG without age confirmation | ✅ Minimum age 13 stated at onboarding and in the Terms; under-18 guidance in the consent screen, Terms and Privacy Policy. ⏳ Target **13+**, consider the Declared Age Range API. |
| Privacy manifest | Required-reason APIs and collected data types | ✅ `PrivacyInfo.xcprivacy`: UserDefaults `CA92.1`; photos, other user content, user ID and purchase history for app functionality, all linked to the user (job results sit under the user ID until download, prompts carry a hashed user tag, reports are keyed to the user ID); no tracking. The RevenueCat SDK ships its own manifest. ⏳ RevenueCat is on (observer mode), so check the App Privacy answers in App Store Connect: purchase history and the user ID now also serve analytics. |
| 4.8 login | An equivalent option if social login is added | ✅ Not applicable: the only sign-in is the optional Sign in with Apple; no third-party social login. |
| SDK floor | iOS 26 SDK since Apr 2026; **iOS 27 SDK from Apr 2027** | ⏳ Build with Xcode 26+/27 for submission (the project works with Xcode 16+). The Liquid Glass tab bar and editor toolbar need the iOS 26 SDK; older SDKs build a frosted fallback. |

## EU AI Act

| Article | Obligation | Status |
|---|---|---|
| **Art. 50(2)**, from 2 Aug 2026 (a new app is covered from launch) | AI-generated or manipulated outputs must be **marked in a machine-readable, detectable way** | ✅ IPTC `Iptc4xmpExt:DigitalSourceType` in the XMP of every exported image: `trainedAlgorithmicMedia` for text-to-image and restyles; `compositeWithTrainedAlgorithmicMedia` for edits, erase and generative enhance; `algorithmicallyEnhanced` for the cut-out. Manual adjustments, Auto, RAW development, retro effects and video edits carry no claim: no AI is involved (standard-editing exemption). ⏳ Add C2PA manifests (server-side signing) and keep provider watermarks such as SynthID. |
| Art. 50(4) | Deployers of deep fakes must disclose them (users acting professionally) | ✅ Optional visible "✦ AI-edited" label in the share composer, plus a tip to switch on the platform's own AI label when posting publicly. |
| **Art. 5(1)(ba)**, from **2 Dec 2026** (Reg. 2026/1744) | Ban on systems that can produce non-consensual intimate imagery of identifiable people **without adequate safeguards** | ✅ Layered safeguards: client and server prompt policy in all 12 app languages, server-only template recipes, provider moderation (xAI drops filtered outputs), output NSFW check on by default (fal's checker when `FAL_KEY` is set), reporting. ⏳ Red-team the filters in every app language and keep the logs as evidence. ⏳ Add an upload-side NSFW check. ⏳ Decide whether to keep `FAL_KEY` set in production, so a second, independent output check runs on xAI results. |

## GDPR / privacy

- **Biometrics:** face photos are not biometric data under Art. 9 unless they are processed for identification. **Never** build face embeddings, matching or "find this person" features.
- **Roles:** we are the controller; xAI (the default AI provider), Supabase, RevenueCat, and fal.ai and its model vendors where used, are processors. ✅ Sub-processor list in Privacy Policy §12 (xAI and RevenueCat included). ⏳ Sign DPAs; ⏳ appoint an Art. 27 representative if there is no EU establishment.
- **Lawful basis:** contract, for performing the requested edit, plus the explicit consent screen. ⏳ Run a DPIA.

**Retention, as implemented**

| Data | Retention |
|---|---|
| Inputs | Never stored by us; passed straight to the AI provider (xAI by default). With xAI Zero Data Retention on (⏳ switch it on in the xAI console before launch), xAI deletes requests and results within an hour and keeps no copies |
| Outputs | xAI: returned inline (base64) and kept on the job row only until the app confirms the download, then cleared; `sweep_jobs` clears any left after 1 hour. fal: expire on the fal CDN after 1 hour; fal request history is off |
| Job rows | Deleted after 30 days (`sweep_jobs`) |
| Library | On the device only |
| Videos and on-device edits | Never leave the device |
| Purchase analytics | Purchase records, our account ID and basic device and app information, held by RevenueCat as our processor; no photos, prompts or results |
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
| **Body image** | ✅ Every people template's identity clause also protects **body shape**; no body-reshaping or skin-lightening features; the prompt policy (app and server, 12 languages) blocks reshaping, skin-tone changes, skin retouching and looks rating in free-text edits, and every Magic Edit carries a guard that keeps faces, bodies, skin and age as they are; the AUP bans shaming or deceptive body edits. |
| **Templates** | ✅ No brand, celebrity or character names (the doll trend is "Doll Box", text-free packaging); outfits are modest by instruction. |
| **Legal set** | ✅ Terms (EULA + subscriptions + credits + Apple terms), Privacy Policy (GDPR, UK GDPR, KVKK, CCPA/CPRA and other US states, COPPA), Acceptable Use & AI Content Policy, KVKK Aydınlatma Metni, in English and Turkish → [legal/](../legal/README.md). ⏳ Lawyer review and the checklist in `legal/README.md`. |
| **Türkiye (KVKK)** | ✅ Aydınlatma metni; transfers abroad on the Board's standard contracts (Law 7499 amendments); application channels (written, KEP, e-signature, registered email). ⏳ Sign and notify the standard contracts within 5 business days; VERBİS assessment. |
| **Sharing** | ✅ Instagram Stories via the documented pasteboard handoff when a Meta App ID is set; without one, the system share sheet with just the image. The composer reminds users to switch on platform AI labels; free exports carry a small brand mark; all AI exports keep IPTC provenance. Cover star's person cut-out (Vision segmentation) runs on the device and is never stored. |
| **Developer AI keys** | ✅ Only in the git-ignored `ios/Config/Secrets.xcconfig` (`GL_AI_PROVIDER` = xai, fal, openai or gemini), read only by DEBUG builds and blanked by `Release.xcconfig`. Production keys stay in backend secrets (`XAI_API_KEY`, or `FAL_KEY`). |
| **Retention** | ✅ `sweep_jobs` now clears job outputs after 1 hour and deletes reports after 12 months (migration `20261012000000`). |
| **Notifications (teens)** | ✅ Every kind is off until she switches it on, and permission is asked in context, never at launch. Nothing between 21:00 and 09:00 or during school hours on weekdays. No streaks, no Time Sensitive interruptions, no push server. These follow UK Children's Code standards 5 and 13, and we use the EU DSA minors guidelines and California SB 976 as benchmarks. |
| **Rating prompts** | ✅ Apple's prompt only (5.6.1), only after real happy moments, never after failures, reports, retries or paywalls (`ReviewPromptPolicy`). |
| **Accounts** | ✅ Optional Sign in with Apple, never required (5.1.1(v)). Email scope only (hide-my-email works), no name. In-app deletion revokes the Apple token (Apple's account-deletion requirement). Privacy Policy, Terms and KVKK notice updated. ⏳ Enable the capability and the Supabase Apple provider; set the Apple key secrets. |
| **On-device face checks** | ✅ The likeness check, Best shot, kindness reminder, Hide faces and the Cover star / Photo strip face-aware crops use Vision on the device only. Hide faces keeps face boxes in memory only, never landmarks, and adds no AI provenance. No identification or recognition, nothing stored or sent, no attractiveness scores. Disclosed in Privacy Policy §4 and the KVKK notice. |
| **Data consistency** | ✅ The in-app retention text now says "within an hour", matching the policy, website and backend (it said 24 hours before). |

## xAI, video, languages and analytics (October 2026)

| Area | Status |
|---|---|
| **xAI as the AI provider** | ✅ Named on the consent screen and in the Privacy Policy (§6, §12) and KVKK notice. Results are cleared as soon as the app confirms the download (1 hour at most); requests carry a one-way user tag, never the user id. xAI doesn't train on API data without permission. ⏳ **Switch on Zero Data Retention in the xAI console before launch** (selfies are personal data); sign xAI's DPA; cover transfers to the US (DPF or SCCs; KVKK standard contract). |
| **Apple Intelligence in Create** | ✅ "Inspire me" and "Make it magic" use Apple's on-device model: nothing leaves the device, every line passes the prompt policy, Privacy Policy §4. "Create with Image Playground" is Apple's feature: Glowlit's consent and credits don't apply, styles are locked to Apple's cartoon styles, personalization is off, and from iOS 27 (Private Cloud Compute) a one-time notice names Apple before the first use; Privacy Policy §6 and §11 and the KVKK notice say so. ⏳ Test on real iOS 26.x and iOS 27 devices before release: disallowed and body-reshaping prompts typed inside Apple's sheet, "photorealistic" with the style lock, and that her own photo can't be added with personalization off; don't ship it if a realistic edit of a selfie gets through. |
| **Video editing and effects** | ✅ On-device only (AVFoundation, Core Image): no upload, no consent or credits needed, no AI provenance claim. Videos are copied to a temporary file and deleted when the editor closes. |
| **Invite card** | ✅ Made from brand art only; never includes the user's photos. The QR code links to the App Store page or the website. |
| **Languages** | ✅ 12 app languages; the prompt policy blocks sexual requests in all of them. Legal documents are English and Turkish only, and other languages show the English versions. ⏳ Native-speaker review of the translations, especially consent, privacy and paywall copy (3.1.2 wording must stay accurate in every language). |
| **RevenueCat** | ✅ Observer mode, on in builds (public SDK key in `AppConfig.json`). Receives purchase records, our account ID and basic device and app information (app and iOS version, country, language), never photos, prompts or results; listed as a sub-processor in the Privacy Policy and the KVKK notice. ⏳ Sign RevenueCat's DPA; update the App Privacy answers (see Privacy manifest above). |
| **Pricing copy** | ✅ No price comparisons anywhere (the market research puts $39.99/year at the median, so "cheaper than others" would be untrue). With a trial or intro price the paywall button stays neutral ("Continue") and the billed terms sit right beside it at button size, price in bold (3.1.2(c)). |

