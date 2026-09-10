# ORB ML: Nishide ve Izumi Literatur Incelemesi

Tarih: 2026-09-09. Amac: mevcut ORB sinyallerini yeniden icat etmek degil,
mevcut strateji basina nedensel bir veto filtresi arastirmak.

## Kapsam ve erisim

Kullanici tarafindan verilen profiller **Katsumasa Nishide** ve **Kiyoshi Izumi**
olarak dogrulandi. Scholar'in web araci kimi isteklere 429/403 verdi; herkese acik
profil HTML'leri dogrudan indirilebildi. Liste sayfalari tamamlanana kadar tarandi:
Nishide 50, Izumi 338 profil kaydi. Bunlar 388 benzersiz ve yazarligi tek tek
dogrulanmis makale anlamina gelmez. Dil/surum tekrarlarini ve profilin olasi
yanlis eslestirmelerini bibliyografya sayisi ile karistirmiyorum. Finansla
ilgisiz bir tibbi kayit da goruldu ve arastirmaya alinmadi.

Tam katalog: `tmp/orb_campaign_research/catalogue.json`.
Tam metinleri erisilebilen ilgili calismalarin yontem, veri ve deney bolumleri
okundu; ucret duvari olanlarda ozet/kurumsal kayit seviyesi acikca belirtildi.
Tum 388 yayinin tam metninin okundugu iddia edilmiyor.
Profiller: [Nishide](https://scholar.google.com/citations?user=TmSsP6oAAAAJ&hl=en),
[Izumi](https://scholar.google.com/citations?user=cF2CJ8AAAAAJ&hl=ja).

## 1. Zamanla degisen faktorler

Nakagawa, Ito, Abe ve Izumi'nin **Deep Recurrent Factor Model** calismasi,
TOPIX500 hisselerinde aylik faktor girdileriyle LSTM ve aciklama icin LRP
kullaniyor. Tahmin donemi Nisan 2007-Mart 2015; modeller gecmis bes yillik
veriyle aylik ilerletiliyor. Lineer, SVR, random forest ve DNN karsilastirmalari
var. En dusuk tahmin hatasi ile en iyi portfoy Sharpe sonucu ayni modelde
olmak zorunda degil. Tam metin incelendi.
[Makale, 2019](https://arxiv.org/pdf/1901.11493).

**Bizim cikarimimiz:** modeli yalniz siniflandirma isabetiyle secmemek; net R
ve elde tutulan islem sayisini olcmek. Yon ile trend/mesafe ozelliklerinin
etkilesimi sabit, kucuk bir ozellik grubu olarak sinanabilir. Ancak bu makale
bir JP225 CFD intraday ORB deneyi degildir. Elimizde aylik hisse kesiti ve
bilanco faktorleri yokken ayni mimariyi kopyalamak bir replikasyon sayilmaz.
Geri yonlu recurrent katman, yalniz tahmin anindan onceki girdi penceresinde
calisiyorsa otomatik olarak look-ahead degildir; gelecek veriyle pencereyi
doldurmak ise olur. Mevcut kampanyada LSTM/LRP uygulanmadi.

## 2. Rejim gecisleri ve alternatif veri

Taguchi ve arkadaslarinin **Constructing Equity Investment Strategies Using
Analyst Reports and Regime Switching Models** calismasi BERT ile rapor
duyarliligi, BiGRU tahmini ve GMM-HMM ile uc volatilite durumu kullaniyor.
Rejim degisimi iki hisseli portfoy agirliklarini degistiriyor. Bu, analist raporu
ve aylik portfoy problemidir; bizim alti teknik rejimimizin veya RF01-RF12'nin
dogrulandigi anlamina gelmez. Tam metin incelendi.
[Makale, 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9157435/).

**Bizim cikarimimiz:** rejim durumunu, gecis belirsizligini ve yasini ayri
ozellikler olarak korumak; fakat butun tarih uzerinde HMM egitip geriye donuk
en guzel durum etiketlerini kullanmamak. Ileriye donuk uygulamada sadece o ana
kadar egitilmis parametreler ve filtrelenmis durum olasiliklari kullanilabilir.
Gelecek gozlemlerle yapilan smoothing, canli karar yerine gecemez. Bu kampanya
yeni bir HMM uydurmuyor; EA'nin mevcut kapali-bar rejim ozelliklerini kullaniyor.

## 3. Kar tahmini kadar risk hedefi de onemli

Maeda ve arkadaslarinin **Deep Reinforcement Learning in Agent Based Financial
Market Simulation** calismasi fiyat/derinlik girdileriyle A2C ogrenmesini yapay
emir defteri ortaminda inceliyor. Sermaye odulu ile envanter riski iceren
likidasyon-degeri odulu karsilastiriliyor; egitim ve dogrulama ayri
simulasyonlarda. Ikinci odul, deneyde risk/getiri davranisini belirgin
degistiriyor. Tam metin incelendi.
[Makale, 2020](https://www.econstor.eu/bitstream/10419/239159/1/1736864491.pdf).

**Bizim cikarimimiz:** sadece W/L sinifi kayip/kar buyukluklerini anlatmaz.
0.15R kazanc ile erken cikista +0.01R ayni pozitif sinifta olsa da ayni ekonomik
sonuc degildir. Bu nedenle beklenen gerceklesmis net R regresyonu karsilastirma
ailesi olarak eklendi. Yapay piyasa sonuclari gercek broker doldurmalarinin
kaniti degildir. RL ajanina yeni emir acma veya risk arttirma yetkisi verilmedi;
sentetik kazanan trade satirlari uretilmedi.

## 4. Emir defteri temsili

Tashiro, Matsushima, Izumi ve Sakaji'nin **Encoding of High-Frequency Order
Information and Prediction of Short-Term Stock Price by Deep Learning**
calismasi emir bilgisi temsili ve kisa vadeli tahminle ilgilidir. Yayin kimligi
yazar laboratuvarinin listesinde dogrulandi; bu oturumda tam metin erisimi
saglanamadi. Dolayisiyla bulgulari yeniden urettigimizi iddia etmiyoruz.
[Yazar laboratuvari listesi](https://sites.google.com/socsim.org/izumi-lab-en/publications/papers),
[yayin DOI](https://doi.org/10.1080/14697688.2019.1622314).

**Bizim cikarimimiz:** OHLC/tick-volume verisini gercek borsa emir defteri,
agresor hacmi veya order-flow imbalance diye yeniden adlandirmamak. Bu veriler
elde yoksa paper'daki girdileri sagliyormus gibi yapmak yaniltici olur. Mevcut
volume_ratio20, brokerin hacim serisinin orani olarak kaldi.

## 5. Rejim belirsizligi: Nishide

Nishide ve Nomi'nin **Regime Uncertainty and Optimal Investment Timing**
calismasi yatirim zamanlamasini, onceden belirli bir tarihte olusabilecek rejim
degisikligi belirsizligi altinda inceliyor. Gercek opsiyon/yatirim problemidir.
Yayinci ozeti ve erisilebilir bolumleri incelendi; tam metin erisimi
iddia edilmiyor. [Makale, 2009](https://doi.org/10.1016/j.jedc.2009.04.002).

**Bizim cikarimimiz:** gecise yakin belirsizlik ayri bir olcu olabilir. Ancak
bu kuramsal sonuc, piyasanin dort ayda bir mekanik degistigini veya her geciste
ORB sinyalinin terslenmesi gerektigini soylemez. Rejim yasi ve pending durumu
modele ipucu olabilir; sabit takvimden zorunlu flip kurali cikartilmadi.

## 6. Rejim kosullu volatilite

Elliott, Nishide ve Osakwe'nin **Heston-Type Stochastic Volatility with a Markov
Switching Regime** calismasi opsiyon fiyatlamasinda Markov rejimiyle stokastik
volatiliteyi birlestirir. Kurumsal bibliyografik kayit/ozet seviyesi incelendi;
tam metin bu oturumda edinilemedi.
[Kurumsal kayit, 2016](https://hdl.handle.net/2440/114353).

**Bizim cikarimimiz:** ayni ATR duzeyi farkli trend/gecis kosullarinda farkli
anlam tasiyabilir. Bu ekonomik hipotez, return challenger'daki sabit
trend-depth x vol-depth etkilesimi icin gerekce sunar; ORB karini arttiracagina
dair ampirik kanit sunmaz. Heston parametrelerini bu CSV'den tahmin ettigimizi
veya opsiyon fiyatlama formulunu filtreye tasidigimizi iddia etmiyoruz.

## 7. Likidite saglama ile yon tahmini ayni problem degil

Hayashi ve Nishide'nin **Strategic Liquidity Provision in High-Frequency
Trading** calismasi hizli/yavas islemciler arasinda stratejik likidite
saglamayi ele alir. Yayinci ozeti ve erisilebilir model/sonuc bolumleri
incelendi; tum makale erisimi iddia edilmiyor.
[Makale, 2024](https://doi.org/10.1016/j.irfa.2024.103168).

**Bizim cikarimimiz:** spread, islem sikligi ve katilimci davranisi ekonomik
baglamdir; 'hizli oyuncular bazen karsi yone likidite verir' sonucunu 'her ORB
breakout'u ters cevir' kuralina indirgemek yanlistir. Kampanyada spread/ATR ve
likiditeye ancak mevcut verinin izin verdigi kadar yaklasan volume orani
korundu; hayali order-flow ozelligi eklenmedi.

## 8. Darbogaz ve yorumlanabilirlik

Suimon, Sakaji, Izumi ve Matsushima'nin **Autoencoder-Based Three-Factor Model
for the Yield Curve of Japanese Government Bonds and a Trading Strategy**
calismasi getiri egrisini uc latent faktorle temsil eder; faktorler seviye,
egim ve egrilik acisindan yorumlanir. Yayinci arama sonucundaki yontem/sonuc
bolumleri goruldu; bu oturumda tam metin erisimi tamamlanamadi.
[Makale, 2020](https://www.mdpi.com/1911-8074/13/4/82).

**Bizim cikarimimiz:** onlarca yeni gosterge eklemek yerine az sayida anlamli
durum degiskeni kullanmak degerlidir. Fakat getiri egrisi paneli olmadan bu
autoencoder'i birebir kuramayiz. Bu kampanyada 40 mevcut ozellik ve return
modeli icin on sabit etkilesim kullanildi; autoencoder egitilmedi.

## 9. Yeni MoE yayini neyi kanitliyor, neyi kanitlamiyor?

Suzuki, Sakaji ve Izumi'nin **Mixture of Experts Approach for Domain Adaptation
in Finance** calismasi 20 Temmuz 2026 tarihli bir finansal dil modeli
alan-uyarlama arastirmasidir. Yayinci ozeti incelendi; finansal metin
benchmark'larinda F1 iyilesmesi raporlanir.
[Yayinci, 2026](https://www.fujipress.jp/jaciii/jc/jacii003000041093/).

**Bizim cikarimimiz:** 'finance' ve 'experts' kelimeleri bunu dogrudan bir trade
rejimi uzmanlari sistemi yapmaz. Metin gorevindeki F1 kazanimi, portfoy net R
kazanimi degildir. Bu calisma sonraki metin/rapor altyapisi icin ilgili; mevcut
bir-satir-bir-trade veri setine buyuk MoE yerlestirmek icin yeterli gerekce degil.

## Kampanyaya gercekte tasinanlar

Bu yayinlar birer tasarim referansidir, sonucun garantisi degil. Uygulanan
katmanlar: zaman sirali secim; sadece egitim verisine fit edilen olcekleme;
ayri esik dogrulamasi; gerceklesmis R hedefi; basit modellerle karsilastirma;
rejim/zaman bazli sonuc raporu; acik model/strateji/veri baglama ve secim riski.
Uygulanmayanlar: LSTM-LRP replikasyonu, GMM-HMM, RL piyasa yaraticisi,
order-book CNN, tahvil autoencoder'i, finansal dil modeli MoE'si.

Kucuk bir tablo veri setinde sinir aginin agac/lineer modelden ustun olmasi
varsayilamaz. Bu nedenle benchmark karsilastirmasi kampanyanin zorunlu
parcasidir. [Grinsztajn ve ark., 2022](https://arxiv.org/abs/2207.08815).
Bir modele ayri validation ayirmak, model secimini sinirsiz tekrar edince
overfit'i ortadan kaldirmaz. [Cawley ve Talbot, 2010](https://www.jmlr.org/papers/v11/cawley10a.html).
Bu nedenle son testin ardindan yeni kurallar uretip ayni testte tekrar
'dogrulama' yapilmadi; gelecekteki forward gozlem ayri tutulmali.
