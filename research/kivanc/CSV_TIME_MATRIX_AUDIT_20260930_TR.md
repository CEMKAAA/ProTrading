# CSV export ve TIME MATRIX denetimi

Tarih: 2026-09-30. Kapsam: Orb, MaCross ve SolAdvanced production kaynaklari.

## Son karar

**Tam hatasizlik onayi verilmedi.** Test edilen matematiksel hesaplamalarda sayisal fark bulunmadi, ancak uc metadata/zamanlama sorunu bulundu. Gecmis veri hazirligi ve eksiklik sayacinda da saglamlastirilmasi gereken iki nokta var.

Bu bir denetim turudur. Production EA, bridge, listener, sinyal cekirdegi ve trade motoru degistirilmedi. Sadece testler ve bu rapor eklendi. Haber pipeline'i ertelendi.

## Bulgular

### 1. TIME MATRIX sinyalin kullanilabilirlik saatini, CSV gercek giris saatini kullaniyor

Onem: Orta. Uc EA'yi da etkiliyor.

- Orb: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5:6892`
- MaCross: `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5:7046`
- SolAdvanced: `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5:3135`

TIME MATRIX istatistigi `availableTime` / `OrbSignalAvailableTime(entryT)` ile kaydediliyor. CSV'nin `entry_hour`, `entry_day` ve teknik ozellik cutoff'u ise yakalanan `entryTime` uzerinden uretiliyor. Ayni zamanda tarihsel TIME MATRIX giris filtresi sinyalin kullanilabilirlik zamanina, canli giris kontrolu mevcut zamana bakiyor.

Sinir testi: Pazartesi 09:59'da kullanilabilir olan, 10:01'de acilan kazanan bir islem. Mevcut TIME MATRIX cagrisi 09-10 kovasina 1W yaziyor, CSV 10-11 kovasini yaziyor. Testte bu fark yeniden uretildi. Bu fixture, belirtilen stratejide gercekten boyle bir piyasa islemi oldugu iddiasi degildir; iki kod yolunun farkini ispatlar.

Aninda ve ayni saat icinde girislerde fark olusmaz. Gecikmeli giris, retest veya saat/gun sinirindaki fill'de fark olusabilir. Kullanici talebi "islemin acildigi saat" oldugundan, iki tarafta ayni fill zamaninin esas alinmasi gerekir. Fill bilinmiyorsa sinyal saati ayri bir basis ile belirtilmeli; gercek giris saatiymis gibi birlestirilmemeli.

### 2. Orb ve MaCross'ta gecerli kapali islemlerin cikis nedeni bos yaziliyor

Onem: Orta.

- Orb: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5:6885`
- MaCross: `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5:7039`
- Ortak yazar: `IndicatorCodeExamples/orb/AuditTradeCsv.mqh:211`

Adapter `csv.reason=sim.invalidReason` atiyor. Gecerli simulasyonda bu alan bos. Gercek cikis turu `sim.outcome` alaninda bulunuyor. Dolayisiyla `label_outcome` TP/SL/NAS vb. bilgisini tasiyabilse de `label_exit_reason` bos kaliyor.

Sinir testinde `outcome=TP`, `valid=true`, `closed=true`, `reason` bos olan kayit bu davranisi yeniden uretti. Cozum, DATA kayitlarinda invalid reason'i korumak, gecerli kapali kayitlarda outcome/gercek cikis nedenini kullanmaktir. SolAdvanced kendi `g_histSignalExitReason` dizisini kullandigi icin bu spesifik atama hatasi onda yok.

### 3. Orb ve MaCross bar-model girisini AUDIT_FILL olarak etiketleyebiliyor

Onem: Orta.

- Orb: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5:6879`
- MaCross: `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5:7033`
- Bar fallback trace: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5:5520`

`entryTime>0` oldugu surece `entry_time_basis=AUDIT_FILL` yaziliyor. Ancak OHLC/bar fallback de `entryTime` dolduruyor. Bu yoldaki zaman gercek executable tick degil, modellenmis bar zamanidir. `entry_spread_basis=NOT_CAPTURED_BAR_MODEL` bunu dolayli olarak ortaya koyuyor ama giris basis'i dogru degil.

