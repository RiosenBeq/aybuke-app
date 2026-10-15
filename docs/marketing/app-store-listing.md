# App Store listing

The App Store text for all 13 locales lives in [`app-store-metadata.json`](app-store-metadata.json), and `scripts/asc/asc_metadata.py` sends it to the iOS and macOS versions (`--check` runs the checks without the API). This page shows the en-US and Turkish text as App Store Connect gets it, the App Review notes and the in-app purchase review notes; `asc_metadata.py --check` and `iap_review_notes.py --check` fail when it differs from the JSON or the scripts.

Rules followed: no prices in the name, subtitle or keywords; no other platforms, competitors or third-party brands; subscription terms disclosed (Guideline 3.1.2); no promise of results; looks and styles named in a description are free, or the line says some need Pro (Guideline 2.3.2, checked against AppCore's catalogs); the Mac text names no iPhone-only feature, no flash and the Mac App Store's subscription path (checked).

## English (en-US)

**App name** (23/30)

    Aybuke: AI Photo Editor

**Subtitle** (30/30)

    Glow-Ups, Trends & Video Edits

**Promotional text** (162/170; can change anytime without review)

> Free on your device: Retro Cam with a photo booth, collages and carousels, text & stickers and video captions. Plus 50+ one-tap looks and 2 free AI credits a day.

**Keywords** (99/100; comma-separated, no spaces after commas)

    selfie,filter,makeup,aesthetic,y2k,retro,cam,booth,collage,sticker,vhs,art,anime,background,remover

**Description, iPhone and iPad** (3943/4000)

```text
Aybuke is the AI photo editor made for girls who glow. Say what you want to change, tap a trend or turn an idea into art. The everyday tools are free and run right on your device.

SAY IT. SEE IT.
• Magic Edit: type "give me pink hair" or "put me in a pink dress" and watch it happen
• Makeup Studio: 14 looks, or mix your own lips, eyes, blush, sparkle and hair color
• Ideas for every photo, picked on your device, or tap Surprise me for a free effect
• Brush to erase things (zoom in for tiny ones), or sharpen a blurry photo with Enhance
• Every look is made to keep your face, skin tone and body just as they are. Doesn't look like you? Retry free

ONE TAP. A WHOLE NEW AESTHETIC.
• 50+ one-tap looks (some need Pro), like Y2K Digicam, Ballet Core, Bow Era, Sleepover and pet portraits
• Create from text in 20 styles, from Pastel Dream to Anime, with your recent prompts one tap away
• Stuck? Inspire me has ideas. Supported devices add Image Playground and Make it magic with Apple Intelligence

RETRO CAM & RETRO BOOTH
• Shoot with live 80s, 90s and Y2K effects, a self-timer and flash
• Retro Booth: 4 shots with a 3-2-1 countdown, printed as a strip or a grid with the date

FREE, RIGHT ON YOUR DEVICE
• 12 retro effects from VHS '86 to Rainbow '17, many with date stamps, plus Tiny World tilt-shift
• Collages and photo dumps from 2 to 9 photos, or a seamless carousel
• Text & Stickers: words in six fonts, cute stickers and doodles
• Video editor: auto captions in 5 styles (supported languages), auto-cut silences, retro effects and trim
• Cut out and refine the subject for a new background with a soft shadow, or make a sticker
• Crop, straighten and adjust, or just tap Auto. RAW photos develop automatically
• Best shot finds the selfie with the best light and focus. Never ranked by looks

MADE TO SHARE
• Story cards, before/after, photo strips, Which vibe? cards and Cover star covers, with caption ideas
• Hide faces: blur or cover other people's faces in the editor, or blur them as you share

RIGHT WHERE YOU NEED IT
• Today's trend and My glow widgets, plus your glow-up live on the Lock Screen and in the Dynamic Island
• Open Retro Cam or Retro Booth from Siri, Control Center or the Action button, and add retro effects in Shortcuts

PRIVATE BY DEFAULT
• Nothing goes to the cloud until you say yes
• Your photos never train AI and are never sold or used for ads
• Cloud results are deleted from our servers within an hour. My Works stays on your device, with a 30-day Recently deleted
• No sign-up needed. Sign in with Apple only to take your credits to another device
• Every AI image carries an invisible "made with AI" label
• Notifications are opt-in and never come at night or during school hours. No streaks, no spam

FAIR PRICING, NO WEEKLY PLANS
• Free: 2 AI credits every day, and the on-device tools are always free
• Aybuke Pro: 80 credits a month (unused credits roll over), every look and style, no watermark, our best-quality AI and up to 4 images at once
• Pro Yearly: $39.99 a year, with a 7-day free trial and 20 credits for eligible new subscribers
• Pro Monthly: $5.99 a month, or $1.99 for your first month if you're eligible
• Credit packs from $2.99 that never expire
• Failed edits get their credits back. With notifications on, we remind you at least a day before your trial ends

Aybuke speaks 12 languages and works on iPhone and iPad. It's made for ages 13 and up. If you're under 18, talk to a parent or guardian before buying anything or turning on cloud AI.

Prices are in US dollars and may vary by country. Payment is charged to your Apple Account at confirmation of purchase or when the free trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings › Apple Account › Subscriptions.

Terms: https://aybuke.org/legal/en/terms-of-use
Privacy: https://aybuke.org/legal/en/privacy-policy
```

**Description, Mac** (3863/4000): made by `asc_metadata.py` from the text above. The section about widgets, the Lock Screen, the Dynamic Island, Control Center and the Action button gives way to this one, and “Shoot with live 80s, 90s and Y2K effects, a self-timer and flash” → “Shoot with your Mac's camera, with live 80s, 90s and Y2K effects and a self-timer”; “works on iPhone and iPad” → “works on iPhone, iPad and Mac”; “in Settings › Apple Account › Subscriptions” → “in the App Store app › your name › Account Settings › Subscriptions”.

```text
ON YOUR MAC
• A sidebar, a menu bar with keyboard shortcuts, and drag and drop: drop a photo on the window to edit it
```

**What's New** (225/4000; for the first update, as 1.0 has none)

> Hello, glow ✨ This is the very first version of Aybuke! Say what to change, try 50+ one-tap looks, play with free 80s, 90s and Y2K effects, make quick video edits and share it all in one tap. We'd love to hear what you think.

**App Review notes** (3307/4000; sent to the iOS and macOS versions through the API on 15 October 2026)

```text
Aybuke is an AI photo editor and image generator for iPhone, iPad and Mac. No login is needed. Sign in with Apple is optional (Settings > Account, Sign in on the paywall, or the prompt after a purchase); it only lets credits follow the user to another device, and Pro always comes from the Apple Account's purchases. The app creates an anonymous account with our backend only when a cloud AI feature is first used (after consent) or a purchase is made.

How to review:
1. Onboarding: a neutral age step (Apple's Declared Age Range on iOS 26, otherwise month and year), then interests. It ends with "Try Digicam '04 on your photo" (free, on the device). Under 13, only on-device tools are offered: no cloud AI, purchases or ads. A soft paywall (close it with X) and a short tour follow; replay the tour from Settings > Show me around.
2. Cloud AI: Explore > "Try it on your photo" (Magic Edit), any look, Makeup Studio (makeup as play: color and sparkle only, never reshaping a face), or Create. Before any photo or prompt leaves the device, a consent screen names every processor: Supabase (our servers), xAI (its Grok Imagine models make the images) and Anthropic (its Claude model checks the photo before an edit and every result for safety). Tap "Allow AI processing". "Not now" keeps the on-device tools working.
3. Credits: free members get 2 AI credits a day per App Store install, verified from StoreKit's signed AppTransaction (Sandbox and TestFlight installs are accepted). Pro includes 80 credits a month. Tapping a balance explains credits.
4. Ads, only for free members 13+ on iPhone and iPad: when out of credits, "Watch a short ad · +1 credit" (at most 2 a day; the credit comes only from AdMob's signed server-side callback), and an occasional interstitial after a finished save or share (at most 3 a day, never inside the editor or before a result). Every ad request is non-personalised, teens get child-directed treatment, and the app never asks for tracking or reads the advertising identifier. No ads for Pro members, under 13 or on the Mac.
5. On-device tools (no consent, no credits): Effects, Adjust, Crop, Cut out, Hide faces, Text & Stickers, Collage, Best shot, the video editor with captions, Retro Cam and Photo Booth.
6. Purchases: two subscriptions (yearly with a 7-day free trial; monthly with a first-month introductory price) and two consumable credit packs, all StoreKit 2. Please use a Sandbox account. Restore is on the paywall and in Settings. The RevenueCat SDK only records purchases for analytics.
7. Safety: prompts are filtered on the device and on the server in all 12 app languages (sexual, revealing, humiliating and body, face or skin reshaping requests are blocked). Claude checks the photo before an edit; every result passes xAI's moderation and the same independent Claude check before the app can download it. Anything flagged, or anything that can't be checked, is blocked and its credit refunded. Users can report any result (results screen > "..." > Report this image).
8. AI labelling: exported AI images carry IPTC DigitalSourceType metadata, and the share screen offers an optional visible "AI-edited" label.
9. Account deletion: Settings > Delete my data & account (Guideline 5.1.1(v)). For a Sign in with Apple account this also revokes the Apple token.
10. The Privacy Policy, Terms of Use and Acceptable Use Policy are in the app (Settings > Terms, privacy & legal) and at aybuke.org. The app is localized in 12 languages; the legal documents are in English and Turkish.

Contact: hello@buaze.com
```

For the macOS version the same text gets one more paragraph before the contact line:

```text
On the Mac: the same app (Mac Catalyst) with a sidebar and a menu bar; drop a photo on the window to edit it, and Retro Cam uses the Mac's camera. The Live Activity, Instagram Stories sharing and ads aren't offered on the Mac; everything else matches the iOS app.
```

**In-app purchase review notes** (sent with `scripts/asc/iap_review_notes.py`; each product's "Review Notes" in App Store Connect)

Aybuke Pro Yearly (`app.glowlit.pro.yearly`) (1176/4000):

```text
Aybuke Pro Yearly (auto-renewable): $39.99 a year, with a 7-day free trial for eligible new subscribers that includes 20 AI credits. Pro gives 80 AI credits a month (unused credits roll over, up to 160), every look and style, the best-quality AI, no watermark and no ads.

Where to find it: in onboarding, choose an age of 13 or older (under 13 the app offers no purchases). Open Settings (the gear at the top right of Explore; on the Mac, the gear at the bottom of the sidebar, or Settings… in the app menu) and, under Membership, tap "Upgrade to Aybuke Pro" to open the paywall, then pick the yearly plan. The paywall also opens from any look or style marked Pro, from "Get more credits" after tapping the credit balance (top of Explore; on the Mac, the bottom of the sidebar), and when free credits run out. Restore: "Restore" on the paywall, or Settings > Membership > "Restore purchases".

Purchases in TestFlight and in App Review run in the App Store sandbox and aren't charged; our server verifies Apple's signed transaction and accepts Sandbox transactions. Using AI credits shows a one-time consent screen first (Supabase, xAI, Anthropic): tap "Allow AI processing".
```

Aybuke Pro Monthly (`app.glowlit.pro.monthly`) (1152/4000):

```text
Aybuke Pro Monthly (auto-renewable): $5.99 a month; eligible new subscribers pay $1.99 for the first month. Pro gives 80 AI credits a month (unused credits roll over, up to 160), every look and style, the best-quality AI, no watermark and no ads.

Where to find it: in onboarding, choose an age of 13 or older (under 13 the app offers no purchases). Open Settings (the gear at the top right of Explore; on the Mac, the gear at the bottom of the sidebar, or Settings… in the app menu) and, under Membership, tap "Upgrade to Aybuke Pro" to open the paywall, then pick the monthly plan. The paywall also opens from any look or style marked Pro, from "Get more credits" after tapping the credit balance (top of Explore; on the Mac, the bottom of the sidebar), and when free credits run out. Restore: "Restore" on the paywall, or Settings > Membership > "Restore purchases".

Purchases in TestFlight and in App Review run in the App Store sandbox and aren't charged; our server verifies Apple's signed transaction and accepts Sandbox transactions. Using AI credits shows a one-time consent screen first (Supabase, xAI, Anthropic): tap "Allow AI processing".
```

30 Credits (`app.glowlit.credits.30`) (980/4000):

```text
30 Credits (consumable): 30 AI credits for $2.99 that never expire. 1 credit = 1 AI creation or edit.

Where to find it: in onboarding, choose an age of 13 or older (under 13 the app offers no purchases). Open Settings (the gear at the top right of Explore; on the Mac, the gear at the bottom of the sidebar, or Settings… in the app menu) and, under Credits, tap "Buy a credit pack". The packs are also below the plans on the paywall ("Not ready to subscribe? Get a credit pack"), and Pro members reach them from "Get more credits" after tapping the credit balance (top of Explore; on the Mac, the bottom of the sidebar).

Purchases in TestFlight and in App Review run in the App Store sandbox and aren't charged; our server verifies Apple's signed transaction and accepts Sandbox transactions. The credits are added after that check, and the balance updates in the app. Using AI credits shows a one-time consent screen first (Supabase, xAI, Anthropic): tap "Allow AI processing".
```

100 Credits (`app.glowlit.credits.100`) (982/4000):

```text
100 Credits (consumable): 100 AI credits for $7.99 that never expire. 1 credit = 1 AI creation or edit.

Where to find it: in onboarding, choose an age of 13 or older (under 13 the app offers no purchases). Open Settings (the gear at the top right of Explore; on the Mac, the gear at the bottom of the sidebar, or Settings… in the app menu) and, under Credits, tap "Buy a credit pack". The packs are also below the plans on the paywall ("Not ready to subscribe? Get a credit pack"), and Pro members reach them from "Get more credits" after tapping the credit balance (top of Explore; on the Mac, the bottom of the sidebar).

Purchases in TestFlight and in App Review run in the App Store sandbox and aren't charged; our server verifies Apple's signed transaction and accepts Sandbox transactions. The credits are added after that check, and the balance updates in the app. Using AI credits shows a one-time consent screen first (Supabase, xAI, Anthropic): tap "Allow AI processing".
```

## Türkçe (tr)

**App name** (29/30)

    Aybuke: AI Fotoğraf Düzenleme

**Subtitle** (29/30)

    Glow-up, retro efekt ve video

**Promotional text** (168/170; can change anytime without review)

> Cihazda ücretsiz: fotoğraf kabinli Retro Cam, kolaj ve kaydırmalı gönderi, yazı, çıkartma, video altyazısı. Ayrıca 50+ tek dokunuşla trend, günde 2 ücretsiz AI kredisi.

**Keywords** (96/100; comma-separated, no spaces after commas)

    yapay zeka,selfie,filtre,makyaj,kolaj,kabin,kamera,arka plan,estetik,y2k,anime,sticker,vhs,silme

**Description, iPhone and iPad** (3990/4000)

```text
Aybuke, ışıldayan kızlar için yapılmış yapay zekâlı fotoğraf editörü. Ne değişsin istiyorsan yaz, bir trende dokun ya da bir fikri sanata dönüştür. Günlük araçlar ücretsiz, doğrudan cihazında çalışır.

SÖYLE, GÖR.
• "Saçımı pembe yap" ya da "bana pembe bir elbise giydir" yaz, gerisini izle
• Makyaj Stüdyosu: 14 stil ya da dudak, göz, allık, ışıltı ve saç rengini sen seç
• Her fotoğrafa cihazında seçilen fikirler ya da ücretsiz bir efekt için Şaşırt beni
• Fırçayla sil ya da bulanık fotoğrafı İyileştir ile netleştir
• Her görünüm yüzünü, ten rengini ve vücudunu olduğu gibi korur. Sana benzemedi mi? Ücretsiz tekrar dene

TEK DOKUNUŞ, BAMBAŞKA BİR ESTETİK.
• 50+ tek dokunuşluk görünüm (bazıları Pro'ya özel): Y2K Digicam, Ballet Core, Fiyonklu Günler, Pijama Partisi, evcil hayvan portreleri
• Metinden görsel oluştur: Pastel Rüya'dan Anime'ye 20 stil; son komutların bir dokunuş uzağında
• Desteklenen cihazlarda Image Playground ve Apple Intelligence ile Sihir kat da var

RETRO CAM VE RETRO BOOTH
• Canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı ve flaş da var
• Retro Booth: 3-2-1 geri sayımlı 4 kare; tarihli şerit ya da ızgara olarak basılır

ÜCRETSİZ, DOĞRUDAN CİHAZINDA
• VHS '86'dan Rainbow '17'ye 12 retro efekt, çoğu tarih damgalı; üstüne Tiny World tilt-shift
• 2 ila 9 fotoğraftan kolaj ve photo dump ya da kesintisiz bir kaydırmalı gönderi
• Yazı ve Çıkartma: altı yazı tipinde yazılar, tatlı çıkartmalar ve karalamalar
• Video editörü: 5 stilde otomatik altyazı (desteklenen dillerde), sessizlik kesme, retro efekt, kısaltma
• Dekupe: nesneyi ayır, rötuşla; yumuşak gölgeli yeni arka plan ya da çıkartma yap
• Kırp, düzelt ve ayarla ya da sadece Otomatik'e dokun. RAW fotoğraflar otomatik işlenir
• En iyi kare, ışığı ve netliği en iyi selfie'yi bulur. Asla görünüşe göre sıralamaz

PAYLAŞMAK İÇİN YAPILDI
• Hikâye kartları, önce/sonra, fotoğraf şeritleri, “Hangi vibe?” kartları ve Kapak yıldızı kapakları; açıklama fikirleriyle
• Yüzleri gizle: başkalarının yüzünü editörde bulanıklaştır ya da kapat, paylaşırken de bulanıklaştır

HER AN YANINDA
• Günün trendi ve son çalışman için widget'lar; glow-up'ın da Kilitli Ekran'da ve Dynamic Island'da canlı
• Retro Cam'i ya da Retro Booth'u Siri, Denetim Merkezi veya Eylem düğmesiyle aç; Kestirmeler'de retro efekt ekle

VARSAYILAN OLARAK GİZLİ
• Sen "evet" demeden hiçbir şey buluta gitmez
• Fotoğrafların asla yapay zekâ eğitiminde, satışta ya da reklamda kullanılmaz
• Buluttaki sonuçlar bir saat içinde sunucularımızdan silinir. Eserlerim cihazında kalır; 30 günlük Son silinenler de var
• Üyelik gerekmez. Kredilerini başka cihaza taşımak için Apple ile Giriş Yap
• Her yapay zekâ görseli görünmez bir "yapay zekâ ile yapıldı" etiketi taşır
• Bildirimler isteğe bağlıdır; gece ve okul saatlerinde asla gelmez. Seri baskısı yok, spam yok

ADİL FİYAT, HAFTALIK PLAN YOK
• Ücretsiz: her gün 2 yapay zekâ kredisi; cihazdaki araçlar her zaman ücretsiz
• Aybuke Pro: ayda 80 kredi (kalanlar sonraki aya devreder), tüm görünümler ve stiller, filigran yok, en iyi kalitede yapay zekâ ve tek seferde 4 görsele kadar
• Yıllık plan: uygun yeni aboneler için 20 krediyle 7 gün ücretsiz deneme
• Aylık plan: uygunsan ilk ay indirimli
• Süresi hiç dolmayan kredi paketleri
• Başarısız düzenlemelerin kredisi hep geri gelir. Bildirimler açıksa denemen bitmeden en az bir gün önce hatırlatırız

Aybuke 12 dilde, iPhone ve iPad'de; 13 yaş ve üzeri için tasarlandı. 18 yaşından küçüksen satın almadan ya da bulut yapay zekâyı açmadan önce ailenle ya da velinle konuş.

Fiyatlar ülkeye göre değişebilir. Ödeme, satın alma onaylandığında ya da ücretsiz deneme sona erdiğinde Apple Hesabından tahsil edilir. Abonelikler, mevcut dönemin bitiminden en az 24 saat önce iptal edilmedikçe otomatik olarak yenilenir. İstediğin zaman Ayarlar › Apple Hesabı › Abonelikler'den yönet ya da iptal et.

Kullanım Koşulları: https://aybuke.org/legal/tr/kullanim-kosullari
Gizlilik Politikası: https://aybuke.org/legal/tr/gizlilik-politikasi
```

**Description, Mac** (3913/4000): made by `asc_metadata.py` from the text above. The section about widgets, the Lock Screen, the Dynamic Island, Control Center and the Action button gives way to this one, and “Canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı ve flaş da var” → “Mac'inin kamerasıyla canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı da var”; “iPhone ve iPad'de” → “iPhone, iPad ve Mac'te”; “Ayarlar › Apple Hesabı › Abonelikler'den” → “App Store uygulaması › adın › Hesap Ayarları › Abonelikler'den”.

```text
MAC'İNDE
• Kenar çubuğu, klavye kısayollu menü çubuğu ve sürükle bırak: düzenlemek için bir fotoğrafı pencereye bırak
```

**What's New** (241/4000; for the first update, as 1.0 has none)

> Merhaba ışıltı ✨ Bu, Aybuke'nin ilk sürümü! Ne değişsin yaz, 50+ tek dokunuşluk görünümü dene, ücretsiz 80'ler, 90'lar ve Y2K efektleriyle oyna, videolarını hızlıca düzenle ve hepsini tek dokunuşla paylaş. Ne düşündüğünü duymayı çok isteriz.

## Product Page Optimization: alternatives to A/B test

| Set | Subtitle (≤30) | Keyword focus |
|---|---|---|
| A (default) | AI Glow-Ups, Trends & Edits | selfie, makeup, aesthetic, doll |
| B | Pink Hair, Soft Glam & Trends | hair color, makeup try-on, beauty |
| C | Selfie Glow-Up & AI Art | selfie, portrait, art, cartoon |
| D (TR) | Selfie glow-up ve AI sanat | selfie, portre, sanat, karikatür |

Test one variable at a time (icon, first screenshot or subtitle) for at least 7 days or until each variant has a few thousand impressions.

## Custom product pages

Use these for creator campaigns and ads, each with its own first screenshot and promotional text. Looks marked (Pro) need Pro: a page built on one says so in its promotional text (Guideline 2.3.2).

- **Glow-up looks**: Soft Glam, Pink Hair, Bouncy Curls (Pro) (first screenshot: before/after)
- **Doll Box trend** (Pro): the trending template, for TikTok and Reels campaigns
- **80s & 90s effects**: VHS '86, Disposable '98 and Digicam '04, plus video edits that cut the silences, for TikTok and Reels creators (first screenshot: effects)
- **Restore family photos**: Restore Old Photo (Pro), for Mother's Day and family moments
- **Shots for my shop**: Product Studio (Pro) and Pro Headshot (Pro), for small online sellers
- **Dreamy AI art**: Create from text with Pastel Dream and Kawaii
