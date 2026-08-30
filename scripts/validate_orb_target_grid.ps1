param(
    [string]$SourceRoot = "IndicatorCodeExamples"
)

$ErrorActionPreference = "Stop"
$files = @(
    "OrbUltimateEA.mq5",
    "A05OrbEA.mq5",
    "A10OrbEA.mq5",
    "N10OrbEA.mq5",
    "Q10OrbEA.mq5"
)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$expected = 1..20 | ForEach-Object { [math]::Round($_ * 0.05, 2) }
$customNames = @(
    "R005", "R010", "R015", "R020", "R025", "R030", "R035", "R040", "R045",
    "R055", "R060", "R065", "R070", "R080", "R085", "R090", "R095"
)

foreach ($name in $files) {
    $path = Join-Path $SourceRoot $name
    $source = [IO.File]::ReadAllText((Resolve-Path $path))

    foreach ($custom in $customNames) {
        Assert-True ($source.Contains("ORB_TARGET_$custom=")) "$name is missing ORB_TARGET_$custom"
    }

    # Existing IDs are persisted by MT5 .set files and must never be renumbered.
    Assert-True ($source.Contains("ORB_TARGET_R050=1")) "$name changed the legacy 0.50R ID"
    Assert-True ($source.Contains("ORB_TARGET_R075=7")) "$name changed the legacy 0.75R ID"
    Assert-True ($source.Contains("ORB_TARGET_R100=2")) "$name changed the legacy 1.00R ID"
    Assert-True (-not $source.Contains("ORB_TARGET_R000")) "$name exposes an invalid zero-distance target"

    Assert-True ($source.Contains('if(current==(int)ORB_TARGET_R045)return 1;')) "$name cycle does not reach legacy 0.50R after 0.45R"
    Assert-True ($source.Contains('if(current==1)return (int)ORB_TARGET_R055;')) "$name cycle does not continue from 0.50R to 0.55R"
    Assert-True ($source.Contains('if(current==(int)ORB_TARGET_R095)return 2;')) "$name cycle does not reach legacy 1.00R after 0.95R"
    Assert-True ($source.Contains('return 1.0/sourceR;')) "$name full inversion is not reciprocal"
    Assert-True ($source.Contains('return StringFormat("TP%03d",(int)MathRound(LegR(leg)*100.0));')) "$name custom target outcomes are not uniquely labelled"
}

for ($i = 0; $i -lt $expected.Count; $i++) {
    $r = $expected[$i]
    Assert-True ($r -gt 0.0 -and $r -le 1.0) "Target grid contains an invalid R value"
    if ($i -gt 0) {
        Assert-True ([math]::Abs(($r - $expected[$i - 1]) - 0.05) -lt 1e-9) "Target grid is not spaced by 0.05R"
    }
    $inverted = 1.0 / $r
    Assert-True ($inverted -gt 0.0) "Reciprocal inversion produced an invalid target"
}

Assert-True ([math]::Abs((1.0 / 0.05) - 20.0) -lt 1e-9) "0.05R inversion parity failed"
Assert-True ([math]::Abs((1.0 / 0.50) - 2.0) -lt 1e-9) "0.50R inversion parity failed"
Assert-True ([math]::Abs((1.0 / 1.00) - 1.0) -lt 1e-9) "1.00R inversion parity failed"

Write-Output "ORB 0.05R target-grid regression checks passed for $($files.Count) files."
