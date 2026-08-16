# Quantower MT5 Bridge Setup

Bu klasordeki listenerlar:

- `LiqNarrativeSolVersion_Quantower_Listener.cs`
- `LiqNarrativeSolAdvanced_Quantower_Listener.cs`
- `OrbUltimate_Quantower_Listener.cs`
- `NasUltimate_Quantower_Listener.cs`

Dort listener da `ProductionFileBridgeQuantowerCore.cs` dosyasini kullanir. MT5 sinyal matematigine dokunmaz; CSV sinyalini okur, riski Quantower hesabinda yeniden hesaplar ve emri Quantower'a yollar.

## 1. Bir Defalik Kurulum

1. Visual Studio 2022 Community kur.
2. Visual Studio Installer icinden `.NET desktop development` workload'unu kur.
3. Quantower'i ac.
4. Quantower Algo icin resmi Visual Studio extension'ini kur.
5. Quantower'da `Settings -> General -> Algo` bolumunu ac.
6. Visual Studio baglantisina izin ver ve Quantower ile Visual Studio portlarinin ayni oldugunu kontrol et.
7. Visual Studio'yu ac.
8. `Create a new project` sec.
9. Quantower strategy sablonunu sec ve projeye `ProTradingSystemQuantowerListeners` adini ver.
10. Sablonun olusturdugu ornek strategy dosyasini projeden kaldir.
11. `Solution Explorer -> proje -> Add -> Existing Item` sec.
12. Bu klasordeki su bes dosyayi projeye ekle:
    - `ProductionFileBridgeQuantowerCore.cs`
    - `LiqNarrativeSolVersion_Quantower_Listener.cs`
    - `LiqNarrativeSolAdvanced_Quantower_Listener.cs`
    - `OrbUltimate_Quantower_Listener.cs`
    - `NasUltimate_Quantower_Listener.cs`
13. `Build -> Build Solution` yap.
14. Quantower'i acik tut. Quantower extension basarili build edilen DLL'i Quantower'a aktarir.

Quantower bu bilgisayarda kurulu degilse `TradingPlatform.BusinessLayer.dll` bulunamaz ve proje derlenemez. Once Quantower ile resmi extension kurulmalidir.

## 2. MT5 Publisher'i Hazirla

1. Kullanacagin MT5 EA'yi dogru charta ekle.
2. EA dashboard'unda `PUB ON` yap.
3. Risk yuzdesini EA dashboard'unda girip `APPLY RISK` ile uygula.
4. Standart EA kullaniyorsan listener'da `Bridge Channel = 0` birak.
5. `_Channel.mq5` deneysel EA kullaniyorsan MT5'te kanali `APPLY CH` ile uygula ve listener'a ayni kanal numarasini gir.

## 3. Quantower Listener'i Baslat

1. Quantower ana menuden `Strategies Manager` panelini ac.
2. `+` ile yeni strategy instance ekle.
3. Asagidaki listenerlardan dogru olani sec.
4. `Symbol` alaninda emrin acilacagi Quantower sembolunu sec.
5. `Account` alaninda emrin acilacagi Quantower hesabini sec.
6. Ayarlari kontrol et.
7. Once demo/SIM hesapta strategy'yi `Run` yap.
8. Strategy logunda `running scope=... file=... channel=...` satirini gor.
9. MT5'te yeni bir sinyal gelene kadar bekle. Listener baslangicta mevcut eski latest sinyalini varsayilan olarak acmaz.

## 4. Varsayilan Hatlar

### Sol Version

```text
Bridge Latest Path = %APPDATA%\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv
Source TF Filter = 60
Source Filter = LiqNarrativeSol|
Bridge Channel = 0
```

### Sol Advanced

```text
Bridge Latest Path = %APPDATA%\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv
Source TF Filter = 60
Source Filter = LiqNarrativeSolAdvanced|
Bridge Channel = 0
```

### ORB Ultimate

```text
Bridge Latest Path = %APPDATA%\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Source TF Filter = 15
Source Filter = OrbUltimate|
Bridge Channel = 0
```

### NAS Ultimate SATS PartialNoBE

```text
Bridge Latest Path = %APPDATA%\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv
Source TF Filter = 5
Source Filter = NasUltimate|
Source Symbol Aliases CSV = BTCUSDm,BTCUSD,BTCUSDT,XBTUSD
Bridge Channel = 0
```

`Source TF Filter` mutlaka NAS EA'nin calistigi MT5 chart timeframe'inin dakika karsiligi olmalidir. Ornegin M1 icin `1`, M5 icin `5` gir.

## 5. Kanal Kullanimi

Standart publisher:

```text
MT5 EA = normal .mq5
Quantower Bridge Channel = 0
```

Kanal publisher:

```text
MT5 EA = *_Channel.mq5
MT5 dashboard channel = 1
Quantower Bridge Channel = 1
```

Kanal 2 icin iki tarafta da `2` gir. Kanal listener'i sadece `bridge_channel` kolonu kendi kanalina esit olan ve `_Latest_C<kanal>_...csv` dosyasindan gelen sinyali kabul eder. Kanal eslesmezse emir acmaz veya pozisyon kapatmaz.

## 6. Baska Sembol Kullanimi

Ornek: MT5 `JP225m`, Quantower `NKD`:

