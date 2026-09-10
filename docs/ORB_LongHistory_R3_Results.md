# Uzun Gecmisle Egitim Ve Mevcut ML Modelleriyle Karsilastirma

## Uygulama

2018-2026 araligindaki uzun gecmisle egitim deneyi tamamlandi. Mevcut
modellerin hicbiri degistirilmedi, devre disi birakilmadi veya yeniden egitilip
uzerine yazilmadi. Kodda bu kampanyanin production'a model yazma yolu yok.

Su anda dogrulanmis uzun donem strateji CSV'leri olan **22 USDJPY stratejisi**
kullanildi. Bu tur JP225/USTEC'nin ham broker gecmisinin bulunmadigi anlamina
gelmez; onlarin ayni uzunlukta ve ayni ayarlardaki strateji exportlari burada
dogrulanmadi. 53 stratejinin tumune sekiz yillik test yaptik iddiasi yok.

## Tarih Plani

| Bolum | Aralik | Amac |
|---|---|---|
| Nihai egitim | 2018-01-01 <= t < 2024-09-09 | Yaklasik 6,7 yillik egitim gecmisi |
| Kalibrasyon | 2024-09-09 <= t < 2025-09-09 | Bir yillik esik dogrulamasi |
| Son test | 2025-09-09 <= t < 2026-09-09 | Son bir yilin dondurulmus testi |

MLP, egitim bolumunun en yeni %20'sini kronolojik erken durdurma icin
kullanir; bu, esik kalibrasyonunun yapildigi sonraki yildan ayridir. Model
ailesi seciminde kullanilan uc ic zaman katlamasi, son kalibrasyon yilindan
once tamamlanir. Boylece son yil egitim, early stopping veya esik secimine
girmez. Tum sinirlarda sonucun sonraki bolumden fiyat kullanmamasi icin
24 saatlik etiket purge uygulanir; siniri asan islemler sayimdan cikar.

Iki dogrulanmis export birlestirildi. Ayar/maliyet snapshot'lari, kimlikler,
oz nitelik semasi ve dosya hash'leri dogrulandi. 41.627 kullanilabilir
strateji-islem satiri var. Eski export 2021-09-09'da, yeni export 2021-09-15'te
basliyor: **alti gunluk export boslugu** doldurulmadi, gizlenmedi. Bu nedenle
sonuc tamamen kesintisiz bir sekiz yillik hesap replay'i degildir.

Son bir yilda 4.780 test satiri var. Alti mevcut modelin orijinal kalibrasyon
tarihi ortak test baslangicini astigi icin karsilastirmada yalnizca iki modelin
de bilgi ufkundan sonraki satirlar kullanildi: toplam **4.764 eslesmis satir**.
Bu tarih kisitlamasi yeni model lehine veya eski model aleyhine sonuc
secerek yapilmadi; bilgi tarihinden mekanik olarak hesaplandi.

Tarihler broker zaman eksenindedir. Bu son yil onceki arastirmalarda
incelendiginden, bu egitim icin disarida tutulan testtir; butun proje icin
hic gorulmemis bir holdout oldugu iddia edilmez.

## Egitilen Modeller

Her strateji yalnizca kendi CSV satirlarini kullanir. Dort sabit aile:

- Mevcut 50 oz nitelikli net-R tasarimi, Ridge alpha=100.
- Mevcut sig boosted-tree tasarimi, 7 yaprak, 80 iterasyon, minimum yaprak 30,
  L2=10, sabit seed.
- Mevcut 40 oz nitelikli MLP ailesi, 16 ReLU noron, alpha=10, en fazla 200 epoch,
  kronolojik erken durdurma.
- R2'deki stratejiye ozel rejim sapmasi modeli, ceza 400.

Bu model secimi yeni egitimin deney butcesidir; mevcut modellerin hangi
alpha/esikle egitildigi degistirilmedi. Rejimler ilk modellerde de zaten
mevcuttu. Dolayisiyla bu deney yalnizca "rejim eklemenin" olcumu degil,
uzun gecmis ve sabit aday aileleriyle yeni egitim/validation olcumudur.

## Overfit Duyarli Skor

