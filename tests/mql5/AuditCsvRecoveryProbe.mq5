#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/TradeCalendarMatrix.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/AuditTradeCsv.mqh"
string AxSignalFeatureHeader(){return "f_test_causal";}
string AxSignalFeatures(datetime at,datetime signalBar,int direction){return "\"1\"";}
ulong begun=0;
bool launched=false,injected=false,sawWaiting=false;
int events=0;
void Finish(bool ok,string reason)
{
   int file=FileOpen("AuditCsvRecoveryProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(file,"success="+(string)ok+" waited="+(string)sawWaiting+" injected="+(string)injected
      +" events="+(string)events+" rows="+(string)g_axIndex+" reason="+reason+"\n");
   FileWriteString(file,"csv="+TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+g_axPath+"\n");
   FileClose(file);EventKillTimer();TerminalClose(0);
}
int OnInit()
{
   if(StringFind(_Symbol,"AXCSV_")!=0)return INIT_FAILED;
   g_axNotify=false;g_tcalPrefix="CSV_RECOVERY_";begun=GetTickCount64();
   EventSetMillisecondTimer(100);return INIT_SUCCEEDED;
}
void OnTimer()
{
   if(GetTickCount64()-begun>120000){Finish(false,"timeout");return;}
   if(!launched)
   {
      AxReset();
      for(int i=0;i<64;i++)
      {
         AxTrade t;ZeroMemory(t);t.entryTime=D'2026.09.14 12:00'+((i*17)%64)*300;
         t.signalTime=t.entryTime-300;t.availableTime=t.entryTime;t.localTime=t.entryTime;
         t.valid=true;t.closed=true;t.won=i%3!=0;t.direction=1;t.rawDirection=1;
         t.entry=1.1;t.sl=1.099;t.tp=1.101;t.exitPrice=t.won?t.tp:t.sl;
         t.netR=t.won?1:-1;t.exitTime=t.entryTime+60;t.outcome=t.won?"TP":"SL";
         t.entryClock="SYNTHETIC_FIXTURE";t.entrySpreadPoints=2;t.spreadBasis="SYNTHETIC_FIXTURE";
         AxCapture(t);
      }
      AxSeal("CsvRecoveryProbe","Synthetic recovery only",PERIOD_M5,D'2026.09.15',"setting_fixture","\"true\"");
      launched=true;if(!AxStart())Finish(false,g_tcalCsvStatus);return;
   }
   if(g_axRetryAt>0&&g_axIndex==0)sawWaiting=true;
   if(sawWaiting&&!injected)
   {
      MqlRates rates[];int count=45*1440;ArrayResize(rates,count);
      for(int i=0;i<count;i++)
      {
         ZeroMemory(rates[i]);rates[i].time=D'2026.08.01'+i*60;
         rates[i].close=1.1+0.002*MathSin(i*0.013)+i*0.00000001;
         rates[i].open=rates[i].close-0.0001;rates[i].high=rates[i].close+0.0003;rates[i].low=rates[i].open-0.0003;
         rates[i].tick_volume=100+i%37;rates[i].spread=2;
      }
      injected=CustomRatesUpdate(_Symbol,rates)==count;
      if(!injected){Finish(false,"fixture injection failed");return;}
   }
   AxTimer();
   if(!g_axBusy)Finish(sawWaiting&&injected&&g_axIndex==64&&g_axMissing==0&&g_axMissingRolling==0
      &&g_axMissingMtf==0&&g_axMissingKiv==0,g_tcalCsvStatus);
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{if(id==CHARTEVENT_CUSTOM+AX_EVENT)events++;AxEvent(id,lparam);}
void OnDeinit(const int reason){EventKillTimer();AxAbort("probe end");TCalDestroy();}
