#property strict
#include <Trade/Trade.mqh>
bool fixture=false;
long fixtureChart=934871;
int g_recoverySelected=-1;
struct FixturePosition {ulong ticket;long magic;int dir;string comment;};
FixturePosition g_recoveryPositions[];
long ProbeChart(){return fixture?fixtureChart:ChartID();}
int ProbePositions(){return fixture?ArraySize(g_recoveryPositions):PositionsTotal();}
ulong ProbeTicket(int i)
{
   if(!fixture)return PositionGetTicket(i);
   g_recoverySelected=i;return i>=0&&i<ArraySize(g_recoveryPositions)?g_recoveryPositions[i].ticket:0;
}
bool ProbeSelect(ulong ticket)
{
   if(!fixture)return PositionSelectByTicket(ticket);
   for(int i=0;i<ArraySize(g_recoveryPositions);i++)if(g_recoveryPositions[i].ticket==ticket){g_recoverySelected=i;return true;}
   g_recoverySelected=-1;return false;
}
long ProbeInteger(ENUM_POSITION_PROPERTY_INTEGER property)
{
   if(!fixture)return PositionGetInteger(property);
   if(g_recoverySelected<0||g_recoverySelected>=ArraySize(g_recoveryPositions))return 0;
   if(property==POSITION_MAGIC)return g_recoveryPositions[g_recoverySelected].magic;
   if(property==POSITION_TYPE)return g_recoveryPositions[g_recoverySelected].dir>0?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   if(property==POSITION_IDENTIFIER)return (long)g_recoveryPositions[g_recoverySelected].ticket;
   return 0;
}
bool ProbeInteger(ENUM_POSITION_PROPERTY_INTEGER property,long &out){out=ProbeInteger(property);return true;}
string ProbeString(ENUM_POSITION_PROPERTY_STRING property)
{
   if(!fixture)return PositionGetString(property);
   if(g_recoverySelected<0||g_recoverySelected>=ArraySize(g_recoveryPositions))return "";
   if(property==POSITION_SYMBOL)return _Symbol;
   if(property==POSITION_COMMENT)return g_recoveryPositions[g_recoverySelected].comment;
   return "";
}
bool ProbeString(ENUM_POSITION_PROPERTY_STRING property,string &out){out=ProbeString(property);return true;}
#define ChartID ProbeChart
#define PositionsTotal ProbePositions
#define PositionGetTicket ProbeTicket
#define PositionSelectByTicket ProbeSelect
#define PositionGetInteger ProbeInteger
#define PositionGetString ProbeString
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "EntryEngineLabEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
string failures="";
void Check(bool ok,string why){checks++;if(!ok){failed++;failures+=why+"\n";Print("RECOVERY_FAIL ",why);}}
void Seed(long owned)
{
   ArrayResize(g_recoveryPositions,3);
   for(int i=0;i<3;i++)
   {
      g_recoveryPositions[i].ticket=(ulong)(90000001+i);g_recoveryPositions[i].magic=i<2?owned:owned+1;
      g_recoveryPositions[i].dir=-1;g_recoveryPositions[i].comment="MAI|1791019800";
   }
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   int f=FileOpen("ModeRecovery_8cdb5d965b.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE)return;
   // Observe broker g_recoveryPositions only. Never invoke OnInit, entry/close, or a publisher.
   FileWriteString(f,"broker_positions="+(string)PositionsTotal()+"\n");
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0)continue;
      FileWriteString(f,"broker ticket="+(string)ticket+" symbol="+PositionGetString(POSITION_SYMBOL)
         +" magic="+(string)PositionGetInteger(POSITION_MAGIC)+" comment="+PositionGetString(POSITION_COMMENT)+"\n");
   }
   fixture=true;long before=RuntimeMagic();
#ifndef RECOVERY_SOL
   g_runtimeMagic=0;
#endif
   Check(RuntimeMagic()==before,"same saved chart identity restores the same magic");
   fixtureChart++;
#ifndef RECOVERY_SOL
   g_runtimeMagic=0;
#endif
   Check(RuntimeMagic()!=before,"new chart identity remains isolated");
   fixtureChart--;
#ifndef RECOVERY_SOL
   g_runtimeMagic=0;
#endif
   Seed(before);
#ifdef RECOVERY_SOL
   Check(OwnPositionCount()==2&&LnNasOpenCount(-1)==2&&LnNasOpenCount(1)==0,"Sol counts restored same-magic native g_recoveryPositions only");
   g_recoveryPositions[0].dir=1;
   Check(OwnPositionCount(1)==1&&LnNasOpenCount(-1)==1,"Sol per-direction count after restart");
   LnNasDefaults(g_lnNas);g_lnNas.independent=true;g_lnNas.maxSameOpen=10;
   ErlSignal s;ZeroMemory(s);s.dir=-1;s.availableTime=TimeCurrent();
   Check(LnNasLiveAccept(s),"Sol second same-direction signal allowed below cap");
   g_lnNas.maxSameOpen=1;
   Check(!LnNasLiveAccept(s)&&g_lastBlock=="MAX_SAME_OPEN","Sol refuses full same-direction cap");
#else
   Check(OwnPositionCount()==2,"native ownership recovers two matching g_recoveryPositions, not foreign one");
#ifndef RECOVERY_ORB
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtHalfBeLeg=0;g_rtBEOnTp1=false;g_rtTimeExit=false;
   g_rtFilteredWindowReverseExit=false;g_rtPostTradeDispBlockExit=false;
   g_rtEntryMode=ORB_ENTRY_BREAKOUT;g_rtNasConfirmation=false;g_orbBridgeEnabled=false;
   g_maIndependent=true;g_maMaxConsecutive=10;
   int buys=0,sells=0;
   Check(MaNativeOpenCount(buys,sells)==2&&buys==0&&sells==2,"Independent counter reads restored native sells");
   Check(MaOpenCapacityAllows(MaNativeOpenCount(),10),"second/third sell not blocked by an existing sell below MAX");
   Check(!MaOpenCapacityAllows(MaNativeOpenCount(),2),"MAX blocks only at actual OPEN occupancy");
   g_recoveryPositions[0].dir=1;
   Check(MaNativeOpenCount(buys,sells)==2&&buys==1&&sells==1,"Ma/Lab MAX uses total simultaneous native g_recoveryPositions");
   Check(MaOpenCounterText(MaNativeOpenCount())=="OPEN 2/10","counter restores without any new signal");
   MaIndependentIdentity();
   bool fresh=!FileIsExist(g_maSeriesFile);
   Check(fresh,"isolated recovery state fixture must not overwrite existing files");
   if(fresh)
   {
      g_maSeriesDir=-1;g_maSeriesCount=876;g_maSeriesBar=D'2026.09.28 09:30';g_maSeriesUncertain=false;
      Check(MaIndependentWrite(),"write existing confirmed order state fixture");
      MaIndependentRelease();g_maSeriesDir=0;g_maSeriesCount=0;g_maSeriesBar=0;
      Check(MaIndependentAcquire(),"reacquire persisted state with open native exposure");
      Check(g_maSeriesDir==-1&&g_maSeriesCount==876&&!g_maSeriesUncertain,"order state preserved after reattach");
      Check(MaOpenCapacityAllows(MaNativeOpenCount(),g_maMaxConsecutive),"historical sequence count never substitutes for OPEN count");
      MaIndependentRelease();FileDelete(g_maSeriesFile);FileDelete(g_maSeriesFile+".lock");
   }
#endif
#endif
   FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+"\n"+failures);
   FileClose(f);fixture=false;EventKillTimer();
}
