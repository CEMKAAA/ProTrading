# ORB R6: Olasilik Ve Kazanc/Kayip Buyuklugu Deneyi

2026-09-11. Tamamlanmis arastirma; production degisikligi yok.

## Karar

Hedef degiskenini net R regresyonundan kazanma olasiligina ayirmak, dort yillik
toplamlarda daha fazla stratejinin sonucunu iyilestirdi. Fakat bu iyilesme son test
yilina tutarli tasinmadi. Onceden belirlenen tarihsel yeterlilik ekranini gecen
aday **0**; mevcut kayitli modeli istatistiksel olarak gecen aday **0**.
Canli modeller, sinyal matematikleri ve listenerlar degistirilmedi.

Bu, yeni yaklasimin tamamen faydasiz oldugunu degil, production icin kendini
henuz kanitlamadigini soyluyor. Overfit olmadigi garanti edilen bir model yok.

## Tamamlanan Deney

- 22 USDJPY stratejisi, stratejiye ozel egitim; ayni mevcut 50 oz nitelik.
- Egitim verisi 2018 baslangicli; ilk fold yaklasik 3.7, son fold 6.7 yil egitim.
- Testler 09.09.2022-09.09.2023, 09.09.2023-09.09.2024,
  09.09.2024-09.09.2025 ve 09.09.2025-09.09.2026.
- Her testten once bir yillik kalibrasyon, iki kronolojik yari; sinirlarda 24 saat
  sonuc/label ayrimi. Test sonuclari egitim veya esik secimine verilmedi.
- 352 model paketi, 704 model/politika/yil sonucu; 19,159 strateji-islem test satiri.
- 22 stratejide uc cift ayni olay/getiri serisini paylasiyor: 19 farkli seri.
  Bunlar bile birbirinden bagimsiz piyasa deneyleri degil.
- Egitim/kayit asamasi 117.98 saniye. Bootstrap ve kaynak tekrar kontrolu buna dahil degil.
- Veri birlestirmede bilinen 2021'deki alti gunluk bosluk doldurulmadi.
- Bu tur JP225 veya 50 stratejinin tumunu kapsamaz; uzun gecmisi eslestirilmis
  22 USDJPY stratejisi ile sinirlidir.

## Neyin Etkisini Izole Ettik?

1. `direct`: dogrudan net R tahmin eden mevcut referans HGB regresyonu.
2. `logistic_mean`: duzenlilestirilmis lojistik modelle net pozitif sonuc olasiligi;
   kazanc/kayip buyuklukleri sadece egitim donemindeki sinif ortalamalari.
3. `hgb_mean`: agac tabanli olasilik modeli, ayni ortalama buyuklukler.
4. `hgb_two_part`: `hgb_mean` ile birebir ayni olasilik tahmini, ayrica kosullu
   kazanc/kayip buyuklugu modelleri; az ornek varsa ortalamaya donus.

Karar skoru `P(kazanc)*beklenen_kazanc - P(kayip)*beklenen_kayip`.
Pozitif label `net_r > 0`; TP'ye degmek zorunlu degil. Kapanista gerceklesmis
net R kullanildi, pozitif kapanislar hedef R'ye yuvarlanmadi. Bu deney CSV'deki
maliyet/sonuc tanimini korur; broker maliyetlerinin ayrica dogrulandigi iddiasi degil.

`fixed_zero`: skor >= 0 ise sinyal gecer. Esik taramasi yok.
`confirmed_zero`: ayni kural ancak her iki kalibrasyon yarisinda da hem net fayda
hem aylik islem-sayisi eslestirilmis secim katkisi pozitifse acilir. Degilse filtre
uygulanmaz; bu, kayitli production modelinin yerine filtresiz modu almak demek degil.

## Dort Yillik Toplamlar

Asagida `fixed_zero` icin filtresize gore daha iyi / daha kotu PnL sayilari var.
Bir stratejinin dort yili birlestirildi; farkli stratejilerin R'leri toplanmadi.

| Yontem | Daha iyi / kotu | Direct referanstan iyi / kotu | En az 3 yilda fayda |
|---|---:|---:|---:|
| Direct net R | 10 / 12 | Referans | 4 |
| Logistic + ortalama buyukluk | 16 / 6 | 12 / 10 | 7 |
| HGB + ortalama buyukluk | 15 / 7 | 14 / 8 | 8 |
| HGB + kosullu buyukluk | 15 / 7 | 15 / 7 | 5 |

