# ORB Veto R5: Skor, Esik Ve Rejim Guvenilirligi

2026-09-11. Research tamamlandi. Canli model, EA, listener veya registry degisikligi: 0.
Bu rapor yeni akademik bulus veya overfit olmadiginin ispati degildir.

## Ne Yapildi

- 22 USDJPY stratejisinde R4'un tum-gecmis Ridge/HGB modelleri sabit tutuldu.
- Iki test yili: Eylul 2024-Eylul 2025, Eylul 2025-Eylul 2026.
- 88 model/donem cifti; model agirliklari yeniden egitilmedi.
- Validation yili ilk alti ay kesif, ikinci alti ay teyit olarak ayrildi.
- Tarih sinirlarinda 24 saat purge ve siniri asan etiketlerin dislanmasi korundu.
- Esikler/kurallar testten once donduruldu, testte yeniden secilmedi.
- Dort politika: sabit sifir, kararli esik bolgesi, belirgin kotu alt %20,
  rejim destekli kotu alt %20. Toplam 352 politika/donem sonucu.
- Ayrica model skorunu kullanmayan rejim-only kontrolu: 88 kayit. Iki modelde
  ayni kontrol oldugu dogrulandi; bunlar 88 bagimsiz model basarisi degil.

Eski test yillari onceki arastirmalarda goruldu. Sonuclar saf holdout degil.
2018 baslangicli export birlesiminde Eylul 2021'de alti gunluk bosluk var.
Tarihler kaynak broker ekseninde, veri uydurulmadan kullanildi.

## En Onemli Bulgu

Sorun yalnizca karar esigi degil. Bu dondurulmus getiri modellerinde skorun islemleri
iyi-kotu siralama becerisi donemler arasinda zayif ve kararsiz.

Olumlu siralama: skor/getiri Spearman >0 VE en yuksek/dusuk skor grubunun ortalama
net R farki >0. Skor grubu sinirlari sadece ilk validation yarisindan belirlenir.

| Model | Test baslangici | Ilk validation olumlu | Ikinci validation olumlu | Ikisi de olumlu | Bunlardan testte olumlu |
|---|---:|---:|---:|---:|---:|
| Ridge | 2024 | 5/22 | 7/22 | 2/22 | 0/2 |
| Ridge | 2025 | 11/22 | 4/22 | 1/22 | 1/1 |
| HGB | 2024 | 5/22 | 12/22 | 1/22 | 0/1 |
| HGB | 2025 | 9/22 | 11/22 | 2/22 | 1/2 |

Toplamda 88 ciftin 6'si iki validation yarisini gecti; 2'si sonraki yilda da
olumlu siralamayi korudu. Ornek kucuk; bu oran gelecekteki basari olasiligi degil.
Eksik skor grubu nedeniyle yapay red olusmadi: bu kampanyada ust-alt ortalama
farki discovery/confirmation/test profillerinin hicbirinde missing degildi.

Bu sonuc **mevcut kayitli canli modellerin tamaminda beceri yok** demek degildir.
Incelenen modeller R4'un ALL-history return challenger'lari. Kayitli modellerle
yalnizca son-yil ortak satirlarinda ekonomik karsilastirma yapildi.

## Politikalar

### Sabit Esik

Sifirin altindaki tahmini net R'yi veto eden mekanik kural, 88 model/donem
ciftinin 21'inde filtresize gore PnL'yi iyilestirdi, 67'sinde kotulestirdi.
Bu nedenle R4'teki bazi olumlu sabit-esik orneklerini genellestirmiyoruz.

### Kararli Esik Bolgesi

88 ciftin 9'unda discovery'de olumlu uc komsu esik bulundu. Teyit ve siralama
kontrollerini birlikte gecen 1 aday vardi: usdjpyOrbGM0Edge, HGB, ikinci test.

- Filtresiz test sonucu: +10,88R.
- Onceden secilen plateau sonucu: -0,56R.
- DD: 5,50R -> 5,10R; kucuk DD azalmasi buyuk PnL kaybini hakli cikarmiyor.

Bu, komsu esiklerin iyi olmasinin tek basina donemler arasi kararlilik garantisi
vermedigine somut ornek. Testi gordukten sonra esik degistirilmedi.

### Belirgin Kotu Alt Grup

Alt %20 grubunun negatifligine dair discovery destegi 10 ciftte, confirmation
destegi 3 ciftte, ikisi birlikte yalnizca 1 ciftte vardi. O cift siralama kontrolunu
gecemedi. Sonuc: aktif bad_tail adayi 0. Bu, sadece yazilim filtresinin kapali
kalmasi degil, kayitli kanit kurallarinin dogal sonucu.

### Rejim Destekli Alt Grup

Iki validation yarisinda ayni rejim alt-grubu icin gerekli destek/bound kosullarini
gecen yok. Aktif regime_tail adayi 0. Az ornekleri oldugundan daha guvenli gostermek
icin minimum destek veya belirsizlik kosullari sonradan gevsetilmedi.

Bu deney mevcut alt%20 grubunu rejimlere ayirdi; yeni indikator veya rejim
matematigi olusturmadi. Sabit prior mass=20 bir regularization tercihidir, fitted
Bayesian posterior veya gercek zarar olasiligi degildir.

### Rejim-Only Kontrolu

Sadece HolyGrail [USDJPY] icin iki yilda da bir miktar zarar azaltildi:

- Birinci yil: -150,54R -> -123,50R.
- Ikinci yil: -81,37R -> -77,55R.

