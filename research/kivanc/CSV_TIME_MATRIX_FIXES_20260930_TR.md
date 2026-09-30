# CSV ve TIME MATRIX: bes bulgunun yama sonucu

Tarih: 2026-09-30. Kanonik kaynaklar: Orb, MaCross, SolAdvanced.

Onceki denetim: `CSV_TIME_MATRIX_AUDIT_20260930_TR.md`. Bu rapor, o
denetimdeki bulgularin ardindan yapilan degisiklikleri kaydeder.

## Duzeltmeler

1. TIME MATRIX tarihsel giris kontrolu ve WR kovasi, simulasyonun giris
   zamanini kullaniyor. Giris trace'i yoksa sinyalin available zamanina
   acik fallback var. CSV ile ayni clock donusumu kullaniliyor. Sol'da bu
   nedenle reddedilen kayitlar DATA gibi cizilmiyor, CSV'ye alinmiyor ve
   sonraki pozisyonlarin kapasitesini tuketmiyor.
2. Orb/MaCross valid kapali kayitlarinda bos cikis nedeni outcome'dan
   tamamlandi. Ortak CSV yazari da ayni korumayi uyguluyor. DATA nedenleri,
   NAS gibi acik nedenler ve OPEN kayitlari korunuyor. MQL ZeroMemory ile
   sifirlanmis string de StringLen kontroluyle kapsaniyor.
3. Orb/MaCross bar-model girisleri `MODELED_BAR_TIME`, gozlenmis quote
   girisleri `AUDIT_FILL`, giris trace'i olmayanlar `UNAVAILABLE` olarak
   etiketleniyor. PnL, entry/SL/TP fiyatlari yeniden hesaplanmiyor.
4. Export baslangicinda ana TF ve M1/M5/M15/H1/H4/D1 kapali-bar gecmisi
   ve indikator buffer'lari hazirlaniyor. Eksik araliklar sinirli boyutta
   isteniyor; gecici eksiklikte OnTimer ile tekrar deneniyor. Chart custom
   event kuyruguna bekleme boyunca spin/repost yapilmiyor. Hazirlik icin
   30 saniye, Kivanc replay'in ilerleyemeyen history/chunk adimi icin
   30 saniye bekleme siniri var. Chunk basarili olunca stall sayaci
   sifirlaniyor; replay'in toplam suresi bu 30 saniye ile sinirli degil.
   Eksik kalan Kivanc satirlari `DATA_MISSING_HISTORY_TIMEOUT` yaziliyor.
   Sonsuz bekleme veya eksik veriyi sayisal sifira donusturme yok.
5. Sonuc mesaji artik genel "missing features: 0" demiyor. Ana grup,
   rolling, MTF ve Kivanc icin ayri eksik-satir sayilari veriyor. Bu
   sayilarin toplami benzersiz eksik trade sayisi degildir: ayni satir
   birden fazla grupta eksik olabilir. NAS/OF gibi opsiyonel gruplar icin
   CSV'nin kendi status alanlari gecerlidir; kapali grup hata sayilmaz.

Normal audit yoluna teknik feature extraction eklenmedi. Bu hazirlik
yalnizca CSV export istegi sirasinda calisir. CSV sutun adlari/sayisi,
bridge/listener protokolleri ve strateji ayar formati degistirilmedi.

## Degisen production kaynaklari

Her uc aile klasorunde degisen ortak moduller:

- `AuditTradeCsv.mqh`
- `AuditQuantFeatures.mqh`
- `AuditKivancExport.mqh`

