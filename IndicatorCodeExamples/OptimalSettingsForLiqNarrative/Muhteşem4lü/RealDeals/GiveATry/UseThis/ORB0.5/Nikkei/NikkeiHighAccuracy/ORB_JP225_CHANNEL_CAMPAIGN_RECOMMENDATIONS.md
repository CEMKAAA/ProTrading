# ORB JP225 Iki Kanal Kampanya Onerisi

Tarih: 2026-08-25

Bu dosya `0.5Gang` adaylari ile `NikkeiHighAccuracy` klasorundeki ek adaylarin ayni MT5 native-parity kampanyasinda karsilastirilmasindan uretilmistir. Bu bir kazanc garantisi degil, tekrar uretilebilir production adayi konfigurasyonudur.

## Nihai Ikili

Ilk production adayi:

- Kanal 1: `A10`, M5 IMB1M, 1R
- Kanal 2: `N10`, M15 BREAK, 1R
- Baslangic riski: kanal basina `%0.35`
- Ayni anda iki kanal aciksa toplam planlanan risk: yaklasik `%0.70`
- Her MT5 EA ve listener instance'inda kanal numarasi eslesmelidir.

Bu iki kanal ayni sembolde calissa da farkli sinyal TF ve giris motorlari kullanir. Testte gunluk getiri korelasyonu `0.069` cikmistir. Bu nedenle ayni ailenin farkli TP varyantlarini yan yana koymaktan daha anlamli bir cesitlendirmedir.

## Hazir Preset EA Dosyalari

Butun ayarlari asagidaki iki EA'nin input varsayilanlarina yerlestirilmistir:

```text
IndicatorCodeExamples/A10OrbEA.mq5
IndicatorCodeExamples/A10OrbEA.ex5

IndicatorCodeExamples/N10OrbEA.mq5
IndicatorCodeExamples/N10OrbEA.ex5
```

Kullanim:

1. `A10OrbEA` dosyasini JP225 `M5` chartina ekle. EA `Signal TF=M5`, `CH=1`, risk `%0.35`, `PUB ON`, `ONLY ON`, `NAT OFF` olarak gelir.
2. Ilk listener instance'inda `Source TF Filter=5`, `Bridge Channel=1` kullan.
3. `N10OrbEA` dosyasini ayri JP225 `M15` chartina ekle. EA `Signal TF=M15`, `CH=2`, risk `%0.35`, `PUB ON`, `ONLY ON`, `NAT OFF` olarak gelir.
4. Ikinci listener instance'inda `Source TF Filter=15`, `Bridge Channel=2` kullan.

Hazir EA'lar ana `OrbUltimateEA.mq5` dosyasinin birebir kopyasidir. Yalniz bu dokumanda listelenen input varsayilanlari ve build etiketi degistirilmistir; sinyal fonksiyonlari degistirilmemistir.

## Kanal 1 - A10 Core

### EA ve sinyal ayarlari

| Ayar | Deger |
|---|---:|
| Kaynak sembol | `JP225m` |
| Chart TF | `M5` |
| Signal TF | `M5` |
| Bridge Channel | `1` |
| Full Inversion | `OFF` |
| Execution | `SINGLE` |
| Entry | `IMB1M` |
| Target Mode | `RLEG` |
| Target | `TP2 = 1.0R` |
| Exit | `FIXED` |
| HC/BE | `OFF` |
| Pip SL | `ON`, `4500` |
| Auto Session By Symbol | `ON` |
| Session Profile | `AUTO` |
| Broker GMT Offset | `0.0` |
| JP ORB | `09:00-09:15 JST` |
| JP session end | `15:30 JST` |
| Breakout Delay | `5 dakika` |
| Confirm Bars | `1` |
| Closed Bar Breakout | `ON` |
| Entry Window | `OFF` |
| Day Filter | `OFF` |
| Time Exit | `OFF` |
| Filtered Reverse Exit | `OFF / REV HOLD` |
| Post-trade DISP Exit | `OFF / DSP HOLD` |
| ATR Filter | `OFF` |
| Volume Filter | `ON` |
| Volume Multiplier | `1.00` |
| Displacement Filter | `ON` |
| FVG Mode | `REQUIRE` |
| Exit trail start | `XS:NOW`, fakat `FIXED` exitte etkisiz |

### Alti makro rejim

Ilk filtre katmani budur. Asagidaki durum birebir uygulanmalidir.

