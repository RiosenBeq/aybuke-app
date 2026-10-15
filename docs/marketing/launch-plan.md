# Launch plan

A practical plan for Aybuke's first 30 days. English first, Turkish summary at the end.

## 1. Before launch (2–4 weeks out)

- [ ] **Name and handles:** search the App Store and trademark databases (TÜRKPATENT, EUIPO, USPTO; Nice classes 9 and 42) for "Aybuke"; claim @glowlit / @glowlitapp on Instagram, TikTok, X, Threads, YouTube, Pinterest and LinkedIn.
- [ ] **Domain and landing page:** register `glowlit.app`, then deploy `web/` (see `web/README.md`); point `websiteURL` in `ios/App/Resources/AppConfig.json` at it so share captions carry a link.
- [ ] **Legal:** finish `legal/config.json`, get the documents reviewed, publish them (see `legal/README.md`).
- [ ] **Meta App ID** for one-tap Instagram Stories sharing: create an app at developers.facebook.com and set `instagramAppID` in `AppConfig.json`.
- [ ] **App Store assets:** screenshots from `docs/marketing/app-store/` (English and Turkish), listing copy from `app-store-listing.md`, the app preview video (screen recording of scripts 1, 2 and 6 from the social kit).
- [ ] **TestFlight beta:** 50–200 testers (friends, creators, a beta waitlist from the landing page). Collect feedback on likeness, speed and pricing.
- [ ] **Press kit:** icon, brand board (`docs/assets/brand/`), screenshots, founder photo and bio, fact sheet, press release (below).
- [ ] **Content bank:** prepare 15 posts and 10 short videos from the social kit before day 1.
- [ ] **Measurement:** App Store Connect analytics, App Analytics campaign links (`ct=` parameter) for each channel and creator, and the in-app numbers you already have (no third-party tracking SDKs).

## 2. Launch week

| Day | What |
|---|---|
| Day 1 (Tue) | App live. Post the launch Reel (script 1) and carousel (caption 1). Stories with the App Store link sticker. Email the beta testers. |
| Day 2 | Product Hunt launch (00:01 PT). Reply to every comment. Post the Doll Box Reel (script 2). |
| Day 3 | Creator wave 1: 5–10 gifted Pro codes go live. Repost (with permission) to Stories. |
| Day 4 | Privacy explainer carousel (caption 9). Pitch tech and lifestyle press with the press release. |
| Day 5 | Start #GlowlitChallenge week 1 (Pink Hair). |
| Day 6 | Community day: reply to comments and DMs, feature favourite creations. |
| Day 7 | Recap post. Review the numbers and adjust the content mix for week 2. |

## 3. 30-day content calendar

Platforms: IG = Instagram, TT = TikTok, YT = YouTube Shorts, TH = Threads. Caption and script numbers refer to `social-media-kit.md`.

| Day | Platform | Format | Topic | Ref |
|---|---|---|---|---|
| 1 | IG, TT | Reel | "Say it" reveal | Script 1, caption 1 |
| 2 | IG, TT, YT | Reel | Doll Box | Script 2, caption 2 |
| 3 | IG | Carousel | Soft Glam before/after | Caption 3 |
| 4 | IG, TH | Carousel | Privacy explainer | Caption 9 |
| 5 | IG, TT | Reel | #GlowlitChallenge: Pink Hair | Caption 19 |
| 6 | IG | Stories | Community favourites | — |
| 7 | IG, TH | Static | Week 1 recap | — |
| 8 | TT, YT | Short | POV: digicam | Script 3, caption 5 |
| 9 | IG | Carousel | Ballet Core | Caption 4 |
| 10 | IG, TT | Reel | 3 looks, 1 selfie | Script 6 |
| 11 | IG, TH | Static | Fair-Price Promise | Caption 10 |
| 12 | IG, TT, YT | Reel | Restore grandma's photo | Script 4, caption 7 |
| 13 | IG | Stories | Q&A sticker: "What trend next?" | — |
| 14 | IG | Carousel | Challenge winners | — |
| 15 | TT | Short | Prompt challenge | Script 8, caption 8 |
| 16 | IG | Static | Café Date | Caption 11 |
| 17 | IG, TT | Reel | Fairy Princess | Caption 6 |
| 18 | IG, TH | Carousel | Free background remover tip | Script 7, caption 15 |
| 19 | IG, TT | Reel | Tell me without telling me | Script 5 |
| 20 | IG | Static | Story cards feature | Caption 20 |
| 21 | IG | Carousel | Week 3 recap + challenge week 3 | — |
| 22 | IG, TT | Reel | Paris Trip | Caption 12 |
| 23 | IG | Carousel | Shop owners: Product Studio | Caption 16 |
| 24 | TT, YT | Short | Café date in 1 tap | Script 9 |
| 25 | IG | Static | Golden Hour Glow | Caption 17 |
| 26 | IG, TT | Reel | Birthday Glam | Caption 13 |
| 27 | IG, TH | Carousel | Privacy in 10 s | Script 10 |
| 28 | IG | Carousel | Bestie Polaroid | Caption 14 |
| 29 | IG, TT | Reel | Seasonal look (Witchy Glam in October) | Caption 18 |
| 30 | IG, TH | Static | Month 1 thank-you + what's next | — |

## 4. Product Hunt

