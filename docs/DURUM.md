# Aybuke — iş durumu (22 Ekim 2026)

Bu oturumun açık işleri. Bir sonraki devamda buradan başlayın; ayrıntı `AGENTS.md` §6'da.

## Mac 1.0 reddi ve yeniden gönderim (22 Ekim 2026)

- **Ret (21 Ekim):** Mac 1.0 (20261015.1233) Guideline 2.3.8 ile reddedildi. Kurulu uygulamanın adı Finder'da, menü çubuğunda ve About/Hide/Quit'te "Glowlit"ti, mağazadaki ad "Aybuke: AI Photo Editor". Neden: uygulama hedefinin `PRODUCT_NAME`'i hedef adıydı (Glowlit.app, çalıştırılabilir dosya ve `CFBundleName` "Glowlit"); String Catalog'daki İngilizce `CFBundleName` "new" durumunda olduğu için `en.lproj/InfoPlist.strings` hiç üretilmiyordu.
- **Düzeltme:** `PRODUCT_NAME = Aybuke` (Aybuke.app, çalıştırılabilir dosya, `CFBundleName`), `PRODUCT_MODULE_NAME = Glowlit` (Swift modülü aynı), Bundle ID aynı. 1.0 kodu üzerine `release/1.0-name-fix` dalı (`98fc3ce`, `4b6c9fa` + düzeltme), ana dalda `cc35859`. Mac'te çalıştırılarak doğrulandı: menü çubuğu "Aybuke".
- **Yeniden gönderildi (22 Ekim 00:50), sonra bir kez daha (02:30):** önce 20261022.26 ile gönderildi. Ardından 15 ajanlı bir ön inceleme denetimi iki gerçek sorun buldu, gönderim incelemeye alınmadan çekildi ve düzeltildi: (1) Ayarlar › Manage subscription, Mac Catalyst'te desteklenmeyen StoreKit sayfasını açıyordu; artık Mac'te App Store'un abonelik sayfasını açıyor (ödeme ekranı ve deneme hatırlatıcısı da Mac'te App Store yolunu söylüyor). (2) Abonelikler ve paketler yalnızca iOS gönderiminde; Mac önce onaylanıp kendiliğinden yayına girse satın alınacak bir şey olmazdı. Mac 1.0 artık **MANUAL** yayında: onaylanınca bekler, abonelikler ve paketler APPROVED olunca takip görevi yayına alır. Şu an Mac 1.0 derleme **20261022.209** (`release/1.0-name-fix` @ `4697549`) ile `WAITING_FOR_REVIEW`; inceleme notunun başında iki düzeltme yazıyor.
- **iOS 1.0 değişmedi, sırada kalıyor:** incelemedeki derleme (20261015.1225) iPhone ve iPad'de her yerde "Aybuke" gösteriyor (ana ekran ve iPadOS 26 menü çubuğu `CFBundleDisplayName` kullanıyor; simülatörde 1.0 adlandırmasıyla denendi). Çekip yeniden göndermek 7 günlük sırayı ve sürüme bağlı abonelik/paket öğelerini riske atardı. Yedek: aynı düzeltmeyle iOS 1.0 derlemesi **20261022.46** yüklendi; Apple iOS 1.0'ı herhangi bir nedenle (ör. "expired" görünen derleme) reddederse bu derlemeyle hemen yeniden gönderilir.

- **Ön inceleme denetimi (22 Ekim):** 7 alan (Mac incelemesi, ad tutarlılığı, iOS 1.0 riskleri, App Store Connect meta verisi, TestFlight, site ve yasal bağlantılar, ad değişikliğinin yan etkileri), her bulgu ayrı bir ajanla doğrulandı. 1.1'de düzeltilenler: Mac'te abonelik yönetimi ve Fotoğraflar izni metni/düğmesi; "glowlit-carousel" dosya adı; Pro Headshot alt başlığında LinkedIn yerine "Profile-ready in seconds" (12 dil, backend kataloğu, site); yasal metinlerde "Türkiye, Türkiye" tekrarı (uygulama, site); 1.1 What's New'daki emoji (App Store Connect reddediyor) ve `asc_metadata.py --check` artık emojiyi yakalıyor, What's New hatası sessizce yutulmuyor; 1.1 inceleme notlarında AI duraklaması ve Mac kamerası; eski GitHub Pages kopyası aybuke.org'a yönleniyor; `release-manual.zsh` adı Aybuke olmayan derlemeyi yüklemiyor. Site: App Store bayrağı (`onAppStore`) açılınca 12 dilde tüm "yakında / erken erişim" metinleri ve akıllı uygulama bandı değişiyor. Sahibe kalanlar: [`SAHIP-22-EKIM.md`](SAHIP-22-EKIM.md).

