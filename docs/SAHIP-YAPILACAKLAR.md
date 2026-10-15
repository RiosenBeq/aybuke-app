# Sahip yapılacaklar

Bu liste yalnızca sahibin yapabileceği işleri içerir: Supabase, xAI, Anthropic (Claude Console), AdMob, AdSense, App Store Connect, Search Console, Vercel ve Mac'te Xcode. Ajan (bu depoda kod ve belge değiştiren asistan) bu hesaplara giremez, anahtar giremez ve gönderme kararı veremez. "Öneri" satırları yalnızca yardımcı görüştür; karar sahibindedir.

**Durum.** 15 Ekim 2026, akşam. **Aybuke 1.0 incelemede:** iOS (derleme 20261015.1225) abonelik grubu, iki abonelik ve iki kredi paketiyle, macOS (derleme 20261015.1233) ile birlikte gönderildi; ikisi de WAITING_FOR_REVIEW, yayın türü AFTER_APPROVAL (onaylanınca kendiliğinden yayına girer). Derlemeler manuel imzalama ve altool ile yüklendi. Backend canlı: migrasyonlar `20261029000002`'ye kadar uygulandı, yedi fonksiyon yayında (`owner-digest` dahil), gizli değerler tamam (Apple ile giriş, Resend ve özet anahtarları dahil), üç cron işi çalışıyor; günlük sigortalar 60 ücretsiz, 10 doğrulanmamış, toplam 400 iş; sahip uyarı e-postaları ve günlük özet geliyor. Apple ile giriş 1.0'da açık (anahtar `36Q32XU57F`, Apple'a karşı doğrulandı). xAI Zero Data Retention "Active". App Privacy 10 veri türüyle yayımlandı. RevenueCat projesi ve uygulaması Aybuke adını aldı, Apple bildirim yönlendirme adresi girildi; Supabase organizasyonu ve projesi de Aybuke oldu. AdMob GDPR mesajı yayında. Yeni ikon Aura Lens (Holo Heart, Ürün Sayfası Optimizasyonu testleri için alternatif ikon olarak derlemede). 364 ekran görüntüsü ve en-US iPhone uygulama önizlemesi yüklendi. TestFlight iç grubu "Aybuke Team" var.

**Kalan (yalnızca sen).** 1.1 ve 1.11 (xAI ve Anthropic harcama limitleri ve bakiye yükleme), 1.2 (xAI anahtarını döndür), 6.1–6.3 (Anthropic ve xAI DPA'ları, KVKK adımları, avukat), 3.7 (onaydan sonra AdMob uygulamasını mağaza kaydına bağla; ana oturum bunu izliyor), 2.12 (TestFlight'ta cihaz testi, artık isteğe bağlı), 3.4 ve 3.6 (AdMob adı, AdSense), 5.1, 5.3–5.5 ve 5.7 (kararlar).

## 1) Önce bunlar (acil)

### 1.1 xAI kredisini yükle ya da aylık limiti artır
- [x] **Kredi yüklendi:** 14 Ekim 2026, 10 USD. Kalan: aylık harcama limitini belirle ve ilk gerçek Magic Edit'i dene (aşağıdaki sıra, adım 2 ve 3).
- [ ] **Ne:** xAI ekip kredisi ya da aylık harcama limiti bitmişti. Bu yüzden her AI işi başarısız oluyor ve kredi iade ediliyordu.
  - **Neden:** `docs/HANDOFF-PROMPT.md`, "xAI" bölümü. Faturalandırma ve harcama limiti: `docs/SUPABASE-TODO.md` §7.
  - **Nerede:** console.x.ai, ekip faturalandırma ve harcama limiti. Menü adları konsolun güncel arayüzüne göre değişebilir.
  - **Sıra:** 1) Kredi yükle. 2) Aylık harcama limiti belirle. 3) Uygulamada bir Magic Edit dene; sonuç gelmeli (`docs/RELEASE-CHECKLIST.md` §3.4).
- [ ] **Bütçe notu:** Bir bulut işi xAI'de yaklaşık 0,04–0,07 USD tutar (oluşturma 0,04, düzenleme 0,05–0,07; `docs/03-product-spec.md`, "AI provider"). Yüklenen 10 USD yalnızca yaklaşık 150–250 düzenlemeye yeter; test ve inceleme için yeterli, lansman için değil. Sunucunun günlük sigortaları (`credit_policy()`, 15 Ekim 2026'dan beri) ücretsiz işleri günde 60'ta (doğrulanmamış kurulumlar 10'da), tüm işleri 400'de durdurur: ücretsiz işlerin sınırı günde yaklaşık 2,4–4,2 USD, tüm işlerinki yaklaşık 16–28 USD eder. Bu tavan her işin tek görsel ürettiğini varsayar: Pro üyelerin Create işleri 4 görsele kadar üretebildiği için tüm işlerin tavanı günde yaklaşık 64 USD'ye çıkabilir (400 işin hepsi 4 görselli Create olsa). Sigortalar işleri sayar, görselleri değil; bu yüzden asıl bütçe sınırı xAI'deki aylık harcama limitidir. Limiti bunu hesaba katarak seç; limit dolunca işler başarısız olur ve kredi iade edilir. Claude'un güvenlik denetimi bunun yanında küçüktür: denetim başına yaklaşık 0,0002 USD (Haiku 5.5: milyon token başına 0,10 USD girdi, 0,50 USD çıktı), bir Magic Edit'te iki denetim (fotoğraf ve sonuç); günde 400 iş yaklaşık 0,2 USD'nin altında kalır (1.11).

### 1.2 Sohbete yapıştırılmış xAI anahtarını döndür
- [ ] **Ne:** Sohbete bir kez yapıştırılmış xAI anahtarı güvenli sayılmaz. Yeni anahtar üret, Supabase'e yaz, sonra eskisini iptal et.
  - **Neden:** `docs/HANDOFF-PROMPT.md`, "Owner-only items". Secret adı `XAI_API_KEY` (`backend/.env.example`).
  - **Nerede:** console.x.ai (API anahtarları); Supabase, proje `efapupjvidyqhqdevmcu`, Edge Functions > Secrets.
  - **Sıra:** 1) xAI'de yeni anahtar oluştur. 2) Supabase'de `XAI_API_KEY` değerini yenisiyle değiştir. 3) Bir AI işi dene (1.1 adım 3). 4) Çalıştığını gördükten sonra eski anahtarı xAI'de iptal et. Anahtarı hiçbir dosyaya, commit'e ya da sohbete yazma.

### 1.3 xAI Zero Data Retention'ı doğrula
- [x] **Yapıldı (15 Ekim 2026):** xAI konsolunda Team › Zero Data Retention "Active" (ekip düzeyinde, bütün anahtarlar için; Files and Collections, istek günlükleri ve stateful Responses API kapandı, uygulama bunları kullanmıyor).
- [ ] **Ne:** xAI konsolunda ekip için Zero Data Retention açık mı, bu anahtar için de geçerli mi, kontrol et.
  - **Neden:** Gizlilik metinleri, xAI'nin Zero Data Retention seçeneğini kullandıklarını yazıyor (`legal/en/privacy-policy.md` ve `legal/tr/gizlilik-politikasi.md`, girdilerin saklanmadığı bölüm). Depo bunu kanıtlayamaz (`docs/SUPABASE-TODO.md` §7).
  - **Nerede:** console.x.ai, ekip ayarları.
  - **Sıra:** 1) Açıksa not al. 2) Kapalıysa aç. 3) Açılamıyorsa metinler yanlış olur; avukatla birlikte karar ver (6.1).

