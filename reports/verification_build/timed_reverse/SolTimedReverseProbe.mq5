#define PROBE_PARITY
#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
datetime ProbeNow(){return D'2025.10.27 08:00';}
// Test-only quote fixtures. Production uses the native terminal API.
MqlTick fixture[];
bool fixtureError=false;
int ProbeNoQuotes(string symbol,MqlTick &ticks[],uint flags,ulong from=0,ulong to=0)
{
   ArrayResize(ticks,0);int n=0;
   for(int i=0;i<ArraySize(fixture);i++)if((ulong)fixture[i].time_msc>=from&&(ulong)fixture[i].time_msc<=to)
   {ArrayResize(ticks,n+1);ticks[n++]=fixture[i];}
   if(fixtureError)SetUserError(55);
   return n;
}
#define TimeCurrent ProbeNow
#define CopyTicksRange ProbeNoQuotes
#include "C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#include "SolBefore.mqh"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef TimeCurrent
#undef CopyTicksRange
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("SOL TIMED REVERSE FAIL: ",label," ",g_lastSimInvalidReason);}}
void OnStart()
{
   g_invertMode=false;g_pipSlMode=false;g_slDistancePct=100;g_slBufferAtrPct=0;
   g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;
   g_btSpreadPts=0;g_btSlippagePts=0;g_btCommissionPerLot=0;g_customTargetR=100;
   LnNasDefaults(g_lnNas);
   ArraySetAsSeries(g_simRates,true);
   int n=CopyRates(_Symbol,PERIOD_M5,D'2025.10.20 07:00',ProbeNow(),g_simRates);
   g_simRatesTf=PERIOD_M5;g_simRatesLatestBar=iTime(_Symbol,PERIOD_M5,0);
   g_simRatesOldestBar=n>0?g_simRates[n-1].time:0;
   Check(n>20,"recorded simulation bars available");
   MqlRates next[];datetime deadline=D'2025.10.26 08:05';
   int nc=CopyRates(_Symbol,PERIOD_M1,deadline,ProbeNow(),next);
   int at=FindEntryBarIndex(g_simRates,D'2025.10.24 08:00');
   Check(at>0&&nc>0,"recorded weekend reopening available");
   if(at>0&&nc>0)for(int side=0;side<2;side++)
   {
      ErlSignal sig;ZeroMemory(sig);sig.valid=true;sig.dir=side==0?1:-1;
      sig.entryTime=g_simRates[at].time;sig.availableTime=sig.entryTime+300;sig.entry=g_simRates[at-1].open;
      sig.sl=sig.entry-sig.dir*0.5;sig.risk=0.5;sig.id="weekend"+(string)side;SetSignalTargetLadder(sig);
      g_lnNas.reverseExit=true;g_lnNas.reverseWaitMinutes=2880;
      bool closed,won,valid;
      double r=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,deadline,closed,won,valid);
      Check(valid&&closed,"48H no-quote exit resolves with explicit bar model");
      Check(g_lastSimExitTime==next[0].time&&g_lastSimExitTime>deadline,"weekend exit timestamp is actual reopening");
      ArrayResize(g_histSignals,2);g_histSignals[0]=sig;g_histSignals[1]=sig;
      g_histSignals[1].availableTime=deadline;
      ArrayResize(g_histSignalValid,2);ArrayResize(g_histSignalClosed,2);
      ArrayResize(g_histSignalExitTime,2);ArrayResize(g_histSignalInvalidReason,2);
      g_histSignalValid[0]=valid;g_histSignalClosed[0]=closed;g_histSignalExitTime[0]=g_lastSimExitTime;
      g_histSignalInvalidReason[0]="";g_lnNas.independent=true;g_lnNas.maxSameOpen=1;
      Check(LnNasAuditCap(1)==1,"Independent stays occupied until modeled reopening");
      g_histSignals[1].availableTime=g_lastSimExitTime;
      Check(LnNasAuditCap(1)==0,"Independent frees slot at reopening");
      g_lnNas.independent=false;
      Print("SOL WEEKEND side=",side," valid=",valid," closed=",closed," exit=",TimeToString(g_lastSimExitTime,TIME_DATE|TIME_SECONDS)," R=",r," reason=",g_lastSimExitReason);
   }
   g_customTargetR=0.5;int early=0;
   for(int i=n-10;i>=0&&i>n-43;i--)for(int side=0;side<2;side++)
   {
      ErlSignal sig;ZeroMemory(sig);sig.valid=true;sig.dir=side==0?1:-1;
      sig.entryTime=g_simRates[i].time;sig.availableTime=g_simRates[i-1].time;sig.entry=g_simRates[i-1].open;
      sig.risk=4*(g_simRates[i-1].high-g_simRates[i-1].low);sig.sl=sig.entry-sig.dir*sig.risk;sig.id="early"+(string)i+(string)side;
      if(sig.risk<=10*_Point)continue;
      SetSignalTargetLadder(sig);bool c,w,v;
      g_lnNas.reverseExit=false;
      double plain=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,c,w,v);
      datetime exit=g_lastSimExitTime;string reason=g_lastSimExitReason;
