#property strict
#ifdef LAB_OFFLINE_HISTORY_FIXTURE
// Test-only frozen local-history fixture. No price, fill or outcome override.
// Broker connectivity is not a completeness flag for a recorded offline dataset.
struct ProbeLocalSeries{ENUM_TIMEFRAMES tf;long first,last,bars;};
ProbeLocalSeries g_probeLocalSeries[];
bool g_probeLocalReady=false;
long ProbeSeriesInfo(const string symbol,const ENUM_TIMEFRAMES tf,const ENUM_SERIES_INFO_INTEGER property)
{
   long value=SeriesInfoInteger(symbol,tf,property);
   if(property!=SERIES_SYNCHRONIZED||value||!g_probeLocalReady||symbol!=_Symbol)return value;
   for(int i=0;i<ArraySize(g_probeLocalSeries);i++)
      if(g_probeLocalSeries[i].tf==tf
         &&g_probeLocalSeries[i].first==SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE)
         &&g_probeLocalSeries[i].last==SeriesInfoInteger(symbol,tf,SERIES_LASTBAR_DATE)
         &&g_probeLocalSeries[i].bars==SeriesInfoInteger(symbol,tf,SERIES_BARS_COUNT))return 1;
   return value;
}
bool FreezeLocalHistory()
{
   ENUM_TIMEFRAMES tfs[]={PERIOD_M1,PERIOD_M5,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};
   ArrayResize(g_probeLocalSeries,ArraySize(tfs));MqlRates rates[];ArraySetAsSeries(rates,false);
   for(int i=0;i<ArraySize(tfs);i++)
   {
      long first=SeriesInfoInteger(_Symbol,tfs[i],SERIES_FIRSTDATE);
      long last=SeriesInfoInteger(_Symbol,tfs[i],SERIES_LASTBAR_DATE);
      long bars=SeriesInfoInteger(_Symbol,tfs[i],SERIES_BARS_COUNT);
      int count=CopyRates(_Symbol,tfs[i],(datetime)first,(datetime)last,rates);
      if(count<1||count!=bars||rates[0].time!=first||rates[count-1].time!=last)return false;
      g_probeLocalSeries[i].tf=tfs[i];g_probeLocalSeries[i].first=first;
      g_probeLocalSeries[i].last=last;g_probeLocalSeries[i].bars=bars;
   }
   g_probeLocalReady=true;return true;
}
#define SeriesInfoInteger ProbeSeriesInfo
#endif

#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
// Freeze only the campaign's audit cutoff for reproducible differential tests.
// Recorded rates, bid/ask quotes, fills and outcome calculations stay unchanged.
datetime g_probeClock=0;
datetime ProbeTimeCurrent(){return g_probeClock>0?g_probeClock:TimeCurrent();}
#define TimeCurrent ProbeTimeCurrent
#include "EntryEngineLabEA.mq5"
#include "EntryEngineBuiltinsBaseline.mqh"
int checks=0,failed=0;
void Check(bool condition,string name){checks++;if(!condition){failed++;Print("FAIL: ",name);}}
LabEngine MakeEngine()
{
   LabEngine e;e.name="Probe engine";e.edge=true;ArrayResize(e.buy,1);ArrayResize(e.sell,1);
   LabRule r;LabRuleDefaults(r);r.feature=0;r.threshold=100;e.buy[0]=r;r.compare=1;e.sell[0]=r;return e;
}
void Click(string name){long l=0;double d=0;LabUiEvent(CHARTEVENT_OBJECT_CLICK,l,d,name);}
string AuditIdentity()
{
   string s=(string)g_histTotal+"|"+(string)g_histWins+"|"+(string)g_histLosses+"|"+AuditMemoPrice(g_histNetR);
   for(int i=0;i<ArraySize(g_axTrades);i++){AxTrade t=g_axTrades[i];s+="|"+(string)t.signalTime+"|"+(string)t.entryTime+"|"+(string)t.exitTime+"|"+(string)t.direction+"|"+t.outcome+"|"+AuditMemoPrice(t.netR)+"|"+AuditMemoPrice(t.entry)+"|"+AuditMemoPrice(t.sl)+"|"+AuditMemoPrice(t.tp);}
   return OrbMlSha256(s);
}
bool RunAudit(int weeks)
{
   for(int attempt=0;attempt<5;attempt++)
   {g_rtHistoricalWeeks=weeks;g_lastHistBuild=0;g_histNeedsRedraw=true;DrawHistoricalSignals();ulong start=GetTickCount64();
      while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-start<180000)ProcessHistoricalAuditStep();
      EventKillTimer();if(!g_histAuditRunning&&!g_histCoveragePending&&g_histTotal>0&&g_histInvalid==0)return true;
      MqlRates warm[];ENUM_TIMEFRAMES tf[]={PERIOD_M1,PERIOD_M5,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};
      for(int i=0;i<ArraySize(tf);i++)CopyRates(_Symbol,tf[i],1,10000,warm);Sleep(3000);
   }return false;
}
#include "EntryEngineLabProbe_78e846a45a_checks.mqh"
#include "EntryEngineLabPickerChecks.mqh"
#include "MaOpenCapacityChecks.mqh"
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
#ifdef LAB_OFFLINE_HISTORY_FIXTURE
   if(!FreezeLocalHistory()){Print("LOCAL_FIXTURE_INCOMPLETE");return;}
