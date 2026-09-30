#ifndef AUDIT_TICK_READ_GUARD_MQH
#define AUDIT_TICK_READ_GUARD_MQH
ulong g_auditTickReadFailures=0;
bool AuditTickReadComplete(int count,int error){return count>=0&&error==0;}
int AuditCopyTicksRange(string symbol,MqlTick &ticks[],uint flags,ulong fromMs,ulong toMs)
{
   ResetLastError();
   int count=CopyTicksRange(symbol,ticks,flags,fromMs,toMs);
   int error=GetLastError();
   // Timeout can return a positive but incomplete count. Never cache it as complete.
   if(!AuditTickReadComplete(count,error))
   {g_auditTickReadFailures++;ArrayResize(ticks,0);return -1;}
   return count;
}
#endif