#ifdef PROBE_PARITY
      bool oc,ow,ov;double old=BeforeSimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,oc,ow,ov);
      Check(c==oc&&w==ow&&v==ov&&plain==old&&exit==g_lastSimExitTime&&reason==g_lastSimExitReason,"reverse OFF exact result parity");
      g_lnNas.reverseExit=true;g_lnNas.reverseWaitMinutes=0;
      double zero=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,sig.availableTime+900,c,w,v);
      datetime zeroAt=g_lastSimExitTime;string zeroReason=g_lastSimExitReason;
      old=BeforeSimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,sig.availableTime+900,oc,ow,ov);
      Check(c==oc&&w==ow&&v==ov&&zero==old&&zeroAt==g_lastSimExitTime&&zeroReason==g_lastSimExitReason,"legacy zero-wait bar results preserved");
      g_lnNas.reverseExit=false;
      plain=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,c,w,v);
#endif
      if(!v||!c||exit>=sig.availableTime+2880*60)continue;
      early++;g_lnNas.reverseExit=true;g_lnNas.reverseWaitMinutes=2880;
      double timed=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,sig.availableTime+2880*60,c,w,v);
      Check(v&&c&&timed==plain&&g_lastSimExitTime==exit&&g_lastSimExitReason==reason,"natural exit before deadline is not discarded as DATA");
   }
   Check(early>0,"natural closure fixtures exercised");
#ifdef PROBE_PARITY
   // No quote exactly at the deadline. Later adverse quotes must not leak
   // into its exit, including when a 64-quote acceleration block straddles it.
   int setup=FindEntryBarIndex(g_simRates,D'2025.10.20 08:00');
   Check(setup>0,"quote fixture source bar exists");
   if(setup>0)for(int side=0;side<2;side++)
   {
      ErlSignal sig;ZeroMemory(sig);sig.valid=true;sig.dir=side==0?1:-1;
      sig.entryTime=g_simRates[setup].time;sig.availableTime=sig.entryTime+300;
      sig.entry=g_simRates[setup-1].open;sig.sl=sig.entry-sig.dir*0.5;sig.risk=0.5;
      sig.id="quotes"+(string)side;SetSignalTargetLadder(sig);
      g_customTargetR=100;g_lnNas.reverseExit=true;g_lnNas.reverseWaitMinutes=2880;
      ArrayResize(fixture,160);
      for(int k=0;k<160;k++)
      {
         ZeroMemory(fixture[k]);fixture[k].time=sig.availableTime+k+(k>=70?3:0);
         fixture[k].time_msc=(long)fixture[k].time*1000;
         fixture[k].bid=sig.entry+sig.dir*k*_Point;
         if(k>=100)fixture[k].bid=sig.entry-sig.dir*0.7;
         fixture[k].ask=fixture[k].bid+10*_Point;
      }
      datetime boundary=sig.availableTime+70;bool c,w,v;
      double reference=0;datetime referenceAt=0;
      for(int accelerated=0;accelerated<2;accelerated++)
      {
         LnQuoteReset();g_lnQuoteAcceleration=accelerated!=0;
         double r=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,boundary,c,w,v);
         Check(v&&c&&g_lastSimExitReason=="TICK_REVERSE_EXIT","exact quote exit resolves");
         Check(g_lastSimExitTime==boundary+3,"first quote AFTER deadline sets actual exit time");
         double closePx=side==0?fixture[70].bid:fixture[70].ask;
         double expected=ApplyForcedSignalExit(sig.dir,closePx,g_lastSimExecEntry,
            MathAbs(g_lastSimExecEntry-g_lastSimExecSl),true,ERL_HC_OFF,0,0);
         Check(MathAbs(r-expected)<1e-12,"future adverse quotes never change deadline result");
         if(accelerated==0){reference=r;referenceAt=g_lastSimExitTime;}
         else Check(r==reference&&g_lastSimExitTime==referenceAt,"accelerated and reference quote paths match");
      }
      // Protective stop takes precedence on the first executable quote.
      fixture[70].bid=sig.entry-sig.dir*0.7;fixture[70].ask=fixture[70].bid+10*_Point;
      LnQuoteReset();
      SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,boundary,c,w,v);
      Check(v&&c&&g_lastSimExitReason=="TICK_SL"&&g_lastSimExitTime==boundary+3,"protective stop priority at reopening quote");
      fixtureError=true;g_invertMode=true;g_customTargetR=1;g_inverseMaxGapPct=100;LnQuoteReset();
      SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,boundary,c,w,v);
      Check(!v&&g_lastSimInvalidReason=="INVERSE_TICKS_REQUIRED","positive partial quote read with error never proves an inverse verdict");
      fixtureError=false;g_invertMode=false;g_customTargetR=100;ArrayFree(fixture);LnQuoteReset();
      g_lnQuoteAcceleration=true;
      SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,sig.availableTime+30,c,w,v);
      Check(!v&&g_lastSimInvalidReason=="REVERSE_TICKS_REQUIRED","unobserved subminute reverse stays DATA");
      g_lnNas.exitMode=1;
      SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,sig.availableTime,c,w,v);
      Check(!v&&g_lastSimInvalidReason=="NAS_EXIT_TICKS_MISSING","NAS forced exit is not fabricated from OHLC");
      g_lnNas.exitMode=0;
   }
#endif
   int f=FileOpen("SolTimedReverseProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