Tek bir sayiyi "overfit olasiligi" diye adlandirmadim. Boyle bir olasiligi
guvenilir bicimde hesapladigimizi soyleyecek bilgi yok. Bunun yerine,
testten once yazilmis bir **dayaniklilik fayda skoru** kullanildi.

Her kronolojik dogrulama bolumunde:

```text
g = (filtreli R - filtresiz R) / aday islem sayisi
s = (filtreli R - aylik islem sayisi eslestirilmis rastgele beklenen R) / N
e = min(g, s)
d = (filtresiz DD - filtreli DD) / N
o = max(0, egitimdeki e - dogrulamadaki e)

On-test skor = 100 * [ortalama(e) + 0.25*ortalama(d)
                     - standart_sapma(e) - ortalama(o)]
```

Yani model sadece daha yuksek PnL ile puan almiyor. Donemler arasinda cok
degisiyorsa veya egitimde guzel gorunup sonraki donemde zayifliyorsa puani
dusuyor. Katsayilar sonucu gordukten sonra degistirilmedi. Uc ic katlama,
en az iki pozitif katkili katlama ve pozitif skor arandi. Nihai kalibrasyonda
katki kaybolursa yine model secilmedi.

Son yilda eski ve yeni modele ayni betimleyici TestRobustness formulu
uygulandi: ekonomik katki + DD katkisi - ceyreklik oynaklik - bootstrap
belirsizlik cezasi. Bu **yeni bir model secme/threshold optimizasyon turu degil**.
Mevcut modelin gecmise ait egitim iyimserligi, zaten gordugu tarihlerde
tekrar hesaplanip bagimsiz ileri test gibi sunulmadi. Bu karsilastirma eksigi
"bilinmiyor" olarak kaydedildi, sifir kabul edilmedi.

Skorun siniri somut: daha az islem alan bir adayin belirsizlik cezasi daha
dusuk olabilir ve skor yukselebilir, ama PnL/DD daha kotu olabilir. Bu nedenle
skor tek basina degisim yetkisi degil. PnL, DD, eslesmis istatistiksel kanit,
on-test tutarlilik ve yeni forward/replay ayri kosullar olarak kaldi.

## Sonuclar

Testten once iki stratejide yeni model secildi. Diger 20 stratejide arastirma
politikasinin karari NO_VETO oldu. **Bu, calisan EA'daki ML OFF yapildi demek
degildir.** Sadece yeni model adayinin dogrulamayi gecemedigi anlamina gelir.

| Strateji | Yeni aday | Mevcut model R | Yeni model R | Mevcut DD | Yeni DD |
|---|---|---:|---:|---:|---:|
| uj_020_good_practice | Ridge | -0,36R | +0,41R | 5,25R | 5,70R |
| usdjpy10RVeryHighWRsETUP | Yerel rejim | +11,01R | +6,64R | 1,01R | 2,56R |

Birinci adayin kazanci yaklasik +0,76R daha iyi, ancak DD daha kotu.
Ikinci aday mevcut modele gore hem kazanc hem DD bakimindan daha kotu.
**Ikisi de mevcut modeli degistirme kosullarini gecmedi.**

Tum 22 arastirma politikasi eski modelle karsilastirilinca 12'sinde PnL daha
iyi, dordunde daha kotu, altisinda ayni. Ancak 12 iyilesmenin 11'i yeni bir
modelden degil, NO_VETO yani arastirmada eski filtrenin uygulanmamasindan
kaynaklaniyor. Bunlari 12 yeni ML basarisi diye sunmak yanlis olur.

Ornegin HolyGrail [USDJPY]'de mevcut filtre -14,23R'ye sinirladigi sonucu
filtresiz politika -81,37R olarak birakiyor. Bu da kullanilmakta olan
filtreleri koruma isteginin onemini gosteriyor: daha yeni kampanya sonucu
otomatik olarak daha iyi degil.

Son testte tum sabit aday ailelerinin filtresize gore sonucu, otomatik
seciciden ayri olarak da saklandi:

| Aday ailesi | R iyilesti | R kotulesti | Ayni |
|---|---:|---:|---:|
| Ridge | 2 | 9 | 11 |
| Sig HGB | 2 | 12 | 8 |
| MLP | 3 | 12 | 7 |
| Yerel rejim | 3 | 9 | 10 |

