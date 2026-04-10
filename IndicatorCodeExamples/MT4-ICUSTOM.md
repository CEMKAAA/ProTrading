# MT4 iCustom Bridge Kurulumu (Sıfırdan, Adım Adım)

Bu doküman, MT4’te çalışan indikatör sinyallerini `iCustom` ile okuyup backend’e göndererek otomatik trade açma zincirini **sıfırdan** kurmak içindir.

Hedef akış:

`MT4 Chart + Indicator` -> `ProTrading_MT4_Bridge_EA.mq4` -> `http://127.0.0.1/api/v1/mt4/bridge/signal` -> `backend` -> `trade engine`

---

## 0) Ön Koşullar

1. Proje klasörü:
`C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem`
2. MT4 data folder:
`C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\50CA3DFB510CC5A8F28B48D1BF2A5702`
3. EA dosyası:
`IndicatorCodeExamples\ProTrading_MT4_Bridge_EA.mq4`
4. Hazır preset (Intrepid örneği):
`IndicatorCodeExamples\EaPresets\intrepidBridge.set`

---

## 1) Backend ve Frontend’i Aç

### Backend (zorunlu)
Proje root’ta terminal aç:

```powershell
cd C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem
python -m uvicorn dashboard.backend.main:app --host 0.0.0.0 --port 8000 --reload
```

### Frontend (opsiyonel ama önerilir)

```powershell
cd C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem
.\start_frontend.bat
```

---

## 2) MT4 WebRequest Limiti: Neden 80 Portu?

Bu EA içinde koruma var: MT4 WebRequest pratikte `http:80` (veya `https:443`) endpoint ile en stabil çalışır.  
Bu yüzden backend `8000`’de açık olsa da MT4 tarafında `http://127.0.0.1` (port 80) kullanıyoruz ve Windows’ta 80 -> 8000 yönlendirme yapıyoruz.

---

## 3) Port 80 Çakışmasını Temizle (SQL Reporting Services)

Senin makinede 80’i SQL Reporting Services (SSRS) kullanıyordu (`/REPORTS`, `/REPORTSERVER`).  
Bu durumda MT4 -> 127.0.0.1:80 istekleri backend’e ulaşmaz.

### 3.1 Yönetici PowerShell aç
Start menü -> PowerShell -> **Run as Administrator**

### 3.2 SSRS servislerini durdur (varsa)

```powershell
Stop-Service -Name SQLServerReportingServices -Force -ErrorAction SilentlyContinue
Stop-Service -Name ReportServer -Force -ErrorAction SilentlyContinue
```

### 3.3 Otomatik açılmayı kapat (isteğe bağlı ama önerilir)

```powershell
Set-Service -Name SQLServerReportingServices -StartupType Manual -ErrorAction SilentlyContinue
Set-Service -Name ReportServer -StartupType Manual -ErrorAction SilentlyContinue
```

Not: Bu işlem **SQL Database Engine’i kapatmaz**, sadece SSRS web rapor servislerini etkiler.

---

## 4) Portproxy Kur (80 -> 8000)

Yönetici PowerShell’de:

```powershell
Set-Service -Name iphlpsvc -StartupType Automatic
Start-Service -Name iphlpsvc
netsh interface portproxy reset
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=80 connectaddress=127.0.0.1 connectport=8000
netsh interface portproxy show v4tov4
```

Beklenen çıktı benzeri:

`0.0.0.0:80 -> 127.0.0.1:8000`

---

## 5) Endpoint’i Elle Test Et (MT4’ten Önce)

PowerShell’de `curl` alias karmaşası olmasın diye `curl.exe` kullan:

```powershell
curl.exe -s -X POST "http://127.0.0.1/api/v1/mt4/bridge/signal" ^
  -H "Content-Type: application/json" ^
  -d "{\"indicator\":\"probe\",\"signal_hint\":\"BUY\",\"symbol\":\"USDJPYM\",\"timeframe\":\"M1\",\"signal_profile\":\"intrepid\",\"message\":\"probe\"}"
```

Beklenen:
- JSON içinde `ok: true`
- veya en azından FastAPI formatında bir JSON cevap (404 HTML olmamalı)

Eğer HTML `Not Found` gelirse yanlış host/port/path’e gidiyorsun.

---

## 6) MT4 İçinde WebRequest Allowed URL Ayarı

MT4 -> `Tools -> Options -> Expert Advisors`

`Allow WebRequest for listed URL` işaretli olacak ve şunları ekle:

1. `http://127.0.0.1`
2. `http://localhost`

Not: path eklemek zorunda değilsin; base URL yeterli.

---

## 7) EA’yı MT4’e Kopyala ve Compile Et

