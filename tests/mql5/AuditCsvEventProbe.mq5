#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/TradeCalendarMatrix.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/AuditTradeCsv.mqh"
string AxSignalFeatureHeader(){return "f_test_causal";}
string AxSignalFeatures(datetime at,datetime signalBar,int direction){return "\"1\"";}
ulong probeStarted=0;
int events=0;
bool launched=false;
int OnInit()
{
   g_axNotify=false;g_tcalPrefix="CSV_EVENT_PROBE_";g_tcalClockLabel="BROKER";
   probeStarted=GetTickCount64();EventSetMillisecondTimer(100);return INIT_SUCCEEDED;
}
void Finish(bool ok,string why)
{
   int f=FileOpen("AuditCsvEventProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,"success="+(string)ok+" events="+(string)events+" rows="+(string)g_axIndex+" reason="+why+"\n");
   FileWriteString(f,"csv="+TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+g_axPath+"\n");FileClose(f);
   EventKillTimer();TerminalClose(0);
}
void OnTimer()
{
   AxTimer();
   if(GetTickCount64()-probeStarted>120000){Finish(false,"timeout");return;}
   if(!launched)
   {
      MqlRates r[];ArraySetAsSeries(r,true);
      if(CopyRates(_Symbol,PERIOD_M5,1,64,r)!=64)return;
      AxReset();
      for(int i=63;i>=0;i--)
      {
         // Permuted entry clocks exercise sorting and restoring original row order.
         int j=(i*17)%64;
         AxTrade t;ZeroMemory(t);t.signalTime=r[j].time;t.availableTime=r[j].time+300;t.entryTime=t.availableTime;t.localTime=t.entryTime;
         t.direction=i%2!=0?1:-1;t.rawDirection=t.direction;t.valid=true;t.closed=true;t.won=i%3!=0;t.netR=t.won?1:-1;
         t.entry=r[j].close;t.sl=t.entry-t.direction;t.tp=t.entry+t.direction;t.exitPrice=t.won?t.tp:t.sl;
         t.exitTime=t.entryTime+60;t.entryClock="SYNTHETIC_PROBE";t.entrySpreadPoints=r[j].spread;t.spreadBasis="BAR_MODEL_NOT_TICK";
         t.outcome=t.won?"TP":"SL";t.signalFeatures="\"1\"";AxCapture(t);
      }
      AxSeal("CsvEventProbe","Event scheduling",PERIOD_M5,r[0].time+600,"setting_fixture","\"true\"");
      launched=true;if(!AxStart())Finish(false,g_tcalCsvStatus);return;
   }
   if(!g_axBusy)Finish(events>0&&g_axIndex==64&&FileIsExist(g_axPath,FILE_COMMON),g_tcalCsvStatus);
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{if(id==CHARTEVENT_CUSTOM+AX_EVENT)events++;AxEvent(id,lparam);}
void OnDeinit(const int reason){EventKillTimer();AxAbort("probe end");TCalDestroy();}
