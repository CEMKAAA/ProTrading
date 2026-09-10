# ORB: 53 Stratejilik ML Kampanyasi

## Sonuc

**53/53 stratejinin 260 haftalik CSV'si olusturuldu ve dogrulandi.**
Toplam **48.744 islem** var. Veri setleri birbirinden ayri; ortak veya karisik
bir egitim CSV'sine donusturulmedi. 30 JP225m, 22 USDJPYm ve 1 USTECm stratejisi
incelendi. 46 yerlesik stratejiye 7 kaydedilmis kullanici stratejisi dahil edildi.

**50 stratejide 98 secilmis model adayi** kaydedildi: 48 MLP ve 50 net-R
regresyon modeli. Bunlarin arkasinda ayri gelistirme katlamalarinda aday model
egitimleri ve benchmark'lar bulunur. 53 stratejinin hepsine basarili model
uretilmis gibi davranilmadi.

14 model, kendi ayni test orneklemindeki filtresiz stratejiden daha yuksek net R
verdi; bunlar 11 farkli stratejiye ait. Ancak **106 model/strateji denemesini
hesaba katan aile-geneli belirsizlik kontrolunden gecen model yok**. MLP'nin
mevcut yerel yayin kontrollerini de gecen yok. Bu nedenle hicbir model aktif
trade filtresi olarak yayinlanmadi veya charta yuklenmedi.

Bu raporun karari: umut veren adaylari sakla, fakat bu kampanyayi kanitlanmis
canli alpha veya overfit-free basari diye sunma. Daha fazla ayni-test aramasi
ile sonucu zorlamak, kullanicinin overfit olmama hedefiyle celisir.

## Dosyalar

Son ve dogrulanmis CSV klasoru:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbMLCampaign_20260909_v3\Datasets
```

Arastirma modelleri ve tum sonuclar:

```text
logs/OrbMLCampaign_20260909_v3/training_v1/
```

- `Results.md`: 53 stratejinin iki model ailesiyle tam sonuc tablosu.
- `all_strategies.csv`: WR, net R, retention, drawdown, MinCum, test tarihleri ve ret nedenleri.
- `test_by_year.csv`: test bolumunun takvim yillarina gore kirilimi; bes yillik OOS iddiasi degil.
- `test_by_regime.csv`: test bolumunun alti teknik rejime gore kirilimi; sonradan filtre secmek icin dogrulama seti degil.
- `<preset_id>/state.json`: strateji, veri hash'i, sure ve iki egitim sonucunun ozeti.
- `<preset_id>/mlp/*.candidate.model`: sayisal MLP agirliklari; aktif `.model` degil.
- `<preset_id>/mlp/campaign_report.json`: katlamalar, esik, benchmark, bootstrap, parity ve ret nedenleri.
- `<preset_id>/return/frozen_selection.json`: testten once sabitlenmis secim.
- `<preset_id>/return/return_model.research.joblib`: sadece guvenilir yerel arastirma icin; EA bunu yukleyemez.
- `<preset_id>/*/test_predictions.csv`: testteki her karar ve degistirilmemis temel trade etiketi.
- `artifact_checksums.json`: kaydedilen arastirma ciktisinin butunluk envanteri.

Ust kampanya klasorunde `export_integrity.json`, derleme loglari, kaynak/binary
hash'leri ve `compiled_sources/` bulunur. Common Files kampanya klasorundeki
`Settings/` runtime snapshot'larini, `UserStrategies/` yedi ozel stratejinin
orijinal kayitlarini korur. Yerlesik preset'ler kaynak snapshot'inda mevcuttur.
Arastirma modeli bir preset ismiyle degil, **preset + konfigurasyon + veri
hash'i + kaynak/build kimligi** ile baglidir. Isimde '10R' yazmasi gercek
geometrinin 10R oldugunu garanti etmez; kayitli ayarlar esastir.

Literaturun ayri incelemesi:
`docs/ORB_ML_Literature_Review_20260909.md`.
Onceden sabitlenen plan:
`docs/ORB_ML_All_Strategies_Campaign_Plan.md`.

## Dikkate deger ama henuz onaylanmamis adaylar

Asagidaki tablo **son %20 test** icindir; bes yilin toplami veya yeni bir forward
hesabin kazanci degildir. Stratejiler testte iyi gorundukleri icin bu tabloda
yer aliyor; bu tablo model secmek icin bagimsiz ikinci bir validation degildir.

| Strateji | Model | Filtresiz R | Filtreli R | Tutulan islemler | Kapanis-DD: once / sonra |
|---|---|---:|---:|---:|---:|
| usdjpy10RVeryHighWRsETUP | Net-R, sig agac | +7.05 | +11.10 | %65.8 | 2.93R / 1.01R |
| LiqNarrative1.5RModel | MLP | +24.16 | +28.72 | %91.8 | 10.20R / 11.20R |
| ProUsdJpySetup | MLP | +15.33 | +16.83 | %93.4 | 5.65R / 4.26R |
| usdjpyGateStateOn | MLP | +2.98 | +4.81 | %74.8 | 4.79R / 3.99R |
| 1RYildiz | Net-R | +3.61 | +5.34 | %55.4 | 9.39R / 7.33R |

`Muhtesem4lu #2` ve `1RYildiz` bu deneyde ayni karsilastirma sonucunu uretti.
Bunlari iki bagimsiz basari kaniti olarak saymak dogru degil.

