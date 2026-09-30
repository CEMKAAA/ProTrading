#property strict
#include "../../../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"
#include "../../../../IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("MA_WINDOW_FAIL ",label," ",g_maCrossAuditFailure);}}
string Identity()
{
   string result="";
   for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)
   {
      MaCrossAuditEvent e=g_maCrossAuditEvents[i];
      result+=(string)e.signalTime+"|"+(string)e.direction+"|"+StringFormat("%.17g",e.close)
         +"|"+StringFormat("%.17g",e.high)+"|"+StringFormat("%.17g",e.low)
         +"|"+StringFormat("%.17g",e.volume)+"|"+StringFormat("%.17g",e.priorVolume)
         +"|"+StringFormat("%.17g",e.markerPrice)+"\n";
   }
   return result;
}
bool Build(string symbol,datetime from,datetime to,int mode,int fast=50)
{return MaCrossAuditBuild(symbol,PERIOD_M5,from,to,(MA_CROSS_SIGNAL_MODE)mode,MA_CROSS_PAIR_FAST,fast,100,200);}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   string symbol="MAWIN_"+(string)GetTickCount64();
   Check(CustomSymbolCreate(symbol,"Tests","USDJPYm"),"create isolated history fixture");
   Check(SymbolSelect(symbol,true),"select fixture");
   datetime last=D'2026.09.29 18:00',from=last-1820*86400,to=last+301;
   MqlRates rates[];ArrayResize(rates,4*1820+1);
   for(int i=0;i<ArraySize(rates);i++)
   {
      ZeroMemory(rates[i]);rates[i].time=from+i*21600;
      rates[i].open=150+2*MathSin(i*0.19);rates[i].close=150+2*MathSin((i+1)*0.19);
      rates[i].high=MathMax(rates[i].open,rates[i].close)+0.05;
      rates[i].low=MathMin(rates[i].open,rates[i].close)-0.05;
      rates[i].tick_volume=100+i%17;rates[i].spread=10;
   }
   Check(CustomRatesUpdate(symbol,rates)==ArraySize(rates),"install five-year sparse bars");
   MqlRates warm[];
   for(int retry=0;retry<100;retry++)
   {
      int main=CopyRates(symbol,PERIOD_M5,0,10000,warm);
      datetime first=main>0?warm[0].time:0;
      int higher=CopyRates(symbol,PERIOD_H4,0,10000,warm);
      datetime firstHigher=higher>0?warm[0].time:0;
      if(McHistorySeed(symbol,PERIOD_M5)>0&&SeriesInfoInteger(symbol,PERIOD_M5,SERIES_SYNCHRONIZED)
         &&McHistorySeed(symbol,PERIOD_H4)>0&&SeriesInfoInteger(symbol,PERIOD_H4,SERIES_SYNCHRONIZED)
         &&first<=from&&firstHigher<=from)break;
      Sleep(100);
   }
   Print("MA_WINDOW_FIXTURE first=",TimeToString(McHistorySeed(symbol,PERIOD_M5))," expected=",TimeToString(from));
   Check(McHistorySeed(symbol,PERIOD_M5)<=from,"fixture includes all five years");
   long totalWarm=0,totalCold=0;
   for(int mode=0;mode<6;mode++)
   {
      MaCrossAuditInvalidate();Check(Build(symbol,from,to,mode),"5Y cold mode "+(string)mode);
      string full=Identity();int fullCount=ArraySize(g_maCrossAuditEvents);
      if(mode!=4)Check(fullCount>0,"mode has source signals "+(string)mode);
      datetime windows[]={last-1092*86400,last-364*86400,last-35*86400,last-14*86400,from};
      for(int w=0;w<ArraySize(windows);w++)
      {
         long builds=g_maCrossAuditBuildCount;ulong start=GetTickCount64();
         Check(Build(symbol,windows[w],to+1,mode),"warm window succeeds");
         totalWarm+=(long)(GetTickCount64()-start);
         Check(g_maCrossAuditBuildCount==builds,"window/advancing second does not replay kernel");
         string reused=Identity();int count=ArraySize(g_maCrossAuditEvents);
         for(int j=0;j<count;j++)Check(g_maCrossAuditEvents[j].signalTime>=windows[w],"no older-window events leak");
         if(w==0&&fullCount>0)Check(count<fullCount,"3Y is strictly smaller than 5Y");
         if(w==4)Check(reused==full,"return to 5Y retains full source cache");
         // Save the superset, force a cold build, then restore it for the next view.
         MaCrossAuditEvent stored[];ArrayCopy(stored,g_maCrossAuditStoredEvents);
         MaCrossAuditInvalidate();start=GetTickCount64();
         Check(Build(symbol,windows[w],to+1,mode),"cold comparison succeeds");
         totalCold+=(long)(GetTickCount64()-start);
         Check(reused==Identity(),"warm/cold timestamps, direction, prices and volume are identical");
         ArrayCopy(g_maCrossAuditStoredEvents,stored);g_maCrossAuditFrom=from;
      }
      long builds=g_maCrossAuditBuildCount;
      Check(Build(symbol,from,to,mode,51),"changed period succeeds");
      Check(g_maCrossAuditBuildCount==builds+1,"changed settings invalidate kernel cache");
   }
   // Market-history timing is reported separately from the sparse fixture.
   MaCrossAuditInvalidate();datetime marketTo=iTime("USDJPYm",PERIOD_M5,1)+301;
   datetime marketFrom=marketTo-1820*86400;
   MqlRates market[];CopyRates("USDJPYm",PERIOD_M5,marketFrom,marketTo,market);
   ulong start=GetTickCount64();
   bool realReady=Build("USDJPYm",marketFrom,marketTo,5);
   long realCold=(long)(GetTickCount64()-start),realWarm=0,realFresh=0;
   if(realReady)
   {
      long builds=g_maCrossAuditBuildCount;start=GetTickCount64();
      Check(Build("USDJPYm",marketTo-1092*86400,marketTo+1,5),"USDJPY real 3Y cache view");
      realWarm=(long)(GetTickCount64()-start);
      Check(g_maCrossAuditBuildCount==builds,"USDJPY real view avoids cold kernel replay");
      string reused=Identity();int count=ArraySize(g_maCrossAuditEvents);
      MaCrossAuditInvalidate();start=GetTickCount64();
      Check(Build("USDJPYm",marketTo-1092*86400,marketTo+1,5),"USDJPY real fresh 3Y view");
      realFresh=(long)(GetTickCount64()-start);
      Check(reused==Identity(),"USDJPY real cached and fresh signals identical");
      Print("MA_WINDOW_MARKET cold5y_ms=",realCold," warm3y_ms=",realWarm," cold3y_ms=",realFresh," events3y=",count);
   }
   else Print("MA_WINDOW_MARKET unavailable: ",g_maCrossAuditFailure);
   int f=FileOpen("MaAuditWindowCacheProbe_36378555ff.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed
      +" fixture_warm_ms="+(string)totalWarm+" fixture_cold_ms="+(string)totalCold
      +" real_ready="+(realReady?"true":"false")+" real_cold5y_ms="+(string)realCold
      +" real_warm3y_ms="+(string)realWarm+" real_cold3y_ms="+(string)realFresh+"\n");FileClose(f);}
}
