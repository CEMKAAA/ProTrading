# ORB JP225 Ikinci Iki-Kanal Production Adayi

Tarih: 2026-08-25

Bu ikili, ana `A10 + N10` ikilisine alternatif olarak secilmistir. Dort kanal ayni anda calistirilmak icin tasarlanmamistir.

## Onerilen Ikili

- Kanal 3: `A05`, M5 IMB1M, 0.5R
- Kanal 4: `Q10`, M15 BREAK, 1R + ATR filtresi
- Risk: kanal basina `%0.30`
- Toplam planlanan gunluk risk: `%0.60`
- Full inversion: iki kanalda da `OFF`

## Hazir EA Dosyalari

Kanal 3 - A05:

```text
IndicatorCodeExamples/A05OrbEA.mq5
IndicatorCodeExamples/A05OrbEA.ex5
```

Kanal 4 - Q10:

```text
IndicatorCodeExamples/Q10OrbEA.mq5
IndicatorCodeExamples/Q10OrbEA.ex5
```

Kurulum:

1. `A05OrbEA` dosyasini JP225 `M5` chartina ekle. Preset `Signal TF=M5`, `CH=3`, risk `%0.30`, `PUB ON`, `ONLY ON`, `NAT OFF` olarak gelir.
2. A05 listener instance'inda `Source TF Filter=5` ve `Bridge Channel=3` kullan.
3. `Q10OrbEA` dosyasini ayri JP225 `M15` chartina ekle. Preset `Signal TF=M15`, `CH=4`, risk `%0.30`, `PUB ON`, `ONLY ON`, `NAT OFF` olarak gelir.
4. Q10 listener instance'inda `Source TF Filter=15` ve `Bridge Channel=4` kullan.

Iki listener'da da base path aynidir; scoped dosya secimi TF ve kanal ile izole edilir:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
```

## Kanal 3 - A05

### Ana ayarlar

| Ayar | Deger |
|---|---:|
| Symbol | `JP225m` |
| Chart TF | `M5` |
| Signal TF | `M5` |
| Bridge Channel | `3` |
| Full Inversion | `OFF` |
| Execution | `SINGLE` |
| Entry | `IMB1M` |
| Target Mode | `RLEG` |
| Target | `TP1 = 0.5R` |
| Exit | `FIXED` |
| HC/BE | `OFF` |
| Pip SL | `ON`, `4500` |
| Risk | `%0.30` |
| Auto Session | `ON / AUTO` |
| Broker GMT Offset | `0.0` |
| Breakout Delay | `5 dakika` |
| Confirm Bars | `1` |
| Closed Bar Breakout | `ON` |
| Entry Window | `OFF` |
| Day Filter | `OFF` |
| Time Exit | `OFF` |
| REV Exit | `OFF / HOLD` |
| DISP Block Exit | `OFF / HOLD` |
| ATR Filter | `OFF` |
| Volume Filter | `ON`, multiplier `1.00` |
| Displacement Filter | `ON` |
| FVG | `REQUIRE` |

### Alti makro rejim

| Rejim | Durum |
|---|---|
| TLV | `ALLOW` |
| THV | `BLOCK` |
| RLV | `BLOCK` |
| RHV | `BLOCK` |
| TR PEND | `ALLOW` |
| TR FRESH | `ALLOW` |

### RF01-RF12

`RF MASTER = ON`

| RF | Durum |
|---|---|
| RF01 | PASS |
| RF02 | PASS |
| RF03 | PASS |
| RF04 | PASS |
| RF05 | PASS |
| RF06 | PASS |
| RF07 | PASS |
| RF08 | `BLOCK` |
| RF09 | PASS |
| RF10 | PASS |
| RF11 | `BLOCK` |
| RF12 | PASS |

### Listener

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 5
Bridge Channel = 3
```

## Kanal 4 - Q10

### Ana ayarlar

| Ayar | Deger |
|---|---:|
| Symbol | `JP225m` |
| Chart TF | `M15` |
| Signal TF | `M15` |
| Bridge Channel | `4` |
| Full Inversion | `OFF` |
| Execution | `SINGLE` |
| Entry | `BREAK` |
| Target Mode | `RLEG` |
| Target | `TP2 = 1.0R` |
| Exit | `FIXED` |
| HC/BE | `OFF` |
| Pip SL | `ON`, `4000` |
| Risk | `%0.30` |
| Auto Session | `ON / AUTO` |
| Broker GMT Offset | `0.0` |
| Breakout Delay | `5 dakika` |
| Confirm Bars | `1` |
| Closed Bar Breakout | `ON` |
| Entry Window | `OFF` |
| Day Filter | `OFF` |
| Time Exit | `OFF` |
| REV Exit | `OFF / HOLD` |
| DISP Block Exit | `OFF / HOLD` |
| ATR Filter | `ON` |
| ATR period | `14` |
| Min/Max ORB ATR | `15% / 80%` |
| Volume Filter | `ON`, multiplier `0.80` |
| Displacement Filter | `ON` |
| FVG | `REQUIRE` |