### 1.4 Supabase migrasyonlarını sırayla uygula
- [x] **Yapıldı (15 Ekim 2026):** on iki dosya (`20261019000000`–`20261025000003`) sırayla, her biri kendi transaction'ında, hatasız uygulandı; MAC-YAYIN 5.2 sorgusu 19/19. Aynı gün sonraki dokuz dosya da (`20261026000000`–`20261029000002`) uygulandı. Sonradan eklenen bir dosya (ör. `20261030000000`) ayrıca uygulanır; durumunu `docs/SUPABASE-TODO.md`'de kontrol et.
- [ ] **Ne:** `backend/supabase/migrations/` içindeki dosyaları zaman damgası sırasıyla SQL Editor'da çalıştır. Her dosyayı `begin;` ile `commit;` arasına al. Dosyaların içinde kendi transaction ifadesi yok (kontrol edildi), bu yüzden sarmalamak güvenli.
  - **Neden:** Dizinde 21 dosya var. En yeni dördü `20261025000000_app_store_notifications.sql` (iade bildirimleri), `20261025000001_sql_gaps.sql` (bakiye ve tekrar sayımı düzeltmeleri), `20261025000002_refunded_transactions.sql` (iadesi önce gelen satın almalar) ve `20261025000003_notification_prune.sql`; `docs/SUPABASE-TODO.md` §1'de 1.10–1.13. Commit'li `docs/SUPABASE-TODO.md` §3 yalnızca 10 dosya listeliyordu; çalışma ağacındaki taslak §1'de 1.1–1.9 sırasını veriyor. Yedi dosya ilk listede yoktu: `20261020000000_credit_policy_v2.sql`, `20261021000000_install_and_subscription_credits.sql`, `20261022000000_abuse_controls.sql`, `20261023000000_ad_rewards_per_install.sql`, `20261024000000_private_rls.sql`, `20261024000001_abuse_fixes.sql`, `20261024000002_entitlement_order.sql`. `docs/HANDOFF-PROMPT.md`'ye göre `20261011000000`–`20261018000000` ile `20261019500000_keepalive.sql` uygulanmış; taslağın §0 sorgusu `20261017000000` ve `20261018000000` nesnelerini kontrol ediyor.
  - **Nerede:** Supabase panosu > SQL Editor (proje `efapupjvidyqhqdevmcu`, Frankfurt).
  - **Sıra:** 1) `docs/SUPABASE-TODO.md` §0'daki sorguyu çalıştır; eksik nesne varsa ilgili dosyayı önce uygula. 2) Uygulanmış dosyaları atla. 3) §1'deki sırayla, uygulanmamış olanları (1.1–1.13) çalıştır; her dosya kendi `begin;` ... `commit;` bloğunda. 4) Bir dosya hata verirse dur, hata metnini ajana ver; sonraki dosyaya geçme.

### 1.5 Gizli değerleri kontrol et ve eksiği ekle
- [x] **Yapıldı (15 Ekim 2026):** `ADMOB_REWARDED_AD_UNIT`, `APPLE_APP_ID`, `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID` yazıldı; `XAI_API_KEY` ve `ANTHROPIC_API_KEY` var; kaldırılacak ad yok. Sonra `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` (5.6) ile `RESEND_API_KEY`, `DIGEST_SECRET` ve `OWNER_ALERT_TO` (1.12) de eklendi.
- [ ] **Ne:** Adları kontrol et, `ADMOB_REWARDED_AD_UNIT` değerini ekle. Değerleri hiçbir yere yazma.
  - **Neden:** `docs/HANDOFF-PROMPT.md`'ye göre ayarlı: `XAI_API_KEY`, `ANTHROPIC_API_KEY` (15 Ekim 2026'da girildi; Claude güvenlik denetimi, 5.8), `APPLE_APP_ID` (6822716008; yoksa ücretsiz krediler App Store kurulumları için kapalı kalır, taslak §6), `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID`. Eksik: `ADMOB_REWARDED_AD_UNIT` (boşsa her ödül reddedilir; `backend/README.md`, "Rewarded ads"). `OUTPUT_MODERATION` artık okunmuyor (`docs/SUPABASE-TODO.md` §6); `docs/RELEASE-CHECKLIST.md` §1.1 bu adı bekliyor. Ekleme.
  - **Nerede:** Supabase > Edge Functions > Secrets.
  - **Sıra:** 1) `ADMOB_REWARDED_AD_UNIT` = `ca-app-pub-2292230772061554/1406702504`. 2) `FAL_KEY` ve `XAI_SAFETY_MODEL` eklenmez; `ANTHROPIC_SAFETY_MODEL` boş kalabilir (varsayılan `claude-haiku-5-5`; bkz. 5.8). 3) `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS` üretimde olmamalı; varsa sil. 4) Apple ile giriş ve RevenueCat anahtarları isteğe bağlı (bkz. 5.6, 5.7).

### 1.6 Edge Functions'ı yayımla
- [x] **Yapıldı (15 Ekim 2026):** altı fonksiyon yayında (ACTIVE); `ad-reward` ve `app-store-notifications` `--no-verify-jwt`; `ai-image` başlangıç satırı `output check in force: xai + anthropic:claude-haiku-5-5`. Yedinci fonksiyon `owner-digest` de yayında (1.12).
- [ ] **Ne:** Migrasyon ve gizli değerlerden sonra altı fonksiyonu yayımla. `ad-reward` ve `app-store-notifications` ilk kez yayımlanıyor; ikisinde de JWT doğrulaması kapalı olmalı (AdMob ve Apple JWT göndermez; fonksiyonlar imzayı kendileri denetler).
  - **Neden:** Canlıdaki `ai-image`, `account`, `credits-redeem` ve `report` 47b5c6f sürümünden (`docs/HANDOFF-PROMPT.md`); depo daha yeni (`docs/RELEASE-CHECKLIST.md` §12: `ai-image` ve `account` yeniden yayımlanmalı). `ad-reward` hiç yayımlanmadı. AdMob geri çağrısında JWT yoktur (`backend/README.md`, "Setup" 5). Önkoşul: `ai-image` ve `account`, §1 migrasyonları ve §0 nesneleri olmadan yayımlanmamalı (`docs/SUPABASE-TODO.md` §5).
  - **Nerede:** Mac'te Terminal, repo içinde `backend` klasörü, Supabase CLI.
  - **Sıra:** 1) `supabase login` (kendi hesabınla). 2) `cd backend`. 3) Aşağıdaki komutları ayrı ayrı çalıştır (`--use-api`: CLI paketlemeyi Docker yerine Yönetim API'siyle yapar; `docs/HANDOFF-PROMPT.md`'deki yöntem). 4) Yayımdan sonra 1.9'daki kontrolleri yap.

```
supabase functions deploy ai-image --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy credits-redeem --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy account --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy report --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy ad-reward --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
supabase functions deploy app-store-notifications --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
```

### 1.7 Zamanlanmış işleri kontrol et
- [x] **Yapıldı (15 Ekim 2026):** `sweep-jobs`, `sweep-ad-rewards`, `sweep-app-store-notifications` etkin. `revenuecat-deletions` kurulmadı (RevenueCat anahtarı yok, `pg_net` kapalı; isteğe bağlı).
- [ ] **Ne:** Temizlik işleri ve RevenueCat silme kuyruğu çalışıyor olmalı. Keep-alive iş akışı main'de etkin olmalı.
  - **Neden:** Takılan işlerin iadesi ve sonuçların silinmesi `sweep-jobs` ile yapılır; reklam kayıtları `sweep-ad-rewards` ile temizlenir (`backend/README.md`, "Setup" 6; `docs/SUPABASE-TODO.md` §3). Keep-alive, ücretsiz planda projenin duraklatılmasını önler (`.github/workflows/keepalive.yml`).
  - **Nerede:** Supabase > SQL Editor; GitHub > repo > Actions.
  - **Sıra:** 1) `select jobname, schedule from cron.job;` çalıştır. `sweep-jobs` (`*/5 * * * *`), `sweep-ad-rewards` (`17 * * * *`) ve `sweep-app-store-notifications` (`23 3 * * *`) yoksa `docs/SUPABASE-TODO.md` §3'teki komutlarla ekle; aynı adla eklemek mevcut işi değiştirir, o yüzden önce kontrol et. 2) `revenuecat-deletions` için `select name from vault.decrypted_secrets;` ile `project_url` ve `service_role_key` adlarına bak; varsa yeniden ekleme. Service role anahtarını hiçbir yere yapıştırma. 3) GitHub Actions'ta "Backend keep-alive" iş akışının çalıştığını kontrol et. Public depoda 60 gün commit yoksa GitHub zamanlamayı durdurur (`keepalive.yml` yorumu); durduysa Actions'tan yeniden etkinleştir.

### 1.8 Kimlik doğrulama ayarları (CAPTCHA açılmaz)
- [x] **Yapıldı (15 Ekim 2026):** anonim giriş açık, saatte IP başına 15, e-posta kapalı, CAPTCHA kapalı (panelde okundu).
- [ ] **Ne:** Anonim giriş açık, e-posta sağlayıcısı kapalı, CAPTCHA kapalı, Apple sağlayıcısında Client IDs `app.glowlit.ios`.
  - **Neden:** `backend/README.md`, "Setup" 2: uygulamanın CAPTCHA widget'ı yok; CAPTCHA açılırsa her anonim kayıt başarısız olur. Commit'li `docs/SUPABASE-TODO.md` §4 CAPTCHA (Turnstile) öneriyordu; çalışma ağacındaki taslakta bu öneri geri alınmış (kapalı kalsın).
  - **Nerede:** Supabase > Authentication > Sign In / Providers ve Rate Limits.
  - **Sıra:** 1) CAPTCHA'nın kapalı olduğunu doğrula. 2) Anonim girişte sınır 15 giriş/saat/IP olsun. 3) E-posta sağlayıcısı kapalı olsun. 4) Apple'da Client IDs `app.glowlit.ios` olsun.

