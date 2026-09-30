#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/TradeCalendarMatrix.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/AuditTradeCsv.mqh"
string AxSignalFeatureHeader(){return "f_test_causal";}
int featureCalls=0;
string AxSignalFeatures(datetime at,datetime signalBar,int direction){featureCalls++;return "\"1\"";}
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("CSV_PROBE_FAIL ",label);}}
int CsvCells(string text,string &values[])
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
int Find(const string &names[],string name)
{for(int i=0;i<ArraySize(names);i++)if(names[i]==name)return i;return -1;}
void OnStart()
{
   g_axNotify=false;g_axSchedule=false;g_tcalPrefix="CSV_PROBE_";g_tcalClockLabel="TEST CLOCK";
   Check(AxQuote("comma,\"quoted\"")=="\"comma,\"\"quoted\"\"\"","RFC4180 escaping");
   Check(AxQuote("=cmd")=="\"'=cmd\"","formula protection");
   Check(AxNumber(EMPTY_VALUE)=="","missing numeric value blank");
   AkEngine engine,prefix;MqlRates fixture;ZeroMemory(fixture);
   int golden=FileOpen("KivancFeatureProbe.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   string gh="bar";
   int slots[30]={AK_VAR12,AK_VAR26,AK_MACD,AK_MACDTRIGGER,AK_MOST,AK_HOTT,AK_LOTT,AK_OTTO_SRC,AK_OTTO,AK_STOCHK,AK_STOCHOTT,AK_MAV6,AK_T3,AK_T3FIB,AK_LARSI,AK_QFAST,AK_QSLOW,AK_STOPLONG,AK_STOPSHORT,AK_SUPER,AK_ALPHA_RSI,AK_MAGIC,AK_FOLLOW,AK_BOOT1,AK_BOOT2,AK_TRF,AK_RSX,AK_PMAX,AK_PIVOTST,AK_CCI};
   for(int k=0;k<30;k++)gh+=","+(string)slots[k];FileWriteString(golden,gh+"\n");
   string at300="";
   for(int k=0;k<700;k++)
   {
      fixture.time=D'2020.01.01'+k*300;
      fixture.close=100+0.012*k+4*MathSin(k*0.13)+1.7*MathCos(k*0.031);
      fixture.open=fixture.close+0.2*MathSin(k*0.73);fixture.high=MathMax(fixture.open,fixture.close)+0.4+0.1*(k%7);
      fixture.low=MathMin(fixture.open,fixture.close)-0.35-0.08*(k%5);fixture.tick_volume=100+k%37;fixture.real_volume=0;
      engine.Push(fixture);engine.UpdateEvents();string line=(string)k;
      if(k<=300){prefix.Push(fixture);prefix.UpdateEvents();}
      for(int j=0;j<30;j++)line+=","+AxNumber(engine.Get(slots[j]));FileWriteString(golden,line+"\n");
      if(k==300){string sh;at300=engine.Snapshot(sh,1);}
   }
   FileClose(golden);
   Check(engine.Count()==700,"Kivanc streaming bar count");
   string prefixHead;
   Check(prefix.Snapshot(prefixHead,1)==at300,"future bars cannot change earlier feature snapshot");
   Check(engine.Get(AK_ALPHA_REAL)==EMPTY_VALUE,"no fake real-volume AlphaTrend");
   string kh,kr=engine.Snapshot(kh,1),kn[],kv[];
   Check(CsvCells(kh,kn)==CsvCells(kr,kv),"Kivanc header row width");
   Check(Find(kn,"f_kiv_derived_mavilim_distance_atr")>=0,"non-indicator distance feature present");
   Check(Find(kn,"f_kiv_macd_cross_buy_age")>=0,"state age feature present");
   Check(engine.Last()+300<=fixture.time+300,"feature cutoff closed bar");
   MqlRates r[];ArrayResize(r,256);ArraySetAsSeries(r,true);
   for(int i=0;i<256;i++)
   {ZeroMemory(r[i]);r[i].close=1000-i;r[i].open=r[i].close-0.5;r[i].high=r[i].close+1;r[i].low=r[i].close-1;r[i].tick_volume=10;r[i].spread=2;}
   string cols[],values[];int nc=StringSplit(AxRollingNames(),',',cols),nv=CsvCells(AxRollingValues(r,20),values);
   Check(nc==32&&nv==nc,"rolling schema width");
   Check(MathAbs(StringToDouble(values[Find(cols,"return")])-(1000.0/980-1))<1e-10,"rolling return");
   Check(MathAbs(StringToDouble(values[Find(cols,"linear_slope")])-1)<1e-10,"chronological slope positive");
   Check(MathAbs(StringToDouble(values[Find(cols,"linear_r2")])-1)<1e-10,"trend r squared");
   Check(MathAbs(StringToDouble(values[Find(cols,"efficiency")])-1)<1e-10,"efficiency");
   Check(StringToDouble(values[Find(cols,"tick_volume_mean")])==10,"tick volume mean");
   Check(StringToDouble(values[Find(cols,"quote_volume_direction_proxy")])==1,"proxy is explicitly proxy");
   Check(StringToDouble(values[Find(cols,"spread_mean_points")])==2,"spread units points");
   Check(CsvCells(AxBlankFields(32),values)==32,"missing group schema width");
   Check(MathAbs(AxWma(r,0,2)-(1000.0*2+999)/3)<1e-10,"weighted MA newest heavy");
   Check(AxHma(r,200)!=EMPTY_VALUE,"HMA 200 coverage");
   ArrayResize(r,8);Check(AxHma(r,200)==EMPTY_VALUE,"HMA missing is not zero");

   AxTrade t;ZeroMemory(t);datetime at=iTime(_Symbol,PERIOD_M5,2)+300;
   if(at<100000)at=D'2026.09.20 12:00';
   t.signalTime=at-300;t.availableTime=at;t.entryTime=at;t.localTime=at;
   t.entryClock="AUDIT_FILL";t.entry=100;t.sl=99;t.tp=102;t.entrySpreadPoints=2;t.spreadBasis="ENTRY_BID_ASK_QUOTE";
   t.direction=1;t.rawDirection=1;t.valid=true;t.closed=true;t.won=true;t.netR=1.99;t.costR=0.01;
   t.exitTime=at+123;t.exitPrice=102;t.outcome="TP";t.signalFeatures="\"1\"";
   string settings="",settingValues="";AxSetting(settings,settingValues,"test","one,two");
   AxReset();AxCapture(t);AxSeal("CsvProbe","strategy,\"name\"",PERIOD_M5,at+1000,settings,settingValues);AxIndicators();
   Check(featureCalls==0,"capturing and sealing audit never extracts features");
   int count=CsvCells(AxHeader(),cols);Check(count>450,"wide quant feature set");
   nv=CsvCells(AxRow(0),values);Check(nv==count,"populated row matches header");
   Check(values[Find(cols,"strategy")]=="strategy,\"name\"","strategy name preserved");
   Check(StringToDouble(values[Find(cols,"label_net_r")])==1.99,"PnL unmodified");
   Check(StringToInteger(values[Find(cols,"label_duration_seconds")])==123,"exact holding seconds");
   Check(values[Find(cols,"measured_slippage_points")]=="","slippage not fabricated");
   Check(values[Find(cols,"setting_test")]=="one,two","settings separate column and escaped");
   Check(StringToDouble(values[Find(cols,"f_effective_target_r")])==2,"effective geometry");
   MqlRates closed[];bool history=AxClosedRates(PERIOD_M5,at,21,closed);
   Check(!history||closed[0].time+300<=at,"closed bars only");
   t.valid=false;t.closed=false;t.entryTime=D'1971.01.01';t.signalFeatures="\"\"";t.reason="DATA_TEST";AxCapture(t);
   nv=CsvCells(AxRow(1),values);Check(nv==count,"no-data row still matches schema");
   Check(values[Find(cols,"label_net_r")]==""&&values[Find(cols,"label_won")]=="","DATA not win or loss");
   Check(values[Find(cols,"feature_status")]=="DATA_MISSING","history missing marked");
   Check(values[Find(cols,"rsi_14")]=="","RSI missing blank");
   t.valid=true;t.closed=false;t.entryTime=at;t.exitTime=0;t.outcome="OPEN";t.netR=0;AxCapture(t);
   nv=CsvCells(AxRow(2),values);Check(nv==count,"open row matches schema");
   Check(values[Find(cols,"label_won")]==""&&values[Find(cols,"label_exit_time")]=="","open not fake loss");
   Check(StringToInteger(values[Find(cols,"label_duration_seconds")])==1000,"open age as of audit");
   AxRelease();ResetLastError();bool started=AxStart();Check(started,"CSV starts: "+g_tcalCsvStatus+" err="+(string)GetLastError());
   // The deliberate 1971 DATA row cannot have broker coverage.
   g_axPrepareTimeoutMs=2000;
   AxStep();
   Check(g_axBusy&&g_axIndex==0&&g_axRetryAt>0,"unavailable history waits before writing any row");
   AxEvent(CHARTEVENT_CUSTOM+AX_EVENT,(long)g_axGeneration-1);
   Check(g_axIndex==0,"stale event cannot bypass preparation");
   for(int i=0;i<6000&&g_axBusy;i++){AxStep();Sleep(20);}
   Check(!g_axBusy&&FileIsExist(g_axPath,FILE_COMMON),"atomic CSV published");
   Check(!FileIsExist(g_axPath+".partial",FILE_COMMON),"no unfinished file presented as final");
   Check(g_axMissing>0&&g_axMissingRolling>0&&g_axMissingMtf>0&&g_axMissingKiv>0,"timeout exposes per-group missing rows");
   string savedPath=g_axPath;Check(AxStart(),"repeat export unique file");AxReset();
   Check(!g_axReady&&!g_axBusy&&ArraySize(g_axTrades)==0,"audit reset cancels and invalidates");
   Check(g_axRetryAt==0&&!g_akWaiting,"cancel clears timer and replay retry");
   Check(!FileIsExist(g_axPath+".partial",FILE_COMMON),"cancel cleans partial");
   AxSeal("CsvProbe","empty audit",PERIOD_M5,at+1000,settings,settingValues);
   Check(AxStart(),"empty complete audit exports");
   for(int i=0;i<1500&&g_axBusy;i++){AxStep();Sleep(20);}
   Check(!g_axBusy&&g_axIndex==0&&FileIsExist(g_axPath,FILE_COMMON),"zero trades produces zero data rows");
   int empty=FileOpen(g_axPath,FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI,0,CP_UTF8);
   bool headerOnly=false;
   if(empty!=INVALID_HANDLE){string headerLine=FileReadString(empty);headerOnly=StringLen(headerLine)>100&&FileIsEnding(empty);FileClose(empty);}
   Check(headerOnly,"empty audit has only a header");
   AxReset();
   int f=FileOpen("AuditTradeCsvProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+" columns="+(string)count+"\n");
   FileWriteString(f,"csv="+TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+savedPath+"\n");FileClose(f);
   TCalDestroy();
}

