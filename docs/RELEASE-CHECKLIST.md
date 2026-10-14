# Aybuke: yayın öncesi gerçek cihaz kontrol listesi

> **Amaç:** App Review'a göndermeden önce Aybuke'yi kendi iPhone'unda (ve Mac'inde), TestFlight derlemesiyle ve canlı backend'e (Supabase + xAI) karşı uçtan uca denemek. Liste koddan çıkarıldı (dal `pink-girls-redesign`, 14 Ekim 2026): ekran adları, düğmeler ve beklenen davranış uygulamadaki gibidir. **Submit for Review** yalnızca sahibin açık onayıyla yapılır (§14).

**Nasıl kullanılır**

- Her madde üç parçadan oluşur: **Yap** (ne yapacaksın), **Beklenen** (ne olmalı), **Sorun olursa** (ne not alacaksın). Tutmayan maddenin kutusunu boş bırak, §13'teki şablonla not al ve devam et.
- Uygulama etiketleri İngilizce arayüzdeki haliyle **kalın**, Türkçe arayüzdeki karşılığı parantez içinde *italik* yazıldı. Örnek: **Delete my data & account** (*Verilerimi ve hesabımı sil*). iOS'un kendi menülerinin Türkçe adları sürüme göre biraz değişebilir.
- Sekmeler: **Explore** (*Keşfet*), **Create** (*Oluştur*), **Edit** (*Düzenle*), **My Works** (*Eserlerim*). **Settings** (*Ayarlar*), Explore'un sağ üstündeki dişliyle açılır (Mac'te Aybuke › Settings…).
- Her notta derleme numarasını yaz: **Settings › Version** (*Sürüm*), ör. `1.0.0 (20261014.1530)`.
- Sunucuyu doğrulamak için Supabase panosunu açık tut (§1.6). Uygulamadaki sayı ile sunucudaki sayı farklıysa sunucu doğrudur.

**Önerilen sıra:** §1 hazırlık → §2 ilk açılış (yetişkin) → §3 ücretsiz kredilerle yapay zekâ → §4 satın almalar → §5 hesap → §6–7 cihaz üstü özellikler ve sistem entegrasyonları → §8 yaş yolları → §9 verileri silme (en son) → §10 Mac → §11 App Store Connect → §14 onay. Sıra önemli, çünkü:

- Ücretsiz deneme ile ilk ay $1.99 aynı abonelik grubundadır. Bir Apple Hesabı bu gruptaki tanıtım tekliflerinden **yalnızca birini** kullanabilir; ikisini de denemek için satın alma geçmişini sıfırlaman ya da ikinci bir hesap kullanman gerekir (§1.3–1.4).
- Yaş bandı istediğin zaman küçültülebilir ama kendi beyanınla büyütülemez (yılda bir). Geri dönmenin yolu §9'daki silmedir.

**Gönderimden önce kapanması gerekenler (özet):** Paid Apps Agreement (§1.1), yeni migration'lar ve fonksiyonlar (`20261017000000_unclaimed_results`, `20261018000000_revenuecat_deletion_queue`, ardından `ai-image` ve `account`; §12), RevenueCat silme anahtarı (kuyruk anahtar gelince gönderir; §9, §12-4), xAI Zero Data Retention (§1.1), derleme sürümü `1.0.0` ile App Store Connect'teki `1.0` (§11, §12-6), App Review notları ve telefon (§11). Sign in with Apple bu sürümde gizli (§5); açmadan önce token iptali anahtarları gerekir (§12-3).

---

## 1. Hazırlık

### 1.1 Ön koşullar (bunlar yoksa satın alma ve yapay zekâ testleri anlamsız)

- [ ] **Paid Apps Agreement etkin** (yalnızca sahip: banka ve vergi)
  - Yap: App Store Connect › Business (Agreements, Tax, and Banking) › Paid Apps.
  - Beklenen: Durum **Active**. Apple'ın sandbox belgesine göre bu sözleşme imzalanmadan sandbox'ta satın alma test edilemez; paywall'da **Subscriptions are unavailable right now.** (*Abonelikler şu anda kullanılamıyor.*) görünür.
  - Sorun olursa: Durumu not et; §4'ü ertele, diğer bölümlerle devam et.
- [ ] **Dört ürün tanımlı ve "Ready to Submit"**
  - Yap: App Store Connect › Aybuke › Subscriptions (grup **Aybuke Pro**: `app.glowlit.pro.yearly`, `app.glowlit.pro.monthly`) ve In-App Purchases (`app.glowlit.credits.30`, `app.glowlit.credits.100`).
  - Beklenen: Yıllıkta 1 hafta ücretsiz deneme, aylıkta 1 ay $1.99 tanıtım fiyatı; en-US ve tr metinleri ve fiyatlar dolu. Ürün bilgisindeki değişikliklerin sandbox'a yansıması bir saati bulabilir.
  - Sorun olursa: "Missing Metadata" olanı not et. Uygulama dört ürünün hepsini bekler: eksik ürün listede görünmez; hiç plan ya da hiç paket yüklenmezse "unavailable" yazısı ve **Try again** çıkar.
- [ ] **Backend canlı, derleme demo modunda değil**
  - Yap: Supabase › Edge Functions: `ai-image`, `credits-redeem`, `account`, `report` yayında. SQL Editor'da `select jobname, schedule from cron.job;` → `sweep-jobs`, `*/5 * * * *`.
  - Beklenen: TestFlight derlemesinde Explore'da **Preview build: AI results are samples** bandı **yok**, sonuçlarda "DEMO PREVIEW" damgası yok.
  - Sorun olursa: Bant görünüyorsa derleme demo modundadır; bu derleme incelemeye asla gönderilmez.
- [ ] **Sunucu gizli değerleri** (yalnızca adlarına bak, değerleri hiçbir yere yazma)
  - Yap: Supabase › Edge Functions › Secrets.
  - Beklenen: `XAI_API_KEY`, `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_ID`, `OUTPUT_MODERATION` var. Ayrıca `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` (hesap silmede Apple token iptali), `REVENUECAT_SECRET_KEY` ve `REVENUECAT_PROJECT_ID` (hesap silmede RevenueCat müşterisini silme) olmalı. `FAL_KEY` için karar ver (§12-5). İsteğe bağlı `XAI_SAFETY_MODEL` (bir xAI görme modeli) boşsa kapalıdır; ayarlanırsa denetim hata, zaman aşımı veya beklenmeyen bir yanıt verdiğinde iş engellenir ve kredi iade edilir.
  - Sorun olursa: Eksikleri listele. §9'daki ilgili maddeler eksik anahtarla başarısız olur.
- [ ] **xAI Zero Data Retention açık** (sahibin işi, henüz doğrulanmadı)
  - Yap: console.x.ai › ekip ayarları.
  - Beklenen: Açık. Onay ekranı ve gizlilik politikası "1 saat içinde silinir" diyor.

### 1.2 TestFlight (internal testing)

- [ ] **Derleme hazır ve sana dağıtıldı**
  - Yap: App Store Connect › TestFlight › iOS'ta derleme "Ready to Test" olmalı. Kendini Internal Testing grubuna ekle; iPhone'da TestFlight uygulamasından **Install**.
  - Beklenen: İşleme 10–30 dk sürer; şifreleme sorusu çıkmaz (`ITSAppUsesNonExemptEncryption = NO`).
  - Sorun olursa: "Missing Compliance" ya da işleme hatası e-postasını not et.
- [ ] **Doğru derlemeyi kullandığını doğrula**
  - Yap: Aybuke › Settings › Version.
  - Beklenen: TestFlight'taki derleme numarasıyla aynı.

### 1.3 Sandbox Apple Hesabı (TestFlight'ta da kullanılabilir)

Apple'ın güncel belgesine göre TestFlight'tan indirilen uygulama her zaman sandbox ortamında çalışır. Kendi Apple Hesabınla satın alırsan ücret alınmaz, ama abonelikler süreden bağımsız **günde bir** yenilenir (1 hafta içinde en fazla 6 kez) ve satın alma geçmişini sıfırlayamazsın. Sandbox kontrolleri (yenileme hızı, geçmişi sıfırlama, yaş senaryoları) için Sandbox Apple Hesabıyla giriş gerekir.

- [ ] **Sandbox test hesabı oluştur**
  - Yap: App Store Connect › Users and Access › Sandbox › Test Accounts › **+**. Daha önce Apple Hesabı olmamış bir e-posta kullan (ör. kendi adresinin `+sandbox1` takma adı). Bir hesabı **Türkiye**, birini **ABD** mağazası yap; parolaları şifre yöneticisine kaydet.
  - Beklenen: Hesaplar listede görünür. Mağaza sonradan App Store Connect'ten değiştirilebilir; değiştirince cihazda sandbox hesabından çıkıp yeniden gir.
- [ ] **Geliştirici Modu** (Developer settings için gerekli)
  - Yap: iPhone'u kabloyla Mac'e bağla, "Bu bilgisayara güven" de; Xcode'da cihaz eşleştirmesini başlat (Window › Devices and Simulators; yeni Xcode sürümlerinde Device Hub). Apple Hesabıyla Xcode'a girmek gerekmez; Geliştirici Modu anahtarı ancak eşleştirmeden sonra görünür. Sonra iPhone'da Settings › Privacy & Security › **Developer Mode** (*Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu*) → aç → yeniden başlat → **Enable**.
  - Beklenen: Settings'te **Developer** (*Geliştirici*) bölümü görünür.