Bu tabloya bakip yeni bir aileyi sonradan secmedik. Uzun gecmisin eklenmesi
tek basina son yilda genelleme garantisi vermedi. Eski rejimlerin daha fazla
agirlik kazanmasi, etiket gurultusu, secim esikleri ve model uyumu gibi
nedenler ayri deney gerektirir; hangisinin sebep oldugu bu turla ispatlanmadi.

## Kanit Ve Koruma

- 49 ilgili test gecti; kimlik izolasyonu, gelecek etiketinin tahmine girmemesi,
  kronolojik sinirlar, skor cezalari ve istatistiksel toplama kontrolleri dahil.
- Tum 22 stratejinin checkpoint dosyalari yeniden okundu ve hash'leri dogrulandi.
- 5/20 gunluk ortak bloklarla 20.000'er bootstrap tekrari yapildi.
- 22 politika ve 88 adaylik coklu karsilastirma duyarliligi raporlandi.
  Hem temel stratejiye hem mevcut modele hem aylik eslestirmeye karsi
  duzeltilmis kanit kosulunu gecen politika sayisi **0**.
- Production kaynak/binary/listener/aktif model envanterinde **436 dosya,
  0 degisiklik**. Bu kampanya emir vermedi, terminal/chart yeniden baslatmadi.
- Arastirma artifact'lari yaklasik 5,3 MB. Eski CSV veya modeller silinmedi.

DD, kapali trade R serisindeki peak-to-trough dusustur; floating/EOD trailing
DD degildir. Benzer stratejiler bagimli oldugu icin toplam R'leri bagimsiz
bir fon gibi toplanmamalidir. Veto sonrasi stateful sinyal/pozisyon akisinin
tam execution replay'i bu CSV-altkume analizinin disindadir.

## Literaturle Baglanti

Gu/Kelly/Xiu'nun kronolojik egitim/validation/test ve regularization yaklasimi
buradaki zaman ayrimi ve model cezalari icin metodolojik temeldir. Onlarin
finansal veri setindeki sonuclar ORB'ye otomatik aktarilmaz.
[Gu, Kelly, Xiu (2020)](https://dachxiu.chicagobooth.edu/download/ML.pdf)

Gelman'in partial-pooling yaklasimi az gozlemli gruplarda asiri tahminleri
sinirlandirmanin gerekcesini saglar; burada gruplar tek stratejinin rejimleri.
[Gelman (2006)](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf)

Bailey ve arkadaslarinin calismasi tekrarlanan backtest/model seciminin
yanliligini aciklar. Deneme kaydi ve coklu karsilastirma kontrolleri bu riski
gormek icindir; gecmiste yapilmis tum insan denemelerini silmez. Skorumuz
bu makaledeki PBO'nun veya DSR'nin hesaplandigi iddiasi degildir.
[Bailey et al. (2015)](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)

## Dosyalar

- `docs/ORB_LongHistory_R3_Protocol.md`: egitimden once dondurulmus protokol.
- `logs/OrbLongHistory_R3_20260910/Results.md`: tam karsilastirma tablosu.
- `logs/OrbLongHistory_R3_20260910/evaluation.json`: skor bilesenleri, model/zaman kontrolleri,
  eslesmis donemler, belirsizlik ve degistirmeme nedenleri.
- `logs/OrbLongHistory_R3_20260910/comparison.csv`: siralanabilir sonuc tablosu.
- `logs/OrbLongHistory_R3_20260910/contract.json`: kaynak, veri ve mevcut model hash'leri.
- `logs/OrbLongHistory_R3_20260910/production_integrity.json`: production kontrolu.

## Tamamlananlar

- [x] Uzun gecmis kapsam, ayar, oz nitelik ve maliyet uyumunu dogrula.
- [x] Son bir yili disarida tutan protokol ve skoru onceden sabitle.
- [x] Strateji bazli dort aday ailesini ve ic zaman katlamalarini egit.
- [x] Yeni modelleri testten once dondur; kayitli mevcut modellerle eslestir.
- [x] Dayaniklilik, belirsizlik ve production koruma kontrollerini uygula.
- [x] Mevcut modelleri degistirmeden olumlu/olumsuz sonuclari raporla.
