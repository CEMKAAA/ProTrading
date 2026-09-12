# Mevcut Modeller Ve R7: Kapsamli Karsilastirma

2026-09-12. USDJPY + yeni JP225 kampanyasi. Canli modele dokunulmadi.

## Karar Ozeti

R7 topluca daha iyi bir model nesli degil. Olasilik kalibrasyonu bazi eski
modellerin fazla islem engellemesini azaltiyor; bazi stratejilerde ise daha iyi
islem secimi sagliyor. Fakat tum ailelerde mevcut modele gore medyan PnL farki
negatif. Mevcut iyi modelleri topluca degistirmek bu veriye gore yanlis olur.

**Arastirmada sonraki onceligim mevcut sampiyon modelin kendisini kalibre etmek.**
R7, kayitli MLP/RIDGE/HGB modeline bir duzeltme eklemiyor; farkli egitilmis R6
lojistik/HGB modellerini kalibre ediyor. Hem temel modeli hem duzeltmeyi ayni
anda degistirmek, eski modelin iyi ogrendigi siralamayi kaybettirebilir. Bu
aciklama bir hipotezdir; asagida ayristirici deney onerisi var.

## Adil Karsilastirma

- Kayitli mevcut model: dosya hash'i ve strateji/ayar kimligi dogrulanmis artifact. Canli chartta ML'nin acik olduguna dair kontrol yapilmadi.
- 22 USDJPY + 27 JP225 = 49 kayitli strateji; her biri icin sekiz sabit R7 adayi, toplam 392 eslenik karsilastirma.
- Uc USDJPY kopya seri nedeniyle 49 bagimsiz piyasa deneyi yok; 46 farkli olay/getiri serisi var.
- Ortak donem 09.09.2025-09.09.2026; her mevcut modelin son egitim/secim bilgisinden sonraki 24 saat de dislaniyor.
- Mevcut modellerin egitimde gordugu eski yillari onlara test diye sunmadik.
- R7 eski model surumlerinin ayrica dort USDJPY, bir/iki uygun JP225 test yili var.
- Yeni JP225 forward refit'lerinin sonraki testi yok; asagidaki sonuclar onlara atfedilemez.
- Tum adaylar, kotu ornekler dahil, ayrintili raporda var. Son yilin kazananini gizlice production modeli secen bir kural yok.

Her aday icin net R, kapali islem DD, WR, islem sayisi, ortalama R, profit factor,
dort ceyrek katkisi, eklenen/cikarilan kararlar, ek maliyet duyarliligi ve
belirsizlik araliklari hesaplandi. Portfoy olusturup korelasyonlu stratejilerin
R'lerini toplamadik. WR, net R > 0 olan kapanis oranidir; yalniz TP hit orani degil.

## Ailelerin Genel Sonucu

"Yeni ustun" PnL azalmadan DD'nin artmamasi ve en az birinin iyilesmesi demek.
Bu betimleyici bir sonuc, kanitlanmis alpha demek degil.

| Varlik | Aday | PnL iyilesen | Yeni PnL-DD ustun | Medyan fark |
|---|---|---:|---:|---:|
| USDJPY | Lojistik / olasilik | 11/22 | 9/22 | -0,39R |
| USDJPY | HGB / olasilik | 9/22 | 8/22 | -1,39R |
| USDJPY | Lojistik / rejim birlikte | 9/22 | 9/22 | -1,06R |
| USDJPY | HGB / rejim birlikte | 9/22 | 6/22 | -0,93R |
| JP225 | Lojistik / olasilik | 10/27 | 7/27 | -1,01R |
| JP225 | HGB / olasilik | 12/27 | 6/27 | -1,75R |
| JP225 | Lojistik / rejim birlikte | 9/27 | 6/27 | -1,17R |
| JP225 | HGB / rejim birlikte | 6/27 | 4/27 | -2,27R |

Rejim katmaninin eklenmesi otomatik iyilesme degil. Daha karmasik duzeltme daha
az veriyle daha fazla parametre ogreniyor; kullandigimiz guclu duzenlilestirme
bile her stratejide yeterli olmadigi gibi, fayda yaratmasi da zorunlu degil.

## Incelemeye Deger Ornekler

Bu tablo sonuclari gordukten sonra secilmis orneklerdir. Onceden belirlenmis bir
production secicisi veya bagimsiz testte onaylanmis kazananlar listesi degildir.

