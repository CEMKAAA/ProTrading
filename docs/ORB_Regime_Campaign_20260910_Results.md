# ORB Rejim Kampanyasi R1: Sonuclar

## Karar

Kampanya yeniden baslatildi ve uc yillik kronolojik tur tamamlandi.
Rejim bilgisi bazi stratejilere katki sagliyor, fakat bu deney **genel ve
guvenilir bir ML iyilestirmesi veya overfit'in cozuldugu** sonucunu vermiyor.
Canli modeller, EA'lar, sinyal matematigi ve listener'lar degistirilmedi.

Yerel, yani stratejiye ozel model daha umut verici. Farkli stratejileri ortak
modele toplamak bu deneyde daha iyi sonuc vermedi. Bu, rejim hipotezinin yanlis
oldugunun ispati degil; bu veri, model ailesi ve secim protokolunun sonucudur.

## Ne Calistirildi?

- 53 stratejinin tamamlanmis ve SHA-256 ile dogrulanmis bes yillik CSV'si.
- 48.744 kullanilabilir strateji-islem satiri: JP225m 24.371, USDJPYm 24.043,
  USTECm 330. Bunlar bagimsiz piyasa olaylari degil.
- Ortak takvim: 2024, 2025 ve 2026'nin ihrac kesimine kadar olan kismi.
  Kesim broker zaman ekseninde 2026-09-09; sonuclari sinirda belli olmayan
  islemler ve 24 saatlik purge nedeniyle son kisimdaki islemler dislanir.
- 26.129 dis test satiri; tam kesintisiz hesap/PnL simulasyonu degildir.
- Alti sabit aile: rejimsiz/ rejimli yerel Ridge, rejimsiz/ rejimli ortak Ridge,
  ortak kosullu kazanc-zarar modeli ve 16 noronlu ortak MLP.
- Toplam 642 uygun model egitildi. Yetersiz ornekli aileler atlanip kayda alindi.
- Rejim girdileri: mevcut alti sinif, yas, gecis guveni, pending durumu,
  trend/volatilite derinligi, RF01-RF12 ve onceden belirlenmis alti etkilesim.
- R geometrisi degismedi. SL/ATR, TP/SL ve spread/SL gibi giriste bilinen
  olcekler kullanildi. Cikis, net R, maliyet sonucu, MFE/MAE ve hedef etiketleri
  modele girdi olarak verilmedi; net R egitim hedefidir.

## Overfit Kontrolleri

Her test yili Y icin ilk egitim Y-1 basindan once, esik kalibrasyonu Y-1'in
ilk yarisinda, model secimi ikinci yarisinda yapildi. Secilen aile ilk yari
sonuna kadar yeniden egitildi; ikinci yarida esik yeniden kalibre edildi.
Model ve esik, Y yilinin tahminleri hesaplanmadan once hash ile donduruldu.

Butun stratejiler ayni tarih sinirlarini kullandi. Boylece ayni piyasa gununun
bir varyantinin egitimde, digerinin testte yer almasi onlendi. Etiketi sonraki
bolumun fiyatlarini kullanan islemler 24 saatlik aralikla ayiklandi. Scaler
sadece ilgili egitim bolumunde fit edildi. Ortak egitimde sembol-gun basina
agirlik dengelendi; cok sayida benzer varyant bir gunu gereksizce buyutmedi.

Filtreye izin verilmesi icin on-test kalibrasyon ve secim bolumlerinde:

1. En az 20 islem ve en az %50 koruma orani.
2. Filtresiz toplam R'den iyi sonuc.
3. Ayni aylik islem sayisini tutan rastgele secimin beklenen R'sinden iyi sonuc.

Kosullar saglanmazsa **NO_VETO**, yani mevcut stratejiyi filtrelememe secildi.
Bu alt limitler dogrulama bolumleri icindir; gelecek testte ayni koruma oranini
garanti etmez. Esik, test sonucuna bakilarak ayarlanmadi.

