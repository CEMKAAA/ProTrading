# ORB Training-Age R4: Sonuclar

2026-09-11. Kampanya tamamlandi. Canli model/EA/listener degisikligi: **0**.

## Ana Sonuc

"Eski veri yeni modelleri bozuyor" hipotezi genel bir aciklama olarak dogrulanmadi.
Egitim gecmisini kisaltmak bazi strateji/model kombinasyonlarinda yararli, bazilarinda
zararli. Validation esigi ve model secimi, bu etki kadar onemli bir arastirma konusu.
Bu bir literatur kesfi veya overfittingin cozuldugu iddiasi degildir.

Mevcut canli modeller korunuyor. Mevcut modelden daha iyi gorunen tek bir test
sonucu, daha az overfit olundugunu veya production degisikligini kanitlamaz.

## Deney

- 22 USDJPY stratejisi, kendi stratejisine ait dogrulanmis CSV birlesimi.
- 2018 baslangicli 41.627 toplam strateji-islem satiri. Varyantlar bagimsiz degil.
- Iki test: 2024-09-09 / 2025-09-09 ve 2025-09-09 / 2026-09-09.
- Her testten once bir yil validation; egitim validation baslamadan bitiyor.
- Son 3 yil, son 5 yil, tum gecmis, iki yil yari omurlu agirlikli tum gecmis.
- Ridge alpha=100 ve HGB 7 yaprak, 80 iterasyon. Ayni 50 oz nitelik.
- 352 model egitildi; tum-gecmis son donem 44 modeli R3 tahminlerini yeniden uretti.
- Esikler testten once validation ile belirlendi. Sabit 0 esigi ve ek validation
  eleme kapisi da TANI amacli raporlandi, testten sonra bir kazanan deploy edilmedi.
- Agirlik toplami kollarda esit: ornek azalirken L2 cezasinin goreli gucu degismesin.
- Her sinirda 24 saat etiket purge; strateji kimligi ve veri/model hash kontrolleri.

En eski ve yeni export arasinda Eylul 2021'de alti gunluk bosluk var. Uydurulmus
veri yok. Bu test yillari onceki arastirmalarda goruldu; saf yeni holdout degiller.
Tarihler kaynak broker zaman ekseninde, gercek GMT'ye yeni bir donusum yapilmadi.

## Veri Yasinin Etkisi

Asagidaki sayilar ayni modelin tum-gecmis koluna gore PnL karsilastirmasidir.
Iki test yilinda 22*2=44 strateji/yil gozlemi var; bunlar bagimsiz deney degil.

| Model | Egitim | Daha iyi | Daha kotu | Ayni |
|---|---|---:|---:|---:|
| Ridge | Son 3 yil | 10 | 20 | 14 |
| Ridge | Son 5 yil | 10 | 21 | 13 |
| Ridge | Tum gecmis, agirlikli | 14 | 17 | 13 |
| HGB | Son 3 yil | 20 | 16 | 8 |
| HGB | Son 5 yil | 16 | 16 | 12 |
| HGB | Tum gecmis, agirlikli | 17 | 17 | 10 |

HGB agirlikli kol, ikinci test yilinda 11 daha iyi / 4 daha kotu / 7 ayni;
birinci yilda 6 daha iyi / 13 daha kotu / 3 ayni. Tek iyi yili genellemiyoruz.

### Esik Secimi Ayrimi

HGB son-5-yil kolunda sabit 0 esigi, ayni sabit esigi kullanan tum-gecmis koluna
gore 30/44 daha iyi PnL verdi. Esikler validation'da secildiginde 16/44.
Ayni sinyal dizilerini tekilleyince bu sayilar 26/38 ve 12/38.

Bu, esik politikasinin veri-yasi avantajini degistirebildigini gosterir. Ancak:

- Sabit 0 esigi testte daha iyi gorundu diye onu yeni canli kural yapmadik.
- Daha fazla/az islem elemek, net PnL'yi oynatabilir; aylik islem sayisiyla
  eslestirilmis rastgele-secim becerisi de evaluation.json'da yer aliyor.