| Strateji / aday | Mevcut R -> R7 R | DD R | Islem | WR |
|---|---:|---:|---:|---:|
| jp2250.5RSetupV2 / lojistik olasilik | +9,54 -> +18,91 | 7,15 -> 4,00 | 130 -> 191 | %71,54 -> %73,30 |
| JP225DISP_ON_IBM1_SETUP_Edge / HGB birlikte | +5,79 -> +12,59 | 4,00 -> 3,50 | 87 -> 88 | %71,26 -> %76,14 |
| 4Kaybetmeden4KazanmaChallengeModeli / HGB buyukluk | +7,22 -> +13,97 | 14,03 -> 7,30 | 181 -> 160 | %51,93 -> %54,37 |
| 1RYildiz / lojistik olasilik | +6,34 -> +11,67 | 7,33 -> 6,13 | 76 -> 47 | %55,26 -> %63,83 |

### V2: Fazla Engellemeyi Azaltma

Yeni model eskisinin actigi 130 islemin tamamini tutuyor, 61 ek islem aciyor.
Bu ek islemler +9,37275R uretiyor. Fark dort ceyregin dordunde de pozitif.
Islem basina varsayimsal ekstra 0,05R maliyetten sonra fark hala +6,32275R.

Ancak filtresiz strateji bu yil +23,24225R: R7 eskiden iyi, filtresizden kotu.
Bir onceki yilda R7 +8,76975R ve filtresize gore +18,62075R iyilesme sagliyor.
Bu, kotu donemde koruma / iyi donemde firsat maliyeti dengesini incelemek icin
iyi bir ornek; sadece en yuksek son-yil R'ye bakarak karar verilmemeli.

### DISP: Islem Sayisi Degil Secim Farki

Mevcutla 64 ortak islem var; 24 yeni islem +3,25R ekliyor, 23 eski islem
-3,5525R zarar verdigi icin bunlarin cikarilmasi da yardimci oluyor. Toplam fark
+6,8025R; islem sayisi yalnizca bir artiyor. Aylik sayi-eslestirilmis secim
katkisi farki +6,91476R. Dort ceyregin ucunde iyilesme var.

Iki tarihsel testte R7 +1,05375R ve +12,59075R; filtresize gore her iki yil da
iyilesme var (+6,9055R ve +3,0775R). Bu, V2'nin daha cok trade acma etkisinden
farkli bir mekanizma icin aday. Iki yil hala kisa, ayni piyasa olaylari tekrarli.

### Yalniz Son Yila Bakmama

`1RYildiz` lojistik olasilik kolunun onceki iki test yilinda -6,15R ve -3,15R
sonuclari var. `4Kaybetmeden4KazanmaChallengeModeli` son yil mevcut ML'den iyi
olsa da filtresize gore iki test yilinda da net R kaybettiriyor. Bunlari
"her kosulda winner model" diye adlandirmak yanlis olur.

## Eski Modeli Koruma Ornekleri

Asagidaki R7 araligi sekiz adayin en dusuk ve en yuksek net R'sidir; en yuksek
deger sonuclar goruldukten sonra secildiginden iyimser bir karsilastirmadir.

| Strateji | Mevcut net R | Sekiz R7 adayinin araligi |
|---|---:|---:|
| JP2251RSetup | +21,14 | +3,84 ... +20,13 |
| jp225Use8000pips | +20,07 | +15,52 ... +19,87 |
| jp225VeryHighWRWithGateState | +9,44 | +3,14 ... +6,37 |
| jp2250.5RHighFrequencyIfYouDontWannaWait | +28,75 | +11,00 ... +25,50 |

Bir aday DD'yi azaltabilir; bu tablo yalnizca karlilik gerekcesiyle otomatik
degisimin yanlis oldugunu gosteriyor. Eski +28,00R -> +37,19R JP2251RSetup
ornegiyle bu +21,14R carpistirilmamali: ayni tarih/ortak satir/model surumu
olmadan bu fark model gerilemesi diye yorumlanamaz.

## Belirsizlik Ve Overfitting

5 ve 20 takvim gunluk eslenik blok bootstrap, 20.000 tekrar, islemsiz gunler ve
adaylar arasinda ortak yeniden ornekleme kullanildi. Iki metrik: net R farki
ve ay icinde tutulan islem sayisina gore eslestirilmis secim katkisi farki.
USDJPY aile sayisi 176, JP225 240; iki metrik birlikte 832 test duyarliligi de var.