```text
Symbol = Quantower'daki NKD kontrati
Source Symbol Aliases CSV = JP225m,JP225,JPN225m,JPN225
Rebase Levels To Live = true
Rebase Only If Symbol Differs = true
Require Source Symbol = true
```

Listener mutlak MT5 JP225 fiyatini NKD'ye kopyalamaz. MT5 entry-SL/TP/HCBE mesafelerini Quantower'daki canli entry fiyatina tasir.

Ornek: MT5 `BTCUSDm`, Quantower BTC futures veya micro BTC futures:

```text
Symbol = Quantower hesabinda gercekten trade edilebilen BTC/MBT kontrati
Source Symbol Aliases CSV = BTCUSDm,BTCUSD,BTCUSDT,XBTUSD
Rebase Levels To Live = true
Rebase Only If Symbol Differs = true
Require Source Symbol = true
Block If Min Qty Exceeds Risk = true
```

BTC CFD ile futures fiyatlari birebir ayni olmak zorunda degildir. Listener mutlak seviyeleri kopyalamak yerine MT5 entry-SL, entry-TP ve entry-HCBE mesafelerini Quantower fill fiyatina rebase eder. Risk hesabi Quantower kontratinin kendi tick size ve tick cost degerleriyle yapilir. Minimum bir kontrat izin verilen riski asiyorsa emir fail-closed engellenir; bu durumda varsa micro kontrati sec.

Ornek: MT5 ve Quantower ayni CFD fiyat tabanini kullaniyorsa `Rebase Levels To Live` yine acik kalabilir. Rebase yalniz ham sembol adlari farkliysa uygulanir.

## 7. Risk ve Koruma

Varsayilan production ayarlari:

```text
Use Risk Quantity = true
Use Bridge Risk % = true
Fixed Risk Capital = 0
Block If Min Qty Exceeds Risk = true
Post Fill Risk Guard = true
Fail If Exact Protection Fails = true
Manage HCBE = true
Block Netting Scope Conflict = true
```

`Fixed Risk Capital = 0` iken risk Quantower hesabinin kendi `Balance` degerinden hesaplanir. MT5 lotu veya MT5 bakiyesi kopyalanmaz.

Listener fill sonrasinda pozisyona bagli exact SL ve TP emirleri kurar. Koruma dogrulanamazsa veya fill sonrasi risk izin verilenden buyukse pozisyonu kapatmayi tekrar tekrar dener.

## 8. Coklu Instance Kurali

Farkli EA, TF veya kanal instance'lari ayri scope kullanir. Bir instance yalniz kendi state dosyasinda kayitli Quantower position ID'lerini kapatabilir veya HCBE yapabilir.

Ayni hesap + Quantower sembolu + EA kaynagi + TF + kanal + CSV yolu ile ikinci bir listener yanlislikla baslatilirsa exclusive scope lease ikinci instance'i fail-closed durdurur. Strategy logunda `another listener already owns scope` gorursun.

Netting hesapta ayni hesap + ayni Quantower sembolu uzerinde iki ayri strategy pozisyonu broker tarafinda tek pozisyona birlesebilir. Bu durumda kusursuz izolasyon teknik olarak mumkun degildir. `Block Netting Scope Conflict = true` bu senaryoda yeni emri fail-closed engeller. Ayni sembolde paralel kanal kullanmak icin hedging destekli hesap veya ayri Quantower hesaplari kullan.

## 9. Canliya Gecmeden Once Kontrol

1. SIM hesabinda yeni BUY sinyali bekle.
2. Quantower entry, SL ve TP mesafelerini MT5 ile karsilastir.
3. Quantower lot/kontrat riskini hesap bakiyesine gore kontrol et.
4. HCBE tetiginde bir kez partial close ve kalan pozisyonda BE SL oldugunu kontrol et.
5. Ters sinyalde sadece ayni listener scope'una ait pozisyonun kapandigini kontrol et.
6. Listener'i restart et ve acik pozisyonu state dosyasindan yeniden sahiplendigini logdan kontrol et.
7. Ancak bunlardan sonra canli hesapta `Run` yap.

Audit dosyalari:

```text
%LOCALAPPDATA%\ProTradingSystem\QuantowerBridge\audit\QuantowerBridge_YYYYMMDD.csv
```

State ve event claim dosyalari kucuktur; tick bazli log yazilmaz. Aylarca calismada GB seviyesinde log sismesi beklenmez.

## 10. Bu Makinedeki Gercek API Dogrulamasi

Quantower kurulumu:

```text
C:\Quantower\TradingPlatform\v1.145.17
```

Listener kaynaklarinin tamami `TradingPlatform.BusinessLayer.dll` surum `1.145.17.0` ile derlenmistir:

```text
Build succeeded
0 warnings
0 errors
```

Bu makine icin production assembly su konuma yuklenmistir:

```text
C:\Quantower\TradingPlatform\v1.145.17\bin\Scripts\Strategies\ProTradingSystemQuantowerListeners.dll
```

DLL yuklendikten sonra Quantower'i yeniden baslat. Ardindan `Strategies Manager` icinde listener instance'ini elle ekleyip `Run` yap; DLL kopyalamak tek basina bir strategy instance baslatmaz.

Bu derleme API uyumlulugunu dogrular. Gercek emir, minimum kontrat, tick cost, protection ve fill davranisi bagli olunan broker/prop connector'una ait oldugu icin ilk calistirma yine SIM hesapta yapilmalidir.
