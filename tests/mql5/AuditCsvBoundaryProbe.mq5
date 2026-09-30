#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/TradeCalendarMatrix.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/AuditTradeCsv.mqh"
string AxSignalFeatureHeader(){return "f_boundary_fixture";}
string AxSignalFeatures(datetime at,datetime signalBar,int direction){return "\"1\"";}
int checks=0,failed=0;
string findings="";
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("BOUNDARY_FAIL ",label);}}
int Cells(string text,string &values[])
{
   ArrayFree(values);bool quote=false;string value="";
   for(int i=0;i<StringLen(text);i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(c=='"')
      {if(quote&&i+1<StringLen(text)&&StringGetCharacter(text,i+1)=='"'){value+="\"";i++;}else quote=!quote;}
      else if(c==','&&!quote){int n=ArraySize(values);ArrayResize(values,n+1);values[n]=value;value="";}
      else if(c!='\r'&&c!='\n')value+=ShortToString(c);
   }
   int n=ArraySize(values);ArrayResize(values,n+1);values[n]=value;return n+1;
}
int Col(const string &names[],string name)
{for(int i=0;i<ArraySize(names);i++)if(names[i]==name)return i;return -1;}
void OnStart()
{
   g_axNotify=false;g_axSchedule=false;g_tcalPrefix="BOUNDARY_TEST_";
   g_tcalClockLabel="BROKER UTC0";
   string names[],values[];Cells(AxRollingNames(),names);
   MqlRates r[];ArrayResize(r,121);ArraySetAsSeries(r,true);
   for(int series=0;series<3;series++)
   {
      for(int j=0;j<121;j++)
      {
         ZeroMemory(r[j]);r[j].close=1000+(series==0?-j:series==1?j:0);
         r[j].open=r[j].close-0.5;r[j].high=r[j].close+1;r[j].low=r[j].close-1;
         r[j].tick_volume=100;r[j].spread=3;
      }
      int windows[4]={5,20,60,120};
      for(int w=0;w<4;w++)
      {
         int n=windows[w];Check(Cells(AxRollingValues(r,n),values)==32,"rolling field width");
         Check(MathAbs(StringToDouble(values[Col(names,"return")])-(r[0].close/r[n].close-1))<1e-10,"rolling return");
         Check(MathAbs(StringToDouble(values[Col(names,"linear_slope")])-(series==0?1:series==1?-1:0))<1e-10,"slope direction");
         Check(MathAbs(StringToDouble(values[Col(names,"efficiency")])-(series==2?0:1))<1e-10,"path efficiency");
         Check(StringToDouble(values[Col(names,"tick_volume_mean")])==100,"volume mean");
         Check(StringToDouble(values[Col(names,"spread_mean_points")])==3,"spread units");
         Check(StringToDouble(values[Col(names,"spread_max_points")])==3,"max spread");
         if(series==2)
         {Check(values[Col(names,"lag1_autocorr")]=="","constant autocorrelation missing");Check(values[Col(names,"close_zscore")]=="","constant zscore missing");}
      }
   }
   AkEngine a,b;MqlRates bar;ZeroMemory(bar);
   for(int i=0;i<600;i++)
   {
      bar.time=D'2020.01.01'+i*300;bar.close=100+i*0.01+MathSin(i*0.17);
      bar.open=bar.close-0.1;bar.high=bar.close+0.3;bar.low=bar.close-0.3;bar.tick_volume=100;
      a.Push(bar);a.UpdateEvents();b.Push(bar);b.UpdateEvents();
   }
   string h,x=a.Snapshot(h,1),h2,y=b.Snapshot(h2,1);
   string again=a.Snapshot(h2,1);
   Check(x==y&&x==again,"snapshot read does not change same-bar events");
   Check(a.Get(AK_MFIREAL)==EMPTY_VALUE,"missing exchange volume never invented");
   Cells(h,names);Cells(x,values);Check(ArraySize(names)==ArraySize(values),"all Kivanc columns aligned");
   bool unique=true;
   for(int i=0;i<ArraySize(names);i++)for(int j=0;j<i;j++)if(names[i]==names[j])unique=false;
   Check(unique,"unique Kivanc names");

   AxTrade t;ZeroMemory(t);t.valid=true;t.closed=true;t.won=true;
   t.signalTime=D'2026.09.21 09:55';t.availableTime=D'2026.09.21 09:59';
   t.entryTime=D'2026.09.21 10:01';t.localTime=t.entryTime;t.exitTime=t.entryTime+60;
   t.entryClock="AUDIT_FILL";t.entry=100;t.sl=99;t.tp=101;t.exitPrice=101;t.netR=1;t.outcome="TP";
   t.costR=0;t.entrySpreadPoints=EMPTY_VALUE;t.spreadBasis="NOT_CAPTURED_BAR_MODEL";
   t.direction=1;t.rawDirection=1;
   AxReset();AxCapture(t);AxSeal("BoundaryProbe","test",PERIOD_M5,t.exitTime,"setting_fixture","\"true\"");
   AxIndicators();
   int width=Cells(AxHeader(),names);Check(Cells(AxRow(0),values)==width,"closed row schema");
   Check(values[Col(names,"entry_hour")]=="10","CSV uses fill hour");
   Check(values[Col(names,"entry_spread_points")]=="","uncaptured spread stays missing");
   Check(values[Col(names,"label_net_r")]=="1.000000000000","PnL preserved exactly");
   Check(values[Col(names,"label_exit_reason")]=="TP","closed outcome supplies missing reason");
   Check(AxExitReason(false,false,"TICK_DATA","SL")=="TICK_DATA","DATA reason preserved");
   Check(AxExitReason(true,true,"NAS_OPPOSITE_EXIT","WIN")=="NAS_OPPOSITE_EXIT","explicit reason preserved");
   Check(AxExitReason(true,false,"","open")=="","open is not a terminal exit");
   Check(AxEntryClock(t.entryTime,EMPTY_VALUE)=="MODELED_BAR_TIME","bar entry is not a tick fill");
   Check(AxEntryClock(t.entryTime,2)=="AUDIT_FILL","quote entry is a tick fill");
   Check(AxEntryClock(0,EMPTY_VALUE)=="UNAVAILABLE","missing entry clock");
   Check(AxEntryAt(0,t.availableTime)==t.availableTime,"unknown fill uses declared fallback");
   TCalReset();TCalRecord(AxEntryAt(t.entryTime,t.availableTime),t.netR);
   findings+="available_hour_wins="+(string)g_tcalWins[1][9]+" fill_hour_wins="+(string)g_tcalWins[1][10]+" csv_entry_hour=10\n";
   Check(g_tcalWins[1][9]==0&&g_tcalWins[1][10]==1,"calendar and CSV use the fill hour");
   g_tcalEnabled=true;for(int d=0;d<7;d++)g_tcalDayHours[d]=0;
   g_tcalDayHours[1]=1<<10;
   Check(!TCalAllows(t.availableTime)&&TCalAllows(AxEntryAt(t.entryTime,t.availableTime)),"delayed fill gate uses admitted hour");
   g_tcalDayHours[1]=1<<9;
   Check(TCalAllows(t.availableTime)&&!TCalAllows(AxEntryAt(t.entryTime,t.availableTime)),"delayed fill blocked in disabled hour");
   g_tcalEnabled=false;
   g_axMissing=0;g_axMissingRolling=1;g_axMissingMtf=2;g_axMissingKiv=3;
   Check(AxCoverageSummary()=="missing rows core=0 rolling=1 MTF=2 Kivanc=3","coverage never implies all groups complete");

   AkExportBegin();g_akQuery=0;g_akRows[0]=AkMissingRow("DATA_MISSING");
   Check(AkExportWait()&&g_akPreparing&&g_akWaiting,"transient replay failure waits instead of completing");
   Check(g_akRows[0]==AkMissingRow("DATA_MISSING"),"waiting preserves uncomputed values");
   uint timeout=g_axPrepareTimeoutMs;g_axPrepareTimeoutMs=0;
   Check(!AkExportWait()&&!g_akPreparing&&!g_akWaiting,"history retry has a deadline");
   Check(g_akRows[0]==AkMissingRow("DATA_MISSING_HISTORY_TIMEOUT"),"timeout is explicit, not invented features");
   g_axPrepareTimeoutMs=timeout;AkExportReset();
   Check(!g_akWaiting&&g_akWaitStarted==0,"cancellation clears retry state");
   TCalReset();TCalRecord(D'2026.09.21 00:00',1);TCalRecord(D'2026.09.21 23:59:59',-1);
   TCalRecord(D'2026.09.22 00:00',1);TCalRecord(D'2026.09.22 00:00',0);
   Check(g_tcalWins[1][0]==1&&g_tcalLosses[1][23]==1&&g_tcalWins[2][0]==1,"day and hour boundaries");
   Check(TCalRankWins(0,1)==1&&TCalRankLosses(0,1)==1&&TCalWr(1,1)==50,"day totals and WR");
   Check(TCalRankWins(1,0)==2&&TCalRankLosses(1,23)==1,"hour totals across days");
   AxReset();TCalDestroy();
   int f=FileOpen("AuditCsvBoundaryProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+"\n"+findings);FileClose(f);
}