- **Tagline (≤60):** AI glow-ups you just say out loud ✨ (35)
- **Description (≤260):** Aybuke is an AI photo editor made for girls who glow. Type "give me pink hair", tap a trend like Doll Box or Ballet Core, or create art from text, then share to Stories in one tap. Private by default and fairly priced: no weekly plan. (235)
- **First comment:** Hi Product Hunt! 👋 We built Aybuke because AI photo apps kept making people look like someone else, hid their prices behind weekly trials and quietly kept their photos. So we did the opposite: identity-preserving looks with a free retry, no weekly plan, refunds for failed edits, and photos that never train AI and are deleted from our servers within an hour. We'd love your feedback, especially on which trend we should add next!

## 5. Communities

- Share where self-promotion is allowed (for example r/iosapps, r/SideProject, Indie Hackers, Turkish iOS and design communities), follow each community's rules, disclose that you're the maker, and offer something useful (a free Pro code, a "how we built it" write-up).
- Don't spam beauty or teen communities, and never message minors.

## 6. Press release

**EN.** *{{COMPANY_NAME}} launches Aybuke, the AI photo editor made for girls who glow.* Aybuke lets people edit photos just by describing the change ("give me pink hair", "add soft glam makeup"), restyle a portrait in one tap with trends such as Doll Box, Ballet Core and Fairy Princess, and create dreamy images from text. Unlike many AI photo apps, Aybuke is private by default: nothing goes to the cloud without the user's consent, photos are never used to train AI and are deleted from our servers within an hour, and every AI image carries an invisible "made with AI" label. Pricing is designed to be fair: 2 free credits a day, no weekly plan, credit packs that never expire and automatic refunds for failed edits. "[Founder quote]", said [Founder name], founder of {{COMPANY_NAME}}. Aybuke is available on the App Store for iPhone (iOS 17 or later): {{APP_STORE_URL}}. Press contact: {{PRESS_EMAIL}}.

**TR.** *{{COMPANY_NAME}}, ışıldayan kızlar için tasarlanan yapay zekâlı fotoğraf editörü Aybuke'yi yayınladı.* Aybuke ile fotoğraflar, yapılacak değişikliği yazarak düzenlenebiliyor ("saçımı pembe yap", "soft glam makyaj ekle"); Doll Box, Ballet Core ve Peri Prensesi gibi trendlerle bir portre tek dokunuşla yeniden yorumlanabiliyor ve metinden rüya gibi görseller oluşturulabiliyor. Birçok yapay zekâ fotoğraf uygulamasının aksine Aybuke varsayılan olarak gizli: kullanıcının onayı olmadan hiçbir şey buluta gitmiyor, fotoğraflar asla yapay zekâ eğitiminde kullanılmıyor ve bir saat içinde sunucularımızdan siliniyor; her yapay zekâ görseli görünmez bir "yapay zekâ ile yapıldı" etiketi taşıyor. Fiyatlandırma adil olacak şekilde tasarlandı: günde 2 ücretsiz kredi, haftalık plan yok, süresi dolmayan kredi paketleri ve başarısız düzenlemelerde otomatik iade. "[Kurucu alıntısı]" diyen [Kurucu adı], ... Aybuke, iPhone için App Store'da (iOS 17 ve üzeri): {{APP_STORE_URL}}. Basın iletişimi: {{PRESS_EMAIL}}.

**Press kit contents:** app icon (light, dark), brand board, 8 App Store screenshots (EN and TR), 3 before/after pairs (with the subjects' written consent), founder photo and bio, fact sheet (launch date, price points, platforms, team, contact).

## 7. What to measure

- **Store:** impressions → product page views → installs (conversion rate per source), Product Page Optimization results.
- **Activation:** onboarding completion, first creation within the first session, AI consent opt-in rate.
- **Monetisation:** paywall view → trial start, trial → paid, refund rate, credit pack purchases.
- **Retention:** D1, D7, D30.
- **Virality:** share-sheet opens per creation, shares per user, installs from links (App Analytics campaign `ct=` parameters per creator).
- **Quality:** "Retry free" rate (a likeness signal), report rate, blocked-request rate.

**ASO routine (every 2 weeks):** review keyword rankings and conversion, swap one keyword cluster, test one creative element (icon, first screenshot or subtitle), refresh the promotional text with the newest trend.

---

## Türkçe özet

1. **Lansmandan önce:** marka ve kullanıcı adı kontrolü (TÜRKPATENT, EUIPO, USPTO), `glowlit.app` alan adı ve `web/` sayfasının yayına alınması, yasal metinlerin tamamlanması, Instagram Hikâyeler paylaşımı için Meta App ID, App Store görselleri (`docs/marketing/app-store/`), TestFlight beta grubu, basın kiti ve 15 gönderi ile 10 kısa videoluk içerik bankası.
2. **Lansman haftası:** 1. gün lansman Reels'i ve karuseli, 2. gün Product Hunt, 3. gün ilk influencer dalgası, 4. gün gizlilik karuseli ve basın, 5. gün #GlowlitChallenge (Pembe Saç), 6. gün topluluk günü, 7. gün değerlendirme.
3. **30 günlük takvim:** yukarıdaki tablo; altyazı ve senaryo numaraları `social-media-kit.md` dosyasındadır.
4. **Basın bülteni:** yukarıdaki Türkçe metin; kurucu alıntısını ve adını ekleyin.
5. **Ölçülecekler:** mağaza dönüşümü, ilk oturumda ilk oluşturma, yapay zekâ onay oranı, deneme→ücretli dönüşüm, D1/D7/D30 elde tutma, oluşturma başına paylaşım ve "Retry free" oranı.
6. **Kurallar:** Değerlendirme veya yorum karşılığında ödül verilmez (App Store kuralı). İş birlikleri yalnızca 18 yaş üstü içerik üreticileriyle yapılır ve #reklam ile açıkça belirtilir. Reşit olmayanlara asla mesaj atılmaz.
