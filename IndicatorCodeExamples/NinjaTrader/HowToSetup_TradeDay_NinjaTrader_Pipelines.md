# TradeDay NinjaTrader Pipeline Setup

Bu rehber dort production listener icindir:

- `Liq Narrative Sol Version Ninja Listener`
- `Liq Narrative Sol Advanced Ninja Listener`
- `ORB Ultimate Ninja Listener`
- `NAS Ultimate Ninja Listener`

Listenerlar sinyal uretmez. MT5 tarafinin `Common\Files` altina yazdigi latest CSV eventini okur, riski NinjaTrader/TradeDay hesabinin kendi bakiyesine gore hesaplar ve NinjaTrader hesabinda emir acar.

## 1. Dosyalari NinjaTrader'a Kur

NinjaTrader'i kapat veya NinjaScript Editor acik degilken asagidaki alti dosyayi:

```text
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\ProductionFileBridgeNinjaCore.cs
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\TradeDayComplianceNinjaCore.cs
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\LiqNarrativeSolVersion_NinjaTrader_Listener.cs
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\LiqNarrativeSolAdvanced_NinjaTrader_Listener.cs
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\OrbUltimate_NinjaTrader_Listener.cs
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\NasUltimate_NinjaTrader_Listener.cs
```

su klasore koy:

```text
C:\Users\Cem\Documents\NinjaTrader 8\bin\Custom\Strategies\
```

Ayni dosyalar daha once kopyalandiysa yenileriyle degistir.

## 2. Compile Et

1. NinjaTrader 8'i ac.
2. `Control Center > New > NinjaScript Editor` sec.
3. Editor icinde `F5` tusuna bas veya sag tiklayip `Compile` sec.
4. `0 error` bekle. Bir hata varsa gercek hesaba gecme.

Bu workspace surumu kurulu NinjaTrader 8 assembly'lerine karsi ayrica derlendi: `0 error`. Harici harness, kurulu `NinjaTrader.Custom.dll` icindeki ayni tipleri de gordugunde yalnizca duplicate-type (`CS0436`) uyarilari verebilir.

## 3. Once Sim101 Testi Yap

1. MT5 publisher EA'sinin ilgili chartta calistigini ve `PUB ON` oldugunu kontrol et.
2. NinjaTrader'da hedef futures kontratinin chartini ac.
3. Chart'a sag tikla, `Strategies` sec.
4. Listener'i sec ve `Account = Sim101` yap.
5. Asagidaki pipeline presetlerinden birini gir.
6. `Enabled = true` yap.
7. Dashboard'da `Fault=NO`, dogru bridge yolu, source TF, account ve instrument gorulmeli.
8. Bir test sinyalinde entry, stop, target ve varsa HCBE emirlerini NinjaTrader `Orders` sekmesinden kontrol et.

Chart yerine `Control Center > Strategies` uzerinden de calistirabilirsin. Bu durumda chart dashboard'u gorunmez fakat listener calisir.

## 4. Sol Version JPN225 Preseti

Strategy:

```text
Liq Narrative Sol Version Ninja Listener
```

Bridge ve identity varsayilanlari:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 60
Default TF To Chart = false
Source Filter = LiqNarrativeSol
Source Symbol Aliases CSV = JP225m,JP225,JPN225m,JPN225
Require Chart Symbol = true
Rebase Levels To Live = true
Rebase Only Source Differs = true
Fail If Exact Protection Fails = true
```

Listener, Sol Advanced ile ayni merkezi 50K QuickPay production defaults setini kullanir: `Starting Balance=50000`, `Profit Target=3000`, `Intraday Trailing DD=2000`, `Position Limit=5 full/50 micro`, `Consistency=30%`, bridge risk ve post-fill risk guardlari acik. Sol Version'a ozel order scope `LNSOLNT`, audit prefix `LiqNarrativeSolVersion_Ninja_Audit_` ve state klasoru kullanilir.

## 5. Sol Advanced JPN225 Preseti

Strategy:

```text
Liq Narrative Sol Advanced Ninja Listener
```

Bridge ve identity:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 60
Default TF To Chart = false
Source Filter = LiqNarrativeSolAdvanced
Source Symbol Aliases CSV = JP225m,JP225,JPN225m,JPN225
Require Chart Symbol = true
```

Ninja instrument:

```text
TradeDay hesabinda kullanilabilen aktif JPY/Japan index futures kontrati.
Ornek aileler broker/instrument listesine gore NKD veya micro karsiligi olabilir.
Kontrat ayini sabit kopyalama; NinjaTrader Instrument Selector'dan aktif kontrati sec.
```

