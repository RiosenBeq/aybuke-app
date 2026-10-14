# Glowlit: kalan işler ve devam promptları

> **Türkçe özet:** Uygulama, backend, App Store Connect kaydı, abonelikler, kredi paketleri, gizlilik bilgileri, web sitesi ve App Review notları hazır. Bu dosya bir sonraki oturumun başlangıç noktası. Kalan iş üç parça: (1) iki yarım kalmış çalışmayı (düzen düzeltmeleri ve performans) ana dala birleştirmek ve doğrulamak, (2) iOS ve Mac derlemelerini App Store Connect'e yüklemek, ekran görüntülerini ve satın alımları sürüme bağlamak, (3) son gerçek cihaz testi ve senin açık onayınla incelemeye göndermek. İncelemeye gönderme adımı yalnızca sahibin açık onayıyla yapılır.

Son güncelleme: 14 Ekim 2026. Çalışma durduruldu; aşağıdaki "Açık işler" bölümü güncel durumu anlatır.

## 1. Nerede, hangi hesapta, hangi klasörde

- **Yerel klasör (bu Mac):** `/Users/okanberkmanavoglu/Downloads/fotoai`
- **GitHub deposu:** https://github.com/RiosenBeq/aybuke-app (eski adı `furkan`; eski adresler yönlendirilir, ama web sitesi adresi değişti)
- **Ana dal:** `pink-girls-redesign` (en son commit `e99701f`)
- **Bekleyen dallar (GitHub'da, yerel kopyalarıyla birlikte):**
  - `worktree-agent-a4a75767d883b6d64` — düzen düzeltmeleri (Onboarding "Try it on your photo" butonu kayması dahil). Son commit: WIP "onboarding layout change left unfinished". Düzeltme commit'leri: `4f5d9a8`, `7ea8421`, `ce18b5f`.
  - `worktree-agent-a1f71de31e33eae9b` — performans çalışması, 12 commit, son commit `9e37a6f` ("Document the performance pass and its rules").
  - Yeni bir hesapta yerel `.claude/worktrees/` klasörleri olmayabilir; her iki dal GitHub'dan çekilebilir: `git fetch origin && git checkout worktree-agent-...`.
- **Web sitesi:** https://riosenbeq.github.io/aybuke-app/ (GitHub Pages, `website.yml` iş akışı, `web/` ve `legal/` değişince otomatik yayınlanır)
- **Backend:** Supabase projesi `efapupjvidyqhqdevmcu` (Frankfurt, EU). Anon anahtar `ios/App/Resources/AppConfig.json` içinde (herkese açık olması tasarım gereği).
- **App Store Connect uygulama kimliği:** `6822716008` — "Glowlit: AI Photo Editor", iOS ve macOS 1.0 "Prepare for Submission".
- **Paket kimliği:** `app.glowlit.ios` (widget: `app.glowlit.ios.widgets`), takım `CBTKNY3LFC`.

## 2. Hesaplar ve gizli bilgiler (repoda OLMAZ)

- **App Store Connect API anahtarı:** dosya `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` olarak bu Mac'te. Yeni hesap/makinede kullanmak için sahibin dosyayı güvenli biçimde kopyalaması gerekir. Dosyayı asla commit etme, yazdırma veya bir yere yapıştırma. Anahtar kimliği ile issuer kimliği App Store Connect → Users and Access → Integrations sayfasındadır. **Kontrol:** o sayfadaki anahtar listesinde "Claude Build Upload" adıyla görünen anahtar kimliği, dosya adındaki kimlikle aynı mı, doğrulanmalı.
- **Supabase CLI:** bu Mac'te `supabase login` ile Glowlit hesabına bağlandı. Yeni makinede `supabase login` yeniden gerekir. Fonksiyon dağıtımı: `supabase functions deploy ai-image credits-redeem account report --project-ref efapupjvidyqhqdevmcu --use-api`.
- **Supabase gizli değerleri (Edge Function Secrets):** `XAI_API_KEY` (sahip kaydetti), `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_ID`, `OUTPUT_MODERATION` ayarlandı. `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` ve `REVENUECAT_SECRET_KEY` gibi isteğe bağlı değerler henüz yok (hesap silme için Apple token iptali gerekir; bkz. §6).
- **xAI konsolu:** Zero Data Retention açık olmalı — **sahibin işi, doğrulanmadı.**
- **Apple sahibi:** App Store Connect "Account Holder" sahibin Apple kimliği. Sözleşmeleri kabul etmek ve gönderimi onaylamak yalnızca sahibin işidir.
- **Yerel gizli dosyalar:** `ios/Config/Secrets.xcconfig` (gitignore'da, yalnızca DEBUG'da kullanılır). Repoya girmez.

## 3. Tamamlananlar (özet)

- Supabase: tablolar (migration `20261011`–`20261015`, `20261016` izin migration'ı SQL Editor'da çalıştırıldı), cleanup cron işi (`*/5`), anonim giriş açık, Apple sağlayıcısı açık (client id `app.glowlit.ios`), 4 fonksiyon yayında, gerçek AI işi uçtan uca çalıştı (yeni kullanıcıya 3 ücretsiz kredi).
- App Store Connect: uygulama kaydı, iOS + macOS, ad, alt başlık, açıklama, anahtar kelimeler, promosyon metni (13 dil), gizlilik ve kullanım koşulları URL'leri, yaş derecelendirmesi 13+, kategoriler (Photo & Video / Graphics & Design), fiyat ücretsiz, 174 ülke (Çin anakarası hariç), App Privacy yayında (5 veri türü), App Review iletişimi (ad, e-posta `hello@buaze.com`, telefon) ve notlar.
- Abonelik grubu "Glowlit Pro": `app.glowlit.pro.yearly` ($39.99, 1 hafta ücretsiz deneme), `app.glowlit.pro.monthly` ($5.99, ilk ay $1.99), her ikisi için en-US ve tr metinleri, 174 ülke fiyatı, tanıtım teklifleri, inceleme ekran görüntüsü.
- Krediler: `app.glowlit.credits.30` ($2.99) ve `app.glowlit.credits.100` ($7.99), en-US ve tr metinleri, fiyat, ülkeler, inceleme ekran görüntüsü.
- RevenueCat: uygulama, public key, App Store bağlantısı; Apple sunucu bildirim URL'leri (üretim ve sandbox) ASC'ye girildi.
- Web sitesi ve yasal metinler: operatör "Okan Berk Manavoğlu (bireysel geliştirici)", adres "İstanbul, Türkiye", şirket sicil/KEP yok, AB/İngiltere temsilcisi atanmadı, barındırma AB (Frankfurt). Tüm iletişim adresi `hello@buaze.com`.
- Uygulama yapılandırması: backend URL, anon key, App Store ID, web ve yasal URL'ler, `forceDemoMode: false`. `check-release-config.py --report` geçiyor.
- Çeviri: 11 dil uygulama kataloglarında.
- Destek/gizlilik: `hello@buaze.com` her yerde.

## 4. Açık işler (sırayla)

1. **Dalları birleştir ve doğrula.**
   - Önce `worktree-agent-a4a75767d883b6d64` (düzen): `ce18b5f`, `7ea8421`, `4f5d9a8` düzeltmeleri + WIP commit'i tamamla. Onboarding'deki "Try it on your photo" butonunun kayması hâlâ kontrol edilmeli: iPhone 17e, İngilizce, Almanca ve Rusça, büyük yazı boyutu.
   - Sonra `worktree-agent-a1f71de31e33eae9b` (performans): 12 commit. Çakışmaları iki tarafı da koruyarak çöz.
   - Birleştirmeden sonra `pink-girls-redesign` üzerinde doğrulama (§5).
2. **Derle ve test et** (§5). Hiçbir uyarı yeni olmamalı.
3. **iOS derlemesini yükle:** `ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/upload-app-store.sh`. Yaklaşık 2 GB boş alan gerekir. Build numarası saat/dakikaya göre otomatik.
4. **Mac derlemesini yükle:** aynı script, `PLATFORM=mac` ile.
5. **Derlemeleri sürümlere bağla:** İşlenme 10–30 dk sürer. App Store Connect → iOS 1.0 ve macOS 1.0 → Build bölümünden seç.
6. **Ekran görüntüleri:** iPhone 6.9" (1290×2796) `docs/marketing/app-store/en/` ve `tr/` ve diğer dillerde; iPad 13" (2064×2752) `…/ipad/`; Mac (2880×1800) `…/mac/`. Yeni `09-library` gibi yanlış/boş dosyaların olmadığını kontrol et.
7. **Abonelik ve kredi paketlerini sürüme ekle:** App Store Connect'te ilk abonelik, uygulama sürümüyle birlikte incelemeye gönderilmek zorundadır. Her paketi "Add for Review" ile sürüme bağla.
8. **Paid Apps Agreement:** Business → "View and Agree to Terms" (sahibin işi). Bu olmadan ücretli ürün satılamaz.
9. **Sandbox testi (gerçek iPhone):** satın alma, geri yükleme, deneme, kredi paketi, hesap silme. Bu adım gerçek cihaz gerektirir. Adım adım liste: [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) (§1, §4–§10).
10. **Gerçek AI testi:** uygulamada Magic Edit ya da Create ile bir fotoğraf; sunucu yanıtı ve kredi düşümü kontrol edilir ([`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) §3; bilinen riskler §12).
11. **Son kontroller:** App Review notları, telefon (sahip doğrulayacak), yasal metinler (avukat/uzman incelemesi önerilir), çeviri kontrolü (anadil konuşanı).
12. **Gönderim:** SADECE sahibin açık onayıyla "Submit for Review".

## 5. Doğrulama komutları

```bash
cd /Users/okanberkmanavoglu/Downloads/fotoai
swift test --package-path ios/Packages/AppCore
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'id=<simülatör-udid>' -quiet
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'platform=macOS,arch=arm64,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
python3 scripts/build-legal.py --check
python3 scripts/export-core-strings.py --check
python3 scripts/check-honest-copy.py
python3 scripts/check-release-config.py --report
```

Ağır derlemelerde disk alanı kontrol et (`df -h /System/Volumes/Data`). Önce DerivedData klasörlerini temizle: `~/Library/Developer/Xcode/DerivedData/Glowlit-*`.

## 6. Bilinen sorunlar ve riskler

- **Overlap (düzen) düzeltmeleri:** kullanıcı "Try it on your photo" butonunun kaydığını bildirdi; düzeltme dalında ama henüz birleşmedi. iPad ve Mac düzeni yalnızca derlendi, ekranda doğrulanmadı.
- **Mac'te Eserlerim:** "Complete unless open" korumasıyla boş görünüyordu; Mac için "until first unlock" ve yeniden deneme eklendi. Gerçek Mac'te doğrulanmalı.
- **Sign in with Apple:** Supabase'de Apple sağlayıcısı açık ama secret boş. Yerel iOS girişi için yeterli olabilir; web akışı için gerekir. Hesap silme için Apple token iptali (`APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY`) henüz yok — eklenmeden hesap silme tam olmaz.
- **Açıklama uzunluğu:** Apple 4000 karakter üst sınırı var; uzun dillerde link etiketleri kısaltıldı. Yeni metin eklenirse tekrar ölç.
- **Apple emoji kuralı:** açıklama ve promosyon metninde emoji yok (Apple reddediyor).
- **Hukuki metinler:** operatör bilgisi bireysel geliştirici olarak dolduruldu; yayın öncesi bir avukat ya da uzman incelemesi önerilir.
- **Codex inceleme kotası:** PR #1 incelemesi için otomatik bot kotası doldu; bu kod hatası değil.
- **Notlar:** `.claude/` klasörü commit edilmez. Kişisel e-posta adresleri açık dosyalara yazılmaz (yalnızca `hello@buaze.com`).

## 7. Devam promptları

### Prompt 1 — birleştir ve doğrula
```text
Çalışma klasörü: /Users/okanberkmanavoglu/Downloads/fotoai (GitHub: RiosenBeq/aybuke-app, dal pink-girls-redesign).
Önce AGENTS.md ve docs/NEXT-STEPS.md dosyalarını oku. Sonra şunları yap:
1. git fetch origin. pink-girls-redesign'in güncel olduğunu doğrula (e99701f ya da üstü).
2. worktree-agent-a4a75767d883b6d64 dalını (düzen düzeltmeleri, WIP dahil) pink-girls-redesign'e --no-ff ile birleştir. WIP commit'i düzgün bir commit mesajıyla bitir. Onboarding'de "Try it on your photo" butonunun kaymasının gerçekten düzeldiğini iPhone 17e simülatöründe İngilizce, Almanca, Rusça ve büyük yazı boyutunda kontrol et (xcrun simctl ile ekran görüntüsü al, Read ile incele).
3. worktree-agent-a1f71de31e33eae9b dalını (performans, 12 commit) birleştir. Çakışmalarda iki tarafı da koru.
4. §5'teki doğrulama komutlarını çalıştır. Hata veya yeni uyarı varsa düzelt.
5. Bitince git push origin pink-girls-redesign. Yeşil değilse push etme, sorunu yaz.
Kurallar: sır (API anahtarı, .p8, Secrets.xcconfig) yazdırma veya commit etme. .claude/ commit etme. Commit mesajları Co-Authored-By satırıyla bitsin. Gönderim (Submit for Review) yapma.
Sonunda: birleştirilen commit'ler, doğrulama sonuçları, kalan sorunlar.
```

### Prompt 2 — App Store Connect'e yükle ve sürümü hazırla
```text
Çalışma klasörü: /Users/okanberkmanavoglu/Downloads/fotoai. Önce AGENTS.md ve docs/NEXT-STEPS.md'yi oku. Prompt 1 tamamlanmış ve pink-girls-redesign GitHub'da yeşil olmalı.
1. ~/.appstoreconnect/private_keys altında AuthKey_<KEY_ID>.p8 olduğunu doğrula (içeriğini yazdırma). App Store Connect → Users and Access → Integrations'taki anahtar kimliği ile dosya adındaki kimliği karşılaştır; uyuşmuyorsa dur ve sor.
2. Disk alanını kontrol et; 2 GB'tan azsa DerivedData temizle ve sor.
3. ASC_KEY_ID ve ASC_ISSUER_ID ortam değişkenleriyle scripts/upload-app-store.sh'i çalıştır (iOS). Hata olursa log'u oku ve çözümü yaz; sırrı yazdırma.
4. PLATFORM=mac ile Mac derlemesini yükle.
5. İşlenme bitince (App Store Connect → TestFlight ya da sürüm → Build) iOS 1.0 ve macOS 1.0 sürümlerine derlemeyi bağla.
6. Ekran görüntülerini yükle: iPhone (1290×2796, en ve tr dillerinde docs/marketing/app-store/<lang>/), iPad (2064×2752, <lang>/ipad/), Mac (2880×1800, <lang>/mac/). Eski ya da boş dosyaları atla.
7. Abonelik grubu "Glowlit Pro" ve iki kredi paketini ilk sürüm incelemesine ekle (App Store Connect → sürüm → In-App Purchases and Subscriptions).
8. Paid Apps Agreement'ın kabul edilmediğini raporla; kabul sahibin işi.
Gönderim (Submit for Review) yapma. Sonunda: yüklenen derleme numaraları, bağlanan öğeler, eksik kalanlar.
```

### Prompt 3 — son kontrol ve onay hazırlığı
```text
Çalışma klasörü: /Users/okanberkmanavoglu/Downloads/fotoai. Prompt 1 ve 2 tamamlanmış olmalı.
1. Gerçek cihaz kontrol listesi hazır: docs/RELEASE-CHECKLIST.md (sahip kendi iPhone ve Mac'inde uygular). Boş kalan kutuları ve §12'deki koddan görülen riskleri oku, kararları rapora yaz.
2. Kodda etiket ya da akış değiştiyse önce docs/RELEASE-CHECKLIST.md'yi güncelle.
3. App Store Connect'te sürüm sayfasını tara: her alan dolu mu (açıklama, anahtar kelimeler, destek URL'si, gizlilik URL'si, App Review notları, telefon, ekran görüntüleri, derleme, fiyat, ülkeler, yaş derecelendirmesi). Eksik olanları raporla.
4. Hiçbir şeyi "Submit for Review" ile gönderme. Sahibe şu soruyu sor: "Her şey hazır. Gönderelim mi?" ve onay gelmeden dur.
Sonunda: eksik alanlar listesi ve sahibin yapması gereken adımlar.
```
