# Finans literaturunden CSV oznitelik adaylari

Tarih: 2026-09-30. Bu belge kaynak taramasi ve deney tasarimidir.
Asagidaki yeni adaylar henuz EA CSV koduna eklenmedi; EA veya modeller bu
turda degistirilmedi. Makale sonucu, bizim stratejilerimizde performans
artisi elde edildigi anlamina gelmez.

## Mevcut sutun sayilari

Test CSV: 990 sutun. Testte tek bir sahte signal-feature ve tek ayar alani var.
Uretim signal-feature basligi 41 alan; EA ayarlari da gercek alanlara aciliyor.

| EA | Ortak veri/sema alanlari | Ayar alanlari | Toplam |
|---|---:|---:|---:|
| Orb | 1029 | 263 | 1292 |
| MaCross | 1029 | 279 | 1308 |
| SolAdvanced | 1029 | 171 | 1200 |

Sayilar mevcut baslik ve adapter kodundan hesaplandi. ORB/Ma ayar
dongulerinde 6 rejim ve 12 RF alani acildi. Bunlar birbirinden bagimsiz
1292/1308/1200 tahmin degiskeni degildir: ayarlar, hedefler, sonuc etiketleri,
durum alanlari ve birbiriyle baglantili ara seriler de dahildir.
Test CSV'de 517 `f_kiv_*` alani var. Kaynak ara durumlari, olay yaslari,
normalized mesafeler, egimler ve gecisler bunlara dahildir.

Mevcutta: asagi/yukari return semi-deviation, carpiklik, excess kurtosis,
lag-1 otokorelasyon, isaret entropisi, yol verimliligi, hacim anomalileri,
rejim gecis yasi ve coklu zaman dilimi ozetleri var. Return standart sapmasi
hesaplayan `realized_vol`, akademik `sqrt(sum(r^2))` ile ayni tanim degildir.
Yeni realized-variation alanlari ayri ve dogru isimle eklenmeli.

## Oncelikli adaylar

### 1. Sicrama payi ve bipower variation

Kaynak: Barndorff-Nielsen ve Shephard, Power and Bipower Variation with
Stochastic Volatility and Jumps (2004).
https://public.econ.duke.edu/~get/browse/courses/883/Spr16/COURSE-MATERIALS/Z_Papers/BNSJFEC2004.pdf

Gecmis kapali bar log-returnleri ile RV=sum(r_i^2),
BV=(pi/2)*sum(abs(r_i)*abs(r_{i-1})), jump excess=max(RV-BV,0)
ve jump share=jump excess/RV; sifir RV icin eksik/tanimlanamaz durum.
Sonlu ornek duzeltmeleri ve noise etkileri acik secilmeli. Bu oran bir
kesin jump tespit testi degildir; test istatistigi ayri bir hesaplamadir.

Hipotezimiz: ayni trend gorunumu, duzgun hareket veya anlik sok kaynakliysa
setup sonucu farkli olabilir. Kapali M1/M5 serileri ile baslanabilir.

### 2. Permutation entropy ve gorulmeyen ordinal pattern payi

Kaynak: Bandt ve Pompe, Permutation Entropy (2002).
https://doi.org/10.1103/PhysRevLett.88.174102
Finans uygulamasi: Zunino ve digerleri (2009).
https://www.sciencedirect.com/science/article/pii/S0378437109002593

Yalniz pozitif/negatif return orani degil, ardarda gelen gozlemlerin
siralanis dagilimi. Embedding 3/4 ve birkac sabit gecikme denenebilir.
Esit fiyatlar icin tie kuralinin kaydi gerekli. Dusuk entropy otomatik
kar garantisi degildir. Gorulmeyen pattern, kisa ornekte yasak pattern
oldugu anlamina gelmez. Kullanilan seri (log-fiyat/return) acik tutulmali.

### 3. Directional-change / intrinsic time

