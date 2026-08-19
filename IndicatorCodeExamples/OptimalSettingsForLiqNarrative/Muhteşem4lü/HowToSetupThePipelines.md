# Universal cTrader Pipeline Setup

All bridge files are under:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files
```

## The Two Inputs You Normally Set

For every cTrader listener instance:

```text
Bridge Latest Path = the generic path for that EA family
Source TF Filter   = the publisher timeframe in minutes
Prefer Scoped Latest = true
```

Use one listener instance for each `EA family + cTrader symbol + source TF` combination. Do not point two different EA families at the same generic bridge path.

## Generic Paths

| MT5 publisher | cTrader listener | Bridge Latest Path |
|---|---|---|
| Normal Liq Narrative | `LiquidityNarrative_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiquidityNarrativeBridge_Latest.csv` |
| Liq Narrative SolVersion | `LiquidityNarrative_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv` |
| Liq Narrative Sol Advanced | `LiqNarrativeSolAdvanced_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv` |
| ORB Ultimate | `OrbUltimate_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv` |
| NAS Professional | `NasUltimate_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv` |

With `Prefer Scoped Latest = true`, always enter the generic path above. The listener finds the matching symbol/TF scoped file automatically.

## Source TF Formula

`Source TF Filter` must equal the value written into the bridge CSV `tf` column:

```text
Normal Liq Narrative      = dashboard ENTRY TF in minutes
Liq Narrative SolVersion = dashboard ENTRY TF in minutes
Sol Advanced              = dashboard ENTRY TF in minutes
ORB Ultimate              = dashboard Signal TF in minutes # her zaman için 15
NAS Professional          = MT5 chart TF in minutes
```

Do not use the MT5 chart timeframe for Liq/ORB unless it is also the selected Entry/Signal TF.

Timeframe conversion:

| Timeframe | Source TF Filter |
|---|---:|
| M1 | `1` |
| M5 | `5` |
| M15 | `15` |
| M30 | `30` |
| H1 | `60` |
| H2 | `120` |
| H4 | `240` |
| D1 | `1440` |

Use the numeric value, especially for H2. Do not enter `H2`; enter `120`.

## Scoped Filename Formula

The universal formula is:

```text
<Common Files>\<FAMILY_PREFIX>_Latest_<MT5_SOURCE_SYMBOL>_<SOURCE_TF_MINUTES>.csv
```

Family prefixes:

```text
Normal Liq Narrative      LiquidityNarrativeBridge
Liq Narrative SolVersion LiqNarrativeSolBridge
Sol Advanced              LiqNarrativeSolAdvancedBridge
ORB Ultimate              OrbUltimateBridge
NAS Professional          NasUltimateBridge
```

Examples:

```text
LiqNarrativeSolBridge_Latest_UK100m_60.csv
LiqNarrativeSolAdvancedBridge_Latest_UK100m_60.csv
OrbUltimateBridge_Latest_DE30m_15.csv
OrbUltimateBridge_Latest_DE30m_5.csv
NasUltimateBridge_Latest_DE30m_5.csv
```

The scoped formula is mainly for verification and troubleshooting. Under normal operation, keep `Bridge Latest Path` on the generic family path and keep `Prefer Scoped Latest = true`.

## Future Setup Examples

### SolVersion on UK100, Entry TF H1

```text
cTrader robot        = LiquidityNarrative_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv
Source TF Filter     = 60
Prefer Scoped Latest = true
Expected scoped file = LiqNarrativeSolBridge_Latest_UK100m_60.csv
```

### Sol Advanced on UK100, Entry TF H1

```text
cTrader robot        = LiqNarrativeSolAdvanced_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv
Source TF Filter     = 60
Prefer Scoped Latest = true
Expected scoped file = LiqNarrativeSolAdvancedBridge_Latest_UK100m_60.csv
```

### ORB on DE30, Signal TF M15

```text
cTrader robot        = OrbUltimate_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Source TF Filter     = 15
Prefer Scoped Latest = true
Expected scoped file = OrbUltimateBridge_Latest_DE30m_15.csv
cTrader chart        = GERMANY 40
```

If ORB Signal TF is changed to M5, change only:

```text
Source TF Filter     = 5
Expected scoped file = OrbUltimateBridge_Latest_DE30m_5.csv
```

## Current Known Setups

| Pipeline | Source TF Filter |
|---|---:|
| Normal Liq, US500, Entry M15 | `15` |
| Normal Liq, US100/USTEC, Entry M15 | `15` |
| SolVersion, JPN225, Entry H1 | `60` |
| Sol Advanced, JPN225, Entry H1 | `60` |
| ORB, JPN225, Signal M15 | `15` |
| ORB, DE30, Signal M15 | `15` |
| NAS Professional, DE30 chart M5 | `5` |

## Symbol Mapping Rule

The listener resolves common aliases such as:

```text
JP225m/JP225/JPN225 -> JPN225
DE30m/GER30/GER40/DAX40 -> GERMANY 40
US500m/SPX500 -> US 500
USTECm/US100/NAS100 -> US Tech 100
US30m/DJ30 -> Wall Street 30
```

For symbols such as UK100, canonical matching normally handles spaces and the MT suffix (`UK100m` and `UK 100`). If the broker uses a materially different cTrader symbol name, set:

```text
Symbol Map CSV = <MT5_SOURCE_SYMBOL>=<EXACT_CTRADER_SYMBOL_NAME>
```

Example only if the exact cTrader tab/symbol name is `UK 100`:

```text
Symbol Map CSV = UK100m=UK 100
```

Multiple mappings are comma-separated:

```text
UK100m=UK 100,DE30m=GERMANY 40
```

## Isolation Rules

Keep these settings:

```text
Prefer Scoped Latest = true
Require Chart Symbol = true
Close Reverse Across TF = false
```

Use separate cTrader listener instances when any of these differ:

```text
EA family
cTrader chart symbol
Source TF Filter
```

That separation prevents SolVersion, Sol Advanced, Normal Liq, ORB and NAS events from claiming, closing or managing each other's positions.


-------------------------------------Şip Şap Setups-------------------------------------------------------------------------
Use these full paths:

US500 and US100 - Normal Liq Narrative

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiquidityNarrativeBridge_Latest.csv

JPN225 - Liq Narrative SolVersion

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv

JPN225 - Liq Narrative Sol Advanced

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv

DE30 - NAS Professional

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv

and "source tf filter"

us500 and us100: 15, jp225 sol: 60, jp225 advanced: 60, de30 nas: 5

and thats it pipelines are set.
----------------------------------------------------------------------------------------------------------------------------

## JP225 ORB Ultimate - Kanal Bazli Production Kurulumu

Bu kurulum bir adet `JP225m`, `M15` ORB instance'i icindir.

### 1. DEMOMT5 publisher

1. DEMOMT5'te `JP225m` chartini ac.
2. Chart timeframe'ini `M15` yap.
3. `Experts\orb\OrbUltimateEA` EA'sini charta ekle.
4. Strateji ayarlarini ve `Risk %` degerini ayarla, sonra `APPLY RISK` butonuna bas.
5. Dashboard'da `PUB ON` yap.
6. Sadece listener hesaplari trade acacaksa `ONLY ON`, `NAT OFF` kullan.
7. Dashboard `CH` alanina kanal numarasini yaz ve `APPLY CH` butonuna bas. Ilk instance icin `1` kullan.
8. Istersen ek GMT giris filtresini kullan: `WIN ON`, baslangic/bitis saatlerini `HH:MM` yaz ve `APPLY GMT` butonuna bas.
9. Su dosyanin olustugunu kontrol et:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest_C1_JP225m_15.csv
```