### 1.9 Kontroller: Security Advisor ve duman testi
- [x] **Yapıldı (15 Ekim 2026):** anonim kullanıcının çalıştırabildiği tek fonksiyon `keepalive()`, RLS'si kapalı tablo yok, Security Advisor bulgu yok; duman testi ve gerçek bir Magic Edit geçti, test kullanıcıları silindi.
- [ ] **Ne:** Security Advisor uyarılarını oku; anonim bir kullanıcıyla duman testi yap; test kullanıcısının silindiğini doğrula.
  - **Neden:** `docs/HANDOFF-PROMPT.md` adım 6. `20261020000000_credit_policy_v2.sql`, Security Advisor'ın "Function Search Path Mutable" uyarısını gidermeyi amaçlıyor.
  - **Nerede:** Supabase panosu > Advisors > Security Advisor; SQL Editor; Terminal. Proje adresi ve anon anahtar `ios/App/Resources/AppConfig.json` içinde. Değerleri kopyalayıp bir dosyaya yazma.
  - **Sıra:** 1) Security Advisor'da beklenen sonuç: "function search path mutable" bulgusu yok; `private` tablolarda RLS kapalı bulgusu yok. `docs/SUPABASE-TODO.md` §2 sorgusunda anonim kullanıcının çalıştırabildiği tek fonksiyon `public.keepalive()`. Başka bulgu varsa listele ve ajana ver. 2) Anonim oturum aç; `GET /functions/v1/ai-image` ile bakiyeyi al. 3) `DELETE /functions/v1/account` ile sil. 4) Authentication > Users'ta kullanıcının gittiğini gör. 5) İsteğe bağlı: `select public.ops_daily_summary();` ile günü oku.

### 1.10 Eski "inventory" projesine dokunma
- [ ] **Ne:** Supabase hesabında bu uygulamayla ilgisi belirsiz eski bir proje olabilir. Silme geri alınamaz.
  - **Neden:** `docs/SUPABASE-TODO.md` §9: bu depoya ait değil; karar sahibin.
  - **Nerede:** Supabase > proje listesi > proje ayarları (General).
  - **Sıra:** 1) Proje adını ve içeriğini kontrol et. 2) Bu uygulamayla ilgisi kanıtlanmadıkça silme. 3) Silinecekse yalnızca sahip yapar. Ajan silmeye dokunmaz.

### 1.11 Anthropic (Claude) hesabı: bakiye ve harcama limiti
- [x] **Kısmen (15 Ekim 2026):** log satırı `output check in force: xai + anthropic:claude-haiku-5-5` göründü ve gerçek bir Magic Edit'te fotoğraf ve sonuç denetimi geçti (adım 3 ve 4). Kalan: bakiye yükleme ve aylık harcama limiti (adım 1 ve 2).
- [ ] **Ne:** `ANTHROPIC_API_KEY` Supabase'de ayarlı. Claude Console'da (platform.claude.com) hesabın bakiyesi olduğunu kontrol et ve aylık harcama limiti koy.
  - **Neden:** Claude, düzenlenecek fotoğrafı ve her sonucu denetleyen bağımsız güvenlik denetimi (`backend/supabase/functions/_shared/safety.ts`, model `claude-haiku-5-5`). Denetim fail-closed çalışır: bakiye biterse, anahtar geçersizse ya da istek reddedilirse her düzenleme ve her sonuç engellenir ve kredi iade edilir. Maliyet denetim başına yaklaşık 0,0002 USD (1.1, bütçe notu).
  - **Nerede:** platform.claude.com, Settings altında Billing ve Limits (menü adları konsolun güncel arayüzüne göre değişebilir); Supabase > Edge Functions > Secrets (yalnızca adı kontrol et).
  - **Sıra:** 1) Bakiye ya da ödeme yöntemi olsun. 2) Aylık harcama limiti koy (örneğin 10–20 USD; denetimin payı küçük). 3) Yayımdan (1.6) sonra Supabase > Edge Functions > Logs'ta `ai-image` için `output check in force: xai + anthropic:claude-haiku-5-5` satırını gör. 4) Bir Magic Edit dene; sonuç gelmeli. Anahtarı hiçbir dosyaya, commit'e ya da sohbete yazma.

### 1.12 Sahip e-postaları (Resend): yeni Pro üye ve günlük özet
- [x] **Yapıldı (15 Ekim 2026):** `owner-digest` yayında; yeni üye uyarıları ve günlük özet e-postaları geliyor. Aşağıdaki adımlar kayıt içindir.
- [ ] **Ne:** `RESEND_API_KEY`, `DIGEST_SECRET` ve `OWNER_ALERT_TO` Supabase'de, `DIGEST_SECRET` GitHub'da ayarlı. Kalan: fonksiyonları yayımla ve bir kez dene.
  - **Neden:** İlk kez kaydedilen her Pro abonelik ve her kredi paketi için anında e-posta (sandbox satın almalar `[TEST]` diye işaretli), her sabah 06:00 UTC'de (İstanbul 09:00) dünün özeti. E-postalarda kullanıcı kimliği, e-posta, token ya da istem yok; yalnızca sayılar, plan ve saat.
  - **Nerede:** `backend/README.md` "Owner alerts"; Resend > Domains; GitHub > Actions > Owner digest.
  - **Sıra:** 1) `supabase functions deploy owner-digest`, sonra `supabase functions deploy ai-image credits-redeem ad-reward` (yeni Pro uyarısı bu üçünde). 2) GitHub > Actions > Owner digest > Run workflow; e-posta gelmeli. 3) Varsayılan gönderen `onboarding@resend.dev` yalnızca Resend hesabının kendi adresine teslim eder: `hello@buaze.com` Resend hesabının adresi değilse Resend'de `buaze.com` alan adını doğrula, sonra `OWNER_ALERT_FROM='Aybuke <alerts@buaze.com>'` ayarla. Anahtarı hiçbir dosyaya, commit'e ya da sohbete yazma.

## 2) Uygulama yayını (App Store Connect ve Mac)

### 2.1 Bağlantı adreslerini tarayıcıdan doğrula
- [x] **Yapıldı (15 Ekim 2026):** aybuke.org, /support, gizlilik ve kullanım sayfaları 200; `check-release-config.py --online` geçiyor.
- [ ] **Ne:** Uygulamanın `websiteURL`, `privacyPolicyURL` ve `termsURL` adresleri artık aybuke.org'u gösteriyor (`ios/App/Resources/AppConfig.json`; bu değişiklik commit'lenecek). Adreslerin tarayıcıda açıldığını doğrula.
  - **Neden:** `AGENTS.md` §6 (4. madde). Bu adresler paylaşım yazılarında ve davet QR kodunda kullanılır. Bu ortamdan dış sitelere çıkılamadığı için `check-release-config.py --online` burada kanıt değil.
  - **Nerede:** Tarayıcı; Vercel (`RiosenBeq/aybuke` dağıtımı, aybuke.org alan adı).
  - **Sıra:** 1) Tarayıcıda aç: `https://aybuke.org`, `https://aybuke.org/legal/en/privacy-policy`, `https://aybuke.org/legal/tr/gizlilik-politikasi`, `https://aybuke.org/app-ads.txt` ve destek sayfası (2.4). 2) Hepsi açılıyorsa `python3 scripts/check-release-config.py --online` çalıştır. 3) Açılmıyorsa Vercel dağıtımını ve alan adını kontrol et; ajana bildir.

### 2.2 Derlemeleri yükle (önce disk ve CI)
- [x] **Yapıldı (15 Ekim 2026):** iOS 20261015.1225 ve Mac 20261015.1233, manuel imzalama ve altool ile (otomatik imzalama bu Mac'te çalışmadı; yöntem `AGENTS.md` §6, 2. madde). App Group ve widget kimliği artık portalda var.
- [ ] **Ne:** iOS ve macOS derlemelerini yükle. Arşiv için yaklaşık 2 GB boş alan gerekir.
  - **Neden:** `AGENTS.md` §6 (2. madde) ve `docs/HANDOFF-PROMPT.md` adım 9 (disk neredeyse dolu). CI (`.github/workflows/ci.yml`) yalnızca `main`'e push'ta ve PR'larda çalışır. `6f2959d` için CI çalışıyor görüldü; `31f8817` için çalıştırma kaydı görünmedi.
  - **Nerede:** Mac'te Terminal, repo kökü. App Store Connect API anahtarı `~/.appstoreconnect/private_keys/` içinde; commit'e girmez.
  - **Sıra:** 1) Disk boşalt. 2) Son commit'in CI'ını GitHub Actions'ta kontrol et. Öneri: yeşil olmadan yükleme yapma. 3) `ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> scripts/upload-app-store.sh`. 4) `PLATFORM=mac ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> scripts/upload-app-store.sh`. 5) İşleme bitince (10–30 dk) derlemeleri 2.3'te sürüme bağla.