## 6. ORB JPN225 Preseti

Strategy:

```text
ORB Ultimate Ninja Listener
```

Bridge ve identity:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 15
Default TF To Chart = false
Source Filter = OrbUltimate
Source Symbol Aliases CSV = JP225m,JP225,JPN225m,JPN225
Require Chart Symbol = true
```

`Source TF Filter`, Ninja chart TF'si degil MT5 bridge eventinin `tf` kimligidir. ORB JPN225 publisher su an `15`, Sol Version ve Sol Advanced ise `60` kullanir.

## 7. NAS Ultimate SATS PartialNoBE Preseti

Strategy:

```text
NAS Ultimate Ninja Listener
```

Bridge ve identity varsayilanlari:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 5
Default TF To Chart = false
Source Filter = NasUltimate
Source Symbol Aliases CSV = BTCUSDm,BTCUSD,BTCUSDT,XBTUSD
Require Chart Symbol = true
Rebase Levels To Live = true
Rebase Only Source Differs = false
Fail If Exact Protection Fails = true
```

`Source TF Filter`, NAS publisher'in MT5 chart timeframe'idir. NAS M1'de calisiyorsa `1`, M5'te calisiyorsa `5` gir.

BTC CFD sinyalini NinjaTrader BTC futures kontratinda yuruturken mutlak MT5 fiyat seviyeleri kopyalanmaz. Rebase, MT5 entry-SL/TP/HCBE mesafelerini Ninja fill fiyatina tasir; kontrat adedi Ninja hesabinin kendi NetLiquidation ve futures PointValue bilgisiyle hesaplanir. Minimum bir kontrat secilen riski asarsa emir fail-closed engellenir.

## 8. Geometry Ayarlari

Ayni fiyat bazina sahip sembollerde:

```text
Rebase Levels To Live = false
Rebase Only Source Differs = true
Mapped Basis Guard % Risk = 25
Fail If Exact Protection Fails = true
```

MT5 CFD fiyati ile Ninja futures fiyati sabit bir basis farkina sahipse:

```text
Rebase Levels To Live = true
```

Bu mod MT5 lotunu veya mutlak entry fiyatini kopyalamaz. MT5 tarafindaki SL, TP ve HCBE mesafelerini koruyup Ninja gercek fill fiyatina tasir. Ilk kez farkli sembol mapping'i kullanirken mutlaka Sim101'de source mesafesi ile Ninja mesafesini karsilastir.

`Mapped Basis Guard % Risk`, rebase kapaliyken kaynak entry ile Ninja live fiyat arasindaki fark SL riskinin belirlenen yuzdesinden buyukse emri fail-closed bloklar.

## 9. Risk Ayarlari

Onerilen production tabani:

```text
Use Risk Contracts = true
Use Bridge Risk % = true
Local Risk % = publisher degeri yoksa kullanilacak fallback
Use Cash Value For Risk = false
Block If 1 Contract Exceeds Risk = true
Post-Fill Risk Guard = true
Max Risk Overshoot % = 5
Fail Closed On Risk Error = true
Max Contracts (0=off) = challenge kurallarina uygun hard cap
```

Risk hesabi:

```text
risk cash = NinjaTrader TradeDay account NetLiquidation * MT5 bridge risk_pct
contract risk = abs(Ninja fill - SL) * Ninja instrument PointValue
contracts = floor(risk cash / contract risk)
```

MT5 lotu kopyalanmaz. Bir futures kontrati bile secilen riski asiyorsa ve `Block If 1 Contract Exceeds Risk=true` ise trade acilmaz. Bu bilincli fail-closed davranistir.

Margin guard icin TradeDay/Ninja tarafindaki gercek intraday margin bilgisini biliyorsan:

```text
Use Margin Guard = true
Estimated Margin / Contract = gercek kontrat margin degeri
Max Margin Usage % = challenge planina uygun limit
Fail If Margin Estimate Missing = true
```

Margin degerini bilmiyorsan `Estimated Margin / Contract=0` ve `Fail If Margin Estimate Missing=false` kullanabilirsin; bu durumda account/order-size capleri ile broker reddi halen korunur fakat yerel margin tahmini yapilmaz.

## 10. Lifecycle ve HCBE

Onerilen ayarlar:

```text
Close Reverse = true
Close Reverse Across TF = false
Enable Close-Only Signals = true
Permanent Reject Guard = true
Manage HCBE = true
Half Close Fraction = 0.5
Fail If Exact Protection Fails = true
```