| Rejim | Durum |
|---|---|
| `TLV - Trend Low Vol` | `ALLOW / ON` |
| `THV - Trend High Vol` | `BLOCK / OFF` |
| `RLV - Range Low Vol` | `BLOCK / OFF` |
| `RHV - Range High Vol` | `BLOCK / OFF` |
| `TR PEND - Transition Pending` | `ALLOW / ON` |
| `TR FRESH - Transition Fresh` | `ALLOW / ON` |

### RF01-RF12

`RF MASTER = ON` olmalidir.

| RF | Durum |
|---|---|
| RF01 | `PASS` |
| RF02 | `PASS` |
| RF03 | `PASS` |
| RF04 | `PASS` |
| RF05 | `PASS` |
| RF06 | `PASS` |
| RF07 | `PASS` |
| RF08 | `PASS` |
| RF09 | `PASS` |
| RF10 | `PASS` |
| RF11 | `PASS` |
| RF12 | `BLOCK` |

### Pipeline ayarlari

MT5 sadece dis listener'a yayin yapacaksa:

```text
PUB ON
ONLY ON
NAT OFF
Bridge Channel = 1
```

cTrader listener:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 5
Bridge Channel = 1
```

Publisher kanal dosyalarini otomatik olarak ayirir:

```text
OrbUltimateBridge_Latest_C1.csv
OrbUltimateBridge_Latest_C1_JP225m_5.csv
```

## Kanal 2 - N10 M15 Break

### EA ve sinyal ayarlari

| Ayar | Deger |
|---|---:|
| Kaynak sembol | `JP225m` |
| Chart TF | `M15` |
| Signal TF | `M15` |
| Bridge Channel | `2` |
| Full Inversion | `OFF` |
| Execution | `SINGLE` |
| Entry | `BREAK` |
| Target Mode | `RLEG` |
| Target | `TP2 = 1.0R` |
| Exit | `FIXED` |
| HC/BE | `OFF` |
| Pip SL | `ON`, `4000` |
| Auto Session By Symbol | `ON` |
| Session Profile | `AUTO` |
| Broker GMT Offset | `0.0` |
| JP ORB | `09:00-09:15 JST` |
| JP session end | `15:30 JST` |
| Breakout Delay | `5 dakika` |
| Confirm Bars | `1` |
| Closed Bar Breakout | `ON` |
| Entry Window | `OFF` |
| Day Filter | `OFF` |
| Time Exit | `OFF` |
| Filtered Reverse Exit | `OFF / REV HOLD` |
| Post-trade DISP Exit | `OFF / DSP HOLD` |
| ATR Filter | `OFF` |
| Volume Filter | `ON` |
| Volume Multiplier | `0.80` |
| Displacement Filter | `ON` |
| FVG Mode | `REQUIRE` |
| Exit trail start | `XS:NOW`, fakat `FIXED` exitte etkisiz |

### Alti makro rejim

| Rejim | Durum |
|---|---|
| `TLV - Trend Low Vol` | `ALLOW / ON` |
| `THV - Trend High Vol` | `BLOCK / OFF` |
| `RLV - Range Low Vol` | `ALLOW / ON` |
| `RHV - Range High Vol` | `BLOCK / OFF` |
| `TR PEND - Transition Pending` | `BLOCK / OFF` |
| `TR FRESH - Transition Fresh` | `BLOCK / OFF` |

### RF01-RF12

`RF MASTER = ON` olmalidir.

| RF | Durum |
|---|---|
| RF01 | `BLOCK` |
| RF02 | `BLOCK` |
| RF03 | `PASS` |
| RF04 | `PASS` |
| RF05 | `BLOCK` |
| RF06 | `PASS` |
| RF07 | `PASS` |
| RF08 | `PASS` |
| RF09 | `PASS` |
| RF10 | `PASS` |
| RF11 | `PASS` |
| RF12 | `PASS` |

### Pipeline ayarlari

MT5 sadece dis listener'a yayin yapacaksa:

```text
PUB ON
ONLY ON
NAT OFF
Bridge Channel = 2
```

cTrader listener:

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 15
Bridge Channel = 2
```

Publisher kanal dosyalarini otomatik olarak ayirir:

```text
OrbUltimateBridge_Latest_C2.csv
OrbUltimateBridge_Latest_C2_JP225m_15.csv
```

## MT5 Native de Calisacaksa