EA takilinca dosyaya once `INIT` yazilmasi normaldir. `INIT` bir trade sinyali degildir.

### 2. cTrader listener

1. cTrader `Automate` bolumunde `OrbUltimate_cTrader_Listener` robotunu Build et.
2. cTrader'da brokerin Nikkei sembol chartini ac. Mevcut mapping icin chart adi `JPN225` olmali.
3. Robotu bu charta ekle.
4. Yalnizca su degerleri kontrol et:

```text
Executor Enabled               = true
Bridge Latest Path             = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest           = true
Source TF Filter               = 15
Bridge Channel                = 1
Default TF To Chart            = false
Source Filter                  = OrbUltimate|
Use Built-In Index Map         = true
Require Chart Symbol           = true
Rebase Levels To Live          = true
Rebase Only Source Differs     = true
Use Risk Lot                   = true
Use Bridge Risk %              = true
Fail If Exact Protection Fails = true
Post-Fill Risk Guard           = true
Ignore Existing On Init        = true
```

5. Robotu `Start` et.

`Ignore Existing On Init=true` guvenli varsayilandir: listener acilirken dosyada duran eski sinyali tekrar acmaz; bir sonraki yeni `BUY/SELL` olayini bekler. cTrader lotu MT5 bakiyesinden kopyalamaz, cTrader hesabinin kendi equity'si ve bridge'den gelen risk yuzdesiyle hesaplar.