Listener su durumlari kalici state ile yonetir:

- partial fill ve sonradan gelen kalan fill
- exact absolute SL/TP OCO kurulumu
- protection kurulamazsa emergency close retry
- reverse signalde sadece kendi scope'una ait pozisyonu kapatma
- HCBE half-close tamamlandiktan sonra BE modify retry
- restart sonrasinda acik pozisyon, pending entry ve HCBE state sahiplenme
- market closed ve no-money retry throttle
- ayni eventin iki kere acilmasini engelleyen claim/commit lock

Listener kapatilinca mevcut broker-side koruyucu emirler bilerek iptal edilmez. Yeniden baslatilan ayni listener ayni account, instrument, bridge path, source ve TF ile state'i sahiplenir.

## 11. Kritik Izolasyon Kurali

Ayni TradeDay hesabi ve ayni futures kontrati uzerinde Sol Version, Sol Advanced veya ORB listenerlarindan birden fazlasini ayni anda calistirma.

Futures hesaplari ayni instrument icin net pozisyon tutar. Iki farkli listener ayni account+instrument uzerinde pozisyonu matematiksel olarak birbirinden ayiramaz. Kod yabanci position/order gordugunde ikinci pipeline'i fail-closed bloklar.

Ikisini ayni anda calistirmak icin:

- farkli TradeDay hesaplari kullan, veya
- firma izin veriyorsa farkli instrument/contract aileleri kullan.

Ayni account+instrument icin tek aktif listener production kuralidir.

## 12. State ve Audit Dosyalari

State klasoru bridge CSV'nin bulundugu dizinin altinda olusur:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NinjaBridgeState\<listener>\<account>\<scope>\
```

Audit dosyalari ayni Common Files dizininde gunluk ve event-bazli yazilir:

```text
LiqNarrativeSolVersion_Ninja_Audit_YYYYMMDD.csv
LiqNarrativeSolAdvanced_Ninja_Audit_YYYYMMDD.csv
OrbUltimate_Ninja_Audit_YYYYMMDD.csv
```

Audit her tick yazmaz. Sadece lifecycle eventleri ve ayarlanabilir, throttle edilmis heartbeat yazilir. Normal kullanimda dosya sisirmez.

State klasorunu acik trade varken silme. Futures kontrat rollover'inda instrument scope degisir; eski kontrattaki pozisyonu ve emirleri manuel olarak reconcile etmeden yeni kontrata gecme.

## 13. Gercek TradeDay Hesabina Gecis

1. TradeDay/CQG baglantisini NinjaTrader'da kur ve dogru hesaba baglan.
2. Sim101 testinde entry, SL, TP, OCO, reverse ve varsa HCBE davranisini dogrula.
3. Sim listener'i disable et.
4. Ayni preset ile yeni strategy instance ac.
5. `Account` alaninda challenge hesabini sec.
6. Aktif futures kontratini sec.
7. `Max Contracts` ve margin ayarlarini challenge kurallarina gore hard-cap yap.
8. `Enabled=true` yap.
9. Dashboard'da `Fault=NO` ve `Executor=ON` kontrol et.
10. Ninja `Orders`, `Executions`, `Positions` ve listener auditinin ilk eventini kontrol et.

TradeDay otomasyon kurallari zamanla degisebilir. Kendi yazdigin botun mevcut challenge kurallariyla uyumunu TradeDay destek ekibinden teyit et. TradeDay NinjaTrader'i desteklenen platform olarak listeler, fakat hesap/otomasyon kurallari program ve tarihe gore degisebilir.

## 14. Production Health Checklist

Her baslatmada:

```text
[ ] MT5 publisher PUB ON
[ ] CSV written_gmt guncel
[ ] Dogru generic Bridge Latest Path
[ ] Prefer Scoped Latest true
[ ] Source TF Filter dogru
[ ] Source Filter dogru
[ ] Source symbol aliases dogru
[ ] Ninja Account challenge hesabi
[ ] Ninja Instrument aktif kontrat
[ ] Ayni account+instrument uzerinde tek listener
[ ] Risk %, Max Contracts ve margin cap dogru
[ ] Rebase ayari mapping'e uygun
[ ] Fault=NO
[ ] Orders sekmesinde yabanci/cakisan emir yok
[ ] Ilk trade sonrasi broker-side SL ve TP mevcut
```

## Resmi Kaynaklar