## Yapıldı

- **1.0 incelemede** (iOS `WAITING_FOR_REVIEW`, AFTER_APPROVAL; Mac `WAITING_FOR_REVIEW`, MANUAL). Onay gelince 1.1 **güncelleme** olarak gönderilir. İncelemedeki iOS 1.0 derlemesi (20261015.1225) App Store Connect'te "expired" görünüyor; bu Apple'ın TestFlight hatasından (BETA_CONTRACT_MISSING, aynı dakikada üç iOS 1.0 derlemesi), imzadan değil. Apple reddederse yedek 20261022.46 ile aynı gönderim (2e624a70, IAP öğeleri içinde) yeniden gönderilir.
- **1.1 kodu:** anketler ("Which vibe?", uygulama + sunucu + aybuke.org/p/…), Glow Cam, video Auto edit, DSLR '12 / DSLR Portrait, Adjust vibe'ları ve My filters, 20 makyaj görünümü, Cut out / Erase iyileştirmeleri, editör zoom'u, paylaşım boyutları, Aybik (Claude yazı yardımı; arayüzde "Claude" ve şirket adı geçmez), ülkeye özel mevsimler, inceleme düzeltmeleri, politika (anket sorusu) düzeltmeleri.
- **Sunucu (Supabase):** migrasyonlar `20261103000001`'e kadar canlı; `ai-image`, `assist`, `polls`, `owner-digest` güncel. xAI bakiye tahmini 8,13 $ (taban 5–6 $).
- **İmza:** geçersiz profiller silindi; aktif: "Aybuke App Store 2", "Aybuke Mac Catalyst App Store 2", iki widget profili. Yükleme betiği profilleri derlemeden önce kontrol eder.
- **TestFlight:** iOS 1.1 (20261016.1326) ve Mac 1.1 (20261016.1350) "Aybuke Team" grubunda; riosenbeq@icloud.com test grubunda.
- **Mağaza görselleri:** 1.1 iPhone ekran görüntüleri 12 dilde (`docs/marketing/app-store/<dil>/`, commit `91adf3c`).
- **Web sitesi (RiosenBeq/aybuke):** 1.1 özellikleri "Sonraki güncellemede" etiketleriyle (`src/data/release.json` → `liveVersion`), 19 görünüm örneği, yasal metinler eşit.

## Son durum (17 Ekim 03:30)

Final 1.1 builds: iOS 20261022.234, Mac 20261022.244 (commit `d105a12`, CI yeşil; imza profilleri ACTIVE; "What to Test" dolu, "Aybuke Beta" grubunda). Daha eski 1.1 derlemeleri 22 Ekim düzeltmelerini içermez; Mac 20261017.821 ve öncesinde uygulamanın adı "Glowlit": hiçbiri gönderilmez.

- **Sonra eklenenler (17 Ekim sabah):** ilk kayıt ve ilk ankette tek seferlik ışıltı (`Milestones`), yükleme parıltıları, 44 pt dokunma alanları, satın alma kartlarında basma efekti; admin paneli Filament tarzı ve `info@nextgenlab.com.tr` e-posta/şifre girişiyle (Supabase Auth, `ADMIN_EMAILS`; anahtar girişi yedek); sahibe giden mailler açık/koyu temaya uygun yeni tasarımda; site kartları yeni tasarım ve 15 yeni görsel (xAI bakiye tahmini 6,58 $).

- **Bu derlemelerde ek olarak:** anket küçük resimleri My Works gibi dosya korumalı; "Verilerimi sil" Enhance ipucunu da sıfırlıyor; Image Playground sonucu ve Erase'in tam boy maskesi ana iş parçacığı dışında işleniyor.
- **Admin paneli:** https://aybuke.org/admin (noindex, no-store, sıkı CSP) → `functions/admin` (JWT açık + `x-admin-token`; sunucuda yalnızca `ADMIN_TOKEN_SHA256`; 5 yanlış denemede 15 dk kilit; işlemler bir yıl denetim kaydında). Anahtar yalnızca sahibin Mac'inde: `~/.config/aybuke/admin-token` (600). Migrasyon `20261105100000_admin_api.sql` canlı.
- **aybuke.org (site repo `ac34bcd`):** Poppins + Inter (kendi sunucumuzda), uygulamayla aynı köşe ölçüsü, cam kartlar, kaydırma animasyonları, her dilde "kısaca Aybuke" kutusu, yeni 404 ve /maintenance, güvenlik başlıkları (HSTS preload, CSP, DENY), Organization + SoftwareApplication yapılandırılmış veri, llms.txt kısa cevaplar. `release.json`: `onAppStore` (1.0 yayına girince) ve `liveVersion` (1.1 yayına girince).