Tick ve bar-model trace'leri ayri etiketlenmeli. SolAdvanced zaten quote basis'ine gore `AUDIT_FILL` / `MODELED_BAR_TIME` ayrimini yapiyor. Bu bulgu, fiyat veya PnL'nin bu turda yanlis hesaplandigi anlamina gelmez; export edilen kanit turunun yanlis etiketlenmesidir.

### 4. Veri henuz hazir degilken export yeniden hazirlik denemesi yapmadan tamamlanabilir

Onem: Saglamlik acigi. Eksik deger uydurulmuyor.

- `IndicatorCodeExamples/orb/AuditKivancExport.mqh:31`
- `IndicatorCodeExamples/orb/AuditKivancExport.mqh:49`
- `IndicatorCodeExamples/orb/AuditTradeCsv.mqh:233`

Kivanc replay hazirligi bir kez baslatiliyor. Seri senkron degilse baslamiyor; chunk okuma basarisizsa replay duruyor. Bekleyen history icin retry ile kalici veri yoklugu arasinda ayrim yok. Diger timeframe gruplari da seri senkron degilse dogrudan `DATA_MISSING` yaziyor.

Bu turun EURUSD chart-event testinde dosya 64 satirla olustu, net etiket toplami +20R korundu, fakat 64 satirin standart ve Kivanc ozellikleri `DATA_MISSING` kaldi. Bu nedenle veri tamligi testi **basarisiz** sayildi. Izole worker loglarinda baglanti/saklama sorunlari goruldu; bunlar production chart'in ayni durumda oldugunu kanitlamaz. Eski basarili run bu turun yerine basarili kanit olarak kullanilmadi.

Oneri: CSV export icin sinirli PREPARING/RETRY asamasi, timeframe basina coverage kontrolu ve bekleme sonunda acik eksiklik raporu. Brokerin saglamadigi veriyi sonsuza kadar beklemek ya da uydurmak yok. Normal audit yoluna feature hesaplama eklenmemeli.

### 5. "Missing feature rows" sayaci tum ozellik gruplarini kapsamiyor

Onem: Dusuk-Orta.

- `IndicatorCodeExamples/orb/AuditTradeCsv.mqh:157`
- `IndicatorCodeExamples/orb/AuditTradeCsv.mqh:280`

`g_axMissing` sadece `AxFeatures` grubunda artiyor. MTF quant gruplari, Kivanc replay ve gerekli NAS/OF gruplarinin eksikleri bu sayaca dahil degil. Ana grup hazirken baska bir grup eksikse "missing features: 0" mesaji tum CSV'nin eksiksiz oldugu anlamina gelmez.

CSV'deki grup status alanlari eksikligi gostermeye devam ediyor. Oneri, bu mesaji "missing core-feature rows" olarak dogru sinirlamak veya beklenen gruplara gore ayri sayaclar gostermektir. Kapali NAS/OF gibi istege bagli gruplar eksik veri hatasi sayilmamali.

## Yeniden calistirilan kontroller

| Kontrol | Sonuc | Kapsam |
|---|---|---|
| Uc production EA derlemesi | 0 hata, 0 uyari | Her uc kanonik kaynak |
| TIME MATRIX ve clock/strateji probe'lari | 343 kontrol, 0 hata | Saat ayarlari, gun/saat uygula-iptal, WR esigi, sayfalama, staged apply, kaydet/yukle |
| CSV temel MQL fixture | 48 kontrol, 0 hata | Escaping, OPEN/DATA, PnL, bos audit, iptal, final dosya |
| Yeni CSV/saat sinir fixture | 104 kontrol, 0 hata | Yukari/asagi/duz seri, 5/20/60/120 pencere, geometri, sabit-seri eksikleri, saat/gun sinirlari, iki bulgunun tekrari |
| Bagimsiz Pine denklem referansi | 30 hesap, 700 bar, 21.000 karsilastirma, 0 fark | Kaynak formullerle streaming MQL karsilastirmasi |
| Gercek production adapter schema testleri | Orb 1292, MaCross 1308, SolAdvanced 1200 benzersiz sutun | Stub adapter yerine gercek EA adapter'i. Ayarlar, giris tarihi, 123 saniye sure ve 0.97R degismedi |
| EURUSD chart-event export | 64 satir, 64 benzersiz kayit, net +20R; feature coverage FAIL | Dosya/satir/etiket korunuyor, ama bu run'da teknik veri hazirligi dogrulanamadi |
| Paylasilan moduller | Uc klasorde ayni SHA-256 | CSV, quant, signal, Kivanc ve TIME MATRIX ortak dosyalari |
| DEMO dagitim hash kontrolu | 112 dosya, 0 fark | Onceki dogrulanmis deployment manifest'i |
| Denetim sonrasi production kaynak hash kontrolu | 0 degisiklik | Derleme stage'ine gore |