Hem MT5 native hem dis listener ayni sinyali acacaksa ilgili kanalda:

```text
PUB ON
ONLY ON
NAT ON
```

Sadece dis challenge hesabinda islem isteniyorsa `NAT OFF` kalmalidir. Risk yuzdesi her listener hesabinin kendi balance/equity degerinden hesaplanir; MT5 lotu kopyalanmaz.

## Kampanya Sonuclari

Veri araligi: `2021-07-01` - `2026-07-20`. Ilk gercek olaylar 2021 Temmuz sonundan basladigi icin 2021 tam yil degildir.

### Tek kanal

| Kanal | Islem | W | L | WR | Net R | Max DD |
|---|---:|---:|---:|---:|---:|---:|
| A10 | 113 | 69 | 44 | 61.06% | +21.51R | -4.49R |
| N10 | 233 | 141 | 92 | 60.52% | +40.90R | -7.94R |

2025-2026 dokunulmamis test:

| Kanal | Islem | WR | Net R | Max DD |
|---|---:|---:|---:|---:|
| A10 | 32 | 68.75% | +11.01R | -3.09R |
| N10 | 51 | 64.71% | +13.23R | -3.24R |

### Esit riskli iki kanal portfoyu

Portfoy hesabi kanal basina `0.5 portfoy-R` agirligi kullanir. Ornegin `%0.35 + %0.35` riskte bir portfoy-R toplam hesap sermayesinin `%0.70` hareketidir.

| Metrik | Sonuc |
|---|---:|
| Aktif gun | 324 |
| Ortak islem gunu | 22 |
| Iki kanal ayni gun kayip | 5 |
| Ortak kayip / aktif gun | 1.54% |
| Gunluk korelasyon | 0.069 |
| Net portfoy R | +31.21R |
| Max portfoy DD | -4.78R |

Yillik esit-risk portfoy sonucu:

| Yil | Net R | Yil ici DD |
|---|---:|---:|
| 2021 kismi | +0.54R | -1.17R |
| 2022 | +4.85R | -1.73R |
| 2023 | +7.64R | -4.55R |
| 2024 | +6.06R | -2.13R |
| 2025 | +3.70R | -3.17R |
| 2026 kismi | +8.42R | -1.09R |

Ek maliyet stresi:

| Her isleme ek maliyet | Portfoy neti |
|---|---:|
| 0.02R | +27.75R |
| 0.05R | +22.56R |
| 0.10R | +13.91R |

10 gunluk moving-block bootstrap, 20,000 yol:

```text
95% toplam sonuc araligi: +12.40R ile +50.17R
Medyan: +30.73R
Pozitif kapanma orani: %99.965
```

Bootstrap tarihi tekrar ornekler; gelecege dair garanti degildir.

## EOD Trailing Drawdown Analizi

Bu hesap statik baslangic bakiyesi drawdown'i degildir. Her aktif gun sonunda yeni equity zirvesi takip edilmis ve sonraki en dusuk EOD equity degerine kadar olan gerileme olculmustur.

Risk varsayimi:

```text
Kanal 1 risk = %0.35
Kanal 2 risk = %0.35
Es zamanli maksimum planlanan risk = yaklasik %0.70
```

Sonuclar:

| Metrik | Sonuc |
|---|---:|
| Toplam trade | 346 |
| Kazanan trade | 210 |
| Kaybeden trade | 136 |
| Birlesik trade WR | 60.69% |
| Aktif EOD gunu | 324 |
| Pozitif EOD gunu | 193 |
| Negatif EOD gunu | 131 |
| Iki kanalin ayni gun kaybettigi gun | 5 |
| Maks ardisik kaybeden trade | 6 |
| Bu 6 trade'in hesap etkisi | -2.17% |
| Maks ardisik negatif EOD gunu | 5 |
| Bu 5 gunun hesap etkisi | -1.81% |

En kotu herhangi-bir-zirveden drawdown:

```text
EOD equity zirvesi: 2023-09-04, baslangica gore +12.2999%
EOD trough:         2024-02-28, baslangica gore  +8.9553%
Peak-to-trough:                               -3.3446%
Eski zirvenin geri alinmasi: 2024-06-26
```

`-%3.3446`, baslangic sermayesinin yuzde puani cinsindendir. Zirvedeki gercek equity'ye oranlanirsa yaklasik `-%2.98` gerilemedir.