Giris noktalarinda degisen dosyalar:

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`

Sol'daki filtrelenmis kayitlarin dogru atlanmasi icin:

- `IndicatorCodeExamples/SolAdvanced/AuditTradeCsvAdapter.mqh`
- `IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh`

Uc EA'nin eslesen `.ex5` dosyalari yeniden derlenip workspace'e kondu.
Source-derived indikator formulleri degistirilmedi.

## Dogrulama

| Test | Sonuc |
|---|---|
| Uc production EA | Her biri 0 hata / 0 uyari |
| TIME MATRIX / clock / strateji | 343 kontrol, 0 hata |
| CSV temel fixture | 52 kontrol, 0 hata |
| CSV sinir / retry fixture | 120 kontrol, 0 hata |
| Pine denklem referansi | 30 hesap, 21.000 karsilastirma, 0 fark |
| Kaynak kontratlari | 20 kontrol gecti; 11 execution/geometri/lifecycle fonksiyon govdesi pre-patch ile birebir ayni |
| Production adapter schema | Orb 1292, MaCross 1308, SolAdvanced 1200 benzersiz sutun; neden, giris basis'i, netR, tarih ve sure gecti |
| Gecici veri eksikliginden toparlanma | 64 satir; core/rolling/MTF/Kivanc eksigi 0; net +20R; satirlar causal |

Toparlanma testi **sentetik bir custom sembolde**, yalnizca izole MT5
worker'inda yapildi. Ilk durumda yetersiz history vardi; export'un
bekledigi gozlemlendi. Sonradan 45 gunluk M1 fixture verisi yuklendi;
timer export'u devam ettirdi, 64 satir eksiksiz uretildi. Bu broker piyasa
verisinde performans veya PnL iddiasi degildir. Test emir gondermez.

Pazartesi 09:59 available / 10:01 entry fixture'i artik TIME MATRIX'te
10-11 kovasina yaziliyor; CSV entry_hour=10. Ayni fixture, biri acik
digeri kapali saat maskeleriyle kabul/reddetme acisindan da test edildi.
DATA nedeni ve OPEN semantigi korundu; iptal stale event/timer'i kesiyor.

## Kalan veri siniri

EURUSD broker chart-event denemesinde worker logu `no connection` dedi.
Bounded retry sonrasi 64 CSV satiri yazildi, ancak bu run'da teknik
history elde edilemedi. Coverage testi bu nedenle FAIL kaldi; basarili
gibi sunulmadi. Satir sayisi/netR korundu ve eksiklikler tum gruplarda
acikca raporlandi. Brokerin saglamadigi history'yi bu yama yaratamaz.

Buna karsilik ayni export yolunun veri sonradan gelince toparlanmasi
custom-sembol testinde PASS oldu. Canli broker baglantisi ve ilgili
history coverage'i ayrica gereklidir.

Bu run tum stratejilerin yeni bir 5Y piyasa kampanyasi degildir. TIME
MATRIX OFF iken matematik fonksiyonlari degistirilmedi; TIME MATRIX ON
ve gecikmeli giris saat sinirini geciyorsa kabul/istatistik degisikligi
bulgunun bilincli duzeltmesidir. Mutlak piyasa parity veya tum sistemin
hatadan arindirilmis oldugu iddia edilmiyor.

## Release ve kanit

- Derleme/test: `.tmp/time_matrix_compile_20260930_175839`
- Sinir: `.tmp/csv_boundary_20260930_175607`
- Toparlanma: `.tmp/csv_recovery_20260930_180832`
- Release: `.tmp/csv_verified_release_20260930_181025`
- Deployment yedegi/hash manifest: `.tmp/audit_csv_deploy_backup_20260930_181138`

DEMO dagitimi: 114 kaynak/binary/dependency dosyasi; kopyalama sonrasi tum
SHA-256 degerleri release ile eslesti. Hedef EA'lar:

- `C:\MT5\DEMO\MQL5\Experts\orb\OrbUltimateEA_StrategyLibrary.ex5`
- `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb\MaCrossOverOrbEA.ex5`
- `C:\MT5\DEMO\MQL5\Experts\SolAdvanced\LiqNarrativeSol_Advanced.ex5`

Terminal test sirasinda canli emir gonderecek bicimde baslatilmadi;
deployment terminali otomatik baslatmaz.