- HGB son-5-yil modelinin karesel tahmin hatasi (MSE), tum-gecmisten sadece
  9/44 karsilastirmada daha dusuk. Karar esiginde daha iyi PnL, daha iyi genel
  getiri tahmini anlamina gelmiyor. MSE de tek basina trading hedefi degildir.
- Regim dagilimi/oz nitelik kaymasi tanilari nedensellik veya rejim mekanizmasi
  kesfi degildir. Bu tur yalnizca egitim yasi ve agirligini degistirdi.

## Iki Yilda Da Tum-Gecmisten Iyi Ornekler

Bu tablo mevcut production modeliyle DEGIL, ayni ailedeki tum-gecmis adayi ile
karsilastirma. Tum test satirlari kullanilir. Sonradan fark edilen orneklerdir.

| Strateji / aday | Birinci yil PnL, tum -> aday | Ikinci yil PnL, tum -> aday | DD, birinci yil | DD, ikinci yil |
|---|---:|---:|---:|---:|
| 0.25RUsdJpy / Ridge son 5 yil | +3,12 -> +3,66R | +1,15 -> +2,66R | 6,27 -> 6,09R | 5,04 -> 4,43R |
| 1RYildiz / HGB son 3 yil | -13,75 -> -5,60R | -3,86 -> +6,27R | 14,57 -> 7,54R | 12,53 -> 7,46R |
| usdjpy10RVeryHighWRsETUP / HGB son 3 yil | -0,74 -> +0,51R | +5,65 -> +10,17R | 3,94 -> 3,17R | 2,84 -> 1,19R |

1RYildiz ile Muhtesem4lu #2 ayni sonuc dizisini tekrar eder, bagimsiz teyit sayilmaz.
HighfreqHighWRusdjpy'nin son-3-yil Ridge kolu da iki yilda tum-gecmisten iyi;
fakat ikinci yil tum islemleri geciriyor. O yili yeni ML filtre basarisi saymiyoruz.

## Kayitli Eski Modelle Karsilastirma

Yalnizca son yilda ve hem yeni hem eski modelin bilgi donemi bittikten sonraki
ORTAK satirlarda hesaplandi. Alti mevcut modelin validation sonu nedeniyle bazi
ilk satirlar adil eslesmeden cikiyor; onceki tablonun tam-yil degerleriyle fark olabilir.

| Strateji / aday | Eski PnL | Aday PnL | Eski DD | Aday DD |
|---|---:|---:|---:|---:|
| ProUsdJpySetup / HGB son 5 yil | +16,43R | +17,86R | 4,26R | 2,93R |
| 0.5RGoodUsdjpy / HGB tum gecmis | +4,22R | +9,96R | 6,56R | 4,00R |
| 0.20R [USDJPY] / HGB tum gecmis | +2,53R | +7,38R | 3,82R | 2,37R |
| usdjpy10RVeryHighWRsETUP / HGB son 3 yil | +11,01R | +10,17R | 1,01R | 1,19R |

Tum-gecmis HGB adaylari R3'te de vardi. Burada gorulmeleri yeni bir veri-yasi
basarisi degil: R3'un ONCEDEN secim katmani onlari aktif politika yapmamisti.
Bu tablo en iyi adaylari test sonrasi secip elde edilmis canli getiri gibi sunulamaz.

ProUsdJpySetup son-5-yil HGB adayi, onceki testte +2,15R verdi; ayni ailenin
tum-gecmis adayi +7,19R idi. Son yildaki iyilesme iki yillik genel ustunluk degil.
Son-yil eskiye gore +1,43R farkinin 20-gunluk blok-bootstrap %95 araligi
yaklasik [-7,13R, +10,05R]. Belirsizlik buyuk.

Aktif filtreyle hem PnL hem DD'yi iyilestiren 15 aday kombinasyonu / 8 strateji
var. Bunlar testten sonra gorulen kombinasyonlar; bir uretim politikasi degil.

## Guven Ve Overfit

- 5 ve 20 takvim gunluk ortak bloklarla, her biri 20.000 tekrar.
- 264 asil veri-yasi karsilastirmasinda, her iki blokta duzeltmeden gecen 2 sonuc.
  Ikisi de HolyGrail'in BIRINCI yilinda zarar azaltma: son-3-yil HGB ve agirlikli HGB.
  Net sonuclar yine zarar: -150,54R'den -48,35R / -41,31R. Karli strateji kesfi degil.
