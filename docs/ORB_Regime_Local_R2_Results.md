# Stratejiye Ozel Rejim Ogrenimi

## Mevcut Yapi Dogrulamasi

Evet: mevcut uretim kampanyasi her stratejinin kendi CSV'sini okuyup modelini
ayri egitiyor. `scripts/run_orb_ml_training_campaign.py` her `preset_id` icin
ayri dizin kullaniyor ve o CSV'yi `train`/`fit` fonksiyonuna gonderiyor.
`OrbStrategyCampaignModels.mqh` tarafinda sembol, TF, broker, runtime/input
uyumu ve model/dataset hash kontrolleri var.

Dolayisiyla onceki R1 turundaki ortak modeller, canlidaki modellerin ortak
veriyle degistirildigi anlamina gelmiyordu. Onlar arastirma karsilastirmasiydi.

CSV'lerde rejim bilgisi zaten mevcut: alti rejim, rejim yasi, gecis guveni,
pending durumu, trend/volatilite derinligi ve RF etiketi. R2 icin CSV'lere yeni
kolon eklenmedi. Gereken etkilesimler egitim/tahmin tasariminda ayni kuralla
turetildi; mevcut CSV ve model dosyalari degistirilmedi.

## R2'de Ne Yapildi?

53 stratejinin tamaminda modeller **yalnizca kendi stratejisinin verisiyle**
egitildi. A stratejisinin scaler, model veya kalibrasyonu B stratejisinin
satirlarini kullanmadi. Model yanlis strateji/config/dataset ile tahmin
istenirse hata veriyor; otomatik baska modele dusmuyor.

Her strateji icin dort sabit aday:

1. Rejimsiz Ridge referansi.
2. R1'deki mevcut rejimli Ridge referansi.
3. Stratejinin genel modeli + rejime ozel sapmalar, ceza 100.
4. Ayni yapi, rejime ozel sapmalar icin daha guclu ceza 400.

Yeni yapi basitlestirilmis olarak:

```text
beklenen net R = stratejinin genel tahmini
               + aktif rejimin bu stratejiye ozel duzeltmesi

minimize: agirlikli karesel tahmin hatasi
          + 100 * genel katsayilarin kare toplami
          + lambda * rejim sapmalarinin kare toplami
lambda = 100 veya 400
```

Genel intercept penalize edilmiyor. Rejim duzeltmesinde intercept ile sekiz
girdinin etkisi var: yone hizali return5, EMA20-50 farki, SL/ATR, spread/SL,
rejim yasi, gecis guveni, trend derinligi ve volatilite derinligi.

Az ornekli rejimin duzeltmesi, ayni stratejinin genel tahminine dogru
kucultuluyor. Seyrek rejim sutunlari tekrar unit-variance olceklenmiyor;
boylece birkac islemle olusan rejimin etkisi yapay olarak buyutulmuyor.
Egitimde hic gorulmeyen rejimin sapmasi sifir; genel tahmin kullaniliyor.

Bu, cezali regresyon ile partial pooling uygulamasidir. Tam Bayesian
posterior, MCMC veya otomatik ogrenilmis prior varyansi oldugu iddia edilmez.
R2'nin bu hiyerarsik adaylarinda ortak kisim kategorik RF/rejim sutunlarini
kullanmaz; surekli baglami korur. Daha zengin RF kategorileri mevcut rejimli
referansta kaldigi icin karsilastirma yalnizca ceza degisimi degil, onceden
belirlenmis model ailesi karsilastirmasidir.

## Overfit'e Karsi Uygulanan Kontroller

- Kronolojik egitim, kalibrasyon, model secimi ve test; rastgele trade bolmesi yok.
- Tum stratejilerde ayni takvim sinirlari ve 24 saatlik etiket purge araligi.
- Scaler yalnizca egitimde fit edilir. Test sonucu veya gelecekteki net R
  hicbir oz nitelige girmez. Net R yalnizca egitim hedefi ve degerlendirme sonucudur.
- Iki sabit kucultme gucu; gizli yuzlerce ceza, feature veya seed denemesi yok.
- Esik ve model test yilindan once secilir, hash ile dondurulur.
- On-test secimde en az 20 islem, %50 koruma, filtresize gore iyilesme ve
  aylik islem sayisi eslestirilmis rastgele secime gore pozitif katki aranir.