### 3. Hedef MT5 listener

1. MetaEditor 5'te `Experts\orb\OrbUltimate_IQCapital_MT5_Listener_EA.mq5` dosyasini derle.
2. Hedef MT5'te `JPN225` chartini ac.
3. `OrbUltimate_IQCapital_MT5_Listener_EA` EA'sini charta ekle.
4. Su degerleri kontrol et:

```text
InpExecutorEnabled             = true
InpBridgeLatestFile            = OrbUltimateBridge_Latest_C1_JP225m_15.csv
InpUseCommonFiles              = true
InpSourceLoginFilter           = 260460316
InpSourceTimeframeFilter       = 15
InpSourceFilter                = OrbUltimate|
InpRequireMappedSymbolEqualsChart = true
InpRebaseMappedLevelsToLiveEntry  = true
InpUseRiskLot                  = true
InpPostFillRiskGuard           = true
InpFailIfExactProtectionFails  = true
InpIgnoreExistingSignalOnInit  = true
```

5. Hedef broker server adi `BeyondIQCapital` degilse `InpDestinationServerFilter` alanini brokerin gercek server adina cevir. Bilincli olarak kapatmak istersen bos birak.
6. MT5 `Algo Trading` dugmesini ac.

Hedef MT5 lotu de DEMOMT5 bakiyesini kullanmaz; hedef MT5 hesabinin kendi equity'si ve bridge risk yuzdesiyle hesaplanir.

### 4. Saglik kontrolu

```text
Publisher CSV updated          = yes
CSV symbol / TF                = JP225m / 15
cTrader mapped chart           = JPN225
MT5 mapped chart               = JPN225
Ayni event ikinci kez aciliyor = no
SL ve TP fill sonrasinda var   = yes
```

Publisheri ve listenerlari yeni sinyal gelmeden once baslat. Yeni sinyal geldiginde her hedef hesapta yalnizca bir kez acilmasi gerekir.

Notlar: TLV`de orb çalışıyor ama rlv`de bırakıp sadece Liq Narrativeye geçmek gerekebilir.

## Production Channel - Bir ORB EA'nin Birden Fazla Kombinasyonu

ORB kanal destegi artik ana production dosyalarindadir. ORB icin `_Channel` isimli deneysel dosyalari kullanma.

Kullanilacak ana dosyalar:

```text
OrbUltimateEA.mq5
OrbUltimate_ProfessionalPipeline.mqh
OrbUltimate_cTrader_Listener.cs
NinjaTrader/OrbUltimate_NinjaTrader_Listener.cs
Quantower/OrbUltimate_Quantower_Listener.cs
```

Kanal numarasi MT5 publisher ve hedef listener instance'inde ayni olmalidir. Kanal eslesmezse listener fail-closed davranir; emri acmaz, kapatmaz veya sahiplenmez.

### Iki ayri challenge hesabi ornegi

```text
TradersLaunch ORB publisher   = CH 1
TradersLaunch listener        = Bridge Channel 1

TradeDay ORB publisher        = CH 2
TradeDay listener             = Bridge Channel 2
```

Her kombinasyon icin ayri MT5 ORB chart instance'i ac. Her listener kendi hesap/chart instance'inde calisir. Ayni sembol ve TF kullanilsa bile kanal farkliysa event, label, lock, HCBE/protection state, audit ve reverse-close kapsamlarinin tamami ayridir.

