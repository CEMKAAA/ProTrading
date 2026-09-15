# EA Klasor Rehberi

| Klasor | Icerik |
| --- | --- |
| `orb/` | ORB Ultimate, StrategyLibrary ve eski Channel varyanti |
| `nas/` | NAS SATS PartialNoBE ve yeni NAS StrategyLibrary |
| `liq/` | Normal Liq Narrative, Invert, SolVersion, Sol Advanced ve channel varyantlari |

Her klasor, EA'larin kullandigi yerel MQH bagimliliklarini da icerir.
Hangi MQH'nin hangi dosyadan kullanildigi klasordeki `README.md` tablosunda,
dosya hash'leri ve bagimlilik agaci `manifest.json` dosyasinda bulunur.
Paylasilan MQH'ler ihtiyac duyan her ailede bulunur; isimlerinde Liq veya Nas
gecmesi yalnizca o EA tarafindan kullanildiklari anlamina gelmez.

## Tek Kaynak Kurali

Mevcut test, derleme ve terminal kurulum scriptleri kokteki dosyalari kullanir.
Bu nedenle asil duzenlenebilir kaynaklar halen `IndicatorCodeExamples/` kokundedir.
Uc yeni klasor, kesfetmek ve bagimliliklari birlikte gormek icin tam kopyalardir;
kaynagin tasinmasi veya sinyal matematiginin degistirilmesi yapilmadi.
Klasor kopyalarini bagimsiz duzenlemeyin. Script yerel degisikligi fark ederse
sessizce ezmek yerine durur.

Workspace kokunden kaynak degisikliklerinden sonra:

```powershell
& scripts/sync_workspace_ea_families.ps1
& scripts/sync_workspace_ea_families.ps1 -Check
```

Yalniz MQ5 ana dosyasini derleyin; MQH tek basina EA degildir. EX5 kopyalamak
yeniden derlemek degildir. Degisen kaynak once normal build akisi ile derlenmelidir.

Bu duzenleme MT5 terminal kurulumlarini, listenerlari, modelleri, veri setlerini,
SacredVersions kopyalarini ve diger eski/deneysel EA'lari degistirmez.
