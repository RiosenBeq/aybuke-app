# Aybuke — iş durumu (17 Ekim 2026, 00:30)

Bu oturumun açık işleri. Bir sonraki devamda buradan başlayın; ayrıntı `AGENTS.md` §6'da.

## Yapıldı

- **1.0 incelemede** (iOS + macOS, `WAITING_FOR_REVIEW`, onaylanınca otomatik yayında). Sahibin kararı: 1.0'a dokunulmaz; onay gelince 1.1 **güncelleme** olarak gönderilir. Not: incelemedeki iOS 1.0 derlemesi (20261015.1225) eski, geçersizleşmiş profille imzalı ve App Store Connect'te "expired" görünüyor; Apple reddederse yeni imzalı derlemeyle hemen yeniden gönderilir.
- **1.1 kodu:** anketler ("Which vibe?", uygulama + sunucu + aybuke.org/p/…), Glow Cam, video Auto edit, DSLR '12 / DSLR Portrait, Adjust vibe'ları ve My filters, 20 makyaj görünümü, Cut out / Erase iyileştirmeleri, editör zoom'u, paylaşım boyutları, Aybik (Claude yazı yardımı; arayüzde "Claude" ve şirket adı geçmez), ülkeye özel mevsimler, inceleme düzeltmeleri, politika (anket sorusu) düzeltmeleri.
- **Sunucu (Supabase):** migrasyonlar `20261103000001`'e kadar canlı; `ai-image`, `assist`, `polls`, `owner-digest` güncel. xAI bakiye tahmini 8,13 $ (taban 5–6 $).
- **İmza:** geçersiz profiller silindi; aktif: "Aybuke App Store 2", "Aybuke Mac Catalyst App Store 2", iki widget profili. Yükleme betiği profilleri derlemeden önce kontrol eder.
- **TestFlight:** iOS 1.1 (20261016.1326) ve Mac 1.1 (20261016.1350) "Aybuke Team" grubunda; riosenbeq@icloud.com test grubunda.
- **Mağaza görselleri:** 1.1 iPhone ekran görüntüleri 12 dilde (`docs/marketing/app-store/<dil>/`, commit `91adf3c`).
- **Web sitesi (RiosenBeq/aybuke):** 1.1 özellikleri "Sonraki güncellemede" etiketleriyle (`src/data/release.json` → `liveVersion`), 19 görünüm örneği, yasal metinler eşit.

## Son durum (17 Ekim 00:30)

- **1.1 tamam ve TestFlight'ta:** iOS 1.1 (20261016.2312), Mac 1.1 (20261016.2317), profiller ACTIVE. İçinde: Enhance (Quick fix + 4 AI modu), 18+ Soft skin, Aybik'in dört yeni özelliği (look finder, anket soruları, kart yazısı, Aybik'e sor), harf harf açılış animasyonu.
- **GitHub:** `main` = `63e4bc4` (CI yeşil). Sunucu: migrasyonlar `20261104000000`'e kadar canlı, `assist` güncel. xAI bakiye tahmini 7,83 $.
- **Mağaza varlıkları hazır (repo):** 12 dilde iPhone/iPad/Mac ekran görüntüleri, İngilizce/Türkçe yıl boyu önizleme videoları (`docs/marketing/app-preview/`), 13 dilde metinler ve 1.1 inceleme notları; araçlar `--version 1.1` alır (`scripts/asc/README.md`).
- **aybuke.org yenilendi** (site repo `c2b4e80`, `3183467`, `84cfc49`): harf harf wordmark, CSS telefon, karanlık mod, /photo-enhancer sayfası, yasal metinler eşit.
- **aybuke.org kısaltıldı (17 Ekim):** 12 dilin ana sayfaları telefonda ~5.400–5.900 px (önce 9.300–12.400), masaüstünde ~6.100–6.400 px (önce 14.000–19.500); özellik sayfaları ~4.000–4.400 px; "Bölüme atla", "Başa dön", sabit üst barda logo, karanlık mod kontrastı; 11 dile kendi SSS sayfası (/tr/faq …); 144 sayfa 200, axe 0 sorun. Açık küçük iş: /aybik sayfası telefonda 4.604 px (hedef 4.500).

## Bekliyor

1. **1.0 onayı** (iOS + Mac `WAITING_FOR_REVIEW`). Bu oturumdaki 2 saatlik takip görevi onay gelince AdMob'u bağlar ve 1.1'i güncelleme olarak gönderir. Oturum kapanırsa yeniden kurun: durum kontrolü → onaylıysa `asc_metadata.py .. --version 1.1 --review-notes`, `asc_screenshots.py .. --version 1.1`, `asc_previews.py .. --version 1.1`, derlemeleri bağla, AFTER_APPROVAL, incelemeye gönder.
2. **1.0 yayına girince sitede:** "henüz App Store'da değil / e-postayla erken erişim" metnini ve "Uygulamayı indir" düğmelerini App Store bağlantısına çevir.
3. **1.1 yayına girince:** sitede `src/data/release.json` → `"liveVersion": "1.1"`, build, push; sahip onaylarsa `PROMPT_POLISH` açılır.

## TestFlight (17 Ekim 01:00)

- Kurulum hatası ("The requested app is not available or doesn't exist") ve 15 Ekim'de iOS derlemelerinin birden "expired" olması Apple tarafındaki bilinen **BETA_CONTRACT_MISSING** hatasından: dış test incelemesine gönderim API'de 422 `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING` dönüyor, oysa tüm sözleşmeler aktif. Apple Developer Destek'e talep açıldı: **Case ID 102999056338** (Distribution › TestFlight). Apple düzeltince: "Aybuke Beta" grubu (herkese açık bağlantı https://testflight.apple.com/join/NRjm1BFq, en çok 200 kişi) için 1.1 (20261016.2312 iOS, .2317 macOS) dış beta incelemesine gönderilir; riosenbeq@icloud.com iki grupta da.
- Beta lisans metni, test bilgileri ve "What to Test" (EN/TR) dolduruldu.

## Sahibe kalanlar

- Çöp Sepeti'ni boşaltmak (Cursor ve VN verileri, ~14 GB).
- xAI anahtarını yenilemek (sohbete yazıldı); yenisi sunucuya `read -s` ile girilir.
- Avukatla KVKK/DPA kontrolü; gerçek cihazda TestFlight denemesi.
