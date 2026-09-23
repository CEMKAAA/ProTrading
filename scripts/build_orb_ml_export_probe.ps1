$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sources = Join-Path $root 'IndicatorCodeExamples/orb'
$destination = Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
[IO.Directory]::CreateDirectory($destination) | Out-Null
# This generates an isolated script, not a deployable production EA. None of the
# trading EA's event handlers are registered or called by the script.
$source = [IO.File]::ReadAllText((Join-Path $sources 'OrbUltimateEA_StrategyLibrary.mq5'))
foreach ($handler in @('OnInit','OnDeinit','OnTick','OnTimer','OnChartEvent','OnTradeTransaction','OnTester')) {
    $source = [regex]::Replace($source, '\b' + $handler + '\s*\(', 'DisabledProbe_' + $handler + '(')
}
$source = $source.Replace('return (bool)MQLInfoInteger(MQL_TESTER);', 'return true;')
$skip = 'if(IsTesterMode()){CancelHistoricalAuditBuild();DeleteHist();g_histStatLine="tester_skip";return;}'
if (!$source.Contains($skip)) { throw 'Historical audit entry guard changed; review probe' }
$source = $source.Replace($skip, '// Script probe: permit historical calculations with tester I/O guards enabled.')
foreach ($name in @('InpEaEnabled','InpShowDashboard','InpAuditCsv','InpLogOnInit')) {
    $source = [regex]::Replace($source, '(input\s+bool\s+'+$name+'\s*=)\s*(?:true|false)', '$1 false')
}
$source += @'

void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)
   {Print("ORB_ML_EXPORT_PROBE REFUSED: isolated worker required");return;}
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;
   OrbStrategyPreset preset;
   if(!OrbStrategyPresetLoad(7,preset)){Print("ORB_ML_EXPORT_PROBE PRESET FAILED");return;}
   OrbStrategyPresetApplyValues(preset);g_strategyPresetIndex=7;g_strategyCandidateIndex=7;
   g_rtAdvancedAuditEngine=true;
   g_rtSlDistancePct=InpSlDistancePct;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;
   g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=InpBacktestSpreadPts>0?InpBacktestSpreadPts:(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   RegimeV3Update(true);
   if(!OrbMlStartExport()){Print("ORB_ML_EXPORT_PROBE START FAILED ",g_mlStatus);return;}
   g_mlFilePath="OrbMLTests\\"+g_mlDataset+".csv";
   ulong start=GetTickCount64(),lastReport=0;
   while(g_mlExport&&!IsStopped()&&GetTickCount64()-start<240000)
   {
      if(!g_histAuditRunning&&g_histCoveragePending&&TimeLocal()>=g_histCoverageNextRetry)
         QueueHistoricalRedraw(0);
      ProcessQueuedHistoricalRedraw();ProcessHistoricalAuditStep();OrbMlExportStep();
      if(GetTickCount64()-lastReport>10000)
      {Print("ORB_ML_EXPORT_PROBE PROGRESS ",g_mlStatus);lastReport=GetTickCount64();}
      Sleep(1);
   }
   if(g_mlExport)OrbMlAbort("PROBE TIMEOUT");
   Print("ORB_ML_EXPORT_PROBE FINISHED ",g_mlStatus," rows=",g_mlWritten,
      " total=",g_histTotal," sec=",(double)(GetTickCount64()-start)/1000.0,
      " path=",TerminalInfoString(TERMINAL_COMMONDATA_PATH),"\\Files\\",g_mlFilePath);
   EventKillTimer();
}
'@
[IO.File]::WriteAllText((Join-Path $destination 'OrbMLExportProbe.mq5'), $source, [Text.UTF8Encoding]::new($false))
# Recursively copy only quoted local includes, leaving the platform's Trade library alone.
$queue = [Collections.Generic.Queue[string]]::new()
$seen = [Collections.Generic.HashSet[string]]::new()
$queue.Enqueue('OrbUltimateEA_StrategyLibrary.mq5')
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $sources $file)), '#include\s+"([^"]+)"')) {
        $include = $match.Groups[1].Value
        if ($seen.Add($include)) {
            Copy-Item -LiteralPath (Join-Path $sources $include) -Destination (Join-Path $destination $include)
            $queue.Enqueue($include)
        }
    }
}
$ini = "[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbMLExportProbe\OrbMLExportProbe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $root 'tmp/orb_ml_probe/export.ini'), $ini)
Write-Output "Export probe generated: $destination (no registered EA lifecycle handlers)"
