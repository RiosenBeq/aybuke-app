# App Store listing

The App Store text for all 13 locales lives in [`app-store-metadata.json`](app-store-metadata.json), and `scripts/asc/asc_metadata.py` sends it to the iOS and macOS versions (`--check` runs the checks without the API). This page shows the en-US and Turkish text as App Store Connect gets it, the App Review notes and the in-app purchase review notes; `asc_metadata.py --check` and `iap_review_notes.py --check` fail when it differs from the JSON or the scripts.

Rules followed: no prices in the name, subtitle or keywords; no other platforms, competitors or third-party brands; subscription terms disclosed (Guideline 3.1.2); no promise of results; looks and styles named in a description are free, or the line says some need Pro (Guideline 2.3.2, checked against AppCore's catalogs); the Mac text names no iPhone-only feature, no flash and the Mac App Store's subscription path (checked).

## English (en-US)

**App name** (23/30)

    Aybuke: AI Photo Editor

**Subtitle** (30/30)

    Glow-Ups, Trends & Video Edits

**Promotional text** (154/170; can change anytime without review)

> Glow in Retro Cam, one-tap vertical videos with Auto edit and Which vibe? polls with friends. Plus 20 makeup looks, 50+ looks and 2 free AI credits a day.

**Keywords** (97/100; comma-separated, no spaces after commas)

    selfie,filter,makeup,aesthetic,y2k,retro,cam,booth,collage,sticker,vhs,anime,background,dslr,poll

**Description, iPhone and iPad** (3954/4000)

```text
Aybuke is the AI photo editor made for girls who glow. Say what you want to change, tap a trend or turn an idea into art. The everyday tools are free and run right on your device.

SAY IT. SEE IT.
• Magic Edit: type "give me pink hair" or "put me in a pink dress" and watch it happen
• Makeup Studio: 20 looks, or mix your own lips, eyes, blush, sparkle and hair color
• Aybik, our AI helper, writes ideas, prompts and captions with you. Or tap Surprise me for a free effect
• Brush to erase things (zoom in for tiny ones), or sharpen a blurry photo with Enhance
• Every look is made to keep your face, skin tone and body just as they are. Doesn't look like you? Retry free

ONE TAP. A WHOLE NEW AESTHETIC.
• 50+ one-tap looks (some need Pro), like Y2K Digicam, Ballet Core, Bow Era, Sleepover and pet portraits
• Create from text in 20 styles, from Pastel Dream to Anime, with your recent prompts one tap away

RETRO CAM, GLOW & BOOTH
• Shoot with live 80s, 90s and Y2K effects, a self-timer and flash
• Glow: live looks, sparkle and a soft lip and blush tint. Light and color only, never retouching
• Retro Booth: 4 shots with a 3-2-1 countdown, printed as a strip or a grid with the date

FREE, RIGHT ON YOUR DEVICE
• 13 retro effects from VHS '86 to DSLR '12 with real background blur, plus Tiny World tilt-shift
• Collages and photo dumps from 2 to 9 photos, or a seamless carousel
• Text & Stickers: words in six fonts, cute stickers and doodles
• Auto edit: one tap makes a 9:16 vertical video with your best moments and captions (one free a day). Plus auto captions in 5 styles, silence cuts, effects and trim
• Cut out and refine the subject for a new background with a soft shadow, or make a sticker
• Crop and straighten, tap Auto, or pick a vibe in Adjust and save up to 12 of your own filters

MADE TO SHARE
• Which vibe? polls: friends vote A or B on two pictures through a private link for 24 hours, no app needed
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

**Description, Mac** (3874/4000): made by `asc_metadata.py` from the text above. The section about widgets, the Lock Screen, the Dynamic Island, Control Center and the Action button gives way to this one, and “Shoot with live 80s, 90s and Y2K effects, a self-timer and flash” → “Shoot with your Mac's camera, with live 80s, 90s and Y2K effects and a self-timer”; “works on iPhone and iPad” → “works on iPhone, iPad and Mac”; “in Settings › Apple Account › Subscriptions” → “in the App Store app › your name › Account Settings › Subscriptions”.

```text
ON YOUR MAC
• A sidebar, a menu bar with keyboard shortcuts, and drag and drop: drop a photo on the window to edit it
```

**What's New** (529/4000; version 1.1, iOS and macOS)

```text
Aybuke 1.1 is here ✨
• Glow in Retro Cam: live looks, sparkle and a soft lip and blush tint
• Auto edit: one tap makes a 9:16 vertical video with your best moments and captions (one free a day)
• Which vibe? polls: friends vote between two pictures through a private link
• The DSLR '12 effect and the DSLR Portrait look, with real background blur
• Makeup Studio now has 20 looks
• Vibes in Adjust, your own filters and cleaner Cut out edges
• Aybik, our AI helper, writes ideas and captions with you
Thanks for glowing with us!
```

**App Review notes** (3646/4000; the first App Store version, iOS and macOS; sent with `asc_metadata.py --review-notes`)

```text
Aybuke is an AI photo editor and image generator for iPhone, iPad and Mac. No login is needed. Sign in with Apple is optional (Settings > Account, or Sign in on the paywall) and only lets credits follow the user to another device; Pro always comes from the Apple Account. An anonymous backend account is created only when a cloud AI feature is first used (after consent) or a purchase is made.

How to review:
1. Onboarding: a neutral age step (Declared Age Range on iOS 26, else month and year). Under 13 only on-device tools: no cloud AI, purchases or ads. A soft paywall (close with X) and a short tour follow.
2. Cloud AI: Explore > "Try it on your photo" (Magic Edit), any look, Makeup Studio (color and sparkle only, never reshaping) or Create. First a consent screen names every processor: Supabase (our servers), xAI (Grok Imagine makes the images) and Anthropic, whose Claude model the app calls "Aybik, our AI helper": it checks photos, results and poll pictures for safety and suggests text. Tap "Allow AI processing"; "Not now" keeps the on-device tools working.
3. Aybik writing help (text only, never a photo, no credits): Create > "Inspire me" or "Make it magic", Makeup Studio > "Describe your vibe", caption ideas on the share screen. Without consent the on-device writer or built-in lists answer.
4. Which vibe? polls: My Works > Select two edits or creations > "Ask friends" (also on the share screen). The pictures pass the safety check, then a private link lets anyone vote A or B in a browser for 24 hours, anonymously; then everything is deleted. Results: My Works > Your polls. Questions that rate or compare looks are blocked; a reported poll is closed.
5. On-device tools (no consent, no credits): Effects (incl. DSLR '12), Adjust, Crop, Cut out, Hide faces, Text & Stickers, Collage, Best shot, Retro Cam and Retro Booth. Glow: Retro Cam > "Glow" under the viewfinder; looks, Sparkle and a lip or blush tint, light and color only. Video: Edit > "Edit a video" > an Auto edit button makes a 9:16 cut with framing and captions (one a day free, then the paywall).
6. Credits: 2 free AI credits a day per App Store install (verified from the signed AppTransaction; Sandbox and TestFlight count). Pro includes 80 a month. If AI says it's taking a short break, a daily cost cap was reached (resets 00:00 UTC).
7. Ads (free members 13+, iPhone and iPad only): "Watch a short ad · +1 credit" when out of credits (2 a day, granted only by AdMob's signed server callback); "Try this look once · watch a short ad" on the paywall a Pro look or style opened (once a day, needs a credit; that one job then runs for 1 credit); an occasional interstitial after a finished save or share (never in the first 24 hours, in the editor or before a result; 3 a day at most). Non-personalised, child-directed treatment for teens, no tracking or advertising identifier.
8. Purchases: two subscriptions (yearly with a 7-day trial; monthly with a first-month price) and two credit packs, StoreKit 2. Please use a Sandbox account. Restore is on the paywall and in Settings.
9. Safety: prompts are filtered on the device and the server in 12 languages (sexual, revealing, humiliating and body, face or skin reshaping requests are blocked). Every result passes xAI's moderation and the Claude check; anything flagged or unchecked is blocked and refunded. Report via "..." > Report this image or the flag beside an edit.
10. Exported AI images carry IPTC DigitalSourceType metadata. Account deletion: Settings > Delete my data & account (revokes the Apple token). Policies: Settings > Terms, privacy & legal, and aybuke.org.

Contact: hello@buaze.com
```

For the macOS version the same text gets one more paragraph before the contact line (3870/4000 in all):

```text
On the Mac: the same app (Mac Catalyst) with a sidebar and a menu bar; drop a photo on the window to edit it. Retro Cam and Glow use the Mac's camera. No Live Activity, Instagram Stories sharing, ads or Pro try on the Mac.
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

**Promotional text** (163/170; can change anytime without review)

> Retro Cam'de ışıma, Otomatik kurgu ile tek dokunuşta dikey video ve arkadaşlarınla Hangi vibe? anketleri. Ayrıca 20 makyaj görünümü ve günde 2 ücretsiz AI kredisi.

**Keywords** (95/100; comma-separated, no spaces after commas)

    yapay zeka,selfie,filtre,makyaj,kolaj,kabin,kamera,arka plan,estetik,y2k,sticker,vhs,dslr,anket

**Description, iPhone and iPad** (3994/4000)

```text
Aybuke, ışıldayan kızlar için yapılmış yapay zekâlı fotoğraf editörü. Ne değişsin istiyorsan yaz, bir trende dokun ya da bir fikri sanata dönüştür. Günlük araçlar ücretsiz, doğrudan cihazında çalışır.

SÖYLE, GÖR.
• "Saçımı pembe yap" ya da "bana pembe bir elbise giydir" yaz, gerisini izle
• Makyaj Stüdyosu: 20 stil ya da dudak, göz, allık, ışıltı ve saç rengini sen seç
• Yapay zekâ yardımcımız Aybik fikir, komut ve açıklama yazmana yardım eder; ücretsiz bir efekt için Şaşırt beni'ye dokun
• Fırçayla sil ya da bulanık fotoğrafı İyileştir ile netleştir
• Her görünüm yüzünü, ten rengini ve vücudunu olduğu gibi korur. Sana benzemedi mi? Ücretsiz tekrar dene

TEK DOKUNUŞ, BAMBAŞKA BİR ESTETİK.
• 50+ tek dokunuşluk görünüm (bazıları Pro'ya özel): Y2K Digicam, Ballet Core, Fiyonklu Günler, Pijama Partisi, evcil hayvan portreleri
• Metinden görsel oluştur: Pastel Rüya'dan Anime'ye 20 stil; son komutların bir dokunuş uzağında

RETRO CAM, IŞIMA VE BOOTH
• Canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı ve flaş da var
• Işıma: canlı görünümler, parıltı, hafif dudak ve allık tonu. Sadece ışık ve renk, asla rötuş yok
• Retro Booth: 3-2-1 geri sayımlı 4 kare; tarihli şerit ya da ızgara olarak basılır

ÜCRETSİZ, DOĞRUDAN CİHAZINDA
• VHS '86'dan gerçek arka plan bulanıklığıyla DSLR '12'ye 13 retro efekt; üstüne Tiny World tilt-shift
• 2 ila 9 fotoğraftan kolaj ve photo dump ya da kesintisiz bir kaydırmalı gönderi
• Yazı ve Çıkartma: altı yazı tipinde yazılar, tatlı çıkartmalar ve karalamalar
• Otomatik kurgu: tek dokunuşla en iyi anlarından altyazılı 9:16 dikey video (günde bir ücretsiz). Ayrıca 5 stilde otomatik altyazı, sessizlik kesme, efekt ve kısaltma
• Dekupe: nesneyi ayır, rötuşla; yumuşak gölgeli yeni arka plan ya da çıkartma yap
• Kırp, düzelt, Otomatik'e dokun ya da Ayarla'da bir vibe seç; 12'ye kadar kendi filtreni kaydet

PAYLAŞMAK İÇİN YAPILDI
• Hangi vibe? anketleri: arkadaşların gizli bir bağlantıyla iki fotoğraf arasında 24 saat boyunca A ya da B der, uygulama gerekmez
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

**Description, Mac** (3917/4000): made by `asc_metadata.py` from the text above. The section about widgets, the Lock Screen, the Dynamic Island, Control Center and the Action button gives way to this one, and “Canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı ve flaş da var” → “Mac'inin kamerasıyla canlı 80'ler, 90'lar ve Y2K efektleriyle çek; zamanlayıcı da var”; “iPhone ve iPad'de” → “iPhone, iPad ve Mac'te”; “Ayarlar › Apple Hesabı › Abonelikler'den” → “App Store uygulaması › adın › Hesap Ayarları › Abonelikler'den”.

```text
MAC'İNDE
• Kenar çubuğu, klavye kısayollu menü çubuğu ve sürükle bırak: düzenlemek için bir fotoğrafı pencereye bırak
```

**What's New** (653/4000; version 1.1, iOS and macOS)

```text
Aybuke 1.1 geldi ✨
• Retro Cam'de ışıma: canlı görünümler, parıltı ve hafif dudak ve allık tonu
• Otomatik kurgu: tek dokunuşla en iyi anlarından altyazılı 9:16 dikey video (günde bir ücretsiz)
• Hangi vibe? anketleri: arkadaşların gizli bir bağlantıyla iki fotoğraf arasında oy versin
• Gerçek arka plan bulanıklığıyla DSLR '12 efekti ve DSLR Portrait görünümü
• Makyaj Stüdyosu'nda artık 20 görünüm var
• Ayarla'da vibe'lar, kendi filtrelerin ve daha temiz Dekupe kenarları
• Yapay zekâ yardımcımız Aybik fikir ve açıklama yazmana yardım ediyor
• Ramazan ve Kurban Bayramı görünümleri, bayram günlerinde Keşfet'te
Bizimle ışıldadığın için teşekkürler!
```
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
