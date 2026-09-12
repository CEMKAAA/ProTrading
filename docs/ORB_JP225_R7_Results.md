# JP225 R7 Egitimi Ve Sonuclari

2026-09-12. Arastirma tamamlandi; production modelleri degistirilmedi.

## Kapsam

- Her biri kendi ayar kimligi ve CSV'si ile 30 JP225 stratejisi.
- USDJPY R7 protokolunun ayni parametrelerle transferi; JP225 sonucuna gore ayar aramasi yok.
- Iki temel aile: duzenlilestirilmis lojistik ve histogram gradient boosting (HGB).
- Bes kol: ham, olasilik kalibrasyonu, kazanc/kayip buyuklugu guncellemesi, ikisi birlikte, rejime ozel kalibrasyonla birlikte.
- 50 mevcut oz nitelik; sinyal uretimi, geometri ve net R etiketleri degismedi.
- JP225 oz nitelik CSV gecmisi Eylul 2021'den basliyor. USDJPY'nin 2018 gecmisi JP225 icin varmis gibi kullanilmadi.

Iki kronolojik test: 09.09.2024-09.09.2025 ve 09.09.2025-09.09.2026.
Temel model egitimi test baslangicindan bir yil once bitiyor. Aradaki yil ilk
kalibrasyona ayriliyor. Test ilerlerken aylik guncellemeler yalniz o anda bilinen,
en az 24 saat once kapanmis islemleri kullanabiliyor. Gelecek ayin sonucu yok.
Bu nedenle bunlar sabit model testinden farkli, ardisik ogrenme testleridir.

## Uretilen Dosyalar

- 55 uygun strateji/yil: ilk testte 26, ikinci testte 29 strateji.
- 550 model/kol/yil sonucu ve 1.430 aylik kalibrasyon durumu.
- 30 stratejinin tamami icin 09.09.2026 itibariyla 60 guncel arastirma modeli.
- Tarihsel temel modellerle birlikte toplam 170 model kaynaktan yeniden egitilerek dogrulandi.
- Egitim/kayit dongusu 82,562 saniye; bagimsiz dogrulama ve karsilastirma bu sureye dahil degil.

Guncel paketler:
`logs/OrbJP225_R7_20260911/<strategy_id>/forward_20260909/`

Her klasorde iki `.research.joblib` model ve `states.json` var. Model manifesti:
`logs/OrbJP225_R7_20260911/forward_manifest.json`.

**Bunlar EA'nin kullanacagi portable modeller degil.** Train tamamlandi, fakat
canli dashboard kaydina alinmadi ve etkinlestirilmedi. Bu yeni refit'lerden sonra
test verisi bulunmadigindan, tarihsel eski model surumlerinin basarisini bu yeni
paketlerin ileriye donuk basarisi olarak gostermiyoruz.

## Veri Yeterliligi

En az 150 temel egitim, 20 ilk kalibrasyon, 20 test islemi gerekiyor. Atlananlar:

| Strateji | Test baslangici | Temel egitim islemi |
|---|---:|---:|
| 2RModeljp225 | 2024 | 97 |
| jp225HighProbaLongWait | 2024 | 122 |
| jp225HolyGrail | 2024 | 82 |
| jp225HolyGrail | 2025 | 135 |
| JP225nOFilter1R | 2024 | 140 |

Bu eksiklikler guncel 2026 egitiminde ortadan kalkiyor; 30 stratejinin hepsi
egitilebildi. Ancak HolyGrail icin uygun tarihsel test varmis gibi sonuc verilmedi.

Ayrica `2RModeljp225`, `jp225HighProbaLongWait`, `jp225HolyGrail` icin dogrulanmis
mevcut model kaydi bulunmadi. Bunlar arastirma egitimine dahil, eski ML modeliyle
karsilastirmaya dahil degil. Kayit bulunamamasi bir filtresiz model basarisi sayilmadi.

## Filtresize Gore Sonuc

Asagidaki sayilar net R'yi filtresiz ayni stratejiye gore iyilestiren strateji
sayisidir. Pozitif PnL uretmek ile filtresiz stratejiyi gecmek farklidir.

