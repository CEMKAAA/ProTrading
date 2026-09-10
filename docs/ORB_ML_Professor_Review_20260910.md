# ORB ML Filtreleri: Literatur, Secim Becerisi ve Dogrulama Plani

## Yonetici ozeti

Mevcut sinyal motorunun uzerine bir makine ogrenmesi filtresi koymak tutarli bir
arastirma hedefidir. Modelin gorevi yeni yon veya geometri icat etmek degil,
zaten olusmus bir setup icin isleme girmenin maliyet sonrasi degerini kestirmek
olmalidir. Fakat filtreli zararin filtresiz zarardan dusuk olmasi, tek basina
modelin dogru islemleri sectigini veya overfit olmadigini gostermez.

Bu raporun temel onerisi **risk azaltma ile tahmin becerisini ayri olcmek**, sonra
stratejiye ozel ama ortak piyasa bilgisinden yararlanan, maliyet duyarli ve
duzenlilestirilmis bir filtre ailesi gelistirmektir. Daha buyuk bir ag, daha fazla
indikator veya daha uzun bir gecmis, bu olcum sorununu kendiliginden cozmez.

Literaturde karmasik modeller lehine de, bunlarin adil olmayan benchmarklarla
degerlendirildigine dair de ciddi calismalar var. Bu nedenle tercih ne
"DL kesin daha iyi" ne de "kucuk veri varsa DL yasak" olmalidir. Ayni veri,
ayni bilgi zamani, ayni risk/maliyet ve ayni model-secim butcesiyle yapilan
karsilastirma karar vermelidir.

10 Eylul 2026 tarihli ek kontrol, mevcut dondurulmus USDJPY modellerini yeniden
egitmeden degerlendirdi. 22 strateji/model seciminde uc birebir sonuc/maske
tekrari bulundu; geriye 19 farkli seri kaldi. Bunlar da birbirlerinden bagimsiz
19 deney sayilamaz. Aylik islem sayisi eslestirilmis kontrolde 10 serinin secim
katkisi pozitif, dordunun negatif, besinin sifira esit. Hicbiri rastgele
kontrollerin %97.5 ust sinirini asmadi. Bu, gelecekte basari olamayacaginin
ispati degil; mevcut sonucu kesin bir genelleme kaniti saymamak icin gerekcedir.

## 1. Mevcut verinin gercekte anlattigi

### 1.1 Eski donem testinin kapsami

Onceki test, 2026 kampanyasinda egitilmis agirliklari, scaler'lari ve esikleri
degistirmeden 2018-01-01 ile 2021-09-08 arasindaki USDJPY setup'larina uyguladi.
2016 M1/M5 verisi intraday test icin yetersiz, 2017 kismi oldugundan bu sonuc
"eksiksiz on yillik test" veya "ilk bes yilin tamami" diye sunulamaz.

Bu bir **geriye dogru donem transfer testi**dir. Egitimde kullanilmayan eski
satirlarda genelleme sinamasi degerlidir; ancak modeli gecmiste egitip sonraki
piyasada calistirmakla ayni deney degildir. Stratejilerin insanlar tarafindan
seciminde bu donemlerin grafikleri zaten incelendiyse, strateji-secim duzeyinde
ek bir bagimsizlik kaybi bulunabilir.

Mevcut kayitlar: `docs/ORB_USDJPY_OlderPeriod_20260910.md` ve
`logs/OrbMLPriorFive_20260910/results/Results.md`.
R sonuclari simulatorun mevcut maliyet/exit varsayimlarini tasir; gercek
listener fill'leri degildir. DD kapali islemlerden hesaplanan peak-to-trough
R'dir; floating veya challenge EOD drawdown'i degildir.

### 1.2 Zarar azalmasi ile secim becerisi farki

N aday islemden k tanesini rastgele ve esit olasilikla alirsak, sabit sonuc
serisi uzerindeki beklenen toplam R:

```text
q = k / N
Beklenen rastgele toplam R = q * filtresiz toplam R
Secim katkisi = filtreli toplam R - beklenen rastgele toplam R
```

Bu ozdeslik bagimsiz trade getirileri varsayimini gerektirmez: her satirin
secim olasiligi q oldugunda beklentinin dogrusalligindan gelir. Ancak bunu bir
anlamlilik testine cevirmek ek varsayimlar gerektirir. Esit islem sayisi,
esit kontrat hacmi, esit tutma suresi veya esit floating risk demek degildir.

| Strateji | Base / ML islem | Base R | ML R | Esit sayili rastgele beklenti | Bunun uzerindeki katkisi |
|---|---:|---:|---:|---:|---:|
| HolyGrail USDJPY | 952 / 253 | -346.69 | -86.19 | -92.14 | +5.94 |
| 1RYildiz | 484 / 296 | +2.64 | +15.98 | +1.61 | +14.37 |
| 0.5RGoodUsdjpy | 951 / 660 | -20.97 | -3.23 | -14.55 | +11.32 |

Yuvarlamadan dolayi son basamaklarda fark olabilir. HolyGrail'deki yaklasik
260R iyilesmenin tamamini tahmin becerisine yazmak yanlis olur. Buna karsilik
1RYildiz'de kalan +14.37R, incelemeye deger bir **secim katkisi adayi**dir.
Bu tabloya bakip yeni bir production modeli secilmedi.