Her iki blok uzunlugunda aile duzeltmesi sonrasi mevcut modele karsi anlamli
ustunluk gosteren aday sayisi **0**. V2'nin duzeltilmemis %95 net fark araligi
[-1,20R; +19,85R], DISP'in [-1,48R; +15,50R]. Sifiri iceren bu araliklar,
guzel nokta tahminlerinin tek basina guvence olmadigini gosteriyor.

Bu "hic edge yok" kaniti degil; su anki orneklemle net ayristiramiyoruz.
Coklu test cezasi onceki sayisiz arastirmayi unutturmaz. Bu tarih artik daha
once gorulmus veridir. Yeni JP225'nin ayni USDJPY parametreleriyle transferi
faydali bir dis-domain sinama ama oradaki stratejiler de bu gecmisten secilmisti.

Kalibrasyon ile karar basarisini ayirmak icin referans:
[Guo et al., On Calibration of Modern Neural Networks](https://proceedings.mlr.press/v70/guo17a.html).
Tekrarli backtest seciminin riski icin:
[Bailey et al., The Probability of Backtest Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf).
Bu kampanyada bu makaledeki PBO olcusu hesaplandi iddiasi yok; uygulanan yontem
yukarida aciklanan kronolojik test ve blok bootstrap'tir.

## Siradaki Arastirma

1. Mevcut sampiyonlari sabitle. Aday uretimini son-yil kazananina gore dallandirmadan once yeni protokol yaz. Egitim verisine hic dokunmayan canli golge tahmin donemi baslatilabilir; su anda baslatilmadi.
2. Ayni temel model uzerinde yalniz kalibrasyon deneyi yap. Mevcut sampiyonlarin zaman-sirali out-of-fold tahminlerini uret veya kayitli olanlari kullan; egitim-ici tahminleri kalibrasyon diye verme. Eski model, ayni model+global kalibrasyon, ayni model+duzenlilestirilmis rejim kalibrasyonu seklinde az sayida kol tut.
3. Olasilik kaymasi ile siralama bozulmasini ayir. Once kalibrasyon yanliligi/Brier, sonra aylik sayi-eslestirilmis secim degeri ve skor dilimi getirileri. Siralama bozulmussa intercept duzeltmesinin onu kurtarmasini bekleme.
4. Iki mekanizmayi ayri izle: V2'de daha cok islem kabul etme, DISP'te benzer sayida daha iyi islem secme. Rejim yas/transition gibi ek oz nitelikleri birer hipotez olarak az sayida, gecmis ic-fold'larda sinale; sonuc yilina gore esik uydurma.
5. R7'nin ek faydasini yalniz toplam R ile degil DD, islem sayisi, kotu ceyrek, ek maliyet ve belirsizlikle birlikte raporla. Tek bir agirlikli skorun guzel gorunmesi kanit degil; tum tradeoff'lar gorunsun.
6. Terfiden once stateful EA/listener replay yap: reddedilen giris sonraki sinyali, ters-kapatmayi, gunluk limiti veya pozisyon sahipligini degistiriyor mu? Ardindan yeni ileri donuk veride, her strateji/model kimligi sabit golge test ve portable model sayisal esdegerlik testi. Offline CSV maskeleme bunlarin yerine gecmez.

Bu oneriler henuz uygulanmis bir R8 kampanyasi degildir. Kullanici onayi olmadan
canli model, filtre secimi veya publish davranisi degismeyecek.

## Dosyalar Ve Dogrulama

- Tum 49 strateji x 8 aday: `logs/OrbIncumbentComparison_20260912/FullComparison.md`.
- Sayisal tam kayit, yillik/ceyreklik farklar ve ek maliyetler: `logs/OrbIncumbentComparison_20260912/comparison.json`.
- Tablo: `logs/OrbIncumbentComparison_20260912/all_comparisons.csv`.
- JP225 egitim ozeti: `docs/ORB_JP225_R7_Results.md`.
- Tekrar calistirma: `scripts/compare_orb_incumbents_r7.py`.
- 95 test gecti; bagimsiz JP225 verifier 170 modeli yeniden egitti, 550 maskeyi ve 1.430 durumu dogruladi.
- 436 izlenen production dosyasi degismedi. EA, listener, sinyal matematigi, aktif model dosyasi veya terminale deployment yok.
- Bu turda tick/execution replay veya canli shadow yapilmadi. Closed-trade DD challenge'in EOD/floating drawdown'i degildir.