#endif
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;g_axNotify=false;g_axSchedule=false;
   CheckLabPickers();
   CheckOpenCapacity();
#ifdef LAB_UI_ONLY
   int uiReport=FileOpen("EntryEngineLabProbe_78e846a45a.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(uiReport!=INVALID_HANDLE){FileWriteString(uiReport,"checks="+(string)checks+" failed="+(string)failed+" ui_only=true\n");FileClose(uiReport);}
   return;
#endif
   for(int a=-1;a<=1;a++)for(int b=-1;b<=1;b++)
   {Check(LabJoin(a,b,0)==(a==0||b==0?0:(a<0||b<0?-1:1)),"AND truth table");Check(LabJoin(a,b,1)==(a==1||b==1?1:(a<0||b<0?-1:0)),"OR truth table");Check(LabJoin(a,b,2)==(a<0||b<0?-1:(a!=b?1:0)),"XOR truth table");}
   LabEngine e=MakeEngine(),decoded;string encoded=LabEngineText(e);
   Check(LabEngineRead(encoded,decoded)&&LabEngineText(decoded)==encoded,"engine round trip");
   Check(!LabEngineRead(encoded+"~extra",decoded),"invalid schema rejected");
   double now[LAB_FEATURES],previous[LAB_FEATURES];ArrayInitialize(now,EMPTY_VALUE);ArrayInitialize(previous,EMPTY_VALUE);
   LabRule r=e.buy[0];r.negate=true;Check(LabAtom(r,now,previous)==-1,"NOT missing stays missing");now[0]=120;previous[0]=90;
   Check(LabAtom(e.buy[0],now,previous)==1&&LabAtom(e.sell[0],now,previous)==0,"independent buy/sell atoms");
   r=e.buy[0];r.rhsFeature=1;r.compare=6;now[1]=115;previous[1]=105;Check(LabAtom(r,now,previous)==1,"two moving operands cross");r=e.buy[0];
   r.negate=false;r.compare=6;Check(LabAtom(r,now,previous)==1,"cross above");
   r.compare=7;Check(LabAtom(r,now,previous)==0,"cross below");
   LabRule rows[];ArrayResize(rows,3);for(int i=0;i<3;i++)rows[i]=e.buy[0];rows[1].compare=1;rows[1].gate=1;rows[2].compare=1;rows[2].gate=0;
   Check(LabEvaluate(rows,now,previous)==0,"explicit left-fold precedence");
   LabRuleStream stream;stream.Reset(e);MqlRates bar;ZeroMemory(bar);bar.time=D'2026.09.01';bar.open=bar.close=110;bar.high=111;bar.low=109;
   Check(stream.Push(bar)==1,"initial buy condition");Check(stream.Push(bar)==0,"edge debounces repeated condition");bar.close=90;bar.low=89;Check(stream.Push(bar)==-1,"sell independent transition");
   e.edge=false;stream.Reset(e);Check(stream.Push(bar)==-1&&stream.Push(bar)==-1,"every-bar trigger");
   e.sell[0]=e.buy[0];stream.Reset(e);bar.close=110;Check(stream.Push(bar)==0,"simultaneous buy/sell blocks");
   e=MakeEngine();e.name="LAB_PROBE_"+(string)GetTickCount64();Check(LabStoreEngine(e),"engine save");e.buy[0].threshold=123;
   Check(LabStoreEngine(e)&&LabReadFile(LabEngineFile(e.name),decoded)&&decoded.buy[0].threshold==123,"same-name engine update");FileDelete(LabEngineFile(e.name),FILE_COMMON);
   e.buy[0].feature=32;e.buy[0].period=250;e.buy[0].rhsFeature=33;e.buy[0].rhsPeriod=50;
   Check(LabEngineRead(LabEngineText(e),decoded)&&decoded.buy[0].period==250&&decoded.buy[0].rhsFeature==33&&decoded.buy[0].rhsPeriod==50,"EMA/SMA parameters round trip");
   g_labEngine=MakeEngine();LabOpenBuilder();string edit=LabUiPrefix()+"VALUE_0";
   ObjectSetString(0,edit,OBJPROP_TEXT,"111");Click(edit);Check(ObjectGetString(0,edit,OBJPROP_TEXT)=="111","edit click keeps current value");
   Click(PREFIX+"BTN_LAB_ENGINES");Check(g_labUi==2,"underlying engine button blocked");
   Click(LabUiPrefix()+"ADD");Check(ArraySize(g_labDraft.buy)==2&&g_labDraft.buy[0].threshold==111,"add commits current edit");
   Click(LabUiPrefix()+"SELL");ObjectSetString(0,LabUiPrefix()+"VALUE_0",OBJPROP_TEXT,"77");
   Click(LabUiPrefix()+"BUY");Check(g_labDraft.sell[0].threshold==77&&g_labDraft.buy[0].threshold==111,"side values retained separately");
   Click(LabUiPrefix()+"PREVIEW");Check(g_labUi==0&&g_labPreviewOnly&&g_rtMaCrossMode==MA_CROSS_LAB_RULES,"unsaved preview activates audit mode");
   Check(!ExecuteOrbEntry("BUY",TimeCurrent(),100,"TEST"),"preview blocks native entry");CancelHistoricalAuditBuild();EventKillTimer();g_histRedrawQueued=false;
   // Known three-bar bearish FVG [100,102], then contact on a later closed bar.
   e=MakeEngine();stream.Reset(e);bar.open=bar.close=103;bar.high=104;bar.low=102;stream.Push(bar);
   bar.open=bar.close=101;bar.high=103;bar.low=99;stream.Push(bar);bar.open=bar.close=99;bar.high=100;bar.low=98;stream.Push(bar);
   Check(stream.Value(24)==0,"forming FVG is not a prior-zone touch");bar.open=bar.close=101;bar.high=101.5;bar.low=100.5;stream.Push(bar);
   Check(stream.Value(22)==1&&stream.Value(24)==1,"bear FVG inside/contact");bar.close=103;bar.high=104;stream.Push(bar);Check(stream.Value(26)==0,"bear FVG invalidation");
   MqlRates rates[];ArraySetAsSeries(rates,false);ulong wait=GetTickCount64();int n=0;
   while(!IsStopped()&&GetTickCount64()-wait<60000){n=CopyRates(_Symbol,PERIOD_M5,1,10000,rates);MqlRates warm[];CopyRates(_Symbol,PERIOD_M1,1,10000,warm);CopyRates(_Symbol,PERIOD_H1,1,10000,warm);CopyRates(_Symbol,PERIOD_H2,1,10000,warm);CopyRates(_Symbol,PERIOD_H4,1,10000,warm);CopyRates(_Symbol,PERIOD_D1,1,10000,warm);
      if(n==10000&&SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)&&SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))break;Sleep(100);}
   Check(n==10000,"broker history ready");
   // Compare all retained kernels with the actual unmodified MaCross source.
   for(int mode=0;mode<6;mode++)for(int pair=0;pair<3;pair++)
   {
      McPineKernel current;McPineKernelBaseline baseline;bool same=true;
      current.Reset((MA_CROSS_SIGNAL_MODE)mode,(MA_CROSS_PAIR)pair,9,20,200);
      baseline.Reset((MA_CROSS_SIGNAL_MODE)mode,(MA_CROSS_PAIR)pair,9,20,200);
      for(int i=0;i<n;i++){double confirmed=rates[i].close*0.9995;
         int a=current.Push(rates[i],confirmed),b=baseline.Push(rates[i],confirmed);
         if(a!=b||current.MarkerPrice()!=baseline.MarkerPrice())same=false;}
      Check(same,"retained builtin signal/marker parity mode="+(string)mode+" pair="+(string)pair);
   }
   int rsi=iRSI(_Symbol,PERIOD_M5,14,PRICE_CLOSE),ad=iADXWilder(_Symbol,PERIOD_M5,14);double rv[],av[];int nr=0,na=0;
   wait=GetTickCount64();while(GetTickCount64()-wait<30000){int anchor=iBarShift(_Symbol,PERIOD_M5,rates[n-1].time,true);nr=CopyBuffer(rsi,0,anchor,100,rv);na=CopyBuffer(ad,0,anchor,100,av);if(nr==100&&na==100)break;Sleep(100);}
   stream.Reset(e);double rsiError=0,adxError=0;for(int i=0;i<n;i++){stream.Push(rates[i]);if(i>=n-100&&nr==100&&na==100){rsiError=MathMax(rsiError,MathAbs(stream.Value(4)-rv[i-(n-100)]));adxError=MathMax(adxError,MathAbs(stream.Value(5)-av[i-(n-100)]));}}
   Check(nr==100&&rsiError<0.0001,"RSI matches MT5 closed bars");Check(na==100&&adxError<0.0001,"ADX matches MT5 Wilder");IndicatorRelease(rsi);IndicatorRelease(ad);
   int mh=iMA(_Symbol,PERIOD_M5,50,0,MODE_SMA,PRICE_CLOSE);double ma[];CopyBuffer(mh,0,iBarShift(_Symbol,PERIOD_M5,rates[n-1].time,true),1,ma);LabOperandStream sma;sma.Reset(33,50);
   for(int i=0;i<n;i++)sma.Push(rates[i]);Check(ArraySize(ma)==1&&MathAbs(sma.Current()-ma[0])<1e-8,"parameterized SMA matches MT5");IndicatorRelease(mh);
   LabEngine cross=MakeEngine();cross.buy[0].feature=32;cross.buy[0].period=9;cross.buy[0].rhsFeature=33;cross.buy[0].rhsPeriod=50;cross.buy[0].compare=6;
   cross.sell[0]=cross.buy[0];cross.sell[0].compare=7;LabOperandStream ema;ema.Reset(32,9);sma.Reset(33,50);stream.Reset(cross);double prevE=EMPTY_VALUE,prevS=EMPTY_VALUE;
   for(int i=0;i<n;i++){ema.Push(rates[i]);sma.Push(rates[i]);double currentE=ema.Current(),currentS=sma.Current();int expected=0;
      if(prevE!=EMPTY_VALUE&&prevS!=EMPTY_VALUE&&currentE!=EMPTY_VALUE&&currentS!=EMPTY_VALUE)expected=currentE>currentS&&prevE<=prevS?1:(currentE<currentS&&prevE>=prevS?-1:0);
      Check(stream.Push(rates[i])==expected,"EMA/SMA crossover stream");prevE=currentE;prevS=currentS;}
   CheckScalperFormulas(rates);CheckScalperPolicy();
   e=MakeEngine();e.name="Audit probe";e.buy[0].feature=4;e.buy[0].compare=6;e.buy[0].threshold=50;e.sell[0]=e.buy[0];e.sell[0].compare=7;
   g_labEngine=e;g_rtMaCrossMode=MA_CROSS_LAB_RULES;g_rtSignalTf=PERIOD_M5;g_rtNasConfirmation=false;g_rtNasStateGate=false;g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_maIndependent=true;g_maMaxConsecutive=2;g_maReverseExit=false;g_rtPipSlMode=true;g_rtPipSlPips=30;g_mcOf.mode=0;g_rtInvertMode=false;
   g_rtFilterAtr=false;g_rtFilterVol=false;g_rtFilterDay=false;g_rtEntryWindow=false;
   g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;g_rtTimeExit=false;g_rtBEOnTp1=false;g_rtHalfBeLeg=0;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtTargetMode=ORB_TARGET_R_LEG;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtFilteredWindowReverseExit=false;g_rtPostTradeDispBlockExit=false;
   for(int i=0;i<6;i++)g_regimeAllowed[i]=true;g_orbRfEnabled=false;TCalStrategyApplyText(TCalStrategyOffText());g_dailyMaxLosses=0;g_dailyTargetWins=0;
   MaVisualTrackDeletes();bool broad=RunAudit(5);bool warm=RunAudit(2);string a=AuditIdentity();int trades=g_histTotal;
   g_orbReplayMemo.Reset("FORCE_COLD_LAB");MaCrossAuditInvalidate();DeleteHist();bool cold=RunAudit(2);string b=AuditIdentity();
   Check(broad&&warm&&cold&&a==b,"custom engine 5W -> 2W exact audit parity");
   Check(g_histWins+g_histLosses>0,"tick replay includes closed trade outcomes");
   MaCrossSignal live;bool liveValid=MaCrossComputeSignal(_Symbol,PERIOD_M5,MA_CROSS_LAB_RULES,MA_CROSS_PAIR_FAST,9,20,200,live);
   Check(MaCrossAuditBuild(_Symbol,PERIOD_M5,TimeCurrent()-14*86400,TimeCurrent(),MA_CROSS_LAB_RULES,MA_CROSS_PAIR_FAST,9,20,200),"custom signal history cache");
   int direction=0;for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)if(g_maCrossAuditEvents[i].signalTime==iTime(_Symbol,PERIOD_M5,1))direction=g_maCrossAuditEvents[i].direction;
   Check(liveValid==(direction!=0)&&(!liveValid||live.direction==direction),"live and historical custom kernel agree");
   string strategyName="LAB_STRATEGY_PROBE_"+(string)GetTickCount64(),snapshot=LabEngineIdentity();
   Check(OrbUserSaveLocked(strategyName),"strategy snapshot save");
   int strategyIndex=g_strategyPresetIndex;OrbStrategyPreset preset;Check(OrbStrategyPresetLoad(strategyIndex,preset),"saved strategy reload");
   g_labEngine.buy[0].threshold=99;g_maRestoringPreset=true;
   Check(OrbUserApply(preset)&&LabEngineIdentity()==snapshot,"strategy restores exact entry engine snapshot");g_maRestoringPreset=false;
   if(strategyIndex>=0){FileDelete(OrbUserFile(strategyIndex),FILE_COMMON);FileDelete("EntryEngineLabStrategyLibrary\\"+preset.id+".metrics",FILE_COMMON);}FileDelete(LabActiveFile(),FILE_COMMON);
   RunScalperAudits();
   CheckLabCapacityAudit();
   int f=FileOpen("EntryEngineLabProbe_78e846a45a.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+" trades="+(string)trades+" audit_same="+(a==b?"true":"false")+" rsi_error="+DoubleToString(rsiError,10)+" adx_error="+DoubleToString(adxError,10)+" history_source="
#ifdef LAB_OFFLINE_HISTORY_FIXTURE
      +"LOCAL_FIXED"
#else
      +"BROKER_SYNCHRONIZED"
#endif
      +"\n");FileClose(f);}MaVisualStopTrackingDeletes();EventKillTimer();
}