### GMT entry window

`WIN ON/OFF`, ORB session matematigini degistirmez; yalnizca yeni trade acilabilecek saatleri ek olarak daraltir.

```text
WIN OFF       = eski davranis; ek saat filtresi yok
08:00-12:00   = GMT 08:00 dahil, 12:00 haric
22:00-03:00   = geceyi asan pencere
00:00-00:00   = tam gun
```

Pencere disinda olusan sinyal daha sonra pencere acilinca gecikmeli olarak acilmaz. Pending retest/imbalance lifecycle da pencere kapaninca temizlenir.

### Diger EA'larin deneysel channel dosyalari

Asagidaki `_Channel` dosyalari ORB disindaki deneysel calismalardir:

Kullanilacak MT5 EA dosyalari:

```text
LiqNarrativeSolVersion_Channel.mq5
LiqNarrativeSol_Advanced_Channel.mq5
LiquidityNarrative_MT5_EA_Channel.mq5
```

Kullanilacak cTrader robotlari:

```text
LiquidityNarrative_cTrader_Listener_Channel.cs
LiqNarrativeSolAdvanced_cTrader_Listener_Channel.cs
```

EA ve listener eslesmesi:

```text
LiqNarrativeSolVersion_Channel.mq5
  Listener: LiquidityNarrative_cTrader_Listener_Channel.cs
  Bridge Latest Path: ...\LiqNarrativeSolBridge_Latest.csv
  Source Filter: LiqNarrativeSol

LiqNarrativeSol_Advanced_Channel.mq5
  Listener: LiqNarrativeSolAdvanced_cTrader_Listener_Channel.cs
  Bridge Latest Path: ...\LiqNarrativeSolAdvancedBridge_Latest.csv
  Source Filter: LiqNarrativeSolAdvanced

LiquidityNarrative_MT5_EA_Channel.mq5
  Listener: LiquidityNarrative_cTrader_Listener_Channel.cs
  Bridge Latest Path: ...\LiquidityNarrativeBridge_Latest.csv
  Source Filter: LiquidityNarrative

```

SolVersion ve normal Liq ayni generic listener kodunu kullanir; cTrader'da iki ayri robot instance'i acilir. Base CSV, `Source Filter`, sembol, TF ve kanal birlikte eslesmeden event kabul edilmez.

Kurulum:

1. Ilk MT5 chart instance'inde dashboard `CH` alanina `1` yaz ve `APPLY CH` butonuna bas.
2. Ikinci kombinasyonda `CH=2`, ucuncude `CH=3` kullan.
3. Her instance icin `PUB ON` yap.
4. cTrader listener instance'inde normal base `Bridge Latest Path` degerini kullan.
5. `Source TF Filter` altindaki `Bridge Channel` alanina MT5 ile ayni sayiyi gir.
6. `Prefer Scoped Latest=true` kullan ve robotu baslat.

ORB kanal 2 ornegi:

```text
MT5 dashboard CH              = 2
Bridge Latest Path            = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest          = true
Source TF Filter              = 15
Bridge Channel                = 2
```

Listener su dosyayi otomatik bulur:

```text
OrbUltimateBridge_Latest_C2_JP225m_15.csv
```

Dosya adini cTrader'a elle `_C2` seklinde yazma. Base `...Bridge_Latest.csv` yolu ve kanal numarasi yeterlidir.

Guvenlik kurallari:

- Kanalsiz eski CSV'ye fallback yoktur. Kanal dosyasi yoksa listener fail-closed bekler.
- CSV icindeki `bridge_channel` ile listener `Bridge Channel` ayni degilse event acilmaz ve tuketilmez.
- Pozisyon label, event lock, HCBE state, audit ve outbox kanal bazinda ayridir.
- Bir kanal diger kanalin pozisyonunu kapatamaz, HCBE yapamaz veya restart sonrasi sahiplenemez.
- `APPLY CH` eski kanali `INIT/detached` olarak emekliye ayirir ve yeni kanala init marker yazar.
- Kanal secimi MT5 restart sonrasinda ayni chart instance'i icin korunur.
