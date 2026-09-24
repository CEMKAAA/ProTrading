param([string]$ReportDir = 'reports/time_matrix_5y_20260924')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reports = (Resolve-Path (Join-Path $root $ReportDir)).Path
$culture = [Globalization.CultureInfo]::InvariantCulture

function MqlText([string]$value) {
    if ($null -eq $value) { return '' }
    $slash = [string][char]92
    $quote = [string][char]34
    return $value.Replace($slash, $slash + $slash).Replace($quote, $slash + $quote).Replace("`r", ' ').Replace("`n", ' ')
}

function Number([object]$value) {
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return '0' }
    $parsed = [double]::Parse([string]$value, $culture)
    return $parsed.ToString('0.############', $culture)
}

function SolClosedDrawdown([string]$symbol, [string]$path) {
    $file = Join-Path $reports "soladvanced_${symbol}_trades.csv"
    if (-not (Test-Path -LiteralPath $file)) { return 0.0 }
    $series = Import-Csv -LiteralPath $file | Where-Object {
        $_.path -eq $path -and $_.valid -eq '1' -and $_.closed -eq '1'
    } | Sort-Object { [long]$_.exit_time }, { [long]$_.available_time }
    $equity = 0.0; $peak = 0.0; $worst = 0.0
    foreach ($trade in $series) {
        $equity += [double]::Parse($trade.net_r, $culture)
        $peak = [Math]::Max($peak, $equity)
        $worst = [Math]::Max($worst, $peak - $equity)
    }
    return $worst
}

$families = @(
    @{ Prefix = 'orb_current'; Target = 'IndicatorCodeExamples/orb/ResearchFiveYearData.mqh'; Id = 'strategy_id'; Name = 'name' },
    @{ Prefix = 'macross'; Target = 'IndicatorCodeExamples/macrossover_orb/ResearchFiveYearData.mqh'; Id = 'strategy_id'; Name = 'name' },
    @{ Prefix = 'soladvanced'; Target = 'IndicatorCodeExamples/SolAdvanced/ResearchFiveYearData.mqh'; Id = 'path'; Name = 'strategy' }
)

foreach ($family in $families) {
    $prefix = $family.Prefix
    $baseFiles = @(Get-ChildItem -LiteralPath $reports -Filter "${prefix}_*_5y.csv" |
        Where-Object { $_.Name -cmatch "^${prefix}_[A-Z][A-Za-z0-9]*_5y\.csv$" } | Sort-Object Name)
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($baseFile in $baseFiles) {
        $symbol = $baseFile.BaseName.Substring($prefix.Length + 1)
        $symbol = $symbol.Substring(0, $symbol.Length - 3)
        $selectedFile = Join-Path $reports "${prefix}_${symbol}_time_matrix.csv"
        $selected = @{}
        if (Test-Path -LiteralPath $selectedFile) {
            foreach ($row in @(Import-Csv -LiteralPath $selectedFile)) {
                $selected[[string]$row.($family.Id)] = $row
            }
        }
        foreach ($row in @(Import-Csv -LiteralPath $baseFile.FullName)) {
            $id = [string]$row.($family.Id)
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $choice = $selected[$id]
            $dd = if ($prefix -eq 'soladvanced') { SolClosedDrawdown $symbol $id } else { [Math]::Abs([double]::Parse($row.max_peak_dd_r, $culture)) }
            $items.Add([pscustomobject]@{
                Id = $id; Name = [string]$row.($family.Name); Symbol = $symbol
                BaseStatus = [string]$row.status; BaseN = [int]$row.total
                BaseW = [int]$row.wins; BaseL = [int]$row.losses; BaseO = [int]$row.open
                BaseR = [string]$row.net_r; BaseDd = [string]$dd.ToString('0.############', $culture)
                SelectedStatus = if ($choice) { [string]$choice.status } else { 'NOT_EVALUATED' }
                TargetR = if ($choice) { [string]$choice.target_r } else { '0' }
                Picks = if ($choice) { [int]$choice.picked_hours } else { 0 }
                SelectedN = if ($choice) { [int]$choice.five_year_total } else { 0 }
                SelectedR = if ($choice) { [string]$choice.five_year_net_r } else { '0' }
                OosN = if ($choice) { [int]$choice.oos_two_year_n } else { 0 }
                OosR = if ($choice) { [string]$choice.oos_two_year_net_r } else { '0' }
            })
        }
    }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('#ifndef RESEARCH_FIVE_YEAR_DATA_MQH')
    $lines.Add('#define RESEARCH_FIVE_YEAR_DATA_MQH')
    $lines.Add('// Frozen research snapshot: closed-trade results from the 2026-09-24 260-week campaign.')
    $lines.Add('// Rebuild this header after editing any saved strategy. No live-trading decisions depend on it.')
    $lines.Add('struct ResearchFiveYearRow { string id,name,symbol,baseStatus,selectedStatus; int baseN,baseW,baseL,baseO,picks,selectedN,oosN; double baseR,baseDd,targetR,selectedR,oosR; };')
    $lines.Add("int ResearchFiveYearCount(){return $($items.Count);}")
    $lines.Add('bool ResearchFiveYearLoad(int index,ResearchFiveYearRow &r)')
    $lines.Add('{')
    $lines.Add('   switch(index)')
    $lines.Add('   {')
    for ($i = 0; $i -lt $items.Count; $i++) {
        $v = $items[$i]
        $lines.Add(('      case {0}: r.id="{1}";r.name="{2}";r.symbol="{3}";r.baseStatus="{4}";r.selectedStatus="{5}";r.baseN={6};r.baseW={7};r.baseL={8};r.baseO={9};r.baseR={10};r.baseDd={11};r.targetR={12};r.picks={13};r.selectedN={14};r.selectedR={15};r.oosN={16};r.oosR={17};return true;' -f
            $i,(MqlText $v.Id),(MqlText $v.Name),(MqlText $v.Symbol),(MqlText $v.BaseStatus),(MqlText $v.SelectedStatus),
            $v.BaseN,$v.BaseW,$v.BaseL,$v.BaseO,(Number $v.BaseR),(Number $v.BaseDd),(Number $v.TargetR),
            $v.Picks,$v.SelectedN,(Number $v.SelectedR),$v.OosN,(Number $v.OosR)))
    }
    $lines.Add('   }')
    $lines.Add('   return false;')
    $lines.Add('}')
    $lines.Add('#endif')
    $destination = Join-Path $root $family.Target
    [IO.File]::WriteAllLines($destination, $lines, (New-Object Text.UTF8Encoding $false))
    Write-Host "$prefix rows=$($items.Count) -> $destination"
}
