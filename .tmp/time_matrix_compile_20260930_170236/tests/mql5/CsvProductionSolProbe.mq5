#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   g_axNotify=false;g_axSchedule=false;g_tcalPrefix="SCHEMA_PROBE_";
   g_tcalClockLabel="BROKER UTC0";AxReset();
   AxTrade t;ZeroMemory(t);t.signalTime=D'2026.09.20 11:55';t.availableTime=D'2026.09.20 12:00';
   t.entryTime=t.availableTime;t.localTime=t.entryTime;t.exitTime=t.entryTime+123;
   t.valid=true;t.closed=true;t.won=true;t.direction=1;t.rawDirection=1;
   t.entryClock="AUDIT_FILL";t.entry=100;t.sl=99;t.tp=101;t.exitPrice=101;t.netR=0.97;t.costR=0.03;
   t.outcome="TP";t.entrySpreadPoints=EMPTY_VALUE;t.spreadBasis="NOT_CAPTURED_BAR_MODEL";
   AxCapture(t);g_hist.total=1;AxSealCurrent();AxIndicators();
   int file=FileOpen("CsvProductionSolProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file!=INVALID_HANDLE){FileWriteString(file,AxHeader()+"\r\n"+AxRow(0));FileClose(file);}
   AxReset();TCalDestroy();
}