- NinjaTrader strategy kurma: https://ninjatrader.com/support/helpGuides/nt8/running_a_ninjascript_strateg2.htm
- NinjaScript compile: https://ninjatrader.com/support/helpguides/nt8/compiling8.htm
- NinjaTrader Strategies tab: https://ninjatrader.com/support/helpguides/nt8/strategies_tab.htm
- TradeDay desteklenen platformlar: https://tradeday.freshdesk.com/en/support/solutions/articles/103000008813-which-trading-platforms-does-tradeday-use-
- TradeDay algo/bot kurali: https://tradeday.freshdesk.com/en/support/solutions/articles/103000085101-automated-algo-and-bot-trading

## 15. TradeDay Compliance Guardlari (Zorunlu Production Ayari)

Her iki listener ayni ortak compliance core'unu kullanir. Bu katman MT5 sinyal matematigini degistirmez; Ninja/TradeDay hesabini hesap seviyesinde korur.

Ayni TradeDay hesabinda calisan tum listener instance'larinda su alanlar **birebir ayni** olmalidir:

```text
TradeDay Compliance Enabled = true
Program = QuickPay veya FastPass
Drawdown Mode = satin alinan plana gore EndOfDay veya Intraday
Challenge Starting Balance = challenge baslangic bakiyesi
Maximum Drawdown Amount = paketin resmi maksimum drawdown tutari
Current Drawdown Floor Override = mevcut challenge'a ortadan baglaniyorsan TradeDay dashboard'daki guncel floor; yeni hesapta 0
Drawdown Safety Buffer Cash = liquidation floor'a kalmadan once kullanilacak tampon
Use Broker Trailing Floor = true
Position Limit Full Equiv = paketin full-contract limiti
Micros Per Full = 10
Max Trades Per Day = 200
Consistency Guard Enabled = true
Evaluation Profit Target = paketin resmi profit target tutari
Consistency Buffer Cash = istenen ek tampon
Session Close Guard Enabled = true
Minutes Before Product Close = 10
Tier1 News Guard Enabled = true
News Minutes Before = 2
News Minutes After = 2
Fail Closed If Calendar Missing = true
Calendar Max Age Hours = 36
Compliance Reset Token = challenge'a ozel ve tum instance'larda ayni deger
```

`Position Limit Full Equiv=5` ve `Micros Per Full=10`, maksimum 5 full veya 50 micro esdegeri demektir. Bu sadece varsayilan emniyet degeridir; satin aldigin paketin limiti daha dusukse mutlaka dusur. Eski `Max Contracts` alani da ikinci bir raw cap olarak calisir ve varsayilan `50`dir; asil hesap-geneli full/micro cap `Position Limit Full Equiv` alanidir.

`Compliance Reset Token` ornegi:

```text
TD_QP_50K_202607_ACCOUNT1
```

Yeni challenge baslatirken once ayni hesaptaki tum listener'lari disable et, tumunde yeni ve ayni token/config'i gir, sonra yeniden enable et. Token degisikligi kalici ledger'i bilerek sifirlar. Acik challenge sirasinda token'i degistirme.

### Drawdown davranisi

- EOD ve Intraday planlari ayri izlenir.
- Floor baslangicta `starting balance - max drawdown` olur.
- Intraday modunda account `NetLiquidation` yuksegine gore, EOD modunda kapanan trading-day equity'sine gore ilerler.
- Floor baslangic bakiyesinin uzerine cikmaz; orada donar.
- Ninja account `TrailingMaxDrawdown` mutlak floor olarak makul gorunuyorsa daha guvenli olan yuksek floor kullanilir.
- Equity floor + safety buffer'a dokunursa hard-stop kalici kaydedilir, tum account order/position'lari flatten edilir ve token degismeden yeni trade acilmaz.

Bilgisayar/restart sonrasi guncel challenge ortasinda calisiyorsan `Current Drawdown Floor Override` alanina TradeDay'in gosterilen gercek floor'unu gir. Bu, restart oncesi intraday peak bilgisinin platform API'sinde bulunmamasi edge-case'ini kapatir.

### Product close guard

Chart'in NinjaTrader `Trading Hours` template'i ilgili futures urununun gercek exchange template'i olmalidir. Listener `SessionIterator` ile urun kapanisini bulur, kapanistan 10 dakika once o instrument'in working order'larini iptal edip pozisyonunu flatten eder. Session template okunamazsa veya urun session disindaysa yeni entry fail-closed bloklanir.

### Tier-1 haber CSV'si

