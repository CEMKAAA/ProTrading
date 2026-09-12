# ORB R7: Kalibrasyon Hipotezi Sonuclari

2026-09-11. Tamamlandi. Arastirma ortami disinda degisiklik yapilmadi.

## Sonuc

**Hipotez kismen desteklendi:** gecmisten ogrenilen aylik olasilik duzeltmesi
modelin fazla kotumserligini azaltti ve son yildaki gerilemenin bir kismini giderdi.
Ancak bunun tum yillarda ve mevcut production modellerine karsi guvenilir bir
ustunluk oldugu kanitlanmadi. Tarihsel terfi ekranini gecen aday **0**.

Kalibrasyon problemini azaltmak ile karlilik problemini cozmek ayni sonuc degil.
Mevcut modeller korundu. Yeni canli filtre, EA, listener veya terminal dosyasi yok.

## Uygulanan Deney

- 22 USDJPY stratejisi; uc kopya olay/getiri cifti cikarilinca 19 farkli seri.
- 09.09.2022-09.09.2026 arasi dort yillik kronolojik test.
- 2018 baslangicli gecmisten egitilmis R6 lojistik ve HGB olasilik modelleri sabit.
- Ayni 50 oz nitelik, ayni sinyaller, ayni net R etiketleri, ayni geometri.
- 176 temel model/yil, 880 model/mudahale/yil sonucu, 2,288 aylik kalibrasyon durumu.
- 19,159 strateji-islem test satiri. Bunlar bagimsiz 19,159 piyasa olayi degil.
- Aylik state/prediction kampanyasi 63.875 saniye; rapor/bootstrap/replay haric.

Guncelleme test basinda ve sonraki ay baslarinda yapildi. Yalnizca son 365 gundeki,
temel modelin egitim bitisinden sonraki ve en az 24 saat once kapanmis setup'lar
kullanildi. Kabul edilenler kadar ML'nin reddettigi setup'lar da kaynak veriden
izlendi. Bu, canli shadow servisi kuruldugu anlamina gelmez.

Test ayinin sonucu ayni ayin kararlarini etkilemez. Sonuc daha sonra kapanip 24
saat gectiginde sonraki ayin duzeltmesine girebilir. Bu nedenle test **prequential**,
yani zamana uygun ardisik ogrenme testidir; dort yil boyunca hic guncellenmeyen
bir model testi olarak sunulmamalidir.

## Bes Mudahale

| Kod | Davranis |
|---|---|
| raw | R6 olasiligi ve egitimdeki kazanc/kayip ortalamalari |
| probability | Gecmis kapanislardan ogrenilen duzenlilestirilmis logit-intercept duzeltmesi |
| magnitude | Gecmis kazanc/kayip ortalamalarinin eski ortalamaya cekilerek guncellenmesi |
| both | Yukaridaki iki duzeltme birlikte |
| regime_both | both + yeterli veri bulunan rejime ozel daha guclu duzenlilestirilmis intercept |

Olasi getiri >=0 karar esigi degistirilmedi. Intercept egimi 1; global duzeltme
aylik durum icinde islemlerin olasilik siralamasini degistirmiyor. Rejim duzeltmesi
rejimler arasi siralamayi degistirebilir. Yetersiz rejim verisinde yerel etki sifir.
Parametreler ve deney kaynak kodlari sonuclar uretilmeden once hash ile sabitlendi.

## Kalibrasyon Gercekten Iyilesti Mi?

Evet, olculen bu boyutta:

| Aile | Ham medyan olasilik yanliligi | Duzeltilmis | Brier hatasi iyilesen strateji |
|---|---:|---:|---:|
| Lojistik | -5.39 yuzde puan | -1.97 yuzde puan | 18/22 |
| HGB | -4.72 yuzde puan | -1.60 yuzde puan | 18/22 |

Degerler dort yillik strateji-bazli tahmin ortalamasi eksi gerceklesen net-pozitif
oran farklarinin medyanidir. Brier dusmesi daha iyi olasilik tahmini demektir;
tek basina daha iyi trade secimi veya pozitif beklenen getiri kaniti degildir.

Yalniz olasilik duzeltmesi islem tutma oranini lojistikte medyan %37.71'den
%58.77'ye, HGB'de %50.37'den %59.51'e cikardi. Bazi farklar daha cok islem
acmaktan kaynaklanabilir; aylik islem-sayisi eslestirme kontrolu bu nedenle var.

## Son Yildaki Bozulmaya Etkisi