Onemli: Stratejilerin kendileri bu tarihlerin grafikleri uzerinde daha once
gelistirildi. Dolayisiyla yeni kronolojik protokol dogru olsa da bu tarihler
artik tamamen kor bir holdout degil. Onceki arastirma denemeleri de belirsizlige
dahildir; yeni ileri paper test bu kampanyanin yerine gecmez.

## Otomatik Secilen Sistemin Sonucu

Asagidaki tablo, testten ONCE secilen model ailesi ve esigin sonucudur:

| Test | Degerlendirilen | ML secilen | Net R iyilesti | Net R kotulesti | Degismedi |
|---|---:|---:|---:|---:|---:|
| 2024 | 53 | 4 | 2 | 2 | 49 |
| 2025 | 53 | 3 | 2 | 1 | 50 |
| 2026, kismi | 53 | 4 | 1 | 3 | 49 |

Uc test birlikte ele alindiginda 4 stratejide toplam R iyilesti, 6'sinda
kotulesti, 43'unde degismedi. Ayni stratejinin birden fazla yilda secilebilmesi
nedeniyle yillik sayilarin toplami farklidir. Bunlari tek bir fonun toplam
R'si olarak toplamak dogru degildir.

En buyuk sayisal iyilesme `uj_020_inv_holy` icin -289,41R'den -202,45R'ye
geldi. Bu bir kazanan sistem degil: **halen agir zarar ediyor**. Islem sayisi
azalmasi eslestirildiginde katki +19,29R'ye iniyor. Yalnizca +86,96R iyilesme
rakamini sunmak yaniltici olurdu.

## Rejim Gercekten Katki Sagliyor mu?

Bu bolum otomatik seciciden AYRI bir ablation karsilastirmasidir. Ayni egitim
tarihleri, ayni temel model, ayni esik araligi ve ayni test satirlari kullanilip
rejim girdileri var/yok karsilastirildi. Esikler kendi on-test kalibrasyonlarinda
secildi. Sonradan en iyi tabloyu secip production'a tasimadik.

| Aile | Rejimle R daha iyi | Rejimle R daha kotu | Ayni | Aylik eslestirilmis secim katkisi daha iyi |
|---|---:|---:|---:|---:|
| Stratejiye ozel | 14 | 10 | 29 | 13 |
| Ortak model | 1 | 7 | 45 | 1 |

Somut arastirma adaylari:

| Strateji | Rejimsiz ML / rejimli ML R | WR | Kapali islem DD | Islem sayisi |
|---|---:|---:|---:|---:|
| JP2251RSetup (`jp_1r_m15`) | +28,00 / +37,19 | %52,52 / %53,92 | 15,52R / 10,25R | 436 / 408 |
| 0.5RsetupAdvanced (`jp_05_adv`) | +13,78 / +21,65 | %69,48 / %70,96 | 9,39R / 8,00R | 439 / 365 |

Bu tablodaki modeller otomatik secicinin kazananlari degil. Ornegin
`jp_05_adv` icin otomatik secici 2026'da kosullu payoff ailesini secti ve
toplam sonucu kotulestirdi. Dolayisiyla "rejimli aday iyi cikti" ile
"canlida onu zamaninda secebiliyoruz" ayri problemler olarak kaldi.

## Belirsizlik Ve Muhendislik Kontrolleri

- 53 stratejide 50 farkli birebir sonuc serisi var; uc cift ayni seriyi tasiyor.
  Diger seriler de ayni piyasa nedeniyle bagimsiz degil.
- 5 ve 20 takvim gunluk bloklarla 20.000'er ortak bootstrap tekrar yapildi.
  Butun stratejilerde ayni gun bloklari kullanildi.
- Hem filtresize karsi kazanc hem aylik islem sayisi eslestirilmis katkida,
  53 politika icin Bonferroni duzeltmesini iki blok uzunlugunda da gecen
  strateji sayisi **0**. Bu kesin basarisizlik ispati degil; guclu istatistiksel
  genelleme iddiasi icin yeterli kanit yok.
