# Next steps: from "almost ready" to "submitted for review"

> **Türkçe özet:** Uygulama, backend, App Store Connect kaydı, abonelikler, kredi paketleri, gizlilik bilgileri, web sitesi ve App Review notları hazır. Kalan iş: iki yarım kalan çalışmayı (düzen ve hız) birleştirmek, derlemek, iOS ve Mac derlemesini App Store Connect'e yüklemek, ekran görüntülerini eklemek ve senin onayınla incelemeye göndermek. Bu dosya bir sonraki oturumun başlangıç noktası.

## Where things stand (14 Oct 2026)

Done:
- Supabase project in Frankfurt (EU): tables, cleanup job, anonymous and Apple sign-in, four Edge Functions deployed, settings (bundle id, team id, app id, moderation) set. A real text-to-image job ran end to end. A new user receives 3 free credits.
- `XAI_API_KEY` is saved in Supabase secrets. Zero Data Retention must be on in the xAI console (owner action).
- App Store Connect app "Glowlit: AI Photo Editor" (app id `6822716008`), iOS and macOS platforms, bundle id `app.glowlit.ios`, SKU `glowlit-ios-001`, category Photo & Video.
- App Privacy answers published. Age rating 13+. Price free, 174 countries (not mainland China).
- Listing text for 13 locales (name, subtitle, promotional text, keywords, description), privacy and terms URLs, App Review contact and notes (with phone).
- In-app purchases: subscription group "Glowlit Pro"; `app.glowlit.pro.yearly` ($39.99, 1-week free trial), `app.glowlit.pro.monthly` ($5.99, $1.99 first month); consumables `app.glowlit.credits.30` ($2.99) and `app.glowlit.credits.100` ($7.99). All with en-US and tr text, prices, territories and review screenshots.
- RevenueCat: app and key exist; Apple server notification URLs set for production and sandbox.
- Web site on GitHub Pages: https://riosenbeq.github.io/aybuke-app/ (privacy, terms, support). Repo: https://github.com/RiosenBeq/aybuke-app
- Contact address everywhere: hello@buaze.com.
- Translations (11 languages) are in the app's string catalogs.
- Config: `ios/App/Resources/AppConfig.json` has backend URL, anon key, App Store id, website and legal URLs, `forceDemoMode: false`. `scripts/check-release-config.py --report` passes.

Still open (in order):
1. **Two background branches not yet merged into `pink-girls-redesign`**: the overlap/layout fixes and the performance pass. They live in git worktrees on the owner's Mac: `.claude/worktrees/agent-a4a75767d883b6d64` (overlap, branch `worktree-agent-a4a75767d883b6d64`) and `.claude/worktrees/agent-a1f71de31e33eae9b` (performance, branch `worktree-agent-a1f71de31e33eae9b`). Merge them with `git merge --no-ff`, resolve conflicts keeping both sides, and remove the worktrees afterwards.
2. **Verify the merged tree**: iOS simulator Debug build, Mac Catalyst build (`-destination 'platform=macOS,arch=arm64,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO`), Release device build, `swift test --package-path ios/Packages/AppCore`, `python3 scripts/build-legal.py --check`, `python3 scripts/export-core-strings.py --check`, `python3 scripts/check-honest-copy.py`, and one launch smoke test (home, editor, onboarding, paywall, collage, camera fixture).
3. **Upload the iOS build**: `ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh` (the App Store Connect API key is in `~/.appstoreconnect/private_keys/`; the key and issuer ids are in App Store Connect → Users and Access → Integrations). Needs about 2 GB free disk space.
4. **Upload the Mac build**: same script with `PLATFORM=mac`.
5. **Attach builds to the versions** in App Store Connect (iOS 1.0 and macOS 1.0) once processing finishes (10–30 min).
6. **Screenshots**: upload the iPhone (6.9"), iPad (13") and Mac (16:10) sets from `docs/marketing/app-store/en/` and `tr/` (plus the other locales where they exist). Mac set: `docs/marketing/app-store/*/mac/`.
7. **Subscriptions and IAPs** need their first review: App Store Connect may require each one to be attached to the app version. The first subscription must be submitted together with the app version.
8. **Paid Apps Agreement**: accept the new version in App Store Connect → Business (owner action). Required before subscriptions can be sold.
9. **Owner actions**: paste `XAI_API_KEY` if not done (it is), turn on Zero Data Retention in the xAI console, delete the old inventory Supabase project if still present, check the translations with a native speaker, confirm the App Review phone number.
10. **Final review**: a last smoke test on a real iPhone (AI test with the real backend, purchase in sandbox, restore, delete account), then **submit for review only after the owner says yes**.
11. Optional: rename `docs/SUPABASE-TODO.md` items that are now done; update `AGENTS.md` status section.

## Rules to keep

- Never commit or print secrets (the xAI key, App Store Connect private key, Supabase service role key). The anon key is public by design.
- Don't commit `.claude/`.
- Don't submit for review without the owner's explicit approval in that session.
- Legal documents are edited in `legal/` only; run `python3 scripts/build-legal.py` afterwards.
- App Store text: no emoji (App Store Connect rejects them), descriptions ≤ 4000 characters, promotional text ≤ 170, keywords ≤ 100 bytes.

## Prompt for the next session

```text
Repo: /Users/okanberkmanavoglu/Downloads/fotoai (branch pink-girls-redesign, remote RiosenBeq/aybuke-app).
Read AGENTS.md and docs/NEXT-STEPS.md first, then continue from "Still open" step 1.
1. Merge the two worktree branches worktree-agent-a4a75767d883b6d64 (layout fixes) and worktree-agent-a1f71de31e33eae9b (performance) into pink-girls-redesign with --no-ff; keep both sides on conflicts; remove the worktrees afterwards.
2. Run the verification in step 2 and fix anything that breaks. Do not push until it is green.
3. Push to origin, then upload the iOS and Mac builds with scripts/upload-app-store.sh (step 3-4). Attach builds and screenshots to the App Store versions (step 5-6).
4. Stop before "Submit for Review" and ask the owner for explicit approval.
Commit messages end with: Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
