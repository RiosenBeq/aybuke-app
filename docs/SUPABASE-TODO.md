# Supabase kurulumu: canlıya alma listesi

Bu dosya, Aybuke'nin arka ucunu (Supabase projesi `efapupjvidyqhqdevmcu`, Frankfurt) canlıya almak için kalan adımları listeler. Kod hazır: veritabanı geçişleri `backend/supabase/migrations/` klasöründe, Edge Functions `backend/supabase/functions/` klasöründe. Gerekçeler ve kötüye kullanım runbook'u: [`backend/README.md`](../backend/README.md). Sahibin yapacakları ve kararları [`docs/SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md) listesinde; bu dosyadaki `§` numaraları o listenin atıfları için sabittir.

> **Durum (16 Ekim 2026):** Arka uç canlı: migrasyonlar `20261103000001`'e (anket sınırları) kadar uygulandı, dokuz fonksiyon yayında (`owner-digest`, `assist` ve `polls` dahil), gizli değerler ve üç cron işi tamam, RevenueCat yönlendirme adresi girildi; Supabase organizasyonu ve projesi "Aybuke" adını aldı. Aybuke 1.0 incelemede. Aşağıdaki kutular 14 Ekim'de yazıldı; liste artık yeniden kurulum ve kontrol için kayıttır. Güncel açık işler: [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md).
>
> **Uygulandı (güvenlik incelemesi, 16 Ekim 2026):** `20261103000000_assist_ceilings.sql` ve `20261103000001_poll_limits.sql` (her biri `psql -1`) canlıda; `assist`, `ai-image` (yerel mevsim görünümleriyle), `polls` ve `owner-digest` yeniden yayımlandı (JWT doğrulaması açık). Uçtan uca deneme: geçici bir anonim kullanıcıyla `assist` 200, `polls/mine` 200, ardından `DELETE /account` 200. Ayrıntı: `backend/README.md`, "Polls" altında "Security review fixes".

> **Kural:** Anahtar, şifre, service role anahtarı, `.p8` içeriği ve e-posta adresi bu dosyaya, bir commit'e ya da bir sohbete yazılmaz. Değerler yalnızca ilgili panele girilir. Proje kimliği ve AdMob birim kimlikleri herkese açıktır.

## §0 Önce kontrol

Eski notlar (`docs/HANDOFF-PROMPT.md`) `20261011000000`–`20261018000000` ve `20261019500000` dosyalarının uygulandığını söylüyor. Bu, veritabanında aşağıdaki sorguyla doğrulanır; nota güvenilmez. `20261017000000` ve `20261018000000` için canlı durum bilinmiyor.

- [ ] SQL Editor'da aşağıdaki sorguyu çalıştır. Satırlar hangi dosyanın canlıda olduğunu gösterir: `true` olanlar tamam, `false` olanlar uygulanmamış demektir.

```sql
select 'public.credit_wallets (20261011000000)' as nesne, to_regclass('public.credit_wallets') is not null as var
union all select 'public.reports (20261012000000)', to_regclass('public.reports') is not null
union all select 'public.apple_accounts (20261013000000)', to_regclass('public.apple_accounts') is not null
union all select 'public.merged_users (20261015000000)', to_regclass('public.merged_users') is not null
union all select 'jobs.delivered_at (20261017000000)', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'jobs' and column_name = 'delivered_at')
union all select 'public.pending_revenuecat_deletions (20261018000000)', to_regclass('public.pending_revenuecat_deletions') is not null
union all select 'public.ad_reward_tokens (20261019000000)', to_regclass('public.ad_reward_tokens') is not null
union all select 'public.keepalive() (20261019500000)', to_regprocedure('public.keepalive()') is not null
union all select 'public.credit_policy() v2 (20261020000000)', exists (select 1 from information_schema.parameters where specific_schema = 'public' and parameter_name = 'cost_input_image_cents')
union all select 'private.app_installs (20261021000000)', to_regclass('private.app_installs') is not null
union all select 'private.ai_switches (20261022000000)', to_regclass('private.ai_switches') is not null
union all select 'public.ad_reward_overview() (20261023000000)', to_regprocedure('public.ad_reward_overview(uuid, boolean, text, text, text)') is not null
union all select 'private.ai_usage_daily con RLS (20261024000000)', coalesce((select rowsecurity from pg_tables where schemaname = 'private' and tablename = 'ai_usage_daily'), false)
union all select 'public.record_entitlement() (20261024000002)', to_regprocedure('public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)') is not null;
```

  - `20261011000000`–`20261018000000` satırlarından biri `false` ise o dosya §1'den önce, kendi `begin; … commit;` bloğunda uygulanır; sıra zaman damgasına göre. `20261019000000` ve sonrası §1'de uygulanır, `true` olanlar atlanır. Uygulanmış bir dosyayı yeniden çalıştırma; `add column` ve `create table` gibi adımlar hata verir.
  - Sorgu yerel bir PostgreSQL 16 kopyasında denendi: eksik dosyalar `false`, tam kurulum `true` döndürdü. Canlı proje bu ortamdan denenemedi.
- [ ] Sayıları kontrol et: `select * from public.credit_policy();` ve `select * from public.ad_reward_policy();`. Beklenen: `free_daily` 2, `pro_monthly` 80, `pro_rollover_cap` 160, `trial_credits` 20, `free_retries_daily` 3, kırıcılar 1500 / 200 / 8000; reklam için `daily_cap` 2, `credits` 1, `token_ttl` 30 dakika. Farklıysa `backend/README.md` "Credit rules" ile karşılaştır.
- [ ] Uzantıları kontrol et: `select extname, extversion from pg_extension where extname in ('pg_cron', 'pg_net', 'supabase_vault');`. §3 için üçü de gerekir; eksikse Database › Extensions'tan aç. (Doğrulanamadı: Vault uzantısının kayıt adı ve panel yolu.)

## §1 Migrasyonlar

Her dosya kendi blokunda, sırayla çalıştırılır. Dosyaların içinde `begin` ve `commit` yoktur; blok her dosyanın etrafına sen koyarsın:

```sql
begin;
-- backend/supabase/migrations/<dosya adı>.sql dosyasının tüm içeriği (kopyalayıp yapıştır)
commit;
```

- Sıra zaman damgasına göre. Bir dosya hata verirse **dur**: hata metnini kaydet, sonraki dosyaya geçme ve dosyayı değiştirme. Uygulanmış migrasyon düzenlenmez; düzeltme yeni bir dosyada yapılır.
- Hangi dosyaların atlanacağı §0 sonucuna göre belirlenir. On üç dosyanın tamamı, her biri kendi `begin; … commit;` bloğunda, yerel PostgreSQL 16 kopyasında hatasız uygulandı.

- [ ] **1.1 `20261019000000_ad_rewards.sql`:** ödüllü reklam kredileri; tablolar `public.ad_reward_tokens` ve `public.ad_rewards`, `sweep_ad_rewards`. 1.6 bazı işlevleri değiştirir.
- [ ] **1.2 `20261019500000_keepalive.sql`:** `public.ops_heartbeat` ve `public.keepalive()`, GitHub keep-alive iş akışının çağırdığı işlev. Eski notlara göre uygulanmış olabilir; §0 sonucuna göre atla.
- [ ] **1.3 `20261020000000_credit_policy_v2.sql`:** `public.credit_policy()`, sunucudaki kredi, kırıcı, hız sınırı ve saklama sayılarının tamamı.
- [ ] **1.4 `20261021000000_install_and_subscription_credits.sql`:** `private` şeması, kurulum tuzu, App Store kurulumu başına ücretsiz kredi, abonelik ve paket kredileri. 1.3'ten sonra gelir.
- [ ] **1.5 `20261022000000_abuse_controls.sql`:** `public.admit_job()`, kırıcılar, hız sınırları, uyarılar (strike), bekleme süreleri, engeller ve `ops_*` sahip araçları.
- [ ] **1.6 `20261023000000_ad_rewards_per_install.sql`:** reklam sınırı kullanıcı ve kurulum başına; `ad_reward_overview` eklenir.
- [ ] **1.7 `20261024000000_private_rls.sql`:** `private` şemasının tablolarında satır güvenliği (RLS) açılır; politika eklenmez.
- [ ] **1.8 `20261024000001_abuse_fixes.sql`:** 1.5'teki `admit_job`, `add_strike` ve `ops_unblock` işlevlerini yerinde değiştirir.
- [ ] **1.9 `20261024000002_entitlement_order.sql`:** `public.record_entitlement()`; abonelik kaydı yalnızca ileri gider.
- [ ] **1.10 `20261025000000_app_store_notifications.sql`:** App Store Server Notifications V2 için işlenen bildirim kimlikleri (`private` tablo, RLS açık, yetki yok), `public.revoke_entitlement()` (iade ya da iptalde Pro hemen kapanır, iade geri alınırsa süre dolmadıysa geri açılır) ve kredi paketi iadesinde kredilerin geri alınması (bir kez, sıfırın altına inmez). Yalnızca service role çalıştırır.
- [ ] **1.11 `20261025000001_sql_gaps.sql`:** `admit_job` günlük ücretsiz tekrar sayısında iade edilen tekrarları saymaz; `flag_job` kullanıcının iptal ettiği işe uyarı (strike) eklemez; `wallet_state` isteğe bağlı istemci adresini alır, böylece adrese bağlı bekleme ve engel bakiyede görünür (eski çağrı aynen çalışır).
- [ ] **1.12 `20261025000002_refunded_transactions.sql`:** iade ve iptalleri `private.refunded_transactions` tablosunda hatırlar; iadesi gelmiş bir paket sonradan kullanılmak istenirse kredi verilmez, iadesi gelmiş Pro dönemi iptal edilmiş olarak kaydedilir. İade geri alınırsa kayıt kalkar.
- [ ] **1.13 `20261025000003_notification_prune.sql`:** 1.12'deki eski kayıt temizliğini, aynı anda gelen iki bildirimin birbirini kilitlemeyeceği biçimde değiştirir.

## §2 Güvenlik kontrolleri

- [ ] **Anonim ve giriş yapmış kullanıcının çalıştırabildiği işlevler.** Sorgu tek satır döndürmeli: `keepalive()`, `anon` true, `authenticated` false. Başka satır varsa ilgili migrasyonda `revoke execute … from public, anon, authenticated` eksiktir; düzeltme yeni bir migrasyonla yapılır.

```sql
select p.oid::regprocedure as fn,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
```

- [ ] **Satır güvenliği.** `select schemaname, tablename, rowsecurity from pg_tables where schemaname in ('public', 'private') order by 1, 2;` Bütün satırlar `true` olmalı.
- [ ] **Security Advisor.** Advisors › Security Advisor'ı §1'den sonra aç. Beklenen: "function search path mutable" ve RLS kapalı bulgusu yok. Yerel kopyada her işlevin `search_path`'i sabitti. Kabul edilen tek uyarı `keepalive()`: anonim çalıştırılır ve `security definer` olduğu için panel işaretleyebilir; bu bilinçli bir karardır. (Doğrulanamadı: panelin uyarı adı ve düzeyi.)
- [ ] **Kod kontrolü.** Bu depoda doğrulandı: migrasyonlar her `public` işlevinin `anon` yetkisini kapatır (tek tek `revoke` ya da 20261022000000'daki döngü ile); `anon`'a açık bırakılan tek işlev `keepalive` (20261019500000).

## §3 Zamanlanmış işler (cron)

Migrasyonlar zamanlama oluşturmaz; yalnızca yorumlarda geçer. Komutları SQL Editor'da elle çalıştır. Önce mevcut işlere bak:

```sql
select jobname, schedule, active from cron.job;
```

Aynı adla `cron.schedule` çağırmak mevcut işi değiştirir (pg_cron'un bu davranışı canlıda doğrulanamadı). Listede adı olan işe dokunma.

- [ ] **`sweep-jobs`** (her 5 dakika): takılan işleri başarısız sayıp iade eder, uygulamaya ulaşmayan sonuçları iade eder, çıktıları 1 saat sonra siler ve eski kayıtları saklama süresine göre temizler. Kötüye kullanım temizliği ayrı bir iş değil; `sweep_jobs` içinde.

```sql
select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');
```

- [ ] **`sweep-ad-rewards`** (her saat :17): süresi dolan reklam jetonlarını bir gün sonra, reklam kayıtlarını 30 gün sonra siler.

```sql
select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');
```

- [ ] **`sweep-app-store-notifications`** (her gün 03:23 UTC): App Store bildirim kayıtlarını 30 gün sonra, iade kayıtlarını (`private.refunded_transactions`) gizlilik politikasının 14. bölümündeki sürelerde siler (`public.sweep_app_store_notifications()`, migration `20261030000000`; pg_cron açıksa migration işi bu fonksiyona yönlendirir).

```sql
select cron.schedule('sweep-app-store-notifications', '23 3 * * *', 'select public.sweep_app_store_notifications()');
```

- [ ] **`revenuecat-deletions`** (her saat :17): bekleyen RevenueCat silmelerini gönderir. RevenueCat anahtarı yokken de çalışır; istekler kuyrukta bekler. Önce Vault'a iki sır eklenir, bir kez: `project_url` ve `service_role_key`. Değeri sahip girer; dosyaya, commit'e ya da sohbete yazılmaz. Ad zaten varsa `select name from vault.decrypted_secrets;` ile görüp yeniden ekleme.

```sql
select vault.create_secret('https://efapupjvidyqhqdevmcu.supabase.co', 'project_url');
select vault.create_secret('<service role anahtarı>', 'service_role_key');
select cron.schedule('revenuecat-deletions', '17 * * * *', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/account/revenuecat-deletions',
    headers := jsonb_build_object('Authorization', 'Bearer ' ||
      (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'))
  )
$$);
```

- [ ] **Kontrol.** `select jobname, schedule, active from cron.job;` çıktısında dört ad da `active` olarak görünmeli. Başka bir ad görürsen silmeden sahibe sor.
- [ ] **Keep-alive (veritabanı dışı).** `.github/workflows/keepalive.yml` her gün 07:23 UTC'de `public.keepalive()` çağırır; anon anahtarı kullanır, sır gerekmez. GitHub Actions'ta "Backend keep-alive" son çalışması yeşil olmalı. (Doğrulanamadı: çalışma geçmişi bu ortamdan görülmedi.) Public depoda 60 gün commit yoksa GitHub zamanlamayı durdurur; durursa Actions'tan yeniden etkinleştir.

## §4 Kimlik doğrulama ayarları

Supabase panelinde Authentication. (Doğrulanamadı: menü adları panel sürümüne göre değişebilir.)

- [ ] **Anonymous sign-ins: açık.** Uygulama anonim kullanıcıyı yalnızca ilk onaylı bulut işinde ya da satın almada açar; kayıt ekranı yok (App Review 5.1.1(v)).
- [ ] **Anonim giriş sınırı: saatte IP başına 15** (Rate Limits). Hesap açmanın çoğaltılmasını sınırlar.
- [ ] **Email sağlayıcısı: kapalı.**
- [ ] **CAPTCHA: kapalı kalsın.** Uygulamada CAPTCHA widget'ı yok; açılırsa her anonim kayıt başarısız olur. Eski Turnstile önerisi geçersiz.
- [ ] **Apple sağlayıcısı: Client ID `app.glowlit.ios`.** Apple ile giriş 1.0'da açık (`signInWithApple: true`, `ios/App/Resources/AppConfig.json`; anahtarlar §6'da ayarlı, SAHIP 5.6).

## §5 Edge Functions

Önkoşul: §1 migrasyonları ve §0 nesneleri tamam; §6'daki zorunlu değerler girili. `ai-image` `admit_job` ve `deliver_outputs` gibi işlevleri, `ad-reward` `ad_reward_overview` ve `redeem_ad_reward` işlevlerini çağırır; bu yüzden fonksiyonlar migrasyonlardan sonra yayımlanır.

`backend/` klasöründe, önce `supabase login` ve isteğe bağlı `supabase link --project-ref efapupjvidyqhqdevmcu`:

```bash
supabase functions deploy ai-image --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy credits-redeem --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy account --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy report --project-ref efapupjvidyqhqdevmcu --use-api
# AdMob'un geri çağrısında JWT yok; ad-reward Google'ın imzasını kendisi denetler.
supabase functions deploy ad-reward --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
# Apple'ın bildiriminde de JWT yok; fonksiyon Apple'ın imzasını (Apple Root CA G3) kendisi denetler.
supabase functions deploy app-store-notifications --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
```

- [ ] Her komut hatasız bitti. (Doğrulanamadı: `--use-api` bayrağı bu ortamda denenmedi, Supabase CLI kurulu değil; `supabase functions deploy --help` ile bak.)
- [ ] `ad-reward` ve `app-store-notifications` `--no-verify-jwt` ile yayımlandı. Bu bayrak olmazsa AdMob'un ve Apple'ın çağrıları reddedilir.
- [ ] Edge Functions › Logs'ta her fonksiyonun ilk istekten sonra başlatma hatası yok.
- [ ] Yayımlanacak commit'te CI yeşil: `.github/workflows/ci.yml` `deno check` ve `deno test` çalıştırır.
- [ ] **App Store Server Notifications V2 adresi (sahip, RevenueCat üzerinden).** App Store Connect her ortam için tek adres kabul eder ve App Store Connect › Aybuke › App Information › App Store Server Notifications'taki Production ve Sandbox adresleri RevenueCat'i gösterir; öyle kalır. Adres RevenueCat'e girildi (15 Ekim 2026): RevenueCat › Project Aybuke › Apps › Aybuke (App Store) › "Apple Server Notification Forwarding URL" = `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/app-store-notifications`. RevenueCat her imzalı bildirimi değiştirmeden iletir; fonksiyon Apple'ın imzasını kendisi denetler. Bu ayarı sahip yapar (bir ajanın denemesi engellendi). Ardından bir Sandbox satın alması (ya da App Store Connect'in test bildirimi, RevenueCat iletirse); Edge Functions › Logs'ta `app-store-notifications` 200 döner. Fonksiyon üretim bildirimlerini yalnızca `APPLE_APP_ID` ayarlıyken kabul eder. SAHIP 2.14.
- [ ] **AdMob doğrulama adresi.** Server-side verification: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` (sorgu dizesi yok), ardından **Verify URL**. Test geri çağrısı 200 döner ve kredi vermez. Ayrıntı: `backend/README.md` "Rewarded ads"; SAHIP 3.2.

## §6 Gizli değerler (secrets)

Değerleri sahip girer. Yer: Supabase panelinde Edge Functions › Secrets; ya da `backend/.env.example` dosyasını `backend/.env` olarak doldurup `supabase secrets set --env-file backend/.env` çalıştır (`.env` git'te yok sayılır, commit etme). `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` Supabase tarafından verilir; bunları ayarlama.

**Zorunlu**

- [ ] `XAI_API_KEY`: xAI anahtarı. Canlıda ayarlı olup olmadığı doğrulanamadı (HANDOFF'a göre ayarlı). Döndürme: SAHIP 1.2.
- [ ] `ANTHROPIC_API_KEY`: Anthropic (Claude) anahtarı; bağımsız güvenlik denetimi (`_shared/safety.ts`). Sahip 15 Ekim 2026'da girdi; değerini okuma ya da yazdırma, yalnızca adına bak. Ayarlıyken düzenlenecek her fotoğraf ve her sonuç Claude'a gider ve denetim fail-closed çalışır: Anthropic bakiyesi biterse ya da anahtar geçersizse her düzenleme ve sonuç engellenir, kredi iade edilir (SAHIP 1.11). Onay ekranı (`consentVersion` 2) ve gizlilik metinleri Anthropic'i bu depoda yazıyor; aybuke.org'daki canlı hukuk sayfaları ise ayrı depodan (`RiosenBeq/aybuke`) yayınlanır ve yeni metni henüz taşımıyor. Henüz herkese açık bir derleme olmadığı için `ai-image` bundan önce yayımlanabilir (§5; MAC-YAYIN 5.5). Ama senin dışında birinin kuracağı bir derleme test kullanıcılarına ulaşmadan ve incelemeye gönderilmeden önce canlı sayfalar Anthropic'i yazmalı: hukuk metinlerini web sitesi deposuna kopyala, orada derle ve yayınla (`web/README.md`; kontrol MAC-YAYIN 11. bölüm). Yayımdan sonra Edge Functions › Logs'ta `ai-image` başlarken `output check in force: xai + anthropic:claude-haiku-5-5` yazar. SAHIP 5.8.
- [ ] `APPLE_APP_ID` = `6822716008`. Üretim (App Store) satın almalarını doğrulamak için şart; yoksa üretim AppTransaction reddedilir ve ücretsiz krediler kapalı kalır. Sandbox bu olmadan da çalışır.
- [ ] `ADMOB_REWARDED_AD_UNIT` = `ca-app-pub-2292230772061554/1406702504`. Boş kalırsa hiçbir reklam ödülü verilmez.
- [ ] `APPLE_BUNDLE_ID` = `app.glowlit.ios`. Kodda bu varsayılan; yine de gir.
- [ ] `APPLE_TEAM_ID` = `CBTKNY3LFC`. Kodda yalnızca Apple ile giriş yolu okur (`_shared/apple-signin.ts`); giriş 1.0'da açık olduğu için gerekli.
- [ ] `APPLE_SIGNIN_KEY_ID` ve `APPLE_SIGNIN_PRIVATE_KEY`: Apple ile giriş 1.0'da açık; Apple'ın kodunu takas etmek ve hesap silinince token'ı iptal etmek için gerekli. 15 Ekim 2026'da girildi (Key ID `36Q32XU57F`) ve Apple'a karşı denendi. SAHIP 5.6.

**İsteğe bağlı (varsayılan kapalı)**

- [ ] `REVENUECAT_SECRET_KEY` ve `REVENUECAT_PROJECT_ID` = `3e7e4f4a`: hesap silinince RevenueCat müşterisini de siler. Anahtar yalnızca `customer_information:customers:read_write` izinli bir v2 gizli anahtar olmalı. Yoksa silmeler `pending_revenuecat_deletions` tablosunda bekler. SAHIP 5.7.
- [ ] `RESEND_API_KEY`, `DIGEST_SECRET` ve `OWNER_ALERT_TO`: sahibe giden uyarı e-postaları ve günlük özet (`backend/README.md`, "Owner alerts"). `RESEND_API_KEY` yoksa uyarılar log satırıyla atlanır. 15 Ekim 2026'da girildi. SAHIP 1.12.
- [ ] `ANTHROPIC_SAFETY_MODEL`: boş bırakılabilir; boşken `claude-haiku-5-5`. Yalnızca denetim modelini değiştirmek için.
- [ ] `FAL_KEY`: **girilmez.** Girilirse her çıktı fal.ai'ye gider; fal.ai onay ekranında (`aiProcessors`) yok ve gizlilik metinleri onu yalnızca kullanılmayan bir alternatif olarak anar. Boşken çıktı denetimi xAI'nin kendi kararıdır; bağımsız denetim Claude'dur. SAHIP 5.8.
- [ ] `XAI_SAFETY_MODEL`: **boş bırakılır.** `ANTHROPIC_API_KEY` ayarlıyken zaten okunmaz (Claude önceliklidir). Canlı API'de test edilmedi. SAHIP 5.8.
- [ ] `AI_PROVIDER`, `XAI_IMAGE_MODEL`, `XAI_EDIT_MODEL`: boş bırakılır. `AI_PROVIDER` boşken `XAI_API_KEY` varsa xAI, yoksa fal kullanılır.

**Girilmez**

- [ ] `GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS`: yalnızca yerel geliştirme içindir. Barındırılan projede fonksiyon bunu yok sayar ve günlüğe yazar; yine de ayarlanmaz.
- [ ] `OUTPUT_MODERATION`: hiçbir fonksiyon okumaz ve çıktı denetimi kapatılamaz. Varsa sil.

## §7 xAI ve dış hesap kontrolleri

Sahibin işi. console.x.ai üzerinde. (Doğrulanamadı: konsolun arayüz adları.)

- [ ] **Kredi ve aylık limit.** Ekip faturalandırmasında kredi yüklü ve aylık harcama limiti tanımlı. Kredi bitince her AI işi başarısız olur ve kredi iade edilir. SAHIP 1.1.
- [x] **Zero Data Retention** (15 Ekim 2026'da açıldı, ekip düzeyinde). Ekip ayarlarında açık ve bu anahtar için geçerli. Gizlilik metinleri (`legal/tr/gizlilik-politikasi.md`, 5. madde) bunu söyler; depo bunu kanıtlayamaz. Açılamıyorsa metinler yanlış olur; karar için SAHIP 1.3 ve 6.1.
- [ ] **Anahtar döndürme.** `XAI_API_KEY` bir sohbete, dosyaya ya da bilete yazıldıysa: yeni anahtar üret, Supabase'de değiştir, bir AI işi dene, eskisini iptal et. SAHIP 1.2.
- [ ] **Anthropic (Claude Console, platform.claude.com).** Bakiye var ve aylık harcama limiti tanımlı; denetim başına yaklaşık 0,0002 USD. Bakiye biterse güvenlik denetimi çalışamaz ve her düzenleme ile sonuç engellenip iade edilir. SAHIP 1.11.

## §8 Yükleme sonrası kontroller (TestFlight)

TestFlight derlemesi Sandbox ile çalışır; sunucu Sandbox işlemlerini her zaman kabul eder (`_shared/apple.ts`). Aşağıdakiler App Store incelemesinden önce, Sandbox derlemesinde kontrol edilir (SAHIP 2.12).

- [ ] **İlk deneme: 2 ücretsiz kredi.** Temiz kurulumda ilk denemeden önce bakiye 2 kredi gösterir. Ücretsiz kredi doğrulanmış App Store kurulumuna bağlıdır; kanıt yoksa verilmez.
- [ ] **Gerçek sonuç.** Bir Magic Edit gerçek sonuç döndürür ve sonuçta "DEMO PREVIEW" damgası yoktur.
- [ ] **"Preview build" bandı yok.** Keşfet'te "Preview build: AI results are samples" görünmez; bu bant yalnızca demo modunda gösterilir (`AppModel.modeBanner`).
- [ ] **Sandbox satın alma.** Bir Sandbox satın alması bakiyeyi değiştirir. SQL Editor'da `select kind, daily, subscription, purchased, created_at from public.credit_ledger order by created_at desc limit 5;` ile yeni satırı gör.
- [ ] **Sahip okuması.** `backend/README.md` "Abuse runbook" bölümünü oku. İlk gerçek günden sonra `select public.ops_daily_summary();` çalıştır.

## §9 Sahip kararları

Bu bölümdeki işleri ajan yapmaz; karar sahibindedir.

- [ ] **Eski "envanter" Supabase projesi.** Bu depoya ait değildir. Silme kalıcıdır; yalnızca sahip yapar. Ajan silmez ve silme komutu yazmaz.
- [x] **İade ve iptal bildirimleri (App Store Server Notifications V2).** Uç nokta yazıldı (`functions/app-store-notifications`, migrasyon 1.10). Kalan: yayımlama (§5) ve adresin RevenueCat'in "Apple Server Notification Forwarding URL" alanına girilmesi (App Store Connect RevenueCat'i göstermeye devam eder; SAHIP 2.14).
- [ ] **Paylaşılan adres eşiği.** Doğrulanmamış bir adresten üç uyarı, o adresteki herkesi bekletir. Adres anahtarları için eşik yükseltilecek mi? Karar: SAHIP 5.3.
- [ ] **Deneme kredilerinin devri (trial roll-in).** Yıllık planın 7 günlük denemesinde kullanılmayan 20 kredi ilk ücretli aya eklensin mi? Karar: SAHIP 5.1.