1. `ProTrading_MT4_Bridge_EA.mq4` dosyasını şuraya kopyala:
`<MT4_DATA_PATH>\MQL4\Experts\`
2. MT4’te `Navigator -> Expert Advisors` altında görünmeli.
3. MetaEditor ile aç (`F4`) ve compile et.

Compile sonucu:
- Error = 0 olmalı
- Warning olabilir ama kritik olan error olmaması

---

## 8) Preset (.set) Hazırlama ve Yükleme

`intrepidBridge.set` dosyasını şuraya kopyala:
`<MT4_DATA_PATH>\MQL4\Presets\`

EA chart’a eklenince:
`Inputs -> Load... -> intrepidBridge.set`

Intrepid için örnek değerler:

```ini
InpIndicatorName=IntrepidIndicator\Intrepid Trend Direction
InpBuyBufferIndex=0
InpSellBufferIndex=1
InpICustomParamsCsv=40,2.0,true,true,true,true,1,1,0
InpSignalShift=0
InpPollSeconds=1
InpOneSignalPerBar=true
InpSignalAbsMin=0.0000001
InpAllowBuy=true
InpAllowSell=true
InpApiBaseUrl=http://127.0.0.1
InpApiPath=/api/v1/mt4/bridge/signal
InpBridgeToken=
InpSignalProfile=intrepid
InpHttpTimeoutMs=5000
InpDebugPrint=true
```

Kritik nokta:
- `InpApiBaseUrl` burada `http://127.0.0.1` olmalı (port yazma).
- Route path doğru olmalı: `/api/v1/mt4/bridge/signal`

---

## 9) Chart’a Kurulum Sırası

Her chart için:

1. İlgili indikatörü chart’a ekle (ör: Intrepid Trend Direction)
2. Aynı chart’a `ProTrading_MT4_Bridge_EA` ekle
3. EA `Common` sekmesinde:
   - `Allow live trading` açık
   - `Allow DLL imports` gerekiyorsa açık
4. MT4 ana toolbar’da `AutoTrading` açık

Not: İndikatör chart’ta açık olsa bile EA kendi `iCustom` instance’ını çağırır.  
Bu yüzden `InpICustomParamsCsv` parametreleri indikatörün gerçek inputlarıyla uyumlu olmalıdır.

---

## 10) Canlı Doğrulama (Success Kriteri)

MT4 Experts logunda şu tip satır başarıdır:

`MT4Bridge sent BUY ... endpoint=http://127.0.0.1/api/v1/mt4/bridge/signal response={"ok":true,...}`

Backend tarafında da trade sonucu:
- `"executed": true`
- ticket numarası dönmesi

---

## 11) Hata Kodları ve Çözüm

### `err=5200` + `code=-1`
Bağlantı kuramadı.
- Backend kapalı olabilir
- Portproxy yok/bozuk olabilir
- 80 başka servis tarafından tutuluyor olabilir

### `err=4060`
WebRequest URL allowlist’e ekli değil.
- MT4 Allowed URL’ye `http://127.0.0.1` ve `http://localhost` ekle

### `HTTP 404`
Yanlış endpoint.
- `InpApiPath=/api/v1/mt4/bridge/signal` olmalı
- `InpApiBaseUrl=http://127.0.0.1` olmalı

### `TRADE_RETCODE_CLIENT_DISABLES_AT`
MT5 tarafında AutoTrading kapalı.

---

## 12) Çoklu Chart / Çoklu İndikatör Ölçekleme

Aynı EA’yı farklı chart’lara takabilirsin.

Önerilen kural:
1. Her indikatör profili için ayrı `.set` dosyası üret:
   - `intrepidBridge.set`
   - `hydraBridge.set`
   - `uranusBridge.set`
   - `fxnukeBridge.set`
2. Her chart’ta doğru `InpSignalProfile` kullan.
3. Her chart kendi symbol/tf kombinasyonunu payload’a taşır; backend bunu ayrı işler.

---

## 13) Güvenli Geri Alma (Rollback)

Kurulumu geri almak istersen:

1. MT4 chartlardan EA kaldır
2. Portproxy temizle:
```powershell
netsh interface portproxy reset
```
3. SSRS gerekiyorsa tekrar aç:
```powershell
Start-Service -Name SQLServerReportingServices -ErrorAction SilentlyContinue
Start-Service -Name ReportServer -ErrorAction SilentlyContinue
```

---

## 14) Hızlı Kontrol Listesi

- [ ] Backend 8000’de açık
- [ ] Portproxy 80 -> 8000 aktif
- [ ] SSRS 80’i işgal etmiyor
- [ ] MT4 Allowed URL’de `http://127.0.0.1` var
- [ ] EA compile errors = 0
- [ ] Chart’ta indikatör + EA birlikte açık
- [ ] Experts logunda `MT4Bridge sent BUY/SELL` görülüyor
- [ ] Backend response `ok:true` dönüyor

---

## 15) Not

Bu akış MT4 log-tail’e bağımlı değildir; sinyali doğrudan bridge endpoint’e gönderir.  
Bu yüzden özellikle MT4’te log dosyası gecikme/senkronizasyon sorunlarını by-pass eder.