- Bu duzeltme gecmisteki butun denemeleri veya alti aileye sonradan bakarak
  aday secimini temizlemez. Blok bootstrap da degisen rejimlerde yaklasik bir
  tani aracidir, garanti degil.
- 23 kampanya/secim tani testi gecti. Uc yilin checkpoint dosyalari yeniden
  okunup tum kayitli artifact hash'leri dogrulandi.
- 642 modelin scaler'lari sonlu ve pozitiftir; egitim etiket tarihleri ilgili
  sinirlardan once kalir. Sekiz scaler'da sabit `f_regime_valid=1` sutununun
  hesaplanan varyansi kayan nokta yuvarlamasiyla yaklasik -1e-44 cikti.
  Kutuphane sabit sutun icin scale=1 kullandi; tahminler sonlu. Model
  dondurulduktan sonra hicbir scaler/model degistirilmedi.
- 436 production kaynak/binary/listener/aktif model dosyasinin once/sonra
  hash kontrolunde **0 degisiklik** var. Bu kontrol calisan pipeline'in yeni
  bir canli saglik testi degil; bu kampanyanin production'a dokunmadigi kontrolu.
- Arastirma ciktilari yaklasik 8,4 MB; mevcut CSV'ler veya ML setleri silinmedi.

## Bir Sonraki Deney

En makul yeni hipotez, butun stratejilere tek rejim katsayisi dayatmak yerine
**stratejiye ozel rejim etkilerini ortak bir ortalamaya dogru daraltan** bir
modeldir. Az ornekli bir strateji/rejim hucresi tek basina uc bir kural
ogrenmemeli; yeterli veri geldikce kendi etkisini gosterebilmelidir.

Bu R1'deki ortak model stratejiye ozel sabit terimler tasiyor; her stratejiye
ozel tum rejim katsayilarini ogrenmiyor. Yerel ailenin daha iyi ablation
sonuclari bu hipotezi arastirmaya deger kiliyor, kanitlamiyor.

Once yeni ailenin formulu, kucultme gucu ve kabul esigi sinirli bir protokolde
yazilmali. R1'in iyi test satirlarini secerek ayar uretilmemeli. Bundan sonra
stratejiler ve yeni model dondurulup yeni gelen sinyallerde paper-forward
izlenmeli. Canliya tasimadan once veto edilen bir tradenin sonraki sinyal/
pozisyon durumuna etkisi tam EA/listener replay'i ile ayrica kontrol edilmeli.

## Dosyalar

- Plan: `docs/ORB_Regime_Campaign_20260910_Plan.md`
- Literatur temeli: `docs/ORB_ML_Professor_Review_20260910.md`
- Tum stratejiler: `logs/OrbRegimeCampaign_20260910_R1/Results.md`
- Siralanabilir sonuc: `logs/OrbRegimeCampaign_20260910_R1/comparison.csv`
- Rejim, model ve belirsizlik ayrintilari: `logs/OrbRegimeCampaign_20260910_R1/evaluation.json`
- Girdiler ve kaynak hash'leri: `logs/OrbRegimeCampaign_20260910_R1/contract.json`
- Production kontrolu: `logs/OrbRegimeCampaign_20260910_R1/production_integrity.json`
- Yeniden calistirma: `python scripts/orb_regime_campaign.py`
- Rapor: `python scripts/orb_regime_campaign_report.py`

Literaturdeki cikis noktalari: Gu/Kelly/Xiu'nun ortak fiyat ozelliklerinden
yararlanma calismasi, Andrew Lo'nun kosula bagli adaptasyon yaklasimi ve
Bailey ve arkadaslarinin coklu deneme/backtest overfit uyarilari. Bu kaynaklar
bu ORB sonuclarini garanti etmez; metodolojik motivasyon saglar.

[Gu, Kelly, Xiu: Empirical Asset Pricing via Machine Learning](https://dachxiu.chicagobooth.edu/download/ML.pdf)

[Lo: The Adaptive Markets Hypothesis](https://web.mit.edu/Alo/www/Papers/JPM2004_Pub.pdf)

[Bailey et al.: The Probability of Backtest Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)
