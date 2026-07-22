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
$oldTouch=@"
      if(!touched)
         continue;

      string dirText = direction > 0 ? "BUY" : "SELL";
"@
$newTouch=@"
      if(!touched)
         continue;
      if(!TpWatchdogRetryAllowed(ticket))
         continue;

      string dirText = direction > 0 ? "BUY" : "SELL";
"@
if(-not $s.Contains($oldTouch)){throw 'touch anchor missing'}
$s=$s.Replace($oldTouch,$newTouch)
$oldAttempt=@"
         if(ok)
            break;
         Print("NAS SATS TP watchdog close attempt failed ticket=", ticket,
               " attempt=", attempt,
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
"@
$newAttempt=@"
         if(ok)
            break;
         uint retcode = trade.ResultRetcode();
         Print("NAS SATS TP watchdog close attempt failed ticket=", ticket,
               " attempt=", attempt,
               " ret=", retcode,
               " ", trade.ResultRetcodeDescription());
         if(retcode == TRADE_RETCODE_MARKET_CLOSED)
            break;
"@
if(-not $s.Contains($oldAttempt)){throw 'attempt anchor missing'}
$s=$s.Replace($oldAttempt,$newAttempt)
$oldSuccess=@"
      if(ok)
      {
         Print("NAS SATS TP watchdog closed ticket=", ticket,
"@
$newSuccess=@"
      if(ok)
      {
         ClearTpWatchdogRetry(ticket);
         Print("NAS SATS TP watchdog closed ticket=", ticket,
"@
if(-not $s.Contains($oldSuccess)){throw 'success anchor missing'}
$s=$s.Replace($oldSuccess,$newSuccess)
$oldFail=@"
      else
      {
         Print("NAS SATS TP watchdog close failed ticket=", ticket,
"@
$newFail=@"
      else
      {
         ScheduleTpWatchdogRetry(ticket, trade.ResultRetcode());
         Print("NAS SATS TP watchdog close failed ticket=", ticket,
"@
if(-not $s.Contains($oldFail)){throw 'failure anchor missing'}
$s=$s.Replace($oldFail,$newFail)
[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding($false)))
