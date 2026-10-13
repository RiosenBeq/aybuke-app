# Glowlit — Yönetici Özeti (Türkçe)

> Bu belge, araştırmayla alınan tüm kararların Türkçe özetidir. Ayrıntılar ve kaynaklar İngilizce belgelerdedir ([docs/README.md](README.md)).

## Ekim 2026 güncellemesi: kızlara özel pembe Glowlit

**Ne değişti?**
- **Hedef kitle:** Glowlit artık kızlar ve genç kadınlar için tasarlandı ("made for girls who glow").
- **Renkler:** Talep üzerine tamamen pembe, açık tonlu "Blush" paleti kullanılıyor: blush `#F7C1D9`, petal `#F8E0EA`, ink `#121212`, antrasit `#24272A`, kırık beyaz `#F8F8F6` ve beyaz. Ana butonlar siyah üzerine pembe yazı. Ayarlar'dan Açık (varsayılan), Koyu veya Otomatik görünüm seçilebiliyor.
- **Tasarım detayları:** Başlıklarda zarif italik serif vurgular ("Watch it *glow.*"), kalp ve parıltı motifleri, başarı anında parıltı animasyonu, gölgeli beyaz kartlar. Pembe uygulama ikonunun koyu ve renklendirilmiş varyantları da var.
- **Yeni şablonlar:** 30 görünüm. Örneğin Doll Box, Pembe Saç, Soft Glam, Bouncy Curls, Clean Girl, Ballet Core, Kiraz Çiçeği, Kafe Buluşması, Paris Gezisi, Peri Prensesi, Doğum Günü Glam ve Witchy Glam. 14 stil var (Pastel Dream ve Kawaii eklendi).
  - Tüm şablonlar yüzü, ten rengini ve **vücut şeklini** korur.
  - Vücut inceltme veya cilt açma gibi özellikler bilinçli olarak yok.
- **Paylaşım (tanıtım için):** Yeni Paylaş ekranından Instagram Hikâyeler, Önce/Sonra kolajı, 9:16 hikâye kartı, görsel kopyalama, hazır açıklama ve hashtag'ler kullanılabiliyor. Ücretsiz paylaşımlarda küçük "Made with Glowlit" işareti var (Pro'da yok). Her dosyada görünmez "yapay zekâ ile yapıldı" etiketi korunuyor.
- **Diğer yeni özellikler:** Galeride kalpli favoriler. "Bu görseli bildir" artık gerçekten backend'e gidiyor (`report` fonksiyonu ve `reports` tablosu).
- **Yasal metinler:** Kullanım Koşulları, Gizlilik Politikası, Kabul Edilebilir Kullanım Politikası (İngilizce ve Türkçe) ve KVKK Aydınlatma Metni hazırlandı. GDPR, KVKK (7499 sayılı Kanun değişiklikleri dahil), CCPA, COPPA, Birleşik Krallık Yaşa Uygun Tasarım Kuralları, AB Yapay Zekâ Tüzüğü md. 50 ve Apple'ın EULA şartları kapsanıyor.
  - Metinler uygulamanın içinde okunabiliyor ve ayrıca `docs/legal/` ile `web/legal/` altında yayınlanıyor.
  - **Bunlar avukat incelemesi gereken taslaklardır.** Şirket bilgilerini `legal/config.json` dosyasına girin ve `legal/README.md` kontrol listesini uygulayın.
- **AI API anahtarı yeri:**
  - **Denemek için:** `ios/Config/Secrets.xcconfig` dosyasına `GL_AI_PROVIDER` (fal, openai veya gemini) ve `GL_AI_API_KEY` yazılır. Bu dosya git'e girmez ve yalnızca geliştirme derlemelerinde okunur.
  - **Canlı sürüm için:** Anahtar backend'de `FAL_KEY` olarak saklanır.
