#define OnInit MaProbeUnusedInit
#define OnDeinit MaProbeUnusedDeinit
#define OnTick MaProbeUnusedTick
#define OnTimer MaProbeUnusedTimer
#define OnChartEvent MaProbeUnusedEvent
#include "../../IndicatorCodeExamples/MaCrossOverEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
int checks=0,failed=0;
string failures="";
void Check(bool ok,string label)
{
   checks++;if(ok)return;failed++;failures+=label+"; ";Print("FAIL ",label);
}
bool Near(double a,double b){return MathAbs(a-b)<1e-8;}
void OnStart()
{
   MaDefaults(g_cfg);g_prefix="MAC_PROBE_"+(string)ChartID()+"_";
   MaConfig restored;Check(MaUnpack(MaPack(g_cfg),restored)&&MaPack(g_cfg)==MaPack(restored),"config roundtrip");
   restored.adxMin=100;Check(MaConfigValid(restored),"ADX 100");restored.adxMin=0;Check(MaConfigValid(restored),"ADX 0");
   restored.adxMin=101;Check(!MaConfigValid(restored),"reject ADX 101");double number=0;
   Check(MaNumber("0,05",number)&&Near(number,.05),"decimal comma");Check(!MaNumber("bad",number),"invalid number");
   Check(MaWindow(10,1380,60)&&!MaWindow(720,1380,60),"overnight window");
   double x[],w[],e[],h[];ArrayResize(x,1000);for(int i=0;i<1000;i++)x[i]=100+MathSin(i*.071)*3+i*.001;
   MaWma(x,27,w);MaEma(x,9,e);MaHma(x,200,h);
   double last=x[0];bool wmaOk=true,emaOk=true;
   for(int i=0;i<1000;i++)
   {
      if(i>0)last=.2*x[i]+.8*last;if(!Near(last,e[i]))emaOk=false;
      if(i>=26){double direct=0;for(int j=0;j<27;j++)direct+=(j+1)*x[i-26+j];if(!Near(direct/378,w[i]))wmaOk=false;}
   }
   Check(wmaOk,"rolling WMA equals direct weighted sum");Check(emaOk,"EMA recurrence");
   MqlRates rates[],prefix[],htf[];ArrayResize(rates,1000);ArrayResize(prefix,600);ArrayResize(htf,3);
   datetime base=D'2025.01.01';
   for(int i=0;i<1000;i++){ZeroMemory(rates[i]);rates[i].time=base+i*300;rates[i].open=x[i]-.1;rates[i].close=x[i];rates[i].high=x[i]+.2;rates[i].low=x[i]-.2;rates[i].spread=10;rates[i].tick_volume=100+i%20;if(i<600)prefix[i]=rates[i];}
   MaSeries full,shorter;MaCalculate(rates,g_cfg,full);MaCalculate(prefix,g_cfg,shorter);bool causal=true;
   for(int i=250;i<600;i++)if(!Near(full.slow[i],shorter.slow[i])||!Near(full.rsi[i],shorter.rsi[i])||full.direction[i]!=shorter.direction[i]||full.bearDiv[i]!=shorter.bearDiv[i])causal=false;
   Check(causal,"future bars do not change prefix signals/features");
   for(int i=0;i<3;i++){ZeroMemory(htf[i]);htf[i].time=base+i*3600;}
   Check(MaLastClosed(htf,base+3599,3600)==-1&&MaLastClosed(htf,base+3600,3600)==0,"only closed HTF available");
   MaConfig c=g_cfg;c.riskMode=2;c.pips=10;c.rr=.5;MaTrade t;
   Check(MaStartTrade(t,base,base,1,0,100,1,1,c)&&Near(t.stop,90)&&Near(t.target,105),"pip geometry");
   c.invert=true;Check(MaStartTrade(t,base,base,-1,0,100,1,1,c)&&Near(t.stop,105)&&Near(t.target,90)&&Near((100-t.target)/t.risk,2),"pure inversion 0.5R becomes 2R");
   c.invert=false;c.rr=2;MaStartTrade(t,base,base,1,0,100,1,1,c);MaFinish(t,101,base+60,"REVERSE",0);
   Check(Near(t.net,.1)&&t.reason=="REVERSE","reverse positive actual R not target R");
   MaStartTrade(t,base,base,1,0,100,1,1,c);MaFinish(t,99,base+60,"REVERSE",0);Check(Near(t.net,-.1),"reverse negative actual R not -1R");
   MaStartTrade(t,base,base,1,0,100,1,1,c);MaAtOpen(t,85,0,base+60,0,c);Check(Near(t.net,-1.5),"stop gap worse than one R");
   MaStartTrade(t,base,base,1,0,100,1,1,c);MqlRates q;ZeroMemory(q);q.time=base;q.high=121;q.low=89;
   MaWithinBar(t,q,.01,0);Check(t.data&&t.done,"ambiguous M1 excluded");
   MaStartTrade(t,base,base,1,0,100,1,1,c);q.high=121;q.low=99;MaWithinBar(t,q,.01,0);Check(t.done&&!t.data&&Near(t.net,2),"TP exact R");
   c.management=2;MaStartTrade(t,base,base,1,0,100,1,1,c);MaAtClose(t,115,0,1,c);
   Check(t.pendingPartial&&Near(t.stop,100),"partial scheduled and BE at closed bar");MaAtOpen(t,115,0,base+60,0,c);MaFinish(t,120,base+120,"TP",0);
   Check(Near(t.net,1.75)&&Near(t.remaining,.5),"weighted partial pnl");
   c.management=3;MaStartTrade(t,base,base,1,0,100,1,1,c);MaAtClose(t,115,0,2,c);double best=t.stop;MaAtClose(t,112,0,2,c);
   Check(Near(best,113)&&Near(t.stop,best),"trailing never loosens");
   ArrayResize(g_results,3);g_asof=base+365*86400;double pnls[]={2,-1,.25};
   for(int i=0;i<3;i++){ZeroMemory(g_results[i]);g_results[i].at=g_asof-(30-i*10)*86400;g_results[i].net=pnls[i];g_results[i].regime=0;g_results[i].done=true;}
   int wins,losses,data,rw[],rl[];double net,minimum,dd;
   g_weeks=52;MaStats(wins,losses,data,net,minimum,dd,rw,rl);Check(wins==2&&losses==1&&Near(net,1.25)&&Near(dd,1),"cached annual stats");
   g_weeks=2;MaStats(wins,losses,data,net,minimum,dd,rw,rl);Check(wins==1&&losses==0&&Near(net,.25)&&ArraySize(g_results)==3,"narrow window slices cache without mutating it");
   g_weeks=52;MaStats(wins,losses,data,net,minimum,dd,rw,rl);Check(Near(net,1.25),"broad cache retained");
   g_loading=false;MaDraw();ObjectSetString(0,g_prefix+"UI_ADXMIN",OBJPROP_TEXT,"42.5");MaUiEvent(CHARTEVENT_OBJECT_CLICK,g_prefix+"UI_APPLY");
   Check(Near(g_cfg.adxMin,42.5)&&g_loading,"APPLY reads latest edits and invalidates audit");
   g_loading=false;MaUiEvent(CHARTEVENT_OBJECT_CLICK,g_prefix+"UI_PIPS");Check(!g_loading,"editing field does not act like Apply");
   g_popup=true;bool vol=g_cfg.volOn;MaUiEvent(CHARTEVENT_OBJECT_CLICK,g_prefix+"UI_VOL");Check(g_cfg.volOn==vol,"popup blocks underlying filter click");
   MaUiEvent(CHARTEVENT_OBJECT_CLICK,g_prefix+"UI_POPX"); // POPX does not exist until popup is drawn.
   MaDraw();MaUiEvent(CHARTEVENT_OBJECT_CLICK,g_prefix+"UI_POPX");Check(!g_popup,"popup close");
   ObjectsDeleteAll(0,g_prefix);
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+",\"failures\":\""+failures+"\"}";
   int file=FileOpen("MaCrossOverProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);if(file!=INVALID_HANDLE){FileWriteString(file,result);FileClose(file);}
   Print("MA_CROSSOVER_PROBE ",result);
}
