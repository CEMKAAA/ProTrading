# StrategyLibrary NAT Giris Kilidi

## Bulgu

`OrbUltimateEA_StrategyLibrary.mq5` v6.88'de native giris engeli
`g_orbBridgeOnly && !g_orbNativeWithBridgeOnly` idi. ONLY OFF + NAT OFF
durumunda native emir yolu acikti. Dashboard'daki NAT OFF yazisi bu nedenle
bagimsiz bir native trading kapatma anahtari olarak davranmiyordu.

Salt-okunur MT5 incelemesinde USDJPYm icin iki pozisyon goruldu:

| Ticket | Yon | Acilis UTC | Magic |
|---|---|---|---|
| 2339386356 | BUY | 2026-09-10 00:30 | 4000015091503719343 |
| 2339799275 | SELL | 2026-09-10 02:03 | 4000015091503452691 |

Snapshot: `logs/nat_gate_audit_20260910/positions.json`.
Bu saatler islemlerin cok eski haftalardan kalmadigini gosterir; tek basina
acilis aninda NAT'in hangi durumda oldugunu ispatlamaz. Kaydedilmis chart
profilleri de anlik dashboard runtime'inin kesin kaniti degildir. Kodda
yanlis girise izin veren yol ise dogrudan dogrulandi.

## v6.89 davranisi

| NAT | PUB | Yeni MT5 entry | Bridge yayin |
|---|---|---|---|
| OFF | OFF | Engelli | Yok |
| OFF | ON | Engelli | Diger filtre/kontroller gecerliyse devam |
| ON | OFF | Diger kontroller gecerliyse acilabilir | Yok |
| ON | ON | Diger kontroller gecerliyse acilabilir | Devam |

ONLY, NAT OFF'u asamaz. ONLY ON secilmesi mevcut davranistaki gibi PUB'u acar;
native icin gene NAT ON gerekir. Iki cikis da kapaliysa yeni execution plani
ve sahte execution cizimi olusturulmaz. Son emir gonderim noktasinda ve
invalid-stops retry oncesinde de native guard vardir.

NAT OFF yeni giris iznidir; **flatten butonu degildir**. Daha once acilmis
pozisyonlar kendiliginden kapanmaz. Mevcut SL/TP, reverse/NAS exit ve koruyucu
yonetim engellenmedi. PUB davranisi, CSV semasi ve listener kodu degistirilmedi.
NAT toggle'i chart/magic/PUB/ONLY durumunu Print ile kaydeder.

## Dogrulama ve yukleme

- Derleme: 0 errors, 0 warnings.
- NAT+mevcut ML regresyon paketi: 76 passed, 3 warnings. Uyarilar dateutil
  deprecation ve sentetik ML testlerindeki optimizer convergence uyarilaridir.
- Sinyal/feature/outcome uyumluluk denetimi: 38 fonksiyon, mismatch yok.
- `C:\MT5\DEMO\MQL5\Experts` kok ve `orb` StrategyLibrary kaynak/include/binary
  kopyalarinda 42 dosya dogrulandi.
- Build: `2026-09-10.v6.89-native-entry-gate`.
- Raporlar: `logs/demo_sync_20260910_v689`.

Bu denetimler compile ve otomatik kaynak/regresyon kontrolleridir; canli
hesapta deneme emri acilarak test yapilmadi. Pozisyonlara dokunulmadi.
Terminal/chartlar yeniden baslatilmadi. Diskte guncel binary bulunmasi,
calisan her instance'in v6.89'u yukledigini tek basina ispatlamaz. Calisan
instance build'i kontrol edilerek guncellenmeli; NAT durumlari tekrar
dogrulanmali. Native acilmasi isteniyorsa artik NAT ON acikca secilmelidir.

Patch yalniz aktif incelenen StrategyLibrary EA'sina aittir. Diger EA'larin
NAT semantiklerinin topluca degistirildigi veya tum pipelinelarin bu runda
yeniden canli test edildigi iddia edilmez.