### USDJPY adayi

Kayit kimligi: `user_c9a062d8f83b3ce13fd4574b`. Model gelistirme katlamalarinda
`hgb_7` olarak secildi, validation esigi -0.05R. Esik sifirin altinda olabilir:
regresyon skorunun kalibrasyonu ile gerceklesmis ekonomik esik ayni sey degil;
deger validation'da donduruldu ve teste gore degistirilmedi.

Test tarihleri broker saatinde 2025-09-08 ile 2026-09-08. Temel strateji 240
islemde 223W/17L; filtre 158 islemde 153W/5L verdi. WR %92.92'den %96.84'e
yukseldi. Net R +7.0453'ten +11.0987'ye cikti. Bu, 82 islemi reddederken 12
loser ve 70 winner'i elemek demektir; salt WR artisi diye sunulmuyor.

En buyuk test iyilesmesi bu adayda RANGE LOW VOL grubunda goruldu, fakat bu
sonradan gozlenen bir kirilimdir. Onu yeni bir kesin rejim kuralina cevirip ayni
testte yeniden olcmek bagimsiz dogrulama olmaz. Modelin aile-geneli kanit
kontrolu basarisiz; ileri veri olmadan production onayi yok.

### JP225 adayi

Kayit kimligi: `jp_15_imb`; kullanici adi `LiqNarrative1.5RModel`, fakat bu bir
ORB preset adidir, normal Liq Narrative EA'sinin yeni testi degil. MLP alpha=10,
esik=0.35. Testte 208 islemin 191'i tutuldu. WR %44.23'ten %45.55'e, net R
+24.1555'ten +28.7185'e yukseldi. Buna karsin kapanis bazli maksimum drawdown
1R artti. Validation donemi filtrelenince de -14.28R idi. Bu nedenle 'daha iyi
son net R' ile 'her bakimdan daha iyi sistem'i karistirmiyorum.

### Buyuk ama yaniltici iyilesme

`HolyGrail [USDJPY]` return modeli -82.37R'yi -14.23R'ye tasidi. +68.14R
iyilesme etkileyici gorunebilir, fakat sonuc hala negatif ve testte islemlerin
yalniz %23.6'si tutuluyor. Bu adayi winner listesine sokmadim. Validation'da
saglanan retention siniri, dagilim degisince testte saglanmayabilir.

## Egitilemeyen veya secilemeyen modeller

| Strateji | Islem | Sonuc |
|---|---:|---|
| 2RModeljp225 | 282 | Iki aile de asgari 300 kullanilabilir islem kosulunu saglamadi |
| jp225HighProbaLongWait | 287 | Ayni ornek sayisi engeli |
| jp225HolyGrail | 234 | Ayni ornek sayisi engeli |
| DISPONUsefullFirstTimeUstecOrb0.5R | 330 | MLP icin katlama/validation esigi yeterli islemi tutmadi; return adayi kaydedildi |
| LiqNarrativeFvgONRetestVolOn1.5RSetup | 474 | Ayni MLP esik engeli; return adayi kaydedildi |

Egitim asgari kosulu deneyden once belirlendi. Sonucta daha cok model uretmis
gorunmek icin ornek siniri dusurulmedi, etiket uydurulmadi veya rastgele
train/test karistirilmadi. Bu bloklar da tam sonuc dosyasinda yer alir.

## Deney tasarimi

Her CSV once tamamlanma marker'i, SHA-256, satir sayisi ve kimlik tutarliligi
kontrolunden gecti. Sinyalin kapanis zamani ozelliklerin hazir oldugu andir;
ozellikler giristen sonra olamaz. Sonuc etiketi giristen once veya veri kesim
tarihinden sonra olamaz. Etiket icerigi: mevcut audit motorunun gerceklesmis,
ayarlanmis maliyetlere gore net R'si. Erken kapanan winner'a otomatik tam TP R
atanmadi; erken kapanan loser'a otomatik -1R atanmadi.

