$utf=New-Object Text.UTF8Encoding($false)
$root=Join-Path $PWD 'IndicatorCodeExamples'
Copy-Item (Join-Path $root 'AuditTickReadGuard.mqh') (Join-Path $root 'macrossover_orb/AuditTickReadGuard.mqh')
foreach($r in @('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5')){
$p=Join-Path $root $r;$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('#include "OrbAdvancedAuditEngine.mqh"','#include "AuditTickReadGuard.mqh"'+"`r`n"+'#include "OrbAdvancedAuditEngine.mqh"')
# Only audit-range reads, not signal calculation or live execution.
$s=$s.Replace('loaded=CopyTicksRange(', 'loaded=AuditCopyTicksRange(').Replace('int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,fromMs,toMs);','int copied=AuditCopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,fromMs,toMs);')
$s=$s.Replace('      if(loaded<=0)', '      if(loaded<0){ClearHistoricalTickReplayCache();return false;}'+"`r`n"+'      if(loaded<=0)')
$s=[regex]::Replace($s,'(HistResult SimulateTrade\(.*?forcedExitOutcome=""\)\s*\{)', '$1'+"`r`n"+'   ulong tickReadFailures=g_auditTickReadFailures;', [Text.RegularExpressions.RegexOptions]::Singleline)
$s=$s.Replace('   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();'+"`r`n"+'   MqlRates r[];int c=CopyRates', '   if(g_auditTickReadFailures!=tickReadFailures){res.valid=false;res.invalidReason="TICK_HISTORY_PENDING";res.netR=0;res.isWin=false;return res;}'+"`r`n"+'   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();'+"`r`n"+'   MqlRates r[];int c=CopyRates')
[IO.File]::WriteAllText($p,$s,$utf)
}
foreach($r in @('OrbAdvancedAuditEngine.mqh','macrossover_orb/OrbAdvancedAuditEngine.mqh')){
$p=Join-Path $root $r;$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('CopyTicksRange(', 'AuditCopyTicksRange(')
# Include here too for stand-alone compile probes.
$s='#include "AuditTickReadGuard.mqh"'+"`r`n"+$s
$needle='   if(!SimulateTradeTicksAdvanced(entryTime,horizon,entry,sl,isBuy,halfBeLeg,scheduledEndReached,'
$s=$s.Replace($needle,'   ulong tickReadFailures=g_auditTickReadFailures;'+"`r`n"+$needle)
$s=$s.Replace('      return SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,'+"`r`n"+'         usedEnd,forcedExitTime,forcedExitOutcome);'+"`r`n"+'   usedEnd=horizon;', '   {'+"`r`n"+'      if(g_auditTickReadFailures!=tickReadFailures){advanced.valid=false;advanced.invalidReason="TICK_HISTORY_PENDING";advanced.netR=0;advanced.isWin=false;usedEnd=horizon;return advanced;}'+"`r`n"+'      return SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome);'+"`r`n"+'   }'+"`r`n"+'   usedEnd=horizon;')
# LF sources as well handled below separately if needed.
[IO.File]::WriteAllText($p,$s,$utf)
}
