# Marketing kit

Everything for launching and promoting Glowlit, the AI photo editor made for girls who glow.

| File | What's inside |
|---|---|
| [app-store-listing.md](app-store-listing.md) | App Store Connect copy for en-US and tr-TR (name, subtitle, promo text, keywords, description, What's New, review notes) with measured character counts, plus A/B test and custom product page ideas |
| [social-media-kit.md](social-media-kit.md) | Positioning, voice, visual direction, bios for every platform, hashtags, 20 bilingual captions, 10 short-video scripts, creator outreach, community replies, challenge ideas |
| [launch-plan.md](launch-plan.md) | Pre-launch checklist, launch week, 30-day content calendar, Product Hunt copy, press release (EN/TR), metrics and the ASO routine |
| [screenshot-captions.json](screenshot-captions.json) | Headlines for the App Store screenshots (EN/TR), read by `scripts/marketing-images.py` |
| `app-store/` | Generated App Store screenshots, 1290×2796 (6.9-inch iPhone), English and Turkish |
| `social/` | Generated launch post (1080×1350), Story (1080×1920) and link-preview image (1200×630) |

**Regenerate the images** after UI changes: capture the simulator screens (see `.github/workflows/screenshots.yml` or the README), then run `python3 scripts/marketing-images.py <folder-with-pngs>`.

**Placeholders** such as `{{APP_STORE_URL}}`, `{{PRIVACY_URL}}`, `{{TERMS_URL}}`, `{{SUPPORT_EMAIL}}`, `{{PRESS_EMAIL}}`, `{{WEBSITE_URL}}` and `{{COMPANY_NAME}}` must be replaced before publishing.

---

## Türkçe

Glowlit'in lansmanı ve tanıtımı için gereken her şey burada:

- **app-store-listing.md:** App Store Connect metinleri (İngilizce ve Türkçe), karakter sayılarıyla birlikte.
- **social-media-kit.md:** Konumlandırma, ses tonu, görsel yön, platform biyografileri, hashtag'ler, 20 iki dilli paylaşım metni, 10 kısa video senaryosu, influencer şablonları ve topluluk yanıtları.
- **launch-plan.md:** Lansman öncesi kontrol listesi, lansman haftası, 30 günlük içerik takvimi, Product Hunt metinleri, basın bülteni ve ölçülecek metrikler.
- **app-store/** ve **social/:** Hazır App Store ekran görüntüleri ile sosyal medya görselleri.

Yayınlamadan önce `{{APP_STORE_URL}}` gibi yer tutucuları gerçek bilgilerle değiştirin.
