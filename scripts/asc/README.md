# App Store Connect API helpers

Small Python scripts used to set up the App Store Connect record through the
API (Python 3 with `requests` and `cryptography`). They read `ASC_KEY_ID` and
`ASC_ISSUER_ID` from the environment and the private key from
`~/.appstoreconnect/private_keys/AuthKey_<id>.p8`; the key never goes in the
repo. Run them from this folder (`cd scripts/asc`).

- `asc.py`: the client (JWT, `get`, `get_all`, `post`, `patch`, `delete`).
- `asc_metadata.py <repo> [--dry-run]`: pushes `docs/marketing/app-store-metadata.json`
  (name, subtitle, description, keywords, promotional text) to iOS and macOS 1.0.
- `asc_screenshots.py <repo> [--dry-run] [--only=en-US,tr] [--platform=ios|mac]`:
  replaces the screenshots with `docs/marketing/app-store/<lang>/` (iPhone), `ipad/`, `mac/`.
- `iap_localize.py`: names and descriptions of the subscription group, both
  subscriptions and both credit packs in all 13 locales.
