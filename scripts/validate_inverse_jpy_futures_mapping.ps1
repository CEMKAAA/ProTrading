param(
    [string]$NinjaCore = "IndicatorCodeExamples/NinjaTrader/ProductionFileBridgeNinjaCore.cs",
    [string]$QuantowerCore = "IndicatorCodeExamples/Quantower/ProductionFileBridgeQuantowerCore.cs"
)

$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Map-Level([double]$LiveEntry, [double]$SourceEntry, [double]$SourceLevel) {
    return $LiveEntry * $SourceEntry / $SourceLevel
}

foreach ($path in @($NinjaCore, $QuantowerCore)) {
    $source = [IO.File]::ReadAllText((Resolve-Path $path))
    Assert-True $source.Contains('AutoInverseJpyQuoteMapping') "$path has no explicit inverse-quote guard"
    Assert-True ($source.Contains('sig.Direction = -sig.Direction') -or $source.Contains('signal.Direction = -signal.Direction')) "$path does not flip USDJPY direction"
    Assert-True $source.Contains('liveEntry * oldEntry / oldSl') "$path does not reciprocally map SL"
    Assert-True $source.Contains('liveEntry * oldEntry / oldTp') "$path does not reciprocally map TP"
    Assert-True $source.Contains('liveEntry * oldEntry / oldHalf') "$path does not reciprocally map HCBE"
    Assert-True $source.Contains('USDJPY_TO_JPYUSD') "$path does not audit inverse conversion"
    Assert-True $source.Contains('JPYFX') "$path has no USDJPY/6J canonical family"
    Assert-True ($source.Contains('"6J"') -and $source.Contains('"MJY"') -and $source.Contains('"J7"')) "$path does not recognize standard, micro, and E-mini JPY/USD futures"
    Assert-True (-not $source.Contains('master == "M6J"') -and -not $source.Contains('root == "M6J"')) "$path incorrectly treats delisted USD/JPY M6J as inverse JPY/USD"
    if ($path -like '*Ninja*') {
        Assert-True ($source.IndexOf('if (source == "J7") return "JPYFX";', [StringComparison]::Ordinal) -lt $source.IndexOf('while (source.Length > 0 && char.IsDigit', [StringComparison]::Ordinal)) "$path strips the J7 product digit before canonicalization"
    }
}

# USDJPY BUY must become a JPY/USD futures SELL.
$sourceEntry = 150.00
$sourceSl = 149.00
$sourceTp = 152.00
$sourceHalf = 151.00
$liveFuturesEntry = 0.0067000
$mappedSl = Map-Level $liveFuturesEntry $sourceEntry $sourceSl
$mappedTp = Map-Level $liveFuturesEntry $sourceEntry $sourceTp
$mappedHalf = Map-Level $liveFuturesEntry $sourceEntry $sourceHalf
Assert-True ($mappedSl -gt $liveFuturesEntry) "USDJPY BUY mapped SL is not above JPY/USD SELL entry"
Assert-True ($mappedTp -lt $liveFuturesEntry) "USDJPY BUY mapped TP is not below JPY/USD SELL entry"
Assert-True ($mappedHalf -lt $liveFuturesEntry -and $mappedHalf -gt $mappedTp) "USDJPY BUY mapped HCBE is outside the profit path"

# USDJPY SELL must become a JPY/USD futures BUY.
$sourceSl = 151.00
$sourceTp = 148.00
$sourceHalf = 149.00
$mappedSl = Map-Level $liveFuturesEntry $sourceEntry $sourceSl
$mappedTp = Map-Level $liveFuturesEntry $sourceEntry $sourceTp
$mappedHalf = Map-Level $liveFuturesEntry $sourceEntry $sourceHalf
Assert-True ($mappedSl -lt $liveFuturesEntry) "USDJPY SELL mapped SL is not below JPY/USD BUY entry"
Assert-True ($mappedTp -gt $liveFuturesEntry) "USDJPY SELL mapped TP is not above JPY/USD BUY entry"
Assert-True ($mappedHalf -gt $liveFuturesEntry -and $mappedHalf -lt $mappedTp) "USDJPY SELL mapped HCBE is outside the profit path"

Write-Output "USDJPY -> 6J/MJY/J7 inverse direction and reciprocal geometry checks passed."
