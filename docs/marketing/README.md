# Marketing kit

Everything for launching and promoting Aybuke, the AI photo editor made for girls who glow.

| File | What's inside |
|---|---|
| [app-store-listing.md](app-store-listing.md) | App Store Connect copy for en-US and tr-TR (name, subtitle, promo text, keywords, description, What's New, review notes) with measured character counts, plus A/B test and custom product page ideas |
| [social-media-kit.md](social-media-kit.md) | Positioning, voice, visual direction, bios for every platform, hashtags, 20 bilingual captions, 10 short-video scripts, creator outreach, community replies, challenge ideas |
| [launch-plan.md](launch-plan.md) | Pre-launch checklist, launch week, 30-day content calendar, Product Hunt copy, press release (EN/TR), metrics and the ASO routine |
| [screenshot-captions.json](screenshot-captions.json) | Titles and subtitles for the App Store screenshots in all 12 app languages, read by `scripts/marketing-images.py`: one list per language for iPhone and iPad (10 scenes), and the Mac lists under `mac` (8 scenes). `*Asterisks*` mark the one accent word; titles stay within 28 characters and subtitles within 60 (the script warns). Optional `chip` is a short callout pinned to the device, `before`/`after` label the Before/After badge, ` ` keeps a name on one line and `\n` marks where a title breaks when it needs two lines |
| `app-store/` | Generated App Store screenshots: `<lang>/` 1290×2796 (6.9-inch iPhone), `<lang>/ipad/` 2064×2752 (13-inch iPad), `<lang>/mac/` 2880×1800 (Mac) |
| `social/` | Generated launch post (1080×1350), Story (1080×1920) and link-preview image (1200×630) |

**The look:** Aura gradients that flow from one image into the next, a Poppins ExtraBold headline with its accent word in New York Italic and a pink-to-violet gradient, the capture in a drawn device frame (iPhone, iPad, a MacBook for the first Mac image, then the app's window), and sparkles and die-cut stickers drawn in code. Russian headlines use SF Pro (Poppins has no Cyrillic); Japanese, Korean and Chinese use Hiragino Sans, Apple SD Gothic Neo and Hiragino Sans GB, with the accent in colour. Claims follow the app: no credit amounts, and every count (50+ looks, 12 effects, 55 stickers, 20 styles, 14 makeup looks) is one the code backs.

**Regenerate the images** after UI changes: capture the simulator screens (the script's header lists each scene's launch arguments; see also `.github/workflows/screenshots.yml`) and, for the Mac set, the Mac app's window, then run `python3 scripts/marketing-images.py <folder-with-pngs>`. To preview without touching the repo, add `--out <dir>`; `--lang en,tr` and `--only iphone,ipad,mac,social` narrow the run, and `--stand-ins` frames iPhone captures where iPad or Mac captures don't exist yet (for judging the layout only, never for upload).

**Placeholders** such as `{{APP_STORE_URL}}`, `{{PRIVACY_URL}}`, `{{TERMS_URL}}`, `{{SUPPORT_EMAIL}}`, `{{PRESS_EMAIL}}`, `{{WEBSITE_URL}}` and `{{COMPANY_NAME}}` must be replaced before publishing.

---

## Türkçe

Aybuke'nin lansmanı ve tanıtımı için gereken her şey burada:

- **app-store-listing.md:** App Store Connect metinleri (İngilizce ve Türkçe), karakter sayılarıyla birlikte.
- **social-media-kit.md:** Konumlandırma, ses tonu, görsel yön, platform biyografileri, hashtag'ler, 20 iki dilli paylaşım metni, 10 kısa video senaryosu, influencer şablonları ve topluluk yanıtları.
- **launch-plan.md:** Lansman öncesi kontrol listesi, lansman haftası, 30 günlük içerik takvimi, Product Hunt metinleri, basın bülteni ve ölçülecek metrikler.
- **app-store/** ve **social/:** Hazır App Store ekran görüntüleri (iPhone, iPad ve Mac) ile sosyal medya görselleri.

Yayınlamadan önce `{{APP_STORE_URL}}` gibi yer tutucuları gerçek bilgilerle değiştirin.
