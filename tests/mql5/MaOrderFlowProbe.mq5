#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowCore.mqh"
int checks=0,failed=0;
void Check(bool yes,string label){checks++;if(!yes){failed++;Print("FAIL ",label);}}
bool Near(double a,double b){return MathAbs(a-b)<1e-8;}
void Fixture(MqlRates &bars[],MqlTick &ticks[])
{
   ArrayResize(bars,3);ArrayResize(ticks,12);
   double p[]={100,101,100,101,101,100,101,100,101,102,103,104};
   for(int b=0;b<3;b++)
   {
      ZeroMemory(bars[b]);bars[b].time=(datetime)(1000+b*60);bars[b].tick_volume=4;
      bars[b].open=p[b*4];bars[b].close=p[b*4+3];bars[b].high=0;bars[b].low=1000;
      for(int j=0;j<4;j++)
      {
         int i=b*4+j;ZeroMemory(ticks[i]);ticks[i].bid=p[i];ticks[i].flags=TICK_FLAG_BID;
         ticks[i].time_msc=((long)bars[b].time+j)*1000;ticks[i].time=(datetime)(ticks[i].time_msc/1000);
         bars[b].low=MathMin(bars[b].low,p[i]);bars[b].high=MathMax(bars[b].high,p[i]);
      }
   }
}
void OnStart()
{
   McOfConfig c={1,2,4,0.7,1.0,0.1},decoded;
   Check(McOfConfigRead(McOfConfigText(c),decoded),"settings roundtrip");
   Check(!McOfConfigRead("nonsense,2,4,.7,1,.1",decoded),"malformed settings rejected");
   MqlRates bars[];MqlTick ticks[];Fixture(bars,ticks);McOfSnapshot s;
   Check(McOfCalculate(ticks,bars,60,0.01,c,s),"complete bid history");
   Check(Near(s.profileCount,8)&&Near(s.buy+s.sell+s.neutral,4),"tick mass conserved");
   Check(Near(s.val,100)&&Near(s.vah,101)&&Near(s.poc,100.125),"profile excludes signal candle and deterministic ties");
   Check(Near(s.delta,1)&&Near(s.activity,1),"per-event delta (not cumulative delta summed again)");
   Check(McOfAllows(c,s,bars[2],1)&&!McOfAllows(c,s,bars[2],-1),"breakout direction");
   McOfSnapshot baseline=s;
   ArrayResize(ticks,13);ticks[12]=ticks[11];ticks[12].time_msc=1180000;ticks[12].bid=99999;
   Check(McOfCalculate(ticks,bars,60,0.01,c,s)&&Near(s.delta,baseline.delta)&&Near(s.poc,baseline.poc),"future tick cannot change signal");
   ticks[12]=ticks[11];ticks[12].time_msc++;ticks[12].flags=TICK_FLAG_ASK;ticks[12].bid=1;
   Check(McOfCalculate(ticks,bars,60,0.01,c,s)&&Near(s.profileCount,8),"ask-only event contributes zero");
   ArrayResize(ticks,11);
   Check(!McOfCalculate(ticks,bars,60,0.01,c,s)&&StringFind(s.reason,"OF_DATA_COVERAGE")==0,"missing tick fails closed");
   Check(!McOfAllows(c,s,bars[2],1),"invalid snapshot cannot allow entry");
   Fixture(bars,ticks);ticks[5].time_msc=ticks[4].time_msc-1;
   Check(!McOfCalculate(ticks,bars,60,0.01,c,s),"unsorted ticks rejected");
   Fixture(bars,ticks);ticks[2].bid=500;
   Check(!McOfCalculate(ticks,bars,60,0.01,c,s),"tick/bar mismatch rejected");
   Fixture(bars,ticks);
   for(int i=0;i<12;i++)ticks[i].bid=300-ticks[i].bid;
   for(int i=0;i<3;i++){double lo=bars[i].low;bars[i].low=300-bars[i].high;bars[i].high=300-lo;bars[i].open=300-bars[i].open;bars[i].close=300-bars[i].close;}
   Check(McOfCalculate(ticks,bars,60,0.01,c,s)&&Near(s.delta,-1)&&McOfAllows(c,s,bars[2],-1),"buy/sell mirror symmetry");
   c.mode=2;s.valid=true;s.val=100;s.vah=110;s.delta=0.5;s.activity=2;
   bars[2].low=99;bars[2].close=102;
   Check(McOfAllows(c,s,bars[2],1),"VAL rejection");
   bars[2].close=99;Check(!McOfAllows(c,s,bars[2],1),"no reclaim rejected");
   bars[2].close=102;s.activity=0.5;s.delta=0.05;
   c.mode=MC_OF_PROFILE;Check(McOfAllows(c,s,bars[2],1),"profile-only does not imply activity or delta");
   c.mode=MC_OF_ACTIVITY;Check(!McOfAllows(c,s,bars[2],1),"activity-only threshold");
   c.mode=MC_OF_DELTA;Check(!McOfAllows(c,s,bars[2],1),"delta-only threshold");
   s.activity=2;s.delta=0.5;
   c.mode=MC_OF_ACTIVITY;Check(McOfAllows(c,s,bars[2],1),"activity-only pass");
   c.mode=MC_OF_DELTA;Check(McOfAllows(c,s,bars[2],1),"delta-only pass");
   c.mode=0;s.valid=false;Check(McOfAllows(c,s,bars[2],1),"OFF preserves original decision");
   for(int n=4;n<=128;n++)
   {
      double h[];ArrayResize(h,n);double total=0;
      for(int j=0;j<n;j++){h[j]=(j*17+3)%13;total+=h[j];}
      Check(McOfValueArea(h,50,0.25,0.7,s),"VA calculation");
      int a=(int)MathRound((s.val-50)/0.25),b=(int)MathRound((s.vah-50)/0.25);double enclosed=0;
      for(int j=a;j<b;j++)enclosed+=h[j];
      Check(Near(s.profileCount,total)&&enclosed+1e-8>=total*0.7&&s.poc>=s.val&&s.poc<=s.vah,"VA contains requested mass and POC");
   }
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("MaOrderFlowProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
