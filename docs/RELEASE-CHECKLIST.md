# Aybuke: yayın öncesi gerçek cihaz kontrol listesi

> **Amaç:** App Review'a göndermeden önce Aybuke'yi kendi iPhone'unda (ve Mac'inde), TestFlight derlemesiyle ve canlı backend'e (Supabase + xAI, Claude güvenlik denetimiyle) karşı uçtan uca denemek. Liste koddan çıkarıldı: ekran adları, düğmeler ve beklenen davranış uygulamadaki gibidir. **Submit for Review** yalnızca sahibin açık onayıyla yapılır (§14).
>
> **Durum (15 Ekim 2026, akşam):** iOS 1.0 (derleme `20261015.1225`) abonelik grubu, iki abonelik ve iki paketle, macOS 1.0 (derleme `20261015.1233`) ile birlikte App Review'a gönderildi; ikisi de WAITING_FOR_REVIEW, yayın türü AFTER_APPROVAL. Backend canlı (migrasyonlar `20261030000000`'ye kadar, yedi fonksiyon), Apple ile giriş açık, xAI Zero Data Retention açık, App Privacy yayında. Bu liste artık onaydan önce ya da sonra TestFlight derlemesiyle yapılacak isteğe bağlı cihaz testidir; TestFlight iç grubu "Aybuke Team" hazır. Açık sahip işleri: [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md).

**Nasıl kullanılır**

- Her madde üç parçadan oluşur: **Yap** (ne yapacaksın), **Beklenen** (ne olmalı), **Sorun olursa** (ne not alacaksın). Tutmayan maddenin kutusunu boş bırak, §13'teki şablonla not al ve devam et.
- Her maddenin başındaki durum etiketi: *[tamam]* depoda ya da origin/main'de doğrulandı; *[yerelde doğrulandı]* kod ve testler bu depoda kontrol edildi, yine de cihazda çalıştırılmalı; *[yalnızca sahip]* sahibin hesabı, konsolu ya da gerçek cihazı gerekir; *[açık]* yapılmadı ya da bir karar bekliyor, neyin engellediği etikette yazılı. **Doğrulanamadı:** satırı, bu depodan kanıtlanamayan her şeyi gösterir.
- Uygulama etiketleri İngilizce arayüzdeki haliyle **kalın**, Türkçe arayüzdeki karşılığı parantez içinde *italik* yazıldı. Örnek: **Delete my data & account** (*Verilerimi ve hesabımı sil*). iOS'un kendi menülerinin Türkçe adları sürüme göre biraz değişebilir.
- Sekmeler: **Explore** (*Keşfet*), **Create** (*Oluştur*), **Edit** (*Düzenle*), **My Works** (*Eserlerim*). **Settings** (*Ayarlar*), Explore'un sağ üstündeki dişliyle açılır (Mac'te Aybuke › Settings…).
- Her notta derleme numarasını yaz: **Settings › Version** (*Sürüm*), ör. `1.0 (20261014.1530)`. Bu satır `CFBundleShortVersionString` ile `CFBundleVersion` değerini yan yana gösterir.
- Sunucuyu doğrulamak için Supabase panosunu açık tut (§1.6). Uygulamadaki sayı ile sunucudaki sayı farklıysa sunucu doğrudur.

**Önerilen sıra:** §1 hazırlık → §2 ilk açılış (yetişkin) → §3 ücretsiz kredilerle yapay zekâ → §4 satın almalar → §5 hesap → §6–7 cihaz üstü özellikler ve sistem entegrasyonları → §8 yaş yolları → §9 verileri silme (en son) → §10 Mac → §11 App Store Connect → §14 onay. Sıra önemli, çünkü:

- Ücretsiz deneme ile ilk ay $1.99 aynı abonelik grubundadır. Bir Apple Hesabı bu gruptaki tanıtım tekliflerinden **yalnızca birini** kullanabilir; ikisini de denemek için satın alma geçmişini sıfırlaman ya da ikinci bir hesap kullanman gerekir (§1.3–1.4).
- Yaş bandı istediğin zaman küçültülebilir ama kendi beyanınla büyütülemez (yılda bir). Geri dönmenin yolu §9'daki silmedir.

**Gönderim durumu (özet):** 15 Ekim 2026'da gönderildi (§14). Kapananlar: Supabase (migrasyonlar, yedi fonksiyon, gizli değerler, cron), Claude güvenlik denetimi, xAI Zero Data Retention, Apple ile giriş anahtarları (§5, §12-3), derlemeler ve ürünlerin sürüme bağlanması, ekran görüntüleri, App Privacy (§11). Açık kalanlar: xAI ve Anthropic harcama limitleri ve bakiye, xAI anahtarının döndürülmesi, RevenueCat silme anahtarı (§9.5, §12-4, isteğe bağlı) ve cihaz testi (bu liste).

---

## 1. Hazırlık

### 1.1 Ön koşullar (bunlar yoksa satın alma ve yapay zekâ testleri anlamsız)

- [ ] **Paid Apps Agreement etkin** *[yalnızca sahip; açık]*
  - Yap: App Store Connect › Business (Agreements, Tax, and Banking) › Paid Apps.
  - Beklenen: Durum **Active**. Apple'ın sandbox belgesine göre bu sözleşme imzalanmadan sandbox'ta satın alma test edilemez; paywall'da **Subscriptions are unavailable right now.** (*Abonelikler şu anda kullanılamıyor.*) görünür.
  - Sorun olursa: Durumu not et; §4'ü ertele, diğer bölümlerle devam et.
  - Doğrulanamadı: sözleşmenin ve banka/vergi bilgilerinin durumu bu depodan görülemez.
- [x] **Dört ürün tanımlı ve "Ready to Submit"** *[yapıldı 15 Ekim 2026: dördü iOS 1.0 ile incelemeye gönderildi]*
  - Yap: App Store Connect › Aybuke › Subscriptions (grup **Aybuke Pro**: `app.glowlit.pro.yearly`, `app.glowlit.pro.monthly`) ve In-App Purchases (`app.glowlit.credits.30`, `app.glowlit.credits.100`).
  - Beklenen: Yıllıkta 1 hafta ücretsiz deneme, aylıkta 1 ay $1.99 tanıtım fiyatı; en-US ve tr metinleri ve fiyatlar dolu. Yerel ürün dosyası (`ios/StoreKit/Products.storekit`) aynı kimlikleri ve fiyatları taşır: yıllık $39.99 (deneme P1W), aylık $5.99 (ilk dönem $1.99), 30 kredi $2.99, 100 kredi $7.99. Ürün bilgisindeki değişikliklerin sandbox'a yansıması bir saati bulabilir.
  - Sorun olursa: "Missing Metadata" olanı not et. Uygulama dört ürünün hepsini bekler: eksik ürün listede görünmez; hiç plan ya da hiç paket yüklenmezse "unavailable" yazısı ve **Try again** çıkar.
- [x] **Backend canlı, derleme demo modunda değil** *[yapıldı 15 Ekim 2026: migrasyonlar `20261030000000`'ye kadar, yedi fonksiyon (`owner-digest` dahil), üç cron işi; gerçek bir Magic Edit uçtan uca 12 sn'de geçti. TestFlight bandı kontrolü sahipte]*
  - Yap: Supabase projesi `efapupjvidyqhqdevmcu` › Edge Functions: `ai-image`, `credits-redeem`, `account`, `report`, `ad-reward` yayında (aşağıdaki iki madde). SQL Editor'da `select jobname, schedule from cron.job;` → `sweep-jobs` `*/5 * * * *`, `sweep-ad-rewards` `17 * * * *`, `revenuecat-deletions` `17 * * * *`. `revenuecat-deletions` zamanlaması Vault'taki `project_url` ve `service_role_key` adlarını kullanır; değerleri hiçbir yere yazma.
  - Beklenen: TestFlight derlemesinde Explore'da **Preview build: AI results are samples** bandı **yok**, sonuçlarda "DEMO PREVIEW" damgası yok.
  - Sorun olursa: Bant görünüyorsa derleme demo modundadır; bu derleme incelemeye asla gönderilmez.
