# Legal documents

Source texts for Glowlit's legal documents, in English (`en/`) and Turkish (`tr/`).

| Document | English | Turkish |
|---|---|---|
| Terms of Use (EULA, subscriptions, credits, Apple terms) | `en/terms-of-use.md` | `tr/kullanim-kosullari.md` |
| Privacy Policy (GDPR, UK GDPR, KVKK, CCPA, teens, children) | `en/privacy-policy.md` | `tr/gizlilik-politikasi.md` |
| Acceptable Use & AI Content Policy | `en/acceptable-use-policy.md` | `tr/kabul-edilebilir-kullanim-politikasi.md` |
| KVKK Information Notice (Aydınlatma Metni) | — | `tr/kvkk-aydinlatma-metni.md` |

> **These are drafts, not legal advice.** They were written against the app's actual data flows (see `docs/04-architecture.md` and `backend/`), but a qualified lawyer must review them before you publish.

## How it works

1. The texts contain `{{TOKENS}}` such as `{{COMPANY_NAME}}`. Their values live in `legal/config.json` (shared values plus English and Turkish ones, because dates and legal phrases differ by language).
2. `python3 scripts/build-legal.py` renders two copies:
   - `ios/App/Resources/Legal/…` — bundled in the app and shown natively, offline, in Settings → Terms, privacy & legal, on the onboarding consent line, the paywall and the AI consent screen;
   - `docs/legal/…` — public copies on GitHub. Use their URLs for App Store Connect (Privacy Policy URL, License Agreement) and `privacyPolicyURL` / `termsURL` in `ios/App/Resources/AppConfig.json` until you host them on your own domain.
3. CI runs `python3 scripts/build-legal.py --check`, so the copies can't drift from the sources.

Markdown rules (the in-app renderer supports a small subset): one `#` title, `##`/`###` headings, paragraphs, `- ` and `1. ` lists, `> ` summaries, `**bold**`, `*italic*` and links. No tables, HTML, images or nested lists.

## Before you publish

