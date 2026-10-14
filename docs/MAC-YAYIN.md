# Aybuke 1.0: Mac'te yayın rehberi

Bu dosya, Aybuke 1.0'ı senin Mac'inden canlıya alıp App Store'a göndermek için gereken her komutu sırayla verir. İki yol var: (A) en alttaki tek promptu Claude Code'a bypass modunda ver, o bu dosyayı adım adım uygulasın; (B) komutları bölüm bölüm kendin çalıştır. İki yolda da "Submit for Review" düğmesine en sonda sen basarsın.

Kurallar: anahtar, şifre, `.p8` içeriği, service role anahtarı ve veritabanı adresi hiçbir dosyaya, commit'e ya da sohbete yazılmaz. Gizli değerler yalnızca terminal değişkenine (`read -s`) ya da ilgili panele girilir. Canlı veritabanında silme, `drop`, `truncate` ya da `db reset` yapılmaz.

Her terminal penceresinde önce şunu çalıştır (zsh'de `#` yorum satırları yapıştırılınca hata vermesin):

```zsh
setopt interactivecomments
```

## 0) Başlamadan önce (yalnızca sen)

1. **xAI.** Kredi yüklendi (14 Ekim, 10 USD); console.x.ai'de aylık harcama limiti koy. Sohbete bir kez yapıştırılmış eski anahtar güvenli değil: yeni bir anahtar oluştur, Supabase panelinde (proje `efapupjvidyqhqdevmcu` › Edge Functions › Secrets) `XAI_API_KEY` değerini yenisiyle değiştir. Eski anahtarı, ilk gerçek AI işi çalıştıktan sonra (12. bölüm) xAI'de iptal et. Ekip ayarlarında Zero Data Retention'ın açık olduğunu doğrula; gizlilik metinleri bunu söylüyor.
2. **Supabase.** Projenin sahibi olan hesapla giriş yapabildiğini ve veritabanı şifresini bildiğini kontrol et (bilmiyorsan Project Settings › Database'den sıfırlanabilir; Edge Functions bu şifreyi kullanmaz).
3. **App Store Connect.** Agreements, Tax, and Banking'de Paid Apps sözleşmesi, banka ve vergi bilgileri "Active" olmalı; yoksa satın almalar incelemeye giremez. Users and Access › Integrations › App Store Connect API'de **Admin** rolünde bir anahtar oluştur (otomatik imzalama için gerekir), `.p8` dosyasını indir.
4. **AdMob (isteğe bağlı).** Geçiş reklamı istiyorsan "After save interstitial" adında bir geçiş birimi oluştur (sıklık sınırı kullanıcı başına günde 3) ve kimliğini hazır tut. Boş kalırsa 1.0'da geçiş reklamı olmaz; bu da geçerli bir karar.
5. **Mac.** En az 15 GB boş disk, Xcode 26 veya daha yenisi, Homebrew. Mac penceresi yakalamak için Terminal'e (ya da kullandığın terminale) ekran kaydı izni ver: System Settings › Privacy & Security › Screen & System Audio Recording.

## 1) Depoyu Downloads klasörüne indir

```zsh
setopt interactivecomments
# GitHub girişi (bir kez). Depo özelse bu gerekir.
brew install gh
gh auth status || gh auth login

# İlk kez: Downloads klasörüne klonla
gh repo clone RiosenBeq/aybuke-app ~/Downloads/aybuke-app -- --branch pink-girls-redesign
cd ~/Downloads/aybuke-app

# Daha önce klonladıysan: yalnızca ileri sar
git fetch origin --prune
git switch pink-girls-redesign
git pull --ff-only origin pink-girls-redesign
git merge-base --is-ancestor origin/main HEAD && echo "OK: dal main'i içeriyor" || echo "DUR: main'de dalda olmayan commit var"
git log --oneline -5
ls backend/supabase/functions/app-store-notifications/index.ts backend/supabase/migrations/2026102500000{0,1,2,3}_*.sql
```

**Beklenen:** `ls` dört migrasyonu ve fonksiyonu listeler, "OK" satırı görünür. Hiçbir zaman `--force`, `reset --hard` ya da `rebase` kullanma.

## 2) Araçlar

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
xcode-select -p
xcodebuild -version              # Xcode 26.x olmalı
xcodebuild -checkFirstLaunchStatus || sudo xcodebuild -runFirstLaunch
df -h /System/Volumes/Data       # Avail en az 15G

brew update
brew install deno supabase/tap/supabase postgresql@16 jq python
grep -q 'opt/postgresql@16/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
deno --version                   # 2.x olmalı (CI deno v2.x kullanır)
supabase --version
psql --version                   # 16.x
command -v initdb pg_ctl pg_isready psql

# Görsel ve App Store Connect betikleri için Python ortamı (depo dışında)
/opt/homebrew/bin/python3 -m venv ~/.venvs/aybuke
~/.venvs/aybuke/bin/python -m pip install --upgrade pip
~/.venvs/aybuke/bin/python -m pip install Pillow requests cryptography
```

**Hata olursa:** `xcode-select` CommandLineTools gösteriyorsa `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Lisans uyarısında `sudo xcodebuild -license accept`. Deno 3.x geldiyse dur: CI 2.x kullanıyor, 2.x kur.

## 3) Kontroller (CI ile aynı)

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

# AppCore testleri (CI=true: paylaşılan dosya eksikse test atlanmaz, başarısız olur)
CI=true swift test --package-path ios/Packages/AppCore

# Edge Functions: biçim, lint, tip ve testler
(cd backend/supabase/functions && deno fmt --check && deno lint && deno check ai-image/index.ts credits-redeem/index.ts account/index.ts report/index.ts ad-reward/index.ts app-store-notifications/index.ts && deno test _shared/ ad-reward/ app-store-notifications/)

# SQL testleri: geçici bir PostgreSQL 16 açar, bitince siler; canlı projeye dokunmaz
PG_BIN="$(brew --prefix postgresql@16)/bin" backend/scripts/test-db.sh && echo "SQL tests OK"

# Belge ve sayı kontrolleri
python3 scripts/build-legal.py --check
python3 scripts/export-core-strings.py --check
python3 scripts/check-honest-copy.py
python3 scripts/check-credit-policy.py
python3 scripts/check-release-config.py --report
git status --short               # boş olmalı
```

**Beklenen:** `Executed N tests, with 0 failures`; Deno `ok | N passed | 0 failed`; SQL'de her grup "tests passed" ve sonunda "SQL tests OK"; Python kontrolleri "up to date", "passed", "Credit numbers agree". `--report` yalnızca geçiş reklamı birimi boş notunu verebilir.

**Hata olursa:** port doluysa `PGPORT_TEST=55433` ekleyip yeniden çalıştır. Kod hatası çıkarsa çıktıyı Claude Code'a ver; testleri ya da uygulanmış migrasyonları elle değiştirme.

## 4) Derlemeler (iPhone simülatörü, Release iOS, Mac Catalyst)

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
mkdir -p build/logs
xcrun simctl list devices available | grep -E 'iPhone 17 Pro Max|iPad Pro 13-inch|iPhone 17e'
IPHONE=50703265-82EF-4CFE-B094-47FFB43025B0     # bu Mac'te yoksa yukarıdaki listeden iPhone 17 Pro Max kimliğini yaz
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination "id=$IPHONE" -derivedDataPath build/DerivedData -quiet > build/logs/ios-sim.log 2>&1 && echo "SIM BUILD OK" || echo "SIM BUILD FAILED"
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet > build/logs/ios-release.log 2>&1 && echo "RELEASE BUILD OK" || echo "RELEASE BUILD FAILED"
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug -destination 'generic/platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet > build/logs/mac.log 2>&1 && echo "MAC BUILD OK" || echo "MAC BUILD FAILED"
grep -hE ': (error|warning): ' build/logs/*.log | sort -u
```

**Beklenen:** üç "OK" satırı; son `grep` boş ya da yalnızca uyarı. İlk derleme paketleri indirir ve birkaç dakika sürer.

## 5) Backend'i canlıya al (Supabase, proje `efapupjvidyqhqdevmcu`)

Sıra önemli: önce migrasyonlar, sonra gizli değerler, sonra fonksiyonlar. Ayrıntı ve gerekçeler: [`SUPABASE-TODO.md`](SUPABASE-TODO.md).

### 5.1 Giriş ve veritabanı adresi

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
supabase login
supabase projects list | grep -q efapupjvidyqhqdevmcu && echo "access ok" || echo "proje bu hesapta görünmüyor"

# Panel: proje › Connect › Connection string › Session pooler. URI'yi [YOUR-PASSWORD] yer tutucusuyla kopyala.
read -r "TEMPLATE?Session pooler URI ([YOUR-PASSWORD] ile): "
read -rs "DBPW?Veritabanı şifresi: "; echo
export SUPABASE_DB_URL="$(TEMPLATE="$TEMPLATE" DBPW="$DBPW" python3 -c 'import os, urllib.parse as u; print(os.environ["TEMPLATE"].replace("[YOUR-PASSWORD]", u.quote(os.environ["DBPW"], safe="")))')"
unset DBPW TEMPLATE
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -tA -c "select current_user, current_database();"
```

**Beklenen:** "access ok" ve `postgres|postgres`. Adresi ekrana yazdırma; `set -x` kullanma.

### 5.2 Canlıda hangi migrasyonlar var

```zsh
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
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
union all select 'private.ai_usage_daily RLS (20261024000000)', coalesce((select rowsecurity from pg_tables where schemaname = 'private' and tablename = 'ai_usage_daily'), false)
union all select 'admit_job abuse fixes (20261024000001)', exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admit_job' and p.prosrc like '%v_abuse%')
union all select 'public.record_entitlement() (20261024000002)', to_regprocedure('public.record_entitlement(uuid, text, text, timestamptz, boolean, text, boolean)') is not null
union all select 'private.app_store_notifications (20261025000000)', to_regclass('private.app_store_notifications') is not null
union all select 'public.wallet_state 5 args (20261025000001)', to_regprocedure('public.wallet_state(uuid, text, text, text, text)') is not null
union all select 'private.refunded_transactions (20261025000002)', to_regclass('private.refunded_transactions') is not null
union all select 'prune skip locked (20261025000003)', exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'record_app_store_notification' and p.prosrc like '%skip locked%');
select extname, extversion from pg_extension where extname in ('pg_cron', 'pg_net', 'supabase_vault') order by 1;
SQL
```

**Beklenen:** her satırda `t` ya da `f`. `f` olan dosyalar 5.3'teki listeye girer. Son sorgu `pg_cron`, `pg_net` ve `supabase_vault`'u göstermeli; eksik olanı Database › Extensions'tan aç.

### 5.3 Eksik migrasyonları sırayla uygula

Her dosya kendi transaction'ında çalışır (`-1`); hata olursa o dosya tamamen geri alınır ve döngü durur. Listeyi 5.2'deki `f` satırlarına göre düzenle; uygulanmış bir dosyayı asla yeniden çalıştırma. `supabase db push` kullanma (psql CLI'nin geçmiş tablosunu yazmaz).

```zsh
ls -1 backend/supabase/migrations
# LİSTEYİ DÜZENLE: yalnızca 5.2'de f olanlar, eskiden yeniye.
apply=(
  20261019000000_ad_rewards.sql
  20261020000000_credit_policy_v2.sql
  20261021000000_install_and_subscription_credits.sql
  20261022000000_abuse_controls.sql
  20261023000000_ad_rewards_per_install.sql
  20261024000000_private_rls.sql
  20261024000001_abuse_fixes.sql
  20261024000002_entitlement_order.sql
  20261025000000_app_store_notifications.sql
  20261025000001_sql_gaps.sql
  20261025000002_refunded_transactions.sql
  20261025000003_notification_prune.sql
)
for f in "${apply[@]}"; do
  p="backend/supabase/migrations/$f"
  [[ -f "$p" ]] || { echo "dosya yok: $p"; break; }
  echo "== $f"
  if ! psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -1 -f "$p"; then
    echo "DURDU: $f geri alındı, sonrakiler çalışmadı. Hata metnini sakla, dosyayı değiştirme."
    break
  fi
done

# Sonra: 5.2'yi yeniden çalıştır (hepsi t olmalı) ve sayıları kontrol et
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
select free_daily, pro_monthly, pro_rollover_cap, trial_credits, free_retries_daily from public.credit_policy();
select * from public.ad_reward_policy();
notify pgrst, 'reload schema';
SQL
```

**Beklenen:** "DURDU" satırı yok. `credit_policy`: 2 | 80 | 160 | 20 | 3. `ad_reward_policy`: günlük sınır 2, kredi 1.

**Hata olursa:** "already exists" o dosyanın zaten uygulandığını gösterir: listeden çıkar. Başka bir hata için dosyayı düzenleme; Claude Code yeni tarihli bir migrasyonla düzeltir.

### 5.4 Gizli değerler (yalnızca adlar kontrol edilir)

```zsh
# Herkese açık kimlikler; burada gizli değer yok
supabase secrets set --project-ref efapupjvidyqhqdevmcu \
  ADMOB_REWARDED_AD_UNIT=ca-app-pub-2292230772061554/1406702504 \
  APPLE_APP_ID=6822716008 \
  APPLE_BUNDLE_ID=app.glowlit.ios \
  APPLE_TEAM_ID=CBTKNY3LFC

secrets=$(supabase secrets list --project-ref efapupjvidyqhqdevmcu)
for n in XAI_API_KEY APPLE_APP_ID APPLE_BUNDLE_ID APPLE_TEAM_ID ADMOB_REWARDED_AD_UNIT; do
  printf '%s\n' "$secrets" | grep -qw "$n" && echo "var    $n" || echo "EKSİK  $n"
done
for n in GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS OUTPUT_MODERATION FAL_KEY XAI_SAFETY_MODEL; do
  printf '%s\n' "$secrets" | grep -qw "$n" && echo "KALDIR $n" || echo "yok    $n (doğru)"
done
unset secrets
# Yalnızca KALDIR yazanlar için (adları tek tek yaz):
# supabase secrets unset --project-ref efapupjvidyqhqdevmcu GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS
```

`XAI_API_KEY` panelden girilir (0. bölüm). `FAL_KEY` ve `XAI_SAFETY_MODEL` bu sürümde girilmez.

### 5.5 Altı fonksiyonu yayımla

```zsh
supabase functions deploy --help | grep -E -- '--(use-api|no-verify-jwt|project-ref)'
pushd backend
supabase functions deploy ai-image --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy credits-redeem --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy account --project-ref efapupjvidyqhqdevmcu --use-api
supabase functions deploy report --project-ref efapupjvidyqhqdevmcu --use-api
# AdMob ve Apple JWT göndermez; bu iki fonksiyon imzayı kendisi denetler
supabase functions deploy ad-reward --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
supabase functions deploy app-store-notifications --project-ref efapupjvidyqhqdevmcu --use-api --no-verify-jwt
popd
supabase functions list --project-ref efapupjvidyqhqdevmcu

BASE=$(jq -r .backendBaseURL ios/App/Resources/AppConfig.json)
curl -sS -o /dev/null -w 'app-store-notifications: %{http_code} (400 beklenir)\n' -X POST "$BASE/functions/v1/app-store-notifications" -H 'Content-Type: application/json' -d '{}'
curl -sS "$BASE/functions/v1/ad-reward" | jq -c .
```

**Beklenen:** altı fonksiyon ACTIVE; ilk `curl` 400, ikincisi fonksiyonun kendi `{"error":{"code":"unauthorized",…}}` yanıtı.

**Hata olursa:** `--use-api` yoksa `brew upgrade supabase`; hâlâ yoksa Docker Desktop'ı açıp aynı komutları `--use-api` olmadan çalıştır. 401 alırsan o fonksiyonu `--no-verify-jwt` ile yeniden yayımla.

### 5.6 Zamanlanmış işler

```zsh
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -c "select jobname, schedule, active from cron.job order by jobname;"
# Yalnızca listede OLMAYANLARI ekle (aynı adla eklemek mevcut işi değiştirir):
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -c "select cron.schedule('sweep-jobs', '*/5 * * * *', 'select public.sweep_jobs()');"
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -c "select cron.schedule('sweep-ad-rewards', '17 * * * *', 'select public.sweep_ad_rewards()');"
# App Store bildirim kayıtları 30 günden sonra silinir (gizlilik metni bunu söyler)
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
select cron.schedule('sweep-app-store-notifications', '23 3 * * *', $$delete from private.app_store_notifications where received_at < now() - interval '30 days'$$);
SQL
```

`revenuecat-deletions` işi Vault'ta `project_url` ve `service_role_key` ister; komutlar [`SUPABASE-TODO.md`](SUPABASE-TODO.md) §3'te. Service role anahtarını panelin SQL Editor'ünde ya da `read -rs` ile gir; ekrana yazdırma. RevenueCat anahtarı olmadan da lansman yapılabilir (silmeler kuyrukta bekler).

### 5.7 Güvenlik ve kimlik doğrulama

```zsh
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
select p.oid::regprocedure as fn,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
select schemaname, tablename, rowsecurity from pg_tables where schemaname in ('public', 'private') and not rowsecurity;
SQL
```

**Beklenen:** ilk sorgu tek satır (`keepalive()`, anon `t`, authenticated `f`); ikinci sorgu boş.

Panelde (Authentication): Anonymous sign-ins **açık**, anonim giriş sınırı saatte IP başına 15, Email sağlayıcısı **kapalı**, CAPTCHA **kapalı**. Advisors › Security Advisor'da "function search path mutable" ya da RLS kapalı bulgusu olmamalı (yalnızca `keepalive()` bilinçli bir istisna).

### 5.8 Duman testi (anonim kullanıcı → bakiye → hesabı sil)

```zsh
BASE=$(jq -r .backendBaseURL ios/App/Resources/AppConfig.json)
ANON=$(jq -r .supabaseAnonKey ios/App/Resources/AppConfig.json)
SIGNUP=$(curl -sS -X POST "$BASE/auth/v1/signup" -H "apikey: $ANON" -H 'Content-Type: application/json' -d '{}')
TOKEN=$(printf '%s' "$SIGNUP" | jq -r '.access_token // empty')
USER_ID=$(printf '%s' "$SIGNUP" | jq -r '.user.id // empty')
unset SIGNUP
[[ -n "$TOKEN" ]] && echo "anonim giriş ok" || echo "anonim giriş BAŞARISIZ (5.7 ayarları)"
curl -sS "$BASE/functions/v1/ai-image" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" | jq .
curl -sS -X DELETE "$BASE/functions/v1/account" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" | jq -c .
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -v uid="$USER_ID" -c "select count(*) as kalan_kullanici from auth.users where id = :'uid'::uuid;"
unset TOKEN USER_ID
```

**Beklenen:** bakiye yanıtı `credits_remaining: 0`, `free_credits: "unverified"` (App Store kurulumu kanıtı olmadan ücretsiz kredi yok; TestFlight'ta 2 görünür), `ai_status: "ok"`; silme `{"deleted":true}`; `kalan_kullanici` 0.

## 6) Konsollar: AdMob ve App Store bildirimleri (yalnızca panel)

1. **AdMob** › Apps › Aybuke › Ad units › ödüllü birim `ca-app-pub-2292230772061554/1406702504` (ödül 1, öğe `credit`) › Server-side verification: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/ad-reward` (sorgu dizesi yok) › **Verify URL**. Beklenen: başarılı (test çağrısı kredi vermez).
2. **AdMob** › Blocking controls › Sensitive categories: flört, kumar, alkol, kilo verme ve diğer hassas kategorileri engelle. Privacy & messaging: AB, Birleşik Krallık ve İsviçre için GDPR mesajı. Uygulama adı "Aybuke" olsun.
3. **Geçiş reklamı birimi** oluşturduysan kimliğini Claude Code'a ver: `ios/App/Resources/AppConfig.json` › `ads.interstitialUnitID` alanına yazılır, kontroller yeniden çalışır, commit'lenir.
4. **App Store Connect** › Apps › Aybuke › App Information › App Store Server Notifications: **Version 2**; Production Server URL ve Sandbox Server URL: `https://efapupjvidyqhqdevmcu.supabase.co/functions/v1/app-store-notifications`. Kaydet; varsa "Send Test Notification". Kontrol:

```zsh
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -c "select notification_type, environment, action, outcome, received_at from private.app_store_notifications order by received_at desc limit 5;"
```

**Beklenen:** `TEST` türünde bir satır, `outcome` `ignored`.

## 7) Mac penceresi ve büyük metin kontrolü

### 7.1 Mac uygulamasını imzasız (ad hoc) çalıştır

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
SCR=$(mktemp -d)
cp ios/Config/Glowlit-macOS.entitlements "$SCR/mac.entitlements"
for k in com.apple.security.application-groups com.apple.developer.applesignin com.apple.developer.declared-age-range; do
  /usr/libexec/PlistBuddy -c "Delete :$k" "$SCR/mac.entitlements" 2>/dev/null
done
xcodebuild build -project ios/Glowlit.xcodeproj -scheme Glowlit -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="$SCR/mac.entitlements" \
  "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]=$SCR/mac.entitlements" -quiet && echo "MAC AD HOC OK"
MACAPP=build/DerivedData/Build/Products/Debug-maccatalyst/Glowlit.app

# Pencere kimliği bulucu (Screen Recording izni gerekir)
cat > "$SCR/winid.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where ["Aybuke", "Glowlit"].contains(w[kCGWindowOwnerName as String] as? String ?? "") && (w[kCGWindowLayer as String] as? Int ?? 1) == 0 {
    print(w[kCGWindowNumber as String] as! Int); break
}
SWIFT