- Kosullar yoksa NO_VETO: mevcut stratejinin sinyalleri aynen korunur.
- Butun adaylar, retler, rejim katsayilari ve rejim basina egitim sayilari kayitli.
- 5 ve 20 takvim gunluk bloklarla 20.000'er bagimli bootstrap tekrari.
- 53 politika ve R1/R2 toplam on aday ailesini hesaba katan 530 karsilastirma
  duyarliligi raporlandi. Bunlar gecmisteki tum insan secimlerini kapsamaz.

Bu kontrollerin calistigindan testlerle emin olabiliriz; **overfit'in kesinlikle
olmadigindan emin oldugumuzu soyleyemeyiz**. Stratejiler gecmiste bu grafikler
uzerinde gelistirildi. R2'nin testleri de daha once incelenmis tarihlerdir.
Yeni mimari dogru bolunse bile eski strateji-secim yanliligi silinmez.

## Sonuclar

48.744 kullanilabilir girdi satiri, 26.129 dis-test satiri, 1.236 uygun model.
Test yillari 2024, 2025 ve 2026'nin ihrac kesimine kadar olan kismi.
Uc yilin toplam sonucu bazinda, testten ONCE secilen modeller:

| Sonuc | Strateji sayisi |
|---|---:|
| Net R iyilesti | 2 |
| Net R kotulesti | 4 |
| Degismedi | 47 |

| Test | Model secilen | R iyilesti | R kotulesti |
|---|---:|---:|---:|
| 2024 | 2 | 1 | 1 |
| 2025 | 3 | 1 | 2 |
| 2026, kismi | 1 | 0 | 1 |

Iki iyilesmenin anlami da sinirli:

- `uj_020_inv_holy`: -289,41R yerine -196,72R. +92,69R iyilesme var ama
  sistem halen cok zarar ediyor. Aylik islem sayisi eslestirmesine gore
  secim katkisi +19,38R. Bunu kazanan sistem diye sunmak yanlis olur.
- `jp_1r_disp`: +28,57R yerine +30,05R; kapali-islem DD 24,71R yerine
  11,59R. Fakat aylik eslestirilmis secim katkisi -0,72R; iyilesmeyi yalnizca
  daha iyi trade secme becerisine baglamak icin kanit yok.

## Aday Rejim Modelleri Karsilastirmasi

Bu tablo yukaridaki otomatik seciciden AYRIDIR. Teste baktiktan sonra iyi
gorunen modeli production'a secmedik. Her aday kendi on-test esigiyle,
her iki adayda da tahmin bulunan ayni satirlarda karsilastirildi.

| Mevcut rejimli modele gore | Daha iyi R | Daha kotu R | Ayni |
|---|---:|---:|---:|
| Yerel rejim sapmasi, ceza 100 | 13 | 9 | 31 |
| Yerel rejim sapmasi, ceza 400 | 12 | 7 | 34 |

Olumlu arastirma ornegi `jp_15_retest`: mevcut rejimli referansta +27,23R,
ceza 100 adayinda +35,06R; WR %47,10 yerine %50,00; kapali-islem DD 14,85R
yerine 12,65R. Islem sayisi 259'dan 190'a iniyor. Bu model o strateji icin
otomatik secicinin onceden sectigi model DEGILDIR; test-sonrasi gozlemdir.

Bazi iyilesmeler ise yararli yeni filtre bulmaktan degil, zararli filtreyi
uygulamamaktan kaynaklaniyor. Ornegin `uj_025_state80`, +11,82R'den
+20,57R'ye donerken 322 yerine tum 367 islemi koruyor. Bu nedenle her pozitif
farki yeni bir alpha olarak adlandirmiyoruz.

Sonuc: rejim duzeltmeleri gercekten stratejiye ozel ogrenildi, fakat **hangi
modelin sonraki donemde ise yarayacagini guvenilir bicimde secme problemi**
cozulmedi. 53 ve 530 duzeltmelerinde, her iki blok uzunlugunda da hem temel
stratejiye hem aylik eslestirmeye karsi anlamli kalan politika sayisi sifir.

