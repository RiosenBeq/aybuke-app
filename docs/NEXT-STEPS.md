# Aybuke: kalan işler ve devam promptları

> **Türkçe özet:** Aybuke 1.0, 15 Ekim 2026'da iOS ve macOS için App Review'a gönderildi (yayın türü AFTER_APPROVAL: onaylanınca kendiliğinden yayına girer). Ajanın yapabileceği lansman işleri bitti. Kalanlar sahibin hesaplarında: xAI ve Anthropic harcama limitleri ve bakiye, xAI anahtarının döndürülmesi, Anthropic ve xAI DPA'ları ile KVKK adımları (avukat), onaydan sonra AdMob uygulamasının mağaza kaydına bağlanması ve isteğe bağlı TestFlight cihaz testi. Güncel liste: [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md). Aşağıdaki §3–§4 geçmiş kayıttır; çelişki olursa `SAHIP-YAPILACAKLAR.md` ve [`AGENTS.md`](../AGENTS.md) §6 geçerlidir.

Son güncelleme: 15 Ekim 2026 akşamı. **Durum:** iOS 1.0 (derleme 20261015.1225; abonelik grubu, iki abonelik ve iki paketle) ve macOS 1.0 (20261015.1233) WAITING_FOR_REVIEW. Derlemeler manuel imzalama ve altool ile yüklendi. Backend canlı: migrasyonlar `20261029000002`'ye kadar, yedi fonksiyon (`owner-digest` dahil), gizli değerler, üç cron işi; günlük sigortalar 60 ücretsiz / 10 doğrulanmamış / 400 toplam iş; sahip uyarı e-postaları ve günlük özet çalışıyor. Apple ile giriş 1.0'da açık (anahtar `36Q32XU57F`). xAI Zero Data Retention açık. App Privacy (10 veri türü), 364 ekran görüntüsü ve en-US iPhone uygulama önizlemesi yayında. RevenueCat (proje ve uygulama adı Aybuke) App Store bildirimlerini `app-store-notifications`'a iletiyor; Supabase organizasyonu ve projesi de Aybuke adını aldı. AdMob GDPR mesajı yayında. TestFlight iç grubu "Aybuke Team" var. Ajan işlerinin listesi [`AI-TODO.md`](AI-TODO.md) dosyasındadır. Başlamadan önce [`AGENTS.md`](../AGENTS.md) §6'yı oku.

## 1. Nerede, hangi hesapta, hangi klasörde

