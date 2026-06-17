# MT5 Event Validation Pipeline

Bu dokuman, EA internal backtest engine sonuclarini MT5 native Strategy Tester ile dogrulamak icin kurulan guncel pipeline'in kalici kullanim kilavuzudur.

Ana fikir:

- Internal backtest engine ana tarama motorudur.
- MT5 native Strategy Tester kisa ve hedefli dogrulama motorudur.
- Dogrulama orneklem uzayi rastgele tarih araliklari degil, internal engine'in gercekten trade urettigi event'lerdir.
- Native MT5 sonuclari ile internal event sonuclari trade-event seviyesinde karsilastirilir.

## Temel Dosyalar

EA ve export tarafi:

- `IndicatorCodeExamples/NasUltimateEA.mq5`
- `IndicatorCodeExamples/RealOrbStrategy.mq5`
- `IndicatorCodeExamples/ERL_IRL_SwingModel_EA.mq5`

Validation scriptleri:

- `scripts/build_mt5_candidate_validation.py`
- `scripts/mt5_validation_harness.py`
- `scripts/build_mt5_event_sample_jobs.py`
- `scripts/compare_mt5_event_samples.py`

Onemli output klasorleri:

- `logs/mt5_validation`
- `configs`
- `IndicatorCodeExamples/EaPresets/CandidateValidation`

Worker MT5 terminal:

- `.tmp/mt5_validation_exness_worker/terminal64.exe`
- `.tmp/mt5_validation_exness_worker/MetaEditor64.exe`

Live/demo MT5 terminal:

- `C:\MT5\DEMO\terminal64.exe`

## Pipeline Ozeti

1. EA dashboard/internal backtest engine ile genis zaman penceresinde brute-force test calistir.
2. Internal aggregate sonuclardan top candidate kombinasyonlari cikar.
3. Candidate preset/job dosyalarini uret.
4. Candidate job'lari `internal-export-only` modda calistirarak gercek trade-event CSV'leri uret.
5. Bu event CSV'lerinden en iyi, en kotu, ilk, son ve zamana yayilmis event sample'lari sec.
6. Event sample'lar icin native MT5 Strategy Tester job'lari uret.
7. Native MT5 job'larini calistir.
8. Internal event ile native tester deal audit'i karsilastir.
9. Latency, entry price farki, trade direction ve trade count farklarini incele.

## 1. Internal Backtest Sonuclarini Uret

EA dashboardundan ilgili stratejinin internal backtest engine'ini calistir.

Ornek:

- NAS V3 icin her sembol/timeframe chartinda 20 hafta.
- ORB icin USTEC chartinda strateji timeframe kombinasyonlari.
- ERL/IRL icin ilgili sembol/timeframe kombinasyonlari.

Internal engine outputlari genellikle `MQL5/Files` altinda olusur.

Ornek NAS aggregate dosyasi:

```text
NasV3Lab_BruteBacktest_YYYYMMDD_HHMMSS.csv
```

Bu dosyalarin normalize/analiz sonucu genelde surada tutulur:

```text
logs/mt5_validation/best_combo_analysis_YYYYMMDD.json
```

## 2. Candidate Preset ve Job Dosyalarini Uret

Top kombinasyonlardan isolated candidate presetleri ve validation job JSON'u uretmek icin:

```powershell
python scripts\build_mt5_candidate_validation.py `
  --analysis logs\mt5_validation\best_combo_analysis_20260616.json `
  --samples-per-candidate 3 `
  --sample-days 2 `
  --timeout-sec 600
```

Varsayilan ciktilar:

```text
configs/mt5_candidate_validation_jobs.json
logs/mt5_validation/candidate_validation_manifest.json
IndicatorCodeExamples/EaPresets/CandidateValidation/
```

Not:

- Bu dosya ilk candidate/job uretimi icindir.
- Eski calendar-window sampling tek basina final dogrulama icin yeterli degildir.
- Final dogrulama icin event-sample akisi kullanilmalidir.

## 3. Internal Event Export-Only Job Uret

Gercek sample universe trade ureten event'ler oldugu icin candidate'lari once internal-event export modunda calistir.