### 1.3 Ayni aylarda ayni sayida trade alan kontrol

Global q yeterli degildir: model zararli bir yilda az, karli yilda cok islem
aliyor olabilir. Bu gercek bir zamanlama katkisi da olabilir. Iki etkiyi ayirmak
icin ikinci kontrol, her ay ML'nin aldigi sayida islemi o ayin adaylari arasindan
rastgele secer. Her model icin 2,000 tekrar ve sabit seed kullanildi.

| Strateji | ML R | Aylik eslestirilmis beklenti | Aylik kontrolun ustundeki R | Rastgele kontrollerin ML'ye yetisme/asmasi |
|---|---:|---:|---:|---:|
| HolyGrail USDJPY | -86.19 | -82.69 | -3.50 | %53.07 |
| 1RYildiz | +15.98 | +5.51 | +10.47 | %14.94 |
| 0.5RGoodUsdjpy | -3.23 | -11.45 | +8.22 | %17.59 |
| usdjpy10RVeryHighWRsETUP | -12.47 | -13.02 | +0.55 | %44.08 |
| HighfreqHighWRusdjpyV2 | -12.46 | -2.38 | -10.08 | %99.40 |

Son sutun **genel gecerli bir finansal p-degeri degildir**. Ay icinde
exchangeability varsayimina dayanan kesifsel bir randomizasyon oranidir.
Otokorelasyon, ortusen pozisyonlar ve degisen dagilim bunu etkiler. Aylik
retention degerleri gerceklesmis filtre maskesinden alinir; ileriye donuk
uygulanabilir bir aylik kota stratejisi oldugu iddia edilmez.

Global kontrol zamanlama+secim toplam katkisini, aylik kontrol ay icindeki
secimi incelemeye yardim eder. Aylik kontrolun zamanlama katkisini bilerek
eslestirip kaldirmasi, zamanlamanin degersiz oldugu anlamina gelmez. Sonraki
asama, gercek risk ve zaman maruziyeti eslestirilmis portfolio replay'dir.

Deney tekrarlanabilir:

```text
python scripts/orb_ml_selection_diagnostic.py
python -m pytest -q tests/test_orb_ml_selection_diagnostic.py
```

Tam sonuc: `logs/OrbMLSelectionDiagnostic_20260910/SelectionDiagnostic.md`.
Makine-okunur sonuc: ayni klasordeki `selection_diagnostic.json`.
Veri/model/threshold degistirilmedi; ortak zaman-maske tekrarları raporlandi.

## 2. Literaturden alinacak dersler

Asagidaki ozetler yayinlarin bulgularini, sistem icin onerilerden ayirir.
Universite baglantisi yazarlarin ilgili yayin/kurumsal kayitlarina dayanir;
bu kurumlarin ORB sistemini onayladigi anlamina gelmez. Hisse risk primi,
makro tahmin ve intraday CFD setup veto problemi ayni problem degildir.

### 2.1 Yale: etkileşimler ve zaman sirali model secimi

