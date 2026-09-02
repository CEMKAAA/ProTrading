$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $root 'IndicatorCodeExamples'
$files = @('OrbUltimateEA.mq5', 'A05OrbEA.mq5', 'A10OrbEA.mq5', 'N10OrbEA.mq5', 'Q10OrbEA.mq5')
$legacyHash = '75D74FAE839B9A7FEA86520B259E1EDB8AA514106047BBCE99EB2797EE2EF10A'
$legacyLifecycleHash = 'B66D04506FFF57F361AE28253C125A7C90C635A7AE434A018028ABA7B296AE3D'

function Assert-True($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Extract-Function([string]$source, [string]$signature) {
    $start = $source.IndexOf($signature)
    if ($start -lt 0) { throw "Function not found: $signature" }
    $brace = $source.IndexOf('{', $start)
    if ($brace -lt 0) { throw "Function body not found: $signature" }
    $depth = 0
    for ($i = $brace; $i -lt $source.Length; $i++) {
        if ($source[$i] -eq '{') { $depth++ }
        elseif ($source[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $source.Substring($start, $i - $start + 1) }
        }
    }
    throw "Unterminated function: $signature"
}

function Hash-Text([string]$value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

foreach ($file in $files) {
    $path = Join-Path $sourceRoot $file
    $source = [IO.File]::ReadAllText((Resolve-Path $path)).Replace("`r`n", "`n")
    Assert-True ($source.Contains('input bool InpAdvancedAuditEngineDefault = false;')) "$file advanced audit is not default-safe"
    Assert-True ($source.Contains('input bool InpAdvancedAuditPersistIndex = true;')) "$file persistent exact index is disabled"
    Assert-True ($source.Contains('input bool InpAdvancedAuditShadowParity = false;')) "$file shadow parity diagnostic is missing"
    Assert-True ($source.Contains('#include "OrbAdvancedAuditEngine.mqh"')) "$file advanced engine include is missing"
    Assert-True ($source.Contains('CreateButton("BTN_ADV_AUD"')) "$file dashboard engine toggle is missing"
    Assert-True ($source.Contains('else if(sparam==PREFIX+"BTN_ADV_AUD")')) "$file engine toggle handler is missing"
    Assert-True ($source.Contains('OrbAdvancedAuditLoadRuntime();')) "$file does not restore its per-chart engine selection"
    Assert-True ($source.Contains('OrbAdvancedAuditResetRunStats();')) "$file does not reset advanced run telemetry"
    Assert-True ($source.Contains('?SimulateHistoricalLifecycleAdvanced(entryT,te,g_histRunNow')) "$file dashboard audit does not dispatch to the advanced lifecycle"
    $advancedAt = $source.IndexOf('SimulateTradeTicksAdvanced(sigTime,tradeEnd')
    $legacyAt = $source.IndexOf('SimulateTradeTicks(sigTime,tradeEnd', $advancedAt)
    Assert-True ($advancedAt -ge 0 -and $legacyAt -gt $advancedAt) "$file has no fail-safe advanced-to-legacy adapter"

    $legacyBody = Extract-Function $source 'bool SimulateTradeTicks('
    Assert-True ((Hash-Text $legacyBody) -eq $legacyHash) "$file legacy exact replay body changed"
    $legacyLifecycle = Extract-Function $source 'HistResult SimulateHistoricalLifecycle('
    Assert-True ((Hash-Text $legacyLifecycle) -eq $legacyLifecycleHash) "$file legacy lifecycle body changed"
}

$engine = [IO.File]::ReadAllText((Resolve-Path (Join-Path $sourceRoot 'OrbAdvancedAuditEngine.mqh'))).Replace("`r`n", "`n")
foreach ($required in @(
    'AccountInfoString(ACCOUNT_SERVER)',
    'OrbAdvSafeToken(_Symbol)',
    'FileMove(temp,FILE_COMMON,target,FILE_COMMON|FILE_REWRITE)',
    'ulong OrbAdvBlocksChecksum()',
    'int OrbAdvFindCandidateNode(',
    'OrbAdvNodeCanSkip(',
    'CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO',
    'bool OrbAdvancedAuditEquivalent(',
    'OrbAdvClearLoadedDay();'
)) {
    Assert-True ($engine.Contains($required)) "Advanced engine invariant missing: $required"
}

Write-Output "ORB advanced exact audit isolation, persistence, segment-tree and frozen-legacy checks passed for $($files.Count) files."
