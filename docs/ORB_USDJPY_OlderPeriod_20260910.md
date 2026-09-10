# USDJPY: Eski Donemde Sabit ML Modelleri

## Veri Siniri

Istenen kontrol: yaklasik son 10 yilin onceki bes yili, 2016-2021.
Mevcut Exness-MT5Trial15 USDJPYm arsiviyle tam bes yillik intraday test
dogrulanamadi. M1 ve M5 sorgulari 2016 icin ayri ayri yalnizca 310 bar
dondurdu. Bu dakika verisi yogunlugu degil; dosyanin 2016 adini tasimasi
backtest icin yeterli degil. 2017 de kismi kapsama sahip.

Puanlamadan ONCE veri kalitesi nedeniyle ana karsilastirma araligi
**2018-01-01 <= tarih < 2021-09-09** olarak sabitlendi. 2018-2021 yillarinda
M1/M5/M15/H1/H2/H4/D1 kapsam, kronoloji ve OHLC kontrolleri yapildi.
Bu rapor tam 10 yil veya tam eski bes yil test edilmis iddiasinda degildir.

## Yontem

- 22 USDJPY stratejisinin ayarlari onceki kampanya snapshot'lariyla dogrulandi.
- Orijinal kampanyanin kaynak kopyasi kullanildi; sadece arastirma cikti
  klasoru ve 2021 veri gozlem tarihi degisti. NAS ve rejim veri yukleyicileri
  de 2021'e sabitlendi. Production dosyalarina dokunulmadi.
- 44 mevcut model, iki aile halinde test edildi: MLP ve net-R regresyonu.
- Agirliklar, scaler ve esikler degismedi; yeniden egitim veya optimizasyon yok.
- Esas sonuc tablosu, bu testten ONCE validation ile secilmis 22 modeli kullanir.
- Model dosyalarinin SHA-256 degerleri testten once/sonra kontrol edildi.
- Onceki egitim donemi ile bu testin islem tarihleri ortusmuyor.
- Kalite kapsaminda 17.584 etiketli strateji-islem satiri kullanildi; bunlar
  benzersiz veya bagimsiz piyasa olaylari degildir. Bes acik/gecersiz etiket
  egitim/test sonucuna katilmadi. Bu kapsamdaki feature-gecersiz satir sayisi 0.
- Ayni ilk maliyet varsayimlari korundu: 10 point fallback spread ve eski
  tarihsel spread mantigi; sifir ilave komisyon/slippage. Gercek broker
  maliyet garantisi verilmez.
- ML etkisi temel lifecycle net-R etiketlerinin giris-veto alt kumesidir;
  hesap seviyesinde yeni pozisyon cakismasi/fill simulasyonu degildir.

## Sonuc

Onceden secilmis 22 modelden **14'u net R'yi iyilestirdi, 2'si kotulestirdi,
6'si ayni kaldi**. Ortanca net-R farki +4,39R. Ayni kalanlarin biri bilerek
NO VETO olarak saklanmis modeldir; digerlerinde bu veri uzerinde eleme olmadi.

| Strateji | Islem: once / ML | WR: once / ML | Net R: once / ML | Kapanis DD: once / ML |
|---|---:|---:|---:|---:|
| 1RYildiz | 484 / 296 | %53,5 / %56,1 | +2,64 / +15,98 | 33,75R / 19,47R |
| 0.5RGoodUsdjpy | 951 / 660 | %62,1 / %63,6 | -20,97 / -3,23 | 51,97R / 27,72R |
| usdjpy10RVeryHighWRsETUP | 869 / 576 | %86,5 / %86,5 | -20,08 / -12,47 | 28,36R / 18,60R |
| HighfreqHighWRusdjpyV2 | 909 / 689 | %78,2 / %76,3 | -4,45 / -12,46 | 13,13R / 15,73R |

Muhtesem4lu #2, 1RYildiz ile ayni islem/sonuc dizisini verir; ikinci bagimsiz
basari sayilmamali. #3 ve #4 icin de kutuphanede ayni-sonuc esleri var.
Strateji R'leri bir portfoy gibi toplanmamali.

### 1RYildiz Yil Kirilimi

| Yil | Filtresiz net R | ML net R |
|---|---:|---:|
| 2018 | +0,27 | +1,75 |
| 2019 | -13,24 | -6,19 |
| 2020 | -2,52 | +11,00 |
| 2021, 9 Eylul oncesi | +18,13 | +9,43 |

Bu model bile her yil kazanmiyor veya her yil temel stratejiyi gecmiyor.
Orneklemdeki diger modellerin cogunda iyilesme, sadece daha az zarar demek.
Bu sonuc, tum ML filtreleri otomatik kullanma veya overfit yok deme gerekcesi
degildir. Modeller gelecekteki donemde egitilip daha eski donemde sinandigi
icin bu **geriye donuk rejim aktarim testi**, kronolojik forward test degil.
Stratejilerin insan tarafindan gecmis chartlarla secilmesi de bagimsizlik
iddiasini sinirlar. Bu sonuca gore yeni model/esik secimi yapilmadi.

## Kanit Dosyalari

`logs/OrbMLPriorFive_20260910/coverage.csv`: 91 yil/TF kapsama kaydi.

`logs/OrbMLPriorFive_20260910/manifest_USDJPYm.tsv`: 22 tamamlanmis export.

`logs/OrbMLPriorFive_20260910/results/Results.md`: 22 secilmis modelin tam tablosu.

`logs/OrbMLPriorFive_20260910/results/all_models.csv`: 44 modelin sonuclari.

`logs/OrbMLPriorFive_20260910/results/by_year.csv`: her modelin yillik kirilimi.

`logs/OrbMLPriorFive_20260910/results/integrity.json`: veri hash'leri, donem
ayrimi, ayni ayarlar ve dislanan satir sayilari.

CSV arsivi `Common\Files\OrbMLPriorFive_20260910\Datasets` altinda, son bes
yillik egitim CSV'lerinden ayri tutulur. Hicbir model productiona yayinlanmadi.
