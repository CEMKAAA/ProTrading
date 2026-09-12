# R8: Mevcut Sampiyonu Degistirmeden Kalibrasyon

2026-09-12. Arastirma tamamlandi, production'a aktarilmadi. Dashboard'daki R7
ile karistirilmamali: R7 yeni lojistik model; R8 mevcut model agirliklarini koruyor.

## Deney

22 USDJPY + 27 JP225 kayitli modelin agirliklari, karar esigi ve no-veto durumu
aynen korundu. Global kalibrasyon ve global+rejim olmak uzere iki aday ek katman,
toplam 98 eslenik karsilastirma. Ortak son-yil donemi 09.09.2025-09.09.2026;
mevcut modelin egitim/secim bilgisinden sonraki 24 saat ayrica dislaniyor.

MLP olasiliklarina duzenlilestirilmis intercept; RIDGE/HGB getiri tahminlerine
gecmis tahmin hatasinin duzenlilestirilmis ortalamasi eklendi. Esik taramasi yok.
Rejim yerel katmani daha guclu duzenlilestiriliyor. Kullanilan formuller ve
parametreler `docs/ORB_ChampionCalibration_R8_Protocol.md` icinde onceden yazildi.

Kalibrasyon icin modelin egitim/secimde GORMEDIGI ve o anda kapanmis islemler
gerekiyor. 49 stratejinin hepsinde ilk ay yeterli 40 kalibrasyon islemi yoktu.
Bu nedenle ilk donemde fallback sifir; yeni sonuclar geldikce aylik katman aktif
olabiliyor. Bunu gizlemek icin eski egitim tahminlerini kalibrasyona katmadik.

## Sonuclar

Iyilesen/kotulesen sayilari mevcut ayni modele gore net R farkidir.

| Varlik | Duzeltme | Daha iyi | Daha kotu | Ayni | Medyan fark |
|---|---|---:|---:|---:|---:|
| USDJPY | Global | 5 | 8 | 9 | 0R |
| USDJPY | Global + rejim | 8 | 8 | 6 | 0R |
| JP225 | Global | 10 | 5 | 12 | 0R |
| JP225 | Global + rejim | 10 | 5 | 12 | 0R |

PnL artip DD'nin artmadigi ornek sayisi sirasiyla 4, 7, 9 ve 8. Ayni kalanlarin
bir kismi no-veto veya yeterli kalibrasyon/karar degisimi olmayan modellerdir;
bu sayilarin toplamini bagimsiz kazanan piyasa olayi gibi yorumlamiyoruz.

Sonradan secilmis betimleyici ornekler, production secicisi degil:

| Strateji / katman | Net R once -> sonra | DD R once -> sonra | Islem |
|---|---:|---:|---:|
| jp2250.5RSetupV2 / global | +9,54 -> +14,53 | 7,15 -> 4,00 | 130 -> 146 |
| FirstTF5ChartJP225 / rejim | +17,27 -> +22,24 | 12,63 -> 11,00 | 188 -> 211 |
| jp2250.5Model / global | +14,84 -> +19,01 | 2,50 -> 2,50 | 107 -> 132 |
| jp2250.5Model / rejim | +14,84 -> +19,51 | 2,50 -> 3,00 | 107 -> 139 |
| JP225DISP_ON_IBM1_SETUP_Edge / global | +5,79 -> +9,08 | 4,00 -> 4,00 | 87 -> 111 |

Rejim katmani her yerde daha iyi degil; ornegin jp2250.5Model'de ekstra kazanc
daha yuksek DD ile geliyor. V2'nin R7 lojistik olasilik +18,91R sonucu ile bu
R8 +14,53R sonucu farkli modellerdir; R8 eski RIDGE agirliklarini korur.

## Ne Ogrendik?

Mevcut modeldeki fazla engellemeyi yumusatmak JP225'ta daha az yapisal degisiklikle
bazi faydalar saglayabiliyor. Ancak tum modelleri kurtaran tek duzeltme yok.
USDJPY genelinde net ilerleme henuz belirgin degil. Rejimli kolun otomatik olarak
globale ustun olacagi hipotezi desteklenmedi.

5/20 takvim gunluk eslenik bootstrap, 20.000 tekrar, iki metrik/98 aday icin
196 test duzeltmesinden sonra anlamli net R ustunlugu gosteren aday **0**.
Bu gecmis zaten arastirildi. Sonuclar bir sonraki temiz ileri donuk golge deney
icin hipotezdir, overfit olmadigi kanitlanmis model diye sunulamaz.

## Dogrulama

49 modelin ham tahminleri tekrar uretildi. 637 aylik durum ve 1.274 aylik karar
maskesi yeniden hesaplandi. MLP intercept'leri bagimsiz Brent cozucusuyle,
getiri duzeltmeleri bagimsiz ortalama/prior denklemleriyle uyustu. Bilinmeyen
etiketleri degistirme testi state'i degistirmedi. Mevcut agirliklar degismedi.

Tum adaylar: `logs/OrbChampionCalibration_R8_20260912/results.json`.
Bagimsiz dogrulama: `logs/OrbChampionCalibration_R8_20260912/verification.json`.
Strateji klasorlerinde tahminler ve aylik kalibrasyon durumlari sakli.

Bu R8 arastirmasi sirasinda 436 izlenen production dosyasi sabitti. Sonrasinda
kullanicinin onayladigi R7/leaderboard 3.51 kurulumu ayri bir islemdir. R8 hicbir
EA model kaydina eklenmedi. Canli shadow veya stateful order replay yapilmadi.

## Sonraki Adim

Iki basit challenger'i (global ve rejim) dondurup yeni veri uzerinde karar ve
sonuc gunlugu tutmak; egitim disi tahmin birikimini artirmak. Bir sonraki
arastirma ihtiyaci daha fazla sinir/esik taramasi degil, kalibrasyonun yeterli
ornekle hangi rejimlerde karari degistirdigini ve bu degisimlerin sonradan da
yararli kalip kalmadigini gormek. Adaylarin golge emir/lifecycle replay'i de
tamamlanmadan gercek hesapta otomatik model degistirme yapilmamali.