Her sayi ilgili yilda filtresize gore daha iyi net R ureten strateji sayisidir.
Yillar takvim yili degil, Eylul 9 baslangicli test donemleridir.

| Aile / mudahale | 2022-23 | 2023-24 | 2024-25 | 2025-26 |
|---|---:|---:|---:|---:|
| Lojistik ham | 22 | 19 | 7 | 4 |
| Lojistik olasilik duzeltmesi | 19 | 15 | 11 | 8 |
| HGB ham | 21 | 19 | 8 | 4 |
| HGB olasilik duzeltmesi | 18 | 17 | 11 | 9 |

**Son iki yil toparlaniyor, ilk iki yilda bedeli var.** Son yil ham modele gore
lojistikte 17/22, HGB'de 14/22 sonuc iyilesti. Bu sayilar filtresize gore 8/22 ve
9/22 ile karistirilmamali: zaten kotu bir modeli iyilestirmek, filtresize ustunluk
anlamina gelmez.

Dort yillik toplamda lojistik `both` ve `regime_both`, 18/22 stratejide filtresizden
daha iyi; ham lojistikte 16/22 idi. Rejim eklemek evrensel kazanim saglamadi:
HGB `both` ham modelden 14/22 kez iyi iken `regime_both` 11/22 kez iyi.

## Ornekler Ve Karsi Ornekler

Asagida mevcut model karsilastirmalari yalnizca son yilin bilgi-zamani uygun
ortak satirlarinda yapilmistir. DD kapali islem net R drawdown'idir.

| Strateji / aday | Mevcut model R | R7 R | Mevcut DD | R7 DD |
|---|---:|---:|---:|---:|
| 1RYildiz / lojistik probability | +6.34 | +11.67 | 7.33 | 6.13 |
| HighfreqHighWRusdjpyV2 / HGB probability | +4.13 | +7.41 | 3.79 | 2.45 |
| ProUsdJpySetup / lojistik probability | +16.43 | +17.66 | 4.26 | 5.06 |
| 0.5RGoodUsdjpy / HGB probability | +4.22 | +7.07 | 6.56 | 11.50 |

Olumlu ornekler korunuyor, ama zayif taraflar da kayitli:

- 1RYildiz'in duzeltilmis dort yillik toplami +6.11R; ham R6 +0.07R. Yillik
  netler +3.74, -6.15, -3.15, +11.67R. Dordunde de karli degil; toplam islem
  tutma orani %31.24, onceden koyulan %40 esigini de saglamiyor.
- HighfreqHighWRusdjpyV2 son yil iyi olmasina ragmen dort yillik R7 toplam -2.31R.
- ProUsdJpySetup'ta son yil kar artsa da DD kotulesiyor. Dort yillik ham lojistik
  +22.49R iken yalniz olasilik duzeltmesi +3.97R'ye dusuyor.
- 0.5RGoodUsdjpy son yil toparlaniyor, fakat dort yilda ham HGB +13.72R'den
  +8.22R'ye geriliyor. Son yil basarisini secip eski yillari gormezden gelmedim.

R7 modelleri testten sonra stratejiye ozel secilip mevcut modellerin yerine konulmadi.

## Rejim Teshisi

Ayrica onceki kalibrasyon yili ile sonraki test yilinin ortalama net R farkini
iki hesap kalemine ayirdim: rejimlerin gorulme agirliklarinin degismesi ve ayni
rejim icindeki ortalama sonucun degismesi. Bu bir muhasebesel ayrisimdir, nedensellik
ispati degil. Net R ve net-pozitif oran icin farklar tam olarak uzlasiyor.

Onemli sinir: 2025-26 testinde rejim 3, onceki kalibrasyon yilinda yoktu.
Gorulmemis rejime gecmis global ortalamayi atayarak hesaplamak yaniltici olabilecegi
icin, ayrica sadece iki donemde de bulunan rejimlerde ayrisim yaptim.

Son yilda bu ortak rejimler test islemlerinin medyan %89.15'ini kapsiyor. Bu
sinirli kapsamda 19 farkli serinin 13'unde rejim-ici degisim kaleminin mutlak
buyuklugu, rejim agirligi degisimininkinden buyuk. Diger yaklasik %10.85'lik yeni
rejim kapsami bu karsilastirmaya dahil degil; bilinmeyeni biliniyormus gibi sunmadim.