# Örnek fotoğraflar sandbox kabına kopyalanır (uygulama bir kez açılınca kap oluşur)
open -n "$MACAPP" --args -GLScreenshotScene home; sleep 6; pkill -x Glowlit
SAMPLES="$HOME/Library/Containers/app.glowlit.ios/Data/Library/Caches/samples"
mkdir -p "$SAMPLES" && cp docs/marketing/samples/*.jpg "$SAMPLES/"

macshot() {  # macshot <sahne ve argümanlar> <WxH> <çıktı.png> [dil]
  local args=$1 size=$2 out=$3 lang=${4:-en}
  pkill -x Glowlit 2>/dev/null; sleep 1
  open -n "$MACAPP" --args -GLScreenshotScene ${=args} -GLWindowSize "$size" -GLSamplePhotos "$SAMPLES" -AppleLanguages "($lang)"
  sleep 8
  local id=$(swift "$SCR/winid.swift")
  [[ -n "$id" ]] && screencapture -x -o -l "$id" "$out" || echo "pencere bulunamadı: $args"
}
mkdir -p ~/Desktop/aybuke-mac-check
for size in 900x640 1600x1000 2200x1400; do
  for scene in home create "editor -GLEditorTool styles" library settings; do
    macshot "$scene" "$size" ~/Desktop/aybuke-mac-check/${size}-${scene%% *}.png
  done
done
pkill -x Glowlit
open ~/Desktop/aybuke-mac-check
```

Bak: her şablon kartı çiziliyor mu, metin kesiliyor mu, kenar çubuğu ve File menüsü çalışıyor mu, tam pencere ekranlarda araç çubuğu gizleniyor mu. ⌘W editörde ve Retro Cam'de kapatıyor mu, şablon kartında sağ tık "Try this look" gösteriyor mu. Sorunları Claude Code'a ver. Geçici imza dosyası (`$SCR`) depoya girmez.

### 7.2 Büyük metin taraması (iPhone 17e)

```zsh
SMALL=$(xcrun simctl list devices available | grep -m1 'iPhone 17e' | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$SMALL" 2>/dev/null; xcrun simctl bootstatus "$SMALL" -b
xcrun simctl install "$SMALL" build/DerivedData/Build/Products/Debug-iphonesimulator/Glowlit.app
xcrun simctl ui "$SMALL" content_size accessibility-extra-extra-extra-large
mkdir -p ~/Desktop/aybuke-large-text
for lang in en de ru; do
  for scene in home create editor library paywall settings; do
    xcrun simctl terminate "$SMALL" app.glowlit.ios 2>/dev/null
    xcrun simctl launch "$SMALL" app.glowlit.ios -GLScreenshotScene "$scene" -AppleLanguages "($lang)" >/dev/null
    sleep 8
    xcrun simctl io "$SMALL" screenshot ~/Desktop/aybuke-large-text/$lang-$scene.png
  done
done
xcrun simctl ui "$SMALL" content_size large
open ~/Desktop/aybuke-large-text
```

Kesilen ya da üst üste binen metinleri not et ve Claude Code'a ver.

## 8) App Store ekran görüntüleri (12 dil)

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
REPO=$PWD
CAP=~/Desktop/aybuke-captures
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Glowlit.app
IPHONE=50703265-82EF-4CFE-B094-47FFB43025B0   # iPhone 17 Pro Max (bu Mac'te farklıysa 4. bölümdeki listeden)
IPAD=0ADBB7F6-481C-4F00-AFD0-182E32E685E2     # iPad Pro 13-inch (M5)
langs=(en tr es pt-BR fr de it ru ja ko zh-Hans id)
typeset -A loc=(en en_US tr tr_TR es es_ES pt-BR pt_BR fr fr_FR de de_DE it it_IT ru ru_RU ja ja_JP ko ko_KR zh-Hans zh_CN id id_ID)
typeset -A scenes=(
  result result
  makeup "editor -GLEditorTool makeup"
  home home
  effects effects
  textStickers textStickers
  create create
  share-cover "share -GLShareFormat cover"
  collage collage
  consent consent
  paywall paywall
)
prep() {
  xcrun simctl boot "$1" 2>/dev/null; xcrun simctl bootstatus "$1" -b
  xcrun simctl status_bar "$1" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$1" content_size large
  xcrun simctl install "$1" "$APP"
}
shoot() {  # shoot <udid> <çıktı klasörü>
  local udid=$1 out=$2 lang name
  for lang in $langs; do
    mkdir -p "$out/$lang"
    for name in ${(k)scenes}; do
      xcrun simctl terminate "$udid" app.glowlit.ios 2>/dev/null
      xcrun simctl launch "$udid" app.glowlit.ios -GLScreenshotScene ${=scenes[$name]} \
        -GLSamplePhotos "$REPO/docs/marketing/samples" -AppleLanguages "($lang)" -AppleLocale "${loc[$lang]}" >/dev/null
      sleep 8
      xcrun simctl io "$udid" screenshot "$out/$lang/$name.png"
    done
  done
}
prep "$IPHONE"; shoot "$IPHONE" "$CAP"
prep "$IPAD";   shoot "$IPAD"   "$CAP/ipad"

# Mac seti (7.1'deki macshot fonksiyonu ve $SAMPLES ile, aynı terminalde)
typeset -A macscenes=(home home makeup "editor -GLEditorTool makeup" result result create create effects effects share-cover "share -GLShareFormat cover" cutout cutout hideFaces hideFaces)
for lang in $langs; do
  mkdir -p "$CAP/mac/$lang"
  for name in ${(k)macscenes}; do macshot "${macscenes[$name]}" 1600x1000 "$CAP/mac/$lang/$name.png" "$lang"; done
done
pkill -x Glowlit

# Görselleri üret (Pillow gerekir)
~/.venvs/aybuke/bin/python scripts/marketing-images.py "$CAP"
open docs/marketing/app-store
```

Her görsele bak: kredi sayısı yok, metin kesilmemiş, doğru dil, yer tutucu yok. Sonra:

```zsh
git add docs/marketing/app-store
git commit -m "Add the App Store screenshots in 12 languages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin pink-girls-redesign
```

## 9) Derlemeleri yükle

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
mkdir -p ~/.appstoreconnect/private_keys
# İndirdiğin AuthKey_<KEY_ID>.p8 dosyasını oraya taşı (içeriğini açıp kopyalama)
mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/ 2>/dev/null
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
read -r "ASC_KEY_ID?API Key ID: ";  export ASC_KEY_ID
read -r "ASC_ISSUER_ID?Issuer ID: "; export ASC_ISSUER_ID
ls ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8

python3 scripts/check-release-config.py --online   # yayın engeli yoksa "passed"
scripts/upload-app-store.sh                        # iOS
PLATFORM=mac scripts/upload-app-store.sh           # Mac (aynı kayda)
```

**Beklenen:** her biri "Uploaded Aybuke … build <tarih.saat>" ile biter; işlenmesi 10–30 dakika sürer (App Store Connect › TestFlight). `GL_PREVIEW_BUILD=1` ile yüklenen bir derlemeyi asla incelemeye gönderme. Şifreleme sorusu çıkmaz (`ITSAppUsesNonExemptEncryption` false).

**Hata olursa:** `--online` bir adresin açılmadığını söylerse 11. bölüme bak. Disk dolarsa `rm -rf build/DerivedData build/app-store build/app-store-mac` ve `xcrun simctl delete unavailable`.

## 10) App Store Connect

### 10.1 API ile (aynı terminalde, `ASC_KEY_ID` ve `ASC_ISSUER_ID` tanımlı)

```zsh
cd ~/Downloads/aybuke-app/scripts/asc
# Metinler (13 dil) ve ekran görüntüleri: önce deneme, sonra gerçek
~/.venvs/aybuke/bin/python asc_metadata.py ../.. --dry-run
~/.venvs/aybuke/bin/python asc_metadata.py ../..
~/.venvs/aybuke/bin/python asc_screenshots.py ../.. --dry-run
~/.venvs/aybuke/bin/python asc_screenshots.py ../.. --platform=ios
~/.venvs/aybuke/bin/python asc_screenshots.py ../.. --platform=mac

# İşlenmiş derlemeyi sürüme bağla; telif, manuel yayın ve adresler
~/.venvs/aybuke/bin/python - <<'PY'
import asc
APP = "6822716008"
for platform in ("IOS", "MAC_OS"):
    versions = asc.get(f"/v1/apps/{APP}/appStoreVersions", **{"filter[platform]": platform, "filter[versionString]": "1.0"})["data"]
    if not versions:
        print(platform, "1.0 sürümü yok"); continue
    vid = versions[0]["id"]
    builds = asc.get("/v1/builds", **{"filter[app]": APP, "filter[preReleaseVersion.platform]": platform,
                                      "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": "1"})["data"]
    if builds:
        asc.patch(f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": builds[0]["id"]}})
        print(platform, "derleme bağlandı:", builds[0]["attributes"]["version"])
    else:
        print(platform, "işlenmiş derleme yok, biraz sonra yeniden çalıştır")
    asc.patch(f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid,
              "attributes": {"copyright": "2026 Okan Berk Manavoğlu", "releaseType": "MANUAL"}}})
    locs, _ = asc.get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    for loc in locs:
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                  "attributes": {"supportUrl": "https://aybuke.org/support", "marketingUrl": "https://aybuke.org"}}})
    print(platform, "telif, manuel yayın ve", len(locs), "dilde adresler yazıldı")
infos = asc.get(f"/v1/apps/{APP}/appInfos")["data"]
for info in infos:
    locs, _ = asc.get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")
    for loc in locs:
        url = "https://aybuke.org/legal/tr/gizlilik-politikasi" if loc["attributes"]["locale"].startswith("tr") else "https://aybuke.org/legal/en/privacy-policy"
        asc.patch(f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"privacyPolicyUrl": url}}})
print("gizlilik adresleri yazıldı")
PY
```

`https://aybuke.org/support` açılmıyorsa (11. bölüm) `supportUrl` için `https://aybuke.org` kullan. Mac açıklaması Lock Screen, Dynamic Island, Live Activity, Instagram Stories ve reklamlardan söz etmemeli; `asc_metadata.py` Mac metnini ayrı yazar, panelde bir kez göz at.

### 10.2 Panelde (yalnızca sen)

| Ne | Nerede | Ne girilir |
|---|---|---|
| Satın almalar sürüme | iOS 1.0 sayfası › In-App Purchases and Subscriptions | `app.glowlit.pro.yearly`, `app.glowlit.pro.monthly`, `app.glowlit.credits.30`, `app.glowlit.credits.100`; her birinde inceleme ekran görüntüsü (`docs/marketing/app-store/en/09-paywall.jpg`) ve not |
| App Privacy | App Privacy | [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md) §11 ve [`SAHIP-YAPILACAKLAR.md`](SAHIP-YAPILACAKLAR.md) 2.7: kurulum hash'i ve e-posta kararını ver; reklam için "Third-Party Advertising" (izleme yok) |
| Yaş derecelendirmesi | App Information › Age Rating | 13+; Advertising işaretli; Age Assurance kararı (SAHIP 2.8) |
| İade bildirimleri | App Information › App Store Server Notifications | 6. bölüm, 4. madde |
| İnceleme bilgisi | Sürüm sayfası › App Review Information | Giriş gerekmez; iletişim bilgileri; not metni [`marketing/app-store-listing.md`](marketing/app-store-listing.md) ve [`marketing/app-store-connect-setup.md`](marketing/app-store-connect-setup.md): ilk bulut işinde anonim hesap, önce onay ekranı (Supabase ve xAI), Makeup Studio, reklam yalnızca 13+ ücretsiz üyeler (kişiselleştirilmemiş; Pro, 13 yaş altı ve Mac'te yok), ücretsiz kredi App Store kurulumuna bağlı (Sandbox kabul edilir), Apple ile giriş bu sürümde gizli, satın almalar ve sandbox notu, güvenlik katmanları ve bildirme, Verilerimi sil, Mac farkları |
| Ülkeler | Pricing and Availability | Çin anakarası hariç |
| Mac | macOS 1.0 sayfası | Mac ekran görüntüleri ve Mac açıklaması |
| Abonelik açıklaması | Abonelik grubu "Aybuke Pro" | "80 kredi" sayısı kalsın mı kararı (SAHIP 2.6) |

## 11) Web sitesi ve arama

```zsh
for u in https://aybuke.org https://aybuke.org/support https://aybuke.org/legal/en/privacy-policy https://aybuke.org/legal/en/terms-of-use https://aybuke.org/legal/tr/gizlilik-politikasi https://aybuke.org/legal/en/privacy-policy.html; do
  printf '%s  %s\n' "$(curl -s -o /dev/null -L -w '%{http_code}' "$u")" "$u"
done
curl -s https://aybuke.org/app-ads.txt | grep -F 'google.com, pub-2292230772061554, DIRECT, f08c47fec0942fa0' && echo "app-ads.txt ok"
python3 ~/Downloads/aybuke-app/scripts/check-release-config.py --online
```

**Beklenen:** hepsi 200 ve "app-ads.txt ok". Sonra Google Search Console › aybuke.org › Sitemaps'te site haritasını yeniden gönder. IndexNow bildirimi web sitesi deposundaki (`RiosenBeq/aybuke`, `public/`) anahtar dosyasıyla yapılır; Claude Code bunu yapabilir.

## 12) TestFlight'ta son kontrol

TestFlight'tan iPhone'a kur (temiz kurulum):
- Bakiye ilk denemeden önce **2 ücretsiz kredi** gösterir.
- Bir Magic Edit gerçek sonuç verir, "DEMO PREVIEW" damgası ve "Preview build" bandı yoktur.
- Sandbox hesabıyla bir kredi paketi alınır; bakiye artar (`select kind, purchased, created_at from public.credit_ledger order by created_at desc limit 5;`).
- Ödüllü reklam (kredin bitince) izlenir; kredi yalnızca AdMob'un geri çağrısından sonra gelir.
- Mümkünse sandbox iadesi: Pro ya da paket hemen kalkar (`private.app_store_notifications` tablosunda `REFUND`, `applied`).

Ardından eski xAI anahtarını iptal et (0. bölüm). Ayrıntılı test listesi: [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md).

## 13) Gönder ve yayınla (sen)

1. App Store Connect › Aybuke › iOS 1.0: derleme bağlı, satın almalar ekli, metinler ve görseller tamam → **Add for Review** → **Submit for Review**. İlk abonelikler ve paketler sürümle birlikte incelemeye gider.
2. macOS 1.0 için aynısı.
3. Onay gelince (yayın türü manuel) **Release This Version**.
4. Ret gelirse App Review'un Resolution Center mesajını Claude Code'a ver; düzeltme yeni bir derleme ve yükleme ister.

## 14) Sorun çıkarsa

| Belirti | Bak |
|---|---|
| Migrasyon "DURDU" | Hata metnini sakla, dosyayı değiştirme; yeni migrasyon yazılır |
| Bakiye 500 "Couldn't load your credits" | 5.2'de `20261025000001` satırı `t` mi; `notify pgrst, 'reload schema';` |
| Fonksiyon 401 | `--no-verify-jwt` ile yeniden yayımla (ad-reward, app-store-notifications) |
| AdMob doğrulaması 503 | `ADMOB_REWARDED_AD_UNIT` eksik (5.4) |
| Apple bildirimi 400 / 503 | `APPLE_APP_ID` ve `APPLE_BUNDLE_ID` (5.4) |
| Her AI işi başarısız ve iade | xAI kredisi ya da `XAI_API_KEY` (0. bölüm) |
| Yükleme "release blocker" | `check-release-config.py --online` çıktısı; demo modu, yasal yer tutucu ya da açılmayan adres |
| Disk dolu | `rm -rf ~/Library/Developer/Xcode/DerivedData/Glowlit-*(N) build/DerivedData build/app-store build/app-store-mac` ve `xcrun simctl delete unavailable` |

## Claude Code için tek prompt (bypass modu)

**Başlatma:** gizli değerler Claude Code'u başlatmadan önce, aynı terminal penceresinde ortam değişkeni olarak verilir; Claude Code onları bu pencereden devralır ve değerleri hiç görmeden kullanır.

```zsh
setopt interactivecomments
cd ~/Downloads/aybuke-app
git pull --ff-only

# 1) Supabase CLI girişi (tarayıcı açılır)
brew install supabase/tap/supabase
supabase login

# 2) Veritabanı adresi (panel: proje › Connect › Session pooler URI, [YOUR-PASSWORD] yer tutucusuyla)
read -r "TEMPLATE?Session pooler URI: "
read -rs "DBPW?Veritabanı şifresi: "; echo
export SUPABASE_DB_URL="$(TEMPLATE="$TEMPLATE" DBPW="$DBPW" python3 -c 'import os, urllib.parse as u; print(os.environ["TEMPLATE"].replace("[YOUR-PASSWORD]", u.quote(os.environ["DBPW"], safe="")))')"
unset DBPW TEMPLATE

# 3) App Store Connect API anahtarı (.p8 dosyası ~/.appstoreconnect/private_keys/ içinde)
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/ 2>/dev/null
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_*.p8
read -r "ASC_KEY_ID?API Key ID: ";  export ASC_KEY_ID
read -r "ASC_ISSUER_ID?Issuer ID: "; export ASC_ISSUER_ID

# 4) Aynı pencerede Claude Code
claude --dangerously-skip-permissions
```

Sonra aşağıdaki bloğun tamamını yapıştır. 0. bölümdeki hesap işlerini önce kendin yap; gizli değerleri sohbete yazma.

```text
You are finishing Aybuke 1.0 (codename Glowlit) on the owner's Mac and preparing it for App Store review, for iOS and macOS. Repository: this folder (RiosenBeq/aybuke-app, branch pink-girls-redesign). You run with permissions bypassed, so the guardrails below are the only brakes. Follow them exactly. Talk to the owner in Turkish.

Read first: AGENTS.md, docs/MAC-YAYIN.md (the runbook: every command you need, in order), docs/SAHIP-YAPILACAKLAR.md, docs/SUPABASE-TODO.md, docs/RELEASE-CHECKLIST.md, docs/AI-TODO.md, scripts/asc/README.md, backend/README.md (the Abuse runbook).

GUARDRAILS
1. Never print, log, paste or commit a secret: the App Store Connect key (.p8), SUPABASE_DB_URL or its password, any Supabase token, the service role key, the xAI key. Read them only from the environment or the files the owner prepared. Never echo them; never use set -x around commands that read them. When a secret must be typed, ask the owner to type it into a read -s prompt in the terminal, never into the chat.
2. Never submit for review. At the very end ask the owner exactly "Her şey hazır. Gönderelim mi?" with a short Turkish summary, and wait for a clear "evet". Only then submit, iOS and macOS.
3. On the live Supabase project never delete a project, user, table or row, never run db reset, drop or truncate, never edit a published migration, never use supabase db push. Apply only the files in backend/supabase/migrations that the check in docs/MAC-YAYIN.md 5.2 shows missing, each in its own transaction (psql -1 -v ON_ERROR_STOP=1), in order, and stop at the first error. The only delete allowed is the smoke-test user through DELETE /functions/v1/account.
4. Never force-push or rewrite history. Work on pink-girls-redesign, push after every finished step, and fast-forward main only when CI is green on that commit (gh run list / gh run view).
5. Stop and ask the owner in Turkish when a step needs an open decision from docs/SAHIP-YAPILACAKLAR.md section 5, or a console only the owner can use: AdMob, App Privacy, age rating, the App Store Server Notifications URL, In-App Purchases on the version page, Search Console, AdSense. Give the exact menu path and what to enter, then wait until the owner says it is done.
6. Commit messages: imperative summary, short body, and the trailer
   Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

PREFLIGHT (report what is missing in Turkish; never print values)
- docs/MAC-YAYIN.md section 0 done by the owner? Ask once.
- Env ASC_KEY_ID, ASC_ISSUER_ID and the file ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 (only check that they exist).
- supabase projects list shows efapupjvidyqhqdevmcu; SUPABASE_DB_URL set (if not, ask the owner to run the 5.1 block in this terminal session or in a terminal you can read from; never ask for the value in chat).
- Tools from section 2; install what is missing with Homebrew. Free disk of at least 15 GB.
If something is missing, tell the owner which item and continue with the steps that do not need it.

THEN, IN ORDER (each step is a section of docs/MAC-YAYIN.md; run its commands, read the output, fix what fails, commit and push after each step that changed files):
1. Section 1 and 3: sync and every check. Fix failures in code (never weaken a test), commit, push.
2. Section 4: the three builds. Fix every error and every new warning, commit, push. Then check CI on GitHub for that commit.
3. Section 5: backend live (5.1 to 5.8). Report in Turkish which migrations were missing, what you applied, the function list, cron jobs, the security checks and the smoke test.
4. Section 6: ask the owner to do the console steps and to give you the interstitial unit id if they want one. If given, put it in ads.interstitialUnitID in ios/App/Resources/AppConfig.json (it must stay consistent with the checks), run section 3 again, commit, push. Check the App Store notification test row.
5. Section 7: Mac window and large-text checks. Look at every capture yourself. Fix clipped or overlapping text and layout problems in the app, rebuild, recapture, commit, push.
6. Section 8: the screenshots in 12 languages for iPhone, iPad and Mac. Look at every final image (no credit numbers, no clipped text, the right language, no placeholder). Commit and push docs/marketing/app-store.
7. Section 9: upload iOS and macOS builds. Never use GL_PREVIEW_BUILD. Wait for processing.
8. Section 10.1: metadata, screenshots, build, copyright, manual release and URLs through the API (check every URL answers 200 first, section 11). Update the App Review notes text in docs/marketing/app-store-listing.md so it covers every point in the 10.2 table, and give the owner the final notes text to paste. Then walk the owner through every row of the 10.2 table and wait until each is done.
9. Section 11: website checks; ping IndexNow with the key file from the website repository RiosenBeq/aybuke (public/); remind the owner to resubmit the sitemap in Search Console.
10. Section 12: ask the owner to run the TestFlight checks and report back; fix what fails (new build if needed).
11. Docs: tick what is done in docs/RELEASE-CHECKLIST.md, docs/SAHIP-YAPILACAKLAR.md and docs/NEXT-STEPS.md; update AGENTS.md section 6. Commit, push, fast-forward main after CI is green.
12. Ask: send the owner a short Turkish summary (what is live, what was checked, open owner items and open decisions), then ask exactly "Her şey hazır. Gönderelim mi?". Submit iOS and macOS for review only after a clear "evet" (or, if the owner prefers to press the button, tell them section 13).

Open work you may also do when the owner agrees (each needs tests and a green CI): docs/AI-TODO.md section 1 item 5 (independent output check, a draft only; FAL_KEY stays unset) and the residual risks listed in docs/AI-TODO.md section 5.
```
