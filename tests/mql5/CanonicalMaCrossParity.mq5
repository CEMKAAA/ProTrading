#property strict
datetime ParityNow(){return D'2026.10.05 00:00';}
string ParityKey(string key){return "PARITY."+(string)ChartID()+"."+key;}
bool ParityCheck(string key){return GlobalVariableCheck(ParityKey(key));}
double ParityGet(string key){return GlobalVariableGet(ParityKey(key));}
datetime ParitySet(string key,double value){return GlobalVariableSet(ParityKey(key),value);}
bool ParityDel(string key){return GlobalVariableDel(ParityKey(key));}
#define TimeCurrent ParityNow
#define GlobalVariableCheck ParityCheck
#define GlobalVariableGet ParityGet
#define GlobalVariableSet ParitySet
#define GlobalVariableDel ParityDel
#define OnInit CanonicalInit
#define OnDeinit CanonicalDeinit
#define OnTick CanonicalTick
#define OnTimer CanonicalTimer
#define OnChartEvent CanonicalChartEvent
#define OnTradeTransaction CanonicalTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef TimeCurrent
#undef GlobalVariableCheck
#undef GlobalVariableGet
#undef GlobalVariableSet
#undef GlobalVariableDel
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
string ParityClockText(int minutes){return StringFormat("%02d:%02d",minutes/60,minutes%60);}
#include "CanonicalParitySettings.mqh"
void ParityFailure(int file,string reason)
{FileWriteString(file,"error="+reason+"\n");FileFlush(file);Print("CANONICAL_PARITY_FAIL ",reason);}
void OnStart()
{
   int file=FileOpen("Stratum\\canonical-macross.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
   if(file==INVALID_HANDLE)return;
   FileWriteString(file,"inputSignature="+OrbCustomInputSignature()+"\n");
   for(int retry=0;retry<120&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   if(AccountInfoString(ACCOUNT_SERVER)!="Exness-MT5Trial15"||AccountInfoInteger(ACCOUNT_LOGIN)!=260460316
      ||TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){
      ParityFailure(file,"ISOLATED_DEMO_ALGO_OFF_REQUIRED");FileClose(file);return;
   }
   int initialized=CanonicalInit();EventKillTimer();
   if(initialized!=INIT_SUCCEEDED){ParityFailure(file,"INIT_REJECTED");FileClose(file);return;}
   OrbStrategyPreset p;string reason="";bool found=false;
   OrbUserReload(true);
   for(int i=0;i<OrbStrategyPresetCount();i++){
      if(!OrbStrategyPresetLoad(i,p)||!OrbUserValidate(p,reason))continue;
      found=true;break;
   }
   if(!found){ParityFailure(file,"NO_COMPATIBLE_SAVED_STRATEGY_"+reason);FileClose(file);CanonicalDeinit(REASON_PROGRAM);return;}
   g_maRestoringPreset=true;
   bool applied=OrbStrategyPresetApplyValues(p);g_maRestoringPreset=false;
   if(!applied||!OrbUserMatches(p)){ParityFailure(file,"SAVED_STRATEGY_APPLY_MISMATCH");FileClose(file);CanonicalDeinit(REASON_PROGRAM);return;}
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;
   g_rtHistoricalWeeks=2;g_rtAdvancedAuditEngine=true;g_histNeedsRedraw=true;g_lastHistBuild=0;
   FileWriteString(file,"name="+p.name+"\nstrategyId="+p.id+"\nsymbol="+_Symbol
      +"\nbrokerServer="+AccountInfoString(ACCOUNT_SERVER)+"\nto="+(string)(long)(ParityNow()-(int)MathRound(InpBrokerGmtOffsetHours*3600.0))+"\n");
   ParityCaptureSettings(file);FileFlush(file);
   ulong end=GetTickCount64()+300000,retryAt=0;
   DrawHistoricalSignals();
   while(GetTickCount64()<end&&!IsStopped()){
      ProcessHistoricalAuditStep();
      if(g_axReady&&!g_histAuditRunning&&!g_histCoveragePending)break;
      if(g_histCoveragePending&&GetTickCount64()>retryAt){g_histNeedsRedraw=true;DrawHistoricalSignals();retryAt=GetTickCount64()+5000;}
      Sleep(25);
   }
   if(!g_axReady||g_histCoveragePending){ParityFailure(file,"AUDIT_TIMEOUT_"+g_histCoverageDetail);FileClose(file);CanonicalDeinit(REASON_PROGRAM);return;}
   int count=ArraySize(g_axTrades);double net=0;
   FileWriteString(file,"rows="+(string)count+"\nTRADES\n");
   int offset=(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   for(int i=0;i<count;i++){
      AxTrade t=g_axTrades[i];if(t.valid&&t.closed)net+=t.netR;
      string why=t.reason;StringReplace(why,"|","/");StringReplace(why,"\n"," ");StringReplace(why,"\r"," ");
      FileWriteString(file,(string)(long)(t.signalTime-offset)+"|"+(string)(long)(t.entryTime-offset)+"|"+(string)(long)(t.exitTime>0?t.exitTime-offset:0)
         +"|"+(string)t.direction+"|"+DoubleToString(t.entry,12)+"|"+DoubleToString(t.sl,12)+"|"+DoubleToString(t.tp,12)
         +"|"+DoubleToString(t.exitPrice,12)+"|"+DoubleToString(t.netR,12)+"|"+(string)(int)t.valid+"|"+(string)(int)t.closed
         +"|"+why+"|"+(t.entrySpreadPoints==EMPTY_VALUE?"":DoubleToString(t.entrySpreadPoints*_Point,12))+"\n");
   }
   FileClose(file);Print("CANONICAL_PARITY_READY ",p.name," rows=",count," netR=",net);
   CanonicalDeinit(REASON_PROGRAM);
}