Bu sonuc, sadece alti rejim etiketinin gorulme sikligini duzeltmenin yeterli
olmadigina dair bir ipucu. Ayni bucket icinde de davranis degisiyor. Ancak
"rejim ici degisim neden oldu" sorusunu tek basina cevaplamiyor; ayni stratejilerin
insan tarafindan secilmis olmasi ve ortak piyasa olaylari da sinirlar arasinda.

## Neden Production'a Alinmadi?

176 aday karsilastirmasi icin aile-bazli, 704 icin ortak Bonferroni duyarlilik
hesaplandi. 5/20 gunluk takvim bloklariyla 20,000 esli bootstrap tekrari kullanildi.

- Ham R6 modeline karsi duzeltilmis anlamlilik kosulunu gecen: 0.
- Aylik sayi-eslestirilmis secim katkisi kosulunu gecen: 0.
- Kayitli mevcut modele karsi duzeltilmis kosulu gecen: 0.
- Tum onceden belirlenmis tarihsel kosullari saglayan: 0.

Yalnizca HolyGrail'deki buyuk zararin azalmasi, filtresize gore net fayda kontrolunu
geciyor; o stratejide zarar azaltmak yine karlilik ispatlamiyor. Bootstrap drift
altinda yaklasiktir. Onceki insan/model aramalarini bu duzeltmeler silemez.

## Dogrulama

- [x] 2,288 aylik durum kaynak veriden yeniden kuruldu.
- [x] Intercept'ler farkli sayisal cozumcu (Brent) ile dogrulandi.
- [x] Henuz kullanilamaz sonuclari degistirmek ayni ayin durumunu degistirmedi.
- [x] Gelecek sonuc kolonlari mevcut tahmin/karari degistirmedi.
- [x] 880 karar maskesi ve sonuclari yeniden hesaplandi.
- [x] 176 ham referans R6 tahmin/kararlarina eslesti.
- [x] Kayitli model karsilastirmalarinin bilgi-zamani sinirlari kontrol edildi.
- [x] Izlenen 436 production dosyasinin hash'i ayni.
- [ ] Pozisyon-state execution replay ve yeni ileri donem shadow yapilmadi.

Ana test grubu ve dort rejim-ayrisim testi birlikte **89 test gecti**.
R4'ten bilinen sabit sutun roundoff ve dateutil deprecation uyarilari disinda
ana test grubunda hata yok. Test verisinin ileri zaman mutasyonunda int32 tasmasi
goruldu; deney dondurulmadan once test timestamp'i int64'e alindi.

Dondurulmus rapor modulunun CLI bolumunde eksik `Path` import'u vardi. Hesaplama
fonksiyonu degismedi; yeni `run_orb_calibration_r7_report.py` girisi eklendi. Ilk
rapor uretimi bu girisle yapildi. Egitim, parametre, sonuc veya frozen hash'ler
degistirilmedi. Bu not, tekrarlanabilirligi ve hata kaydini korumak icindir.

## Sonraki Karar

Olumsuzlugu "daha buyuk ag lazim" diye yorumlamiyorum. Kucuk kalibrasyon katmani
gorevini kismen yapiyor; kalan problem karar esigine yakin islemlerde ekonomik
secim gucu ve rejim-ici degisimin zamaninda taninmasi.

Siradaki deneyden once sabitlenmesi gereken soru: ayni rejim icindeki kotulesme
yalnizca gecmis kapanislardan saptanabiliyor mu, yoksa ancak sonuc ortaya ciktiktan
sonra mi gorunuyor? Buna karar vermeden yeni gecmis esikleri taramak veya R7'yi
canliya almak uygun degil. Bu turde ek bir esik aramasi yapilmadi.

## Dosyalar

```text
python scripts/orb_calibration_r7.py
python scripts/run_orb_calibration_r7_report.py
python scripts/verify_orb_calibration_r7.py
python scripts/orb_calibration_r7_diagnostics.py
```

Protokol: `docs/ORB_Calibration_R7_Protocol.md`.
Tam karsilastirmalar: `logs/OrbCalibration_R7_20260911/evaluation.json`.
Ozet: `logs/OrbCalibration_R7_20260911/Results.md` ve `models.csv`.
Rejim ayrisimi, kalibrasyon ve eklenen/elenen islem katkisi: `diagnostics.json`.
Kaynak replay: `verification.json`; production kontrolu: `production_integrity.json`.
Her strateji/yil altinda `states.json`, `predictions.csv`, `result.json` ve hash'ler.

Kaynaklar ve sabit parametreler protokolde. Bu rapor bir overfit-free garantisi,
canli pipeline health check'i veya kurum adina arastirma iddiasi degildir.