EOD trailing limit `-%4.00` ise:

```text
Tarihsel en kotu EOD DD: -3.3446%
Kalan tampon:             0.6554 yuzde puani
Limit kullanimi:          %83.62
Tarihsel ihlal:           0
```

Drawdown esigi gecisleri:

| EOD DD esigi | Ayri asagi gecis | Esik altindaki aktif gun |
|---|---:|---:|
| -1% | 24 | 108 |
| -2% | 10 | 46 |
| -3% | 4 | 5 |
| -4% | 0 | 0 |

Bu sonuc `%4` EOD trailing limite teorik olarak sigiyor, ancak marj genis degildir. Slippage, komisyon, futures/CFD geometri farki ve iki emrin ayni gun korelasyonunun tarihtekinden daha yuksek olmasi tamponu tuketebilir. `%0.35 + %0.35` bu nedenle baslangic tavani olarak kalmalidir; forward sonuc olmadan yukseltilmemelidir.

Gunluk EOD seri dosyasi:

```text
logs/orb_jp225_two_channel_campaign_20260825/analysis_combined/eod_drawdown_035_each.csv
```

## Yedek Adaylar

### Q10

`N10` ile ayni M15 BREAK 1R ailesidir; tek fark ATR filtresinin de acik olmasidir.

- 214 islem, 61.68% WR, +42.56R, -8.90R DD
- A10 ile portfoy: +32.04R, -5.26R DD
- N10 ile korelasyon: `0.956`

N10 yerine denenebilir; N10 ile birlikte ikinci kanal olarak kullanilmamalidir.

### M05

M15 IMB1M, 0.5R, pip SL 4000, VOL 1.0, DISP ON, FVG REQUIRE.

- 211 islem, 74.88% WR, +18.67R, -6.22R DD
- Her takvim yilinda pozitif
- A10 ile portfoy: +20.09R, -4.22R DD

Daha yuksek WR isteyen fakat daha dusuk expectancy kabul eden konservatif yedektir.

## Elenenler

- `B05`: 2025-2026 test neti yalnizca `+0.09R`; onceki ikinci kanal tavsiyesinin yerini N10 aldi.
- `J05`: 2024 ve 2026 negatif.
- `K15`: 2021 ve 2022 negatif, drawdown yuksek.
- `L15`: 2024 validation negatif.
- `O10`: 2025-2026 test negatif.
- `R10`: yuksek frekansli fakat `-25.68R` DD; challenge icin uygun degil.
- `S075`: 2025-2026 test `-2.99R`; kisa ekran goruntusu basarisi uzun doneme tasinmadi.
- A05/A075/A10'u birlikte kullanmak: ayni sinyal ailesi ve yuksek korelasyon nedeniyle gercek cesitlendirme degil.

## Yeniden Uretim Dosyalari

```text
logs/orb_jp225_two_channel_campaign_20260825/candidate_manifest.csv
logs/orb_jp225_two_channel_campaign_20260825/candidate_manifest_stage3.csv
logs/orb_jp225_two_channel_campaign_20260825/jobs_stage2_5y.json
logs/orb_jp225_two_channel_campaign_20260825/jobs_stage3_additional_5y.json
logs/orb_jp225_two_channel_campaign_20260825/events/
logs/orb_jp225_two_channel_campaign_20260825/analysis_combined/
```

## Production Kontrol Listesi

1. Kanal 1 EA'da `CH=1`, listener'da `Bridge Channel=1`, `Source TF Filter=5`.
2. Kanal 2 EA'da `CH=2`, listener'da `Bridge Channel=2`, `Source TF Filter=15`.
3. Her iki listener'da `Prefer Scoped Latest=true`.
4. Kanal 1 RF master ON ve yalniz RF12 BLOCK.
5. Kanal 2 RF master ON ve yalniz RF01/RF02/RF05 BLOCK.
6. Inversion iki kanalda da OFF.
7. Kanal basina baslangic riski `%0.35`; ayni sembolde ayni anda toplam `%0.70` risk ihtimali kabul edilmeden artirilmaz.
8. Listener logunda okunan dosya adinda dogru `_C1_..._5` veya `_C2_..._15` scope'u gorulmeden live emir acilmaz.
9. Ayar degisikliginden sonra dashboarddaki APPLY dugmeleri kullanilir ve bridge INIT satirinda channel/risk/TF tekrar kontrol edilir.