```powershell
python scripts\build_mt5_candidate_validation.py `
  --analysis logs\mt5_validation\best_combo_analysis_20260616.json `
  --samples-per-candidate 1 `
  --sample-days 2 `
  --timeout-sec 300 `
  --nas-internal-export-only `
  --jobs-out configs\mt5_candidate_validation_nas_export_only_jobs.json `
  --report-out logs\mt5_validation\candidate_validation_nas_export_only_manifest.json
```

Bu modda NAS preset override'larina sunlar eklenir:

```text
InpValidationInternalTradeExport=true
InpValidationInternalExportOnly=true
InpValidationExportFrom=<from>
InpValidationExportTo=<to>
```

Onemli:

- `InternalExportOnly=true` oldugunda EA native trade acmaz.
- Sadece internal trade-event CSV uretir.
- Bu hizlidir ve native execution yukunu azaltir.

## 4. Export-Only Job'lari Calistir

Tek job smoke icin:

```powershell
python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_nas_m5_export_only_smoke_job.json
```

Toplu export-only icin:

```powershell
python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_nas_export_only_jobs.json
```

Beklenen status:

```text
ok_internal_event_export
```

Beklenen artifact:

```text
NasV3Lab_InternalTradeEvents_<job>_<date>.csv
```

Internal event CSV kolonlari:

```text
job_id,build,symbol,chart_tf,signal_mode,sensitivity,rr_mode,hc_tp1,hc_tp2,
export_from,export_to,loaded_from,loaded_to,rates_copied,
fill_mode,same_bar_policy,spread_pts,slippage_pts,commission_per_lot,
signal_time,signal_bar_index,direction,signal_entry,signal_sl,risk,
tp1,tp2,final_tp,outcome,net_r,is_win,is_loss
```

## 5. Event Sample Native Job'lari Uret

Internal event CSV'lerinden native MT5 dogrulama job'lari uret:

```powershell
python scripts\build_mt5_event_sample_jobs.py `
  --source-jobs configs\mt5_candidate_validation_nas_export_only_jobs.json `
  --events "logs/mt5_validation/**/artifacts/*InternalTradeEvents*.csv" `
  --jobs-out configs\mt5_candidate_validation_event_sample_jobs.json `
  --report-out logs\mt5_validation\event_sample_manifest.json `
  --samples-per-export-job 5
```

Sampling mantigi:

- En kotu trade.
- En iyi trade.
- Ilk trade.
- Son trade.
- Zamana yayilmis ek event'ler.

Bu sayede orneklem uzayi kalite kontrol mantigina benzer:

- best-case
- worst-case
- edge-case
- random/distant samples
- farkli zaman bolumleri

## 6. Native MT5 Event Sample Job'larini Calistir

Tek job:

```powershell
python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_event_sample_one_job.json
```

Toplu event sample job:

```powershell
python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_event_sample_jobs.json
```

Beklenen artifactler:

```text
NasV3Lab_TesterTradeAudit_<date>.csv
NasV3Lab_InternalTradeEvents_<job>_<date>.csv
```

Tester trade audit kolonlari:

```text
job_id,engine,ea,build,symbol,timeframe,server_time,gmt_time,
deal,position_id,order,entry_type,deal_type,reason,magic,volume,
price,request_price,request_sl,request_tp,profit,swap,commission,fee,retcode,comment
```

## 7. Event Sample Comparison Calistir

Native deal audit ile internal event'i karsilastir:

```powershell
python scripts\compare_mt5_event_samples.py `
  --jobs configs\mt5_candidate_validation_event_sample_jobs.json `
  --report-out logs\mt5_validation\event_sample_comparison.csv
```

Tek job icin:

```powershell
python scripts\compare_mt5_event_samples.py `
  --jobs configs\mt5_candidate_validation_event_sample_one_job.json `
  --report-out logs\mt5_validation\event_sample_one_comparison.csv
```

Rapor ornek kolonlari:

```text
job_id
symbol
timeframe
sample_signal_time
sample_direction
sample_entry
sample_net_r
internal_match
internal_net_r
internal_outcome
native_entry_time
native_entry_price
native_entry_type
latency_min
entry_price_diff
status
```

Ornek sonuc:

```text
sample_signal_time=2026.04.07 12:25:00
sample_direction=BUY
sample_entry=24097.56
native_entry_time=2026.04.07 12:30:00
native_entry_price=24100.00
latency_min=5.0
entry_price_diff=2.44
status=ok
```

Yorum:

- Internal engine sinyali `12:25` barinda uretmis.
- Native EA trade'i `12:30`da acmis.
- Bu fark execution/timing farkidir.
- Pipeline artik bu farki hipotez olarak degil, olculmus veri olarak gosterir.

## 8. Compile ve Deploy

NAS EA patch sonrasi worker/live terminale deploy ornegi:

```powershell
$root='C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem'
$src="$root\IndicatorCodeExamples\NasUltimateEA.mq5"
$core="$root\IndicatorCodeExamples\NasUltimate_Core.mqh"
$worker="$root\.tmp\mt5_validation_exness_worker\MQL5\Experts"
$live='C:\MT5\DEMO\MQL5\Experts'
$terminalData='C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts'

Copy-Item -Force $src "$worker\NasUltimateEA.mq5"
Copy-Item -Force $core "$worker\NasUltimate_Core.mqh"

& "$root\.tmp\mt5_validation_exness_worker\MetaEditor64.exe" `
  /portable `
  /compile:"$worker\NasUltimateEA.mq5" `
  /log:"$root\logs\mt5_validation\compile_nas_validation_export.log"