Gu, Kelly ve Xiu'nun **Empirical Asset Pricing via Machine Learning** calismasi
(RFS, 2020), hisse getirilerini farkli ML aileleriyle karsilastirir. Kazanclarin
onemli bir kismi dogrusal olmayan degisken etkileşimlerinden gelir. Calismada
ag derinligini artirmak surekli kazanc getirmez; incelenen aglarda performans
uc gizli katman civarinda tepe yapar. Egitim, validation ve test zaman sirasiyla
ayrilir; validation'da secilen model gercek testte degerlendirilir.
[Yazar PDF'i, ozellikle s. 5 ve 9](https://dachxiu.chicagobooth.edu/download/ML.pdf).

**Buraya aktarim onerisi:** `range/ATR x trend`, `spread/SL x target_R`,
`rejim_yasi x displacement` gibi az sayida ekonomik olarak yorumlanabilir
etkileşimi sabit liste halinde test etmek. Bu makale "bizde uc katman en
iyidir" veya "her stratejide DL kullanilmali" sonucunu vermez.

### 2.2 Yale: maliyeti model disinda bir dipnot olarak birakmamak

Jensen, Kelly, Malamud ve Pedersen'in **Machine Learning and the Implementable
Efficient Frontier** calismasi, ML ile maliyet duyarli portfolio optimizasyonunu
birlestirir. Maliyetleri yok sayan tahminler kagit uzerinde cazip, uygulamada
zayif portfoyler uretebilir. Degerlendirme, risk seviyesine gore maliyet sonrasi
elde edilebilir getiri cephesinde yapilir.
[Yayin](https://academic.oup.com/rfs/advance-article/doi/10.1093/rfs/hhag022/8524346),
[yazarlarin replikasyon kodu](https://github.com/theisij/ml-and-the-implementable-efficient-frontier).

**Buraya aktarim onerisi:** 0.10R ile 2R setup'larinda ayni WR esiginin ekonomik
anlami yoktur. Secim kriteri net R olmali; spread, komisyon, gecikme ve listener
fiyat farki ayrica streslenmeli. Hisse piyasasina ait market-impact katsayilari
CFD/futures'a oldugu gibi kopyalanmamali.

### 2.3 Yale: chart sekli ogrenmek, sonuc resmini ogrenmek degildir

Jiang, Kelly ve Xiu'nun **(Re-)Imag(in)ing Price Trends** calismasi (JF, 2023),
hisse fiyat grafiklerinden ML ile tahmine yararli sekiller ogrenmeyi inceler;
ozette farkli zaman ufuklari ve ulkeler arasinda aktarim sonuclari raporlanir.
Burada yayin ozeti ve replikasyon eklerinin kaydi incelendi; tum deneylerin
yeniden uretildigi iddia edilmiyor.
[Yayin ve replikasyon ekleri](https://onlinelibrary.wiley.com/doi/10.1111/jofi.13268).

**Buraya aktarim onerisi:** yeterli veri olursa sinyal ONCESINDEKI normalize
OHLC dizisini kucuk bir temporal CNN ile islemek. Mevcut strateji PNG'lerini
egitim girdisi yapmamak: grafiklerde gelecekteki mumlar, WIN/LOSS renkleri,
hedef/exit isaretleri ve audit sonuclari bulunabilir. Bunlar target leakage olur.

### 2.4 MIT: rejim degisimi, takvimde sabit bir alarm degildir

Andrew Lo'nun **The Adaptive Markets Hypothesis** calismasi (2004), piyasa
etkinligini rekabet, adaptasyon ve cevreyle birlikte degisen bir yapi olarak
tartisir. Bu teorik cerceve, strateji performansinin zamana gore degisebilmesine
yer verir; sabit aralikla rejim degisimini ispatlayan bir takvim formulu sunmaz.
[MIT yazar PDF'i](https://web.mit.edu/Alo/www/Papers/JPM2004_Pub.pdf).

**Buraya aktarim onerisi:** rejim, rejim yasi ve gecis belirsizligini birlikte
incelemek; "her 4-5 ayda flip" gibi bir hardcode kural yazmamak. Yeni durum
tespitinde yalniz o anda bilinen fiyatlari ve o tarihe kadar egitilmis
parametreleri kullanmak. Tum tarih uzerinde sonradan etiketlenmis rejimler
canliya esit degildir.

### 2.5 Harvard: benchmark ve kisitlar tahminin kendisi kadar onemli

Campbell ve Thompson'un **Predicting Excess Stock Returns Out of Sample:
Can Anything Beat the Historical Average?** calismasi (RFS, 2008), tarihsel
ortalama benchmark'ina karsi tahminleri inceler. Ekonomik olarak gerekcelenen
isaret kisitlari bazi tahminlerin out-of-sample performansini iyilestirebilir.
Burada yayin ozeti ve NBER calisma kaydi dogrulandi; Harvard PDF baglantisi
erisim hatasi verdiginden tam metin okundu iddiasi yoktur.
[Yayin ozeti](https://academic.oup.com/rfs/article-abstract/21/4/1509/1567518),
[NBER calisma kaydi](https://www.nber.org/papers/w11468).

**Buraya aktarim onerisi:** her model en az filtresiz motoru, esit sayili
rastgele filtreyi ve basit duzenlilestirilmis modeli gecmeli. Hisse piyasasinin
pozitif risk primi kisitini iki yonlu USDJPY islemlerine dogrudan uygulamak
yanlis olur.

### 2.6 Harvard: shrinkage ve ayni veri uzerinde karsilastirma

Stock ve Watson'un **An Empirical Comparison of Methods for Forecasting Using
Many Predictors** calismasi (2005 taslagi), cok sayida tahmin ediciyle
shrinkage, bagging ve model ortalamayi ortak bir cercevede inceler. Veri,
ABD'nin 1959-2003 aylik makro serileridir; intraday trade etiketi degildir.
Ortak veri ve uygulama farklarinin karsilastirmadaki onemi acikca vurgulanir.
[Harvard metni](https://stock.scholars.harvard.edu/sites/g/files/omnuum5911/files/stock/files/empiricalcomparisonmedthod.pdf).

**Buraya aktarim onerisi:** mevcut ridge'i zayif bir benchmark gibi gorup
atmak yerine adil sekilde tutmak; yeni agla ayni temiz veri ve ayni test
takviminde karsilastirmak. Ensemble agirliklarini test sonuclarina bakarak
degistirmemek.

### 2.7 Karmaşıklik tartismasinin iki tarafi

Kelly, Malamud ve Zhou'nun **The Virtue of Complexity in Return Prediction**
(JF, 2024) calismasi, belirli teorik kosullarda ve ABD piyasa getirisi
uygulamasinda, gozlemden fazla parametreli modellerin yarar saglayabilecegini
gosterir. Random Fourier features kullanilarak karmasiklik incelenir. Bu,
parametre sayisinin tek basina overfit teshisi olmadigina dair onemli bir
karsi-ornek sunar.
[Yale'deki yayin PDF'i](https://economics.yale.edu/sites/default/files/2024-01/The%20Journal%20of%20Finance%20-%202023%20-%20KELLY%20-%20The%20Virtue%20of%20Complexity%20in%20Return%20Prediction%20%281%29.pdf).

Buncic'in **Simplified: A Closer Look at the Virtue of Complexity in Return
Prediction** calismasi ise sifir intercept kisiti ve performans toplama
yonteminin basit modelleri dezavantajli gosterdigini savunur. Bu bir elestiri
calismasidir; tartismanin kesin olarak kapandigi sonucu cikarilamaz. Mart 2026
guncellemeli yazar ozeti ve SSRN kaydi incelendi; tam metne erisim tamamlanamadi.
[Yazar kaydi](https://www.danielbuncic.com/),
[calisma](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5239006).

Kelly ve Malamud'un **Understanding The Virtue of Complexity** (2025) yaniti,
elestirilerin ana sonucu gecersiz kilmadigini savunur; nominal/etkin
karmasiklik ve implicit regularization ayrimina dikkat ceker. Yanitin
arastirma ozeti incelendi, tum 101 sayfalik ekleri degil.
[Yazarlarin yaniti](https://papers.ssrn.com/sol3/Delivery.cfm/5346842.pdf?abstractid=5346842&mirid=1).

**Bizim kararimiz:** ne buyuk modeli pesinen elemek ne de universite ismine
guvenip kabul etmek. Intercept'li ridge, kucuk ag ve kontrollu bir nonlinear
genislemeyi ayni uygulanabilir net-R patikasinda karsilastirmak. Farkli seed'lerin
Sharpe'larini ortalamak yerine, gercekte uygulanacak ensemble tahminlerini
birlestirip onun tek getiri patikasini olcmek.

### 2.8 Stanford baglantili DL: ekonomik amac fonksiyonu

Chen, Pelger ve Zhu'nun **Deep Learning in Asset Pricing** calismasi,
no-arbitrage kosulunu, adversarial test varliklarini ve zamanla degisen makro
durumlari birlestirir. Incelenen metinde 1967-2016 hisse verisi ve ayri
egitim/validation/test donemleri vardir. Modelin basarisi sadece tahmin
hatasiyla degil ekonomik kriterlerle olculur.
[Yazar metni](https://arxiv.org/pdf/1904.00745).

**Buraya aktarim onerisi:** ekonomik problemle uyumlu bir loss/secim kriteri.
Ancak tek bir ORB stratejisinin trade CSV'si, stochastic discount factor
egitecek genis varlik kesiti degildir. Bu mimariyi oldugu gibi kopyalamak
profesyonellik degil, farkli bir problemi yanlis modellemek olur.

### 2.9 Coklu deneme: 50 model, tek hipotez degildir

Harvey, Liu ve Zhu'nun **... and the Cross-Section of Expected Returns**
(RFS, 2016) calismasi, cok sayida faktor denenirken standart tek-test
anlamlilik yorumlarinin yetersizligini tartisir. Burada yayin kaydi ve
indekslenmis metin parcasi dogrulandi; PDF erisimi tamamlanamadi.
[Yazar PDF baglantisi](https://people.duke.edu/~charvey/Research/Published_Papers/P118_and_the_cross.PDF).

Bailey, Borwein, Lopez de Prado ve Zhu'nun **The Probability of Backtest
Overfitting** metni, model seciminin out-of-sample siralamayi ne kadar
bozabilecegini CSCV/PBO ile inceler. Yalniz kazanan denemeyi gostermek,
arastirma surecindeki secim maliyetini saklar.
[Incelenen 2015 metni](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf).

Bailey ve Lopez de Prado'nun **The Deflated Sharpe Ratio** (2014) calismasi,
coklu secim ve normal olmayan getirilerin Sharpe yorumu uzerindeki etkisini
ele alir. Denenen alternatiflerin sayisi ve bagimliligi onemlidir.
[Metin](https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf).

**Buraya aktarim onerisi:** strateji, feature, threshold, seed ve model ailesi
denemelerini ortak bir deney defterinde tutmak. PBO/DSR birer tanisal olcu
olabilir; ikisini de "overfit yok olasiligi" diye dashboard'a yazmamak.
CSCV'nin bazi bolunmeleri ileri/geri zaman karistirabildiginden gercek rolling
forward testin yerine gecirmemek. Bilinmeyen eski manuel deneme sayisini sifir
kabul etmemek; alt sinir ve duyarlilik raporlamak.

### 2.10 Kalibrasyon: 0.80 skor, otomatik %80 basari degildir

Guo, Pleiss, Sun ve Weinberger'in **On Calibration of Modern Neural Networks**
(ICML, 2017) calismasi, siniflandirma dogrulugu ile olasilik kalibrasyonunu
ayirir ve temperature scaling'i inceler. Deneyler trading verisi degildir.
[Makale](https://proceedings.mlr.press/v70/guo17a/guo17a.pdf).

**Buraya aktarim onerisi:** probability kullanan modellerde ayri, gecmis bir
kalibrasyon donemi; Brier/log-loss ve reliability kontrolu. Az sayida trade'de
esnek isotonic kalibrasyonun kendisi de overfit olabilir. Threshold ayarlamak,
olasilik kalibrasyonu yapmakla ayni islem degildir.

Barber, Candes, Ramdas ve Tibshirani'nin **Conformal Prediction Beyond
Exchangeability** (Annals of Statistics, 2023) calismasi, dagilim kaymasinda
standart conformal garantilerinin sinirlarini ve agirlikli yaklasimlari inceler.
Incelenen uygulamalar elektrik ve secim tahminidir, trading degil.
[Metin](https://arxiv.org/pdf/2202.13415).

**Buraya aktarim onerisi:** belirsizlik araliklarini faydali bir uyarici olarak
test etmek, fakat bir trade icin "%95 kesin kazanc" etiketi uretmemek.
Marjinal coverage, rejim bazinda veya secilmis trade alt-kumesinde ayni
coverage garantisi vermez. Sert rejim kaymasinda araliklar da bozulabilir.

## 3. Sistemde zaten olanlar ve gercek eksikler

Asagidaki durum kod incelemesine dayanir; her ozellik productionda istatistiksel
olarak basarili anlamina gelmez.

| Katman | Mevcut durum | Sonraki iyilestirme |
|---|---|---|
| Egitim/validation/test | Zaman sirali ayrim mevcut | Tum stratejilere ortak takvim ve nested model-family secimi |
| Purge/embargo | Exit zamaniyla purge, embargo mevcut | Ortusen strateji/event gruplarini da ayni tarafta tutmak |
| Olcekleme | Scaler yalniz fit verisine egitiliyor | Yeni preprocessing icin ayni kontrati korumak |
| MLP regularization | Alpha secimi, chronological checkpoint mevcut | Ayri probability calibration; fazla hiperparametre acmamak |
| Walk-forward | Ic donem katlari mevcut | Bastan sona donemsel yeniden egitim politikasi replay'i |
| Benchmark | Logistic/tree/ridge/HGB karsilastirmalari mevcut | Esit sayili ve maruziyet eslestirilmis kontrol eklemek |
| Belirsizlik | Daily block bootstrap mevcut | Stratejiler arasi ortak gunleri birlikte orneklemek |
| Coklu test | Return kampanyasinda duzeltme var | Manuel secimler dahil kampanyalar arasi trial defteri |
| Target | Win etiketi ve net-R challenger mevcut | Degisken exit buyuklukleri icin conditional payoff modeli |
| Model baglama | Strateji/config hash uyumu mevcut | Yeni modellere immutable manifest ve karar aninda kimlik kaydi |
| ML audit | Filtre uygulanabiliyor | In-sample, backward, frozen OOS ve gercek forward'i ayri gostermek |

Kaynak kodlar: `scripts/orb_ml_filter.py`, `scripts/orb_ml_research.py`,
`scripts/orb_ml_return_campaign.py`, `scripts/check_orb_campaign_compatibility.py`.

Mevcut bootstrap'un full baseline'a gore kazanci olcmesi, secim katkisini
maruziyet azalmasindan ayirmaz. Eklenen tanisal script bu boslugun ilk kismini
kapatir; henuz tam risk-eslestirilmis portfolio testi degildir.

## 4. Benim kuracagim model mimarisi

### 4.1 Sinyal motoru sabit, filtre karari ayri

```text
Sabit ORB setup motoru
  -> mevcut deterministic filtreler
  -> accepted candidate + o anda bilinen feature snapshot
  -> stratejiye bagli model/config kontrolu
  -> net deger ve belirsizlik skoru
  -> mevcut ML ON/OFF politikasina gore accept/veto
  -> ayni native/bridge execution ve koruyucu lifecycle
```

Veto edilen sinyal yeni entry uretemez. Fakat mevcut bir pozisyonu kapatmasi
gereken koruyucu ters-sinyal lifecycle'i, yeni trade ML'den gecmedi diye
bastirilmamalidir. Dataset satir alt-kumesi testinden sonra gercek state
machine replay'i bu nedenle zorunludur. Karar zamani ile grafik mum zamani
ayri alanlar olarak korunmalidir.

### 4.2 Birinci aday: net-R regression'u daha iyi tanimlamak

Mevcut ridge/HGB return challenger'i iyi bir baslangic. Hedefi WR yerine
gerceklesebilecek maliyet sonrasi net R olarak tutarim. TP'ye varmadan ters
NAS/ORB sinyalinde kapanan trade'e tam TP_R etiketi vermem. Flat/erken exit
etiketleri de egitime girer; acik veya veri-yetersiz islemler L yapilmaz.

Onerdigim ilk yeni model bir **iki parca payoff modeli**:

```text
p_pos = P(net_R > 0 | entry'de bilinen x, strateji s)
g = E(net_R | net_R > 0, x, s)
l = E(-net_R | net_R <= 0, x, s)
beklenen_net_R = p_pos*g - (1-p_pos)*l
```

Sifir sonuclarda l=0 katkisi mumkundur. Bu bir oneridir, yayinlardan birebir
kopyalanmis ORB algoritmasi degildir. Target zaten NET R ise komisyonu
formulden ikinci kez dusmemek gerekir. Ilave maliyet stresi uygulanacaksa
yalniz baz senaryonun uzerindeki maliyet farki dusulur.

Sabit geometride ve sabit maliyette teorik WR esigi kontrol olarak yararlidir:
brut kazanc aR, brut kayip 1R, her iki sonucta cR maliyet icin basabas
`p=(1+c)/(1+a)`. Degisken erken exit ve maliyetlerde bu sabit formulun yerine
yukaridaki conditional payoff gerekir.

Uc ayri modelle orneklem parcasi kuculebilir; bu nedenle direkt ridge/HGB
regression'a karsi kazanmazsa iki-parca modeli productiona tasimam.

### 4.3 Ikinci aday: stratejiler arasi kontrollu bilgi paylasimi

Her strateji icin ayri buyuk ag yerine ortak piyasa temsili + stratejiye ozel
kucuk head oneririm. Model kimligi ve karari gene stratejiye ozeldir.
Ortak girdiler piyasa durumu; ozel girdiler SL/ATR, target_R, inversion,
giris/exit modu gibi gercek setup ozellikleridir.

Ayni piyasa gununde olusan on farkli strateji varyantini on bagimsiz piyasa
orneklemi saymam. Ayni event ailesi ve ortusen label araligi tek split grubuna
alinir; loss agirligi tekrar sayisina gore dengelenir. Bir gunun A stratejisi
train'de, ayni hareketin B stratejisi testte olamaz.

Karsilastirma: ayri ridge, pooled ridge + strateji etkisi, sonra kucuk paylasimli
MLP. Negatif transfer varsa pooling'i reddederim. Kesin duplicate seriler
ayri basari kaniti olarak sayilmaz; benzer ama farkli exit'ler silinmez, gruplanir.

### 4.4 Ucuncu aday: rejime kosullu ve duzenlilestirilmis residual

Mevcut alti macro rejim ve RF durumlari aynen korunur. Yeni model, stratejinin
yalniz gecmisten hesaplanmis baz beklentisine gore artı/eksi katkisini ogrenir.
Az ornekli rejimin katsayilari global modele dogru shrink edilir. Her rejime
bagimsiz buyuk ag egitmek yerine, sinirli etkileşimler ve ortak parametreler
tercih edilir.

Gecmis performans girdisi kullanilacaksa yalniz **o anda kapanmis** tradelerden
olusturulur; halen acik trade'in nihai kazanci ozellige sizamaz. Gecmis bir
rejimin tum-donem WR'sini her satira yapistirmak target leakage'dir.

Bu residual model, maruziyet eslestirilmis net-R katkisinda mevcut return
challenger'i gecerse degerlidir. Grafik uzerinde hikayesi guzel oldugu icin
kabul edilmez. Rejim karari fiyattan turetildigi icin mekanizma hipotezi
kurulabilir; bundan nedensellik ispati cikmaz.

### 4.5 DL icin kontrollu kapasite deneyi

Tabular modeller uzerinde gercek katki gorulurse, sabit uzunlukta gecmis OHLC
penceresini normalize eden kucuk causal temporal CNN denenebilir. Her pencere
karar aninda biter; futuro mum, resimdeki hedefe ulasma izi veya future-fit
normalizasyon kullanilmaz. Indicator soup yerine mum govdesi/fitili,
range-genislemesi, hacim ve spread baglami kullanilir.

Az veri riskini atlamak icin gozlem sayisini yapay olarak pencere kaydirarak
buyutmeyiz: komsu pencereler bagimsiz degildir. Pretraining yapilacaksa o da
ilgili fold'un gelecegini gormemelidir. Random Fourier + ridge de DL'ye rakip
kontrollu bir nonlinear aday olabilir. Hepsi onceden sinirlanmis deney butcesi
icinde kalir; seed/katmanlari kazanana kadar taramak yoktur.

## 5. Feature engineering: az, nedensel ve test edilebilir

Yeni feature'lar eklemeden once mevcut 40/50 feature ile cakisanlar elenir.
Tercih edilen ilk gruplar:

| Grup | Ornek | Hipotez | Sizinti kontrolu |
|---|---|---|---|
| Uygulama maliyeti | spread/SL, ek komisyon_R | Kucuk hedef maliyete hassas | Karar anindaki quote, gelecek fill degil |
| Range/volatilite | opening_range/ATR, SL/ATR | Gurultu/SL olcegi uyumu | ATR son bilinen mumlarla |
| Geometri | target_R, SL/price | Model farkli payoff'lari ayirsin | Dashboard'un sinyal anindaki snapshot'i |
| Yon baglami | sinyal_yonu x H1/H2 egim | Trend/pullback uyumu | Tamamlanmamis HTF mumunun gelecegi yok |
| NAS durumu | son NAS yonu, yasi, ORB ile uyum | Entry teyidi/exit riski | available_at <= decision_at |
| Rejim gecisi | rejim yasi, son gecisten sure | Gecislerde istikrar farki | Gelecekten smoothed state yok |
| Zaman/mikroyapi | acilistan dakika, broker session | Likidite/maliyet farki | Tarihsel DST ve timezone dogru |
| Veri kalitesi | bar boslugu, spread fallback bayragi | Eksik veri etkisini ayirmak | Kalite bayragi label'dan turetilmez |

Takvim feature'i otomatik olarak overfit degildir. Fakat 50 strateji x gun x
saat x mevsim tarayip en guzelini bulmak guclu selection bias yaratir.
Her feature grubu icin bir mekanizma hipotezi ve ablation testi yazilir.
SHAP veya feature importance tek basina bu mekanizmayi dogrulamaz.

## 6. Overfitting'e karsi kabul protokolu

### 6.1 Veri kontrati

Her satir `strategy_id`, `config_hash`, kaynak broker/sembol, signal ve entry
TF, `signal_at`, `features_available_at`, `decision_at`, `entry_at`,
`exit_at`, `label_available_at`, outcome ve maliyet semantigini tasimali.
MFE/MAE/exit_reason gelecekte olusan hedef/denetim alanidir; entry filtresine
girdi olamaz. Feature whitelist ve sirasi model manifestinde kilitlenir.

H1/H2 EMA/ATR, ancak kullanilan mumun bilgisi karar aninda mevcutsa gecerlidir.
Broker saatini bugunku UTC offset'iyle on yil geriye cevirmek guvenilir
degildir; tarihsel saat kurali ya dogrulanir ya belirsizlik acikca etiketlenir.
Futures/CFD farki, mapping ve gercek fill maliyeti de veri kontratinin parcasidir.

### 6.2 Nested chronological walk-forward

1. Tum stratejiler icin ortak dis takvim bloklari belirlenir.
2. Her dis train blogunda model ailesi/regularization ic katlarda secilir.
3. Checkpoint, probability kalibrasyonu ve threshold icin ayri kronolojik
   bolumler veya leakage-safe cross-fitting kullanilir.
4. Train'de baslayip validation/test'e uzanan label araliklari purge edilir.
5. Scaler, imputation, feature secimi, regime learner ve encoder yalniz izinli
   train verisinden fit edilir. Hazir tum-donem tablo tekrar kullanilmaz.
6. Dis test blogunda hicbir esik veya agirlik degismez. Retrain politikasi da
   onceden belirlenir; kotu test geldi diye pencere degistirilmez.
7. Dondurulan tum adaylar, veto ettikleri setup'lar dahil, ileri veri uzerinde
   shadow olarak izlenir. Yalniz actigi tradeleri loglamak feedback bias yaratir.

Su anda incelenmis 2018-2026 donemlerinin bir kismina tekrar "untouched final
test" adi verilemez. Yeni protokol bu donemlerde gelistirme/rolling evidence
uretir; son karar icin yeni ileri veri gerekir. Ozellikle her yil %60 WR
sartina gore sistemi yeniden tekrar tekrar secmek, yillari da validation'a
donusturur.

### 6.3 Birincil olcu ve risk sinirlari

Birincil amac: maliyet ve maruziyet eslestirilmis net-R secim katkisi.
Ikincil olculer: net R/trade, trade retention, profit factor, kuyruk kaybi,
kapali-trade DD, mark-to-market DD ve challenge kurallarina uygun EOD DD.
WR gorunur ama model seciminde tek basina kullanilmaz.

Her strateji icin tablo en az su dort modu gostermeli:
**base / ML / ayni sayili rastgele / ayni maruziyetli kontrol**.
Sifir trade alan model, zero loss urettigi icin kazanan ilan edilmemeli.
Retention icin is hedefi onceden belirlenmeli; orn. %50 altina inen adaylari
ayri bir seyrek-trade ailesi olarak raporlamak bir politika olabilir, evrensel
bilimsel esik degildir.

DD'yi sadece kapanmis trade PnL'lerinden hesaplamak, hesabın gun icindeki
floating drawdown ihlalini goremez. MFE/MAE ikilisi bile birden fazla pozisyonun
ortak zaman patikasini tam vermez. Challenge testi senkronize fiyat/pozisyon
replay'i veya gercek zamanli equity orneklerini gerektirir.

### 6.4 Tanisal testler

- Ayni ay/likidite dilimi icinde retention-eslestirilmis random veto.
- Gun veya uygun sure blogu bazinda paired bootstrap; tum stratejiler ayni
  takvim bloklariyla birlikte orneklenir. Seri bagimliligi icin blok duyarliligi.
- Feature grubu ablation: ayni test takvimi, ayni arama butcesi.
- Label/time-shift negatif kontrolu: tahmin becerisi kalirsa leakage veya
  veri duzenleme hatasi aramak; shift sonucunu gercek strateji sanmamak.
- Threshold komsulugu ve birkac onceden secilmis seed ile istikrar; en iyi seed
  degil tum seed dagilimi ve uygulanacak ensemble'in tek getiri serisi.
- Nominal maliyet, +%25 ve +%50 ek maliyet senaryolari gibi onceden dondurulmus
  stresler; uydurma maliyeti gercek broker tarifesi diye sunmamak.
- Veri-quality maskesi, broker/quote farki ve tick/bar-path belirsizligi testi.
- Kampanya seviyesinde coklu deneme duzeltmesi; eksik eski trial kayitlari
  nedeniyle kalan belirsizligin ayrica raporlanmasi.

Bootstrap CI veya bir randomizasyon sonucu tek basina kusursuz sertifika
degildir. Iliskili veride yanlis ornekleme, model iyi olmasa bile dar CI
uretebilir. Bu rapordaki yeni random veto testi de bu nedenle production
acma/kapama karari vermiyor.

## 7. Siradaki uc deney

### Deney A: Secim becerisi ve label/lifecycle parity

**Hipotez:** modelin katkisi sadece islem sayisini azaltmaktan fazladir.
Mevcut dondurulmus modeller kullanilir; yeni model egitilmez. Global ve aylik
random kontroller tamamlandi. Siradaki eksik, listener/native ile uyumlu
event-by-event replay ve ayni risk-zaman maruziyeti kontroludur.

Kabul: ayni veri/maliyet uzerinde tutarli pozitif katkı, yeterli trade ve
senaryo bazinda bozulmayan risk. Kapanma/ters sinyal state mismatch bulunursa
model calismasi durur; once label/execution parity duzeltilir.

### Deney B: Cost-aware payoff + az sayida etkileşim

**Hipotez:** degisken erken exit sonuclarini ve maliyet_R'yi daha iyi modellemek,
salt win classifier'ina gore fayda saglar. Rakipler mevcut ridge/HGB, kucuk
iki-parca payoff modeli ve az etkilesimli duzenlilestirilmis modeldir.
Arama alani deneyden once kaydedilir. ML modele bakmadan once kabul olcusu
ve retention is gereksinimi dondurulur.

Kabul: kronolojik dis katlarda maruziyet-eslestirilmis net deger artisi ve
kuyruk riski bozulmamasi; yalniz bir yil veya tek strateji kopyasindan gelen
kazanc yeterli sayilmaz. Tum adaylarin negatif veya belirsiz cikmasi gecerli
bir sonuc olup productiona zorla model cikarmayi gerektirmez.

### Deney C: Pooled regime-aware kucuk ag

**Hipotez:** ortak piyasa durumu ogrenimi, stratejiye ozel az verinin
varyansini azaltir. Ayni event gunleri train/test arasinda bolunmeden pooled
ridge ile kucuk paylasimli MLP karsilastirilir. Rejim etkileşimi ve gecis/yas
feature'lari ayri ablation'larda test edilir. Temporal CNN daha sonraki
kontrollu kapasite challenger'idir, ilk basamak degildir.

Kabul: tekil strateji modellerine gore gercek dis-kat kazanci, stratejiler
arasi negative transfer olmamasi, makul latency ve MQL inference parity.
Bir modelin testte en iyi oldugu goruldukten sonra onu secmek yeni bir
secimdir; ayni testi bu secimin bagimsiz kaniti diye tekrar sunmamak gerekir.

## 8. Productiona gecis sinirlari

Model dosyasi; dataset hash, feature schema, strateji config, cutoff, egitim
araligi, kalibrasyon/threshold, maliyet varsayimi, kod hash ve deney ID'siyle
immutable olarak saklanmali. Model invalid veya yanlis stratejiye aitse ML ON
durumunda yeni giris fail-closed olur; acik pozisyonun korumasi devam eder.
Guncelleme atomik yapilir, yarim dosya kabul edilmez, onceki model rollback
icin tutulur. Training chart thread'inde yapilmaz.

ML OFF temel stratejiyi, ML ON dondurulmus veto politikasini calistirir.
Otomatik yeniden egitim kendiliginden otomatik production promotion demek
degildir. Yeni model once shadow ve parity kontrolunden gecmelidir.

Karar gunlugunde `candidate_id`, strateji/config, model hash, karar anı,
score, threshold, accept/veto nedeni ve sonradan tamamlanan outcome bulunmali.
Bu kayitlar hem actigi hem reddettigi adaylarda tutulursa forward kanit uretir.
Feature dagilimi kaymasi, calibration hatasi ve execution kaymasi ayri izlenir;
her kayip serisinde otomatik model degistirmek yeni bir overfit dongusu yaratir.

**Sonuc:** hedef overfitting'i bir etiketle yok saymak degil, yanlis bulgunun
productiona gecmesini zorlastirmaktir. Mevcut filtrelerin faydali olduguna dair
ipuclari var; yeni kontrol bu faydanin ne kadarinin sadece maruziyet azalmasi
oldugunu aciga cikardi. Bir sonraki en degerli adim daha buyuk ag degil,
uygulanabilir ve maliyet-eslestirilmis secim becerisini netlestirmektir.

## Kaynak ve erisim notlari

- Gu, Kelly, Xiu (2020), RFS: yazar PDF'i, model secimi ve yontem bolumleri.
- Jensen, Kelly, Malamud, Pedersen, Implementable Efficient Frontier:
  yayin sayfasi/yontem-sonuc metni ve yazarlara ait kod kaydi; replikasyon run edilmedi.
- Jiang, Kelly, Xiu (2023), JF: yayin ozeti, yazar baglantilari ve eklerin kaydi.
- Lo (2004), JPM: MIT'deki tam metin, AMH cercevesi.
- Campbell, Thompson (2008), RFS: yayin/NBER ozeti; PDF erisim siniri var.
- Stock, Watson (2005): Harvard taslagi, shrinkage ve karsilastirma bolumleri.
- Kelly, Malamud, Zhou (2024), JF: Yale PDF'i, RFF ve sonuc bolumleri.
- Buncic (2025, Mart 2026 guncelleme): yazar ve SSRN ozeti; tam metin yok.
- Kelly, Malamud (2025): cevap calismasinin arastirma ozeti, ekleri degil.
- Chen, Pelger, Zhu: arXiv metni, model amaci/veri/validation bolumleri.
- Harvey, Liu, Zhu (2016), RFS: yazar/yayin kaydi ve indekslenmis metin; PDF acilamadi.
- Bailey, Borwein, Lopez de Prado, Zhu: Subat 2015 PBO metni.
- Bailey, Lopez de Prado (2014): DSR tam metni, secim yanliligi bolumleri.
- Guo, Pleiss, Sun, Weinberger (2017), ICML: kalibrasyon metni.
- Barber, Candes, Ramdas, Tibshirani (2023): arXiv v5, exchangeability ve coverage sinirlari.

Butun bir universitenin tum yayinlarinin tarandigi veya bu calismalarin ORB
verisinde tekrarlandigi iddia edilmez. Bu, problem odakli bir literatur ve
metodoloji degerlendirmesidir. Sayisal ORB bulgulari yukarida verilen yerel,
tekrarlanabilir deneylerden; akademik iddialar ilgili birincil kaynaklardan gelir.