Hala zararli. Bu sinirli iyilesmeyi ML'nin buldugu alpha diye sunmuyoruz.
Iki model ailesinde ayni kontrol ayni sonucu verdi, bagimsiz iki bulgu degil.

## Eski Modele Gore Olumlu Gorunen Ama Genellenmeyen Ornekler

Asagidaki tablo son yilda mevcut modelin bilgi donemi sonrasindaki ortak
satirlari kullanir. Bunlar test sonrasi gozlemler, onceden secilmis canli portfoy degil.

| Strateji / aday | Eski PnL | Aday PnL | Eski DD | Aday DD |
|---|---:|---:|---:|---:|
| 0.5RGoodUsdjpy / HGB sabit 0 | +4,22R | +9,96R | 6,56R | 4,00R |
| goodPractice / Ridge sabit 0 | -0,36R | +0,81R | 5,25R | 1,60R |
| usdjpyGateStateOn / HGB sabit 0 | +5,10R | +9,05R | 3,99R | 1,75R |

Onceki yila bakinca tablo degisiyor:

- 0.5RGoodUsdjpy: filtresiz +2,32R, HGB sabit 0 ile -2,35R.
- usdjpyGateStateOn: filtresiz +6,57R, HGB sabit 0 ile -2,00R.

Onceki yil kayitli eski modeli test etmiyoruz; o model o donemden egitim bilgisi
almis olabilir. Yukaridaki onceki-yil referansi FILTRESIZ stratejidir.
Bu ayrim korunmadan bir modelin iki yil boyunca eskiyi gectigi soylenemez.

## Belirsizlik Ve Production Karari

- Her yil ortak takvim gunleriyle 5/20 gunluk blok-bootstrap, 20.000 tekrar.
- Gain ve aylik islem-sayisiyla eslesmis secim becerisinde birlikte coklu-test
  duzeltmesini gecen yeni politika: 0.
- Mevcut model karsilastirmasinda duzeltmeyi gecen: 0.
- 352/176 karsilastirma aileleri ve birlesik 1.232 hassasiyeti JSON'da.
- Rejim-only karsilastirmasi tanisal; gelecekteki bagimsiz kanit yerine gecmez.
- Skor PnL/DD, ceyrek oynakligi, kesif-teyit farki ve belirsizligi icerir.
  P(overfit) olarak yorumlanamaz, eski modelin bilinmeyen iyimserligi sifir sayilmaz.
- Mevcut modellerin hicbiri kaldirilmadi veya degistirilmedi.

## Dogrulama

- [x] R5 protokolu ve kod hash'leri hesaplamadan once donduruldu.
- [x] 88 model/donem icin politikalar orijinal CSV'lerden yeniden uretildi.
- [x] 352 karar maskesi ve 88 rejim kontrolu yeniden hesaplanip eslestirildi.
- [x] Gelecek net R/exit kolonlarini degistirmek tahmin veya karari degistirmiyor.
- [x] Eski model yalnizca uygun son-yil ortak satirlarinda karsilastirildi.
- [x] Rejim-only kontrolu model ailesinden bagimsiz ayni sonucu veriyor.
- [x] R5/R4/R3/R2/R1 test grubunda 67 test gecti.
- [x] 436 production dosyasi hash'i degismedi.
- [ ] Stateful execution replay yapilmadi: terfi adayi onaylanmadi.
- [ ] Yeni prospective shadow testi yapilmadi: mevcut terminal akisina dokunulmadi.

R4 testlerinden bilinen sabit sutun roundoff uyarisinin ve dateutil deprecation
uyarisinin disinda hata yok. R5 yeni egitim yapmadi. Bunlar execution testi degil.
Model skorunun kaynak veriden tekrar hesaplanmasi ile gercek pozisyon-state replay
birbirinden farkli kontrollerdir. DD kapanmis trade R'sidir; floating/EOD limit degil.

## Arastirma Karari

Bu sonuclar uzerine daha cok esik veya rejim istisnasi denemek dogru sonraki adim
degil. Kontrollu siradaki soru: maliyet-sonrasi net R regresyonu mu, yoksa mevcut
modellerdeki gibi siniflandirma + gercek kazanc/kayip buyukluklerini ayri ele almak mi
daha kararli siralama veriyor? Ayni oz nitelikler ve ayni kronolojik kisimlarla
hedef/kayip fonksiyonunu izole etmek gerekir; testte iyi gorunen stratejiye ozel
hedef secilmemeli. Bunun icin yeni bir deney onceden sabitlenmeli.

Sonraki bir aday tarihsel kontrolleri gecerse once pozisyon-state replay,
ardindan canli emirsiz shadow takip gerekir. Eski test donemlerini tekrar tekrar
kullanarak kusursuz bir model ispatlanamaz.

## Dosyalar Ve Referanslar

- `docs/ORB_Veto_R5_Protocol.md`: dondurulmus deney tasarimi.
- `logs/OrbVeto_R5_20260911/Results.md`: tam ozet tablolar.
- `logs/OrbVeto_R5_20260911/evaluation.json`: skor profilleri, rejim adetleri, belirsizlik.
- `logs/OrbVeto_R5_20260911/policies.csv`: 440 politika/kontrol sonucu.
- `logs/OrbVeto_R5_20260911/verification.json`: bagimsiz kaynak-veri tekrar kontrolu.
- `logs/OrbVeto_R5_20260911/production_integrity.json`: production degistirmeme kontrolu.

[Gu/Kelly/Xiu](https://dachxiu.chicagobooth.edu/download/ML.pdf),
[Bailey ve arkadaslari](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf),
[Gelman](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf).
Yontemsel referanslardir; bu trading sistemi icin kanitlanmis kar iddiasi degil.