`LiqNarrativeSolVersion.mq5` ve `LiqNarrativeSol_Advanced.mq5`, MQL5 Economic Calendar API'sini kullanarak production dosyasini otomatik doldurur:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\TradeDay_Tier1_News_GMT.csv
```

Publisher varsayilanlari:

```text
TradeDay Calendar Publisher Enabled = true
TradeDay Calendar File = TradeDay_Tier1_News_GMT.csv
TradeDay Calendar Lookahead Days = 0
TradeDay Include Japan Medium High = true
TradeDay Include Japan Low = false
```

`Lookahead Days=0`, MQL5 kaynaginda o anda bilinen tum gelecek event'leri alir. Dosya ilk EA baslangicinda, her yeni UTC gununde bir kez ve broker UTC offset'i degistiginde yeniden uretilir. MQL5 takvim saatleri broker trade-server saatidir; publisher `TimeTradeServer-TimeGMT` offset'ini dakika hassasiyetinde normalize edip her eventi GMT'ye cevirir. DST/offset degisimi algilaninca ayni gun icinde zorunlu refresh yapilir.

TradeDay generic `low/medium/high` sinifini kullanmaz. Zorunlu liste isim bazli secilir: FOMC minutes/rate statement, US CPI ve NFP `ALL`; EIA crude `OIL`; EIA gas `GAS`; crop production `AGS`. Japonya medium/high event'leri NKD icin ek konservatif korumadir. Japonya low varsayilan olarak kapali tutulur; TradeDay zorunlulugu degildir ve gereksiz blackout uretebilir.

Format:

```csv
# generated_gmt=2026-07-27 10:00:00;build=...;server_offset_seconds=10800;...
event_gmt,scope,label
2026-08-07 12:30:00,ALL,TD_US_NFP_NONFARM_PAYROLLS
2026-08-12 12:30:00,ALL,TD_US_CPI_CONSUMER_PRICE_INDEX
2026-08-19 14:30:00,OIL,TD_EIA_CRUDE_CRUDE_OIL_INVENTORIES
```

Yazim temp dosya + atomic replace ile yapilir. API sorgusu veya event detayi eksik kalirsa mevcut last-known-good CSV silinmez. Ninja listener dosyadaki `generated_gmt` metadata'sini kontrol eder; dosya 36 saatten eskiyse, yoksa, bossa veya gelecek event icermiyorsa `Fail Closed=true` ile yeni entry'yi bloklar. Aktif blackout'ta ilgili working order/position kapatilir ve `-2/+2 dakika` boyunca entry acilmaz.

Manuel fallback template'i:

```text
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\IndicatorCodeExamples\NinjaTrader\TradeDay_Tier1_News_GMT_TEMPLATE.csv
```
### 200 trade ve consistency

- Account `ExecutionUpdate` akisi izlenir; manual ve diger otomasyon entry'leri de sayilir.
- Partial fill'ler `OrderId` ile tekillestirilir ve tek trade sayilir.
- 200 veya daha dusuk ayarlanmis limite gelince yeni entry kesin bloklanir.
- Quick Pay icin gunluk soft cap `profit target * 30%`, Fast Pass icin `profit target * 45%` olarak uygulanir.
- Soft cap'e ulasilinca account flatten edilir ve sonraki CME trading day'e kadar entry acilmaz.
- Bu consistency davranisi resmi kurala gore konservatiftir: challenge'i fail ettiren bir kural degil, hedefin buyumesini onleyen local guarddir.

Kalici account ledger'i burada tutulur:

```text
C:\Users\Cem\Documents\NinjaTrader 8\NinjaBridgeState\TradeDayCompliance\<ACCOUNT>.state
```

Dosyada yalnizca birkac scalar alan ve o gun en fazla 200 order kimligi vardir. Tick loglamaz ve diski sisirmez.

## TradeDay Resmi Compliance Kaynaklari

- Maximum drawdown: https://tradeday.freshdesk.com/en/support/solutions/articles/103000008855-what-is-the-maximum-drawdown-rule-
- Permitted trading times: https://tradeday.freshdesk.com/en/support/solutions/articles/103000018874-what-is-the-permitted-trading-times-guideline-
- News/data releases: https://tradeday.freshdesk.com/en/support/solutions/articles/103000081072-can-i-trade-news-or-data-releases-
- Position limits: https://tradeday.freshdesk.com/en/support/solutions/articles/103000008891-what-are-the-position-limits-guidelines-and-contracts-vs-micros-
- Evaluation/consistency: https://tradeday.freshdesk.com/en/support/solutions/articles/103000008847-what-are-the-objectives-and-rules-of-the-quick-pay-and-fast-pass-evaluation-
- Prohibited practices: https://tradeday.freshdesk.com/en/support/solutions/articles/103000121031-prohibited-trade-practices