## Önceki durum (17 Ekim 00:30)

- **1.1 tamam ve TestFlight'ta:** iOS 1.1 (20261016.2312), Mac 1.1 (20261016.2317), profiller ACTIVE. İçinde: Enhance (Quick fix + 4 AI modu), 18+ Soft skin, Aybik'in dört yeni özelliği (look finder, anket soruları, kart yazısı, Aybik'e sor), harf harf açılış animasyonu.
- **GitHub:** `main` = `63e4bc4` (CI yeşil). Sunucu: migrasyonlar `20261104000000`'e kadar canlı, `assist` güncel. xAI bakiye tahmini 7,83 $.
- **Mağaza varlıkları hazır (repo):** 12 dilde iPhone/iPad/Mac ekran görüntüleri, İngilizce/Türkçe yıl boyu önizleme videoları (`docs/marketing/app-preview/`), 13 dilde metinler ve 1.1 inceleme notları; araçlar `--version 1.1` alır (`scripts/asc/README.md`).
- **aybuke.org yenilendi** (site repo `c2b4e80`, `3183467`, `84cfc49`): harf harf wordmark, CSS telefon, karanlık mod, /photo-enhancer sayfası, yasal metinler eşit.
- **aybuke.org kısaltıldı (17 Ekim):** 12 dilin ana sayfaları telefonda ~5.400–5.900 px (önce 9.300–12.400), masaüstünde ~6.100–6.400 px (önce 14.000–19.500); özellik sayfaları ~4.000–4.400 px; "Bölüme atla", "Başa dön", sabit üst barda logo, karanlık mod kontrastı; 11 dile kendi SSS sayfası (/tr/faq …); 144 sayfa 200, axe 0 sorun. Açık küçük iş: /aybik sayfası telefonda 4.604 px (hedef 4.500).

## Bekliyor

1. **1.0 onayı** (iOS + Mac `WAITING_FOR_REVIEW`). Takip görevi her platformu ayrı ele alır: onaylanan platformun 1.1'ini gönderir; Mac onaylanırsa abonelikler ve paketler APPROVED olunca Mac'i yayına alır. Elle yapmak gerekirse: `asc_metadata.py .. --version 1.1 --review-notes`, `asc_screenshots.py .. --version 1.1`, `asc_previews.py .. --version 1.1` (diğer platformun 1.0'ı hâlâ incelemedeyse yalnızca bu platformun 1.1 kaydını açıp `--version <id>` verin), final derlemeleri bağla, AFTER_APPROVAL, incelemeye gönder.
2. **iOS 1.0 yayına girince sitede ve AdMob'da:** `src/data/release.json` → `"onAppStore": true`, build, push (tüm "yakında" metinleri, App Store düğmeleri ve akıllı bant buna göre değişir); AdMob uygulamasını mağaza kaydına bağla. Yalnızca Mac onaylanırsa site değişmez.
3. **1.1 yayına girince:** sitede `src/data/release.json` → `"liveVersion": "1.1"`, build, push; sahip onaylarsa `PROMPT_POLISH` açılır.

## TestFlight (17 Ekim 01:00)

- Kurulum hatası ("The requested app is not available or doesn't exist") ve 15 Ekim'de iOS derlemelerinin birden "expired" olması Apple tarafındaki bilinen **BETA_CONTRACT_MISSING** hatasından: dış test incelemesine gönderim API'de 422 `ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING` dönüyor, oysa tüm sözleşmeler aktif. Apple Developer Destek'e talep açıldı: **Case ID 102999056338** (Distribution › TestFlight). Apple düzeltince: "Aybuke Beta" grubu (herkese açık bağlantı https://testflight.apple.com/join/NRjm1BFq, en çok 200 kişi) için final 1.1 derlemeleri (yukarıdaki "Final 1.1 builds" satırı) dış beta incelemesine gönderilir; riosenbeq@icloud.com iki grupta da. Apple düzelttiğini söylerse 48 saat sonra yeni derleme yüklemek gerekebilir (Apple'ın bu hatadan sonraki önerisi); TestFlight ancak gerçek bir kurulum çalışınca düzelmiş sayılır.
- Beta lisans metni ve test bilgileri dolu; "What to Test" (EN/TR) final derlemelere 22 Ekim'de girildi. "Aybuke Beta"dan Glowlit adlı eski Mac 1.1 derlemeleri çıkarıldı.
- **22 Ekim 03:00:** beta incelemesine gönderim artık `BETA_CONTRACT_MISSING` değil, genel 422 "Please try again later." dönüyor (eski ve yeni derlemelerde aynı). Apple tarafında bir değişiklik olabilir; takip görevi denemeye devam ediyor.

## Otomatik takip (17 Ekim)

Claude uygulamasında kalıcı zamanlanmış görev **"Aybuke yayın ve TestFlight takibi"** (`aybuke-release-watch`, 3 saatte bir; kenar çubuğu › Scheduled). Her platformun 1.0'ı onaylanınca o platformun 1.1'ini ("Final 1.1 builds" satırındaki derlemeyle) metin, görsel ve videolarıyla güncelleme olarak gönderir; Mac onaylanınca abonelikler onaylanana kadar yayını bekletir; iOS yayına girince AdMob'u bağlar ve sitedeki App Store bayrağını açar; iOS 1.0 onaylanana kadar günde bir AI duraklamasını kontrol eder; 1.1 yayına girince sitede `liveVersion` "1.1" yapar; TestFlight beta incelemesini her seferinde yeniden dener. Oturumdaki eski cron işleri silindi (çift gönderim olmasın). Uygulama kapalıyken zamanı gelen çalışma, uygulama açılınca yapılır.

## aybuke.org görselleri (17 Ekim 16:45)

Site repo `57bf0b7` (Vercel'de yayında, 144 sayfa 200, axe 0 sorun, IndexNow bildirildi): menüdeki "01 Magic Edit" kartı boş degrade yerine Pink Hair örneğini koyu bir perdeyle gösteriyor (karanlık modda okunmayan beyaz alt yazı düzeldi); Which vibe?, Retro effects ve Video editor sayfalarının üstünde çizim yerine uygulamanın gerçek ekranları, saç rengi sayfasında Pink Hair önce/sonra kaydırıcısı, görselsiz son kart (Adjust vibes) Adjust ekranıyla. Yeni görsel üretilmedi (xAI harcaması yok); hepsi mevcut gerçek ekranlar ve örnek fotoğraflar.

Ardından site repo `f3e1430`: özellik kartlarında hover'da karanlık modda pembeleşip kaybolan etiket ("AI PHOTO EDITOR" vb.) düzeldi; geniş ekranda açıklamalar kesilmeden tam, kartlarda dönen yuvarlak "aç" düğmesi, "Coming in the next update" yumuşak etiket. Açık temada ferahlık: özellik turu ve özellik sayfalarının okuma bölümü pembeden beyaza geçen bantlar, hero görsellerinin arkasında beyaz ışık, SSS beyaz kartta, çipler, ikincil düğmeler ve fiyat kartları beyaz. Karanlık mod aynı. 144 sayfa 200, axe 0 sorun.

Site repo `a4fb2aa`: sahibin adı yalnızca yasal metinlerde (Kullanım Koşulları, Gizlilik, AUP, KVKK, Künye; veri sorumlusunun kimliği yasal zorunluluk). Altbilgi "© 2026 Aybuke", ana sayfalardaki "Yapan" bilgisi 12 dilde "İstanbul'da bağımsız bir geliştirici", llms.txt ve yapılandırılmış veride yayıncı Aybuke (Organization). Uygulamanın içindeki yasal metinler değişmedi (yeni derleme gerekmez).

## Sahibe kalanlar

- **Önce:** [`SAHIP-22-EKIM.md`](SAHIP-22-EKIM.md): xAI ve Anthropic bakiyesi (App Review AI'ı deneyecek), Apple'a TestFlight için hazır mesaj, sözleşme kontrolü, Xcode ile cihaz testi, AdMob adı, "Bestie Polaroid" kararı.
- xAI anahtarını yenilemek (sohbete yazıldı); yenisi sunucuya `read -s` ile girilir.
- Avukatla KVKK/DPA kontrolü.
