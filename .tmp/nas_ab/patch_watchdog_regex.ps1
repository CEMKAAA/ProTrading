$p=(Resolve-Path 'IndicatorCodeExamples\NasUltimate_SATS_PartialNoBE_EA.mq5')
$s=[IO.File]::ReadAllText($p)
$old='uint     g_lastTpTouchWatchdogMs = 0;'
$new=@"
uint     g_lastTpTouchWatchdogMs = 0;

struct NasTpWatchdogRetryState
{
   ulong ticket;
   datetime nextRetry;
   uint lastRetcode;
};
NasTpWatchdogRetryState g_tpWatchdogRetryStates[];
"@.TrimEnd()
if(-not $s.Contains($old)){throw 'global anchor missing'}
$s=$s.Replace($old,$new)
$anchor='void EnforceManagedTpTouchClose(const bool force)'
$helpers=@"
int FindTpWatchdogRetryState(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_tpWatchdogRetryStates); ++i)
      if(g_tpWatchdogRetryStates[i].ticket == ticket)
         return i;
   return -1;
}

bool TpWatchdogRetryAllowed(const ulong ticket)
{
   int idx = FindTpWatchdogRetryState(ticket);
   return idx < 0 || TimeCurrent() >= g_tpWatchdogRetryStates[idx].nextRetry;
}

void ScheduleTpWatchdogRetry(const ulong ticket, const uint retcode)
{
   int idx = FindTpWatchdogRetryState(ticket);
   if(idx < 0)
   {
      idx = ArraySize(g_tpWatchdogRetryStates);
      ArrayResize(g_tpWatchdogRetryStates, idx + 1);
      g_tpWatchdogRetryStates[idx].ticket = ticket;
   }
   int delaySec = retcode == TRADE_RETCODE_MARKET_CLOSED ? 60 : 5;
   g_tpWatchdogRetryStates[idx].nextRetry = TimeCurrent() + delaySec;
   g_tpWatchdogRetryStates[idx].lastRetcode = retcode;
}

void ClearTpWatchdogRetry(const ulong ticket)
{
   int idx = FindTpWatchdogRetryState(ticket);
   if(idx < 0)
      return;
   int last = ArraySize(g_tpWatchdogRetryStates) - 1;
   if(idx != last)
      g_tpWatchdogRetryStates[idx] = g_tpWatchdogRetryStates[last];
   ArrayResize(g_tpWatchdogRetryStates, last);
}

"@
if(-not $s.Contains($anchor)){throw 'function anchor missing'}
if(-not $s.Contains('int FindTpWatchdogRetryState(')){$s=$s.Replace($anchor,$helpers+$anchor)}
$patterns=@(
 @('if\(!touched\)\s*\r?\n\s*continue;\s*\r?\n\s*\r?\n\s*string dirText', "if(!touched)`n         continue;`n      if(!TpWatchdogRetryAllowed(ticket))`n         continue;`n`n      string dirText"),
 @('if\(ok\)\s*\r?\n\s*break;\s*\r?\n\s*Print\("NAS SATS TP watchdog close attempt failed ticket=", ticket,\s*\r?\n\s*" attempt=", attempt,\s*\r?\n\s*" ret=", trade\.ResultRetcode\(\),\s*\r?\n\s*" ", trade\.ResultRetcodeDescription\(\)\);', "if(ok)`n            break;`n         uint retcode = trade.ResultRetcode();`n         Print(\"NAS SATS TP watchdog close attempt failed ticket=\", ticket,`n               \" attempt=\", attempt,`n               \" ret=\", retcode,`n               \" \", trade.ResultRetcodeDescription());`n         if(retcode == TRADE_RETCODE_MARKET_CLOSED)`n            break;"),
 @('if\(ok\)\s*\r?\n\s*\{\s*\r?\n\s*Print\("NAS SATS TP watchdog closed ticket=", ticket,', "if(ok)`n      {`n         ClearTpWatchdogRetry(ticket);`n         Print(\"NAS SATS TP watchdog closed ticket=\", ticket,"),
 @('else\s*\r?\n\s*\{\s*\r?\n\s*Print\("NAS SATS TP watchdog close failed ticket=", ticket,', "else`n      {`n         ScheduleTpWatchdogRetry(ticket, trade.ResultRetcode());`n         Print(\"NAS SATS TP watchdog close failed ticket=\", ticket,")
)
foreach($pair in $patterns){$before=$s; $s=[regex]::Replace($s,$pair[0],$pair[1],1); if($s -eq $before){throw "regex anchor missing: $($pair[0])"}}
[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding($false)))