### 2.3 Derlemeyi ve satın almaları 1.0 sürümüne bağla
- [x] **Yapıldı (15 Ekim 2026):** derlemeler iOS ve macOS 1.0'a bağlandı; abonelik grubu, iki abonelik ve iki paket iOS 1.0 ile incelemeye gönderildi. İlk abonelikler Çin fiyatı istedi: CHN ¥298 / ¥38 girildi, Çin yine satışta değil.
- [ ] **Ne:** iOS 1.0 ve macOS 1.0 sürümlerine derlemeyi, iki aboneliği ve iki kredi paketini ekle.
  - **Neden:** `docs/HANDOFF-PROMPT.md` ("App Store Connect"): abonelikler MISSING_METADATA, paketler READY_TO_SUBMIT. İlk abonelik uygulama sürümüyle birlikte incelemeye gönderilmeli (`docs/RELEASE-CHECKLIST.md` §11).
  - **Nerede:** App Store Connect > Aybuke > iOS 1.0 > In-App Purchases and Subscriptions; macOS 1.0'da da aynı bölüm.
  - **Sıra:** 1) `app.glowlit.pro.yearly`, `app.glowlit.pro.monthly`, `app.glowlit.credits.30` ve `app.glowlit.credits.100` ekle. 2) İnceleme ekran görüntüsü ve notu olsun. Paywall görüntüsü `docs/marketing/app-store/en/09-paywall.jpg`. 3) Durumlar "Ready to Submit" olsun.

### 2.4 Destek ve gizlilik adresleri
- [x] **Yapıldı (15 Ekim 2026):** Support `https://aybuke.org/support`, Marketing `https://aybuke.org`, gizlilik EN/TR adresleri 13 dilde API ile yazıldı.
- [ ] **Ne:** App Store Connect'teki Support URL, Marketing URL ve gizlilik URL'lerini tek bir karara bağla.
  - **Neden:** Çalışma ağacındaki taslak `docs/marketing/app-store-connect-setup.md` Support ve Marketing URL'sini `https://aybuke.org` yazıyor. `docs/HANDOFF-PROMPT.md` (adım 7) ise Support URL'sini `https://aybuke.org/support` diyor. İki belge çelişiyor.
  - **Nerede:** App Store Connect > sürüm sayfası (Support URL, Marketing URL) ve App Information (Privacy Policy URL).
  - **Sıra:** 1) `https://aybuke.org/support` açılıyorsa onu, açılmıyorsa `https://aybuke.org` yaz. 2) Gizlilik URL'leri: `https://aybuke.org/legal/en/privacy-policy` ve `https://aybuke.org/legal/tr/gizlilik-politikasi`. 3) Sayfaların 200 döndüğünü kontrol et (2.1).

### 2.5 Telif satırı, yayın türü ve sürüm numarası
- [x] **Yapıldı (15 Ekim 2026):** telif `2026 Okan Berk Manavoğlu`; iOS ve macOS 1.0 yayın türü önce MANUAL yazıldı, sonra AFTER_APPROVAL oldu (onaylanınca kendiliğinden yayın). Sürüm 1.0.
- [ ] **Ne:** Üç ayarı karara bağla.
  - **Telif (karar verildi):** `2026 Okan Berk Manavoğlu`. `docs/HANDOFF-PROMPT.md` ve kurulum dokümanı §6 bu değeri veriyordu; kurulum dokümanındaki eski `2026 Aybuke` satırı bu değerle düzeltildi.
  - **Yayın türü:** HANDOFF'a göre sürüm "AFTER_APPROVAL" (onaydan hemen sonra otomatik yayın). Kurulum dokümanı §6 "Manual release after approval" diyor. Öneri: manuel yayın; backend ve reklam kurulumu bitmeden yayın olmasın.
  - **Sürüm numarası:** `ios/Glowlit.xcodeproj/project.pbxproj` içinde `MARKETING_VERSION = 1.0` (dört yer). `docs/RELEASE-CHECKLIST.md` §11 ve §12-6 "1.0.0" diyor; bu uyarı artık geçerli değil. App Store Connect'te sürüm 1.0 olmalı.
  - **Nerede:** App Store Connect > sürüm sayfası.
  - **Sıra:** 1) Telif satırına `2026 Okan Berk Manavoğlu` yaz. 2) "Manually release this version" seç (öneri). 3) Sürümün 1.0 olduğunu kontrol et.

### 2.6 Abonelik açıklamasındaki kredi sayısı
- [x] **Yapıldı (15 Ekim 2026):** öneri uygulandı: açıklamalar 13 dilde sayısız ("Monthly credits, every look, best-quality AI"); inceleme notları 80 kredi ve fiyatlarla düzeltildi.
- [ ] **Ne:** Abonelik açıklaması "80 kredi" yazıyor; kurulum dokümanı sayı yazılmamasını istiyor. Karar ver.
  - **Neden:** `scripts/asc/iap_localize.py` en-US için "80 credits a month, every look, best AI" yazıyor; HANDOFF'a göre 13 dilde böyle. `docs/marketing/app-store-connect-setup.md` §4: "It names no number on purpose". Sunucudaki sayı (`credit_policy()`) değişebilir.
  - **Nerede:** App Store Connect > abonelik grubu "Aybuke Pro" > yerelleştirmeler; ya da `scripts/asc/iap_localize.py`.
  - **Sıra:** 1) Karar: sayıyı tut ya da kaldır. Öneri: kaldır; sayı değişirse App Store metni de değişmek zorunda kalır. 2) Kaldırılırsa ajan `iap_localize.py` dosyasını düzeltir; App Store Connect'e sen ya da ajan yazar.

### 2.7 App Privacy yanıtları
- [x] **Yayımlandı (15 Ekim 2026):** 10 veri türü (`docs/marketing/app-store-connect-setup.md` §5). Kurulum hash'i beyanının avukatça teyidi 6.1'de kalır.
- [ ] **Ne:** İki konuyu karara bağla, sonra Xcode raporuyla karşılaştır.
  - **Kurulum anahtarı (install-key hash):** Ücretsiz krediler App Store kurulumuna bağlı. Uygulama, StoreKit `AppTransaction`'dan türetilmiş tuzlu bir hash gönderiyor (`backend/README.md`, "Why it's shaped like this" tablosundaki "Free credits per App Store download" satırı). Saklama: son kullanımdan 30 gün (`docs/SUPABASE-TODO.md`, Notlar). `docs/HANDOFF-PROMPT.md` adım 10 "App Functionality / fraud prevention" diyor; ama kurulum dokümanı §5, `docs/RELEASE-CHECKLIST.md` §11 ve `ios/App/Resources/PrivacyInfo.xcprivacy` bu veriyi içermiyor. Karar: veri türü ve kullanıcıyla ilişkisi.
  - **E-posta:** `docs/RELEASE-CHECKLIST.md` §11 "Email Address" işaretli diyor; kurulum dokümanı §5 girişe kapalıyken beyan edilmeyebileceğini yazıyor. `PrivacyInfo.xcprivacy` e-postayı listeliyor. Karar: tutarlı bir yanıt seç.
  - **Nerede:** App Store Connect > App Privacy; Xcode > Organizer > Archive > Generate Privacy Report.
  - **Sıra:** 1) Archive'dan Privacy Report al. 2) İki kararı yaz. Öneri: kurulum hash'inin beyanını avukatla (6.1) teyit et. 3) Ajan `PrivacyInfo.xcprivacy` dosyasını karara göre güncelleyecek.

