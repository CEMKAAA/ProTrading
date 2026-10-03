#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
uint rng=72931;
uint Next(){rng=1664525*rng+1013904223;return rng>>1;}
void Check(bool ok,string why){checks++;if(!ok){failed++;if(failed<10)Print("ACCEL_FAIL ",why);}}
int ReferenceEntry(int dir,datetime at,datetime through,datetime &accepted)
{
   accepted=at;
   if(g_lnNas.gate==0)return 1;
   if(g_lnNas.gate==2)
   {
      for(int i=ArraySize(g_lnNasEvents)-1;i>=0;i--)
         if(g_lnNasEvents[i].at<=at&&g_lnNasEvents[i].stateAllowed)return g_lnNasEvents[i].dir==dir?1:0;
      return -1;
   }
   datetime age=at-g_lnNas.entryAgeMinutes*60;
   for(int i=ArraySize(g_lnNasEvents)-1;i>=0;i--)
      if(g_lnNasEvents[i].at<=at&&g_lnNasEvents[i].at>=age&&g_lnNasEvents[i].flowAllowed)
      {if(g_lnNasEvents[i].dir==dir)return 1;break;}
   for(int i=0;i<ArraySize(g_lnNasEvents);i++)
      if(g_lnNasEvents[i].at>at&&g_lnNasEvents[i].at<=through&&g_lnNasEvents[i].dir==dir&&g_lnNasEvents[i].flowAllowed)
      {accepted=g_lnNasEvents[i].at;return 1;}
   return 0;
}
datetime ReferenceExit(int dir,datetime opened,datetime through,int wait)
{
   if(g_lnNas.exitMode==0)return 0;
   if(g_lnNas.exitMode==1)
      for(int r=0;r<ArraySize(g_histRawCache);r++)
         if(g_histRawCache[r].availableTime>opened){through=MathMin(through,g_histRawCache[r].availableTime);break;}
   datetime eligible=opened+wait*60,last=0;int lastDir=0;
   for(int i=0;i<ArraySize(g_lnNasEvents);i++)
   {
      LnNasEvent e=g_lnNasEvents[i];if(e.at<=opened||e.at>through||!e.flowAllowed)continue;
      if(e.at<=eligible){last=e.at;lastDir=e.dir;continue;}
      if(last>0&&lastDir==-dir)return eligible;
      if(e.dir==-dir)return e.at;
   }
   if(last>0&&lastDir==-dir&&through>=eligible)return eligible;
   return 0;
}
void CheckNas()
{
   LnNasDefaults(g_lnNas);g_lnNas.exitMode=2;
   datetime base=D'2020.01.01';int n=20000;
   ArrayResize(g_lnNasEvents,n);ArrayResize(g_histRawCache,1200);
   for(int i=0;i<n;i++)
   {
      g_lnNasEvents[i].at=base+i*120;g_lnNasEvents[i].dir=(Next()&1)!=0?1:-1;
      g_lnNasEvents[i].stateAllowed=Next()%3!=0;g_lnNasEvents[i].flowAllowed=Next()%4!=0;
   }
   for(int i=0;i<1200;i++){ZeroMemory(g_histRawCache[i]);g_histRawCache[i].availableTime=base+i*2000;}
   LnNasIndexEvents();g_lnNasSeed=base-86400;g_lnNasBar=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,1);
   g_lnNasSignature=_Symbol+"|"+(string)(ENUM_TIMEFRAMES)_Period+"|"+(string)g_lnNas.sensitivity+"|"
      +(string)g_lnNas.stateVolume+"|"+DoubleToString(g_lnNas.stateMultiplier,8)+"|"
      +(string)g_lnNas.flowVolume+"|"+DoubleToString(g_lnNas.flowMultiplier,8);
   for(int q=0;q<5000;q++)
   {
      int dir=Next()%2!=0?1:-1;datetime at=base+(datetime)(Next()%(n*120));
      datetime through=at+(datetime)(Next()%30000);int wait=(int)(Next()%180);
      g_lnNas.gate=(int)(Next()%3);g_lnNas.exitMode=(int)(Next()%3);g_lnNas.entryAgeMinutes=(int)(Next()%240);
      datetime a=0,b=0;int ra=ReferenceEntry(dir,at,through,a),rb=LnNasEntryDecision(dir,at,through,b);
      Check(ra==rb&&a==b,"entry state/age/flow timestamp");
      Check(ReferenceExit(dir,at,through,wait)==LnNasExitAt(dir,at,through,wait),"NAS wait and setup boundaries");
   }
   ArrayResize(g_lnNasEvents,0);LnNasIndexEvents();g_lnNas.gate=1;datetime accepted=0;
   Check(LnNasEntryDecision(1,base,base+3600,accepted)==0,"empty successful NAS cache");
   g_lnNas.gate=2;Check(LnNasEntryDecision(1,base,base+3600,accepted)==-1,"empty state is DATA");
}
void CheckQuotes()
{
   LnQuoteReset(true);ulong hour=(ulong)D'2020.01.01'*1000;
   ArrayResize(g_lnQuoteTicks,4096);
   for(int k=0;k<4096;k++)
   {
      ZeroMemory(g_lnQuoteTicks[k]);g_lnQuoteTicks[k].time_msc=(long)hour+k*800;
      g_lnQuoteTicks[k].time=(datetime)(g_lnQuoteTicks[k].time_msc/1000);
      double bid=100+0.8*MathSin(k*0.019);
      g_lnQuoteTicks[k].bid=k%91==0?0:bid;g_lnQuoteTicks[k].ask=k%137==0?0:bid+0.02+(k%9)*0.001;
   }
   g_lnQuoteFrom=hour;g_lnQuoteTo=hour+3599999;g_lnQuoteReady=true;
   LnQuoteBuildBlocks();LnQuoteRememberHour();
   for(int q=0;q<2000;q++)
   {
      int first=(int)(Next()%4000),after=MathMin(4096,first+32+(int)(Next()%500));
      int dir=Next()%2!=0?1:-1;double sl=dir>0?98.5:101.5;
      double tp=dir>0?100.5+(Next()%100)*0.01:99.5-(Next()%100)*0.01;
      double half=dir>0?100.4:99.6;bool watch=Next()%2!=0,reverse=Next()%7==0;
      int skip=LnQuoteSkip(first,after,dir,sl,tp,half,watch,reverse);
      for(int k=first;k<skip;k++)
      {
         MqlTick t=g_lnQuoteTicks[k];if(t.bid<=0||t.ask<=0)continue;
         double px=dir>0?t.bid:t.ask;
         Check(reverse||(!(dir>0?px<=sl:px>=sl)&&!(dir>0?px>=tp:px<=tp)&&(!watch||!(dir>0?px>=half:px<=half))),"no event inside skipped tick block");
      }
      ulong from=(ulong)g_lnQuoteTicks[first].time_msc,limit=(ulong)g_lnQuoteTicks[after-1].time_msc;
      datetime last=0;double close=0;
      ulong next=LnQuoteSkipRange(from,limit,dir,sl,tp,half,watch,reverse,last,close);
      datetime expectedAt=0;double expectedClose=0;
      for(int k=first;k<after&&(ulong)g_lnQuoteTicks[k].time_msc<next;k++)
      {
         MqlTick t=g_lnQuoteTicks[k];if(t.bid<=0||t.ask<=0)continue;
         double px=dir>0?t.bid:t.ask;
         Check(reverse||(!(dir>0?px<=sl:px>=sl)&&!(dir>0?px>=tp:px<=tp)&&(!watch||!(dir>0?px>=half:px<=half))),"minute summary never skips an event");
         expectedAt=t.time;expectedClose=px;
      }
      Check(last==expectedAt&&close==expectedClose,"skipped range preserves exact last quote for OPEN/forced exit");
   }
   g_lnQuoteReady=false;g_lnQuoteFrom=hour+3600000;g_lnQuoteTo=hour+7199999;
   int before=ArraySize(g_lnQuoteHours);LnQuoteRememberHour();
   Check(ArraySize(g_lnQuoteHours)==before,"partial/failed ranges cannot become proof indexes");
   LnQuoteReset(true);Check(ArraySize(g_lnQuoteHours)==0,"explicit data invalidation clears summaries");
   Check(LnQuoteHistoryChanged("test",100,1000,10,1),"new data owner invalidates summaries");
   Check(!LnQuoteHistoryChanged("test",100,1000,10,1),"unchanged history retains summaries");
   Check(!LnQuoteHistoryChanged("test",100,1060,11,1),"append-only new bar retains completed summaries");
   Check(LnQuoteHistoryChanged("test",100,1060,12,1),"non-append backfill invalidates summaries");
   Check(LnQuoteHistoryChanged("test",40,1060,13,1),"earlier history start invalidates summaries");
   Check(LnQuoteHistoryChanged("test",40,1060,13,0),"sync loss invalidates summaries");
   Check(LnQuoteHistoryChanged("test",40,1060,13,1),"resync invalidates summaries");
   Check(LnQuoteHistoryChanged("test",40,1000,12,1),"history reset invalidates summaries");
   LnQuoteReset(true);ArrayResize(g_lnQuoteTicks,12);
   for(int i=0;i<12;i++)
   {
      MqlTick t;ZeroMemory(t);t.time_msc=(long)hour+i*1800000;t.time=(datetime)(t.time_msc/1000);
      t.bid=100+i*0.01;t.ask=t.bid+0.04;g_lnQuoteTicks[i]=t;
   }
   g_lnQuoteFrom=hour;g_lnQuoteTo=hour+LN_QUOTE_PAGE_MS-1;g_lnQuoteReady=true;
   LnQuoteBuildBlocks();LnQuoteRememberHour();
   Check(ArraySize(g_lnQuoteHours)==6,"six-hour page creates all six complete summaries");
   datetime last=0;double close=0;
   Check(LnQuoteSkipRange(hour,hour+LN_QUOTE_PAGE_MS-1,1,99,102,0,false,false,last,close)==hour+LN_QUOTE_PAGE_MS
      &&last==g_lnQuoteTicks[11].time&&close==g_lnQuoteTicks[11].bid,"multi-hour proof preserves final exact quote across empty minutes");
}
struct ReplayTrace
{
   double r,entry,sl,tp,half,spread;
   bool valid,closed,won;
   int dir;
   datetime entered,exited;
   string reason,error,basis;
};
ReplayTrace Replay(const ErlSignal &signal,datetime through,bool acceleration)
{
   g_lnQuoteAcceleration=acceleration;ReplayTrace t;ZeroMemory(t);
   t.r=SimulateSignal(signal,g_target,g_hc,g_targetModel,g_entryTf,through,t.closed,t.won,t.valid);
   t.entry=g_lastSimExecEntry;t.sl=g_lastSimExecSl;t.tp=g_lastSimExecTp;t.half=g_lastSimExecHalf;
   t.dir=g_lastSimExecDir;t.entered=g_lastSimEntryTime;t.exited=g_lastSimExitTime;
   t.reason=g_lastSimExitReason;t.error=g_lastSimInvalidReason;t.spread=g_lastSimEntrySpread;t.basis=g_lastSimEntryBasis;
   return t;
}
void CheckMarketReplay()
{
   g_htf=PERIOD_H2;g_entryTf=PERIOD_H1;g_swingLookback=5;
   g_entryModel=ERL_ENTRY_LEGACY_HTF_FVG_TAP;g_stopModel=ERL_STOP_FIRST_FVG_CANDLE;
   g_useAsiaLiquidityTarget=true;g_allowDuplicateEntries=true;
   g_pipSlMode=true;g_slDistancePct=100;g_slBufferAtrPct=10;
   g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;
   g_btSpreadPts=0;LnNasDefaults(g_lnNas);LnNasInvalidate();LnQuoteReset(true);
   ErlSignal raw[];
   BuildSignals(g_htf,g_entryTf,g_swingLookback,g_weeklyBias,g_entryModel,g_stopModel,ERL_TARGET_FIXED_R,
      g_requireIrlTouch,g_requireEntrySweep,g_requireDisplacementFvg,g_requireAsiaLiquidityDraw,
      g_useAsiaLiquidityTarget,g_requireSmt,TimeCurrent()-140*86400,raw);
   Check(ArraySize(raw)>0,"real broker signal fixtures available");
   if(ArraySize(raw)<1)return;
   int terminals=0;
   for(int q=0;q<72;q++)
   {
      ErlSignal signal=raw[(q%3)*(ArraySize(raw)-1)/2];
      g_pipSlPips=q%3==0?1:(q%3==1?10:100);
      g_target=q%2==0?ERL_RR_TP4:ERL_RR_TP2;g_hc=(q/3)%2==0?ERL_HC_OFF:ERL_HC_TP1;
      g_invertMode=(q/6)%2!=0;g_inverseMaxGapPct=100;
      g_targetModel=q%11==0&&!g_invertMode?ERL_TARGET_OPPOSITE_SIGNAL:ERL_TARGET_FIXED_R;
      g_btSlippagePts=(q/12)%3;g_btCommissionPerLot=(q/24)%3;
      datetime end=signal.availableTime+(q%4==0?300:(q%4==1?3600:86400));
      ReplayTrace a=Replay(signal,end,false),b=Replay(signal,end,true);
      Check(a.r==b.r&&a.valid==b.valid&&a.closed==b.closed&&a.won==b.won
         &&a.dir==b.dir&&a.entered==b.entered&&a.exited==b.exited&&a.reason==b.reason&&a.error==b.error
         &&a.entry==b.entry&&a.sl==b.sl&&a.tp==b.tp&&a.half==b.half&&a.spread==b.spread&&a.basis==b.basis,
         "reference tick replay equals accelerated fill/HC/exit/PnL/cost/inversion trace case "+(string)q);
      if(a.valid&&a.closed)terminals++;
   }
   Check(terminals>0,"real market parity includes terminal trades");
   g_lnQuoteAcceleration=true;LnQuoteReset(true);
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   CheckNas();CheckQuotes();CheckMarketReplay();
   int f=FileOpen("AuditPerf_optimized_cc5f761b.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+"\n");FileClose(f);}
}