- **Yerel klasör:** sahibin Mac'indeki depo kökü (yol bu dosyada yazılmaz). Komutlarda `<depo kökü>` yazan yere kendi klasörünü koy.
- **GitHub deposu:** https://github.com/RiosenBeq/aybuke-app
- **Ana dal:** `main`, CI yeşil olunca `pink-girls-redesign`'i ileri sarar (15 Ekim 2026'da `4b6c9fa`). Çalışma `pink-girls-redesign`'de sürer.
- **Bekleyen dallar (GitHub'da):**
  - `worktree-agent-a1f71de31e33eae9b` (performans) ve `worktree-agent-a6acce03ae5d2fa55` (kredi ve kötüye kullanım): ikisi de `main`'de.
  - `worktree-agent-a9b1c4b8c9e51e4d3`: `main`'de.
  - `worktree-agent-a4a75767d883b6d64` (düzen): düzeltme commit'leri `pink-girls-redesign`'de, ama tek WIP commit'i `db0a6bc` ("onboarding layout change left unfinished") değil. Bkz. 4.1, adım 4.
  - `origin/screenshots`: `pink-girls-redesign`'de değil. `.github/workflows/screenshots.yml` bu dala yazar.
- **Web sitesi:** https://aybuke.org (Vercel). Kaynağı `RiosenBeq/aybuke` deposunun `main` dalı (AGENTS.md §6). Bu depodaki `web/` ve GitHub Pages iş akışı (`.github/workflows/website.yml`) eski kopya. Yasal sayfalar: `/legal/en/privacy-policy`, `/legal/en/terms-of-use`, `/legal/tr/gizlilik-politikasi`.
  - Doğrulanamadı: aybuke.org ve bu sayfalar bu ortamdan açılamadı (bağlantı kurulamadı).
- **Backend:** Supabase projesi `efapupjvidyqhqdevmcu` (Frankfurt, Free plan; organizasyon ve proje adı Aybuke). 15 Ekim 2026'dan beri canlı.
- **App Store Connect:** uygulama kimliği `6822716008` (`AppConfig.json` › `appStoreID`). Paket kimliği `app.glowlit.ios`, widget `app.glowlit.ios.widgets`, takım `CBTKNY3LFC`.
  - Abonelik grubu "Aybuke Pro": `app.glowlit.pro.yearly` ($39.99) ve `app.glowlit.pro.monthly` ($5.99, ilk ay $1.99).
  - Kredi paketleri: `app.glowlit.credits.30` ($2.99) ve `app.glowlit.credits.100` ($7.99).
  - Fiyatlar ve ürün kimlikleri `ios/StoreKit/Products.storekit` ile eşleşiyor.
- **AdMob:** uygulama kimliği `ca-app-pub-2292230772061554~5236020895`; ödüllü birim `ca-app-pub-2292230772061554/1406702504`. Geçiş birimi "After save interstitial" `ca-app-pub-2292230772061554/6797438012` (günde 3), 15 Ekim 2026'da oluşturuldu ve `ads.interstitialUnitID` alanına girer (SAHIP 3.1).

## 2. Hesaplar ve gizli bilgiler (repoda OLMAZ)

- **App Store Connect API anahtarı:** `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`. Yeni makinede sahibin dosyayı güvenli biçimde kopyalaması gerekir. Dosyayı asla commit etme, yazdırma veya bir yere yapıştırma. Dosya adındaki anahtar kimliği ile issuer kimliği, App Store Connect → Users and Access → Integrations sayfasındaki liste ile yüklemeden önce karşılaştırılmalı.
- **Supabase CLI:** yeni makinede `supabase login` gerekir. Fonksiyon dağıtım komutları 4.2, adım 5'te.
- **Supabase Secrets** (Edge Functions → Secrets): değerler bu dosyada ve repoda yok. 15 Ekim 2026 durumu:
  - Ayarlı: `XAI_API_KEY`, `ANTHROPIC_API_KEY`, `APPLE_APP_ID` (`6822716008`), `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID`, `ADMOB_REWARDED_AD_UNIT`, `APPLE_SIGNIN_KEY_ID` / `APPLE_SIGNIN_PRIVATE_KEY` (Apple ile giriş açık, `signInWithApple: true`), `RESEND_API_KEY`, `DIGEST_SECRET`, `OWNER_ALERT_TO`.
  - Olmamalı: `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS`. `_shared/apple.ts` yalnızca yerel projede kabul eder; barındırılan projede yok sayar ve günlüğe yazar.
  - Hiçbir fonksiyon `OUTPUT_MODERATION` okumuyor (yalnızca `_shared/moderation_test.ts` bunun yok sayıldığını test eder).
  - Eklenmez (sahip kararı, SAHIP-YAPILACAKLAR.md 5.8: bağımsız denetim Claude): `FAL_KEY`, `XAI_SAFETY_MODEL`. `ANTHROPIC_SAFETY_MODEL` boş kalabilir (varsayılan `claude-haiku-5-5`).
  - Yok (isteğe bağlı): `REVENUECAT_SECRET_KEY`. Hesap silme RevenueCat kaydını `pending_revenuecat_deletions` tablosunda bekletir; günlük özet bekleyenleri listeler.
- **xAI konsolu:** Zero Data Retention "Active" (15 Ekim 2026). Açık: aylık harcama limiti ve bakiye (SAHIP-YAPILACAKLAR.md 1.1), sohbete yapıştırılmış API anahtarının döndürülmesi (1.2).
- **Apple sahibi:** App Store Connect "Account Holder" sahibin Apple kimliğidir. Sözleşmeleri kabul etmek (Paid Apps Agreement dahil) ve gönderimi onaylamak yalnızca sahibin işidir.
- **Yerel gizli dosyalar:** `ios/Config/Secrets.xcconfig` (`.gitignore`'da, yalnızca DEBUG'da kullanılır). Repoya girmez.

## 3. Tamamlananlar (özet)

> 14–15 Ekim 2026 sabahının kaydı. Sonrası: yukarıdaki "Son güncelleme" ve [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md).

- **Ana dal ve CI:** PR #1 `main`'de (`d007a8b`). `main` için CI çalıştırması (38625838738) yeşil. Yeniden adlandırma `6f2959d` için CI çalıştırması (38626550552, elle başlatıldı) dört işte yeşil: belgelerin senkronu, AppCore testleri (Linux), backend (Deno ve PostgreSQL) ve iOS derlemesi (iOS ve Mac Catalyst adımları dahil). `31f8817` ve `28c16eb` için çalıştırma yok (bkz. 4.1, adım 1).
- **Yerelde geçen kontroller:** bu oturumda `build-legal.py --check`, `export-core-strings.py --check`, `check-honest-copy.py` ve `check-release-config.py --report` geçti. `--report` o gün yalnızca geçiş birimi boş uyarısını veriyordu (15 Ekim'de birim eklendi, uyarı kalktı). Ajanın bildirip bu dosyada yeniden çalıştırmadığı kontroller: AppCore `swift test` 319 testi geçti (yeniden adlandırmadan sonra); Deno fmt, lint, check ve 50 test geçti; `backend/scripts/test-db.sh` PostgreSQL 16'da geçti; 206 Swift dosyasının sözdizimi denetlendi. Sayılar koda karşı kontrol edildi: 319 `func test` bildirimi ve 50 `Deno.test`.
- **Uygulama yapılandırması** (`28c16eb`): `websiteURL` `https://aybuke.org`; `privacyPolicyURL` ve `termsURL` aybuke.org'daki uzantısız yasal adresler. GitHub Pages adresleri kaldırıldı. `appStoreID` ayarlı, `forceDemoMode` false, `signInWithApple` false.
- **Kredi ve kötüye kullanım** (`main`'de, canlı değil): 2 ücretsiz kredi/gün, yalnızca doğrulanmış App Store kurulumuna; Pro 80/ay ve 160 üst sınır; deneme 20 kredi; Likeness Lock 3/gün; 1500 ücretsiz iş/gün ve 8000 iş/gün devre kesiciler; 24 saat içinde 3 strike, 24 saatlik cool-down. Sayılar `public.credit_policy()` içinde (`20261020000000_credit_policy_v2.sql`).
- **Reklam** (`main`'de, canlı değil): `ad-reward` fonksiyonu, `20261019000000_ad_rewards.sql` ve `20261023000000_ad_rewards_per_install.sql` migrasyonları, ödüllü birim kimliği. `web/app-ads.txt` AdMob satırını içeriyor. Canlı site doğrulanamadı.
- **Ürün ve yasal metinler:** dört ürün kimliği ve fiyatları `Products.storekit` ile eşleşiyor. `legal/` kaynak; satıcı bilgisi bireysel geliştirici (`legal/config.json` › `COMPANY_REGISTRY`). KVKK için yazılı adres (`KEP_ADDRESS`) boş.
- **Supabase** (HANDOFF-PROMPT.md'ye göre): migrasyonlar `20261011000000`–`20261018000000` ve `20261019500000_keepalive.sql` uygulanmış; `ai-image`, `account`, `credits-redeem` ve `report` `47b5c6f` sürümünde yayında; anonim girişte IP başına 15/saat sınırı; e-posta sağlayıcısı kapalı.
  - Doğrulanamadı: orkestratörün bildirdiğine göre `20261019500000_keepalive.sql` uygulanmamış, `20261017000000` ve `20261018000000`'in durumu bilinmiyor. İki kaynak çelişiyor; SQL ile kontrol edilmeli (4.2, adım 3).
- **App Store Connect** (HANDOFF-PROMPT.md'ye göre): uygulama kaydı, iOS ve macOS platformları, 13 dilde metin, gizlilik yanıtları ve yaş derecelendirmesi girildi. Abonelikler eksik metadata, paketler gönderime hazır görünüyor.
  - Doğrulanamadı: güncel durum bu ortamdan görülemedi; sahibin ekranı esas alınır.
- **Çeviri:** 11 dil uygulama kataloglarında. 14 Ekim'de eklenen yaklaşık 360 metnin çevirisi açık (AGENTS.md §6, AI-TODO.md §1.12).

## 4. Açık işler (sırayla)

> Geçmiş kayıt: §4.1 ve §4.2'deki adımların hepsi 15 Ekim 2026'da yapıldı ya da karara bağlandı (backend canlı, iade bildirimleri yayında, derlemeler gönderildi). Güncel açık işler [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md) ve [`AI-TODO.md`](AI-TODO.md) dosyalarında.

### 4.1 Ajan adımları

Sırayla yapılır. Her adımın "Kontrol" satırı tamamlanmadan bir sonrakine geçilmez.

1. **Güncel başta CI çalıştır.** `31f8817` ve `28c16eb` için CI çalıştırması yok: `ci.yml` yalnızca `main`'e push, pull request ve elle (`workflow_dispatch`) çalışır. `pink-girls-redesign` üzerinde `workflow_dispatch` ile başlat. `31f8817` ile gelen Deno adımı (`deno test _shared/ ad-reward/`, `ci.yml` satır 42) bu çalıştırmada ilk kez koşar.
   *Kontrol:* dört iş yeşil. Sonuçları çalıştırma kimliğiyle birlikte yaz.
2. **`pink-girls-redesign`'i `main`'e al.** Yalnızca 1. adım yeşilse. Açık pull request yok (PR #1 kapalı ve birleşmiş); yeni bir PR açılır ya da sahibin onayıyla birleştirilir.
   *Kontrol:* `origin/main` başı `pink-girls-redesign` başıyla aynı ve `main`'in CI'ı yeşil. Not: `keepalive.yml` `main`'de olduğunda günlük (07:23 UTC) çalışmaya başlar. `20261019500000_keepalive.sql` canlıda yoksa `public.keepalive()` bulunamadığı için çağrı başarısız olur.
3. **Screenshots iş akışının `main`'deki başarısızlığını incele.** `d007a8b`'nin `main`'e push'unda `Screenshots` iş akışı başarısız oldu (çalıştırma 38625839047). İş akışı `ios/**` değiştiğinde `main`'e her push'ta çalışır.
   *Kontrol:* elle başlatılan çalıştırma yeşil ve hata nedeni bu dosyaya yazıldı.
   - Doğrulanamadı: hata nedeni. Günlük bu ortamdan alınamadı.
4. **Düzen dalını karara bağla.** `worktree-agent-a4a75767d883b6d64`'ün `pink-girls-redesign`'de olmayan tek commit'i `db0a6bc` (WIP). "Try it on your photo" düğmesinin kayması hâlâ var mı, bu ortamdan görülemiyor. Commit'i incele; gerekliyse birleştir, değilse dalın kapanmasını sahibine öner.
   *Kontrol:* iPhone 17e simülatöründe Onboarding İngilizce, Almanca, Rusça ve en büyük yazı boyutunda düğme kaymıyor (AI-TODO.md §2.11).
5. **Sayıları ve belgeleri koda uydur.**
   - `backend/README.md` satır 118 "20 reports a day" diyor. `credit_policy()` içinde `reports_per_day` = 10.
   - `docs/SUPABASE-TODO.md` §3 yalnızca on migrasyon listeliyor (`20261011000000`–`20261019500000`); klasörde on yedi var.
   - `docs/RELEASE-CHECKLIST.md` satır 40 hâlâ `OUTPUT_MODERATION` bekliyor.
   *Kontrol:* `grep -rn "20 reports" backend docs AGENTS.md` yalnızca AI-TODO.md'deki kontrol notunu bulur. `OUTPUT_MODERATION` yalnızca test ve geçmiş notlarda geçer.
6. **aybuke.org adreslerini doğrula.** `check-release-config.py --online` yalnızca `websiteURL` ve `websiteURL + "/legal/en/privacy-policy.html"` adreslerini 200 için kontrol eder; uygulamanın kullandığı uzantısız `privacyPolicyURL` kontrol edilmez. Sahip tarayıcıda hangi biçimin yanıt verdiğine bakmalı. Uzantısız adres açılmıyorsa `AppConfig.json` ya da betik düzeltilir.
   *Kontrol:* `python3 scripts/check-release-config.py --online` geçer.
   - Doğrulanamadı: aybuke.org, yasal sayfalar ve `app-ads.txt` bu ortamdan açılamadı.
7. **App Store Server Notifications V2 uç noktası** (lansman engeli; AI-TODO.md §1.6). Kodda bildirim uç noktası yok. Uç nokta iade ve iptali doğrulanmış bir imzayla `public.record_entitlement` (`p_revoked`, `20261024000002_entitlement_order.sql`) üzerinden işaretlemeli. Sahip URL'yi App Store Connect'e girer.
   *Kontrol:* iade ve iptal için test var; `deno test _shared/ ad-reward/` geçiyor.
8. **Üç SQL boşluğu** (AI-TODO.md §1.8). Her biri yeni migrasyon ve testle kapanır; uygulanmış dosyalar değişmez.
   - `admit_job` (`20261024000001_abuse_fixes.sql`, tanım satır 77, sayım satır ~210) bugün `retry_of` dolu tüm işleri sayıyor. İade edilen ya da zaman aşımına uğrayan Likeness Lock denemesi de günlük üç hakkı harcıyor.
   - `public.flag_job` (`20261022000000_abuse_controls.sql`, satır 435) işin durumuna bakmadan strike ekliyor; iptal edilmiş iş de strike sayılabilir.
   - `GET /ai-image` bakiyesi (`ai-image/index.ts`, `walletState`) istemci adresini geçirmiyor; adres cool-down'ları bakiyede görünmüyor.
   *Kontrol:* `backend/scripts/test-db.sh` her boşluk için yeni testle geçer.
9. **Swift testleri sessizce atlamasın; politika vektörleri eksiksiz olsun** (AI-TODO.md §1.9–1.10).
   - Beş `XCTSkip` çağrısı dört dosyada var (`CreditsTests`, `ContentPolicyTests`, `CatalogSyncTests`, `TranslationTests`). Dosya bulunamazsa testler atlanıyor; başarısız olmalılar.
   - `_shared/policy-vectors.json` içinde Yunanca sonda sigma ve CJK satır sonu vektörü yok.
   *Kontrol:* `swift test --package-path ios/Packages/AppCore` atlanan test göstermez; `scripts/export-catalog.sh` çalıştırıldıktan sonra `swift test` ve `deno test _shared/` geçer.
10. **Web kaynağı ve bağımsız çıktı denetimi taslağı** (AI-TODO.md §1.4–1.5).
    - `web/README.md` hâlâ GitHub Pages yayınını anlatıyor; tek kaynak kararı yazılmalı.
    - fal.ai `aiProcessors` listesinde yok (`AppConfig.json`: yalnızca Supabase ve xAI). `FAL_KEY` ayarlanmadan önce bu liste ve gizlilik metinleri güncellenmeli. Taslak sahibe gider; `FAL_KEY` ayarlanmaz.
    *Kontrol:* `scripts/build-legal.py --check` geçer; `moderation_test.ts` fal yolunu kapsar.
    **Yapıldı (15 Ekim 2026), fal.ai yerine Claude ile:** bağımsız denetim `_shared/safety.ts` içinde Anthropic'in Claude modeli (`ANTHROPIC_API_KEY`); onay ekranı Supabase, xAI ve Anthropic'i listeler (`consentVersion` 2), gizlilik metinleri Anthropic'i yazar. `FAL_KEY` ayarlanmaz. Ayrıntı: AI-TODO.md §1.5.
11. **Belgeleri aynı işte güncelle** (AGENTS.md §6). Bir sayı ya da rota değişirse `RELEASE-CHECKLIST.md`, `SUPABASE-TODO.md`, `marketing/app-store-connect-setup.md` ve `AGENTS.md` aynı değişiklikte düzeltilir.

Kalan kod işleri (AI-TODO.md §1.7, §1.11–1.13 ve §2) sıradadır; §2 Mac ya da cihaz gerektirir.

### 4.2 Sahip adımları (ilk beş)

Sahibin tam listesi [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md) dosyasındadır (Supabase, xAI, AdMob, AdSense, App Store Connect, Search Console, Vercel, Mac'te Xcode). Aşağıda yalnızca ilk beş adım var; sıra önemli.

1. **xAI kredisini yükle ya da aylık limiti artır** (SAHIP 1.1). Kredi bitince her AI işi başarısız oluyor ve kredi iade ediliyor (HANDOFF-PROMPT.md).
   *Kontrol:* bir Magic Edit gerçek sonuç veriyor (`RELEASE-CHECKLIST.md` §3.4).
2. **Sohbete yapıştırılmış xAI anahtarını döndür** (SAHIP 1.2). Yeni anahtarı Supabase `XAI_API_KEY` olarak yaz, bir AI işi dene, sonra eski anahtarı xAI'de iptal et. Anahtarı hiçbir dosyaya ya da sohbete yazma.
   *Kontrol:* eski anahtar iptal edildi ve AI işi yine çalışıyor.
3. **Migrasyonları sırayla uygula** (SAHIP 1.4). Önce SQL Editor'da (proje `efapupjvidyqhqdevmcu`) durumu kontrol et:

   ```sql
   select
     to_regprocedure('public.settle_unconfirmed(uuid)') as m20261017,
     to_regclass('public.pending_revenuecat_deletions') as m20261018,
     to_regclass('public.ad_reward_tokens') as m20261019,
     to_regprocedure('public.keepalive()') as m20261019500;
   ```

   Sonuç `null` olan dosya uygulanmamış demektir. Uygulanmışları atla. Uygulanmamış dokuz dosya bu sırayla, her biri kendi `begin;` … `commit;` bloğunda çalışır: `20261019000000_ad_rewards.sql`, `20261019500000_keepalive.sql`, `20261020000000_credit_policy_v2.sql`, `20261021000000_install_and_subscription_credits.sql`, `20261022000000_abuse_controls.sql`, `20261023000000_ad_rewards_per_install.sql`, `20261024000000_private_rls.sql`, `20261024000001_abuse_fixes.sql`, `20261024000002_entitlement_order.sql`. Bir dosya hata verirse dur ve hata metnini ajana ver.
   *Kontrol:* bittiğinde `select to_regprocedure('public.record_entitlement(uuid,text,text,timestamptz,boolean,text,boolean)'), to_regprocedure('public.sweep_ad_rewards()');` iki sütunda da `null` olmayan değer döndürür.
4. **Gizli değerleri kontrol et ve eksiği ekle** (SAHIP 1.5). `ADMOB_REWARDED_AD_UNIT` = `ca-app-pub-2292230772061554/1406702504`. `APPLE_APP_ID` = `6822716008` olduğunu doğrula. `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS` varsa sil. `FAL_KEY` ve `XAI_SAFETY_MODEL` eklenmez.
   *Kontrol:* `XAI_API_KEY`, `ANTHROPIC_API_KEY`, `APPLE_APP_ID`, `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID` ve `ADMOB_REWARDED_AD_UNIT` adları var. Değerleri hiçbir yere yazma.
5. **Edge Functions'ı yayımla** (SAHIP 1.6). 3. ve 4. adımdan sonra. `ad-reward` ilk kez yayımlanıyor ve JWT doğrulaması kapalı olmalı; AdMob geri çağrısında JWT yok.

   ```bash
   supabase functions deploy ai-image --project-ref efapupjvidyqhqdevmcu --use-api
   supabase functions deploy credits-redeem --project-ref efapupjvidyqhqdevmcu --use-api
   supabase functions deploy account --project-ref efapupjvidyqhqdevmcu --use-api
   supabase functions deploy report --project-ref efapupjvidyqhqdevmcu --use-api
   supabase functions deploy ad-reward --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
   ```

   *Kontrol:* beş dağıtım hatasız. SAHIP 1.9'daki duman testi geçer.

Bu beşten sonra sahibin sırası: 1.3 (xAI Zero Data Retention, 4.3), 1.7 (`select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');` ve cron işlerinin kontrolü), 1.8 (kimlik ayarları), 1.9 (duman testi); sonra App Store Connect (2), AdMob (3: geçiş birimi, ödüllü birimde sunucu doğrulaması, app-ads.txt), Search Console site haritası ve IndexNow (4.1 ve 4.2).

### 4.3 Sahibin kararını bekleyenler

Ajan gerekli bilgiyi ve kodu hazırlar; karar sahibindedir. Her madde SAHIP-YAPILACAKLAR.md §5–§6 ve AI-TODO.md §3 ile eşleşir.

1. **Deneme kredileri.** Kodda: deneme 20 krediyi bir kez verir. İlk ücretli dönemde kalan krediler korunur, 80 eklenir, toplam en çok 160 olur (`private.refresh_subscription`, `20261021000000_install_and_subscription_credits.sql`). Karar: bu davranış kalsın mı? Kalacaksa paywall ve yasal metinler bunu açıkça söylemeli. Öneri (SAHIP 5.1): mevcut davranış.
2. **İade bildirimleri (App Store Server Notifications V2).** Uç nokta yok: iade edilen Pro abonelik `expires_at` tarihine kadar Pro kalır. AGENTS.md ve `backend/README.md` "Before launch" bunun lansmandan önce kurulmasını istiyor. Karar: uç nokta lansmandan önce kurulsun mu? Öneri (SAHIP 5.2): evet. Uç nokta ajan tarafından yazılır; URL'yi sahip App Store Connect'e girer.
3. **Paylaşılan adresler.** Doğrulanmamış kurulumda anahtar yoksa IP özeti kullanılıyor (`20261024000001_abuse_fixes.sql`). Aynı adresten üç strike, o adresteki herkesi 24 saat cool-down'a alır; okul ve mobil operatör adresleri için bu fazla sert olabilir. Karar: adres anahtarları için eşik yükseltilsin mi? Öneri (SAHIP 5.3): yükselt; değişiklik yeni bir migrasyonla yapılır.
4. **xAI Zero Data Retention.** Gizlilik metinleri (`legal/en/privacy-policy.md` ve `legal/tr/gizlilik-politikasi.md`, madde 5) xAI'nin Zero Data Retention seçeneğini kullandığını yazıyor. Bu depo bunu kanıtlayamaz. Sahip xAI konsolunda ekip ayarında açık olduğunu doğrulamalı (SAHIP 1.3). Açık değilse açılır; açılamıyorsa metinler değişir ve avukatla birlikte karar verilir.
5. **MERSİS satırı.** `legal/config.json` › `COMPANY_REGISTRY`: İngilizcede "None (individual developer)", Türkçede "Yok (bireysel geliştirici)". Bilgi doğruysa kalır. Kaldırılacaksa değer boş bırakılır ve `python3 scripts/build-legal.py` çalıştırılır (SAHIP 5.4). Avukat incelemesi (SAHIP 6.1) bu satırı da kapsamalı.

Diğer karar maddeleri (destek adresi, Apple ile giriş ve RevenueCat anahtarları, KVKK başvuru adresi, yurt dışı aktarım dayanağı) SAHIP-YAPILACAKLAR.md §5–§6'da; AI-TODO.md §3'te ek olarak e-posta beyanı ve marka araması var.

## 5. Doğrulama komutları

Komutları depo kökünden çalıştır.

```bash
swift test --package-path ios/Packages/AppCore
(cd backend/supabase/functions && deno fmt --check && deno lint && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts report/index.ts ad-reward/index.ts app-store-notifications/index.ts owner-digest/index.ts && deno test _shared/ ad-reward/ app-store-notifications/ account/ owner-digest/ ai-image/ credits-redeem/)
backend/scripts/test-db.sh
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'id=<simülatör-udid>' -quiet
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO -quiet
python3 scripts/build-legal.py --check
python3 scripts/export-core-strings.py --check
python3 scripts/check-honest-copy.py
python3 scripts/check-release-config.py --report
python3 scripts/check-release-config.py --online   # sahibin Mac'inde; bu ortamdan adresler açılamaz
```

Ağır derlemelerde disk alanını kontrol et (`df -h /System/Volumes/Data`). Önce DerivedData klasörlerini temizle: `~/Library/Developer/Xcode/DerivedData/Glowlit-*`.

## 6. Bilinen sorunlar ve riskler

- **xAI ve Anthropic bütçesi:** arka uç canlı; xAI'de 14 Ekim'de yüklenen 10 USD test ve inceleme için yeterli, lansman için değil. Bakiye ya da limit dolarsa her AI işi başarısız olur ve kredi iade edilir. Harcama limitleri ve yükleme sahipte (SAHIP-YAPILACAKLAR.md 1.1, 1.11); günlük sigortalar 60 ücretsiz / 400 toplam iş.
- **Çıktı denetimi:** `FAL_KEY` yokken kontrol xAI'nin kendi moderasyon kararıdır. Kontrol başarısız olursa sonuç engellenir (fail-closed, `_shared/moderation.ts`). Bunun üstüne Claude düzenlenecek fotoğrafı ve her sonucu denetler (`_shared/safety.ts`, o da fail-closed); 15 Ekim 2026'da canlıda gerçek bir Magic Edit'le doğrulandı. Anthropic bakiyesi biterse her düzenleme engellenir ve iade edilir (SAHIP-YAPILACAKLAR.md 1.11).
- **Apple ile giriş açık** (`signInWithApple: true`, 1.0). Anahtarlar ayarlı ve App Privacy yayında. Cihazda giriş, kredi birleştirme ve token iptalli silme testi sahipte ve isteğe bağlı (`RELEASE-CHECKLIST.md` §5, §9.6). Kapatılırsa `check-honest-copy.py` App Store metinlerindeki giriş satırlarını reddeder.
- **Mac'te Eserlerim:** Mac derlemesinde `ImageStore` dosyaları `completeFileProtectionUntilFirstUserAuthentication` ile yazıyor (`ImageStore.swift`, `#if targetEnvironment(macCatalyst)`). Gerçek Mac'te kutuların boş kalmadığı doğrulanmalı.
  - Doğrulanamadı: bu ortamda Mac yok.
- **Ücretsiz kredi kötüye kullanımı:** App Attest ve DeviceCheck henüz yok (`backend/README.md`, "Before launch", işaretsiz). Bunlar olmadan ücretsiz kredi toplamak tam olarak engellenmez. Apple tarafı ayar ve gerçek cihaz testi gerektirir (AI-TODO.md §2.7).
- **Kayıt saklama:** hesap silindikten sonra karma kurulum kayıtları en çok 30 gün kalır (`install_retention_days`). Gizlilik metni bunu söylüyor (AI-TODO.md §5.1).
- **Yasal metinler:** avukat incelemesi önerilir (SAHIP 6.1). Veri sorumlusu bireysel geliştirici; KVKK için yazılı adres (`KEP_ADDRESS`) boş.
- **Keep-alive:** `keepalive.yml` yalnızca varsayılan dal `main`'den çalışır. GitHub, herkese açık depoda 60 gün commit yoksa zamanlanmış iş akışlarını durdurur (`keepalive.yml` yorumu).
- **Mağaza metinleri:** App Store açıklama ve promosyon metinlerinde emoji kullanılmaz. Açıklama uzunluğu yeni metinle yeniden ölçülmeli.
- **Destek ve kişisel bilgi:** destek adresi `AppConfig.json` (`supportEmail`) ve `legal/config.json` (`CONTACT_EMAIL`) içinde. Kişisel e-posta adresi açık dosyalara yazılmaz (AGENTS.md §5).

## 7. Devam promptları

### Prompt 1 — ajan işleri
```text
Çalışma klasörü: <depo kökü> (GitHub: RiosenBeq/aybuke-app, dal pink-girls-redesign).
Önce AGENTS.md ve docs/NEXT-STEPS.md dosyalarını oku. Sonra docs/NEXT-STEPS.md §4.1'deki adımları sırayla yap: önce CI, sonra main'e birleştirme (yalnızca CI yeşilse), sonra kalanlar. Her adımın "Kontrol" satırı tamamlanmadan bir sonrakine geçme. Ayrıntılı kod işleri için docs/AI-TODO.md §1'e bak.
Kurallar: sır (API anahtarı, .p8, Secrets.xcconfig, service role anahtarı, RevenueCat gizli anahtarı) yazdırma veya commit etme. .claude/ commit etme. Uygulanmış bir migrasyonu değiştirme; yeni dosya ekle. Supabase, AdMob, xAI ve App Store Connect işlerine dokunma: onlar sahibindedir. Gönderim (Submit for Review) yapma.
Sonunda: yapılanlar, her kontrolün sonucu, kalan sorunlar.
```
