# MT4 Bridge Setup (Direct Signal -> ProTrading)

Bu kurulumda MT4 tarafinda EA, indicator buffer sinyalini `iCustom` ile okur ve backend'e direkt POST atar.
Boylece log parsinge bagimlilik azalir.

## 1) EA dosyasini MT4'e kopyala

- Kaynak dosya: `IndicatorCodeExamples/ProTrading_MT4_Bridge_EA.mq4`
- Hedef klasor:
  - `MT4 -> File -> Open Data Folder -> MQL4 -> Experts`
- Sonra MT4:
  - `Navigator -> Expert Advisors` altinda `Refresh`
  - Gerekirse MetaEditor'da compile et.

## 2) WebRequest izin ver

- MT4: `Tools -> Options -> Expert Advisors`
- `Allow WebRequest for listed URL` aktif et
- Listeye ekle:
  - `http://127.0.0.1:8000`

## 3) Backend endpoint

- Endpoint: `POST /api/v1/mt4/bridge/signal`
- Tam URL:
  - `http://127.0.0.1:8000/api/v1/mt4/bridge/signal`

Opsiyonel guvenlik:
- `.env`:
  - `MT4_BRIDGE_INGEST_TOKEN=strong_local_token`
- EA input:
  - `InpBridgeToken` ayni deger olmali.

## 4) EA inputlarini ayarla (chart bazli)

- `InpIndicatorName`: indicator path/name
  - Ornek: `IntrepidIndicator\\Intrepid Trend Direction`
- `InpBuyBufferIndex`: BUY buffer index
- `InpSellBufferIndex`: SELL buffer index
- `InpSignalProfile`: `intrepid`, `hydra`, `uranus`, `fxnuke`, `alchemy`, `forexcyper`, `generic`
- `InpApiBaseUrl`: default `http://127.0.0.1:8000`
- `InpApiPath`: default `/api/v1/mt4/bridge/signal`
- `InpICustomParamsCsv`: indicator Inputs parametreleri (opsiyonel)
  - Ornek: `14,0,1`
  - `true/false` de kabul edilir
  - Ayirici olarak `,` (veya `;`) kullanabilirsin

Onemli:
- `InpICustomParamsCsv`, MT4 indicator penceresindeki `Inputs` sirasiyla bire bir ayni olmali.
- Bu generic EA su an yalnizca numeric/bool parametreleri destekler.
- String input isteyen indicatorlar icin indicatora ozel adapter EA gerekir.

## 5) Dogrulama

- MT4 Experts tabinda su tarz log gormelisin:
  - `MT4Bridge iCustom params count: ...`
  - `MT4Bridge sent BUY ... response=...`
- Dashboard tarafinda:
  - `mt4_exec` / `mt4_exec_failed` satirlari dusmeli.

## 6) Mevcut motorla entegrasyon

Bu endpoint backend'de mevcut pipeline'a baglidir:
- dedupe
- reverse-close (ayni indicator/symbol/tf ters sinyalde)
- MT5 execution
- execution audit log