- [x] **Sunucu gizli değerleri** (yalnızca adlarına bak, değerleri hiçbir yere yazma) *[yapıldı 15 Ekim 2026: XAI_API_KEY, ANTHROPIC_API_KEY, APPLE_APP_ID, APPLE_BUNDLE_ID, APPLE_TEAM_ID, ADMOB_REWARDED_AD_UNIT, APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY, RESEND_API_KEY, DIGEST_SECRET, OWNER_ALERT_TO var; kaldırılacak ad yok]*
  - Yap: Supabase › Edge Functions › Secrets.
  - Beklenen: `XAI_API_KEY`, `APPLE_BUNDLE_ID` (`app.glowlit.ios`), `APPLE_TEAM_ID` (`CBTKNY3LFC`), `APPLE_APP_ID` (`6822716008`) ve `ADMOB_REWARDED_AD_UNIT` var. `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` giriş açık olduğu için gerekli (§5; silmede token iptali), `REVENUECAT_SECRET_KEY` ve `REVENUECAT_PROJECT_ID` ise hesap silmede RevenueCat müşterisini silmek için (§9.5) gerekir. `ANTHROPIC_API_KEY` de var (Claude güvenlik denetimi; `ANTHROPIC_SAFETY_MODEL` boş kalabilir, varsayılan `claude-haiku-5-5`). `FAL_KEY` ve `XAI_SAFETY_MODEL` yok (karar: Claude, §12-5). `OUTPUT_MODERATION` artık okunmuyor: ekleme, varsa sil. `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS` üretimde olmamalı; varsa sil (hosted projede yok sayılır ve log'a yazılır).
  - Sorun olursa: Eksikleri listele. `APPLE_APP_ID` yoksa App Store kurulumlarında ücretsiz krediler kapalı kalır (kurulum kanıtı maddesi). §9'daki ilgili maddeler eksik anahtarla başarısız olur.
- [x] **xAI Zero Data Retention açık** (15 Ekim 2026'da xAI konsolunda Team › Zero Data Retention: Active)
  - Yap: console.x.ai › ekip ayarları.
  - Beklenen: Açık. Onay ekranı ve gizlilik politikası "1 saat içinde silinir" diyor.
  - Doğrulanamadı: Zero Data Retention durumu bu depodan kanıtlanamaz (`docs/SUPABASE-TODO.md` §7).
- [x] **Veritabanı geçişleri (sırayla)** *[yapıldı 15 Ekim 2026: 20261019000000–20261025000003, on iki dosya, her biri kendi transaction'ında, hatasız; MAC-YAYIN 5.2 sorgusu 19/19; ardından 20261026000000–20261030000000 de uygulandı]*
  - Yap: Önce iki eski geçişin durumuna bak. SQL Editor'da:
    ```sql
    select to_regclass('public.pending_revenuecat_deletions');
    select proname from pg_proc where proname in ('settle_unconfirmed', 'deliver_outputs', 'cancel_job', 'fail_job', 'sweep_jobs');
    ```
    İlk sorgu `20261018000000`, ikincisi `20261017000000`'in nesnelerini kontrol eder; ikinci sorgu beş adı da döndürmeli. Eksikse ilgili dosyayı önce uygula. Sonra `backend/supabase/migrations/` içindeki şu dokuz dosyayı bu sırayla, her birini kendi `begin;` ... `commit;` bloğunda çalıştır: `20261019000000_ad_rewards.sql`, `20261019500000_keepalive.sql`, `20261020000000_credit_policy_v2.sql`, `20261021000000_install_and_subscription_credits.sql`, `20261022000000_abuse_controls.sql`, `20261023000000_ad_rewards_per_install.sql`, `20261024000000_private_rls.sql`, `20261024000001_abuse_fixes.sql`, `20261024000002_entitlement_order.sql`. Dosyaların içinde kendi transaction ifadesi yok (bu depoda kontrol edildi), bu yüzden sarmalamak güvenli.
  - Beklenen: Her dosya hatasız biter. Zamanlamalar §1.1'deki "Backend canlı" maddesinde.
  - Sorun olursa: Dur; hatanın dosya adını ve metnini not et. Sonraki dosyaya geçme, başarısız dosyayı ikinci kez çalıştırma.
  - Not: `docs/SUPABASE-TODO.md` §3 yalnızca `20261019500000`'a kadar listeliyor; bu maddedeki liste esastır.
- [x] **Edge Functions yayımı** *[yapıldı 15 Ekim 2026: altı fonksiyon ACTIVE, ardından `owner-digest`; ad-reward ve app-store-notifications JWT doğrulaması kapalı]*
  - Yap: Mac'te Terminal, repo içinde `backend` klasöründe, `supabase login` ile kendi hesabınla giriş yaptıktan sonra komutları ayrı ayrı çalıştır:
    ```
    supabase functions deploy ai-image --project-ref efapupjvidyqhqdevmcu --use-api
    supabase functions deploy credits-redeem --project-ref efapupjvidyqhqdevmcu --use-api
    supabase functions deploy account --project-ref efapupjvidyqhqdevmcu --use-api
    supabase functions deploy report --project-ref efapupjvidyqhqdevmcu --use-api
    supabase functions deploy ad-reward --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
    supabase functions deploy app-store-notifications --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
    supabase functions deploy owner-digest --project-ref efapupjvidyqhqdevmcu --use-api
    ```
  - Beklenen: Yedi fonksiyon yayımlanır. `ad-reward` ve `app-store-notifications` JWT doğrulaması kapalı olmalı; AdMob'un ve Apple'ın çağrısında JWT yoktur, fonksiyonlar imzayı kendileri doğrular. `owner-digest`te JWT doğrulaması açık kalır (kendi `DIGEST_SECRET`'ı da var).
  - Sorun olursa: Komutun çıktısını not et. `ai-image` ve `account`, yukarıdaki geçişler uygulanmadan yayımlanmaz.
  - Doğrulanamadı: `--use-api` bayrağı bu ortamda Supabase CLI kurulu olmadığı için denenmedi; komutlar sahibin notundan (`docs/SAHIP-YAPILACAKLAR.md` §1.6) alındı.
- [ ] **Kurulum kanıtı** (ücretsiz krediler doğrulanmış bir App Store kurulumuna bağlı) *[yalnızca sahip; yerelde doğrulandı]*
  - Yap: §1.5'teki temiz kurulumdan sonra TestFlight derlemesini yeniden kur ve Settings › **Credits** (*Krediler*) aç.
  - Beklenen: **Credits left** (*Kalan krediler*) 2. Xcode'dan çalıştırılan derleme ücretsiz kredi almaz: Xcode'un StoreKit işlemi yalnızca yerel backend'de ve `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS=true` ile kabul edilir (`_shared/apple.ts`). TestFlight ve App Store kurulumları imzalı AppTransaction'ı sunucuda doğrulatır (Production ve Sandbox).
  - Sorun olursa: TestFlight kurulumunda 0 görünürse önce `APPLE_APP_ID` (`6822716008`) değerine bak. Sunucu günlüğünde "APPLE_APP_ID isn't set" ya da "AppTransaction rejected" yazıyorsa sebep budur.
  - Doğrulanamadı: canlı Apple doğrulaması bu ortamdan denenemedi.
- [ ] **Kötüye kullanım runbook'u okundu** *[yalnızca sahip; yerelde doğrulandı]*
  - Yap: `backend/README.md` içindeki **Abuse runbook** (*Kötüye kullanım*) bölümünü oku. İlk gerçek günden önce SQL Editor'da `select public.ops_daily_summary();` çalıştır.
  - Beklenen: AI'yi durdurmanın (`select public.ops_pause_ai('all', 2, 'neden');`), bloku kaldırmanın (`ops_unblock`) ve strike'ları okumanın (`ops_strikes`) nasıl yapılacağını biliyorsun. Sayılar: 3 strike 24 saatte 24 saatlik cool-down başlatır; 30 günde 3 cool-down install'ı bloklar; ücretsiz AI işleri günde 60'ta, doğrulanmamış kurulumlar 10'da, tüm AI 400'de durur (UTC gün; ücretli işlere her zaman yer kalır).
  - Sorun olursa: Bir `ops_*` fonksiyonu yoksa yukarıdaki geçişlerin tamamının uygulandığını kontrol et.
- [x] **Claude güvenlik denetimi açık; XAI_SAFETY_MODEL ve FAL_KEY boş** *[yapıldı 15 Ekim 2026: log satırı `output check in force: xai + anthropic:claude-haiku-5-5`; gerçek düzenlemede fotoğraf ve sonuç denetimi geçti]*
  - Yap: Supabase › Edge Functions › Secrets'ta adlara bak: `ANTHROPIC_API_KEY` var; `XAI_SAFETY_MODEL` ve `FAL_KEY` yok. Claude Console'da (platform.claude.com) bakiye ve aylık harcama limiti olsun (`docs/SAHIP-YAPILACAKLAR.md` §1.11). `ai-image` yayımlandıktan sonra Edge Functions › `ai-image` › Logs'a bak.
  - Beklenen: Log'da `output check in force: xai + anthropic:claude-haiku-5-5`. Claude (`_shared/safety.ts`), düzenlenecek fotoğrafı görsel modele gitmeden önce ve her sonucu xAI'nin kendi denetiminden sonra denetler; denetim hata verirse, zaman aşımına uğrarsa, reddederse ya da beklenmeyen yanıt dönerse iş engellenir ve kredi iade edilir. İşaretlenen fotoğraf strike sayılmadan iade edilir (`input_blocked`); işaretlenen sonuç strike sayılır. `ANTHROPIC_API_KEY` ayarlıyken `XAI_SAFETY_MODEL` okunmaz.
  - Sorun olursa: Log'da yalnızca `xai` yazıyorsa anahtar eksiktir. Her düzenleme `photo_check_failed` ya da her sonuç `safety_check_failed` ile iade ediliyorsa Anthropic bakiyesine, limite ve anahtara bak; kısa neden `ai-image` Logs'taki uyarıda yazar.
  - Doğrulanamadı: Claude yolu yalnızca sahte yanıtlarla test edildi (`docs/AI-TODO.md` §5, risk 20); canlı API'de ilk deneme §3.4.
- [ ] **xAI kredisi, harcama limiti ve API anahtarı** *[yalnızca sahip; açık: 14 Ekim'de 10 USD yüklendi ve gerçek düzenleme çalıştı; harcama limiti, yeni yükleme ve anahtar döndürme sahipte]*
  - Yap: console.x.ai › faturalandırma: kredi yükle, aylık harcama limiti belirle. Anahtar döndürülecekse: xAI'de yeni anahtar üret, Supabase'te `XAI_API_KEY` değerini yenisiyle değiştir, bir Magic Edit dene, sonra eski anahtarı xAI'de iptal et. Anahtarı hiçbir dosyaya, commit'e ya da sohbete yazma.
  - Beklenen: xAI'de bakiye ve limit var; Magic Edit gerçek sonuç verir (§3.4).
  - Sorun olursa: Bakiye bitmişse her AI işi başarısız olur ve kredi iade edilir (`docs/SAHIP-YAPILACAKLAR.md` §1.1 bu durumu bildiriyor). Bu madde kapanmadan §3'e geçme.
  - Doğrulanamadı: xAI bakiyesi, limit ve anahtarın döndürülüp döndürülmediği bu depodan görülemez.
- [x] **Reklam birimleri (AdMob)** *[yapıldı 15 Ekim 2026: SSV doğrulandı ve kaydedildi, geçiş birimi oluşturuldu, hassas kategoriler engellendi, "Aybuke GDPR" mesajı yayımlandı; AdMob uygulamasını mağaza kaydına bağlamak onaydan sonra (SAHIP 3.7)]*
  - Yap: AdMob'da ödüllü birimi (`ca-app-pub-2292230772061554/1406702504`, ödül 1, öğe `credit`) aç. **Server-side verification** geri çağırma adresi: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` (sorgu dizesi olmadan). **Verify URL**'yi çalıştır. Geçiş reklamı birimi "After save interstitial" (`ca-app-pub-2292230772061554/6797438012`) oluşturuldu ve kimliği `ios/App/Resources/AppConfig.json` içindeki `ads.interstitialUnitID` alanında; AdMob'daki sıklık sınırının günde 3 olduğunu kontrol et.
  - Beklenen: Verify URL doğrular. `ADMOB_REWARDED_AD_UNIT` ile aynı birim kimliği Supabase'te var; boşsa hiçbir ödül verilmez. `interstitialUnitID` dolu: Release derlemesinde ücretsiz 13+ üyelere, kayıt ya da paylaşım bittikten sonra doğal bir arada, uygulamanın kendi sınırlarıyla (`InterstitialPacing`: ilk 24 saat yok, 3. kayıttan sonra, 4 dakikada en çok 1, günde en çok 3) geçiş reklamı gösterilebilir. Pro'da, 13 yaş altında, Mac'te ve önizleme derlemelerinde gösterilmez.
  - Sorun olursa: Doğrulama başarısızsa `ad-reward` günlüğüne bak. Ödül kayıtları 30 gün sonra `sweep_ad_rewards` ile temizlenir.
  - Doğrulanamadı: AdMob konsolunun durumu bu depodan görülemez. AdSense ödeme hesabı (`docs/SAHIP-YAPILACAKLAR.md` §3.6) sahibe ait ve açık.
- [x] **Web sitesi ve yasal adresler** *[yapıldı 15 Ekim 2026: bütün adresler 200, app-ads.txt doğru, hukuk metinleri (Anthropic) aybuke.org'da canlı]*
  - Yap: Tarayıcıda aç: `https://aybuke.org`, `https://aybuke.org/legal/en/privacy-policy`, `https://aybuke.org/legal/tr/gizlilik-politikasi`, `https://aybuke.org/app-ads.txt` ve destek sayfası.
  - Beklenen: Hepsi açılır. `app-ads.txt` AdMob yayıncı satırını (`pub-2292230772061554`) içerir. Uygulamanın `websiteURL`, `privacyPolicyURL` ve `termsURL` değerleri aybuke.org'a işaret eder.
  - Sorun olursa: Açılmıyorsa Vercel dağıtımını ve alan adını kontrol et. Search Console site haritası ve IndexNow bildirimi (`docs/SAHIP-YAPILACAKLAR.md` §4) sahibe ait ve açık.
  - Depoda: `AppConfig.json` aybuke.org'u gösteriyor (`28c16eb`, `origin/main`'de de). Site ayrı depoda (`RiosenBeq/aybuke`, Vercel).

### 1.2 TestFlight (internal testing)

- [ ] **Derleme hazır ve sana dağıtıldı** *[yalnızca sahip; derlemeler yüklendi: iOS `20261015.1225`, Mac `20261015.1233`; iç grup "Aybuke Team" var; kendini ekleyip kurmak açık]*
  - Yap: App Store Connect › TestFlight › iOS'ta derleme "Ready to Test" olmalı. Kendini Internal Testing grubuna ekle; iPhone'da TestFlight uygulamasından **Install**.
  - Beklenen: İşleme 10–30 dk sürer; şifreleme sorusu çıkmaz (`ITSAppUsesNonExemptEncryption = NO`, `ios/Config/Info.plist`).
  - Sorun olursa: "Missing Compliance" ya da işleme hatası e-postasını not et.
  - Doğrulanamadı: TestFlight'taki mevcut derleme bu ortamdan görülemez.
- [ ] **Doğru derlemeyi kullandığını doğrula** *[yalnızca sahip]*
  - Yap: Aybuke › Settings › Version.
  - Beklenen: TestFlight'taki derleme numarasıyla aynı (ör. `1.0 (20261014.1530)`).

### 1.3 Sandbox Apple Hesabı (TestFlight'ta da kullanılabilir)

Apple'ın güncel belgesine göre TestFlight'tan indirilen uygulama her zaman sandbox ortamında çalışır. Kendi Apple Hesabınla satın alırsan ücret alınmaz, ama abonelikler süreden bağımsız **günde bir** yenilenir (1 hafta içinde en fazla 6 kez) ve satın alma geçmişini sıfırlayamazsın. Sandbox kontrolleri (yenileme hızı, geçmişi sıfırlama, yaş senaryoları) için Sandbox Apple Hesabıyla giriş gerekir.

- [ ] **Sandbox test hesabı oluştur** *[yalnızca sahip]*
  - Yap: App Store Connect › Users and Access › Sandbox › Test Accounts › **+**. Daha önce Apple Hesabı olmamış bir e-posta kullan (ör. kendi adresinin `+sandbox1` takma adı). Bir hesabı **Türkiye**, birini **ABD** mağazası yap; parolaları şifre yöneticisine kaydet.
  - Beklenen: Hesaplar listede görünür. Mağaza sonradan App Store Connect'ten değiştirilebilir; değiştirince cihazda sandbox hesabından çıkıp yeniden gir.
- [ ] **Geliştirici Modu** *[yalnızca sahip]*
  - Yap: iPhone'u kabloyla Mac'e bağla, "Bu bilgisayara güven" de; Xcode'da cihaz eşleştirmesini başlat (Window › Devices and Simulators; yeni Xcode sürümlerinde Device Hub). Apple Hesabıyla Xcode'a girmek gerekmez; Geliştirici Modu anahtarı ancak eşleştirmeden sonra görünür. Sonra iPhone'da Settings › Privacy & Security › **Developer Mode** (*Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu*) → aç → yeniden başlat → **Enable**.
  - Beklenen: Settings'te **Developer** (*Geliştirici*) bölümü görünür.
- [ ] **TestFlight için sandbox hesabıyla giriş** *[yalnızca sahip]*
  - Yap: 1) Aybuke'yi TestFlight'tan normal hesabınla kur. 2) Settings › [adın] › **Media & Purchases** (*Medya ve Satın Almalar*) › **Sign Out**. 3) Settings › **Developer** › en altta **Sandbox Apple Account** › **Sign In** › sandbox hesabı.
  - Beklenen: Satın almalar artık sandbox hesabına yazılır. Sandbox alanı Developer'da yoksa Settings › App Store'un en altına bak (bazı iOS 18 sürümlerinde orada görünüyor).
  - Dikkat: Apple'a göre Media & Purchases'tan çıkmak diğer uygulamalarda satın aldığın içeriğe erişimi etkileyebilir; mümkünse ayrı bir test cihazı kullan. Test bitince Media & Purchases'a geri gir (TestFlight satın almaları yeniden kendi hesabına yazılır).
- [ ] **Yenileme hızını seç** *[yalnızca sahip]*
  - Yap: Settings › Developer › Sandbox Apple Account › **Manage** › Renewal Rate (ya da App Store Connect'ten).
  - Beklenen: Varsayılan "Every 5 minutes": 1 hafta = 3 dk, 1 ay = 5 dk, 1 yıl = 1 saat; abonelik 12 kez yenilenir, sonra kendiliğinden biter. Yıllık deneme bu ayarla 3 dakika sürer.

### 1.4 Satın alma geçmişini sıfırlama

- [ ] **Sandbox hesabı** *[yalnızca sahip]*
  - Yap: Settings › Developer › Sandbox Apple Account › **Manage** › **Clear Purchase History**, ardından sandbox hesabından çıkıp tekrar gir (önbellek temizlenir). Aynı işlem App Store Connect › Users and Access › Sandbox › hesabı seç › **Clear Purchase History** ile de yapılır.
  - Beklenen: Geçmiş boşalır, hesap tanıtım tekliflerine (deneme, ilk ay $1.99) yeniden uygun olur. Geri alınamaz.
- [ ] **Kendi Apple Hesabınla TestFlight** *[yalnızca sahip]*
  - Beklenen: Geçmiş sıfırlanamaz. Bu yolda gruptaki iki tanıtım teklifinden yalnızca birini deneyebilirsin. Hangisini denediğini not et.

### 1.5 Temiz kurulum

- [ ] **Gerçekten sıfırdan başla** *[yalnızca sahip; açık: Keychain silinmiyor (§12-7)]*
  - Yap: Aybuke daha önce kuruluysa önce uygulamada Settings › **Delete my data & account** (*Verilerimi ve hesabımı sil*) › **Delete my data** (*Verilerimi sil*) yap. Sonra uygulamayı sil ve TestFlight'tan yeniden kur.
  - Neden: Oturum Keychain'de saklanıyor (`ios/App/Services/Auth/Keychain.swift:22`); iOS uygulama silinince Keychain'i temizlemiyor. Oturum açılışta `ios/App/Services/Auth/AuthSessionManager.swift:23` satırında okunuyor. Yalnızca silip kurarsan eski anonim hesap, bakiyesi ve varsa Apple ile girişin geri gelir (§12-7).
  - Beklenen: Onboarding'in ilk sayfası açılır; Settings › Account'ta "Signed in with Apple" yazmaz.

### 1.6 Doğrulama araçları (test boyunca açık tut)

- [ ] **Supabase panosu** *[yalnızca sahip]*: Authentication › Users (anonim ve Apple kullanıcıları). Table Editor'da `credit_wallets` (`purchased` paket kredileridir; `daily` ve `subscription` 20261021'den beri kullanılmaz, 0 kalır), `credit_ledger` (`hold`, `release`, `grant_pack`), `jobs` (`status`, `cost`, `retry_of`, `retried`, `error_code`, `delivered_at`), `entitlements` (`credits`, `trial_granted`, `environment` = Sandbox), `private.app_installs` (karma anahtarlı install kayıtları), `reports`, `pending_revenuecat_deletions`. Ayrıca Edge Functions › Logs.
- [ ] **RevenueCat panosu** *[yalnızca sahip]*: Customers listesinde sandbox verisini göster. RevenueCat yalnızca satın alan kişi için açılır. Uygulamadan gönderilen müşteri kimliği büyük harfli UUID'dir; Supabase kimliği küçük harflidir ve silme her iki yazımı da dener (`_shared/revenuecat.ts`).
- [ ] **Ekran kaydı** *[yalnızca sahip]*: Denetim Merkezi'nden. Bir hatayı göstermenin en hızlı yolu.

---

## 2. İlk açılış (yetişkin yolu)

- [ ] **2.1 Tanıtım sayfaları** *[yalnızca sahip]*
  - Yap: İlk iki sayfada **Continue** (*Devam et*) ya da **Skip** (*Atla*).
  - Beklenen: Atla seni yaş adımına götürür; yaş adımı atlanamaz.
- [ ] **2.2 Yaş adımı (yetişkin)** *[yalnızca sahip; kod yerelde doğrulandı: `AgeStepView`]*
  - Yap: iOS 26 ve sonrası: **Your age range** (*Yaş aralığın*) › **Continue** → Apple'ın yaş aralığı penceresi → paylaş. Pencere çıkmazsa ya da paylaşmazsan **When were you born?** (*Ne zaman doğdun?*) menüleri gelir: **Month** (*Ay*) ve **Year** (*Yıl*), ör. Ocak 2000 → **Continue**.
  - Beklenen: Menülerde hiçbir şey önceden seçili değildir; yalnızca yaş bandı cihazda saklanır. Sonra **What are you here for?** ilgi alanları sayfası gelir.
  - Sorun olursa: Kayan düğme ya da kesik yazı varsa ekran görüntüsü al (özellikle büyük yazı boyutunda).
- [ ] **2.3 Try Digicam '04 on your photo** (*Digicam '04 efektini fotoğrafında dene*) *[yalnızca sahip]*
  - Yap: **Start with your photo** (*Fotoğrafınla başla*) → bir selfie seç.
  - Beklenen: Efekt cihazda uygulanır (internet gerekmez), önce/sonra kaydırıcısı görünür. Onay ekranı çıkmaz, kredi düşmez. Altta **Keep editing** (*Düzenlemeye devam et*) ve **Save to My Works** (*Eserlerim'e kaydet*) var.
  - Yap: **Save to My Works**.
  - Beklenen: "Saved to My Works ✨" (*Eserlerim'e kaydedildi ✨*). Ardından X ile kapatılabilen yumuşak paywall çıkar (yalnızca yetişkinlerde ve Pro değilsen). Kapatınca kısa tur gelir: **Next** (*İleri*) / **Skip** (*Atla*).
  - Alternatifler: **Keep editing** ile editör Effects'te açılır ve paywall editör kapanınca gelir. **Skip for now** (*Şimdilik atla*) doğrudan paywall'a gider.
  - Sorun olursa: Paywall hiç gelmediyse ya da editör açıkken geldiyse not et.
- [ ] **2.4 Explore ilk görünüm** *[yalnızca sahip]*
  - Beklenen: Üstte "Aybuke", şimşek simgeli kredi hapında **2** ve dişli var. **Magic Edit** kartı (**Try it on your photo** / *Fotoğrafında dene*) ve **Quick tools** (*Hızlı araçlar*): Retro Cam, Effects, Enhance, Remove BG, Erase, Styles, Adjust, Collage, Video, Best shot. 1 Ekim–2 Kasım arasında **Spooky season** (*Halloween havası*) satırı görünür.
  - Sorun olursa: "Preview build" bandı görünüyorsa bu engelleyicidir.
- [ ] **2.5 Büyük yazı taraması (iPhone 17e)** *[yalnızca sahip; açık]*
  - Yap: iPhone 17e'de iOS metin boyutunu en büyüğe getir (Ayarlar › Erişilebilirlik › Görüntüleme ve Metin Boyutu). Cihaz dilini sırayla İngilizce, Almanca ve Rusça yap. Explore, Create, Edit, My Works, paywall ve Settings'te gez.
  - Beklenen: Kesilmiş ya da taşan metin, kayan düğme ve ekran dışına çıkan öğe yok.
  - Sorun olursa: Ekran görüntüsü al, ekran adını ve dili yaz; §13'teki şablonla ajana ver.
  - Kaynak: `docs/SAHIP-YAPILACAKLAR.md` §2.11.

---

## 3. Krediler ve yapay zekâ (canlı backend)

- [ ] **3.1 Günlük ücretsiz krediler** *[yerelde doğrulandı; canlı açık]*
  - Yap: Settings › **Credits** (*Krediler*).
  - Beklenen: **Credits left** (*Kalan krediler*) 2. Altında "You get 2 free credits every day…" yazar. Ücretsiz kredi yalnızca doğrulanmış App Store kurulumunda verilir (§1.1, kurulum kanıtı). Sunucu günlük kredileri UTC gün değişince 2'ye tamamlar (Türkiye saatiyle 03:00); krediler birikmez. Pro aboneliğinde günlük kredi yoktur (§3.11).
  - Doğrulanamadı: canlı sunucu. Yerelde `credit_policy()` (`free_daily` = 2) ve `private.refresh_install` kontrol edildi.
- [ ] **3.2 Güvenlik filtresi** (onay ekranından ve krediden önce çalışır) *[yalnızca sahip; kod yerelde doğrulandı: `ContentPolicy`, `policy.ts`]*
  - Yap: Explore › Magic Edit › bir fotoğraf → kutuya `make me thinner` (Türkçe: `beni daha zayıf yap`) yaz → yukarı ok.
  - Beklenen: Onay ekranı ya da paywall açılmadan hata çıkar: "Aybuke keeps you, you. Try hair color, makeup colors, outfits, light or backgrounds." (*Aybuke seni sen olarak tutar…*). Sunucuya istek gitmez, kredi düşmez.
- [ ] **3.3 Onay ekranı** (ilk bulut işi) *[yalnızca sahip; kod yerelde doğrulandı: `aiProcessors`]*
  - Yap: **Give me pink hair** çipine dokun → gönder.
  - Beklenen: **Your photos, your call** (*Fotoğrafların, senin kararın*) ekranı açılır. Giriş cümlesi tek bir şirket adı vermez: "To create and edit images with AI, we send the photo and text you choose to our servers and to the companies listed below, who process them for us." (*…seçtiğin fotoğrafı ve metni sunucularımıza ve aşağıda listelenen şirketlere göndeririz; bu şirketler onları bizim adımıza işler.*). "Deleted from our servers within an hour", "Deleted by our safety-check provider within 30 days, unless flagged for breaking its rules" (*Güvenlik denetimi sağlayıcımız tarafından 30 gün içinde silinir (kurallarına aykırı diye işaretlenenler hariç)*) ve "Never used to train AI models" maddeleri var. **Who processes what you send** (*Gönderdiklerini kim işliyor*) altında Supabase (*Sunucularımız: yapay zekâ işlerin ve kredilerin*), xAI (Grok Imagine) (*Görselleri oluşturur ve düzenler*) ve Anthropic (Claude) (*Düzenlediğin fotoğrafları ve her sonucu güvenlik için denetler*) listelenir (`aiProcessors`, `consentVersion` 2; fal.ai listede yok, `FAL_KEY` yokken hiçbir şey görmez). Daha önce eski listeye (Supabase ve xAI, sürüm 1) onay verdiysen onay ekranı bir kez daha açılır. **Read our Privacy Policy** uygulama içinde açılır. Düğmeler eşit ağırlıktadır: **Allow AI processing** (*Yapay zekâ ile işlemeye izin ver*) ve **Not now** (*Şimdi değil*).
  - Yap: Önce **Not now**.
  - Beklenen: Hiçbir şey gönderilmez, editör açık kalır, Supabase'te yeni kullanıcı oluşmaz.
  - Yap: Tekrar gönder → **Allow AI processing**.
- [ ] **3.4 Magic Edit uçtan uca** *[yalnızca sahip; açık: xAI bakiyesi, §1.1]*
  - Beklenen: "Applying your edit…" (*Düzenlemen uygulanıyor…*) katmanında **Cancel** (*Vazgeç*) ve ilk seferde **Ping me when it's ready** (*Hazır olunca bana haber ver*) görünür. İş başlayınca Live Activity de başlar; uygulamadan çıkınca Dynamic Island'da görürsün (§7.2). Sonuç genellikle bir dakikadan kısa sürede gelir (3 dakikayı geçerse zaman aşımı ve iade). Önce/sonra karşılaştırma açık gelir; **Hold to see original** (*Orijinali görmek için basılı tut*); **Still you** (*Hâlâ sensin*) etiketi; **Retry free** (*Ücretsiz tekrar dene*) ya da **Doesn't look like you? Retry free** (*Benzemedi mi? Ücretsiz tekrar dene*); bayrak simgesi (Report).
  - Sunucu: `jobs`'ta yeni satır `completed` ve `cost = 1`; `credit_ledger`'da −1 `hold`; `credit_wallets` toplamı 1. Uygulama sonucu indirince `outputs` alanı boşaltılır.
  - Uygulamadaki bakiye: İş başlar başlamaz hap 1'e düşer (sunucunun 202 yanıtındaki bakiye); iş bitince Settings › Credits left da 1'dir, widget iş bitince güncellenir. Uygulamayı kapatıp açınca da 1 kalmalı.
  - Yap: Üst çubukta **Save** (*Kaydet*).
  - Beklenen: İlk kayıtta Fotoğraflar için "yalnızca ekleme" izni sorulur, sonra "Saved to Photos" (*Fotoğraflar'a kaydedildi*). Ücretsiz kullanıcıda resmin köşesinde küçük Aybuke işareti bulunur; eser My Works'e de eklenir.
  - Sorun olursa: Hata metnini, saati ve `jobs.error_code` değerini yaz. `photo_check_failed` ya da `safety_check_failed` ise Claude denetimi çalışamamıştır (§1.1, Claude güvenlik denetimi maddesi); `input_blocked` ise Claude fotoğrafı işaretlemiştir, başka bir fotoğrafla dene.
- [ ] **3.5 Bir kez ücretsiz tekrar (Likeness Lock)** *[yalnızca sahip; yerelde doğrulandı: 15 dakika, günde 3]*
  - Yap: Sonuçtan sonraki **15 dakika** içinde **Retry free**.
  - Beklenen: Aynı iş aynı başlangıç fotoğrafıyla tekrar çalışır, kredi düşmez. Başarılı olunca düğme kaybolur; ücretli sonuç Undo (geri al) ile geri gelir. Supabase'te yeni `jobs` satırı `cost = 0` ve `retry_of` dolu, eski satırda `retried = true`; `credit_ledger`'da yeni `hold` yoktur. Tekrarlar kullanıcı başına günde en çok **3**'tür (`free_retries_daily`). 15 dakika sonra düğme hiç görünmez.
  - Sorun olursa: Tekrarda kredi düştüyse engelleyicidir (paywall "Plus a free retry if it doesn't look like you" diyor).
- [ ] **3.6 Başarısız ya da iptal edilen işte iade** *[yalnızca sahip; yerelde doğrulandı: `cancel_job`, `deliver_outputs`, `settle_unconfirmed`]*
  - Yap: Yeni bir Magic Edit başlat, katman görünürken **Cancel**.
  - Beklenen: Supabase'te `jobs.status = cancelled`, aynı iş için `credit_ledger`'da `hold` ve `release` (net 0). Uygulamayı yeniden açınca bakiye işten önceki değerdedir.
  - Yap: İş sürerken Uçak Modu'nu aç, 30 saniye bekle, kapat.
  - Beklenen: Uygulama vazgeçmez; bağlantı gelince sonuç normal şekilde gelir ve bakiye 1 düşmüş olur.
  - Yap (isteğe bağlı): İş sürerken Uçak Modu'nu aç ve 2 dakikadan uzun açık bırak.
  - Beklenen: "The connection dropped before your result arrived. If it never reaches you, your credit comes back automatically within about an hour." (*Sonucun gelmeden bağlantı koptu. Sonuç sana ulaşmazsa kredin yaklaşık bir saat içinde otomatik olarak iade edilir.*). Live Activity "Failed creations are refunded automatically…" der. Yaklaşık 1 saat sonra Supabase'te iş `failed` ve `error_code = undelivered` olur, `credit_ledger`'da aynı iş için `release` vardır; uygulamayı öne getirince bakiye geri gelmiş görünür.
- [ ] **3.7 Create uçtan uca** *[yalnızca sahip]*
  - Yap: **Create** sekmesi → bir fikir yaz ya da **Inspire me** (*İlham ver*) → **Style** (*Stil*) ve **Size** (*Boyut*) seç → **Generate** (*Oluştur*, 1 kredi).
  - Beklenen: Apple Intelligence olan cihazda **Make it magic** (*Sihir kat*) ve "Written on your device by Apple Intelligence"; yoksa **Enhance prompt** (*Komutu geliştir*). Sonra "Creating your image…" (*Görselin oluşturuluyor…*) ve **Your creation** (*Eserin*) ekranı. Sonuç anlık fotoğraf gibi belirir ve kendiliğinden My Works'e eklenir. **Images** (*Görsel sayısı*) bölümünde 2–4 kilitlidir; seçip Generate'e basınca paywall açılır.
  - Yap: **Regenerate** (*Yeniden oluştur*).
  - Beklenen: Önce "Regenerate?" onayı çıkar ("Same prompt and style, new pictures. Uses 1 credit, refunded if it fails."); onaylayınca aynı istemle yeni görsel gelir.
  - Yap: Sağ üstte **…** (More) → **Report this image** (*Bu görseli bildir*) → bir neden seç.
  - Beklenen: "Thanks — we'll review this image." (*Teşekkürler — bu görseli inceleyeceğiz.*) ve Supabase `reports` tablosunda yeni satır.
- [ ] **3.8 Krediler bitince** *[yalnızca sahip]*
  - Yap: Ücretsiz kullanıcıyken 2 krediyi bitir, bir iş daha dene.
  - Beklenen: Sunucu "yetersiz kredi" der ve paywall açılır. Altında **Or wait for your free daily credits. Remind me when they're back** (*Ya da günlük ücretsiz kredilerini bekle. Geri gelince bana hatırlat*) bağlantısı var; dokununca bildirim izni sorulur, "We'll remind you when your free credits are back ✨" görünür ve paywall kapanır. Eski kalmış bakiye bu noktada 0'a düzelir.
  - Pro kullanıcıda aylık krediler bitince paywall yerine **You've used this month's credits** (*Bu ayın kredilerini kullandın*) sayfası ve kredi paketleri gelir (§4 sonrası dene).
- [ ] **3.9 Çevrimdışı** *[yalnızca sahip]*
  - Yap: Uçak Modu'nu aç.
  - Beklenen: Explore'da "You're offline. Effects, Adjust, Cut out and Video still work." (*Çevrimdışısın. Efektler, Ayarla, Dekupe ve Video çalışmaya devam ediyor.*) notu görünür. Magic Edit ve Create aynı uyarıyı verir; hiçbir şey gönderilmez, kredi düşmez. Effects, Adjust, Cut out ve video düzenleyici çalışır. Uçak Modu kapanınca not kaybolur.
- [ ] **3.10 Onayı Settings'ten değiştirme** *[yalnızca sahip]*
  - Yap: Settings › **Privacy** (*Gizlilik*) › **Cloud AI processing** (*Bulutta yapay zekâ işleme*) anahtarını kapat → bir Magic Edit dene.
  - Beklenen: Onay ekranı yeniden açılır. Anahtarın altında aynı üç işleyen (Supabase, xAI ve Anthropic) listelenir; anahtarı açınca da aynı onay ekranı gelir.
- [ ] **3.11 Ertesi gün yenilenme** *[yalnızca sahip]*
  - Yap: Ertesi gün Türkiye saatiyle 03:00'ten sonra uygulamayı aç.
  - Beklenen: Ücretsiz kullanıcıda bakiye 2 olur (4 olmaz). Pro'da günlük kredi 0'dır, aylık krediler devam eder.
- [ ] **3.12 Ideas for this photo ve Surprise me** (ücretsiz) *[yalnızca sahip]*
  - Yap: Editörde fotoğrafın altındaki **Ideas for this photo** (*Bu fotoğraf için fikirler*) → **Surprise me** (*Şaşırt beni*).
  - Beklenen: Uygun bir ücretsiz efekt hemen uygulanır (kredi ve onay yok). Bir görünüm (look) önerisi seçersen önce "Try …?" onayı ve kredi bilgisi gelir.
- [ ] **3.13 Image Playground** (yalnızca iOS 18.4+ ve Apple Intelligence destekli cihazda) *[yalnızca sahip]*
  - Yap: Create › **Create with Image Playground** (*Image Playground ile oluştur*).
  - Beklenen: Apple'ın penceresi açılır; Aybuke onayı ve kredisi kullanılmaz. Sonuç My Works'e kaydedilir. iOS 27'de ilk kullanımda "Image Playground is Apple's" uyarısı çıkar.
  - Uyumluluk kontrolü ([`05-compliance.md`](05-compliance.md)): Apple penceresinde uygunsuz ya da vücut değiştiren istemler yaz, "photorealistic" dene ve kendi fotoğrafını eklemeyi dene. Gerçekçi bir selfie düzenlemesi geçiyorsa yayından önce bildir.

---

## 4. Satın almalar (sandbox / TestFlight)

Fiyatlar ABD mağazasında: Yıllık $39.99 (7 gün ücretsiz), Aylık $5.99 (ilk ay $1.99), 30 kredi $2.99, 100 kredi $7.99. Bu fiyatlar yerel ürün dosyasında (`ios/StoreKit/Products.storekit`) da var; `AppConfig.json` fiyat taşımaz. Türkiye mağazasında App Store Connect'teki TRY karşılıkları görünür. Satın alma penceresinde "Environment: Sandbox" ibaresini ve hangi hesabın kullanıldığını not et.

- [ ] **4.1 Paywall ürünleri yüklüyor** *[yalnızca sahip]*
  - Yap: Ücretsiz kullanıcıyken Explore'daki kredi hapına dokun.
  - Beklenen: **Your photos, in their best light** (*Fotoğrafların, en güzel ışığında*) başlığı ve avantajlar. **Yearly** (*Yıllık*) önceden seçili, **BEST VALUE** (*EN AVANTAJLI*) rozetli; büyük yazıyla "… / year", altında "7 days free, then …/year · just …/month". **Monthly** (*Aylık*) **TRY IT** (*DENE*) rozetli, altında "First month $1.99, then $5.99/month · cancel anytime". **No weekly plans, ever.** (*Haftalık plan yok, asla.*) yazar. Altta **Restore** (*Geri yükle*), **Terms** (*Koşullar*), **Privacy** (*Gizlilik*) ve otomatik yenileme metni, sağ üstte X var. Giriş yapmadıysan **Sign in** de görünür (§5.1). Terms ve Privacy uygulama içinde açılır.
  - Sorun olursa: 10 saniye sonra "Couldn't reach the App Store. Check your connection." ve **Try again** (*Tekrar dene*) ya da "Subscriptions are unavailable right now." görünürse §1.1'i kontrol et ve ekran görüntüsü al.
- [ ] **4.2 Pro Yearly ve 7 günlük ücretsiz deneme** *[yalnızca sahip; yerelde doğrulandı: `refresh_subscription` deneme kredisini bir kez verir]*
  - Yap: Yearly seçiliyken ekranı aşağı kaydır.
  - Beklenen: **How your free trial works** (*Ücretsiz deneme nasıl işler?*) kartında: **Today** (*Bugün*) "Unlock everything. No charge today.", **Day N** (*N. gün*) "We'll remind you before your trial ends.", **Day 7** "You'll be charged … on … unless you cancel before." Düğmede yalnızca **Continue** (*Devam et*) yazar; hemen altında düğme boyutunda "7 days free, then **$39.99**/year" (yinelenen fiyat kalın).
  - Yap: **Continue** → Apple penceresinde koşulları gör → onayla.
  - Beklenen: "Welcome to Aybuke Pro ✦ Your free trial ends <tarih saat>." (*Aybuke Pro'ya hoş geldin ✦ Ücretsiz denemen … tarihinde bitiyor.*). Paywall kapanır; giriş yapmadıysan kısa süre sonra hesap sayfası ("Keep your credits on every device") açılır, **Not now** ile kapanır (§5.1). Kredi hapında taç simgesi görünür. Settings › **Membership** (*Üyelik*): **Aybuke Pro**, "Free trial until …" (*Ücretsiz deneme … tarihine kadar*) ve **Manage subscription** (*Aboneliği yönet*).
  - Sunucu: `entitlements`'ta yeni satır (`environment` Sandbox, `trial_granted` true). Deneme ilk görüldüğünde **20** kredi bir kez verilir (`credits` 20 olur). Pro'da günlük ücretsiz kredi yoktur. Uygulama, onay vermemiş olsan da, bakiyeyi hemen sunucudan okur (yaklaşık 20 kredi, günlük 0).
  - Sorun olursa: "Purchase failed" (*Satın alma başarısız oldu*) metnini yaz; Pro görünmüyorsa Settings › Restore purchases dene ve not et.
- [ ] **4.3 Deneme hatırlatması (zamanlama)** *[yerelde doğrulandı: `NotificationPlanner`, 26 saat]*
  - Kural (kodda): Hatırlatma, deneme bitişinden **en az 26 saat önceki en geç uygun ana** kurulur. 21:00–09:00 arası ve hafta içi 08:00–15:00 arası atlanır; bu durumda aynı ya da bir önceki akşam 20:59'a çekilir. Örnek: Çarşamba 16:00'da başlayan deneme gelecek Çarşamba 16:00'da biter, hatırlatma Pazartesi 20:59'da gelir ve paywall'da "Day 5" yazar.
  - Yap: Satın almadan önce paywall'daki "Day N" değerinin bu kurala uyduğunu kontrol et.
  - Beklenen, deneme kısaysa (sandbox hesabında dakikalar, TestFlight'ta yaklaşık bir gün): 26 saatlik pay kalmadığı için hatırlatma **kurulmaz** ve bildirim izni de sorulmaz; karşılama mesajı bu yüzden deneme bitiş saatini yazar. Settings › Membership'teki "Free trial until …" ile karşılaştır.
  - Beklenen, deneme 26 saatten uzunsa (gerçek 7 günlük deneme, yayından sonra): satın almanın hemen ardından bildirim izni sorulur, karşılama mesajı tarih yazmaz ve bildirim kurala uygun saatte "Your free trial ends …" / "To avoid the … charge, cancel before … in Settings › Apple Account › Subscriptions." metniyle gelir (*Ücretsiz denemenin bitişi: … / … tutarında ücret alınmaması için … öncesinde Ayarlar › Apple Hesabı › Abonelikler bölümünden iptal et.*). İzin reddedilirse hatırlatma kurulmaz ve mesaj bitiş tarihini yazar.
  - Yap: Deneme sürerken **Manage subscription** → aboneliği iptal et.
  - Beklenen: Pro deneme bitene kadar sürer; gerçek denemede hatırlatma da silinir.
- [ ] **4.4 Pro Monthly ve ilk ay $1.99** *[yalnızca sahip]*
  - Ön koşul: Hesap Pro olmamalı ve bu grupta daha önce tanıtım teklifi kullanmamış olmalı. Sandbox hesabında **Clear Purchase History** ikisini birden sağlar (etkin aboneliği de siler, §1.4); kendi hesabında ikinci bir hesap gerekir. Yıllık denemeyi kullanmış bir hesapta Monthly kartında yalnızca "Cancel anytime" yazar, **TRY IT** rozeti olmaz ve düğme "Continue — …/month" olur. Bu doğru davranıştır.
  - Yap: Uygun hesapla Monthly'yi seç.
  - Beklenen: Düğmede **Continue**, altında "First month $1.99, then **$5.99**/month · cancel anytime". Apple penceresinde ilk dönem $1.99. Satın almadan sonra Pro açılır ve **+80** kredi gelir (ilk ücretli dönem tam aylık paydır; toplam en çok **160**).
- [ ] **4.5 Kredi paketleri (30 ve 100)** *[yalnızca sahip; yerelde doğrulandı: `grant_pack` her Apple işlemi için bir kez]*
  - Yap: Paywall › **Not ready to subscribe? Get a credit pack** (*Abone olmaya hazır değil misin? Kredi paketi al*) ya da Settings › Credits › **Buy a credit pack** (*Kredi paketi al*).
  - Beklenen: **Credit packs** (*Kredi paketleri*) sayfasında "Pay once. Credits never expire. 1 credit = 1 creation or edit." yazar. İki satırda App Store Connect'teki ad, açıklama ve "≈ … per credit" (*Kredi başına ≈ …*) görünür.
  - Yap: 30'luk paketi al, sonra 100'lük paketi al.
  - Beklenen: Her seferinde "Credits added ✦" (*Krediler eklendi ✦*) ve bakiye hemen +30 / +100 (uygulama sunucunun verdiği yeni bakiyeyi gösterir). `credit_ledger`'da Apple işlem kimliğiyle tek bir `grant_pack` satırı. Paketler tüketilebilir, aynı paket tekrar alınabilir.
  - Sorun olursa: "We couldn't add your credits yet. We'll retry automatically." görürsen uygulamayı kapatıp aç ve kredilerin **bir kez** eklendiğini kontrol et. İki kez eklenirse engelleyicidir.
- [ ] **4.6 Restore purchases** *[yalnızca sahip]*
  - Yap: Settings › Membership › **Restore purchases** (*Satın alımları geri yükle*).
  - Beklenen: Pro varsa "Purchases restored ✦", yoksa "No active subscription found." Paywall'daki **Restore**: Pro varsa paywall kapanır; yoksa "Nothing to restore" / "No active subscription found for this Apple Account." uyarısı çıkar. Kredi paketleri geri yüklenmez, onlar sunucudaki bakiyede durur.
  - Yap: Uygulamayı sil ve TestFlight'tan yeniden kur.
  - Beklenen: Aynı Apple Hesabında Pro, Restore'a basmadan da görünür. Bakiye Keychain'deki oturum sayesinde geri gelir (§1.5).
- [ ] **4.7 Pro bitince** *[yalnızca sahip; yerelde doğrulandı: `refresh_subscription` abonelik kredisini sıfırlar]*
  - Yap: Aboneliği iptal et ve dönemin bitmesini bekle (sandbox'ta dakikalar ya da saatler; ayrıca 12 yenilemeden sonra sandbox aboneliği kendiliğinden biter).
  - Beklenen: Pro kapanır ve Settings'te **Upgrade to Aybuke Pro** (*Aybuke Pro'ya geç*) görünür. Sunucuda abonelik kredileri 0'a iner, günlük 2 kredi geri gelir; **paket kredileri kalır**.
- [ ] **4.8 Pro özellikleri ve filigran** *[yalnızca sahip]*
  - Beklenen: Pro'da kilitli görünümler ve stiller açılır; Create'te 2–4 görsel seçilebilir (görsel başına 1 kredi); dışa aktarımda Aybuke işareti olmaz. Ücretsiz kullanıcı kilitli bir şeye dokununca paywall açılır. Cihaz üstü düzenlemelerde hiçbir zaman işaret olmaz.
- [ ] **4.9 Onay bekleyen satın alma (Ask to Buy)** (TestFlight'ta denenemez) *[yalnızca sahip]*
  - Neden: Apple'ın sandbox ayarlarında ebeveyn onayını (Ask to Buy, Texas SB 2420) üreten bir seçenek yok. Arayüz, Xcode'un yerel StoreKit dosyasıyla simülatörde denenir.
  - Yap: Mac'te Xcode'da `ios/StoreKit/Products.storekit`'i aç → **Editor › Enable Ask to Buy** → Debug derlemeyi simülatörde çalıştır (şema bu dosyayı kullanır) → paywall'dan satın al.
  - Beklenen: Düğmede **Waiting for approval** (*Onay bekleniyor*), kartta "Waiting for approval. If it's approved, Pro turns on automatically." (paketlerde "…your credits are added automatically."). **Debug › StoreKit › Manage Transactions** ile onaylayınca "Welcome to Aybuke Pro ✦" gelir. Reddedersen bekleme durumu uygulama yeniden açılana kadar kalır (StoreKit reddi bildirmez).
  - Not: Sunucu Xcode işlemlerini bilerek kabul etmez; paket onayında "We couldn't add your credits yet…" görmen normaldir. Test bitince Ask to Buy'ı kapat ve dosyayı açık haliyle commit etme.
- [ ] **4.10 Kesintili satın alma** (isteğe bağlı, gerçek cihazda geç gelen satın alma yolu) *[yalnızca sahip]*
  - Yap: App Store Connect › Users and Access › Sandbox › hesap › **Interrupt Purchases for This Tester** → sandbox hesabıyla bir kredi paketi al.
  - Beklenen: Apple önce koşulları gösterir. Uygulamada ya "Waiting for approval" ya da bir hata görürsün. Koşulları kabul edince işlem arka planda tamamlanır ve krediler bir kez eklenir. Ne gördüğünü not et; testten sonra seçeneği kapat.
- [ ] **4.11 Satın almalar kapalıyken** (isteğe bağlı) *[yalnızca sahip]*
  - Yap: Settings › Screen Time › Content & Privacy Restrictions › In-app Purchases: **Don't Allow** (*Ekran Süresi › İçerik ve Gizlilik Sınırlamaları*).
  - Beklenen: Paywall'da "Purchases are turned off on this device." (*Bu cihazda satın alımlar kapalı.*) yazar ve satın alma düğmeleri pasif olur; Restore çalışır. Testten sonra ayarı geri aç.
- [ ] **4.12 Paywall'un yaşa göre davranışı** (§8'de tekrar kontrol edilir) *[yalnızca sahip]*
  - Beklenen: Yetişkinde onboarding sonunda bir kez kendiliğinden açılır (kapatılabilir). 13–17 yaşta hiç kendiliğinden açılmaz, yalnızca dokununca açılır. 13 yaş altında hiç yoktur (Membership bölümü de yoktur).
- [ ] **4.13 Sandbox satın alma testi (son derleme)** *[yalnızca sahip; açık]*
  - Yap: Gönderilecek derlemede, Türkiye ve ABD mağazasındaki sandbox hesaplarıyla §4.1–4.6'yı sırayla uygula: yıllık deneme, aylık ilk ay, 30 ve 100 paket, geri yükleme.
  - Beklenen: Her satın alma "Environment: Sandbox" ile tamamlanır; sunucuda `entitlements` (Sandbox) ve `credit_ledger`'da `grant_pack` satırları oluşur; hiçbir kredi iki kez eklenmez.
  - Sorun olursa: Hangi adımda, hangi mağazada ve hangi hesapla olduğunu not et (§13).
  - Kaynak: `docs/SAHIP-YAPILACAKLAR.md` §2.12. Doğrulanamadı: sandbox satın alması bu ortamda çalıştırılamaz (App Store erişimi yok).

---

## 5. Hesap: Sign in with Apple (1.0'da açık)

`ios/App/Resources/AppConfig.json` içinde `"signInWithApple": true`. Sunucuda `APPLE_SIGNIN_KEY_ID` (`36Q32XU57F`) ve `APPLE_SIGNIN_PRIVATE_KEY` ayarlı ve Apple'a karşı doğrulandı (15 Ekim 2026), bu yüzden silme token'ı iptal edebilir (§9.6). Pro her zaman Apple Hesabından (StoreKit), krediler sunucudaki hesaptan gelir. Bu bölümü aynı Apple Hesabıyla iki cihazda yap (iPhone ve iPad ya da Mac).

- [ ] **5.1 Giriş noktaları** *[yerelde doğrulandı: `AppModel.offersSignIn`; cihazda açık]*
  - Yap: Settings'i aç; paywall'ın altına bak; giriş yapmadan bir kredi paketi al.
  - Beklenen: Settings'te **Account** (*Hesap*) bölümünde Sign in with Apple düğmesi ve "Keep your credits when you switch or add a device. Pro stays with your Apple Account. Signing in is optional." yazısı; paywall'da **Sign in**; satın almadan kısa süre sonra "Keep your credits on every device" sayfası açılır, "Pro works wherever you use the same Apple Account" yazar ve **Not now** ile kapanır. Giriş hiçbir yerde zorunlu değil; satın almalar ve krediler girişsiz de çalışır.
- [ ] **5.2 Giriş ve kredi birleştirme** *[yalnızca sahip]*
  - Yap: Kredisi olan anonim hesapla (ör. 5.1'deki paketten sonra) Sign in with Apple ile giriş yap; e-postayı gizlemeyi seçebilirsin.
  - Beklenen: "You're signed in ✨ Your credits now come with you." görünür ve bakiye aynı kalır: paket kredileri hesaba geçer (Apple hesabında önceden paket kredisi varsa toplanır), günlük ücretsiz krediler kuruluma bağlı kalır. Settings › Account: **Signed in with Apple** ve **Sign out** (*Çıkış yap*). Sunucu: `public.apple_accounts`'ta bu kullanıcı için token satırı, `public.merged_users`'ta birleşen anonim kimlik; `account` log'unda hata yok.
  - Sorun olursa: "You're signed in, but your credits haven't moved to your account yet. We'll try again automatically." görünürse uygulamayı kapatıp aç (birleştirme açılışta yeniden denenir) ve `account` log'undaki satırı (ör. `apple code exchange failed`, `merge_accounts failed`) not et. Giriş hiç olmuyorsa Supabase › Authentication › Providers › Apple açık ve Client IDs'de `app.glowlit.ios` olmalı.
- [ ] **5.3 İkinci cihaz** *[yalnızca sahip]*
  - Yap: İkinci cihazda aynı Apple Hesabıyla giriş yap.
  - Beklenen: Aynı kredi bakiyesi. Pro, aynı Apple Hesabıyla burada da görünür (gerekirse Settings › Restore purchases).
- [ ] **5.4 Çıkış ve Apple tarafında kaldırma** *[yalnızca sahip]*
  - Yap: Settings › Account › **Sign out** › onayla. Yeniden giriş yap; sonra iPhone'da Settings › [adın] › Sign-In & Security › **Sign in with Apple** listesinden Aybuke'yi kaldır ve uygulamaya dön.
  - Beklenen: Çıkışta "Signed out. Sign in again anytime in Settings." görünür. Apple listesinden kaldırınca uygulama sessizce çıkış yapar (en geç bir sonraki açılışta).

Silmede token iptali: §9.6.

---

## 6. Cihaz üzerindeki özellikler (ücretsiz, kredi ve onay gerekmez)

### 6.1 Retro Cam ve Photo Booth

- [ ] **Kamera izni: reddet** *[yalnızca sahip]*
  - Yap: Explore › **Retro Cam** (ya da Edit'teki Retro Cam kartı). **Strike a pose** (*Bir poz ver*) ekranında **Turn on the camera** (*Kamerayı aç*) → sistem penceresinde **Don't Allow**.
  - Beklenen: Sistem penceresinde "Aybuke uses the camera for Retro Cam and Retro Booth…" metni görünür. Reddedince **Camera access is off** (*Kamera erişimi kapalı*) ekranı, **Open Settings** (*Ayarlar'ı aç*) ve **Close** (*Kapat*) gelir. İlk ekrandaki **Not now** kamerayı açmadan kapatır.
- [ ] **Kamera izni: Ayarlar'dan aç** *[yalnızca sahip]*
  - Yap: **Open Settings** → Aybuke › Camera (*Kamera*) iznini aç → uygulamaya dön.
  - Beklenen: İzin değişince iOS uygulamayı yeniden başlatır (normal davranış). Retro Cam'i yeniden açınca canlı önizleme gelir.
- [ ] **Çekim** *[yalnızca sahip]*
  - Yap: Önizlemede yukarı ya da aşağı kaydırarak efekt değiştir: Disposable '98, VHS '86, Digicam '04, Instant '82, Throwback '16, Film Still, Camcorder '06, Neon '84 (Glamour ve Kira Kira canlıda yoktur). **Self-timer** (*Zamanlayıcı*: kapalı → 3 sn → 10 sn), **Flash** (*Flaş*), **Switch camera** (*Kamerayı değiştir*) dene → deklanşöre bas.
  - Beklenen: Çekilen fotoğraf önizlemedekiyle aynı görünür. "Developing…" (*Fotoğrafın hazırlanıyor…*) sonrası inceleme ekranında **Retake** (*Yeniden çek*), **Edit** (*Düzenle*), **Share** (*Paylaş*) ve **Save** (*Kaydet*) var. Kaydetmeden kapatırsan "Discard this shot?" (*Bu kare silinsin mi?*) sorulur.
- [ ] **Photo Booth** *[yalnızca sahip]*
  - Yap: Modu **Booth** (*Kabin*) yap → deklanşöre bas.
  - Beklenen: Her kareden önce 3-2-1 ve "1 of 4" ilerlemesi, toplam 4 kare. İnceleme ekranında **Strip** (*Şerit*) / **Grid** (*Izgara*), **Date** (*Tarih*) çipi ve "Add a caption (optional)" (*Açıklama ekle (isteğe bağlı)*) alanı var. "Printing your strip…" (*Şeridin basılıyor…*) → Save. Açıklamaya uygunsuz bir sözcük yazılırsa engellenir.

### 6.2 Effects, Adjust, Crop

- [ ] **Effects** *[yalnızca sahip]*
  - Yap: Edit › **Effects** (*Efektler*) → fotoğraf seç → VHS '86, Disposable '98, Kira Kira, Digicam '04, Instant '82, Glamour '92, Neon '84, Throwback '16, Camcorder '06, Film Still ve Tiny World'ü dene → **Apply** (*Uygula*) → Save.
  - Beklenen: Panelde "Free for everyone · on your device · no credits" yazar. Film Still'de "Add a subtitle (optional)" alanı vardır ve uygunsuz metin engellenir. Kaydedilen dosyada Aybuke işareti ve yapay zekâ etiketi yoktur.
- [ ] **Adjust ve Crop** *[yalnızca sahip]*
  - Yap: **Adjust** (*Ayarla*) › **Auto** (*Otomatik*) ve kaydırıcılar → Apply. **Crop** (*Kırp*): oranlar, sola döndür, aynala, düzelt → Apply.
  - Beklenen: Başka araca geçince önizleme kaybolmaz; uygulanır ve Undo ile geri alınır.

### 6.3 Cut out (Remove BG)

- [ ] **Arka plan kaldırma** *[yalnızca sahip]*
  - Yap: Edit › **Remove BG** (*Arka Planı Kaldır*; editörün alt çubuğunda **Cut out** / *Dekupe*) → **Remove background** (*Arka planı kaldır*).
  - Beklenen: Ücretsizdir (0 kredi) ve internet gerekmez. Birden çok kişi varsa "Tap who or what to keep" (*Kimi ya da neyi tutacağına dokun*) görünür. **Keep more** (*Ekle*) / **Keep less** (*Çıkar*) fırçası (tek parmak boyar, iki parmak kaydırır ve yakınlaştırır), **Background** (*Arka plan*: renk, gradyan, bulanık orijinal ya da kendi fotoğrafın), **Shadow** (*Gölge*), **Sticker** (*Çıkartma*) menüsünde **Copy as sticker** ("Copied, paste it in a chat") ve **Save sticker**, sonra **Apply**.

### 6.4 Hide faces ve nezaket notu

- [ ] **Nezaket notu** *[yalnızca sahip]*
  - Yap: Birden çok yüzlü bir fotoğrafı Magic Edit ile aç.
  - Beklenen: "Friends in this photo? Ask them before you edit them 💗" notu ve **Only edit me** (*Sadece beni düzenle*), **Hide their faces** (*Yüzlerini gizle*), **They're OK with it** (*Onlar da onayladı*) düğmeleri.
- [ ] **Yüzleri gizleme** *[yalnızca sahip]*
  - Yap: **Hide their faces** ya da Edit › **Hide faces** (*Yüzleri gizle*).
  - Beklenen: Senin dışındaki yüzler seçili gelir; "Check every face. Tap to hide any we missed." yazar. **Blur** (*Bulanık*), **Pixelate** (*Pikselleştir*), **Heart** (*Kalp*), **Star** (*Yıldız*), **Smiley** (*Gülen yüz*) seçenekleri var. Yüze dokunmak gizler ya da gösterir; boş bir yere dokunmak kaçan yüzü örter. **Apply**. Her şey cihazda yapılır, yapay zekâ etiketi eklenmez.

### 6.5 Text & Stickers

- [ ] **Yazı, çıkartma, karalama** *[yalnızca sahip]*
  - Yap: Edit › **Text & Stickers** (*Yazı ve Çıkartma*) → **Text** (*Yazı*) › **Add text** (*Yazı ekle*), **Stickers** (*Çıkartma*), **Doodle** (*Karalama*) → **Apply**.
  - Beklenen: Apply'a kadar öğeler düzenlenebilir. Uygunsuz metin engellenir. Dışa aktarımda emoji yerine uygulamanın çizdiği çıkartmalar kullanılır.

### 6.6 Collage

- [ ] **Kolaj ve kaydırmalı gönderi** *[yalnızca sahip]*
  - Yap: Explore › **Collage** (*Kolaj*) ya da Edit › **Make a collage** (*Kolaj yap*) → **Choose 2–9 photos** (*2–9 fotoğraf seç*) → düzen ve oran seç. **Carousel** (*Kaydırmalı*) ile 2–5 slayt dene → Save.
  - Beklenen: Tek fotoğraf seçersen "Pick at least 2 photos for a collage." uyarısı çıkar. Carousel kaydında "Saved N slides to Photos" yazar ve slaytlar Fotoğraflar'a sırayla eklenir. Bir fotoğrafa dokununca seçilir; sürükleyip yakınlaştırabilir ya da "Tap another photo to swap" ile yer değiştirebilirsin.

### 6.7 Video düzenleyici ve otomatik altyazı

- [ ] **Video düzenleme** *[yalnızca sahip]*
  - Yap: Edit › **Edit a video** (*Video düzenle*) → konuşmalı bir video seç.
  - Beklenen: 5 dakikadan uzun videoda "This video is longer than 5 minutes, so we'll use the first 5:00." yazar. **Auto-cut silences** (*Sessizlikleri otomatik kes*) "Removes X s of silence…" gösterir; efektler ve **Trim** (*Kısalt*) çalışır.
- [ ] **Altyazı (iOS 26)** *[yalnızca sahip]*
  - Yap: **Captions** (*Altyazılar*) › **Add captions** (*Altyazı ekle*).
  - Beklenen: İzin sorulmaz. Dil modeli gerekiyorsa bir kez "Downloading … for captions (one time)…" çıkar (internet ister). Sonra "Listening to your video…" (*Videon dinleniyor…*) ve "N captions" gelir. **Edit** ile metin ve zaman düzenlenir; 4 stil, **Show captions** (*Altyazıları göster*) ve **Copy captions (SRT)** var. Ses ve metin cihazdan çıkmaz.
- [ ] **Altyazı izni** (iOS 17–18 kullanan bir cihaz varsa) *[yalnızca sahip]*
  - Yap: Aynı adımlar → sistemin konuşma tanıma izninde **Don't Allow**.
  - Beklenen: "Speech recognition is off for Aybuke. Turn it on in Settings, or add captions yourself." ve **Open Settings**. İzin verince otomatik altyazı çalışır. Dil cihazda desteklenmiyorsa "Automatic captions aren't available for this language on this device…" yazar.
- [ ] **Kaydetme** *[yalnızca sahip]*
  - Yap: **Save** (*Kaydet*).
  - Beklenen: "Saving your video…" ilerlemesi, ardından "Video saved to Photos ✨" (*Video Fotoğraflar'a kaydedildi ✨*). Altyazılar efektin tarih damgası ya da kamera ekranının üstünde durur ve önizlemeyle aynı görünür.

### 6.8 Best shot

- [ ] **En iyi kareyi bulma** *[yalnızca sahip]*
  - Yap: Edit › **Find your best shot** (*En iyi kareni bul*) → **Choose selfies** (*Selfie'leri seç*), en fazla 12.
  - Beklenen: "Looking at light and focus…" (*Işık ve netlik inceleniyor…*) sonrası bir fotoğrafta **Best light & focus** (*En iyi ışık ve netlik*) çipi görünür. Yüzü olmayan fotoğraflar için "… left out" yazar. **Edit this one** (*Bunu düzenle*) editörü açar. Hiçbir şey yüklenmez.

### 6.9 My Works ve Recently deleted

- [ ] **Tek eser işlemleri** *[yalnızca sahip]*
  - Yap: **My Works**'te bir esere uzun bas: **Share**, **Save to Photos**, **Add to favorites** (*Favorilere ekle*), **Edit**, **Duplicate** (*Çoğalt*), **Delete** (*Sil*).
  - Beklenen: Sil'de "Deleted creations stay in Recently deleted for 30 days." uyarısı ve ardından "Moved to Recently deleted" (*Son silinenler'e taşındı*).
- [ ] **Son silinenler** *[yalnızca sahip]*
  - Yap: **Recently deleted** (*Son silinenler*) çipi → bir esere dokun → **Restore** (*Geri yükle*) ya da **Delete now** (*Şimdi sil*).
  - Beklenen: Eserde kalan gün sayısı ("N days") görünür. Restore sonrası "Back in My Works" (*Eserlerim'e geri döndü*); Delete now önce "This can't be undone." onayı ister.
- [ ] **Toplu seçim** *[yalnızca sahip]*
  - Yap: **Select** (*Seç*) → birkaç eser → alt çubukta Share, Save, Favorite, Delete.
  - Beklenen: Toplu işlemler çalışır; widget'lar silinen eseri göstermez.

### 6.10 Paylaşma

- [ ] **Paylaşım ekranı** *[yalnızca sahip]*
  - Yap: Bir Magic Edit sonucunda kâğıt uçak simgesine dokun.
  - Beklenen: **Share your glow** (*Işıltını paylaş*) ekranında biçimler: **Photo**, **Before / After** (*Öncesi / Sonrası*), **Story card** (*Hikâye kartı*), **Cover star** (*Kapak yıldızı*), **Photo strip** (*Fotoğraf şeridi*, birden çok görselde) ve **Which vibe?** (*Hangi vibe?*, Create'teki iki varyasyonda). Hedefler: **Stories** (*Hikâye*), **Save**, **Copy image** (*Görseli kopyala*), **More apps** (*Diğer uygulamalar*). **Caption** ile **Copy**, ve görünüşe değil havaya dair **Caption ideas** (*Açıklama fikirleri*) var. Yapay zekâ içeriğinde **Add a visible “AI-edited” label** anahtarı ve platformun AI etiketini açma notu bulunur. Ücretsiz kullanıcıda "Free exports carry a small Aybuke mark." ve **Remove it with Pro** (*Pro ile kaldır*) görünür.
- [ ] **Stories** *[yalnızca sahip]*
  - Yap: **Stories**.
  - Beklenen: "Tap Instagram, then Stories ✨" (*Önce Instagram'a, sonra Hikâyeler'e dokun ✨*) ve sistem paylaşım sayfası açılır (Meta App ID tanımlı değil). Açıklama panoya kopyalanır.
- [ ] **Kopyala ve kaydet** *[yalnızca sahip]*
  - Yap: **Copy image** → Notlar'a yapıştır; sonra **Save**.
  - Beklenen: "Image copied" ve "Saved to Photos". Yapay zekâ görselleri "made with AI" meta verisiyle kopyalanır ve kaydedilir.
- [ ] **Diğer yüzleri gizle** *[yalnızca sahip]*
  - Yap: My Works'ten birden çok kişili bir fotoğrafı paylaş → **Hide other faces** (*Diğer yüzleri gizle*).
  - Beklenen: En büyük yüz dışındakiler cihazda bulanıklaşır.
- [ ] **Fotoğraflar izni reddedilince** *[yalnızca sahip]*
  - Yap: Settings › Aybuke › Photos: **None** → bir şey kaydetmeyi dene.
  - Beklenen: "Photos access is off" (*Fotoğraflar erişimi kapalı*) uyarısında **Open Settings**, **Share instead** (*Bunun yerine paylaş*) ve **Cancel** var.

---

## 7. Widget, Live Activity, Control Center, Siri, bildirimler

- [ ] **7.1 Widget'lar** *[yalnızca sahip]*
  - Yap: Ana Ekran'a **My glow** (*Işıltım*, küçük ve orta) ve **Today's trend** (*Günün trendi*, küçük ve orta) ekle. Kilitli Ekran'a My glow (yuvarlak) ve Today's trend (dikdörtgen ve satır içi) ekle.
  - Beklenen: My glow kredi sayısını (Pro'da taç), son eseri ("Your latest" ya da "Make your first glow ✨") ve orta boyda Magic, Cut out, Effects, Video kısayollarını gösterir; her kısayol doğru araca açılır. Magic Edit ve Create sonuçlarında başlık olarak istemin değil "Your latest creation" yazar. Today's trend her gün bir ücretsiz görünüm gösterir ve dokununca o şablonla fotoğraf seçimi açılır.
- [ ] **7.2 Live Activity** *[yalnızca sahip]*
  - Yap: Bir Magic Edit başlat ve hemen Ana Ekran'a çık.
  - Beklenen: Dynamic Island'da ve Kilitli Ekran'da "Creating your glow…" ilerlemesi görünür; başlıkta istem değil araç ya da şablon adı ("Magic Edit") yazar. Bitince "Your glow-up is ready" / "Tap to see it ✨" ve dokununca uygulama açılır. Hata olursa "That one didn't work" / "No credit was used. Tap to try again."
  - **Koddan risk:** Bu metinler Türkçe cihazda da İngilizce kalır (§12-2). Widget kataloğu var, ama Türkçe cihazdaki görünüm denenmedi. Türkçe arayüzde ne gördüğünü not et.
- [ ] **7.3 Control Center denetimleri** (iOS 18+) *[yalnızca sahip]*
  - Yap: Denetim Merkezi'ni düzenle › denetim ekle › "Aybuke": **Magic Edit** (*Sihirli Düzenleme*), **Retro effects** (*Retro efektler*), **Edit a video** (*Video düzenle*), **Retro Cam**, **Retro Booth**.
  - Beklenen: Her biri doğru ekrana açılır; Retro Booth, Retro Cam'i Booth modunda açar. Editör, video düzenleyici, Retro Cam ya da kolaj açıkken gelen bağlantı hiçbir şeyi değiştirmez (kaydedilmemiş iş korunur).
- [ ] **7.4 Siri, Kestirmeler, Spotlight, Eylem düğmesi** *[yalnızca sahip]*
  - Yap: Kestirmeler'de yeni kestirme → "Aybuke" eylemleri: **Apply a Retro Effect** (*Retro Efekt Uygula*), **Open Retro Cam** (*Retro Cam'i Aç*), **Start Retro Booth** (*Retro Booth'u Başlat*), **Make a Collage** (*Kolaj Yap*), **Edit a Photo** (*Fotoğraf Düzenle*). Örnek akış: Fotoğrafları Seç → Apply a Retro Effect (VHS '86) → Fotoğraf Albümüne Kaydet.
  - Beklenen: Apply a Retro Effect uygulamayı açmadan, arka planda düzenlenmiş görüntü dosyasını döndürür (fotoğraf yüklenmez). Türkçe Siri ifadeleri çalışır: "Aybuke uygulamasında Retro Cam'i aç", "Aybuke ile fotoğraf kabini başlat", "Aybuke ile kolaj yap", "Aybuke ile fotoğraf düzenle". Spotlight'ta "Retro Cam" araması kısayolu gösterir; kısayol Eylem düğmesine atanabilir (iPhone 15 Pro ve sonrası).
- [ ] **7.5 Bildirimler ve sessiz saatler** *[yerelde doğrulandı: `NotificationPlanner`; cihazda açık]*
  - Yap: Settings › **Notifications** (*Bildirimler*): **When my glow is ready** (*Işıltım hazır olduğunda*), **When my free credits are back** (*Ücretsiz kredilerim geri geldiğinde*; Pro'da görünmez), **Look of the week** (*Haftanın görünümü*, "Fridays at 5 pm.").
  - Beklenen: Hepsi kapalı başlar. İlkini açınca iOS izin ister. İzin reddedilmişse anahtarlar pasif olur ve **Allow notifications in Settings** (*Ayarlar'da bildirimlere izin ver*) görünür. Alttaki not: gece 9 ile sabah 9 arası ve hafta içi okul saatlerinde bildirim yok.
  - Yap (hazır bildirimi): Settings › Aybuke › **Live Activities** (*Canlı Etkinlikler*) kapat → Create başlat → uygulamadan çık. Bir kez hafta içi 15:00–21:00 arasında, bir kez 21:00'den sonra dene.
  - Beklenen: Uygun saatte "Your images are ready ✨" / "Your edit is ready ✨" gelir (istem yazmaz). 21:00–09:00 arası ve hafta içi 08:00–15:00 arası bildirim **gelmez**, sonradan da gelmez. Live Activity açıkken bildirim yerine Live Activity görünür.
  - Diğerleri: Kredi bildirimi yalnızca bakiye 0 iken kurulur. Yenilenme Türkiye saatiyle 03:00'te olduğu için bildirim hafta sonu 09:00'da, hafta içi 15:00'te gelir. Haftanın görünümü Cuma 17:00'de gelir ve dokununca o görünüm açılır.

---

## 8. Yaş yolları

İki yol var:

- **Apple yaş senaryoları (iOS 26, önerilen):** Sandbox hesabıyla girişliyken Settings › Developer › Sandbox Apple Account › **Manage** › **Age Assurance** altında "Under 13", "13 - 15", "16 - 17" ya da "18+" ile başlayan senaryolardan birini seç. Sonra uygulamada Settings › Age › **Update age range** (*Yaş aralığını güncelle*) › **Continue**. Apple'dan gelen yanıt her zaman kabul edilir; bantlar arasında serbestçe geçebilirsin.
- **Kendi beyanın (menüler):** Apple penceresinde paylaşmayı reddedersen ay ve yıl menüleri çıkar (iOS 26 öncesi cihazlarda menüler doğrudan gelir). Pencere çıkmadan sandbox senaryosu hemen uygulanıyorsa menüleri görmek için sandbox hesabından çıkıp dene ve bunu not et. Ekim 2026'ya göre örnek doğum tarihleri: Ocak 2009 → 16–17, Ocak 2012 → 13–15, Ocak 2015 → 13 yaş altı. Küçük bant her zaman kabul edilir; büyük bant yılda bir kez kabul edilir.

- [ ] **8.1 16–17 (Türkiye mağazası)** *[yalnızca sahip; açık: Türkiye için 18 değeri avukat onayında]*
  - Yap: Bandı 16–17 yap.
  - Beklenen: Settings'te **Age range** "16 to 17" (*16–17 yaş*). Kodda Türkiye için dijital onay yaşı 18 tanımlı (`AgeBand.swift`, "to be completed with counsel"); bu yüzden Türkiye mağazasında sonraki bulut işinde onay ekranı **ebeveyn adımıyla** gelir. ABD mağazasında 16–17 için ebeveyn adımı çıkmaz.
  - Doğrulanamadı: Türkiye için 18 değerinin hukuki onayı (`docs/SAHIP-YAPILACAKLAR.md` §6.1).
- [ ] **8.2 13–15 (ebeveyn adımı)** *[yalnızca sahip]*
  - Yap: Bandı 13–15 yap → bir Magic Edit dene.
  - Beklenen: Onay ekranında **Ask a parent or guardian to read this with you** (*Bunu annen, baban ya da velinle birlikte oku*) ve **A parent or guardian said yes** (*Annem, babam ya da velim onay verdi*) anahtarı var; anahtar kapalıyken **Allow AI processing** pasiftir. Yetişkinken verilen onay artık geçersizdir. Paywall kendiliğinden açılmaz; satın alma yalnızca dokununca mümkündür.
- [ ] **8.3 13 yaş altı (yalnızca cihaz üstü araçlar)** *[yalnızca sahip]*
  - Yap: Bandı 13 yaş altı yap.
  - Beklenen: Create sekmesi kaybolur. Explore'da Magic Edit kartı, kredi hapı, şablon satırları ve "Create from text" yoktur. Edit'in araç ızgarasında yalnızca Effects, Text & Stickers, Remove BG, Adjust, Crop ve Hide faces kalır (Retro Cam, Best shot, kolaj ve video kartları durur). Settings'te Membership, Account, Credits, Notifications ve Cloud AI processing yoktur; Privacy notu "Every tool runs on your device. Your photos are never uploaded." olur. Widget'larda yalnızca ücretsiz araçlar görünür ve Magic Edit denetimi **Cut out** olur. Siri'deki "Edit a Photo" ücretsiz araçları açar. Onay ekranı ve paywall hiç çıkmaz.
- [ ] **8.4 Kendi beyanınla yükseltme engeli** *[yalnızca sahip]*
  - Yap: Menülerle yetişkin bir tarih gir (ör. Ocak 2000).
  - Beklenen: Reddedilir: "That's older than the age range you entered before. You can change it once a year." (*Bu, daha önce girdiğin yaş aralığından daha büyük. Bunu yılda bir kez değiştirebilirsin.*). Sayfada "You can enter a younger age anytime. An older one can be entered once a year." yazar. Apple'ın yanıtı ise her zaman kabul edilir (tasarım gereği). Kendi beyanınla geri dönmenin yolu §9'daki silmedir.
- [ ] **8.5 Onboarding'de genç yolu** (isteğe bağlı, §9'dan sonra) *[yalnızca sahip]*
  - Yap: Silmeden sonra onboarding'de 13–15 seç → **Skip for now**.
  - Beklenen: Paywall açılmaz, doğrudan tur başlar.

---

## 9. Verilerimi ve hesabımı sil (en son yap)

- [ ] **9.1 Silmeden önce not al** *[yalnızca sahip]*
  - Yap: Supabase › Users'taki kullanıcı kimliğini, `credit_wallets` satırını ve RevenueCat'te bu kimliğin büyük harfli müşteri kaydını not et. (§5'te giriş yaptıysan: iPhone'da Settings › [adın] › Sign-In & Security › **Sign in with Apple** listesinde Aybuke'yi gör.)
- [ ] **9.2 Silme** *[yalnızca sahip]*
  - Yap: Settings › Privacy › **Delete my data & account** (*Verilerimi ve hesabımı sil*) → "Delete my data?" (*Verilerim silinsin mi?*) → **Delete my data** (*Verilerimi sil*).
  - Beklenen: Onay metni "Deletes your creations and your account with its credits from our servers, and resets every setting on this device. Subscriptions are managed by Apple and must be cancelled separately." İlerleme göstergesinden sonra "Your data has been deleted." (*Verilerin silindi.*) ve uygulama onboarding'in başına döner.
- [ ] **9.3 Cihazda silinmesi gerekenler** *[yalnızca sahip]*
  - Beklenen: My Works boş (Recently deleted dahil). Onay, yaş bandı, ilgi alanları, görünüm (Light'a döner), son istemler, bildirim tercihleri ve bekleyen bildirimler silinmiş (yalnızca Pro deneme hatırlatması kalır); Bildirim Merkezi'ndeki Aybuke bildirimleri de silinmiş. Live Activity kapanmış. Widget'lar "Make your first glow ✨" ve (Pro değilsen) 2 kredi gösterir. Settings'te giriş yapılmamış görünür (Account bölümü yeniden Sign in with Apple sunar); ipuçları ve tur sıfırlanmış.
- [ ] **9.4 Sunucuda silinmesi gerekenler** *[yalnızca sahip]*
  - Beklenen: Supabase › Users'ta kullanıcı yok. `credit_wallets`, `credit_ledger`, `jobs`, `entitlements`, `reports`, `apple_accounts` ve `merged_users` satırları silinmiş (cascade). Kullanıcıyla bağlantısı olmayan karma install kayıtları (`private.app_installs`, `private.strikes`, `private.cooldowns`) en çok 30 gün kalır (gizlilik politikası; `install_retention_days` = 30). Bu satırlarda kullanıcı kimliği bulunmamalı; kontrol et.
- [ ] **9.5 RevenueCat** *[açık: `REVENUECAT_SECRET_KEY` yok]*
  - Beklenen, `REVENUECAT_SECRET_KEY` varken: müşteri RevenueCat'ten silinir (RevenueCat kuyruğa alır, birkaç dakika sürebilir) ve `pending_revenuecat_deletions` tablosunda bu kimlik için satır kalmaz.
  - Beklenen, anahtar yokken: silme yine tamamlanır; kimlik `pending_revenuecat_deletions` tablosunda bekler ve `account` log'unda "REVENUECAT_SECRET_KEY is not set: RevenueCat deletions wait in pending_revenuecat_deletions" görünür. Anahtar eklenince bir sonraki hesap silmede ya da saatlik `revenuecat-deletions` çağrısında satır silinir (§12-4).
- [ ] **9.6 Apple ile Giriş token'ı** (§5'te giriş yapılmış hesapta) *[yalnızca sahip; anahtarlar ayarlı]*
  - Yap: Girişli hesapla 9.2'yi uygula.
  - Beklenen: Silme tamamlanır ve Aybuke, iPhone'da Settings › [adın] › Sign-In & Security › **Sign in with Apple** listesinden kalkar (Guideline 5.1.1(v)). Sunucuda token yoksa (girişte Apple'ın kodu alınamadıysa) uygulama silmeden önce Apple'ın onay penceresini bir kez daha açar; onaylayınca token iptal edilir. Pencereyi kapatırsan "Confirm with Apple to finish deleting your account." yazar ve **hiçbir şey silinmez**.
  - Sorun olursa: `account` log'unda "Sign in with Apple token NOT revoked for deleted account" ya da "apple token revocation failed" varsa saati ve kullanıcı kimliğini not et (§12-3). Silmenin kendisi yine tamamlanır.
- [ ] **9.7 Silinmemesi gerekenler** *[yalnızca sahip]*
  - Beklenen: Apple aboneliği sürer; iptali Settings › Apple Account › Subscriptions'tan yapılır. Pro aktifse uygulamada yeniden görünür ve onboarding sonunda paywall çıkmaz. Fotoğraflar'a kaydettiklerin ve uygulamanın dil seçimi durur.
- [ ] **9.8 Çevrimdışı silme** *[yalnızca sahip]*
  - Yap: Uçak Modu'nda silmeyi dene.
  - Beklenen: "Check your internet connection and try again." (*İnternet bağlantını kontrol et ve tekrar dene.*) yazar ve **hiçbir şey silinmez**.
- [ ] **9.9 Diğer cihazlar** *[yalnızca sahip]*
  - Not al: Aynı hesapla girişli ikinci cihazda (Mac ya da iPad) Settings › Account'un ne gösterdiğini ve bir yapay zekâ işi denediğinde ne olduğunu yaz.

---

## 10. Mac (Mac Catalyst)

- [ ] **10.1 Kurulum** *[yerelde doğrulandı: `MacWindow.minimumSize` 960×660, `MacShell.swift`; Mac'te açık]*
  - Yap: Mac'te TestFlight uygulamasını aç (Mac App Store'dan) → Aybuke macOS derlemesi → **Install**.
  - Beklenen: Tek pencere açılır; en küçük boyutu **960×660**'tır (kod: `MacWindow.minimumSize`). Bölümler başlık çubuğunda değil, sol kenar çubuğundadır (`MacShell.swift`); pencere başlığı yazısı gizlidir. Settings › Version macOS derleme numarasını gösterir.
  - Not: Eski metin 900×640 yazıyordu; kod 960×660 kullanır. 900×640 yalnızca yakalama boyutudur (§10.9).
- [ ] **10.2 Menü çubuğu** *[yerelde doğrulandı: `MacSupport.swift`; Mac'te açık]*
  - Yap: **Aybuke › Settings…** (⌘,) (*Ayarlar…*), **File › New Creation** (⌘N) (*Yeni Eser*), **File › Open Photo…** (⌘O) (*Fotoğraf Aç…*), **File › Open Video…** (⌥⌘O) (*Video Aç…*), **File › Save** (⌘S), **File › Close** (⌘W), **View › Hide Sidebar** (⌃⌘S) (*Kenar Çubuğunu Gizle*), **View** menüsünde Explore ⌘1, Create ⌘2, Edit ⌘3, My Works ⌘4, **Help › Contact support** (*Destekle iletişime geç*).
  - Beklenen: New Creation Create sekmesini açar. Open Photo… fotoğraf seçiciyi, ardından Magic Edit'i açar. Contact support, hello@buaze.com adresine yeni e-posta açar. Save ve Close ekranda açık olan kapağa etki eder (Save yalnızca kaydedebilen kapaklarda açılır). ⌘W ekrandaki kapağı (editör, kolaj, video düzenleyici, Retro Cam; kaydedilmemiş iş varsa önce sorar), sonra sayfaları, paywall'ı ve Best shot'ı kapatır (§12-11). File › New Window yoktur. Onboarding, tur, bir sayfa ya da editör açıkken komutlar bilerek çalışmaz.
- [ ] **10.3 Sürükle bırak** *[yalnızca sahip]*
  - Yap: Finder'dan bir JPEG, HEIC ya da RAW dosyasını pencereye sürükle.
  - Beklenen: "Drop a photo to edit it" (*Düzenlemek için bir fotoğraf bırak*) kaplaması görünür, sonra editör Magic Edit'te açılır (RAW'da "RAW photo developed with the best settings ✨"). Kolaj karşılama ekranında "Or drop photo files here" yazar.
- [ ] **10.4 Editör kısayolları** *[yerelde doğrulandı: ⌘Return; cihazda açık]*
  - Beklenen: Esc editörü kapatır (kaydedilmemiş iş varsa "Discard your edits?" sorar), ⌘S kaydeder, ⌘Return uygular.
- [ ] **10.5 Retro Cam (Mac kamerası)** *[yalnızca sahip]*
  - Yap: Explore › Retro Cam → **Turn on the camera** → macOS izin penceresi.
  - Beklenen: İzin verilirse canlı önizleme gelir; **Space** fotoğraf çeker ya da booth'u başlatır, Esc kapatır. Reddedilirse "Allow camera access for Aybuke in System Settings › Privacy & Security › Camera." (*Sistem Ayarları › Gizlilik ve Güvenlik › Kamera bölümünden Aybuke'nin kameraya erişmesine izin ver.*) ve **Open System Settings** görünür; izni açıp uygulamayı yeniden açınca çalışır. Kamerası olmayan bir Mac'te Retro Cam kutuları hiç görünmez.
- [ ] **10.6 Uyku ve uyanma sonrası My Works** *[yalnızca sahip]*
  - Yap: My Works'te 5'ten fazla eser varken Mac'i kilitle ya da uyut, sonra uyandır, kilidi aç ve Aybuke'ye dön; yeni bir eser kaydet.
  - Beklenen: Küçük resimler boş kalmaz (gerekirse uygulama öne gelince yeniden yüklenir) ve yeni kayıt çalışır.
  - Sorun olursa: Boş kalan kareleri ekran görüntüsüyle not et (ayrıca bkz. `docs/AI-TODO.md` §2).
- [ ] **10.7 Satın alma ve hesap (evrensel satın alma)** *[yalnızca sahip]*
  - Beklenen: iPhone'daki Pro, aynı Apple Hesabıyla Mac'te de görünür (gerekirse Settings › Restore purchases). Krediler, Sign in with Apple ile girince iPhone'dakiyle aynıdır (§5.3); girişsiz Mac'in kendi anonim hesabı vardır.
  - Doğrulanamadı: Mac'in ücretsiz kredisi iPhone'la aynı App Store kurulum kimliğini paylaşıp paylaşmadığı bu depodan görülemez; Mac'te ayrı bir ücretsiz kredi görünüyorsa not et.
- [ ] **10.8 Mac'te olmayanlar** *[yalnızca sahip]*
  - Beklenen: Live Activity yoktur; "When my glow is ready" açıksa ve Aybuke arka plandaysa bildirim gelir (sessiz saatler dışında). Paylaşma ekranında **Stories** yerine **Share** açılır menüsü vardır. Dil seçimi: System Settings › General › Language & Region › Applications.
- [ ] **10.9 Mac pencere yakalamaları** (ekran görüntüsü için) *[yalnızca sahip; açık: Mac'te yapılmadı]*
  - Yap: Mac'te Aybuke'yi 900×640, 1600×1000 ve yaklaşık 2200×1400 UIKit noktası boyutunda aç ve her birini yakala. 1600×1000 için `-GLWindowSize 1600x1000` kullan ve pencereyi `screencapture -x -o -l <CGWindowID>` ile yakala.
  - Beklenen: Üç boyutta da metin kesilmez, kenar çubuğu ve içerik okunur. Bu yakalamalar `docs/marketing/app-store/` için kullanılır (§11).
  - Sorun olursa: Boyutu ve kesilen öğeyi not et.
  - Kaynak: `docs/SAHIP-YAPILACAKLAR.md` §2.10; `docs/HANDOFF-PROMPT.md`.

---

## 11. App Store Connect: gönderim öncesi kontroller (sahip)

**15 Ekim 2026:** bu bölüm gönderimle kapandı; aşağıdaki işaretler o günün durumudur.

Değerlerin hepsi: [`marketing/app-store-connect-setup.md`](marketing/app-store-connect-setup.md). App Review metni: [`marketing/app-store-listing.md`](marketing/app-store-listing.md).

- [x] **Derlemeler sürümlere bağlı** *[yapıldı 15 Ekim 2026: iOS `20261015.1225`, Mac `20261015.1233`]*
  - Yap: iOS 1.0 › Build ve macOS 1.0 › Build bölümünde bu testte kullandığın derlemeleri seç.
  - Beklenen: İkisi de seçili ve "Missing Compliance" uyarısı yok.
  - Not: Projede `MARKETING_VERSION = 1.0` (`ios/Glowlit.xcodeproj/project.pbxproj`, dört yer) ve App Store Connect'te sürüm "1.0"; eski "1.0.0" uyuşmazlığı artık geçerli değil (§12-6). Derleme listede görünmüyorsa App Store Connect'te sürüm numarasının 1.0 olduğunu kontrol et.
- [x] **Yeni iPhone ve Mac derlemelerinin App Store Connect adımları** *[yapıldı 15 Ekim 2026: manuel imzalama ve altool ile yüklendi; yöntem `AGENTS.md` §6, 2. madde]*
  - Yap: 1) Disk: arşiv için yaklaşık 2 GB boş alan. 2) Gönderilecek commit için CI'ı kontrol et (`6f2959d` için yeşil; `28c16eb` için kayıt yok). 3) iPhone: `ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> scripts/upload-app-store.sh`. 4) Mac: `PLATFORM=mac ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> scripts/upload-app-store.sh`. 5) İşleme bitince (10–30 dk) derlemeleri yukarıdaki iOS 1.0 ve macOS 1.0 sayfalarına bağla.
  - Beklenen: İki derleme işlenmiş ve sürüm sayfalarında seçilebilir. Sürüm numarası 1.0 ile eşleşir.
  - Sorun olursa: Yükleme hatasını ve derleme numarasını not et.
  - Doğrulanamadı: yükleme ve App Store Connect durumu bu ortamdan görülemez. API anahtarı `~/.appstoreconnect/private_keys/` içinde kalır, commit'e girmez.
- [x] **Ekran görüntüleri** *[yapıldı 15 Ekim 2026: 364 görüntü ve en-US iPhone uygulama önizlemesi yüklendi; aşağıdaki "Şu an" ve "Eski" notları o günden öncesine ait]*
  - Beklenen: 12 dilin her biri için iPhone 6.9" (1290×2796) 10, iPad 13" (2064×2752) 10 ve Mac (2880×1800) 8 görüntü; dosyalar `docs/marketing/app-store/<dil>/` altında (iPad `ipad/`, Mac `mac/` alt klasöründe; es-MX İspanyolca `es/` görüntülerini kullanır). Boş ya da yanlış dosya olmamalı.
  - Şu an: `docs/marketing/app-store/` içinde yalnızca `en` ve `tr` var; ikisinde de 9 iPhone, 9 iPad ve 8 Mac görüntüsü var. Diğer on dil yok; iPhone ve iPad için birer görüntü daha eksik. Mac yakalamaları henüz alınmadı (§10.9).
  - Eski: Depodaki `08-consent.jpg` görüntüleri (`en/`, `tr/`, `en/ipad/`, `tr/ipad/`) eski onay ekranını gösteriyor: giriş cümlesi yalnızca xAI'yi adlandırıyor, listede Anthropic (Claude) yerine fal.ai ("Checks results for safety") var ve 30 günlük silme maddesi yok. Hiçbir ekran görüntüsü yüklenmeden önce bu dördü (ve diğer dillerde ve Mac'te çekilecek onay ekranları) bu sürümün derlemesinden `-GLScreenshotScene consent` ile yeniden çekilip `scripts/marketing-images.py` ile yeniden üretilmeli; eskiler App Store Connect'e yüklenmez.
- [x] **Abonelikler ve paketler sürüme ekli** *[yapıldı 15 Ekim 2026: grup, iki abonelik ve iki paket iOS 1.0 ile gönderildi; ilk abonelikler için Çin fiyatı (¥298 / ¥38) girildi, Çin satışta değil]*
  - Yap: iOS 1.0 sayfası › In-App Purchases and Subscriptions › Pro Yearly, Pro Monthly, 30 Credits ve 100 Credits'i ekle. İlk abonelik uygulama sürümüyle birlikte incelemeye gönderilmek zorundadır. macOS sayfasında da bu bölüm varsa aynılarını seç.
  - Beklenen: Her birinde inceleme ekran görüntüsü ve not var, durumları "Ready to Submit"; abonelik grubunun en-US ve tr adları dolu.
  - Karar verildi: abonelik açıklaması sayı içermiyor (`docs/SAHIP-YAPILACAKLAR.md` §2.6).
- [ ] **Paid Apps Agreement Active** *[yalnızca sahip; açık]* (banka ve vergi bilgisi tamam)
- [x] **App Privacy yayında** *[yapıldı 15 Ekim 2026: 10 veri türü; kurulum hash'inin avukatça teyidi açık, SAHIP 6.1]*
  - Beklenen (`docs/marketing/app-store-connect-setup.md` §5): Kendi toplamamız, kullanıcıyla bağlı: Photos or Videos, Other User Content, User ID ve Purchase History (User ID ile Purchase History'de RevenueCat için Analytics da işaretli), ve ödül kayıtlarımız nedeniyle Advertising Data (App Functionality, Third-Party Advertising ve Analytics). Google Mobile Ads SDK'sı, kullanıcıyla bağlı olmayan ve izleme için kullanılmayan (Third-Party Advertising ve Analytics): Coarse Location, Device ID, Product Interaction, Advertising Data ve Performance Data. Izleme (tracking) yok.
  - **Email Address**: Apple ile giriş açık olduğu için beyan edilir (App Functionality, kullanıcıyla bağlı, izleme yok); `PrivacyInfo.xcprivacy` de listeliyor (§12-15).
  - Açık karar 2, kurulum kimliği: Ücretsiz krediler için kullanılan karma (salted hash) kurulum anahtarı ne kurulum dokümanında ne `PrivacyInfo.xcprivacy` içinde var. Veri türü ve kullanıcıyla ilişkisini karara bağla (§12-15).
  - Kontrol: Archive'dan Privacy Report al (Xcode › Organizer) ve yukarıdaki listeyle karşılaştır.
- [ ] **Yaş derecelendirmesi** *[yalnızca sahip; açık: Age Assurance kararı]*
  - Beklenen: Kurulum dokümanı §2'deki gibi dürüst cevaplar ve 13+ ("Override to Higher Age Rating"); Capabilities altında **Advertising** işaretli. Kids kategorisi seçili değil. "Age Assurance" kutusunu dokümandaki nota göre karara bağla.
- [ ] **App Review Information** *[yalnızca sahip; açık: telefon numarası]*
  - Beklenen: Ad, soyad, **telefon** (+90…, sahip doğrular) ve e-posta `hello@buaze.com`. "Sign-in required" işaretsiz. Notlar `app-store-listing.md`'deki "App Review notes" metni; `{{SUPPORT_EMAIL}}` yer tutucusu kalmamış. macOS notuna şu cümle eklenmiş: "On the Mac, Instagram Stories sharing and the Live Activity aren't offered; everything else matches the iOS app."
- [ ] **Export compliance** *[yerelde doğrulandı: `ITSAppUsesNonExemptEncryption` = `false`, `ios/Config/Info.plist`]*
  - Beklenen: Info.plist'te `ITSAppUsesNonExemptEncryption = NO` olduğu için soru gelmez. Gelirse yalnızca HTTPS (standart, muaf şifreleme) kullanıldığını yanıtla.
- [ ] **Fiyat ve bulunabilirlik** *[yalnızca sahip]*
  - Beklenen: Free; **China mainland hariç** tüm ülkeler (174).
- [x] **Sürüm sayfası** *[yapıldı 15 Ekim 2026: Support `https://aybuke.org/support`, Marketing `https://aybuke.org`, telif `2026 Okan Berk Manavoğlu`, yayın türü AFTER_APPROVAL]*
  - Beklenen: Açıklamanın sonunda Terms ve Privacy bağlantıları; anahtar kelimeler ve promosyon metni dolu. Support URL, Marketing URL ve Privacy Policy URL açılıyor. Gizlilik: `https://aybuke.org/legal/en/privacy-policy` ve `https://aybuke.org/legal/tr/gizlilik-politikasi`. Support ve Marketing URL: `https://aybuke.org` (kurulum dokümanı §2), HANDOFF'a göre `https://aybuke.org/support`; karar açık (`docs/SAHIP-YAPILACAKLAR.md` §2.4). macOS açıklamasında Lock Screen ve Dynamic Island satırları yok, iPhone/iPad yerine Mac yazıyor. Release: iOS ve macOS'ta AFTER_APPROVAL (onaylanınca kendiliğinden yayın; SAHIP §2.5).
- [x] **Sunucu ön koşulları (§1.1):** Apple ile giriş anahtarları, `ANTHROPIC_API_KEY` (Claude güvenlik denetimi; `FAL_KEY` ve `XAI_SAFETY_MODEL` boş) ve xAI Zero Data Retention tamam *[15 Ekim 2026]*. RevenueCat silme anahtarı isteğe bağlı ve yok (§9.5).

---

## 12. Koddan görülen riskler (testte özellikle bak)

Bu sürümde düzeltilenler ve açık kalanlar. Canlıya alma 15 Ekim 2026'da tamamlandı: migrasyonlar `20261030000000`'ye kadar, yedi fonksiyon yayında.

1. **İşten sonra bakiye — tamam (kodda).** Bitmiş işlerin (başarılı, başarısız, iptal) yanıtı bakiyeyi taşır ve bakiye iş başlarken hemen gösterilir (`ai-image`, `job_balance`). Kontrol: §3.4, §3.6.
2. **Live Activity metinleri — tamam (kodda).** Başlık ve alt satır widget kataloğundan (`ios/GlowlitWidgets/Localizable.xcstrings`) gelir. Doğrulanamadı: 12 dilin tamamının çevirisi ve Türkçe cihazda görünüm. Kontrol: Türkçe cihazda Dynamic Island (§7.2).
3. **Sign in with Apple token iptali — tamam (kodda ve sunucuda; cihazda açık).** `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` (`backend/supabase/functions/_shared/apple-signin.ts` › `appleConfig()`) 15 Ekim 2026'da eklendi ve giriş 1.0'da açık (`signInWithApple: true`, §5). Token sunucuda yoksa silme Apple'dan yeni bir kod ister. Kontrol: §5 ve §9.6. Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.6.
4. **RevenueCat silme — açık (kuyrukta bekliyor).** `REVENUECAT_SECRET_KEY` (ve v2 anahtarı için `REVENUECAT_PROJECT_ID`; `_shared/revenuecat.ts` › `revenueCatKey()`) yokken silmeler `pending_revenuecat_deletions` tablosunda bekler; anahtar eklenince hesap silmede ve saatlik `POST /account/revenuecat-deletions` çağrısında gönderilir (zamanlama: `docs/SUPABASE-TODO.md` §3). Kontrol: §9.5. Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.7 (isteğe bağlı).
5. **Çıktı denetimi ve bağımsız Claude denetimi — tamam (kodda ve canlıda, 15 Ekim 2026).** Her sonuç önce tek bir çıktı denetiminden geçer (`_shared/moderation.ts`): xAI'nin kendi kararı (filtrelenen ya da eksik görsel işi engeller); fal.ai sınıflandırıcısı yalnızca `FAL_KEY` ile, o da girilmez. Bunun üstüne bağımsız denetim Claude'dur (`_shared/safety.ts`, `ANTHROPIC_API_KEY`, model `claude-haiku-5-5`): düzenlenecek fotoğraf görsel modele gitmeden ve her sonuç teslimden önce denetlenir. İkisi de fail-closed: denetim çalışamazsa sonuç gösterilmez ya da fotoğraf düzenlenmez ve kredi iade edilir. JPEG, PNG ve WebP dışındaki (örneğin HEIC) ya da base64 olarak 10 MB'ı aşan görseller Claude'a gönderilmeden engellenir; uygulama en çok 1536 piksellik JPEG gönderir, bu yüzden normal yüklemeler sığar. Onay ekranı Supabase, xAI ve Anthropic'i listeler (`consentVersion` 2). `XAI_SAFETY_MODEL` girilmez ve Claude varken okunmaz. Kontrol: §1.1 (Claude güvenlik denetimi maddesi) ve §3.4. Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.8.
6. **Sürüm numarası — tamam.** `MARKETING_VERSION = 1.0` (`ios/Glowlit.xcodeproj/project.pbxproj`, dört yer), App Store Connect'te "1.0". Kontrol: §11.
7. **Yeniden kurulum temiz değil — açık.** Oturum Keychain'de `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` ile saklanıyor (`ios/App/Services/Auth/Keychain.swift:22`) ve açılışta okunuyor (`ios/App/Services/Auth/AuthSessionManager.swift:23`). Uygulamayı silip kurmak eski anonim hesabı ve bakiyeyi geri getirir. Kontrol: §1.5.
8. **Bağlantı kopunca iade — tamam (kodda; canlıda açık).** Uygulama geri çekilerek sormaya devam eder ve yalnızca 2 dakika yanıt alamazsa vazgeçer (`ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift`, `offlineGrace` 120 sn). Sunucu, uygulamaya hiç ulaşmayan sonuçları bir saat sonra iade eder (`undelivered`), ulaşıp onaylanmayanları günde en fazla bir kez (`unconfirmed`; `settle_unconfirmed`, `20261017000000`). Kontrol: §3.6.
9. **"Pro on all your devices" metni — tamam.** Hesap metinleri artık Pro'nun Apple Hesabından geldiğini söylüyor. Eski metnin anahtarı string kataloğunda duruyor ama Swift kodunda kullanılmıyor; yalnızca katalog temizliği kaldı. Pro yine yalnızca StoreKit'ten okunuyor.
10. **Onay verilmeden bakiye — tamam (kodda).** Oturum varsa bakiye açılışta, öne gelişte ve satın almadan sonra onaydan bağımsız okunur; yalnızca okumak için hesap oluşturulmaz (`AppModel.refreshServerBalance`). Kontrol: onay vermeden kredi paketi al, uygulamayı kapatıp aç, bakiye paketi göstermeli.
11. **Mac ⌘W editör ve Retro Cam'de — tamam (kodda).** Close (⌘W) ekrandaki kapağı kendi kapatma düğmesiyle kapatır; editör, kolaj, video düzenleyici ve Retro Cam'in çekim incelemesi işi atmadan önce sorar (`AppModel.closeActiveCover`, her kapak kendisi ayarlar; `ios/App/App/MacSupport.swift`). Kontrol: §10.2.
12. **İade ve iptal bildirimleri (App Store Server Notifications V2) — tamam (15 Ekim 2026).** `functions/app-store-notifications` yayında (migrasyon `20261025000000`); RevenueCat (proje ve uygulama artık "Aybuke") her bildirimi bu adrese iletir, App Store Connect RevenueCat'i göstermeye devam eder. İade ya da iptal edilen Pro hemen kapanır, iade edilen paketin kalan kredisi geri alınır. Kontrol: sandbox satın almasından sonra `app-store-notifications` log'unda 200. Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.2, §2.14.
13. **Paylaşılan adresler — karar açık.** Doğrulanmış bir App Store işlemi olmayan kurulumlarda üç strike, aynı ağ adresindeki herkesi cool-down'a sokar (`private.add_strike`, adres anahtarı). Okul ve operatörler adresi paylaşır. Kontrol: §1.1 (kötüye kullanım runbook'u; önce `ops_strikes` ile bakılır). Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.3.
14. **Deneme kredileri ilk ücretli aya geçiyor — karar açık.** Yıllık denemenin 20 kredisi, kullanılmadan kalırsa ilk ücretli dönemin 80 kredisine eklenir; toplam en çok 160 (`private.refresh_subscription`). Kontrol: §4.2 ve §4.4. Karar: `docs/SAHIP-YAPILACAKLAR.md` §5.1.
15. **E-posta ve kurulum kimliği App Privacy'de — e-posta tamam, kurulum kimliği avukatta.** Giriş açık olduğu için e-posta beyan edilir ve `PrivacyInfo.xcprivacy` de listeliyor; App Privacy 15 Ekim 2026'da yayımlandı. Kurulum kimliğinin (karma) beyanı avukatla teyit edilecek. Kaynak: `docs/SAHIP-YAPILACAKLAR.md` §2.7, §6.1.
16. **Mac yazı tipi ve bölümler — açık.** Mac'e özgü kalıntılar (iPhone'da görünmez): yaklaşık 92 zincirli caption ve footnote yazı çağrısı SwiftUI'nin Mac boyutunu koruyor; 12 sabit yazı boyutu Mac'in metin ayarıyla ölçeklenmiyor; "See all" sayfası ile editörün Styles paneli şablon bağlam menüsüne sahip değil; kapak farkındalı araç çubuğu gizlemesi her bölüm yığınında kanıtlanmadı. Kontrol: §10 ve Mac'te ekran yakalamaları (§10.9). Kaynak: `docs/AI-TODO.md` §2 (3. madde ve izleyenler).
17. **Fotoğraf kontrolü hata metni — tamam (kodda).** Fotoğraf kontrolü çalışamadığında ayrı ve doğru bir mesaj gösterilir. Kontrol: §3.5 (başarısız tekrar).

---

## 13. Sorun bildirme şablonu

```text
Madde: §3.4 Magic Edit uçtan uca
Cihaz / sistem / dil: iPhone …, iOS 26.x, Türkçe   (Mac: macOS …)
Derleme: Settings › Version = 1.0 (…)
Hesap durumu: yaş bandı …, Pro (evet/hayır, deneme mi), Apple ile giriş (evet/hayır), sandbox hesabı (TR/ABD/yok)
Zaman (TR): 14.10.2026 16:42
Ne yaptım: …
Beklenen: …
Gördüğüm: …   (ekran görüntüsü ya da kayıt ekle)
Sunucu: jobs.id = …, status = …, error_code = …, credit_ledger satırları …
Engelleyici mi: evet / hayır
```

---

## 14. Gönderim

- [x] **Gönderildi (15 Ekim 2026):** iOS 1.0 ve macOS 1.0 WAITING_FOR_REVIEW, yayın türü AFTER_APPROVAL. Sonraki sürümlerde de aynı kural geçerli: §1.1 ve §11 işaretli, §12'deki riskler için karar verilmiş, engelleyiciler kapalı ve sahip "Her şey hazır. Gönderelim mi?" sorusuna açıkça **evet** demeden **Add for Review** ve **Submit for Review** yapılmaz.

Kaynaklar (Apple): [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox), [Subscription renewal rate in TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/subscription-renewal-rate-in-testflight), [Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings), [Testing age assurance in sandbox](https://developer.apple.com/documentation/storekit/testing-age-assurance-in-sandbox). Proje içi: [`NEXT-STEPS.md`](NEXT-STEPS.md), [`05-compliance.md`](05-compliance.md), [`SUPABASE-TODO.md`](SUPABASE-TODO.md), [`AI-TODO.md`](AI-TODO.md), [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md), [`../backend/README.md`](../backend/README.md).