Copy-Item -Force "$worker\NasUltimateEA.ex5" "$live\NasUltimateEA.ex5"
Copy-Item -Force "$worker\NasUltimateEA.ex5" "$terminalData\NasUltimateEA.ex5"
```

Basarili compile ciktisi:

```text
Result: 0 errors, 0 warnings
```

## 9. Onemli Tasarim Kurallari

### Calendar Window Kullanma

Rastgele gun araligi secmek dogrulama icin zayiftir.

Yanlis yaklasim:

```text
2026.04.01-2026.04.03 arasinda native test calistir.
```

Dogru yaklasim:

```text
Internal engine'in trade urettigi 2026.04.07 12:25 sinyalini native MT5 ile dogrula.
```

### Net R ile Net Profit Direkt Ayni Degil

Internal engine `R` bazinda olcer.

Native MT5:

- lot engine
- spread
- broker stop level
- commission
- tick model
- margin
- fill fiyati

ile gercek `profit` uretir.

Bu yuzden direkt kiyas:

```text
internal net_r == native net_profit
```

yanlistir.

Dogru kiyas:

- signal time ayni mi?
- direction ayni mi?
- entry zamani ne kadar gecikmis?
- entry price farki ne?
- native trade acilmis mi?
- exit nedeni TP/SL/manual/reverse olarak uyumlu mu?
- trade count benzer mi?

### Long Path Problemi

MT5 `/config:` path'i uzun olursa terminal config'i yukleyemeyebilir.

Log belirtisi:

```text
cannot load config "...very_long_path..." at start
```

Cozum:

- `scripts/mt5_validation_harness.py` filesystem pathlerinde kisa hash'li `fs_safe_id()` kullanir.
- `job_id` CSV icinde uzun kalabilir.
- Dosya/klasor adi kisa olmalidir.

### MQL FileOpen Dosya Adi Limiti

MQL `FileOpen()` cok uzun dosya adlarinda basarisiz olabilir.

Log belirtisi:

```text
NAS validation export failed: file open ...
```

Cozum:

- EA icinde `FileSafe()` dosya adini truncate eder.
- CSV icindeki `job_id` yine tam uzunlukta yazilir.

## 10. Current Support Matrix

NAS V3:

- Internal aggregate backtest: var.
- Tester trade audit: var.
- Internal trade-event export: var.
- Export-only mode: var.
- Event-sample native validation: var.
- Event comparison report: var.

ORB:

- Internal aggregate backtest: var.
- Tester trade audit: var.
- Event-sample pipeline icin internal trade-event export NAS seviyesinde henuz tamamlanmalidir.

ERL/IRL:

- Internal aggregate backtest: var.
- Tester trade audit: var.
- Event-sample pipeline icin internal trade-event export NAS seviyesinde henuz tamamlanmalidir.

Yeni stratejilerde hedef standart:

- Internal aggregate backtest CSV.
- Tester trade audit CSV.
- Internal trade-event export CSV.
- Export-only tester mode.
- Event-sample native validation compatibility.

## 11. Yeni Bir EA Icin Minimum Gereksinimler

Yeni EA yazarken bu pipeline'a uyumlu olmasi icin:

1. Internal brute-force summary CSV uret.
2. Tester modunda deal audit CSV uret.
3. Secili kombinasyon icin internal trade-event CSV uret.
4. Export-only mode ekle.
5. `InpValidationJobId` inputu ekle.
6. `InpValidationInternalTradeExport` inputu ekle.
7. `InpValidationInternalExportOnly` inputu ekle.
8. `InpValidationExportFrom` ve `InpValidationExportTo` inputlarini ekle.
9. CSV kolonlarinda `job_id`, `symbol`, `timeframe`, `signal_time`, `direction`, `signal_entry`, `signal_sl`, `net_r`, `outcome` mutlaka olsun.
10. Dosya adlari kisa tutulmali, ama CSV icindeki `job_id` tam yazilmali.

## 12. Hiz ve Disk Yonetimi

Native MT5 test pahalidir.

Bu yuzden:

- Once internal engine ile genis tarama yapilir.
- Native MT5 sadece secilmis event sample'lari dogrular.
- 20 haftalik full native test default yontem degildir.
- `InternalTradeEvents` CSV'leri trade-event bazlidir, tick bazli degildir; dosya boyutu kontrolludur.
- Buyuk generated klasorler commit edilmeden once gozden gecirilmelidir:
  - `.tmp/`
  - `logs/mt5_validation/`
  - `IndicatorCodeExamples/EaPresets/CandidateValidation/`
  - gecici `configs/mt5_candidate_validation_*`

## 13. Saglikli Sonuc Nasil Gorunur

Iyi dogrulama:

```text
status=ok
internal_match=1
latency_min makul
entry_price_diff aciklanabilir
native_entry_type internal direction ile ayni
```

Supheli dogrulama:

```text
missing_native_entry
internal_match=0
latency_min cok yuksek
entry_price_diff asiri buyuk
direction ters
native trade hic yok
```

Bu durumda kontrol sirasi:

1. Preset dogru mu?
2. Candidate combo inputlari native preset'e yazilmis mi?
3. `InpValidationJobId` ayni mi?
4. `InpValidationExportFrom/To` dogru mu?
5. Native tester sembol/timeframe dogru mu?
6. EA live execution bar kapanisinda mi, sinyal barinda mi islem aciyor?
7. Spread/stop-level/trading-window/risk-engine trade'i bloklamis mi?

## 14. En Kisa Smoke Akisi

Tek NAS sample icin hizli uctan uca test:

```powershell
python scripts\build_mt5_candidate_validation.py `
  --samples-per-candidate 1 `
  --sample-days 2 `
  --timeout-sec 300 `
  --nas-internal-export-only `
  --jobs-out configs\mt5_candidate_validation_nas_export_only_jobs.json `
  --report-out logs\mt5_validation\candidate_validation_nas_export_only_manifest.json

python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_nas_m5_export_only_smoke_job.json

python scripts\build_mt5_event_sample_jobs.py `
  --source-jobs configs\mt5_candidate_validation_nas_export_only_jobs.json `
  --events "logs/mt5_validation/**/artifacts/*InternalTradeEvents*.csv" `
  --jobs-out configs\mt5_candidate_validation_event_sample_smoke_jobs.json `
  --report-out logs\mt5_validation\event_sample_smoke_manifest.json `
  --samples-per-export-job 5

python scripts\mt5_validation_harness.py run `
  --jobs configs\mt5_candidate_validation_event_sample_one_job.json

python scripts\compare_mt5_event_samples.py `
  --jobs configs\mt5_candidate_validation_event_sample_one_job.json `
  --report-out logs\mt5_validation\event_sample_one_comparison.csv
```

Beklenen final cikti:

```text
logs/mt5_validation/event_sample_one_comparison.csv
```

Bu dosya internal engine ile MT5 native tester'in ayni trade event'i nasil gordugunu gosterir.