### 2.8 Yaş derecelendirmesi ve Age Assurance
- [ ] **Ne:** HANDOFF'a göre 13+ (override), Advertising ve Age Assurance işaretli. Kurulum dokümanı §2 Age Assurance'ı, yaş adımı içeren derleme yayındayken işaretlemeyi söylüyor.
  - **Neden:** `docs/marketing/app-store-connect-setup.md` §2; `docs/HANDOFF-PROMPT.md` ("App Store Connect").
  - **Nerede:** App Store Connect > yaş derecelendirmesi.
  - **Sıra:** 1) Karar: Age Assurance işareti kalsın mı. Öneri: dokümanla uyum için işareti yaş adımını içeren derleme yayına girene kadar kaldır. 2) Advertising işareti kalmalı.
  - **Not (15 Ekim 2026):** yaş adımını içeren 1.0 incelemede ve AFTER_APPROVAL ile onaylanınca yayına girer; o andan sonra işaret dokümanla uyumludur.

### 2.9 Ekran görüntüleri (12 dil)
- [x] **Yapıldı (15 Ekim 2026):** bütün App Store dilleri için iPhone, iPad ve Mac görüntüleri (toplam 364) ve en-US iPhone uygulama önizlemesi yüklendi.
- [ ] **Ne:** Görüntüler eksik. `docs/marketing/app-store/` içinde yalnızca `en` ve `tr` var; ikisinde de iPhone 9, iPad 9, Mac 8 dosya var. Diğer on dil yok.
  - **Neden:** `docs/RELEASE-CHECKLIST.md` §11 her dil için iPhone 10, iPad 10, Mac 8 diyor. `docs/HANDOFF-PROMPT.md` adım 8: Mac yakalamaları henüz yapılmadı.
  - **Nerede:** Mac; `scripts/marketing-images.py` (başlıktaki sahne listesi); `docs/marketing/screenshot-captions.json`; çıktı `docs/marketing/app-store/<dil>/`.
  - **Sıra:** 1) Mac'te iPhone 17 Pro Max ve iPad Pro 13 inç M5 simülatörlerinde ile Mac penceresinde (`-GLWindowSize 1600x1000`, `screencapture -x -o -l <CGWindowID>`) yakalamaları al. Dil için `-AppleLanguages "(tr)" -AppleLocale tr`; örnek fotoğraflar için `-GLSamplePhotos docs/marketing/samples`. 2) `python3 scripts/marketing-images.py <yakalamalar>` çalıştır. 3) Her görüntüye bak: kredi sayısı olmamalı. 4) `cd scripts/asc && python3 asc_screenshots.py ../..` ile yükle.

### 2.10 Mac derleme ve pencere kontrolleri
- [x] **Kısmen (15 Ekim 2026):** Mac derlemesi yüklendi ve Mac ekran görüntüleri 12 dilde alındı. Kalan: üç pencere boyutunda göz kontrolü (isteğe bağlı).
- [ ] **Ne:** Derlemeleri al ve Mac penceresini 900×640, 1600×1000 ve yaklaşık 2200×1400 UIKit noktasında yakala.
  - **Neden:** `docs/HANDOFF-PROMPT.md` adım 5 ve "Unfinished branches" 2 (Mac yakalama); `AGENTS.md` §3. En küçük pencere 900×640 (`docs/RELEASE-CHECKLIST.md` §10).
  - **Nerede:** Xcode, Mac.
  - **Sıra:** 1) Debug simülatör derlemesi. 2) `xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`. 3) `xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO`. Hataları ve yeni uyarıları ajana bildir. 4) Üç pencere boyutunda yakalama al; sorun varsa `docs/RELEASE-CHECKLIST.md` §13 şablonunu kullan.

### 2.11 Büyük metin taraması
- [ ] **Ne:** iPhone 17e'de en büyük metin boyutunda İngilizce, Almanca ve Rusça ile ekranları gez.
  - **Neden:** `docs/HANDOFF-PROMPT.md` adım 5 ("Large-text survey").
  - **Nerede:** iPhone 17e; iOS'un metin boyutu ayarı (Erişilebilirlik > Görüntüleme ve Metin Boyutu).
  - **Sıra:** 1) Cihaz dilini sırayla EN, DE, RU yap. 2) En büyük metin boyutunu seç. 3) Explore, Create, Edit, My Works, paywall ve Settings'te kesilen ya da taşan metni not et; ajana ver.

### 2.12 Cihazda testler: sandbox, Ask to Buy, ödüllü reklam, Apple ile giriş
- **Durum (15 Ekim 2026):** 1.0 gönderildi, bu yüzden test artık isteğe bağlı; TestFlight iç grubu "Aybuke Team" hazır. Apple ile giriş açık olduğu için cihaz testi giriş, kredi birleştirme ve token iptalli silmeyi de kapsar (`docs/RELEASE-CHECKLIST.md` §5 ve §9.6).
- [ ] **Ne:** Üç test yap: sandbox satın alma; Ask to Buy (simülatörde); AdMob test cihazında ödüllü reklam.
  - **Neden:** `docs/RELEASE-CHECKLIST.md` §1.3–§4 (sandbox); §4.9 (Ask to Buy TestFlight'ta denenemez); `docs/HANDOFF-PROMPT.md` son madde.
  - **Nerede:** App Store Connect > Users and Access > Sandbox > Test Accounts; AdMob (test cihazı); Mac'te Xcode (`ios/StoreKit/Products.storekit`).
  - **Sıra:** 1) Türkiye ve ABD mağazası için iki sandbox hesabı oluştur. 2) `docs/RELEASE-CHECKLIST.md` §1.2–1.4 ve §4.1–4.6'yı uygula. 3) Ask to Buy: Xcode'da `Products.storekit` dosyasını aç, Editor > Enable Ask to Buy; testten sonra kapat ve dosyayı açık haliyle commit'leme. 4) AdMob'da cihazı test cihazı olarak kaydet. Ödüllü reklamı izle; kredi yalnızca AdMob'un geri çağrısından sonra gelir (Supabase > Edge Functions > Logs'ta `ad-reward` kaydına bak). 5) TestFlight derlemesinde yeni kurulumda 2 ücretsiz kredi görünmeli, Magic Edit gerçek sonuç vermeli ve "Preview build" bandı olmamalı (`docs/SUPABASE-TODO.md` §8).

### 2.13 Gönderme kararı
- [x] **Gönderildi (15 Ekim 2026):** iOS ve macOS 1.0 incelemede (WAITING_FOR_REVIEW).
- [ ] **Ne:** Her şey hazır olduğunda sahibin açık onayı olmadan gönderme yapılmaz.
  - **Neden:** `AGENTS.md` §6 (3. madde): "Submit for Review" için sahibin onayı gerekir. `docs/SUPABASE-TODO.md` başlığına göre Supabase adımları bitmeden uygulama incelemeye gönderilmez. `docs/RELEASE-CHECKLIST.md` §14.
  - **Nerede:** App Store Connect > iOS 1.0 ve macOS 1.0 sürüm sayfaları.
  - **Sıra:** 1) `docs/RELEASE-CHECKLIST.md` §1.1 ve §11 maddelerini işaretle. 2) Backend canlı ve derleme demo modunda değil (§1.1). 3) Ajan "Her şey hazır. Gönderelim mi?" diye kısa bir özetle sorar; açık "evet" gelirse gönderilir.

### 2.14 App Store Server Notifications V2: RevenueCat yönlendirme adresi
- [x] **Yapıldı (15 Ekim 2026):** adres RevenueCat'e girildi; RevenueCat projesi ve uygulaması artık "Aybuke" adını taşıyor (yol: RevenueCat › Aybuke projesi › Apps › Aybuke (App Store)). App Store Connect'teki adresler RevenueCat'i göstermeye devam ediyor.
- [ ] **Ne:** İade ve iptal bildirimlerinin Supabase'e de gelmesi için adresi RevenueCat'e gir. App Store Connect'teki adresleri değiştirme.
  - **Neden:** Uç nokta yazıldı (`backend/supabase/functions/app-store-notifications`). İade ya da iptal edilen Pro abonelik hemen kapanır; iade edilen kredi paketi geri alınır (bakiye sıfırın altına inmez). App Store Connect her ortam için tek adres kabul eder ve Production ile Sandbox adresleri şu an RevenueCat'i gösteriyor; öyle kalmalı. RevenueCat her imzalı bildirimi değiştirmeden yönlendirme adresine iletir, fonksiyon Apple'ın imzasını yine kendisi denetler (`backend/README.md`, "Setup" 5). Bir ajanın bu ayarı yapma denemesi engellendi; bu adımı sahip yapar. Adres girilmezse iade edilen Pro, süresi dolana kadar açık kalır.
  - **Nerede:** RevenueCat › Aybuke projesi › Apps › Aybuke (App Store) › "Apple Server Notification Forwarding URL". App Store Connect › Aybuke › App Information › App Store Server Notifications yalnızca kontrol edilir.
  - **Sıra:** 1) Önce 1.4 (1.10 dahil) ve 1.6 (`app-store-notifications` yayımlandı). 2) RevenueCat'te Apple Server Notification Forwarding URL: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/app-store-notifications`; kaydet. 3) App Store Connect'te Production ve Sandbox adreslerinin hâlâ RevenueCat'i gösterdiğini kontrol et; değiştirme. 4) Bir Sandbox satın alması yap (ya da App Store Connect'ten test bildirimi gönder; RevenueCat iletirse o da gelir); Supabase > Edge Functions > Logs'ta `app-store-notifications` 200 görünmeli. 5) `APPLE_APP_ID` secret'ı ayarlı olmalı (1.5), yoksa üretim bildirimleri reddedilir.

