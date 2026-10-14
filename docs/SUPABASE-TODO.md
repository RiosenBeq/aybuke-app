# Supabase kurulumu — sonraya bırakıldı

Bu dosya, Glowlit'in arka ucunu (Supabase) canlıya almak için kalan adımları listeler. Kod hazır: `backend/` klasöründe veritabanı geçişleri, Edge Functions ve testler var. Ayrıntılı İngilizce rehber: [`backend/README.md`](../backend/README.md).

> **Önemli:** Arka uç canlı olmadan uygulamadaki yapay zekâ özellikleri **demo modunda** çalışır (sonuçlar simüle edilir). App Store'a incelemeye göndermeden önce aşağıdaki adımlar tamamlanmalı; yoksa inceleme ekibi gerçek sonuç göremez ve uygulama "eksik" (Guideline 2.1) gerekçesiyle reddedilebilir.

## 1. Giriş ve temizlik

- [ ] Chrome'da Supabase'e giriş yap: **Continue with ChatGPT** → **Okan Berk Manavoğlu** hesabı.
- [ ] Eski **envanter** projesini sil: Project Settings → General → Delete project. (Kalıcı silme olduğu için bunu hesap sahibi yapmalı.)

## 2. Yeni proje

- [ ] **New project** → ad: `Glowlit`, bölge: **Central EU (Frankfurt)** (KVKK/GDPR açısından AB önerilir).
- [ ] Veritabanı şifresi: "Generate a password" ile oluştur ve şifre yöneticisine kaydet.

## 3. Veritabanı (SQL Editor)

- [ ] `backend/supabase/migrations/` içindeki dosyaları sırayla çalıştır:
  1. `20261011000000_init.sql`
  2. `20261012000000_reports_and_retention.sql`
  3. `20261013000000_accounts.sql`
  4. `20261014000000_retry_reopen.sql`
  5. `20261015000000_merged_users.sql`
  6. `20261016000000_explicit_grants.sql`
  7. `20261017000000_unclaimed_results.sql` (uygulamaya hiç ulaşmayan sonuçların iadesi; `ai-image` yeniden yayımlanmadan önce)
  8. `20261018000000_revenuecat_deletion_queue.sql` (RevenueCat silme kuyruğu; `account` yeniden yayımlanmadan önce)
- [ ] Zamanlanmış temizlik (takılan işleri ve uygulamaya ulaşmayan sonuçları iade eder, sonuçları 1 saat sonra siler):
  ```sql
  create extension if not exists pg_cron;
  select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
  ```
- [ ] RevenueCat silme kuyruğu için saatlik çağrı (`pg_net` uzantısını aç; anahtar yokken istekler kuyrukta bekler, anahtar eklenince bu çağrı onları gönderir). Proje URL'sini ve service role anahtarını bir kez Vault'a koy, sonra zamanla:
  ```sql
  create extension if not exists pg_net;
  select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
  select vault.create_secret('<service role key>', 'service_role_key');
  select cron.schedule('revenuecat-deletions', '17 * * * *', $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
             || '/functions/v1/account/revenuecat-deletions',
      headers := jsonb_build_object('Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'))
    )
  $$);
  ```

## 4. Kimlik doğrulama (Authentication)

- [ ] **Anonymous sign-ins** açık olsun (kayıt ekranı yok; Apple yönergesi 5.1.1(v)).
- [ ] Kötüye kullanıma karşı **CAPTCHA (Turnstile)** önerilir.
- [ ] **Apple** sağlayıcısı: Client IDs alanına `app.glowlit.ios` ekle.
- [ ] Apple Developer'da App ID için **Sign in with Apple** açık olsun; hesap silmede token iptali için bir "Sign in with Apple" anahtarı (.p8) oluştur.

## 5. Edge Functions

Terminalde (Supabase CLI kurulu):

```bash
cd backend
supabase login
supabase link --project-ref <proje-ref>
supabase functions deploy ai-image credits-redeem account report
```

## 6. Gizli anahtarlar (Edge Functions → Secrets)

Bu değerleri hesap sahibi yapıştırmalı (anahtarları ben giremem). Şablon: `backend/.env.example`.

- [ ] `XAI_API_KEY` — xAI anahtarı (yapay zekâ için)
- [ ] `APPLE_BUNDLE_ID` = `app.glowlit.ios`
- [ ] `APPLE_APP_ID` — App Store Connect'teki sayısal uygulama kimliği (uygulama kaydı oluşunca)
- [ ] `APPLE_TEAM_ID` = `CBTKNY3LFC`
- [ ] `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY` — Sign in with Apple anahtarı
- [ ] `REVENUECAT_SECRET_KEY` ve `REVENUECAT_PROJECT_ID` — hesap silinince RevenueCat müşterisini de silmek için. RevenueCat → Project settings → API keys'te yalnızca `customer_information:customers:read_write` izinli bir **v2** gizli anahtar oluştur; proje kimliği aynı sayfada. Boş kalırsa hesap silme yine çalışır; RevenueCat silme istekleri `pending_revenuecat_deletions` tablosunda bekler ve anahtar eklenince (her hesap silmede ve saatlik zamanlanmış çağrıda, bkz. `backend/README.md` 6. adım) gönderilir.
- [ ] (İsteğe bağlı) `FAL_KEY` — bağımsız çıktı güvenlik kontrolü (fal.ai) ve yedek sağlayıcı. Her sonuç tek bir çıktı kontrolünden geçer ve kontrol çalışamazsa sonuç engellenip kredi iade edilir (kapatma ayarı yok; eski `OUTPUT_MODERATION` artık okunmuyor). `FAL_KEY` yokken kontrol xAI'nin kendi denetim kararıdır. `FAL_KEY` eklenince sonuçlar fal.ai'ye gider; bu yüzden önce fal.ai'yi onay ekranına (`aiProcessors`) geri ekleyen bir uygulama sürümü yayımlanmalı.

> **Onay ekranı:** Uygulamanın yapay zekâ onay ekranı, işleyicileri `ios/App/Resources/AppConfig.json` içindeki `aiProcessors` listesinden gösterir (şu an Supabase ve xAI). `AI_PROVIDER`'ı değiştirmek veya listede olmayan bir işleyici eklemek, önce o işleyiciyi listeleyen bir uygulama güncellemesi gerektirir; liste değişince uygulama onayı yeniden ister. Backend sağlayıcıyı uygulama sürümü olmadan değiştirebilir, bu yüzden sırayı koru.

## 7. xAI konsolu

- [ ] [console.x.ai](https://console.x.ai) → ekip ayarlarında **Zero Data Retention**'ı aç. Selfie'ler kişisel veri; gizlilik politikamız ve xAI şartları bunu bekliyor.
- [ ] Faturalandırma ve harcama limiti tanımla.

## 8. Uygulamayı arka uca bağla

- [ ] `ios/App/Resources/AppConfig.json`:
  - `backendBaseURL`: `https://<proje-ref>.supabase.co`
  - `supabaseAnonKey`: projenin publishable (anon) anahtarı (herkese açık olması tasarım gereği sorun değil)
- [ ] Commit → yeni build → TestFlight'ta gerçek bir Magic Edit ile uçtan uca test.
- [ ] Sonra App Store'a incelemeye gönder.

## Notlar

- Çözülemeyen engel: Chrome uzantısı OpenAI giriş sayfasına güvenlik gereği erişemiyor; ChatGPT ile girişte hesap seçimini kullanıcı yapmalı.
- Arka uç tasarımı, maliyetler ve kredi kuralları: [`backend/README.md`](../backend/README.md), [`docs/03-product-spec.md`](03-product-spec.md).
