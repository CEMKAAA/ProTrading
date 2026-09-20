#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool yes,string label){checks++;if(!yes){failed++;Print("FAIL ",label," ",g_userStrategyNote);}}
void OnStart()
{
   g_runtimeMagic=9192026000+(long)(GetTickCount64()%1000000);
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   g_orbBridgeEnabled=false;g_maIndependent=true;g_maMaxConsecutive=20;
   g_mcOf.mode=MC_OF_EITHER;g_mcOf.lookback=36;g_mcOf.bins=48;g_mcOf.minActivity=1.25;
   string name="__MA_SAVE_PROBE_"+(string)GetTickCount64();
   Check(OrbUserSave(name),"save independent 20");
   OrbStrategyPreset saved;int index=g_strategyPresetIndex;
   Check(OrbStrategyPresetLoad(index,saved),"load record");
   int slot=OrbUserSlot(saved.id),oldCount=g_userCount;string identity=saved.id;
   if(slot>=0)
   {
      Check(g_userStrategies[slot].independent&&g_userStrategies[slot].maxSeries==20,"metadata readback");
      g_maIndependent=false;g_maMaxConsecutive=1;g_maRestoringPreset=true;
      g_mcOf.mode=MC_OF_OFF;g_mcOf.lookback=24;
      OrbUserApply(saved);g_maRestoringPreset=false;
      Check(g_maIndependent&&g_maMaxConsecutive==20&&OrbUserMatches(saved),"startup restores exact mode and series");
      Check(g_mcOf.mode==MC_OF_EITHER&&g_mcOf.lookback==36&&g_mcOf.bins==48&&g_mcOf.minActivity==1.25,"order flow preset restores exactly");
      g_maIndependent=false;g_maMaxConsecutive=7;
      Check(OrbUserSave(name),"same name update");
      Check(g_userCount==oldCount&&g_strategyPresetIndex==index,"no duplicate slot");
      Check(OrbStrategyPresetLoad(index,saved)&&saved.id==identity,"identity retained");
      Check(!g_userStrategies[slot].independent&&g_userStrategies[slot].maxSeries==7,"updated metadata");
      FileDelete(OrbUserFile(slot),FILE_COMMON);
      FileDelete("MaCrossOrbStrategyLibrary\\"+identity+".metrics",FILE_COMMON);
   }
   Check(!AuditTickReadComplete(50,4403),"positive partial timeout rejected");
   Check(!AuditTickReadComplete(-1,0),"negative count rejected");
   Check(AuditTickReadComplete(50,0)&&AuditTickReadComplete(0,0),"complete and empty valid intervals");
   McOfReset();g_mcOf.mode=MC_OF_BREAKOUT;g_rtInvertMode=false;
   long enabledSignature=NasPendingConfigSignature();
   g_mcOf.mode=MC_OF_OFF;
   Check(enabledSignature!=NasPendingConfigSignature(),"pending candidate invalidated by flow policy");
   string reason="",detail="";
   Check(ModernFilterAllows(0,0,PERIOD_M5,1000,"BUY",false,ORB_FVG_OFF,reason,detail),"OF OFF no data access gate");
   g_mcOf.mode=MC_OF_BREAKOUT;
   g_mcOfCache[0].key=_Symbol+"/"+(string)PERIOD_M5+"/"+(string)(datetime)1000+McOfIdentity();
   g_mcOfCache[0].snapshot.valid=true;g_mcOfCache[0].snapshot.val=100;g_mcOfCache[0].snapshot.vah=105;
   g_mcOfCache[0].snapshot.delta=0.8;g_mcOfCache[0].snapshot.activity=2;
   g_mcOfCache[0].signal.close=106;g_mcOfCache[0].signal.high=107;g_mcOfCache[0].signal.low=102;
   Check(ModernFilterAllows(0,0,PERIOD_M5,1000,"BUY",false,ORB_FVG_OFF,reason,detail),"shared gate accepts confirmed buy");
   g_rtInvertMode=true;
   Check(!ModernFilterAllows(0,0,PERIOD_M5,1000,"BUY",false,ORB_FVG_OFF,reason,detail)&&reason=="OF_BLOCK","filter uses executed inverted direction");
   OrbWindowSignal windows[];
   AppendOrbWindowSignal(windows,1000,"BUY","OF_BLOCK",100,101,99);
   AppendOrbWindowSignal(windows,1000,"BUY","OF_DATA_BARS",100,101,99);
   Check(ArraySize(windows)==0,"OF rejects do not create window exit events");
   AppendOrbWindowSignal(windows,1000,"BUY","VOL_LOW",100,101,99);
   Check(ArraySize(windows)==1,"original window behavior retained");
   GlobalVariableDel(OrbStrategyPresetSelectionKey());GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("20260920_202901_MaStrategySaveProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
