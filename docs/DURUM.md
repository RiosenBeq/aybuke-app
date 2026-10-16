# Aybuke — iş durumu (16 Ekim 2026, 19:00)

Bu oturumun açık işleri. Bir sonraki devamda buradan başlayın; ayrıntı `AGENTS.md` §6'da.

## Yapıldı

- **1.0 incelemede** (iOS + macOS, `WAITING_FOR_REVIEW`, onaylanınca otomatik yayında). Sahibin kararı: 1.0'a dokunulmaz; onay gelince 1.1 **güncelleme** olarak gönderilir. Not: incelemedeki iOS 1.0 derlemesi (20261015.1225) eski, geçersizleşmiş profille imzalı ve App Store Connect'te "expired" görünüyor; Apple reddederse yeni imzalı derlemeyle hemen yeniden gönderilir.
- **1.1 kodu:** anketler ("Which vibe?", uygulama + sunucu + aybuke.org/p/…), Glow Cam, video Auto edit, DSLR '12 / DSLR Portrait, Adjust vibe'ları ve My filters, 20 makyaj görünümü, Cut out / Erase iyileştirmeleri, editör zoom'u, paylaşım boyutları, Aybik (Claude yazı yardımı; arayüzde "Claude" ve şirket adı geçmez), ülkeye özel mevsimler, inceleme düzeltmeleri, politika (anket sorusu) düzeltmeleri.
- **Sunucu (Supabase):** migrasyonlar `20261103000001`'e kadar canlı; `ai-image`, `assist`, `polls`, `owner-digest` güncel. xAI bakiye tahmini 8,13 $ (taban 5–6 $).
- **İmza:** geçersiz profiller silindi; aktif: "Aybuke App Store 2", "Aybuke Mac Catalyst App Store 2", iki widget profili. Yükleme betiği profilleri derlemeden önce kontrol eder.
- **TestFlight:** iOS 1.1 (20261016.1326) ve Mac 1.1 (20261016.1350) "Aybuke Team" grubunda; riosenbeq@icloud.com test grubunda.
- **Mağaza görselleri:** 1.1 iPhone ekran görüntüleri 12 dilde (`docs/marketing/app-store/<dil>/`, commit `91adf3c`).
- **Web sitesi (RiosenBeq/aybuke):** 1.1 özellikleri "Sonraki güncellemede" etiketleriyle (`src/data/release.json` → `liveVersion`), 19 görünüm örneği, yasal metinler eşit.

## Sürüyor

- **Enhance (Remini benzeri) + 18+ Soft skin** — kod yazıldı, doğrulanıp commit'lenecek. Commit'lenmemiş hâli yedekte: `origin/wip/enhance-backup`.
- **Mağaza varlıkları** — iPad ve Mac ekran görüntüleri, İngilizce/Türkçe yıl boyu önizleme videosu (After Effects), 13 dilde "Yenilikler". Çıktılar: `docs/marketing/app-store/…`, `docs/marketing/app-preview/`.

## Bekliyor (sırayla)

1. **Aybik genişletmesi:** vibe ile görünüm bulma (Keşfet), anket sorusu önerisi, kart yazısı önerisi, "Aybik'e sor" yardımcısı; gizlilik metni ve sunucu sınırları.
2. **Animasyon cilası:** harf harf "aybuke" açılışı, sonuç ve geçiş animasyonları.
3. **Son denetim + düzeltmeler**, tam test turu, son 1.1 derlemesi (TestFlight), CI yeşil → `main`.
4. **aybuke.org yeniden tasarım** (animasyon, görseller, SEO; yerel dal `redesign-wip`), sonra siteyi `main`'e.
5. **1.0 onayı gelince:** 1.1 sürüm kaydı, metinler/görseller/video yüklemesi, derlemeyi bağlayıp incelemeye gönderme; AdMob'u mağaza kaydına bağlama; sitede `liveVersion` "1.1"; `PROMPT_POLISH` açma.

## Sahibe kalanlar

- Çöp Sepeti'ni boşaltmak (Cursor ve VN verileri, ~14 GB).
- xAI anahtarını yenilemek (sohbete yazıldı); yenisi sunucuya `read -s` ile girilir.
- Avukatla KVKK/DPA kontrolü; gerçek cihazda TestFlight denemesi.
