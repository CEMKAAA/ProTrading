#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label);}}
void OnStart()
{
   string symbols[]={"BTCUSDm","USDJPYm"};
   datetime asOf=D'2026.10.09 19:46:57';
   for(int s=0;s<ArraySize(symbols)&&!IsStopped();s++)
   {
      string symbol=symbols[s];SymbolSelect(symbol,true);
      ENUM_TIMEFRAMES tf=s==0?PERIOD_M5:PERIOD_M15;
      string detail="";bool blocked=false,ready=false;
      ulong started=GetTickCount64();datetime seed=0;
      while(!IsStopped()&&GetTickCount64()-started<240000)
      {
         seed=McHistorySeed(symbol,tf);
         if(McHistoryReady(symbol,tf,seed,detail,blocked)){ready=true;break;}
         if(blocked)break;Sleep(250);
      }
      Print("ORIGIN_PROBE symbol=",symbol," server=",(datetime)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_SERVER_FIRSTDATE),
         " terminal=",(datetime)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_TERMINAL_FIRSTDATE),
         " loaded=",(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE)," seed=",seed," ready=",ready," detail=",detail);
      Check(ready,"complete recursive prefix "+symbol);if(!ready)continue;
      datetime from=asOf-260*7*86400;
      MaCrossAuditInvalidate();
      bool built=MaCrossAuditBuild(symbol,tf,from,asOf,MA_CROSS_TRENDER_IQ,MA_CROSS_PAIR_FAST,9,27,200);
      Check(built,"wide kernel "+symbol);if(!built)continue;
      Check(MaCrossAuditOriginStable(),"wide origin stable "+symbol);
      datetime narrow=asOf-2*7*86400;
      Check(MaCrossAuditBuild(symbol,tf,narrow,asOf,MA_CROSS_TRENDER_IQ,MA_CROSS_PAIR_FAST,9,27,200),"narrow reuse "+symbol);
      MaCrossAuditEvent expected[];ArrayCopy(expected,g_maCrossAuditEvents);
      Check(g_maCrossAuditReuseCount>0,"event cache reused "+symbol);
      // Rebuild without the wide cache: identical closed-bar signals must result.
      MaCrossAuditInvalidate();
      Check(MaCrossAuditBuild(symbol,tf,narrow,asOf,MA_CROSS_TRENDER_IQ,MA_CROSS_PAIR_FAST,9,27,200),"fresh narrow "+symbol);
      Check(ArraySize(expected)==ArraySize(g_maCrossAuditEvents),"fresh/reused event count "+symbol);
      bool same=ArraySize(expected)==ArraySize(g_maCrossAuditEvents);
      for(int i=0;same&&i<ArraySize(expected);i++)
         same=expected[i].signalTime==g_maCrossAuditEvents[i].signalTime
            &&expected[i].direction==g_maCrossAuditEvents[i].direction&&expected[i].close==g_maCrossAuditEvents[i].close;
      Check(same,"fresh/reused exact signals "+symbol);
      Check(seed==McHistorySeed(symbol,tf),"origin unchanged across window order "+symbol);
   }
   int file=FileOpen("AuditHistoryOriginProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file!=INVALID_HANDLE){FileWriteString(file,"{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}");FileClose(file);}
}