### Alti makro rejim

| Rejim | Durum |
|---|---|
| TLV | `ALLOW` |
| THV | `BLOCK` |
| RLV | `ALLOW` |
| RHV | `BLOCK` |
| TR PEND | `BLOCK` |
| TR FRESH | `BLOCK` |

### RF01-RF12

`RF MASTER = ON`

| RF | Durum |
|---|---|
| RF01 | `BLOCK` |
| RF02 | `BLOCK` |
| RF03 | PASS |
| RF04 | PASS |
| RF05 | `BLOCK` |
| RF06 | PASS |
| RF07 | PASS |
| RF08 | PASS |
| RF09 | PASS |
| RF10 | PASS |
| RF11 | PASS |
| RF12 | PASS |

### Listener

```text
Bridge Latest Path = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Prefer Scoped Latest = true
Source TF Filter = 15
Bridge Channel = 4
```

## Yayin Modu

Yalniz dis listener hesabi islem acacaksa iki EA'da:

```text
PUB ON
ONLY ON
NAT OFF
```

MT5 native pozisyonu da istenirse `NAT ON` yapilir.

## Walk-Forward Sonuclari

Secim protokolu:

- Discovery: 2021-2023
- Validation: 2024
- Untouched test: 2025-2026
- Her iki kanal validation ve testte ayri ayri pozitif
- Portfoy her takvim yilinda pozitif

### Tek kanal

| Kanal | Trade | W | L | WR | Net R | DD | 2024 | 2025-26 test |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A05 | 107 | 80 | 27 | 74.77% | +9.69R | -4.59R | +2.54R | +4.60R |
| Q10 | 214 | 132 | 82 | 61.68% | +42.56R | -8.90R | +8.82R | +14.26R |

### Esit riskli portfoy

| Metrik | Sonuc |
|---|---:|
| Aktif gun | 300 |
| Ortak islem gunu | 21 |
| Ortak kayip gunu | 4 |
| Ortak kayip / aktif gun | 1.33% |
| Gunluk korelasyon | 0.090 |
| Net portfoy R | +26.13R |
| Max portfoy DD | -5.53R |

Yillik portfoy R:

| Yil | Net R |
|---|---:|
| 2021 kismi | +1.04R |
| 2022 | +4.01R |
| 2023 | +5.97R |
| 2024 | +5.68R |
| 2025 | +5.27R |
| 2026 kismi | +4.17R |

## EOD Trailing DD - Risk %0.30 + %0.30

| Metrik | Sonuc |
|---|---:|
| Toplam trade | 321 |
| W / L | 212 / 109 |
| WR | 66.04% |
| Pozitif / negatif EOD gunu | 195 / 105 |
| Net hesap etkisi | +15.68% |
| Worst EOD trailing DD | -3.317% |
| Maks ardisik loss | 6 trade / -1.86% |
| Maks ardisik negatif EOD | 5 gun / -1.86% |
| %4 limite kalan tampon | 0.683 yuzde puani |

Worst drawdown:

```text
Peak:     2023-09-04, equity +9.9283%
Trough:   2023-12-22, equity +6.6109%
DD:       -3.3174%
Recovery: 2024-10-30
```

Ek maliyet stresi:

| Her trade'e ek maliyet | Net portfoy R |
|---|---:|
| 0.02R | +22.92R |
| 0.05R | +18.10R |
| 0.10R | +10.08R |

10 gunluk moving-block bootstrap, 20,000 yol:

```text
95% aralik: +11.47R ile +41.70R
Medyan: +26.63R
Pozitif sonuc: %99.965
```

## Neden D05 + Q10 Degil

`D05 + Q10` portfoy DD/verim oraninda daha yuksek gorundu. Ancak D05 tek basina:

- 2024 validation'da negatiftir.
- 2025-2026 test neti yalnizca `+0.35R` seviyesindedir.

Bu nedenle Q10'un D05 zayifligini gizledigi bir pair production adayi olarak kabul edilmedi.

## Kritik Kullanim Siniri

Bu ikili `A10 + N10` ikilisinin alternatifidir, tamamlayici dort-kanal paketi degildir:

- A05, A10 ile ayni IMB1M sinyal ailesini kullanir.
- Q10, N10'un ATR-filtreli yakin akrabasidir; N10/Q10 korelasyonu yaklasik `0.956`dir.
- Iki pair ayni hesapta birlikte tam riskle calistirilirsa tekrarlanan JP225 maruziyeti olusur.
- Production'da ya `A10 + N10` ya da `A05 + Q10` secilmelidir.

## Arastirma Dosyalari

```text
logs/orb_jp225_two_channel_campaign_20260825/analysis_combined/second_pair_screen.csv
logs/orb_jp225_two_channel_campaign_20260825/analysis_combined/second_pair_a05_q10_eod_030_each.csv
```