- **Tanıtım kiti (`docs/marketing/`):** App Store metinleri (İngilizce ve Türkçe, karakter sayılı), sosyal medya kiti (biyografiler, hashtag'ler, 20 gönderi, 10 video senaryosu, influencer şablonları), 30 günlük lansman planı, 8'er App Store ekran görüntüsü ve sosyal medya görselleri.
- **Web sitesi (`web/`):** Tanıtım sayfası ve yasal sayfalar hazır. GitHub Pages ile yayınlanabilir (`.github/workflows/website.yml`).

**Sizin yapmanız gerekenler:** Yasal metinleri avukata inceletin ve şirket bilgilerini girin. AI API anahtarını iletin. Instagram Hikâyeler'e doğrudan paylaşım için bir Meta App ID alın. `glowlit.app` alan adını ve marka tescilini kontrol edin.

![Glowlit marka panosu](assets/brand/brand-board.png)

## Ne yaptık?

Brief şuydu: AI ile fotoğraf düzenleme ve AI ile görsel oluşturma uygulaması yapılacak. Uygulama İngilizce olacak; piyasa, kullanıcı tercihleri, renk, yazı tipi ve isim araştırılacak; iş aşama aşama ilerleyecek; Swift kullanılacak.

Bu brief'i üç paralel araştırmayla (pazar, marka/tasarım, teknoloji/uyumluluk) somut bir ürüne dönüştürdük ve hepsini koda döktük:

1. **Araştırma:**
   - 15 rakip uygulama incelendi.
   - Kullanıcıların sevdiği ve nefret ettiği noktalar çıkarıldı.
   - 2025–2026 viral trendleri ve fiyatlandırma kıyasları (RevenueCat, Adapty) derlendi.
   - Renk haritası, yazı tipi ve isim çalışması yapıldı.
   - AI modelleri, maliyetler, App Store kuralları ve AB Yapay Zeka Yasası incelendi.
2. **Marka:** isim **Glowlit**, slogan *"Make it glow."*, pembe "Blush" paleti (Ekim 2026'dan beri; başlangıçta "Golden Hour" amberdi), Bricolage Grotesque + New York Italic yazı tipleri, pembe "Sunrise Split" ikonu.
3. **iOS uygulaması (SwiftUI):**
   - Ekranlar: onboarding, AI onayı, keşfet, metinden görsel oluşturma, editör (Magic Edit, stiller, iyileştirme, arka plan silme, nesne silme, ayarlar), kütüphane, paywall, ayarlar.
   - Backend olmadan da tamamen çalışan **demo modu** var.
4. **Backend (Supabase + fal.ai):**
   - Kimlik doğrulama, kredi defteri, Apple satın alma doğrulaması, güvenlik filtreleri ve asenkron AI iş kuyruğu.
5. **Testler ve CI:**
   - 65 Swift birim testi.
   - Deno tip kontrolü ve lint.
   - Gerçek PostgreSQL üzerinde kredi defteri testleri.
   - macOS'ta Xcode derlemesi ve simülatör ekran görüntüleri.

## Uygulamadan görüntüler

![Glowlit uygulama ekranları](assets/screenshots/overview.jpg)

Görüntüler, CI'daki Screenshots iş akışında iPhone Pro simülatöründe demo modunda alındı. Ekranların tek tek hâlleri `assets/screenshots/` klasöründe; en güncel tam çözünürlüklü set ise `screenshots` dalında.

## Temel kararlar ve nedenleri

### İsim: Glowlit
- **Anlamı:** "Glow" kategorinin en duygusal sonuç kelimesi (glow-up, ışıl ışıl cilt, altın saat ışığı); "lit" ise ışıkla aydınlanmış demek, Z kuşağı argosunda da "harika" anlamına geliyor.
- **Neden diğer adaylar değil:** Araştırmadan çıkan Sunlit, Lumora, Pixora, Aglow gibi adayların `.app` ve `.ai` alan adları dolu, yani aktif kullanımdalar. **glowlit.app ve glowlit.ai ise boş.** Türetilmiş bir isim olduğu için marka tescili açısından da sözlük kelimelerinden daha güçlü.
- **Okunuş ve diller:** Duyulduğu gibi yazılıyor. İngilizce, İspanyolca, Portekizce, Fransızca, Almanca ve Türkçede olumsuz bir anlamı yok.
- **Mağaza başlığı:** `Glowlit: AI Photo Editor`.
- ⚠️ Lansmandan önce App Store, USPTO ve EUIPO marka taraması yapılmalı ve `glowlit.app` alınmalı.

### Renk: "Blush" (pembe, açık tema)
- **Ekim 2026'dan itibaren:** Talep üzerine uygulama tamamen pembe tonlarda. Arka plan petal `#F8E0EA`, kartlar beyaz, vurgu blush `#F7C1D9`, yazılar ink `#121212`.
- **Kontrast:** Pembe zeminde siyah yazı 15:1, siyah buton üzerinde pembe yazı 12:1. Pembe üzerine beyaz yazı **kullanılmaz** (1.6:1).
- **Kural:** Her ekranda tek bir ana aksiyon vardır: siyah, hap biçimli buton ve pembe yazı. Seçili öğeler pembe, fotoğrafların üzerine renk filtresi konmaz.
- **Önceki tercih:** Araştırmadaki "Golden Hour" amber ve koyu tema emekliye ayrıldı; gerekçeleri İngilizce belgede kayıtlı.

### Yazı tipi: Bricolage Grotesque + SF Pro
- **Seçim:** Başlıklarda karakterli, sıcak bir grotesk; gövde metinlerinde Apple'ın SF Pro'su (Dynamic Type desteği için).
- **Lisans ve kesimler:** Lisansı SIL OFL, yani ücretsiz ve uygulamaya gömülebilir. Değişken fonttan üç statik kesim üretildi.
- **Elenenler:** Space Grotesk ve Sora sıradan "AI/web3" görünümü veriyor (Sora ayrıca OpenAI ile karışıyor); Unbounded kripto çağrışımı taşıyor.

### İkon: "Sunrise Split"
Pembe zemin üzerinde yarısı siyah (öncesi), yarısı beyaz (sonrası) bir disk, ortada karşılaştırma tutamacı ve iki parıltı. Hem ışığı, hem önce/sonra dönüşümünü, hem de uygulamanın imza etkileşimini anlatıyor. 29 piksele küçültüldüğünde de okunuyor.

### Fiyatlandırma: "Adil Fiyat Sözü"
Araştırmanın en net bulgusu: kullanıcıların **1 numaralı şikâyeti haftalık deneme tuzakları ve sürpriz ücretler**. Yıllık plan ise kurulum başına yaklaşık **5 kat** daha fazla gelir getiriyor; haftalık abonelerin bir yıl sonra yalnızca %1–2'si kalıyor.

| Plan | Fiyat | İçerik |
|---|---|---|
| Ücretsiz | 0 | Günde 3 kredi, cihaz içi araçlar (arka plan silme, ayarlar) sınırsız |
| **Pro Yıllık** (varsayılan) | **$59.99/yıl**, 7 gün ücretsiz deneme | Ayda 100 kredi (kullanılmayan 1 ay devreder), tüm şablonlar, HD, filigransız |
| Pro Aylık | $9.99/ay | Aynı içerik |
| Kredi paketleri | 30 kredi $4.99 · 100 kredi $12.99 | **Süresiz** geçerli |

Güven özellikleri:
- **Haftalık plan yok.**
- Paywall'da deneme takvimi gösteriliyor ve deneme bitmeden 24 saat önce hatırlatma bildirimi geliyor.
- Başarısız işlerin kredisi **otomatik iade ediliyor**.
- Sahte geri sayım kullanılmıyor.

### Farklılaştırıcılar
1. **Likeness Lock:** İnsan içeren her şablonda yüz ve kimlik korunuyor. Sonuç kullanıcıya benzemezse "Bana benzemiyor mu? Ücretsiz tekrar dene" seçeneği var (en duygusal kalite şikâyetine çözüm).
2. **48 saatlik trend motoru:** Şablon tarifleri sunucuda duruyor. Yeni bir trend (figürin, aksiyon figürü, karikatür vb.) uygulama güncellemesi gerektirmeden 24–48 saatte yayına alınabiliyor.
3. **Varsayılan olarak gizli:**
   - Bulut işlemesinden önce açık onay alınıyor (Apple 5.1.2(i)).
   - Arka plan silme ve ayarlar cihaz içinde yapılıyor.
   - Yüklenen fotoğraflar saklanmıyor; çıktılar 1 saatte siliniyor.
   - Dışa aktarılan her görsele AB Yapay Zeka Yasası için "AI ile üretildi" meta verisi (IPTC) ekleniyor.

## Mimari (kısaca)

- **iOS:**
  - SwiftUI, iOS 17+, @Observable, SwiftData, StoreKit 2.
  - Arka plan silme Vision ile, ayarlar Core Image ile yapılıyor.
  - İş mantığı Linux'ta da test edilebilen ayrı bir pakette (`AppCore`).
- **Backend:**
  - Supabase: anonim oturum, Postgres kredi defteri (RLS), Edge Functions.
  - fal.ai modelleri:
    - Metinden görsel ve düzenleme: Nano Banana 2
    - İyileştirme: SeedVR2
    - Nesne silme: object-removal
  - Uygulama yalnızca "işlem" adını gönderiyor; modeli sunucu seçiyor. Böylece model değiştirmek için uygulama güncellemesi gerekmiyor ve API anahtarı uygulamada hiç bulunmuyor.
- **Maliyet:**
  - Bulut işlemi başına ortalama yaklaşık $0.06.
  - Kredi kuralları SQL'de tanımlı, uygulama güncellemesi olmadan değiştirilebiliyor.

## Nasıl çalıştırılır?

1. Mac'te **Xcode 16 veya üzeri** ile `ios/Glowlit.xcodeproj` dosyasını açın ve bir iPhone simülatörü seçip ▶︎ ile çalıştırın.
2. Backend tanımlı değilse uygulama **demo modunda** açılır. AI sonuçları cihazda simüle edilir ve "DEMO PREVIEW" etiketi taşır.
3. Gerçek AI için `backend/README.md` adımlarını izleyin:
   - Supabase projesi oluşturun ve `FAL_KEY` gizli anahtarını tanımlayın.
   - Fonksiyonları deploy edin.
   - `AppConfig.json` dosyasına Supabase adresini ve anahtarını yazın.

## Sırada ne var? (bkz. [06-roadmap.md](06-roadmap.md))

1. İsmin hukuki kontrolü ve `glowlit.app` alan adının alınması.
2. Gizlilik politikası ve kullanım şartları sayfalarının yayınlanması.
3. Supabase'in kurulup deploy edilmesi ve TestFlight'ta uçtan uca test.
4. App Store Connect'te ürünlerin ve abonelik fiyatlarının tanımlanması.
5. App Attest ile ücretsiz kredi suistimaline karşı koruma; yaş doğrulama (Declared Age Range API).
6. Şablon kartlarına gerçek önce/sonra görsellerinin eklenmesi (farklı ten renkleri ve yüz tiplerinden oluşan geniş bir oyuncu kadrosuyla).
7. Büyüme aşaması: selfie profilli Likeness Lock v2, şablonların video versiyonları, C2PA içerik kimlik bilgileri, yerelleştirme.
