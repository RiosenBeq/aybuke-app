# Glowlit — Yönetici Özeti (Türkçe)

> Bu belge, araştırmayla alınan tüm kararların Türkçe özetidir. Ayrıntılar ve kaynaklar İngilizce belgelerdedir ([docs/README.md](README.md)).

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
2. **Marka:** isim **Glowlit**, slogan *"Make it glow."*, "Golden Hour" amber paleti, Bricolage Grotesque yazı tipi, "Sunrise Split" ikonu.
3. **iOS uygulaması (SwiftUI):**
   - Ekranlar: onboarding, AI onayı, keşfet, metinden görsel oluşturma, editör (Magic Edit, stiller, iyileştirme, arka plan silme, nesne silme, ayarlar), kütüphane, paywall, ayarlar.
   - Backend olmadan da tamamen çalışan **demo modu** var.
4. **Backend (Supabase + fal.ai):**
   - Kimlik doğrulama, kredi defteri, Apple satın alma doğrulaması, güvenlik filtreleri ve asenkron AI iş kuyruğu.
5. **Testler ve CI:**
   - 48 Swift birim testi.
   - Deno tip kontrolü ve lint.
   - Gerçek PostgreSQL üzerinde kredi defteri testleri.
   - macOS'ta Xcode derlemesi ve simülatör ekran görüntüleri.

## Temel kararlar ve nedenleri

### İsim: Glowlit
- **Anlamı:** "Glow" kategorinin en duygusal sonuç kelimesi (glow-up, ışıl ışıl cilt, altın saat ışığı); "lit" ise ışıkla aydınlanmış demek, Z kuşağı argosunda da "harika" anlamına geliyor.
- **Neden diğer adaylar değil:** Araştırmadan çıkan Sunlit, Lumora, Pixora, Aglow gibi adayların `.app` ve `.ai` alan adları dolu, yani aktif kullanımdalar. **glowlit.app ve glowlit.ai ise boş.** Türetilmiş bir isim olduğu için marka tescili açısından da sözlük kelimelerinden daha güçlü.
- **Okunuş ve diller:** Duyulduğu gibi yazılıyor. İngilizce, İspanyolca, Portekizce, Fransızca, Almanca ve Türkçede olumsuz bir anlamı yok.
- **Mağaza başlığı:** `Glowlit: AI Photo Editor`.
- ⚠️ Lansmandan önce App Store, USPTO ve EUIPO marka taraması yapılmalı ve `glowlit.app` alınmalı.

### Renk: "Golden Hour" amber
- **Boş alan:** İncelenen 34 AI görsel markasının **hiçbiri** turuncu/amber ile öne çıkmıyor. Mor ("AI moru"), mavi, pembe ve siyah çok kalabalık.
- **Anlam:** Fotoğrafçılığın özü ışık; altın saat ışığı cildi en güzel gösteren ışık.
- **Koyu tema:** Arayüz koyu (#0C0C0E). Foto/Video paywall'larının yaklaşık %79'u koyu ve fotoğraflar koyu zeminde öne çıkıyor.
- **Kural:** Her ekranda yalnızca **bir** amber eleman bulunur (ana aksiyon). Amber üzerine beyaz yazı **yazılmaz** (kontrast 2.1:1); her zaman koyu mürekkep (#1A1206) kullanılır, kontrast 8.8:1.

### Yazı tipi: Bricolage Grotesque + SF Pro
- **Seçim:** Başlıklarda karakterli, sıcak bir grotesk; gövde metinlerinde Apple'ın SF Pro'su (Dynamic Type desteği için).
- **Lisans ve kesimler:** Lisansı SIL OFL, yani ücretsiz ve uygulamaya gömülebilir. Değişken fonttan üç statik kesim üretildi.
- **Elenenler:** Space Grotesk ve Sora sıradan "AI/web3" görünümü veriyor (Sora ayrıca OpenAI ile karışıyor); Unbounded kripto çağrışımı taşıyor.

### İkon: "Sunrise Split"
Amber zemin üzerinde yarısı karanlık (öncesi), yarısı aydınlık (sonrası) bir disk ve ortada karşılaştırma tutamacı. Hem ışığı, hem önce/sonra dönüşümünü, hem de uygulamanın imza etkileşimini anlatıyor. 29 piksele küçültüldüğünde de okunuyor.

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