Kaynak: Glattfelder, Dupuis ve Olsen (2011).
https://arxiv.org/abs/0809.1040

Sabit saat yerine fiyat esigiyle tanimlanan olaylar: son onayli donusten
beri sure, son olay yonu, halen gozlenen overshoot, esik-normalize hareket,
birim zaman basina onayli donus sayisi. Bitmemis hareketin gelecekteki
son uzunlugu kullanilamaz. Tick sirasini gerektirir; kapali bar close
surumu ancak acikca isimlendirilmis daha dusuk cozunurluklu uyarlamadir.

### 4. Cok olcekli variance ratio

Kaynak: Lo ve MacKinlay (1988).
https://web.mit.edu/~alo/www/Papers/lo-mackinlay-88.html

VR(q)=Var(q-adimli return)/(q*Var(tek-adimli return)). q=2,4,8 gibi
az sayida sabit olcek; ornek sayisi ve tahmin belirsizligi de kaydedilmeli.
Otokorelasyonun olcekler arasi davranisini gosterebilir. VR>1/<1 tek
basina istatistiksel kanit veya giris sinyali sayilmaz.

### 5. Gunun saatine gore normalize aktivite / volatilite

Kaynak: Andersen ve Bollerslev (1997).
https://doi.org/10.1016/S0927-5398(97)00004-2

Bizim uyarlamamiz: yalniz onceki seanslardan ayni saat dilimi icin
volatilite ve quote-update aktivitesi referansi. O anki aktivite / o saatin
gecmis medyani ve abnormal volatility. Normal acilis hareketini gercek
anomaliden ayirmayi test edecegiz. Referans tum veri setinden veya
sonraki gunlerden hesaplanamaz. Broker/DST/seans takvimi tutarli olmali.

### 6. Dusuk dereceli path signatures

Kaynak: Futter, Horvath ve Wiese, Signature Trading (2023).
https://arxiv.org/abs/2308.15135
Yeni hesaplama/finans uygulamasi: Choi (2026).
https://doi.org/10.1002/for.70176

Gecmis normalize fiyat-zaman yolu icin ikinci dereceden signature ve
signed area. Fiyat-aktivite veya cross-asset yollarinin verisi varsa bunlar
ayri hipotezlerdir. Bir boyutlu signature sirayi yeterince ayirt edemez;
embedding, olcek ve truncation acik olmali. Birinci/ikinci dereceden
baslamak, onlarca derece eklemekten daha savunulabilir. 2026 makalesinde
fayda varliklar arasinda esit degil; hisse senetlerinde ilave katkisi az.

## Ikinci asama ve veri kisitlari

- HAR-RV: gecmis gun/hafta/ay gerceklesen volatilite bilesenleri.
  https://doi.org/10.1093/jjfinec/nbp001
- Rough volatility: log-volatilite artimlarinin olcek davranisi. Return
  Hurst'u ile karistirilmamali; kisa/noisy pencerede tahmin guvenilmez.
  https://arxiv.org/abs/1410.3394
- Hawkes: event clustering / self-excitation, yeterli timestamp verisi
  ve rolling kalibrasyonla. Broker quote update'leri exchange trade'i
  degildir; bunlardan hesaplanan deger piyasa endojenligi diye sunulamaz.
  https://arxiv.org/abs/1201.3572
- Cont-Kukanov-Stoikov OFI: best bid/ask FIYAT ve MIKTAR degisimleri gerekir.
  Bid/ask fiyati veya tick volume yeterli degildir. Mevcut quote proxy
  gercek exchange OFI diye yeniden isimlendirilmeyecek.
  https://arxiv.org/abs/1011.6402
- Corwin-Schultz gibi transaction high/low spread estimatorleri CFD bid
  OHLC'sine dogrudan ayni anlamla uygulanamaz. Gercek quote spread'i
  mevcutken onu tercih et; estimatoru slippage veya measured spread diye
  sunma. https://doi.org/10.1111/j.1540-6261.2012.01729.x