## 3) Reklam (AdMob ve AdSense)

### 3.1 Geçiş reklamı birimi
- [x] **Yapıldı (15 Ekim 2026):** "After save interstitial" geçiş birimi oluşturuldu: `ca-app-pub-2292230772061554/6797438012`, sıklık sınırı kullanıcı başına günde 3. Kimlik `ios/App/Resources/AppConfig.json` › `ads.interstitialUnitID` alanına yazıldı. Böylece sahibin 1.0 kararı (kaydettikten sonra ara sıra geçiş reklamı) uygulanmış oldu.
  - **Neden:** Birim kimliği boşken geçiş reklamı kapalıydı (`docs/HANDOFF-PROMPT.md` adım 7). Uygulamada zaten en çok 3/gün sınırı var (`AGENTS.md`, "Ads"); AdMob sınırı ek güvence.
  - **Nerede:** AdMob > Aybuke uygulaması > Ad units.
  - **Kalan:** Kimliği içeren Release derlemesinin yüklenmesi (2.2). DEBUG derlemeleri her zaman Google'ın test birimlerini kullanır.

### 3.2 Ödüllü birimde sunucu doğrulaması
- [x] **Yapıldı (15 Ekim 2026):** Ödüllü birimin sunucu doğrulaması (SSV) ayarlandı: geri çağrı adresi Verify URL ile doğrulandı ve kaydedildi. Aşağıdaki adımlar kayıt ve gerekirse yeniden kurulum içindir.
  - **Neden:** `backend/README.md`, "Rewarded ads" ve kurulum dokümanı §5. Önkoşullar: 1.5 (gizli değer) ve 1.6 (`ad-reward` yayında). Gizli değer yoksa doğrulama 503 döner.
  - **Nerede:** AdMob > ödüllü birim (`ca-app-pub-2292230772061554/1406702504`, ödül miktarı 1, öğe `credit`) > Server-side verification.
  - **Sıra:** 1) Adres: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` (sorgu dizesi yok). 2) Verify URL. Test çağrısı token taşımadığı için 200 döner ve kredi vermez. 3) Hata alınırsa Supabase Logs'a bak; önce 1.5 ve 1.6'yı kontrol et.

### 3.3 Hassas kategoriler ve GDPR mesajı
- [x] **Hassas kategoriler engellendi (15 Ekim 2026):** standart 11 hassas kategorinin tamamı ve kısıtlı kategoriler. Engelleme hesap düzeyindedir, bu yüzden sahibin Baby Bloom uygulamasını da etkiler; Baby Bloom için uygun olup olmadığını kontrol et.
- [x] **GDPR mesajı yayımlandı (15 Ekim 2026):** "Aybuke GDPR": yalnızca Aybuke uygulaması, gizlilik politikası adresi, her ülkede "Do not consent" düğmesi, 9 ek dil. AEA, Birleşik Krallık ve İsviçre'deki yetişkinler reklam istediklerinde formu görür.
  - **Neden:** `docs/marketing/app-store-connect-setup.md`, "Ads (AdMob)" bölümü. Uygulama genç ve yaşı bilinmeyen kullanıcılar için G, yetişkinler için PG isteği gönderir (`AGENTS.md`). Google'ın formu yalnızca AEA, Birleşik Krallık ve İsviçre'deki yetişkinlere, reklam istediklerinde açılır.
  - **Nerede:** AdMob > Privacy & messaging > European regulations > "Aybuke GDPR" > Publish anahtarı. Hassas kategoriler: AdMob > Blocking controls > Sensitive categories.
  - **Kalan:** ABD eyaletleri mesajı isteğe bağlı; kararını ver.

### 3.4 AdMob uygulama adı
- [ ] **Ne:** AdMob'daki uygulama adını "Aybuke" yap.
  - **Neden:** `docs/HANDOFF-PROMPT.md` adım 4 ("AdMob's app name (owner's browser)"). Uygulama kimliği `ca-app-pub-2292230772061554~5236020895` değişmez.
  - **Nerede:** AdMob > Apps > uygulama ayarları.
  - **Sıra:** Mevcut adı kontrol et; eski kod adı (Glowlit) kalmışsa değiştir.

### 3.5 app-ads.txt
- [x] **Yapıldı (15 Ekim 2026):** `https://aybuke.org/app-ads.txt` 200 döndürüyor ve AdMob satırını içeriyor.
- [ ] **Ne:** `https://aybuke.org/app-ads.txt` adresinin AdMob satırını döndürdüğünü tarayıcıdan doğrula.
  - **Neden:** AdMob, alan adının kökünde arar. Satır: `google.com, pub-2292230772061554, DIRECT, f08c47fec0942fa0` (`web/app-ads.txt`; web sitesi deposunda `public/app-ads.txt`). Bu ortamdan açılamadı.
  - **Nerede:** Tarayıcı; gerekirse Vercel dağıtımı.
  - **Sıra:** 1) Adresi aç ve satırı karşılaştır. 2) Açılmıyorsa ya da satır farklıysa Vercel dağıtımını kontrol et ve ajana bildir.

### 3.6 AdSense ödeme hesabı
- [ ] **Ne:** AdSense'te "işlem gerekli" durumunu kapat.
  - **Neden:** `docs/HANDOFF-PROMPT.md` ("Other services" ve "Owner-only items"). Kimlik, adres ve vergi bilgileri gerekir; kodla yapılacak bir şey yok.
  - **Nerede:** AdSense > ödeme ayarları.
  - **Sıra:** 1) Ekranda istenen eksik adımı oku. 2) Kimlik, adres ve vergi bilgilerini gir. 3) Onay bekleniyorsa not al.

### 3.7 AdMob uygulamasını mağaza kaydına bağla (onaydan sonra)
- [ ] **Ne:** Aybuke App Store'da yayına girince AdMob'daki iOS uygulamasını mağaza kaydına (App Store kimliği `6822716008`) bağla. Ana oturum yayını izliyor ve zamanı gelince hatırlatır.
  - **Neden:** AdMob app-ads.txt dosyasını mağaza kaydındaki geliştirici web sitesinden (aybuke.org) bulur; mağazaya bağlanmamış uygulamada reklam sunumu sınırlı kalabilir. Uygulama yayında olmadan bağlanamaz.
  - **Nerede:** AdMob > Apps > Aybuke > App settings (menü adları konsolun güncel arayüzüne göre değişebilir).
  - **Sıra:** 1) Uygulama App Store'da görünür olsun. 2) AdMob'da uygulamayı mağaza kaydıyla bağla. 3) app-ads.txt durumunun doğrulandığını kontrol et (birkaç gün sürebilir).

## 4) Web ve arama

### 4.1 Search Console site haritası
- [x] **Yapıldı (15 Ekim 2026):** site haritası yeniden gönderildi ve okundu (107 sayfa).
- [ ] **Ne:** aybuke.org için site haritasını yeniden gönder.
  - **Neden:** `docs/HANDOFF-PROMPT.md`, "Unfinished branches" 3 (site yayında; ardından Search Console ve IndexNow).
  - **Nerede:** Google Search Console > aybuke.org mülkü > Sitemaps.
  - **Sıra:** 1) Site haritası adresini web sitesi deposundan (`RiosenBeq/aybuke`) doğrula. 2) Yeniden gönder. 3) Durumun "Başarılı" olduğunu kontrol et.

### 4.2 IndexNow
- [x] **Yapıldı (15 Ekim 2026):** 107 adres gönderildi, HTTP 200.
- [ ] **Ne:** Sayfa adreslerini IndexNow'a bildir.
  - **Neden:** `docs/HANDOFF-PROMPT.md`, "Unfinished branches" 3. Anahtar dosyası web sitesi deposunun `public/` klasöründe; bu depoda yok.
  - **Nerede:** `RiosenBeq/aybuke` deposu `public/`; IndexNow.
  - **Sıra:** 1) Anahtar dosyasının aybuke.org kökünden açıldığını kontrol et. 2) Bildirimi sen ya da ajan gönderir; yanıtı not et.