Veri zaman sirasinda eski %60 gelistirme, sonraki %20 validation, en yeni %20
test olarak ayrildi. Sinirlari gecen trade etiketleri 24 saat ek boslukla
temizlendi. Yani sadece sinyal zamanina bakilmadi; trade'in kapandigi zaman da
sonraki bolume sizmamali. Bu nedenle kullanilan egitim satiri sayisi nominal
%60'tan biraz az olabilir.

MLP ailesinde 40 sabit ozellik, 16 ReLU noronu, alpha=1/10/100, en fazla 400
epoch kullanildi. Eski %60'in icinde uc expanding walk-forward katlama var.
Her fit icinde son kronolojik bolum early stopping icin ayrildi. Scaler sadece
fit bolumunden ogrendi. Aday secimi fold net-R iyilesmesinden, esik validation
bolumunden yapildi. Logistic regression ve kucuk boosted-tree classifier ayni
kosullarda benchmark olarak egitildi.

Return ailesi gerceklesmis net R'yi tahmin etti. Ridge alpha=10/100/1000 ve
7 yaprakli, 80 iterasyonlu histogram gradient boosting karsilastirildi. 40
ozellige sekiz yon-hizalanmis fiyat/trend terimi ile iki rejim etkilesimi
eklendi. Esikler ve model aileleri teste bakmadan kodda sabitlendi. Gelistirme
ve validation filtresiz hali gecmediginde model karari **filtresiz kal** oldu.
Bu sebeple bazi sonuc satirlarinda fark sifirdir; hesaplama hatasi degil.

Tum son-test agirlik/esik kararlari sabitlendi. Test sonucunu degistiren bir
regresyon testi, model agirligi/esik seciminin degismedigini dogruladi. Son
testte kotu cikan stratejiler icin yeni haftagunu kurali veya yeni esik
aranmadi. Ilk veri ihracatindaki zaman hatasi duzeltilince yeniden egitim
yapildi, ancak model hiperparametreleri bu sirada degistirilmedi.

## Belirsizlik ve sinirlar

Filtreli eksi filtresiz net R farki kapanis gunlerinde eslestirildi; islemsiz
takvim gunleri de sifir olarak dahil edildi. Dairesel moving-block bootstrap
20.000 tekrar, blok uzunlugu ceil(gun sayisi^(1/3)) ile yapildi. Iki model
ailesi x 53 strateji icin Bonferroni duzeltmesi uygulandi. Bu bir yaklasik
bootstrap tanisidir; marjinal p-degerlerinin varsayimlarini veya yapisal rejim
degisimini sihirli bicimde ortadan kaldirmaz. Aile-geneli duzeltme stratejilerin
bagimsiz olmasini gerektirmez, fakat onceki insan/strateji secimini tam olarak
hesaplamaz.