- Kayitli eski modele karsi 176 karsilastirmada her iki blok duzeltmesini gecen: 0.
- Birlesik 440-karsilastirma hassasiyeti JSON'da. Onceki bilinmeyen insan/model
  denemeleri bu duzeltmelerle ortadan kalkmaz. Bootstrap nonstationarity altinda yaklasiktir.
- Skor agirliklari testten once sabitlendi: PnL/secim becerisi, DD, ceyrek istikrari,
  egitim-validation iyimserligi ve bootstrap belirsizligi. Skor P(overfit) degildir.
- Eski modelin egitim iyimserligi bu deneyle adil bicimde yeniden tahmin edilmedi.
  Bu nedenle yeni/eski skor farkini "daha az overfit" garantisi olarak kullanmiyoruz.

## Muhendislik Dogrulamasi

- [x] 352 kayitli modelin tahmini kaynak CSV'lerden yeniden hesaplandi.
- [x] Tum esikler validation'dan tekrar hesaplanip dondurulanlarla eslestirildi.
- [x] Outcome/exit-time kolonlari degistirilince tahminlerin degismedigi dogrulandi.
- [x] 44 son-donem tum-gecmis tahmini R3 ile uyumlu.
- [x] Egitim/calibration zamanlari, agirlik toplamlari, kaynak/model kimlikleri kontrol edildi.
- [x] 436 production dosyasi hash'i degismedi. Model replacement: 0.
- [x] R4/R3/R2/R1 test grubunda 59 test gecti.

Weighted StandardScaler sabit sutunlarda cok kucuk negatif varyans nedeniyle
uyari verdi. 56 kayitta en kucuk deger -5,21e-43; hepsinin olcegi 1 ve tahminleri
sonlu. Gercek NaN/hatali olcek gizlenmedi, bu sayisal durum verification.json'da.
Bir ek uyari dateutil deprecation. Canli derleme veya terminal testi gerektiren
bir EA degisikligi yapilmadi; bu bir pipeline health check degil.

Egitim ~103,5 saniye. Arastirma klasoru ~37,5 MiB; canli audit loguna yazilmadi.
DD kapanmis islemler uzerindedir, floating/EOD hesap drawdown'i degildir.
Sabit trade satirlarini elemek yeni execution state'i tekrar simule etmez.

## Sonraki Arastirma Karari

Tum modelleri kisa gecmise gecirmek veya yeni buyuk ag eklemek icin kanit yok.
Bir sonraki izolasyon deneyi sabit model skorlarini kullanarak esik secimini
incelemeli: kalibrasyon karini tek basina maksimize etmek yerine secim becerisi,
esik komsulugu kararliligi ve daha once sabitlenmis konservatif kurallar.
Bu turdan sonra o kurallari ayni test sonucuna uydurmak yeni bir overfit olur.
Gelecekten veri gelene kadar yeni kurallar da research/shadow olarak kalmali.

## Dosyalar

- `docs/ORB_TrainingAge_R4_Protocol.md`: egitimden once sabitlenmis yontem ve kaynaklar.
- `logs/OrbTrainingAge_R4_20260911/Results.md`: tum kollarin ozetleri.
- `logs/OrbTrainingAge_R4_20260911/evaluation.json`: tam metrikler, blok araliklari ve skorlar.
- `logs/OrbTrainingAge_R4_20260911/models.csv`: 352 modelin siralanabilir sonucu.
- `logs/OrbTrainingAge_R4_20260911/verification.json`: bagimsiz tekrar hesaplama kontrolleri.
- `logs/OrbTrainingAge_R4_20260911/production_integrity.json`: degistirmeme kontrolu.

Literatur baglantisi: [Gu, Kelly, Xiu](https://dachxiu.chicagobooth.edu/download/ML.pdf)
duzenlilestirilmis modelleri kronolojik egitim/validation/test ayrimiyla inceler.
[Bailey ve arkadaslari](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)
tekrarlanan model seciminin backtest yanliligina dikkat ceker. R4 bu ilkelerden
yararlanan bir tani deneyidir; makalelerin bulgularini ORB icin yeniden kanitlamaz.