**Daha karmasik model daha iyi demek degil.** Ayni olasilik tahminlerini kullanan
iki HGB surumu karsilastirildiginda, kosullu buyukluk modeli 19 farkli serinin
yalnizca 5'inde daha iyi, 14'unde daha kotu. Direct'ten iyi gorunmesi, basit
siniflandiricidan da iyi oldugu anlamina gelmiyor.

## Somut Ornekler Ve Karsi Kanitlar

DD burada kapali islem net R dizisinin tepe-dip drawdown'idir. Floating, hesap
yuzdesi, EOD trailing drawdown veya challenge kaybetme olasiligi degildir.

| Strateji / yeni model | 4 yil filtresiz R | 4 yil model R | Filtresiz DD | Model DD |
|---|---:|---:|---:|---:|
| ProUsdJpySetup / HGB kosullu buyukluk | +0.83 | +28.64 | 35.57 | 11.06 |
| usdjpyGateStateOn / HGB ortalama | +5.54 | +12.70 | 17.49 | 5.57 |
| 0.5RGoodUsdjpy / HGB ortalama | -3.45 | +13.72 | 24.06 | 11.50 |
| 1RYildiz / Logistic ortalama | -31.65 | +0.07 | 46.77 | 20.44 |

Bu tablo tek basina terfi gerekcesi degil:

- ProUsdJpySetup'in yillik filtresizden farklari +21.93, +8.45, +3.03, **-5.61R**.
  Son yilin bilgi-zamani uygun ortak satirlarinda kayitli eski model +16.43R,
  yeni model +9.68R. Yeni DD 2.28R ile eski 4.26R'den dusuk, fakat PnL'de geride.
- GateStateOn son yil eski +5.10R / 3.99R DD iken HGB ortalama +6.50R / 1.75R DD.
  Olumlu ornek; ama dort yillik net faydanin 20 gunluk bootstrap araligi
  **-10.22 ile +24.90R**. Belirsizlik sifiri kapsiyor.
- 0.5RGoodUsdjpy dort yilda iyi gorunse de son yil eski +4.22R, yeni **-0.41R**;
  DD de 6.56R'den 11.50R'ye kotulesiyor.
- 1RYildiz lojistik model filtresize gore dort yilda da iyilestirdi. Ama modelin
  yillik netleri -1.83, -5.37, -3.40, +10.67R: dort yilin ucu hala zarar.
- HolyGrail'de uc olasilik modeli de buyuk kaybi azaltti; yine de dort yillik
  toplamlar -102.51R, -111.92R, -98.56R. Zarar azaltma karlilikla ayni sey degil.
- Mevcut usdjpy10R modelinin son ortak yil +11.01R / 1.01R DD sonucu, yeni
  uc adaydan da daha iyi. Korundu.

## Donem Degisimi Neden Onemli?

Logistic modelin filtresize gore iyilestirdigi strateji sayisi sirayla
22/22, 19/22, 7/22, 4/22. Tekrarlanan seriler cikarilinca
19/19, 16/19, 6/19, 3/19. Dort yillik toplami tek puana indirgemek bu bozulmayi gizler.

19 seri uzerinde modelin medyan islem tutma orani yaklasik %33, %34, %41, %39.
Yani iyilesmelerin onemli bir kismi daha az islem acarak geliyor; siklik kaybi yok
iddiasi dogru olmaz. Aylik sayi-eslestirme kontrolu bu nedenle dahil edildi.

Testteki olasilik tahmini ortalamasi ile gerceklesen net-pozitif oran arasindaki
strateji-medyan fark -5.67, -5.44, -7.44, -4.87 yuzde puan. Sistematik kotumserlik
gozleniyor. Bu tek basina sebebin rejim degisimi oldugunu kanitlamaz; olasilik
kalibrasyonu, gecmise ait kazanc/kayip ortalamalari ve veri secimi aday aciklamalar.

Brier skorunda egitimdeki sabit kazanma oranini gecme sayisi Logistic icin 31/88,
HGB icin 27/88. Pozitif getiri siralamasinda Logistic 43/88, Direct 32/88.
Siralamadaki bir iyilesme, mutlak olasiliklarin ve sifir getiri esiginin dogru
kalibre edildigini gostermiyor.

## Istatistik Ve Terfi

