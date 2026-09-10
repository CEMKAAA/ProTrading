$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$frozen=Join-Path $root 'logs/OrbMLCampaign_20260909_v3/compiled_sources'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLPriorFive'
$report=Join-Path $root 'logs/OrbMLPriorFive_20260910'
[IO.Directory]::CreateDirectory($dest)|Out-Null
[IO.Directory]::CreateDirectory($report)|Out-Null
$source=[IO.File]::ReadAllText((Join-Path $frozen 'OrbMLCampaign.mq5'))
# Frozen, no-order campaign clone. Only the observation time and artifact namespace change.
$source=$source.Replace('OrbMLCampaign_20260909_v3','OrbMLPriorFive_20260910')
$source=$source.Replace("D'2026.09.09 00:00:00'","D'2021.09.09 00:00:00'")
$source=$source.Replace('CopyRates(_Symbol,tf,0,MathMax(20,barsToCopy),rates)',"CopyRates(_Symbol,tf,D'2021.09.09 00:00:00',MathMax(20,barsToCopy),rates)")
$source=$source.Replace('frozen cutoff 2026.09.09 00:00 broker','frozen cutoff 2021.09.09 00:00 broker; density-valid results require separate coverage mask')
$source=$source.Replace('   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;', '   if(_Symbol!="USDJPYm")return; g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;')
[IO.File]::WriteAllText((Join-Path $dest 'OrbMLPriorFive.mq5'),$source,[Text.UTF8Encoding]::new($false))
foreach($f in Get-ChildItem -LiteralPath $frozen -Filter '*.mqh'){
    $text=[IO.File]::ReadAllText($f.FullName).Replace('OrbMLCampaign_20260909_v3','OrbMLPriorFive_20260910')
    if($f.Name -eq 'LiqNarrativeSol_RegimeV3.mqh'){
        # Request the same number of daily warmup bars at the historical as-of,
        # not at today's terminal date. No feature or regime formula changes.
        $text=$text.Replace('CopyRates(_Symbol, PERIOD_D1, 0, requested, d1)',"CopyRates(_Symbol, PERIOD_D1, D'2021.09.09 00:00:00', requested, d1)")
        $text=$text.Replace('datetime until = TimeCurrent() + 86400;',"datetime until = D'2021.09.09 00:00:00' + 86400;")
    }
    [IO.File]::WriteAllText((Join-Path $dest $f.Name),$text,[Text.UTF8Encoding]::new($false))
}
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbMLPriorFive\OrbMLPriorFive`r`nSymbol=USDJPYm`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $report 'export.ini'),$ini)
Write-Output 'Frozen USDJPY prior-period exporter generated; production files untouched'
