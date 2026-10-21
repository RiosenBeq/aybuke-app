# App Store Connect API helpers

Small Python scripts used to set up the App Store Connect record through the
API (Python 3 with `requests` and `cryptography`). They read `ASC_KEY_ID` and
`ASC_ISSUER_ID` from the environment and the private key from
`~/.appstoreconnect/private_keys/AuthKey_<id>.p8`; the key never goes in the
repo. Run them from this folder (`cd scripts/asc`).

Every script that changes a version takes `--version 1.1` (the version string, on
iOS and macOS; created, with its missing locales, when it doesn't exist yet), `--version
<version id>` (that record; a comma list for both), or
by default each platform's editable version (`asc.resolve_versions`), and
`--dry-run`, which shows the records it found and what it would send.

- `asc.py`: the client (JWT, `get`, `get_all`, `post`, `patch`, `delete`) and
  `resolve_versions` / `editable_app_info`.
- `asc_metadata.py <repo> [--version 1.1] [--dry-run] [--review-notes] | --check [--show=<locale>]`:
  pushes `docs/marketing/app-store-metadata.json` (name and subtitle to the editable
  app info; description, keywords, promotional text and What's New to iOS and macOS;
  What's New is left out only when App Store Connect answers that it can't be edited,
  as on an app's first version: 409 `STATE_ERROR` "Attribute 'whatsNew' cannot be
  edited at this time". Any other refusal stops the push).
  The Mac description is made from the iOS one with each locale's `mac` block
  (iPhone-only bullets out, its Mac section in, exact replacements; optional
  `promotionalText` and `whatsNew` for the Mac); `--review-notes` also sends the App
  Review notes from `app-store-listing.md` (the Mac's with its extra paragraph).
  `--check` runs every check offline: limits, no emoji in any text it sends (App
  Store Connect refuses them), the Mac text, Pro looks named without "Pro",
  "Glowlit", the review notes and `app-store-listing.md` in sync.
  `--season <id> [--dry-run]` pushes only the promotional text from each locale's
  `promoBySeason` (a local season such as `eidAlFitr`, `lunarNewYear`, `carnaval`;
  no review needed), and `--season default` puts the usual text back.
- `asc_screenshots.py <repo> [--version 1.1] [--dry-run] [--only=en-US,tr] [--platform=ios|mac]`:
  replaces the screenshots with `docs/marketing/app-store/<lang>/` (iPhone), `ipad/`, `mac/`.
- `asc_previews.py <repo> [--version 1.1] [--dry-run] [--only=en-US,tr]`: replaces the
  iPhone App Preview of en-US and Turkish with `docs/marketing/app-preview/aybuke-app-preview-iphone-{en,tr}.mp4`.
- `iap_localize.py`: names and descriptions of the subscription group, both
  subscriptions and both credit packs in all 13 locales.
- `iap_review_notes.py <repo> [--dry-run | --check]`: the App Review notes of both
  subscriptions and both credit packs (where the paywall and the packs are, sandbox);
  `--check` compares them with `app-store-listing.md` offline.