5 ve 20 takvim gunluk esli blok bootstrap, her birinde 20,000 tekrar; islemin
olmadigi gunler de tutuldu. Esdeger denemeler ayni yeniden orneklemeleri kullandi.
132 aday/politika karsilastirmasi icin aile-bazli duzeltme ve 528 karsilastirmalik
ortak duyarlilik sonucu kaydedildi. Drift altinda bootstrap yaklasiktir.

- Net fayda duzeltmesini gecenler sadece HolyGrail'in uc zarar azaltici modeli.
- Aylik islem-sayisi eslestirmesinin ustunde secim katkisi duzeltmesini gecen: 0.
- Direct modele ustunluk duzeltmesini gecen: 0.
- Kayitli mevcut modele ustunluk duzeltmesini gecen: 0.
- Tum onceden sabitlenen tarihsel kosullari birlikte gecen: 0.

Bu gecmis zaten onceki arastirmalarda goruldu. Test label'larini fit'e vermemek,
insanin tekrarli arastirma seciminden dogan overfit riskini ortadan kaldirmaz.
Yeni ileri donem verisi olmadan bagimsiz canli basari ispatlanamaz.

## Kontroller

- [x] 352 model tahmini kaynak veriden ayri replay koduyla eslestirildi.
- [x] 704 filtre karari, kalibrasyon kosullari ve gerceklesmis metrikleri dogrulandi.
- [x] Ayni olasilik basligi ve kazanc/kayip donusumu dogrulandi.
- [x] Gelecek net R ve cikis zamanini degistirmek tahmini degistirmedi.
- [x] 44 Direct referans sonucu R4 ile birebir toleransli eslesti.
- [x] Incumbent karsilastirmalari yalnizca bilgi-zamani uygun son-yil satirlarinda.
- [x] R6/R5/R4/R3/R2/R1 toplam 75 test gecti.
- [x] Izlenen 436 production dosyasinin SHA-256 degeri degismedi.
- [ ] Pozisyon-state execution replay yapilmadi; terfiye aday bulunmadi.
- [ ] Yeni ileri donem emirsiz shadow deneyi yapilmadi; terminale dokunulmadi.

Testlerde bilinen dateutil deprecation ve eski R4 sabit-oz-nitelik roundoff
uyarilari mevcut; test hatasi yok. Kaynak tahmin replay'i, terminal/fill davranisi
dogrulamasi degildir. Bu arastirma pipeline health check iddiasi tasimaz.

## Sonraki Arastirma Karari

Yeni indikator eklemek veya agi buyutmek yerine **olasilik kalibrasyonu ve
maliyet-sonrasi basabas esiginin zamansal kararliligi** siradaki kontrollu hipotez.
Olasi deneyde ayni sabit olasilik modeli korunmali; sadece gecmis kalibrasyon
penceresinde ogrenilen, az parametreli bir duzeltme ham tahminle karsilastirilmali.
Islem sayisi eslestirilmis kontrol ve kayitli eski modele karsi ortak-satir testi
zorunlu kalmali. Son test sonucuna gore strateji bazli esik ayarlanmayacak.

Bu sonraki deneyi bu raporda kazanan ilan etmiyorum; henuz calistirilmadi.
Bu turdeki olumlu ornekler hipotez kaydi olarak korunuyor, production secimi degil.

## Yeniden Uretim

```text
python scripts/orb_target_r6.py
python scripts/orb_target_r6_report.py
python scripts/verify_orb_target_r6.py
python scripts/orb_target_r6_diagnostics.py
python -m pytest -q tests/test_orb_target_r6.py tests/test_orb_veto_r5.py tests/test_orb_training_age_r4.py tests/test_orb_long_history_r3.py tests/test_orb_regime_local_r2.py tests/test_orb_regime_campaign.py
```

Frozen tasarim: `docs/ORB_Target_R6_Protocol.md`.
Sonuc, belirsizlik ve tum negatif ornekler: `logs/OrbTarget_R6_20260911/evaluation.json`.
Ozet: `logs/OrbTarget_R6_20260911/Results.md` ve `models.csv`.
Tani: `logs/OrbTarget_R6_20260911/diagnostics.json`.
Kontroller: `logs/OrbTarget_R6_20260911/verification.json` ve `production_integrity.json`.
Model paketleri/predictions.csv ilgili strateji/yil altinda; deploy edilmez.
Log klasoru git-ignore kapsaminda; 352 model paketi git'e eklenmedi.

Yontem kaynaklari dondurulmus protokolde. Bulgular bizim verimizin ampirik
sonuclaridir; universite/kurum referanslari karliligi dogrulamaz.