## 5) Karar bekleyen konular (önerilerle)

### 5.1 Deneme kredileri
- [ ] **Karar:** Yıllık planın 7 günlük denemesindeki 20 kredi kullanılmadan kalırsa ilk ücretli aya eklensin mi (20 + 80, en çok 160), yoksa dönüşümde sıfırlansın mı?
  - **Neden:** `backend/README.md`, "Credit rules" (`trial_credits` = 20); `AGENTS.md`, "Money". Mevcut tasarım ekleme yönünde.
  - **Öneri:** Mevcut davranışı koru; paywall ve hukuki metinler bunu açıkça söylesin. Böylece kullanıcı kredisini kaybetmez.

### 5.2 App Store Server Notifications V2
- [x] **Karar verildi ve yapıldı:** uç nokta lansmandan önce kuruldu (`functions/app-store-notifications`, migrasyon `20261025000000`). Kalan sahip işi: yayımlama (1.6) ve adresi RevenueCat'in yönlendirme alanına girmek (2.14).

### 5.3 Paylaşılan IP adresleri
- [ ] **Karar:** Doğrulanmamış bir adresten üç strike, o adresteki herkesi cool-down'a sokuyor. Adres anahtarları için daha yüksek bir eşik uygulansın mı?
  - **Neden:** `backend/README.md`, "Abuse runbook": bir adres birçok kişiye hizmet edebilir (okul, mobil operatör). Eşik `credit_policy()` içinde.
  - **Öneri:** Adres anahtarları için eşiği yükselt. Değişiklik yeni bir migrasyonla yapılır; ajan yazar.

### 5.4 MERSİS satırı
- [ ] **Karar:** Gizlilik ve kullanım metinlerindeki "Ticaret sicili / MERSİS numarası: Yok (bireysel geliştirici)" satırı kalsın mı?
  - **Neden:** `legal/config.json` (`COMPANY_REGISTRY`). `docs/HANDOFF-PROMPT.md`, "Unfinished branches" 3: web sitesinde MERSİS bilgisi olmamalı diyor; senkron metinler ise satırı yazıyor.
  - **Öneri:** "Yok" bilgisi doğruysa tut. Kaldırılacaksa `legal/config.json` içinde `COMPANY_REGISTRY` alanını boş bırak (boş değerli satır üretilmez), sonra `python3 scripts/build-legal.py` çalıştır.

### 5.5 Destek ve iletişim e-postası
- [ ] **Karar:** Uygulama, hukuk metinleri, App Review ve web sitesinde `hello@buaze.com` kullanılıyor. Bu adres kalsın mı, yoksa aybuke.org alan adında bir adres mi kullanılsın?
  - **Neden:** `legal/config.json` (`CONTACT_EMAIL`, `PRIVACY_EMAIL`); `ios/App/Resources/AppConfig.json` ve `ios/App/App/AppConfig.swift` (`supportEmail`); `web/index.html`; `docs/RELEASE-CHECKLIST.md` §11.
  - **Öneri:** Lansmandan önce karar ver. Değişirse hepsi tek seferde güncellenir; `check-release-config.py --online` yeni alan adının posta kaydını (MX) da kontrol eder.

### 5.6 Apple ile giriş
- [x] **Karar verildi (15 Ekim 2026):** Apple ile giriş 1.0'da açık (`signInWithApple: true`, `AppConfig.json`). Anahtar 15 Ekim 2026'da oluşturuldu; Key ID `36Q32XU57F` gizli değildir. `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` Supabase Secrets'ta; Apple'a karşı denendi (sahte kod `invalid_grant` döndü, yani istemci gizli anahtarı geçerli).
  - **Neden:** Krediler başka cihaza taşınabilsin; Pro her zaman Apple Hesabı'nın satın alımlarından gelir. Hesap silme Apple token'ını iptal eder; sunucuda token yoksa uygulama silmeden önce Apple ile bir kez daha onay ister (`account` fonksiyonu, `AGENTS.md` "Accounts").
  - **Yapıldı (15 Ekim 2026):** App Privacy yayımlandı (2.7); `20261027000000_account_tables_private.sql` dahil `20261029000002`'ye kadar migrasyonlar uygulandı ve `account` yayında (1.4, 1.6).
  - **Kalan (sahip):** cihazda giriş, kredi birleştirme ve token iptalli silme testi (2.12; `docs/RELEASE-CHECKLIST.md` §5, §9.6). Test sırasında giriş başarısız olursa Supabase > Authentication > Providers > Apple'ın açık olduğuna ve Client IDs'de `app.glowlit.ios` bulunduğuna bak.

### 5.7 RevenueCat v2 anahtarı (isteğe bağlı)
- [ ] **Karar:** `REVENUECAT_SECRET_KEY` ve `REVENUECAT_PROJECT_ID=3e7e4f4a` eklensin mi?
  - **Neden:** `backend/.env.example`; `backend/README.md`, "Accounts" 4. madde. Anahtar yoksa hesap silme, RevenueCat kaydını `pending_revenuecat_deletions` tablosunda bekletir.
  - **Öneri:** Lansman için şart değil. Eklenirse hesap silme anında RevenueCat'e gider. Anahtar türü: RevenueCat > Project settings > API keys; yalnızca `customer_information:customers:read_write` izinli v2 gizli anahtar.

### 5.8 Bağımsız güvenlik denetimi: Claude (fal.ai yerine)
- [x] **Karar verildi (15 Ekim 2026):** Bağımsız denetim Claude'dur (Anthropic, `claude-haiku-5-5`); `FAL_KEY` ve `XAI_SAFETY_MODEL` eklenmez.
  - **Neden:** Lansmandan önce bağımsız bir denetim gerekiyordu (`docs/AI-TODO.md` §1.5; yol haritası `server-moderation-stack`). Claude görsel üretemez ya da düzenleyemez; bu yüzden görseller xAI'de (Grok Imagine) kalır, Claude yalnızca denetler: düzenlenecek fotoğrafı görsel modele gitmeden önce ve her sonucu, xAI'nin kendi denetiminin üstüne (`_shared/safety.ts`, `_shared/moderation.ts`). Denetim fail-closed: hata, zaman aşımı, ret ya da beklenmeyen yanıt işi engeller ve krediyi iade eder. `ANTHROPIC_API_KEY` ayarlıyken `XAI_SAFETY_MODEL` okunmaz.
  - **Yapılanlar:** Onay ekranı artık Supabase, xAI (Grok Imagine) ve Anthropic (Claude) listeler (`aiProcessors`, `consentVersion` 2; daha önce onay verenlere ekran bir kez daha açılır). Gizlilik politikası (EN, TR) ve KVKK aydınlatma metni Anthropic, PBC'yi (ABD) alt işleyen olarak yazar: API girdi ve çıktılarını 30 gün içinde siler, kullanım politikası ihlali olarak işaretlenen içeriği 2 yıla kadar saklayabilir, varsayılan olarak model eğitiminde kullanmaz. fal.ai yalnızca kullanılmayan bir alternatif olarak anılır.
  - **Yapıldı (15 Ekim 2026):** canlıda log satırı ve gerçek bir Magic Edit'te iki denetim (1.11); aybuke.org'daki hukuk sayfaları Anthropic'i anıyor.
  - **Kalan (sahip):** 1.11 (bakiye ve harcama limiti); Anthropic'in veri işleme sözleşmesi (DPA) ve ABD'ye aktarım dayanağı avukatla (6.1, 6.3).

## 6) Hukuk

### 6.1 Avukat incelemesi
- [ ] **Ne:** `legal/` altındaki metinleri (İngilizce, Türkçe, KVKK) bir avukat incelesin.
  - **Neden:** `docs/HANDOFF-PROMPT.md`, "Owner-only items" ("A lawyer's review"). Konular: xAI Zero Data Retention iddiası (1.3); Anthropic'in saklama süreleri (30 gün; işaretlenen içerik 2 yıla kadar), işaretlediği içerik için bağımsız veri sorumlusu rolü ve DPA'sı (5.8, 6.3); kurulum anahtarı hash'i (2.7); "Atanmış temsilci yok" satırları (GDPR md. 27 ve UK GDPR); 13–15 yaş için vasi adımı; MERSİS satırı (5.4).
  - **Nerede:** Kaynak `legal/en` ve `legal/tr`. Kopyalar `docs/legal`, `ios/App/Resources/Legal` ve `web/legal` içinde.
  - **Sıra:** 1) Metinleri avukata gönder. 2) Değişiklik çıkarsa `legal/` içinde düzelt; `python3 scripts/build-legal.py` ile kopyaları yenile.