- [ ] **TestFlight için sandbox hesabıyla giriş**
  - Yap: 1) Aybuke'yi TestFlight'tan normal hesabınla kur. 2) Settings › [adın] › **Media & Purchases** (*Medya ve Satın Almalar*) › **Sign Out**. 3) Settings › **Developer** › en altta **Sandbox Apple Account** › **Sign In** › sandbox hesabı.
  - Beklenen: Satın almalar artık sandbox hesabına yazılır. Sandbox alanı Developer'da yoksa Settings › App Store'un en altına bak (bazı iOS 18 sürümlerinde orada görünüyor).
  - Dikkat: Apple'a göre Media & Purchases'tan çıkmak diğer uygulamalarda satın aldığın içeriğe erişimi etkileyebilir; mümkünse ayrı bir test cihazı kullan. Test bitince Media & Purchases'a geri gir (TestFlight satın almaları yeniden kendi hesabına yazılır).
- [ ] **Yenileme hızını seç**
  - Yap: Settings › Developer › Sandbox Apple Account › **Manage** › Renewal Rate (ya da App Store Connect'ten).
  - Beklenen: Varsayılan "Every 5 minutes": 1 hafta = 3 dk, 1 ay = 5 dk, 1 yıl = 1 saat; abonelik 12 kez yenilenir, sonra kendiliğinden biter. Yıllık deneme bu ayarla 3 dakika sürer.

### 1.4 Satın alma geçmişini sıfırlama

- [ ] **Sandbox hesabı:** Settings › Developer › Sandbox Apple Account › **Manage** › **Clear Purchase History**, ardından sandbox hesabından çıkıp tekrar gir (önbellek temizlenir). Aynı işlem App Store Connect › Users and Access › Sandbox › hesabı seç › **Clear Purchase History** ile de yapılır.
  - Beklenen: Geçmiş boşalır, hesap tanıtım tekliflerine (deneme, ilk ay $1.99) yeniden uygun olur. Geri alınamaz.
- [ ] **Kendi Apple Hesabınla TestFlight:** Geçmiş sıfırlanamaz. Bu yolda gruptaki iki tanıtım teklifinden yalnızca birini deneyebilirsin. Hangisini denediğini not et.

### 1.5 Temiz kurulum

- [ ] **Gerçekten sıfırdan başla**
  - Yap: Aybuke daha önce kuruluysa önce uygulamada Settings › **Delete my data & account** (*Verilerimi ve hesabımı sil*) › **Delete my data** (*Verilerimi sil*) yap. Sonra uygulamayı sil ve TestFlight'tan yeniden kur.
  - Neden: Oturum Keychain'de saklanıyor ve iOS uygulama silinince Keychain'i temizlemiyor (`ios/App/Services/Auth/Keychain.swift:22`). Yalnızca silip kurarsan eski anonim hesap, bakiyesi ve varsa Apple ile girişin geri gelir (§12-7).
  - Beklenen: Onboarding'in ilk sayfası açılır; Settings › Account'ta "Signed in with Apple" yazmaz.

### 1.6 Doğrulama araçları (test boyunca açık tut)

- [ ] **Supabase panosu:** Authentication › Users (anonim ve Apple kullanıcıları). Table Editor'da `credit_wallets` (bakiye = `daily` + `subscription` + `purchased`), `credit_ledger` (`hold`, `release`, `grant_pack`), `jobs` (`status`, `cost`, `retry_of`, `retried`, `error_code`), `entitlements` (`environment` = Sandbox), `reports`. Ayrıca Edge Functions › Logs.
- [ ] **RevenueCat panosu:** Customers listesinde sandbox verisini göster. RevenueCat yalnızca satın alan kişi için açılır; müşteri kimliği, Supabase kullanıcı kimliğinin büyük harfli halidir.
- [ ] **Ekran kaydı:** Denetim Merkezi'nden. Bir hatayı göstermenin en hızlı yolu.

---

## 2. İlk açılış (yetişkin yolu)

- [ ] **2.1 Tanıtım sayfaları**
  - Yap: İlk iki sayfada **Continue** (*Devam et*) ya da **Skip** (*Atla*).
  - Beklenen: Atla seni yaş adımına götürür; yaş adımı atlanamaz.
- [ ] **2.2 Yaş adımı (yetişkin)**
  - Yap: iOS 26 ve sonrası: **Your age range** (*Yaş aralığın*) › **Continue** → Apple'ın yaş aralığı penceresi → paylaş. Pencere çıkmazsa ya da paylaşmazsan **When were you born?** (*Ne zaman doğdun?*) menüleri gelir: **Month** (*Ay*) ve **Year** (*Yıl*), ör. Ocak 2000 → **Continue**.
  - Beklenen: Menülerde hiçbir şey önceden seçili değildir; yalnızca yaş bandı cihazda saklanır. Sonra **What are you here for?** ilgi alanları sayfası gelir.
  - Sorun olursa: Kayan düğme ya da kesik yazı varsa ekran görüntüsü al (özellikle büyük yazı boyutunda).
- [ ] **2.3 Try Digicam '04 on your photo** (*Digicam '04 efektini fotoğrafında dene*)
  - Yap: **Start with your photo** (*Fotoğrafınla başla*) → bir selfie seç.
  - Beklenen: Efekt cihazda uygulanır (internet gerekmez), önce/sonra kaydırıcısı görünür. Onay ekranı çıkmaz, kredi düşmez. Altta **Keep editing** (*Düzenlemeye devam et*) ve **Save to My Works** (*Eserlerim'e kaydet*) var.
  - Yap: **Save to My Works**.
  - Beklenen: "Saved to My Works ✨" (*Eserlerim'e kaydedildi ✨*). Ardından X ile kapatılabilen yumuşak paywall çıkar (yalnızca yetişkinlerde ve Pro değilsen). Kapatınca kısa tur gelir: **Next** (*İleri*) / **Skip** (*Atla*).
  - Alternatifler: **Keep editing** ile editör Effects'te açılır ve paywall editör kapanınca gelir. **Skip for now** (*Şimdilik atla*) doğrudan paywall'a gider.
  - Sorun olursa: Paywall hiç gelmediyse ya da editör açıkken geldiyse not et.
- [ ] **2.4 Explore ilk görünüm**
  - Beklenen: Üstte "Aybuke", şimşek simgeli kredi hapında **2** ve dişli var. **Magic Edit** kartı (**Try it on your photo** / *Fotoğrafında dene*) ve **Quick tools** (*Hızlı araçlar*): Retro Cam, Effects, Enhance, Remove BG, Erase, Styles, Adjust, Collage, Video, Best shot. 1 Ekim–2 Kasım arasında **Spooky season** (*Halloween havası*) satırı görünür.
  - Sorun olursa: "Preview build" bandı görünüyorsa bu engelleyicidir.

---

## 3. Krediler ve yapay zekâ (canlı backend)

- [ ] **3.1 Günlük ücretsiz krediler**
  - Yap: Settings › **Credits** (*Krediler*).
  - Beklenen: **Credits left** (*Kalan krediler*) 2. Altında "You get 2 free credits every day…" yazar. Sunucu günlük kredileri her gün 00:00 UTC'de (Türkiye saatiyle 03:00) 2'ye tamamlar; krediler birikmez.
- [ ] **3.2 Güvenlik filtresi** (onay ekranından ve krediden önce çalışır)
  - Yap: Explore › Magic Edit › bir fotoğraf → kutuya `make me thinner` (Türkçe: `beni daha zayıf yap`) yaz → yukarı ok.
  - Beklenen: Onay ekranı ya da paywall açılmadan hata çıkar: "Aybuke keeps you, you. Try hair color, makeup colors, outfits, light or backgrounds." (*Aybuke seni sen olarak tutar…*). Sunucuya istek gitmez, kredi düşmez.
- [ ] **3.3 Onay ekranı** (ilk bulut işi)
  - Yap: **Give me pink hair** çipine dokun → gönder.
  - Beklenen: **Your photos, your call** (*Fotoğrafların, senin kararın*) ekranı açılır. "Deleted from our servers within an hour" ve "Never used to train AI models" maddeleri var. **Who processes what you send** (*Gönderdiklerini kim işliyor*) altında yalnızca Supabase (*Sunucularımız: yapay zekâ işlerin ve kredilerin*) ve xAI (Grok Imagine) (*Görselleri oluşturur ve düzenler*) listelenir (`FAL_KEY` yokken fal.ai hiçbir şey görmez). Daha önce fal.ai'lı listeye onay verdiysen onay ekranı bir kez daha açılır. **Read our Privacy Policy** uygulama içinde açılır. Düğmeler eşit ağırlıktadır: **Allow AI processing** (*Yapay zekâ ile işlemeye izin ver*) ve **Not now** (*Şimdi değil*).
  - Yap: Önce **Not now**.
  - Beklenen: Hiçbir şey gönderilmez, editör açık kalır, Supabase'te yeni kullanıcı oluşmaz.
  - Yap: Tekrar gönder → **Allow AI processing**.
- [ ] **3.4 Magic Edit uçtan uca**
  - Beklenen: "Applying your edit…" (*Düzenlemen uygulanıyor…*) katmanında **Cancel** (*Vazgeç*) ve ilk seferde **Ping me when it's ready** (*Hazır olunca bana haber ver*) görünür. İş başlayınca Live Activity de başlar; uygulamadan çıkınca Dynamic Island'da görürsün (§7.2). Sonuç genellikle bir dakikadan kısa sürede gelir (3 dakikayı geçerse zaman aşımı ve iade). Önce/sonra karşılaştırma açık gelir; **Hold to see original** (*Orijinali görmek için basılı tut*); **Still you** (*Hâlâ sensin*) etiketi; **Retry free** (*Ücretsiz tekrar dene*) ya da **Doesn't look like you? Retry free** (*Benzemedi mi? Ücretsiz tekrar dene*); bayrak simgesi (Report).
  - Sunucu: `jobs`'ta yeni satır `completed` ve `cost = 1`; `credit_ledger`'da −1 `hold`; `credit_wallets` toplamı 1. Uygulama sonucu indirince `outputs` alanı boşaltılır.
  - Uygulamadaki bakiye: İş başlar başlamaz hap 1'e düşer (sunucunun 202 yanıtındaki bakiye); iş bitince Settings › Credits left da 1'dir, widget iş bitince güncellenir. Uygulamayı kapatıp açınca da 1 kalmalı.
  - Yap: Üst çubukta **Save** (*Kaydet*).
  - Beklenen: İlk kayıtta Fotoğraflar için "yalnızca ekleme" izni sorulur, sonra "Saved to Photos" (*Fotoğraflar'a kaydedildi*). Ücretsiz kullanıcıda resmin köşesinde küçük Aybuke işareti bulunur; eser My Works'e de eklenir.
  - Sorun olursa: Hata metnini, saati ve `jobs.error_code` değerini yaz.
- [ ] **3.5 Bir kez ücretsiz tekrar (Likeness Lock)**
  - Yap: Sonuçtan sonraki 15 dakika içinde **Retry free**.
  - Beklenen: Aynı iş aynı başlangıç fotoğrafıyla tekrar çalışır, kredi düşmez. Başarılı olunca düğme kaybolur; ücretli sonuç Undo (geri al) ile geri gelir. Supabase'te yeni `jobs` satırı `cost = 0` ve `retry_of` dolu, eski satırda `retried = true`; `credit_ledger`'da yeni `hold` yoktur. 15 dakika sonra düğme hiç görünmez.
  - Sorun olursa: Tekrar denemede kredi düştüyse engelleyicidir (paywall "Plus a free retry if it doesn't look like you" diyor).
- [ ] **3.6 Başarısız ya da iptal edilen işte iade**
  - Yap: Yeni bir Magic Edit başlat, katman görünürken **Cancel**.
  - Beklenen: Supabase'te `jobs.status = cancelled`, aynı iş için `credit_ledger`'da `hold` ve `release` (net 0). Uygulamayı yeniden açınca bakiye işten önceki değerdedir.
  - Yap: İş sürerken Uçak Modu'nu aç, 30 saniye bekle, kapat.
  - Beklenen: Uygulama vazgeçmez; bağlantı gelince sonuç normal şekilde gelir ve bakiye 1 düşmüş olur.
  - Yap (isteğe bağlı): İş sürerken Uçak Modu'nu aç ve 2 dakikadan uzun açık bırak.
  - Beklenen: "The connection dropped before your result arrived. If it never reaches you, your credit comes back automatically within about an hour." (*Sonucun gelmeden bağlantı koptu. Sonuç sana ulaşmazsa kredin yaklaşık bir saat içinde otomatik olarak iade edilir.*). Live Activity "Failed creations are refunded automatically…" der. Yaklaşık 1 saat sonra Supabase'te iş `failed` ve `error_code = undelivered` olur, `credit_ledger`'da aynı iş için `release` vardır; uygulamayı öne getirince bakiye geri gelmiş görünür.
- [ ] **3.7 Create uçtan uca**
  - Yap: **Create** sekmesi → bir fikir yaz ya da **Inspire me** (*İlham ver*) → **Style** (*Stil*) ve **Size** (*Boyut*) seç → **Generate** (*Oluştur*, 1 kredi).
  - Beklenen: Apple Intelligence olan cihazda **Make it magic** (*Sihir kat*) ve "Written on your device by Apple Intelligence"; yoksa **Enhance prompt** (*Komutu geliştir*). Sonra "Creating your image…" (*Görselin oluşturuluyor…*) ve **Your creation** (*Eserin*) ekranı. Sonuç anlık fotoğraf gibi belirir ve kendiliğinden My Works'e eklenir. **Images** (*Görsel sayısı*) bölümünde 2–4 kilitlidir; seçip Generate'e basınca paywall açılır.
  - Yap: **Regenerate** (*Yeniden oluştur*).
  - Beklenen: Önce "Regenerate?" onayı çıkar ("Same prompt and style, new pictures. Uses 1 credit, refunded if it fails."); onaylayınca aynı istemle yeni görsel gelir.
  - Yap: Sağ üstte **…** (More) → **Report this image** (*Bu görseli bildir*) → bir neden seç.
  - Beklenen: "Thanks — we'll review this image." (*Teşekkürler — bu görseli inceleyeceğiz.*) ve Supabase `reports` tablosunda yeni satır.
- [ ] **3.8 Krediler bitince**
  - Yap: Ücretsiz kullanıcıyken 2 krediyi bitir, bir iş daha dene.
  - Beklenen: Sunucu "yetersiz kredi" der ve paywall açılır. Altında **Or wait for your free daily credits. Remind me when they're back** (*Ya da günlük ücretsiz kredilerini bekle. Geri gelince bana hatırlat*) bağlantısı var; dokununca bildirim izni sorulur, "We'll remind you when your free credits are back ✨" görünür ve paywall kapanır. Eski kalmış bakiye bu noktada 0'a düzelir.
  - Pro kullanıcıda aylık krediler bitince paywall yerine **You've used this month's credits** (*Bu ayın kredilerini kullandın*) sayfası ve kredi paketleri gelir (§4 sonrası dene).
- [ ] **3.9 Çevrimdışı**
  - Yap: Uçak Modu'nu aç.
  - Beklenen: Explore'da "You're offline. Effects, Adjust, Cut out and Video still work." (*Çevrimdışısın. Efektler, Ayarla, Dekupe ve Video çalışmaya devam ediyor.*) notu görünür. Magic Edit ve Create aynı uyarıyı verir; hiçbir şey gönderilmez, kredi düşmez. Effects, Adjust, Cut out ve video düzenleyici çalışır. Uçak Modu kapanınca not kaybolur.
- [ ] **3.10 Onayı Settings'ten değiştirme**
  - Yap: Settings › **Privacy** (*Gizlilik*) › **Cloud AI processing** (*Bulutta yapay zekâ işleme*) anahtarını kapat → bir Magic Edit dene.
  - Beklenen: Onay ekranı yeniden açılır. Anahtarın altında aynı iki işleyen (Supabase ve xAI) listelenir; anahtarı açınca da aynı onay ekranı gelir.
- [ ] **3.11 Ertesi gün yenilenme**
  - Yap: Ertesi gün Türkiye saatiyle 03:00'ten sonra uygulamayı aç.
  - Beklenen: Ücretsiz kullanıcıda bakiye 2 olur (4 olmaz). Pro'da günlük kredi 0'dır, aylık krediler devam eder.
- [ ] **3.12 Ideas for this photo ve Surprise me** (ücretsiz)
  - Yap: Editörde fotoğrafın altındaki **Ideas for this photo** (*Bu fotoğraf için fikirler*) → **Surprise me** (*Şaşırt beni*).
  - Beklenen: Uygun bir ücretsiz efekt hemen uygulanır (kredi ve onay yok). Bir görünüm (look) önerisi seçersen önce "Try …?" onayı ve kredi bilgisi gelir.
- [ ] **3.13 Image Playground** (yalnızca iOS 18.4+ ve Apple Intelligence destekli cihazda)
  - Yap: Create › **Create with Image Playground** (*Image Playground ile oluştur*).
  - Beklenen: Apple'ın penceresi açılır; Aybuke onayı ve kredisi kullanılmaz. Sonuç My Works'e kaydedilir. iOS 27'de ilk kullanımda "Image Playground is Apple's" uyarısı çıkar.
  - Uyumluluk kontrolü ([`05-compliance.md`](05-compliance.md)): Apple penceresinde uygunsuz ya da vücut değiştiren istemler yaz, "photorealistic" dene ve kendi fotoğrafını eklemeyi dene. Gerçekçi bir selfie düzenlemesi geçiyorsa yayından önce bildir.

---

## 4. Satın almalar (sandbox / TestFlight)

Fiyatlar ABD mağazasında: Yıllık $39.99 (7 gün ücretsiz), Aylık $5.99 (ilk ay $1.99), 30 kredi $2.99, 100 kredi $7.99. Türkiye mağazasında App Store Connect'teki TRY karşılıkları görünür. Satın alma penceresinde "Environment: Sandbox" ibaresini ve hangi hesabın kullanıldığını not et.

- [ ] **4.1 Paywall ürünleri yüklüyor**
  - Yap: Ücretsiz kullanıcıyken Explore'daki kredi hapına dokun.
  - Beklenen: **Your photos, in their best light** (*Fotoğrafların, en güzel ışığında*) başlığı ve avantajlar. **Yearly** (*Yıllık*) önceden seçili, **BEST VALUE** (*EN AVANTAJLI*) rozetli; büyük yazıyla "… / year", altında "7 days free, then …/year · just …/month". **Monthly** (*Aylık*) **TRY IT** (*DENE*) rozetli, altında "First month $1.99, then $5.99/month · cancel anytime". **No weekly plans, ever.** (*Haftalık plan yok, asla.*) yazar. Altta **Restore** (*Geri yükle*), **Terms** (*Koşullar*), **Privacy** (*Gizlilik*) ve otomatik yenileme metni, sağ üstte X var. **Sign in** bu sürümde yoktur (§5). Terms ve Privacy uygulama içinde açılır.
  - Sorun olursa: 10 saniye sonra "Couldn't reach the App Store. Check your connection." ve **Try again** (*Tekrar dene*) ya da "Subscriptions are unavailable right now." görünürse §1.1'i kontrol et ve ekran görüntüsü al.
- [ ] **4.2 Pro Yearly ve 7 günlük ücretsiz deneme**
  - Yap: Yearly seçiliyken ekranı aşağı kaydır.
  - Beklenen: **How your free trial works** (*Ücretsiz deneme nasıl işler?*) kartında: **Today** (*Bugün*) "Unlock everything. No charge today.", **Day N** (*N. gün*) "We'll remind you before your trial ends.", **Day 7** "You'll be charged … on … unless you cancel before." Düğmede yalnızca **Continue** (*Devam et*) yazar; hemen altında düğme boyutunda "7 days free, then **$39.99**/year" (yinelenen fiyat kalın).
  - Yap: **Continue** → Apple penceresinde koşulları gör → onayla.
  - Beklenen: "Welcome to Aybuke Pro ✦ Your free trial ends <tarih saat>." (*Aybuke Pro'ya hoş geldin ✦ Ücretsiz denemen … tarihinde bitiyor.*) Paywall kapanır; bu sürümde ardından hesap sayfası **açılmaz** (Sign in with Apple gizli, §5). Kredi hapında taç simgesi görünür. Settings › **Membership** (*Üyelik*): **Aybuke Pro**, "Free trial until …" (*Ücretsiz deneme … tarihine kadar*) ve **Manage subscription** (*Aboneliği yönet*).
  - Sunucu: `entitlements`'ta yeni satır (`environment` Sandbox). Pro ilk görüldüğünde `credit_wallets.subscription` 100 olur; o günün kalan ücretsiz kredileri de durur, ertesi günden itibaren günlük 0'dır. Uygulama, onay vermemiş olsan da, bakiyeyi hemen sunucudan okur (yaklaşık 100 + kalan günlük kredi).
  - Sorun olursa: "Purchase failed" (*Satın alma başarısız oldu*) metnini yaz; Pro görünmüyorsa Settings › Restore purchases dene ve not et.
- [ ] **4.3 Deneme hatırlatması (zamanlama)**
  - Kural (kodda): Hatırlatma, deneme bitişinden **en az 26 saat önceki en geç uygun ana** kurulur. 21:00–09:00 arası ve hafta içi 08:00–15:00 arası atlanır; bu durumda aynı ya da bir önceki akşam 20:59'a çekilir. Örnek: Çarşamba 16:00'da başlayan deneme gelecek Çarşamba 16:00'da biter, hatırlatma Pazartesi 20:59'da gelir ve paywall'da "Day 5" yazar.
  - Yap: Satın almadan önce paywall'daki "Day N" değerinin bu kurala uyduğunu kontrol et.
  - Beklenen, deneme kısaysa (sandbox hesabında dakikalar, TestFlight'ta yaklaşık bir gün): 26 saatlik pay kalmadığı için hatırlatma **kurulmaz** ve bildirim izni de sorulmaz; karşılama mesajı bu yüzden deneme bitiş saatini yazar. Settings › Membership'teki "Free trial until …" ile karşılaştır.
  - Beklenen, deneme 26 saatten uzunsa (gerçek 7 günlük deneme, yayından sonra): satın almanın hemen ardından bildirim izni sorulur, karşılama mesajı tarih yazmaz ve bildirim kurala uygun saatte "Your free trial ends …" / "To avoid the … charge, cancel before … in Settings › Apple Account › Subscriptions." metniyle gelir (*Ücretsiz denemenin bitişi: … / … tutarında ücret alınmaması için … öncesinde Ayarlar › Apple Hesabı › Abonelikler bölümünden iptal et.*). İzin reddedilirse hatırlatma kurulmaz ve mesaj bitiş tarihini yazar.
  - Yap: Deneme sürerken **Manage subscription** → aboneliği iptal et.
  - Beklenen: Pro deneme bitene kadar sürer; gerçek denemede hatırlatma da silinir.
- [ ] **4.4 Pro Monthly ve ilk ay $1.99**
  - Ön koşul: Hesap Pro olmamalı ve bu grupta daha önce tanıtım teklifi kullanmamış olmalı. Sandbox hesabında **Clear Purchase History** ikisini birden sağlar (etkin aboneliği de siler, §1.4); kendi hesabında ikinci bir hesap gerekir. Yıllık denemeyi kullanmış bir hesapta Monthly kartında yalnızca "Cancel anytime" yazar, **TRY IT** rozeti olmaz ve düğme "Continue — …/month" olur. Bu doğru davranıştır.
  - Yap: Uygun hesapla Monthly'yi seç.
  - Beklenen: Düğmede **Continue**, altında "First month $1.99, then **$5.99**/month · cancel anytime". Apple penceresinde ilk dönem $1.99. Satın almadan sonra Pro açılır ve +80 kredi gelir.
- [ ] **4.5 Kredi paketleri (30 ve 100)**
  - Yap: Paywall › **Not ready to subscribe? Get a credit pack** (*Abone olmaya hazır değil misin? Kredi paketi al*) ya da Settings › Credits › **Buy a credit pack** (*Kredi paketi al*).
  - Beklenen: **Credit packs** (*Kredi paketleri*) sayfasında "Pay once. Credits never expire. 1 credit = 1 creation or edit." yazar. İki satırda App Store Connect'teki ad, açıklama ve "≈ … per credit" (*Kredi başına ≈ …*) görünür.
  - Yap: 30'luk paketi al, sonra 100'lük paketi al.
  - Beklenen: Her seferinde "Credits added ✦" (*Krediler eklendi ✦*) ve bakiye hemen +30 / +100 (uygulama sunucunun verdiği yeni bakiyeyi gösterir). `credit_ledger`'da Apple işlem kimliğiyle tek bir `grant_pack` satırı. Paketler tüketilebilir, aynı paket tekrar alınabilir.
  - Sorun olursa: "We couldn't add your credits yet. We'll retry automatically." görürsen uygulamayı kapatıp aç ve kredilerin **bir kez** eklendiğini kontrol et. İki kez eklenirse engelleyicidir.
- [ ] **4.6 Restore purchases**
  - Yap: Settings › Membership › **Restore purchases** (*Satın alımları geri yükle*).
  - Beklenen: Pro varsa "Purchases restored ✦", yoksa "No active subscription found." Paywall'daki **Restore**: Pro varsa paywall kapanır; yoksa "Nothing to restore" / "No active subscription found for this Apple Account." uyarısı çıkar. Kredi paketleri geri yüklenmez, onlar sunucudaki bakiyede durur.
  - Yap: Uygulamayı sil ve TestFlight'tan yeniden kur.
  - Beklenen: Aynı Apple Hesabında Pro, Restore'a basmadan da görünür. Bakiye Keychain'deki oturum sayesinde geri gelir (§1.5).
- [ ] **4.7 Pro bitince**
  - Yap: Aboneliği iptal et ve dönemin bitmesini bekle (sandbox'ta dakikalar ya da saatler; ayrıca 12 yenilemeden sonra sandbox aboneliği kendiliğinden biter).
  - Beklenen: Pro kapanır ve Settings'te **Upgrade to Aybuke Pro** (*Aybuke Pro'ya geç*) görünür. Sunucuda aylık krediler 0'lanır, günlük 2 kredi geri gelir, **paket kredileri kalır**.
- [ ] **4.8 Pro özellikleri ve filigran**
  - Beklenen: Pro'da kilitli görünümler ve stiller açılır; Create'te 2–4 görsel seçilebilir (görsel başına 1 kredi); dışa aktarımda Aybuke işareti olmaz. Ücretsiz kullanıcı kilitli bir şeye dokununca paywall açılır. Cihaz üstü düzenlemelerde hiçbir zaman işaret olmaz.
- [ ] **4.9 Onay bekleyen satın alma (Ask to Buy)** (TestFlight'ta denenemez)
  - Neden: Apple'ın sandbox ayarlarında ebeveyn onayını (Ask to Buy, Texas SB 2420) üreten bir seçenek yok. Arayüz, Xcode'un yerel StoreKit dosyasıyla simülatörde denenir.
  - Yap: Mac'te Xcode'da `ios/StoreKit/Products.storekit`'i aç → **Editor › Enable Ask to Buy** → Debug derlemeyi simülatörde çalıştır (şema bu dosyayı kullanır) → paywall'dan satın al.
  - Beklenen: Düğmede **Waiting for approval** (*Onay bekleniyor*), kartta "Waiting for approval. If it's approved, Pro turns on automatically." (paketlerde "…your credits are added automatically."). **Debug › StoreKit › Manage Transactions** ile onaylayınca "Welcome to Aybuke Pro ✦" gelir. Reddedersen bekleme durumu uygulama yeniden açılana kadar kalır (StoreKit reddi bildirmez).
  - Not: Sunucu Xcode işlemlerini bilerek kabul etmez; paket onayında "We couldn't add your credits yet…" görmen normaldir. Test bitince Ask to Buy'ı kapat ve dosyayı açık haliyle commit etme.
- [ ] **4.10 Kesintili satın alma** (isteğe bağlı, gerçek cihazda geç gelen satın alma yolu)
  - Yap: App Store Connect › Users and Access › Sandbox › hesap › **Interrupt Purchases for This Tester** → sandbox hesabıyla bir kredi paketi al.
  - Beklenen: Apple önce koşulları gösterir. Uygulamada ya "Waiting for approval" ya da bir hata görürsün. Koşulları kabul edince işlem arka planda tamamlanır ve krediler bir kez eklenir. Ne gördüğünü not et; testten sonra seçeneği kapat.
- [ ] **4.11 Satın almalar kapalıyken** (isteğe bağlı)
  - Yap: Settings › Screen Time › Content & Privacy Restrictions › In-app Purchases: **Don't Allow** (*Ekran Süresi › İçerik ve Gizlilik Sınırlamaları*).
  - Beklenen: Paywall'da "Purchases are turned off on this device." (*Bu cihazda satın alımlar kapalı.*) yazar ve satın alma düğmeleri pasif olur; Restore çalışır. Testten sonra ayarı geri aç.
- [ ] **4.12 Paywall'un yaşa göre davranışı** (§8'de tekrar kontrol edilir)
  - Beklenen: Yetişkinde onboarding sonunda bir kez kendiliğinden açılır (kapatılabilir). 13–17 yaşta hiç kendiliğinden açılmaz, yalnızca dokununca açılır. 13 yaş altında hiç yoktur (Membership bölümü de yoktur).

---

## 5. Hesap: Sign in with Apple (bu sürümde gizli)

`ios/App/Resources/AppConfig.json` içinde `"signInWithApple": false`. Kod duruyor; açmak bu tek değer, ama önce sunucuya `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` eklenmeli (silmede token iptali, §12-3) ve App Privacy'de e-posta beyan edilmeli.

- [ ] **5.1 Giriş noktası yok**
  - Yap: Settings'i aç; paywall'ın altına bak; bir kredi paketi ya da abonelik al.
  - Beklenen: Settings'te **Account** (*Hesap*) bölümü yok, paywall'da **Sign in** yok, satın almadan sonra hesap sayfası açılmaz. Hiçbir yerde "Sign in with Apple" düğmesi görünmez. Satın almalar, krediler ve §9'daki silme aynen çalışır.
- [ ] **5.2 Daha önce giriş yapmış test cihazı** (yalnızca eski bir TestFlight sürümünde giriş yaptıysan)
  - Beklenen: Settings › Account yalnızca bu durumda görünür: **Signed in with Apple** ve **Sign out** (*Çıkış yap*). Çıkış yapınca bölüm kaybolur ve bir daha giriş seçeneği sunulmaz.
- [ ] **5.3 Açıldığında** (sonraki bir sürüm, `signInWithApple: true`)
  - Beklenen: Hesap sayfası "Keep your credits on every device" der ve Pro için "Pro works wherever you use the same Apple Account" yazar (Pro, satın alan Apple Hesabından gelir; krediler hesaptan). Giriş sonrası "You're signed in ✨ Your credits now come with you." görünür.

---

## 6. Cihaz üzerindeki özellikler (ücretsiz, kredi ve onay gerekmez)

### 6.1 Retro Cam ve Photo Booth

- [ ] **Kamera izni: reddet**
  - Yap: Explore › **Retro Cam** (ya da Edit'teki Retro Cam kartı). **Strike a pose** (*Bir poz ver*) ekranında **Turn on the camera** (*Kamerayı aç*) → sistem penceresinde **Don't Allow**.
  - Beklenen: Sistem penceresinde "Aybuke uses the camera for Retro Cam and Retro Booth…" metni görünür. Reddedince **Camera access is off** (*Kamera erişimi kapalı*) ekranı, **Open Settings** (*Ayarlar'ı aç*) ve **Close** (*Kapat*) gelir. İlk ekrandaki **Not now** kamerayı açmadan kapatır.
- [ ] **Kamera izni: Ayarlar'dan aç**
  - Yap: **Open Settings** → Aybuke › Camera (*Kamera*) iznini aç → uygulamaya dön.
  - Beklenen: İzin değişince iOS uygulamayı yeniden başlatır (normal davranış). Retro Cam'i yeniden açınca canlı önizleme gelir.
- [ ] **Çekim**
  - Yap: Önizlemede yukarı ya da aşağı kaydırarak efekt değiştir: Disposable '98, VHS '86, Digicam '04, Instant '82, Throwback '16, Film Still, Camcorder '06, Neon '84 (Glamour ve Kira Kira canlıda yoktur). **Self-timer** (*Zamanlayıcı*: kapalı → 3 sn → 10 sn), **Flash** (*Flaş*), **Switch camera** (*Kamerayı değiştir*) dene → deklanşöre bas.
  - Beklenen: Çekilen fotoğraf önizlemedekiyle aynı görünür. "Developing…" (*Fotoğrafın hazırlanıyor…*) sonrası inceleme ekranında **Retake** (*Yeniden çek*), **Edit** (*Düzenle*), **Share** (*Paylaş*) ve **Save** (*Kaydet*) var. Kaydetmeden kapatırsan "Discard this shot?" (*Bu kare silinsin mi?*) sorulur.
- [ ] **Photo Booth**
  - Yap: Modu **Booth** (*Kabin*) yap → deklanşöre bas.
  - Beklenen: Her kareden önce 3-2-1 ve "1 of 4" ilerlemesi, toplam 4 kare. İnceleme ekranında **Strip** (*Şerit*) / **Grid** (*Izgara*), **Date** (*Tarih*) çipi ve "Add a caption (optional)" (*Açıklama ekle (isteğe bağlı)*) alanı var. "Printing your strip…" (*Şeridin basılıyor…*) → Save. Açıklamaya uygunsuz bir sözcük yazılırsa engellenir.

### 6.2 Effects, Adjust, Crop

- [ ] **Effects**
  - Yap: Edit › **Effects** (*Efektler*) → fotoğraf seç → VHS '86, Disposable '98, Kira Kira, Digicam '04, Instant '82, Glamour '92, Neon '84, Throwback '16, Camcorder '06, Film Still ve Tiny World'ü dene → **Apply** (*Uygula*) → Save.
  - Beklenen: Panelde "Free for everyone · on your device · no credits" yazar. Film Still'de "Add a subtitle (optional)" alanı vardır ve uygunsuz metin engellenir. Kaydedilen dosyada Aybuke işareti ve yapay zekâ etiketi yoktur.
- [ ] **Adjust ve Crop**
  - Yap: **Adjust** (*Ayarla*) › **Auto** (*Otomatik*) ve kaydırıcılar → Apply. **Crop** (*Kırp*): oranlar, sola döndür, aynala, düzelt → Apply.
  - Beklenen: Başka araca geçince önizleme kaybolmaz; uygulanır ve Undo ile geri alınır.

### 6.3 Cut out (Remove BG)

- [ ] **Arka plan kaldırma**
  - Yap: Edit › **Remove BG** (*Arka Planı Kaldır*; editörün alt çubuğunda **Cut out** / *Dekupe*) → **Remove background** (*Arka planı kaldır*).
  - Beklenen: Ücretsizdir (0 kredi) ve internet gerekmez. Birden çok kişi varsa "Tap who or what to keep" (*Kimi ya da neyi tutacağına dokun*) görünür. **Keep more** (*Ekle*) / **Keep less** (*Çıkar*) fırçası (tek parmak boyar, iki parmak kaydırır ve yakınlaştırır), **Background** (*Arka plan*: renk, gradyan, bulanık orijinal ya da kendi fotoğrafın), **Shadow** (*Gölge*), **Sticker** (*Çıkartma*) menüsünde **Copy as sticker** ("Copied, paste it in a chat") ve **Save sticker**, sonra **Apply**.

### 6.4 Hide faces ve nezaket notu

- [ ] **Nezaket notu**
  - Yap: Birden çok yüzlü bir fotoğrafı Magic Edit ile aç.
  - Beklenen: "Friends in this photo? Ask them before you edit them 💗" notu ve **Only edit me** (*Sadece beni düzenle*), **Hide their faces** (*Yüzlerini gizle*), **They're OK with it** (*Onlar da onayladı*) düğmeleri.
- [ ] **Yüzleri gizleme**
  - Yap: **Hide their faces** ya da Edit › **Hide faces** (*Yüzleri gizle*).
  - Beklenen: Senin dışındaki yüzler seçili gelir; "Check every face. Tap to hide any we missed." yazar. **Blur** (*Bulanık*), **Pixelate** (*Pikselleştir*), **Heart** (*Kalp*), **Star** (*Yıldız*), **Smiley** (*Gülen yüz*) seçenekleri var. Yüze dokunmak gizler ya da gösterir; boş bir yere dokunmak kaçan yüzü örter. **Apply**. Her şey cihazda yapılır, yapay zekâ etiketi eklenmez.

### 6.5 Text & Stickers

- [ ] **Yazı, çıkartma, karalama**
  - Yap: Edit › **Text & Stickers** (*Yazı ve Çıkartma*) → **Text** (*Yazı*) › **Add text** (*Yazı ekle*), **Stickers** (*Çıkartma*), **Doodle** (*Karalama*) → **Apply**.
  - Beklenen: Apply'a kadar öğeler düzenlenebilir. Uygunsuz metin engellenir. Dışa aktarımda emoji yerine uygulamanın çizdiği çıkartmalar kullanılır.

### 6.6 Collage

- [ ] **Kolaj ve kaydırmalı gönderi**
  - Yap: Explore › **Collage** (*Kolaj*) ya da Edit › **Make a collage** (*Kolaj yap*) → **Choose 2–9 photos** (*2–9 fotoğraf seç*) → düzen ve oran seç. **Carousel** (*Kaydırmalı*) ile 2–5 slayt dene → Save.
  - Beklenen: Tek fotoğraf seçersen "Pick at least 2 photos for a collage." uyarısı çıkar. Carousel kaydında "Saved N slides to Photos" yazar ve slaytlar Fotoğraflar'a sırayla eklenir. Bir fotoğrafa dokununca seçilir; sürükleyip yakınlaştırabilir ya da "Tap another photo to swap" ile yer değiştirebilirsin.

### 6.7 Video düzenleyici ve otomatik altyazı

- [ ] **Video düzenleme**
  - Yap: Edit › **Edit a video** (*Video düzenle*) → konuşmalı bir video seç.
  - Beklenen: 5 dakikadan uzun videoda "This video is longer than 5 minutes, so we'll use the first 5:00." yazar. **Auto-cut silences** (*Sessizlikleri otomatik kes*) "Removes X s of silence…" gösterir; efektler ve **Trim** (*Kısalt*) çalışır.
- [ ] **Altyazı (iOS 26)**
  - Yap: **Captions** (*Altyazılar*) › **Add captions** (*Altyazı ekle*).
  - Beklenen: İzin sorulmaz. Dil modeli gerekiyorsa bir kez "Downloading … for captions (one time)…" çıkar (internet ister). Sonra "Listening to your video…" (*Videon dinleniyor…*) ve "N captions" gelir. **Edit** ile metin ve zaman düzenlenir; 4 stil, **Show captions** (*Altyazıları göster*) ve **Copy captions (SRT)** var. Ses ve metin cihazdan çıkmaz.
- [ ] **Altyazı izni** (iOS 17–18 kullanan bir cihaz varsa)
  - Yap: Aynı adımlar → sistemin konuşma tanıma izninde **Don't Allow**.
  - Beklenen: "Speech recognition is off for Aybuke. Turn it on in Settings, or add captions yourself." ve **Open Settings**. İzin verince otomatik altyazı çalışır. Dil cihazda desteklenmiyorsa "Automatic captions aren't available for this language on this device…" yazar.
- [ ] **Kaydetme**
  - Yap: **Save** (*Kaydet*).
  - Beklenen: "Saving your video…" ilerlemesi, ardından "Video saved to Photos ✨" (*Video Fotoğraflar'a kaydedildi ✨*). Altyazılar efektin tarih damgası ya da kamera ekranının üstünde durur ve önizlemeyle aynı görünür.

### 6.8 Best shot

- [ ] **En iyi kareyi bulma**
  - Yap: Edit › **Find your best shot** (*En iyi kareni bul*) → **Choose selfies** (*Selfie'leri seç*), en fazla 12.
  - Beklenen: "Looking at light and focus…" (*Işık ve netlik inceleniyor…*) sonrası bir fotoğrafta **Best light & focus** (*En iyi ışık ve netlik*) çipi görünür. Yüzü olmayan fotoğraflar için "… left out" yazar. **Edit this one** (*Bunu düzenle*) editörü açar. Hiçbir şey yüklenmez.

### 6.9 My Works ve Recently deleted

- [ ] **Tek eser işlemleri**
  - Yap: **My Works**'te bir esere uzun bas: **Share**, **Save to Photos**, **Add to favorites** (*Favorilere ekle*), **Edit**, **Duplicate** (*Çoğalt*), **Delete** (*Sil*).
  - Beklenen: Sil'de "Deleted creations stay in Recently deleted for 30 days." uyarısı ve ardından "Moved to Recently deleted" (*Son silinenler'e taşındı*).
- [ ] **Son silinenler**
  - Yap: **Recently deleted** (*Son silinenler*) çipi → bir esere dokun → **Restore** (*Geri yükle*) ya da **Delete now** (*Şimdi sil*).
  - Beklenen: Eserde kalan gün sayısı ("N days") görünür. Restore sonrası "Back in My Works" (*Eserlerim'e geri döndü*); Delete now önce "This can't be undone." onayı ister.
- [ ] **Toplu seçim**
  - Yap: **Select** (*Seç*) → birkaç eser → alt çubukta Share, Save, Favorite, Delete.
  - Beklenen: Toplu işlemler çalışır; widget'lar silinen eseri göstermez.

### 6.10 Paylaşma

- [ ] **Paylaşım ekranı**
  - Yap: Bir Magic Edit sonucunda kâğıt uçak simgesine dokun.
  - Beklenen: **Share your glow** (*Işıltını paylaş*) ekranında biçimler: **Photo**, **Before / After** (*Öncesi / Sonrası*), **Story card** (*Hikâye kartı*), **Cover star** (*Kapak yıldızı*), **Photo strip** (*Fotoğraf şeridi*, birden çok görselde) ve **Which vibe?** (*Hangi vibe?*, Create'teki iki varyasyonda). Hedefler: **Stories** (*Hikâye*), **Save**, **Copy image** (*Görseli kopyala*), **More apps** (*Diğer uygulamalar*). **Caption** ile **Copy**, ve görünüşe değil havaya dair **Caption ideas** (*Açıklama fikirleri*) var. Yapay zekâ içeriğinde **Add a visible “AI-edited” label** anahtarı ve platformun AI etiketini açma notu bulunur. Ücretsiz kullanıcıda "Free exports carry a small Aybuke mark." ve **Remove it with Pro** (*Pro ile kaldır*) görünür.
- [ ] **Stories**
  - Yap: **Stories**.
  - Beklenen: "Tap Instagram, then Stories ✨" (*Önce Instagram'a, sonra Hikâyeler'e dokun ✨*) ve sistem paylaşım sayfası açılır (Meta App ID tanımlı değil). Açıklama panoya kopyalanır.
- [ ] **Kopyala ve kaydet**
  - Yap: **Copy image** → Notlar'a yapıştır; sonra **Save**.
  - Beklenen: "Image copied" ve "Saved to Photos". Yapay zekâ görselleri "made with AI" meta verisiyle kopyalanır ve kaydedilir.
- [ ] **Diğer yüzleri gizle**
  - Yap: My Works'ten birden çok kişili bir fotoğrafı paylaş → **Hide other faces** (*Diğer yüzleri gizle*).
  - Beklenen: En büyük yüz dışındakiler cihazda bulanıklaşır.
- [ ] **Fotoğraflar izni reddedilince**
  - Yap: Settings › Aybuke › Photos: **None** → bir şey kaydetmeyi dene.
  - Beklenen: "Photos access is off" (*Fotoğraflar erişimi kapalı*) uyarısında **Open Settings**, **Share instead** (*Bunun yerine paylaş*) ve **Cancel** var.

---

## 7. Widget, Live Activity, Control Center, Siri, bildirimler

- [ ] **7.1 Widget'lar**
  - Yap: Ana Ekran'a **My glow** (*Işıltım*, küçük ve orta) ve **Today's trend** (*Günün trendi*, küçük ve orta) ekle. Kilitli Ekran'a My glow (yuvarlak) ve Today's trend (dikdörtgen ve satır içi) ekle.
  - Beklenen: My glow kredi sayısını (Pro'da taç), son eseri ("Your latest" ya da "Make your first glow ✨") ve orta boyda Magic, Cut out, Effects, Video kısayollarını gösterir; her kısayol doğru araca açılır. Magic Edit ve Create sonuçlarında başlık olarak istemin değil "Your latest creation" yazar. Today's trend her gün bir ücretsiz görünüm gösterir ve dokununca o şablonla fotoğraf seçimi açılır.
- [ ] **7.2 Live Activity**
  - Yap: Bir Magic Edit başlat ve hemen Ana Ekran'a çık.
  - Beklenen: Dynamic Island'da ve Kilitli Ekran'da "Creating your glow…" ilerlemesi görünür; başlıkta istem değil araç ya da şablon adı ("Magic Edit") yazar. Bitince "Your glow-up is ready" / "Tap to see it ✨" ve dokununca uygulama açılır. Hata olursa "That one didn't work" / "No credit was used. Tap to try again."
  - **Koddan risk:** Bu metinler Türkçe cihazda da İngilizce kalır (§12-2). Türkçe arayüzde ne gördüğünü not et.
- [ ] **7.3 Control Center denetimleri** (iOS 18+)
  - Yap: Denetim Merkezi'ni düzenle › denetim ekle › "Aybuke": **Magic Edit** (*Sihirli Düzenleme*), **Retro effects** (*Retro efektler*), **Edit a video** (*Video düzenle*), **Retro Cam**, **Retro Booth**.
  - Beklenen: Her biri doğru ekrana açılır; Retro Booth, Retro Cam'i Booth modunda açar. Editör, video düzenleyici, Retro Cam ya da kolaj açıkken gelen bağlantı hiçbir şeyi değiştirmez (kaydedilmemiş iş korunur).
- [ ] **7.4 Siri, Kestirmeler, Spotlight, Eylem düğmesi**
  - Yap: Kestirmeler'de yeni kestirme → "Aybuke" eylemleri: **Apply a Retro Effect** (*Retro Efekt Uygula*), **Open Retro Cam** (*Retro Cam'i Aç*), **Start Retro Booth** (*Retro Booth'u Başlat*), **Make a Collage** (*Kolaj Yap*), **Edit a Photo** (*Fotoğraf Düzenle*). Örnek akış: Fotoğrafları Seç → Apply a Retro Effect (VHS '86) → Fotoğraf Albümüne Kaydet.
  - Beklenen: Apply a Retro Effect uygulamayı açmadan, arka planda düzenlenmiş görüntü dosyasını döndürür (fotoğraf yüklenmez). Türkçe Siri ifadeleri çalışır: "Aybuke uygulamasında Retro Cam'i aç", "Aybuke ile fotoğraf kabini başlat", "Aybuke ile kolaj yap", "Aybuke ile fotoğraf düzenle". Spotlight'ta "Retro Cam" araması kısayolu gösterir; kısayol Eylem düğmesine atanabilir (iPhone 15 Pro ve sonrası).
- [ ] **7.5 Bildirimler ve sessiz saatler**
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

- [ ] **8.1 16–17 (Türkiye mağazası)**
  - Yap: Bandı 16–17 yap.
  - Beklenen: Settings'te **Age range** "16 to 17" (*16–17 yaş*). Kodda Türkiye için dijital onay yaşı 18 tanımlı; bu yüzden Türkiye mağazasında sonraki bulut işinde onay ekranı **ebeveyn adımıyla** gelir. ABD mağazasında 16–17 için ebeveyn adımı çıkmaz.
- [ ] **8.2 13–15 (ebeveyn adımı)**
  - Yap: Bandı 13–15 yap → bir Magic Edit dene.
  - Beklenen: Onay ekranında **Ask a parent or guardian to read this with you** (*Bunu annen, baban ya da velinle birlikte oku*) ve **A parent or guardian said yes** (*Annem, babam ya da velim onay verdi*) anahtarı var; anahtar kapalıyken **Allow AI processing** pasiftir. Yetişkinken verilen onay artık geçersizdir. Paywall kendiliğinden açılmaz; satın alma yalnızca dokununca mümkündür.
- [ ] **8.3 13 yaş altı (yalnızca cihaz üstü araçlar)**
  - Yap: Bandı 13 yaş altı yap.
  - Beklenen: Create sekmesi kaybolur. Explore'da Magic Edit kartı, kredi hapı, şablon satırları ve "Create from text" yoktur. Edit'in araç ızgarasında yalnızca Effects, Text & Stickers, Remove BG, Adjust, Crop ve Hide faces kalır (Retro Cam, Best shot, kolaj ve video kartları durur). Settings'te Membership, Account, Credits, Notifications ve Cloud AI processing yoktur; Privacy notu "Every tool runs on your device. Your photos are never uploaded." olur. Widget'larda yalnızca ücretsiz araçlar görünür ve Magic Edit denetimi **Cut out** olur. Siri'deki "Edit a Photo" ücretsiz araçları açar. Onay ekranı ve paywall hiç çıkmaz.
- [ ] **8.4 Kendi beyanınla yükseltme engeli**
  - Yap: Menülerle yetişkin bir tarih gir (ör. Ocak 2000).
  - Beklenen: Reddedilir: "That's older than the age range you entered before. You can change it once a year." (*Bu, daha önce girdiğin yaş aralığından daha büyük. Bunu yılda bir kez değiştirebilirsin.*). Sayfada "You can enter a younger age anytime. An older one can be entered once a year." yazar. Apple'ın yanıtı ise her zaman kabul edilir (tasarım gereği). Kendi beyanınla geri dönmenin yolu §9'daki silmedir.
- [ ] **8.5 Onboarding'de genç yolu** (isteğe bağlı, §9'dan sonra)
  - Yap: Silmeden sonra onboarding'de 13–15 seç → **Skip for now**.
  - Beklenen: Paywall açılmaz, doğrudan tur başlar.

---

## 9. Verilerimi ve hesabımı sil (en son yap)

- [ ] **9.1 Silmeden önce not al**
  - Supabase › Users'taki kullanıcı kimliğini, `credit_wallets` satırını ve RevenueCat'te bu kimliğin büyük harfli müşteri kaydını not et. (Yalnızca eski bir sürümde Apple ile giriş yaptıysan: iPhone'da Settings › [adın] › Sign-In & Security › **Sign in with Apple** listesinde Aybuke'yi gör.)
- [ ] **9.2 Silme**
  - Yap: Settings › Privacy › **Delete my data & account** (*Verilerimi ve hesabımı sil*) → "Delete my data?" (*Verilerim silinsin mi?*) → **Delete my data** (*Verilerimi sil*).
  - Beklenen: Onay metni "Deletes your creations and your account with its credits from our servers, and resets every setting on this device. Subscriptions are managed by Apple and must be cancelled separately." İlerleme göstergesinden sonra "Your data has been deleted." (*Verilerin silindi.*) ve uygulama onboarding'in başına döner.
- [ ] **9.3 Cihazda silinmesi gerekenler**
  - Beklenen: My Works boş (Recently deleted dahil). Onay, yaş bandı, ilgi alanları, görünüm (Light'a döner), son istemler, bildirim tercihleri ve bekleyen bildirimler silinmiş (yalnızca Pro deneme hatırlatması kalır); Bildirim Merkezi'ndeki Aybuke bildirimleri de silinmiş. Live Activity kapanmış. Widget'lar "Make your first glow ✨" ve (Pro değilsen) 2 kredi gösterir. Settings'te Apple ile giriş yok; ipuçları ve tur sıfırlanmış.
- [ ] **9.4 Sunucuda silinmesi gerekenler**
  - Beklenen: Supabase › Users'ta kullanıcı yok. `credit_wallets`, `credit_ledger`, `jobs`, `entitlements`, `reports`, `apple_accounts` ve `merged_users` satırları silinmiş (cascade).
- [ ] **9.5 RevenueCat**
  - Beklenen, `REVENUECAT_SECRET_KEY` varken: müşteri RevenueCat'ten silinir (RevenueCat kuyruğa alır, birkaç dakika sürebilir) ve `pending_revenuecat_deletions` tablosunda bu kimlik için satır kalmaz.
  - Beklenen, anahtar yokken: silme yine tamamlanır; kimlik `pending_revenuecat_deletions` tablosunda bekler ve `account` log'unda "REVENUECAT_SECRET_KEY is not set: RevenueCat deletions wait in pending_revenuecat_deletions" görünür. Anahtar eklenince bir sonraki hesap silmede ya da saatlik `revenuecat-deletions` çağrısında satır silinir (§12-4).
- [ ] **9.6 Apple ile Giriş token'ı** (yalnızca Apple ile giriş yapılmış bir hesapta; bu sürümde giriş gizli)
  - Beklenen: Aybuke, Sign in with Apple listesinden kalkar (Guideline 5.1.1(v)).
  - Sorun olursa: `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` yoksa kalkmaz; `account` log'unda "Sign in with Apple token NOT revoked" ya da "…deleted without a stored token to revoke" hatası görünür (§12-3). Silmenin kendisi yine tamamlanır.
- [ ] **9.7 Silinmemesi gerekenler**
  - Beklenen: Apple aboneliği sürer; iptali Settings › Apple Account › Subscriptions'tan yapılır. Pro aktifse uygulamada yeniden görünür ve onboarding sonunda paywall çıkmaz. Fotoğraflar'a kaydettiklerin ve uygulamanın dil seçimi durur.
- [ ] **9.8 Çevrimdışı silme**
  - Yap: Uçak Modu'nda silmeyi dene.
  - Beklenen: "Check your internet connection and try again." (*İnternet bağlantını kontrol et ve tekrar dene.*) yazar ve **hiçbir şey silinmez**.
- [ ] **9.9 Diğer cihazlar**
  - Not al: Aynı hesapla girişli ikinci cihazda (Mac ya da iPad) Settings › Account'un ne gösterdiğini ve bir yapay zekâ işi denediğinde ne olduğunu yaz.

---

## 10. Mac (Mac Catalyst)

- [ ] **10.1 Kurulum**
  - Yap: Mac'te TestFlight uygulamasını aç (Mac App Store'dan) → Aybuke macOS derlemesi → **Install**.
  - Beklenen: Tek pencere açılır, en küçük boyutu yaklaşık 900×640'tır; sekmeler başlık çubuğundadır. Settings › Version macOS derleme numarasını gösterir.
- [ ] **10.2 Menü çubuğu**
  - Yap: **Aybuke › Settings…** (⌘,) (*Ayarlar…*), **File › New Creation** (⌘N) (*Yeni Eser*), **File › Open Photo…** (⌘O) (*Fotoğraf Aç…*), **View** menüsünde Explore ⌘1, Create ⌘2, Edit ⌘3, My Works ⌘4, **Help › Contact support** (*Destekle iletişime geç*).
  - Beklenen: New Creation Create sekmesini açar. Open Photo… fotoğraf seçiciyi, ardından Magic Edit'i açar. Contact support, hello@buaze.com adresine yeni e-posta açar. Onboarding, tur, bir sayfa ya da editör açıkken komutlar bilerek çalışmaz. File › New Window yoktur.
- [ ] **10.3 Sürükle bırak**
  - Yap: Finder'dan bir JPEG, HEIC ya da RAW dosyasını pencereye sürükle.
  - Beklenen: "Drop a photo to edit it" (*Düzenlemek için bir fotoğraf bırak*) kaplaması görünür, sonra editör Magic Edit'te açılır (RAW'da "RAW photo developed with the best settings ✨"). Kolaj karşılama ekranında "Or drop photo files here" yazar.
- [ ] **10.4 Editör kısayolları**
  - Beklenen: Esc editörü kapatır (kaydedilmemiş iş varsa "Discard your edits?" sorar), ⌘S kaydeder, ⌘Return uygular.
- [ ] **10.5 Retro Cam (Mac kamerası)**
  - Yap: Explore › Retro Cam → **Turn on the camera** → macOS izin penceresi.
  - Beklenen: İzin verilirse canlı önizleme gelir; **Space** fotoğraf çeker ya da booth'u başlatır, Esc kapatır. Reddedilirse "Allow camera access for Aybuke in System Settings › Privacy & Security › Camera." (*Sistem Ayarları › Gizlilik ve Güvenlik › Kamera bölümünden Aybuke'nin kameraya erişmesine izin ver.*) ve **Open System Settings** görünür; izni açıp uygulamayı yeniden açınca çalışır. Kamerası olmayan bir Mac'te Retro Cam kutuları hiç görünmez.
- [ ] **10.6 Uyku ve uyanma sonrası My Works**
  - Yap: My Works'te 5'ten fazla eser varken Mac'i kilitle ya da uyut, sonra uyandır, kilidi aç ve Aybuke'ye dön; yeni bir eser kaydet.
  - Beklenen: Küçük resimler boş kalmaz (gerekirse uygulama öne gelince yeniden yüklenir) ve yeni kayıt çalışır.
  - Sorun olursa: Boş kalan kareleri ekran görüntüsüyle not et (NEXT-STEPS §6'daki eski sorun).
- [ ] **10.7 Satın alma ve hesap (evrensel satın alma)**
  - Beklenen: iPhone'daki Pro, aynı Apple Hesabıyla Mac'te de görünür (gerekirse Settings › Restore purchases). Sign in with Apple ile kredi bakiyesi iPhone'dakiyle aynıdır (§5.2).
- [ ] **10.8 Mac'te olmayanlar**
  - Beklenen: Live Activity yoktur; "When my glow is ready" açıksa ve Aybuke arka plandaysa bildirim gelir (sessiz saatler dışında). Paylaşma ekranında **Stories** yerine **Share** açılır menüsü vardır. Dil seçimi: System Settings › General › Language & Region › Applications.

---

## 11. App Store Connect: gönderim öncesi kontroller (sahip)

Değerlerin hepsi: [`marketing/app-store-connect-setup.md`](marketing/app-store-connect-setup.md). App Review metni: [`marketing/app-store-listing.md`](marketing/app-store-listing.md).

- [ ] **Derlemeler sürümlere bağlı**
  - Yap: iOS 1.0 › Build ve macOS 1.0 › Build bölümünde bu testte kullandığın derlemeleri seç.
  - Beklenen: İkisi de seçili ve "Missing Compliance" uyarısı yok.
  - Dikkat: Projede `MARKETING_VERSION = 1.0.0`, App Store Connect'teki sürüm ise "1.0". Derleme listede görünmüyorsa App Store Connect'te sürüm numarasını 1.0.0 yap (gönderimden önce düzenlenebilir) ve not al (§12-6).
- [ ] **Ekran görüntüleri**
  - Beklenen: 12 dilin her biri için iPhone 6.9" (1290×2796) 10, iPad 13" (2064×2752) 10 ve Mac (2880×1800) 8 görüntü; dosyalar `docs/marketing/app-store/<dil>/` altında (iPad `ipad/`, Mac `mac/` alt klasöründe; es-MX İspanyolca `es/` görüntülerini kullanır). Boş ya da yanlış dosya olmamalı.
- [ ] **Abonelikler ve paketler sürüme ekli**
  - Yap: iOS 1.0 sayfası › In-App Purchases and Subscriptions › Pro Yearly, Pro Monthly, 30 Credits ve 100 Credits'i ekle. İlk abonelik uygulama sürümüyle birlikte incelemeye gönderilmek zorundadır. macOS sayfasında da bu bölüm varsa aynılarını seç.
  - Beklenen: Her birinde inceleme ekran görüntüsü ve not var, durumları "Ready to Submit"; abonelik grubunun en-US ve tr adları dolu.
- [ ] **Paid Apps Agreement Active** (yalnızca sahip; banka ve vergi bilgisi tamam)
- [ ] **App Privacy yayında**
  - Beklenen: 10 veri türü: Photos or Videos, Other User Content, User ID, Purchase History, Email Address (kullanıcıyla ilişkili); reklamlar nedeniyle Coarse Location, Device ID, Product Interaction, Performance Data (Third-Party Advertising ve Analytics, kullanıcıyla ilişkisiz) ve Advertising Data (App Functionality, Third-Party Advertising ve Analytics; ödüllü reklam kayıtlarımız nedeniyle kullanıcıyla ilişkili). User ID ve Purchase History'de RevenueCat nedeniyle Analytics amacı da işaretli; izleme (tracking) yok. Ayrıntı: kurulum dokümanı §5.
- [ ] **Yaş derecelendirmesi**
  - Beklenen: Kurulum dokümanı §2'deki gibi dürüst cevaplar ve 13+ ("Override to Higher Age Rating"); Capabilities altında **Advertising** işaretli. Kids kategorisi seçili değil. "Age Assurance" kutusunu dokümandaki nota göre karara bağla.
- [ ] **App Review Information**
  - Beklenen: Ad, soyad, **telefon** (+90…, sahip doğrular) ve e-posta `hello@buaze.com`. "Sign-in required" işaretsiz. Notlar `app-store-listing.md`'deki "App Review notes" metni; `{{SUPPORT_EMAIL}}` yer tutucusu kalmamış. macOS notuna şu cümle eklenmiş: "On the Mac, Instagram Stories sharing and the Live Activity aren't offered; everything else matches the iOS app."
- [ ] **Export compliance**
  - Beklenen: Info.plist'te `ITSAppUsesNonExemptEncryption = NO` olduğu için soru gelmez. Gelirse yalnızca HTTPS (standart, muaf şifreleme) kullanıldığını yanıtla.
- [ ] **Fiyat ve bulunabilirlik**
  - Beklenen: Free; **China mainland hariç** tüm ülkeler (174).
- [ ] **Sürüm sayfası**
  - Beklenen: Açıklamanın sonunda Terms ve Privacy bağlantıları; anahtar kelimeler ve promosyon metni dolu. Support URL, Marketing URL ve Privacy Policy URL açılıyor (GitHub Pages). macOS açıklamasında Lock Screen ve Dynamic Island satırları yok, iPhone/iPad yerine Mac yazıyor. Release seçeneği "Manually release this version".
- [ ] **Sunucu ön koşulları (§1.1):** Apple Sign-in anahtarları, RevenueCat anahtarları, `FAL_KEY` kararı ve xAI Zero Data Retention tamam.

---

## 12. Koddan görülen riskler (testte özellikle bak)

Bu sürümde düzeltilenler (yayından önce migration'lar `20261017000000_unclaimed_results` ve `20261018000000_revenuecat_deletion_queue` uygulanmalı, sonra `ai-image` ve `account` yeniden yayımlanmalı):

1. **İşten sonra bakiye — düzeltildi.** 202 yanıtındaki bakiye hemen gösterilir; biten (başarılı, başarısız, iptal) işlerin yanıtı da bakiyeyi taşır. Kontrol: §3.4, §3.6.
2. **Live Activity metinleri — düzeltildi.** Başlık ve alt satır widget kataloğundan 12 dilde gelir. Kontrol: Türkçe cihazda Dynamic Island (§7.2).
3. **Sign in with Apple token iptali — anahtarlar hâlâ yok.** `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` (`backend/supabase/functions/_shared/apple-signin.ts` › `appleConfig()`) eklenmedi; bu yüzden giriş bu sürümde gizli (`signInWithApple: false`, §5). Eksik anahtar artık log'a hata olarak düşer ve silmeyi bozmaz.
4. **RevenueCat silme — kuyrukta bekliyor.** `REVENUECAT_SECRET_KEY` (ve v2 anahtar için `REVENUECAT_PROJECT_ID`; `_shared/revenuecat.ts` › `revenueCatKey()`) yokken silmeler `pending_revenuecat_deletions` tablosunda bekler; anahtar eklenince hesap silmede ve saatlik `POST /account/revenuecat-deletions` çağrısında gönderilir (zamanlama: `backend/README.md` 6. adım). Kontrol: §9.5.
5. **Çıktı denetimi — artık hata durumunda kapalı (fail-closed).** Her sonuç tek bir denetimden geçer: `FAL_KEY` yokken xAI'nin kendi denetim kararı (filtrelenen ya da eksik görsel tüm işi engeller), `FAL_KEY` varsa fal.ai sınıflandırıcısı. Denetim çalışamazsa sonuç gösterilmez ve kredi iade edilir ("Our safety check couldn't run…"). Onay ekranı artık fal.ai'yi listelemez; `FAL_KEY` eklenecekse önce fal.ai'yi listeye geri ekleyen bir sürüm gerekir.
6. **Sürüm numarası uyuşmayabilir.** `ios/Glowlit.xcodeproj/project.pbxproj:428` ve `:468`'de `MARKETING_VERSION = 1.0.0` var, App Store Connect'teki sürüm "1.0".
7. **Yeniden kurulum temiz değil.** Oturum Keychain'de `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` ile saklanıyor (`ios/App/Services/Auth/Keychain.swift:22`) ve açılışta okunuyor (`ios/App/Services/Auth/AuthSessionManager.swift:21`). Uygulamayı silip kurmak eski anonim hesabı ve bakiyeyi geri getirir.
8. **Bağlantı kopunca iade — düzeltildi.** Uygulama kopmalarda geri çekilerek sormaya devam eder ve ancak 2 dakika yanıt alamazsa vazgeçer; sunucu uygulamaya hiç ulaşmayan sonuçları bir saat dolunca iade eder (`undelivered`), ulaşıp onaylanmayanları günde en fazla bir kez (`unconfirmed`). Kontrol: §3.6.
9. **"Pro on all your devices" metni — düzeltildi.** Hesap metinleri artık Pro'nun Apple Hesabından geldiğini söylüyor (giriş bu sürümde zaten gizli). Pro yine yalnızca StoreKit'ten okunuyor.
10. **Onay verilmeden bakiye — düzeltildi.** Oturum varsa bakiye açılışta, öne gelişte ve satın almadan sonra onaydan bağımsız okunur; yalnızca okumak için hesap oluşturulmaz. Kontrol: onay vermeden kredi paketi al, uygulamayı kapatıp aç, bakiye paketi göstermeli.

---

## 13. Sorun bildirme şablonu

```text
Madde: §3.4 Magic Edit uçtan uca
Cihaz / sistem / dil: iPhone …, iOS 26.x, Türkçe   (Mac: macOS …)
Derleme: Settings › Version = 1.0.0 (…)
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

- [ ] §1.1 ve §11'deki maddelerin hepsi işaretli, §12'deki riskler için karar verilmiş (düzelt ya da bilerek kabul et).
- [ ] Engelleyici olarak işaretlenen tüm sorunlar kapandı ya da sahip bunları açıkça kabul etti.
- [ ] Sahip "Her şey hazır. Gönderelim mi?" sorusuna açıkça **evet** dedi. Onay gelmeden **Add for Review** ve **Submit for Review** yapılmaz.

Kaynaklar (Apple): [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox), [Subscription renewal rate in TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/subscription-renewal-rate-in-testflight), [Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings), [Testing age assurance in sandbox](https://developer.apple.com/documentation/storekit/testing-age-assurance-in-sandbox). Proje içi: [`NEXT-STEPS.md`](NEXT-STEPS.md), [`05-compliance.md`](05-compliance.md), [`SUPABASE-TODO.md`](SUPABASE-TODO.md), [`../backend/README.md`](../backend/README.md).