## Deney protokolu

1. Once ilk 6 aileden sinirli 30-60 aday, sadece CSV export yoluna.
2. Her alan icin cutoff, kaynak, tanim, parametre ve missing status.
3. Kaynak denklemlerine karsi sayisal test; future-prefix-invariance testi.
4. Strateji bazli purged chronological folds; scaler/feature selection
   sadece egitim fold'unda. Holdout model seciminde kullanilmayacak.
5. Aile bazli ablation: baseline ile ayni fold/trade/cost taniminda
   net R, drawdown, coverage ve belirsizlik karsilastirmasi.
6. Gelisme yoksa aileyi reddet; binlerce korelasyonlu sutunu az trade'e
   verip in-sample WR artisini basari sayma.

## Veri yeterliligi ve haber katmani: kullanici kosulu

Veri bulunabilirligi bir on kosuldur, model performansi gerekcesiyle
asilamaz. Bir oznitelik dogrudan olculebilir, acikca isimlendirilmis
proxy veya kullanilamaz olarak siniflanacak. Proxy, akademik orijinali
yerine gecmis gibi sunulmayacak. Eksik veri sifirla doldurulmayacak.
Haber ve information katmani henuz implemente edilmedi.

Ilk aday, ekonomik olay takvimi: ilgili para birimleri/ulkeler, onceki
yuksek onemli olaydan beri sure, o anda bilinen sonraki olaya kalan sure,
gecmis 30/60/240 dakikada olay sayisi ve olay sinifi. Bugun bilinen
takvim, gecmiste aynen biliniyordu varsayilamaz; schedule degisiklikleri
ve erisilebilirlik tarihleri de arastirilacak.

Makro surprise yalniz yayinlanmis ilk actual ile o zaman mevcut consensus
forecast varsa hesaplanacak. Revize deger veya actual-minus-previous
consensus surprise diye sunulamaz. ALFRED vintage verisi yararli, ancak
gun hassasiyeti tek basina M1 entry zamanini dogrulamaz.

Kaynaklar:
https://www.mql5.com/en/docs/calendar
https://fred.stlouisfed.org/docs/api/fred/realtime_period.html

Ikinci aday: arsivli haber basligi/metni, yayinci, asset/topic relevansi,
haber yasi, tekil hikaye sayisi, tekrar yayim orani ve sentiment
dagilimi. Birden fazla haber trade satirlarini cogaltmayacak; pencere
ozetleri ayni trade satirina eklenecek. Sentiment bir buy/sell etiketi
degildir. Ornek finansal NLP kaynagi:
https://arxiv.org/abs/1908.10063

Kural: haber/metin surumunun available_at degeri entry_time'dan sonra
olamaz. published_at, first_seen_at, received_at ve version ayri anlamlar
tasir. Bugun indirilen guncellenmis sayfa orijinal metin diye kullanilmaz.
Haber metninde gelecekteki piyasa sonucunu anlatan ekler varsa reddedilir.

GDELT metadata/arsiv icin aday, fakat tam metin, saniye hassasiyetinde
ilk yayin ve 5 yillik kesintisiz kapsam garanti degil. Tum arsiv kapsamasi
olmadan 'haber yok' denemez: NO_EVENT_IN_COVERED_WINDOW ile DATA_MISSING
farkli durumlar olacak. Collector timestamp'leriyle konservatif bir
availability tanimi yapilabilir; gercek trader latency'si diye sunulmaz.
https://gdeltproject.org/data.html
https://blog.gdeltproject.org/announcing-the-gdelt-article-list-rss-feed/

Haber ekleme de yalniz CSV disari aktarma yolunda ve varsa yerel onbellek
uzerinden yapilacak; normal audit veya sinyal cekirdegi web cagrisiyla
yavaslatilmayacak. Once kisa donem coverage/timezone/revision testi,
sonra yeterli veri varsa genis tarih araligi ve dis-orneklem ablation.
