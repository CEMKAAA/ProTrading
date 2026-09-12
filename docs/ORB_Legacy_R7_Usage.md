# Legacy / R7 Secimi Ve Uc Modlu Leaderboard

2026-09-12. EA: `OrbUltimateEA_StrategyLibrary.mq5`, surum 3.52.
Sinyal uretim cekirdegi, geometri, publisher CSV semasi ve listener kodu degismedi.

R7 artik degistirilebilir model yuvasidir. Paket kurma, atomik aktivasyon ve geri
alma adimlari: [ORB_Model_Slot.md](ORB_Model_Slot.md).

## Model Secimi

1. Her zamanki Search ile stratejiyi uygula.
2. STRATEGY ML bolumunun basligindaki `MODEL: LEGACY` butonuna basinca `MODEL: R7 / CHAMPION SLOT` olur. Tekrar basinca Legacy'ye doner.
3. Filtreyi calistirmak icin ayrica `ML FILTER ON` gerekir. Model secmek, ML'yi kendiliginden acmaz.
4. `LOAD TRAINED` ve `USE RESULT`, R7 seciliyken o stratejinin R7 paketini yukler; CSV secmek veya tekrar Train yapmak gerekmez.

Yeni chartta varsayilan Legacy'dir. Secim hesap + chart kimligiyle saklanir.
Strateji degisince yalniz yeni stratejiye ait model yuklenir. Ayarlar, parite,
broker, TF veya model checksum uyusmazsa ML ON iken yeni giris reddedilir.
R7 eksikken Legacy'ye sessiz fallback yok. Acik/bekleyen trade veya CSV export
varken generation degistirilemez. Mevcut pozisyonlarin normal cikis yonetimi
degismez. Generation degisimi historical audit'i yeniden kuyruga alir.

Baslangic atamasi: ayni 52 **logistic_mean + probability calibration** paketi.
R7 yuvasi artik tarihli logistic veya ORB_MLP1 paketlerini kabul eder; yeni
agirliklar icin EA derlemek gerekmez. Yeni mimari/feature semasinda testli bir
adapter gerekir. En iyi modeli otomatik secmez. Legacy'ye dokunulmadi.

## Leaderboard

Sol ust mod butonu sirayla:

`VANILLA / NO ML / 5Y` -> `LEGACY ML / 5Y RETROSPECTIVE` -> `R7 ML / 5Y RETROSPECTIVE`

Her modda Net R, WR, kapali-islem MaxDD R, islem sayisi N ve mevcut Wilson/DD
siralamasi gorunur. 53 Vanilla, 50 Legacy, 52 R7 kaydi var. Eksik model `NO MODEL`
olarak gorunur, sifir kar gibi gosterilmez. R7 metrikleri artik aktif paket
manifestinden okunur; yeni modelde metrik yoksa eski sonuclar kullanilmaz.
USTEC icin R7 yok; uc JP225 stratejisi
icin Legacy modeli yok. Donem EA'nin 260 haftalik (1820 gunluk) 5Y tanimi:
15.09.2021-09.09.2026 broker zamani. Bu sabit snapshot, her gun otomatik yenilenmez.

Leaderboard'da mod gezmek canli ML modunu veya ON/OFF'u degistirmez. Satira
tiklamak stratejiyi mevcut parite/lifecycle korumalarindan gecerek uygular;
canli model generation ve ML ON/OFF aynen korunur. Bu iki secim ML panelindedir.

**Bes yillik ML leaderboard'u retrospektiftir, egitim donemini de icerir.**
Kayitli Legacy veya guncel R7 modelinin sabit agirliklari bes yillik ayni kapali
islem CSV'sine uygulanmistir. OOS validasyon veya gelecekte beklenen kar degildir.
Tum 53 CSV'de feature-valid/closed satir dislama yok; acik islem PnL'si dahil degil.
Sonuclar yeni emulator/EA tick replay degil, arastirma CSV'sindeki aday islemlerin
model karariyla maskelenmesidir. State-dependent emir akisi icin ayri replay gerekir.

## R7 Tarihsel Audit Ile Fark

EA'nin canli ve historical R7 filtresi ise karar zamaninda mevcut olan tarihli
model ve kalibrasyon surumunu kullanir. Gelecekte egitilmis modeli eski sinyale
uygulamaz. USDJPY tarihli kapsam 2022'de, JP225'in cogu 2024'te baslar; bazi seyrek
stratejilerde daha gec baslar. Onceki tarihler `NO HISTORICAL COVERAGE` hatasiyla
`INCOMPLETE` olarak belirtilir; kazanmis/kaybetmis diye uydurulmaz.

Bu nedenle **ML audit ile 5Y retrospektif leaderboard'un sayilari ayni olmak
zorunda degil**. Iki farkli degerlendirme oldugu baslik ve tooltip'te belirtilir.
Vanilla/Legacy modellerin onceki calisma davranisi degistirilmedi.

Guncel R7 state 09.09.2026 itibariyla uretilmistir ve **01.10.2026 broker
zamaninda sona erer**. Yenilenmediyse ML ON durumunda `STATE EXPIRED / REFRESH
REQUIRED` ile yeni girisleri engeller; eski state'i sonsuza kadar kullanmaz.
Bu turda aylik otomatik yeniden egitim servisi eklenmedi.

## Dosyalar Ve Test

- R7 orijinal dosyalari: `logs/OrbR7Runtime_20260912/Files/OrbML/R7/`.
- Moduler staging: `logs/OrbModelSlots_20260912/Slots/`.
- Aktif atama: Common Files altinda `OrbML/Slots/<strategy_id>/active.slot`.
- Surumler `Releases/<revision>.slot`, model `OrbML/Slots/Artifacts/<sha256>.model`.
- Python model/kalibrasyon kaynaklari: `logs/OrbR7Runtime_20260912/forward/`.
- Leaderboard tam veri: `logs/OrbR7Runtime_20260912/leaderboard_5y_retrospective.json`.
- 52 logistic paket + 1 MLP test paketi, 4.143 MQL/Python tahmini: kararlar ayni, maks fark 6.67e-16.
- Yanlis kimlik/checksum ve kapsam/expiry kontrolleri MQL'de test edildi.
- EA ve emirsiz probe 0 errors, 0 warnings ile derlendi.
- Bu testler gercek hesaba emir acmadi; canli trading/GUI tiklama testi yapildi iddiasi yok.
- 204 Python testi gecti; mevcut test fixture'larinda 6 kutuphane uyarisi var.

Onayli kurulum tamamlandi: `C:\MT5\DEMO\MQL5\Experts` ve `Experts\orb`
altinda kaynaklar, include'lar ve derlenmis EX5; Common Files altinda 52 R7
model yuvasi. Legacy modeller degistirilmedi.
Kayit: `logs/OrbModelSlots_20260912/installation.json`.
R7 paketlerinin toplami yaklasik 687 KiB; bu inference arsivleri tick logu yazmaz.

Terminali yeniden baslatma komutu verilmedi; EX5 dosyasi degisimi platformun
bagli EA'yi yeniden yuklemesine yol acabilir. Calisan chartta 3.52 kontrolu
kullaniciya aittir; sadece dosya kurulumundan aktif instance dogrulamasi cikarmiyoruz.

Onceki R7 arastirma kontratlarinin production hash snapshot'lari degistirilmedi.
Bu kullanici-istekli runtime patch'i onlardan dogal olarak farklidir; eski
`verify_contract` artik bu yeni kaynaklari eski snapshot'a esit bulmamalidir.
Eski deney dosyalari ve modelleri aynen korunur.
