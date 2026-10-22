# Sahibe kalanlar (22 Ekim 2026)

Mac 1.0 reddi düzeltildi ve yeniden incelemede; iOS 1.0 incelemede. Aşağıdakiler yalnızca senin yapabileceğin adımlar (ödeme, sözleşme, konsol). Sırası önem sırasıdır.

## 1. AI bakiyeleri (App Review AI'ı deneyecek) — bugün

- **xAI:** https://console.x.ai › Billing: bakiye yükle (tahmini kalan 6,58 $; günlük üst sınır 60 ücretsiz iş ≈ 2,4–4,2 $). Aylık harcama limitini lansmanı kaldıracak kadar yükselt. Sonra Supabase SQL editöründe yeni bakiyeyi sent olarak yaz: `select public.ops_set_provider_balance('xai', <sent>);`
- **Anthropic:** https://platform.claude.com › Settings › Billing: ön ödemeli bakiye (tercihen otomatik yükleme) ve aylık harcama limiti. Bakiye biterse güvenlik kontrolü her işi durdurur ve iade eder.
- AI duraklarsa (takip görevi günde bir kontrol eder ve sana yazar): bakiyeyi yükle, sonra `select public.ops_resume_ai();`

## 2. TestFlight (`BETA_CONTRACT_MISSING`) — Apple'ın düzeltmesi gerekiyor

Uygulama tarafındaki her şey tamam: test bilgileri, lisans, şifreleme beyanı, son derlemelerin "What to Test" metinleri (22 Ekim'de dolduruldu). Hata Apple'ın sunucusunda; düzeltmesi için:

1. **Sözleşmeler:** https://appstoreconnect.apple.com › Business › Agreements: Free Apps ve Paid Apps "Active" olmalı; "View and Agree to Terms" ya da bekleyen Schedule 2/3 olmamalı (Apple 13 Ekim'de PLA ve Schedule 2/3'ü güncelledi). https://developer.apple.com/account sayfasında kabul bekleyen bir sözleşme bandı varsa kabul et.
2. **Destek talebini büyüt:** https://developer.apple.com/contact › Membership and Account › "Development and Technical" yerine **Distribution › TestFlight**; mümkünse telefonla görüşme iste. Mevcut talep: **102999056338**. Aşağıdaki metni yapıştır.
3. **Feedback Assistant** (https://feedbackassistant.apple.com) › TestFlight: aynı metinle bir rapor aç.

> Hello, TestFlight is broken for our team and only Apple can fix it. Team ID CBTKNY3LFC, app Aybuke (Apple ID 6822716008, bundle ID app.glowlit.ios), existing case 102999056338.
> - POST /v1/betaAppReviewSubmissions returns 422 ENTITY_UNPROCESSABLE.BETA_CONTRACT_MISSING for every build (latest attempt 22 Oct 2026 for macOS build 20261022.52), although every agreement in App Store Connect is active.
> - Internal testers get "The requested app is not available or doesn't exist" for every build, including builds signed with active profiles.
> - All three iOS 1.0 builds (20261015.838, .1056, .1225) were set to expired at 2026-10-15 19:36:20–19:37:06 UTC; the macOS builds from the same day were not.
> Please re-provision the beta contract for this team. Please also confirm that iOS 1.0 build 20261015.1225, which shows "expired" in TestFlight and is waiting for App Review, can still be reviewed and released.
> Thank you.

Apple düzelttiğini söylerse: 48 saat bekle, sonra takip görevi yeni derleme yüklemeyi sorar (Apple'ın bu hatadan sonraki önerisi).

## 3. Gerçek cihaz testi (TestFlight beklemeden)

iPhone'u Mac'e bağla, Xcode'da `ios/Glowlit.xcodeproj` › şema Glowlit › cihazını seç › Run (otomatik imza, Xcode'daki hesabınla). Scheme › Run › Options › StoreKit Configuration "None" yaparsan satın almalar Sandbox hesabıyla gerçek Apple sandbox'ından geçer. `docs/RELEASE-CHECKLIST.md` §5 ve §9: Apple ile giriş, kredi birleşmesi, "Verilerimi sil".

## 4. AdMob uygulama adı

https://admob.google.com › Apps › Aybuke › App settings: ad "Aybuke" mı? "Glowlit" ise değiştir. Privacy & messaging › European regulations › "Aybuke GDPR" önizlemesinde de "Aybuke" ve yeni ikon görünmeli. App Store'a bağlama 1.0 yayına girince (takip görevi yapar ya da sana tıklama listesi verir).

## 5. Senin kararın: "Bestie Polaroid"

"Polaroid" tescilli bir marka; bir görünüm adı olarak uygulamada, mağaza ekran görüntülerinde (Mac sonuç ekranındaki fikir satırı, iPad ana sayfa) ve sitede (/trends/polaroid) geçiyor. Şimdiye kadar hiçbir inceleme işaretlemedi, risk düşük. Değiştirmek istersen (örn. "Bestie Instant"): uygulamada 12 dilde ad, ekran görüntülerinin bir kısmı ve sitedeki sayfa birlikte değişmeli; 1.1'den sonraki güncellemeye bırakmayı öneririm. ("LinkedIn-ready in seconds" alt başlığı 1.1'de "Profile-ready in seconds" oldu.)

## 6. İsteğe bağlı: eski GitHub Pages kopyası

`riosenbeq.github.io/aybuke-app` artık aybuke.org'a yönlendiriyor ve arama motorlarına kapalı. Tamamen kapatmak istersen: GitHub › RiosenBeq/aybuke-app › Settings › Pages › Unpublish.