### 6.2 KVKK başvuru adresi (isteğe bağlı)
- [ ] **Karar:** KVKK'daki yazılı başvurular için posta ya da KEP adresi eklensin mi?
  - **Neden:** `legal/config.json` içinde `KEP_ADDRESS` boş (boş değerli satır gizlenir). `docs/HANDOFF-PROMPT.md`: ev adresi DSA gereği AB mağazalarında zaten görünür; sahibin onayı olmadan yayımlanmaz.
  - **Öneri:** Avukatın görüşüne göre karar ver. Ev adresi yerine ayrı bir adres kullanılabiliyorsa onu tercih et.

### 6.3 Sözleşmeler ve yurt dışı aktarım dayanağı (önce Anthropic ve xAI)
- [ ] **Ne:** Anthropic ve xAI için: 1) veri işleme sözleşmesini (DPA) imzala; 2) ABD'ye aktarım dayanağını belirle (Data Privacy Framework sertifikası ya da Standart Sözleşme Hükümleri, SCC, Birleşik Krallık eki ile); 3) KVKK Kurulu'nun standart sözleşmesini imzala ve imzadan sonra 5 iş günü içinde Kişisel Verileri Koruma Kurumu'na bildir; 4) metinleri avukata onaylat. Google (reklam) ve diğer işleyiciler için dayanağı da avukat belirlesin.
  - **Neden:** Gizlilik politikası (§13) ve KVKK aydınlatma metni (§5), aktarımların standart sözleşmelere dayandığını ve imzadan sonra 5 iş günü içinde bildirildiğini yazıyor; Anthropic ve xAI ile bunlar henüz imzalanmamış olabilir. İmzalanana kadar bu ifade karşılıksızdır. Metinlerdeki dayanak ifadesi olduğu gibi bırakıldı ve yeni bir güvence yazılmadı: bu iş bitince metin doğru olur. Ayrıntı: `docs/05-compliance.md` (GDPR / privacy, "Contracts and transfers"); `docs/HANDOFF-PROMPT.md`, "Owner-only items".
  - **Ayrıca:** Anthropic'in reşit olmayanların kullandığı ürünlere ilişkin yönergesi: arka uçta çalışan ve kullanıcıyla hiç konuşmayan bir sınıflandırıcıya (fotoğraf ve sonuç denetimi) uygulanıp uygulanmadığını avukatla ve Anthropic'le netleştir.
  - **Nerede:** Anthropic ve xAI'nin ticari koşulları ve veri işleme ekleri (gerekirse destek ekipleri); KVKK standart sözleşme metni ve bildirim: kvkk.gov.tr. Kaynak metinler: `legal/en/privacy-policy.md`, `legal/tr/gizlilik-politikasi.md`, `legal/tr/kvkk-aydinlatma-metni.md`.
  - **Sıra:** 1) DPA'ları imzala (Anthropic, xAI). 2) Her biri için DPF sertifikasını kontrol et; yoksa SCC. 3) KVKK standart sözleşmesini imzala; 5 iş günü içinde Kurum'a bildir. 4) Avukat metinleri imzalananlarla karşılaştırsın; değişiklik gerekirse `legal/` içinde düzelt ve `python3 scripts/build-legal.py` çalıştır.

## 7) Sahibin kendi hesaplarında yapacakları (özet)

| Hesap | Açık madde (yapılanlar yukarıda işaretli) |
|---|---|
| xAI | 1.1 (harcama limiti, bakiye), 1.2 (anahtar döndürme), 6.3 (DPA) |
| Anthropic (Claude Console) | 1.11 (bakiye, harcama limiti), 6.3 (DPA) |
| Supabase (proje `efapupjvidyqhqdevmcu`) | 1.10 (eski projeye dokunma) |
| AdMob | 2.12 (test cihazı, isteğe bağlı), 3.4, 3.7 (onaydan sonra mağaza bağlantısı) |
| AdSense | 3.6 |
| App Store Connect ve TestFlight | 2.8 (Age Assurance notu), 2.12 (sandbox, isteğe bağlı) |
| RevenueCat | 5.7 (isteğe bağlı) |
| Mac (Xcode, simülatör) | 2.10 (pencere boyutları, isteğe bağlı), 2.11, 2.12 (Ask to Buy) |
| Avukat | 6.1, 6.2, 6.3 |

## Şu an tamamlananlar

- **15 Ekim 2026, akşam:** iOS 1.0 (20261015.1225) ile macOS 1.0 (20261015.1233) App Review'da, AFTER_APPROVAL; abonelik grubu, iki abonelik ve iki paket iOS sürümüyle gönderildi. Backend migrasyonları `20261029000002`'ye kadar, yedi fonksiyon, sahip e-postaları ve günlük özet canlı; Apple ile giriş açık; xAI Zero Data Retention açık; App Privacy, ekran görüntüleri ve uygulama önizlemesi yayında; RevenueCat yönlendirme adresi girildi; AdMob GDPR mesajı yayında.
- PR #1 (`pink-girls-redesign`) `main`'de; merge commit `d007a8b`. CI `d2cbbf3`'te yeşil: iOS derlemesi (iPhone ve Mac Catalyst), backend (Deno ve PostgreSQL), AppCore testleri (Linux), hukuk metinlerinin senkronu ve metin kontrolü.
- Kredi ve kötüye kullanım dalı birleşti. Doğrulama: yerelde Deno fmt, lint ve check ile 50 test geçti; `backend/scripts/test-db.sh` PostgreSQL 16'da geçti.
- Mac dalı birleşti. Doğrulama: Mac Catalyst derlemesi CI'da; Mac ekran görüntüleri 15 Ekim 2026'da alındı (2.10).
- Web sitesi (`RiosenBeq/aybuke`) birleşti; Vercel üretime yayınlıyor; hukuk metinleri uygulamadan senkron. Doğrulama: 15 Ekim 2026'da bütün adresler 200 (2.1).
- Yeniden adlandırma (`6f2959d`, Glowlit → Aybuke) ve `31f8817` (ad-reward Deno testleri CI'da). CI, `6f2959d` için `workflow_dispatch` ile çalıştırıldı ve tamamen yeşil (iOS derlemesi iPhone ve Mac Catalyst için dahil). AppCore testleri yeniden adlandırmadan sonra 319 geçti (yerel Linux Swift 6.1).
- App Store Server Notifications V2 uç noktası, iade edilen paketlerin geri alınması ve SQL düzeltmeleri (tekrar sayımı, iptal edilen işe uyarı yok, bakiyede adres beklemesi) yazıldı; Deno ve PostgreSQL testleri yerelde geçti. Uygulama: fotoğraf kontrolü çalışamadığında ayrı ve doğru bir mesaj; Mac'te ⌘W editörü ve Retro Cam'i kapatır; şablon kartlarında sağ tık menüsü; Mac'te küçük kalan yazılar büyütüldü.
- `scripts/check-credit-policy.py`: sunucu, `AppConfig.json` ve AppCore'daki kredi sayıları ayrışırsa CI kırmızı olur.
- Bağımsız güvenlik denetimi Claude ile (15 Ekim 2026): `_shared/safety.ts` (Anthropic yolu, sahte yanıtlarla testli), onay ekranında Anthropic (`consentVersion` 2) ve hukuk metinlerinde Anthropic, PBC. Canlıda (15 Ekim 2026; 1.6, 1.11).
- AdMob (15 Ekim 2026): geçiş birimi `ca-app-pub-2292230772061554/6797438012` (günde 3) `ads.interstitialUnitID`'de; ödüllü birimin SSV adresi doğrulandı ve kaydedildi; 11 standart hassas kategori ve kısıtlı kategoriler engellendi (hesap düzeyinde); "Aybuke GDPR" mesajı yayında (3.3).
- Yerelde geçen kontroller: `build-legal.py --check`, `export-core-strings.py --check`, `check-honest-copy.py`, `check-release-config.py --report`; `--online` 15 Ekim 2026'da geçti (2.1).

## Belgelerde kalan düzeltmeler

- `docs/marketing/app-store-connect-setup.md` §2: Age Assurance notu 2.8'e göre güncellenecek; kurulum anahtarı hash'inin App Privacy beyanı avukat görüşüne (6.1) göre gözden geçirilecek.
- `docs/research/2026-10-ux-audit.md` eski '3 AI credits' ifadesini tarihsel kayıt olarak taşıyor; değiştirilmez.