1. **Lawyer review** of all seven documents, in both languages.
2. **Fill in `legal/config.json`**: company name, address, MERSİS number, KEP address, EU and UK representatives, hosting region, effective date. Then run `python3 scripts/build-legal.py`.
3. **Data processing agreements** with Supabase, fal.ai and any model provider you call directly (Google, OpenAI), and accept Google's ads data protection terms in the AdMob console (Google acts partly as an independent controller for ads). Keep the sub-processor list (Privacy Policy §12) in sync.
4. **Paid API tiers only.** The policies promise that photos are never used to train AI. Some free tiers (for example the free tier of the Google Gemini API) may use content to improve their products, which would break that promise.
5. **International transfers:** check the EU-US Data Privacy Framework status of each provider and sign Standard Contractual Clauses (plus the UK Addendum) where needed. For Türkiye, sign the KVKK Board's **standard contracts** with each foreign recipient and **notify the Authority within 5 business days**.
6. **VERBİS:** assess whether you must register as a data controller.
7. **Representatives:** appoint an EU representative (GDPR Art. 27) and a UK representative if you have no establishment there.
8. **Teens:** the app is designed for girls and young women, including 13–17-year-olds. Run a DPIA, keep the high-privacy defaults described in Privacy Policy §18, and answer Apple's age-rating questionnaire honestly.
9. **App Store Connect:** make the privacy "nutrition label" match the Privacy Policy (photos, other user content, user ID, purchase history and our rewarded-ad records, used for app functionality, linked to the user; and for Google's ad SDK coarse location, device ID, product interaction, advertising data and performance data for third-party advertising and analytics, not linked; nothing used for tracking; see `docs/marketing/app-store-connect-setup.md` §5), add the Privacy Policy URL, and either upload `terms-of-use` as a custom EULA or rely on Apple's standard EULA plus your Terms.
10. **Publish stable URLs** (your own domain or the GitHub copies) and keep old versions for your records.
11. **Keep the operational promises:** review reports, answer appeals with a human, delete job rows after 30 days and outputs after 1 hour (`sweep_jobs` with pg_cron), delete ad reward records after 30 days (`sweep_ad_rewards`), and keep server logs ≤ 90 days.

---

## Türkçe: Yayınlamadan önce yapılacaklar

Bu klasör, Glowlit'in yasal metinlerinin İngilizce (`en/`) ve Türkçe (`tr/`) kaynaklarını içerir. Metinler uygulamanın gerçek veri akışlarına göre hazırlanmış **taslaklardır**. Yayınlamadan önce mutlaka bir avukata inceletin.

**Nasıl çalışır?** Metinlerdeki `{{COMPANY_NAME}}` benzeri alanların değerleri `legal/config.json` dosyasındadır. `python3 scripts/build-legal.py` komutu metinleri hem uygulamanın içine (`ios/App/Resources/Legal`) hem de GitHub'da herkese açık kopya olarak `docs/legal` klasörüne üretir. CI, bu kopyaların kaynakla aynı olduğunu kontrol eder.

1. **Avukat incelemesi:** yedi belgenin tamamı, her iki dilde.
2. **`legal/config.json` dosyasını doldurun:** şirket unvanı, adres, MERSİS numarası, KEP adresi, AB ve Birleşik Krallık temsilcileri, barındırma bölgesi, yürürlük tarihi. Ardından `python3 scripts/build-legal.py` komutunu çalıştırın.
3. **Veri işleme sözleşmeleri:** Supabase, fal.ai ve doğrudan kullandığınız model sağlayıcılarıyla (Google, OpenAI) imzalayın; AdMob konsolunda Google'ın reklam veri koruma koşullarını kabul edin (Google reklamlar için kısmen bağımsız veri sorumlusudur). Gizlilik Politikası §12'deki alt işleyen listesini güncel tutun.
4. **Yalnızca ücretli API planları:** Metinler fotoğrafların asla yapay zekâ eğitiminde kullanılmayacağını taahhüt eder. Bazı ücretsiz planlar (örneğin Google Gemini API'nin ücretsiz katmanı) içerikleri ürün geliştirmek için kullanabilir. Bu, taahhüdümüzle çelişir.
5. **Yurt dışına aktarım:** Her yabancı alıcıyla Kurul'un ilan ettiği **standart sözleşmeyi** imzalayın ve imzadan sonra **5 iş günü içinde Kurum'a bildirin**. AB tarafı için DPF sertifikasını kontrol edin, gerekirse Standart Sözleşme Hükümlerini (SCC) imzalayın.
6. **VERBİS:** veri sorumluları siciline kayıt yükümlülüğünüzü değerlendirin.
7. **Temsilciler:** AB'de veya Birleşik Krallık'ta yerleşiminiz yoksa GDPR md. 27 kapsamında AB temsilcisi ve Birleşik Krallık temsilcisi atayın.
8. **Gençler:** Uygulama 13–17 yaş arası dahil kızlar ve genç kadınlar için tasarlandı. Veri koruma etki değerlendirmesi (DPIA) yapın, Gizlilik Politikası §18'deki yüksek gizlilik varsayılanlarını koruyun ve Apple'ın yaş derecelendirme anketini dürüstçe yanıtlayın.
9. **App Store Connect:** Gizlilik etiketini politikayla uyumlu doldurun (fotoğraflar, diğer kullanıcı içeriği, kullanıcı kimliği, satın alma geçmişi ve ödüllü reklam kayıtlarımız; uygulama işlevi için, kullanıcıyla ilişkili; Google reklam SDK'sı için genel konum, cihaz kimliği, ürün etkileşimi, reklam verileri ve performans verileri; üçüncü taraf reklam ve analiz için, kullanıcıyla ilişkisiz; hiçbiri takip için kullanılmaz; bkz. `docs/marketing/app-store-connect-setup.md` §5). Gizlilik Politikası adresini ekleyin. Kullanım Koşulları'nı özel EULA olarak yükleyin ya da Apple'ın standart EULA'sını kullanın.
10. **Kalıcı adresler:** Metinleri kendi alan adınızda veya GitHub kopyalarında yayınlayın. Eski sürümleri arşivleyin.
11. **Operasyonel taahhütler:** Bildirimleri inceleyin, itirazları bir insanın yanıtlamasını sağlayın. İş kayıtlarını 30 gün, çıktıları 1 saat sonra silen `sweep_jobs` görevini ve reklam ödül kayıtlarını 30 gün sonra silen `sweep_ad_rewards` görevini pg_cron ile çalıştırın. Sunucu kayıtlarını en fazla 90 gün saklayın.