## Dogrulama Ve Production

- 39 model/kimlik/zaman siniri/oz nitelik/istatistik testi gecti.
- 1.236 modelin scaler'lari ve etiket tarih sinirlari denetlendi.
- Rejim katsayi kayitlarindaki 256 gorulmemis rejim hucresinde sapma sifir.
  Bunlar farkli yil/asama/aday kombinasyonlari; 256 bagimsiz rejim degil.
- Kampanya tekrar acildi; uc yil yeniden egitilmeden tum checkpoint hash'leri
  dogrulanarak okundu. CSV hash'leri ayni kaldi.
- 436 production kaynak/binary/listener/aktif model dosyasinda 0 degisiklik.
- Yeni arastirma ciktilari yaklasik 13,2 MB. Eski CSV veya modeller silinmedi.
- `.research.joblib` dosyalari EA runtime formati degildir, otomatik yuklenmez.
  Dashboard'taki mevcut ML filtreleri bu turla degistirilmedi.

Kapali-islem R serisi; floating DD, EOD trailing DD veya gercek hesabin
gunluk getiri serisi degildir. DSR/PBO sertifikasi uretilmedi. Ayrica filtre
edilen islemin sonraki sinyal/pozisyon durumuna etkisi frozen CSV alt-kumesi
ile tam yeniden simule edilmez. Canli aday olursa stateful EA/listener replay'i
ve gercekten yeni, dondurulmus paper-forward donemi gerekir.

## Literaturun Uygulamaya Donusumu

Gelman'in hiyerarsik modelleme calismasi, az gozlemli gruplarin tahminlerini
ortak yapiya dogru dengelemenin gerekcesini ve sinirlarini gosterir. Burada
gruplar farkli stratejiler degil, **tek stratejinin farkli rejimleri**.
Bu uygulama bizim uyarlamamizdir; orijinal makale bir trading deneyi degildir.
[Gelman, 2006](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf)

Gu/Kelly/Xiu'nun finansal ML calismasindaki regularization ve zamansal
egitim/validation/test ayrimi metodolojik temeldir. Ayni yontem ailesini
kullanmak onlarin sonuclarinin ORB'ye otomatik aktarildigi anlamina gelmez.
[Gu, Kelly, Xiu, 2020](https://dachxiu.chicagobooth.edu/download/ML.pdf)

Bailey ve arkadaslarinin backtest overfit calismasi, tekrar tekrar aday
secmenin yarattigi yanliliga dikkat ceker. Bu nedenle basarisiz adaylari da
kaydettik, deneme butcesini sinirladik ve eski testleri yeniden kullanmanin
bagimsiz kanit olmadigini acikca belirttik.
[Bailey et al., 2015](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)

## Dosyalar Ve Tamamlanan Isler

Onceden dondurulmus protokol, hash'i bozulmamasi icin sonradan degistirilmedi.
Tamamlanma kaydi burada:

- [x] Mevcut strateji bazli egitim ve rejim oz niteliklerini dogrula.
- [x] Protokolu test sonuclarini gormeden dondur.
- [x] Stratejiye ozel rejim modellerini ve kimlik/sinir testlerini uygula.
- [x] 53 stratejinin tum uygun kronolojik turlarini calistir.
- [x] Belirsizlik, gorulmemis rejim ve production hash kontrollerini tamamla.
- [x] Olumlu ve olumsuz sonuclari, overfit-free iddiasi olmadan raporla.

`docs/ORB_Regime_Local_R2_Protocol.md`: degistirilmeden saklanan protokol.

`logs/OrbRegimeLocal_R2_20260910/Results.md`: tum stratejilerin tablosu.

`logs/OrbRegimeLocal_R2_20260910/evaluation.json`: rejim katsayilari,
ornek sayilari, yillik sonuclar, butun kontroller ve belirsizlik.

`logs/OrbRegimeLocal_R2_20260910/comparison.csv`: siralanabilir sonuc tablosu.

`logs/OrbRegimeLocal_R2_20260910/production_integrity.json`: once/sonra hash kontrolu.
