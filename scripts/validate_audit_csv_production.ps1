param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stageRoot=(Resolve-Path -LiteralPath $Stage).Path
if(!$stageRoot.StartsWith((Join-Path $root '.tmp')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Stage must be within workspace .tmp'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker busy'}
$items=@(@('Orb','orb/OrbUltimateEA_StrategyLibrary.mq5','g_histTotal'),@('Ma','macrossover_orb/MaCrossOverOrbEA.mq5','g_histTotal'),@('Sol','SolAdvanced/LiqNarrativeSol_Advanced.mq5','g_hist.total'))
$results=@()
foreach($item in $items){
 $live=Join-Path $root ('IndicatorCodeExamples/'+$item[1]);$staged=Join-Path $stageRoot $item[1]
 if((Get-FileHash $live).Hash -ne (Get-FileHash $staged).Hash){throw 'Source changed since compilation'}
 $name='CsvProduction'+$item[0]+'Probe'
 $probe=Join-Path $stageRoot ('tests/mql5/'+$name+'.mq5')
 New-Item -ItemType Directory -Path (Split-Path $probe) -Force | Out-Null
 $code=@'
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../ENTRY"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   g_axNotify=false;g_axSchedule=false;g_tcalPrefix="SCHEMA_PROBE_";
   g_tcalClockLabel="BROKER UTC0";AxReset();
   AxTrade t;ZeroMemory(t);t.signalTime=D'2026.09.20 11:55';t.availableTime=D'2026.09.20 12:00';
   t.entryTime=t.availableTime;t.localTime=t.entryTime;t.exitTime=t.entryTime+123;
   t.valid=true;t.closed=true;t.won=true;t.direction=1;t.rawDirection=1;
   t.entryClock=AxEntryClock(t.entryTime,EMPTY_VALUE);t.entry=100;t.sl=99;t.tp=101;t.exitPrice=101;t.netR=0.97;t.costR=0.03;
   t.outcome="TP";t.entrySpreadPoints=EMPTY_VALUE;t.spreadBasis="NOT_CAPTURED_BAR_MODEL";
   AxCapture(t);TOTAL=1;AxSealCurrent();AxIndicators();
   int file=FileOpen("NAME.txt",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file!=INVALID_HANDLE){FileWriteString(file,AxHeader()+"\r\n"+AxRow(0));FileClose(file);}
   AxReset();TCalDestroy();
}
'@
 $code=$code.Replace('ENTRY',$item[1]).Replace('TOTAL',$item[2]).Replace('NAME',$name)
 [IO.File]::WriteAllText($probe,$code,(New-Object Text.UTF8Encoding($false)))
 $log=$probe+'.log';$started=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(-not $p.WaitForExit(180000)){throw 'Production schema compile timeout'}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Production schema compile failed'}
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5')) -Force
 $ini=$probe+'.ini'
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1') | Set-Content $ini -Encoding ASCII
 $started=Get-Date
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(-not $p.WaitForExit(180000)){if($p.Path -eq $terminal){$p.Kill()};throw 'Production schema worker timeout'}
 $path=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
 if(!(Test-Path $path) -or (Get-Item $path).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh schema missing'}
 $row=Get-Content $path -Raw | ConvertFrom-Csv
 $properties=@($row.PSObject.Properties.Name)
 if(@($properties | Select-Object -Unique).Count -ne $properties.Count){throw 'Duplicate column names'}
 if($row.label_net_r -ne '0.970000000000' -or $row.entry_time -ne '2026.09.20 12:00:00'){throw 'Production adapter export value changed'}
 if(!$row.setting_time_matrix -or $row.label_duration_seconds -ne '123'){throw 'Production adapter metadata missing'}
 if($row.label_exit_reason -ne 'TP' -or $row.entry_time_basis -ne 'MODELED_BAR_TIME'){throw 'Production export reason/entry basis regression'}
 $results+=@{ea=$item[0];columns=$properties.Count;settings=@($properties|Where-Object {$_ -like 'setting_*'}).Count;net_r=$row.label_net_r;path=$path;compile='0 errors, 0 warnings'}
 Write-Output "$($item[0]): $($properties.Count) unique columns; timestamp, netR and settings preserved"
}
$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $stageRoot 'csv_production_schemas.json') -Encoding UTF8