Derleme/test stage: `.tmp/time_matrix_compile_20260930_170236`.

Sinir testi stage: `.tmp/csv_boundary_20260930_172050`.

Production adapter sonuclari: `.tmp/time_matrix_compile_20260930_170236/csv_production_schemas.json`.

## Dogrulanan davranislar

- Uygula/iptal sadece hedef gunu, saati veya gun-saat kovasini etkiliyor. HOURS uygula tum yedi gune yayiliyor.
- Akilli secim WR esigini, esige esit degerleri ve MIN N'yi dikkate aliyor. Bos/hatali input secimi degistirmiyor.
- Leaderboard pick'leri APPLY PICKS'e kadar staging alaninda kaliyor. Strateji save/load gunlere ozel maskeleri geri getiriyor.
- Normal audit kayit yakalama ve seal asamasinda teknik/Pine feature extraction calismiyor.
- CLOSED/OPEN/DATA satirlari farkli tutuluyor. DATA'ya sahte win/loss ve PnL yazilmiyor. OPEN icin audit'in sifir gerceklesmis R semantigi korunuyor; `label_closed=false`, won/exit alanlari bos kaliyor. OPEN sifiri kapali breakeven etiketi gibi egitimde kullanilmamali.
- Yakalanmis tick spread'i points olarak aktariliyor. Gercek order slippage'i tarihsel simulasyondan uydurulmuyor.
- Tekrarlanan ayni-bar Pine snapshot okumasi event-age alanlarini degistirmiyor.
- Referans fixture'da eski snapshot sonraki barlar nedeniyle degismiyor. Kapali-bar ve onaylanmis-pivot prensibi korunuyor.
- Test edilen hesaplamalarda NaN/EMPTY degerleri sayisal sifira zorla donusturulmuyor.

## Sinirlar

- 21.000 sayisal karsilastirma 30 hesap icindir; 517 Kivanc sutununun her biri icin bagimsiz bir denklem/event oracle'i kuruldugu iddia edilmiyor.
- CSV'nin binlerce sutunu binlerce bagimsiz indikator demek degildir. Aralarinda ayarlar, ara hesaplar, ayni ozelligin farkli pencereleri ve post-entry etiketler vardir.
- Source-derived hesaplar yerel Pine dosyalarinin belirtilmis default parametreleriyle uretilir. Kullanici sinyal cekirdeginin MA uzunluklarini degistirirse sabit `ema_9` sutunu otomatik olarak yeni uzunluga donusmez; adi neyse o hesaptir. Runtime ayari `setting_*` alaninda ayrica saklanir.
- Bu denetim butun stratejilerin piyasa tickleriyle yeniden 5Y test edilmesi veya mevcut audit motorunun tamamini bagimsiz trade simulator'u ile ispatlamak degildir.
- Gercek broker / TradingView feed esitligi, tarihsel gercek emir slipaji ve brokerin eksik tick arsivi bu testlerle ispatlanmaz.
- Normal audit sonuclari ve broker quote'lari bu turda degistirilmedi. Bu nedenle bulunan sorunlari duzelten yeni bir EA deploy edilmedi.

## Sonraki oncelik

Once 1-3 numarali dogrudan metadata/zamanlama hatalari kucuk yamalarla duzeltilmeli. Sonra export readiness ve grup-bazli coverage raporu saglamlastirilmali. Degisiklikten sonra ayni testler ve en az bir gecikmeli-giris gercek audit CSV/TIME MATRIX kovasi karsilastirmasi tekrar yapilmali. Haber veya ML entegrasyonu bu kontrollerden once eklenmemeli.