| Aile / kol | 2024-25 / 26 strateji | 2025-26 / 29 strateji |
|---|---:|---:|
| Lojistik / ham | 21 | 2 |
| Lojistik / olasilik | 21 | 5 |
| Lojistik / buyukluk | 21 | 2 |
| Lojistik / birlikte | 21 | 3 |
| Lojistik / rejim birlikte | 20 | 4 |
| HGB / ham | 20 | 3 |
| HGB / olasilik | 21 | 5 |
| HGB / buyukluk | 18 | 3 |
| HGB / birlikte | 20 | 2 |
| HGB / rejim birlikte | 20 | 2 |

Son yilda HGB kollarinin hepsi 29 stratejide de pozitif sonuc uretti. Fakat ayni
donemde filtresiz stratejiler zaten gucluydu: olasilik kolu bunlarin yalnizca
5'inde net R'yi artirdi. "29/29 pozitif" diye bir ML basarisi iddiasi yaniltici olur.
Onceki daha zor donemde filtrelerin zarari azaltmasi, iyi donemde kazanci da
azaltabilecekleri gercegini ortadan kaldirmiyor.

## Mevcut Modellerle Karsilastirma

27 JP225 mevcut kaydi icin ortak son-yil islemleri kullanildi. Mevcut modelin
egitim/secim bilgi bitisinden sonraki 24 saat de dislandi. Dolayisiyla bazi
stratejilerde ortak sonuc ile tam tarihsel yil sonucu farkli olabilir.

| Aile / kol | PnL daha iyi / kotu / ayni | PnL-DD acisindan yeni ustun | Medyan PnL farki |
|---|---:|---:|---:|
| Lojistik / olasilik | 10 / 16 / 1 | 7 | -1,01R |
| Lojistik / buyukluk | 4 / 23 / 0 | 4 | -2,42R |
| Lojistik / birlikte | 7 / 20 / 0 | 4 | -2,39R |
| Lojistik / rejim birlikte | 9 / 17 / 1 | 6 | -1,17R |
| HGB / olasilik | 12 / 15 / 0 | 6 | -1,75R |
| HGB / buyukluk | 6 / 21 / 0 | 6 | -3,96R |
| HGB / birlikte | 6 / 21 / 0 | 5 | -2,10R |
| HGB / rejim birlikte | 6 / 21 / 0 | 4 | -2,27R |

Yeni ustun: PnL en az ayni, DD en fazla ayni ve en az biri daha iyi. Bu yalnizca
betimleyici bir siniflandirma; istatistiksel kanit veya model atama kurali degil.

## Dogrulama Ve Sinirlar

- 170 kaynaktan yeniden egitim, 550 karar maskesi ve 1.430 kalibrasyon durumu dogrulandi.
- Intercept hesaplari bagimsiz Brent cozucusuyle uyustu.
- O anda bilinmeyen sonuc etiketlerini degistirmek o andaki kalibrasyonu degistirmedi.
- 436 izlenen production dosyasinin hash'i degismedi.
- R1-R7 ve yeni karsilastirma dahil 95 test gecti; 4 mevcut kutuphane uyarisi var.
- 5/20 gunluk eslenik blok bootstrap'te coklu karsilastirma duzeltmesi sonrasinda mevcut modele karsi anlamli ustunluk gosteren aday yok.
- Bu gecmis daha once arastirildi; kronolojik ayrim onu tekrar el degmemis test yapmaz.
- CSV'deki oz niteliklerin uretilmesini yeniden tick seviyesinde denetleyen veya listener emirlerini yeniden oynatan bir test yapilmadi.
- DD kapali islem R egrisine aittir; floating/EOD/account drawdown degildir.

Bagimsiz dogrulama: `logs/OrbJP225_R7_20260911/verification.json`.
Protokol: `docs/ORB_JP225_R7_Protocol.md`.
Iki varligin tum 392 karsilastirmasi: `logs/OrbIncumbentComparison_20260912/FullComparison.md`.
Yorum ve arastirma karari: `docs/ORB_Current_vs_R7_Comparison.md`.

**Karar:** egitim hedefi tamamlandi. Mevcut modeller korunuyor; R7 yalniz
arastirma adayi. Yeni ileri donuk veri ve execution uyumlulugu olmadan terfi yok.