**En onemli sinir:** bu stratejiler zaten gecmis goruntulere/auditlere bakilarak
gelistirildi. ML agirliklari son bolumde fit edilmemis olsa bile temel
stratejinin tarih secimi tamamen bakir degildir. Bu nedenle bu bir kronolojik
pseudo-out-of-sample arastirmadir; bugunden sonra kilitlenen forward donemin
yerini tutmaz. Model seciminde validation'a tekrar tekrar uyum saglama riski
literaturde de aciktir.
[Cawley ve Talbot](https://www.jmlr.org/papers/v11/cawley10a.html).

Trade filtrelemesinin net R tablosu, temel stratejinin **ayni trade etiketleri**
uzerindeki counterfactual veto analizidir. Bir emrin reddi sonraki pozisyon
state'ini, ters sinyalle kapamayi veya kabul edilebilecek baska girisleri
degistiriyorsa tam stateful EA/listener replay gerekir. Bu kampanya o canli
portfoy replay'inin veya broker fill testinin yerine gecmez.

R cinsinden drawdown kapanmis-islem egri zirvesinden hesaplandi. Floating MAE,
gun icindeki equity tabani veya challenge EOD trailing ihlal sayisi degildir.
R esitlemesi lot/marjin/komisyon para birimi donusumunu dogrulamaz.

Maliyetler deney basinda sabitlendi: fallback spread gozlemleri JP225m=31,
USDJPYm=10, USTECm=112 point. Native tick replay uygun yerde bid/ask kullanir;
`cost_r=0` her zaman spread yok demek degildir. Input slippage ve ek komisyon
varsayilanlari sifirdir. Dolayisiyla 'net R', gercek challenge hesabinin butun
ucretleri dusulmus garanti getirisi degil, **kayitli maliyet modeline gore**
sonuctur. Bu degerler sonuclari guzellestirmek icin ayarlanmadi.

260 hafta 1.820 gundur; tam bes takvim yiliyla birebir ayni degildir. Bu
verilerde ilk trade 2021-09-15, son trade 2026-09-08. Bir stratejinin ilk trade'i
daha gec olabilir; bu tek basina o sembolun onceki barlarinin eksik oldugunu
gostermez. Coverage guard ve CSV butunluk kontrolleri ayri uygulandi.

## Bulunan veri hatalari ve duzeltme

Ilk kampanyada IMB1M girisine yanlislikla M5/M15 breakout suresi ekleniyordu.
Simulasyon M1 kapanisindan trade'i baslatiyor, CSV ise daha gec giris saati
yaziyordu. Bazi dogru TP'ler bu nedenle 'giristen once cikis' gibi gorunup
gecersiz etiket oluyordu. Ayrica gun/session taramasinin tarih kesiminden sonra
gorulebilen sinyalleri CSV'ye girebiliyordu.

Duzeltme sadece ihracat saatine ve export satir secimine uygulandi. Tam audit
capture sayisi once dogrulaniyor; sonra kesim tarihinde henuz mevcut olmayan
adaylar ayiklaniyor. 7.639 giris zaman damgasi dogru timeframe'e getirildi,
463 etiket kurtarildi, kesim sonrasi 14 satir cikarildi. 53 CSV'nin tamami:

- ayni eski sinyal mumlari ve yonleri;
- ayni entry/SL/TP fiyatlari;
- ayni cikis zamani ve nedeni;
- onceden gecerli etiketlerde ayni net R;
- audit toplamiyla 1e-6R tolerans icinde eslesme;
- sifir eksik ozellik, sifir gecersiz etiket.

Denemenin basarisiz v2 ihracatinda tarih kontrolu kesim zamani atanmadan
calistigi icin capture-count guard dosya uretimini durdurdu. Guard bypass
edilmedi; filtre dogru tamamlanma asamasina tasindi. Yalniz `v3` klasoru nihai
veridir. Onceki denemeler izlenebilirlik icin tutuldu ve finale karistirilmadi.

Ayni export-only duzeltme StrategyLibrary workspace'ine v6.85 olarak tasindi.
Sinyal uretimi, risk, emir acma/kapama ve listener kaynaklari degistirilmedi.
Yeni kaynak kontrati eski CSV/model kimligini sessizce yeniden kullanmaz.
Arastirma build'i ve canli EA build'i ayni kimlik degildir; kampanya modeli
dogrudan yeniden adlandirilip canli `.model` yapilmamali.

## Dogrulama ve dagitim durumu

- Python testleri: **52 passed**, 3 uyari. Ikisi sentetik LBFGS parity testinde
  convergence warning; biri dateutil deprecation. Bu kampanya Adam erken-durdurma kullandi.
- MQL research batch derlemesi: **0 errors, 0 warnings**.
- StrategyLibrary v6.85 staging derlemesi: **0 errors, 0 warnings**.
- 48 MLP'nin portable ve sklearn olasilik farki en fazla **1.67e-16**.
- Baseline karsilastirmasi: 36 signal/audit govdesi korunmus; 8 Backtest
  fonksiyonu ayni. Onceki reference-stat orchestration duzeltmeleri ayri
  runtime probe ile dogrulanmisti, burada yeniden strateji matematigi yazilmadi.
- CSV hacmi **67.46 MB**; final egitim artifact'leri yaklasik **16 MB**.
- Canli MT5 chartlari restart edilmedi. cTrader/Ninja/Quantower ayarlari,
  riskleri ve listener dosyalari degistirilmedi. Hicbir model aktive edilmedi.
- Workspace EX5 yeni v6.85 ile esitlendi; aktif terminale otomatik dagitim yok.

## Tekrarlanabilir komutlar

```powershell
python scripts/validate_orb_ml_campaign_exports.py --root "C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbMLCampaign_20260909_v3" --prior "C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbMLCampaign_20260909" --out logs/OrbMLCampaign_20260909_v3/export_integrity.json

python scripts/run_orb_ml_training_campaign.py --root "C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbMLCampaign_20260909_v3" --out logs/OrbMLCampaign_20260909_v3/training_v1

python scripts/summarize_orb_ml_campaign.py --out logs/OrbMLCampaign_20260909_v3/training_v1
```

Egitim komutu ayni kod/veri hash'leriyle tamamlanan stratejileri tekrar egitmez.
Kod degismisse ayni klasordeki donmus sonuclari ezmek yerine durur. Yeni bir
arastirma denemesi ayri dizin ve ayri protokol gerektirir.

Sonraki anlamli adim ayni holdout'ta v100 aramak degil: yukaridaki adaylari
kilitli parametrelerle yeni sinyallerde shadow olarak olcmek, gercek maliyetleri
ve stateful veto replay'ini dogrulamak. Bu rapor tek basina sermaye veya model
aktivasyonu icin onay degildir.
