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
   string name="__MA_SAVE_PROBE_"+(string)GetTickCount64();
   Check(OrbUserSave(name),"save independent 20");
   OrbStrategyPreset saved;int index=g_strategyPresetIndex;
   Check(OrbStrategyPresetLoad(index,saved),"load record");
   int slot=OrbUserSlot(saved.id),oldCount=g_userCount;string identity=saved.id;
   if(slot>=0)
   {
      Check(g_userStrategies[slot].independent&&g_userStrategies[slot].maxSeries==20,"metadata readback");
      g_maIndependent=false;g_maMaxConsecutive=1;g_maRestoringPreset=true;
      OrbUserApply(saved);g_maRestoringPreset=false;
      Check(g_maIndependent&&g_maMaxConsecutive==20&&OrbUserMatches(saved),"startup restores exact mode and series");
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
   GlobalVariableDel(OrbStrategyPresetSelectionKey());GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("20260919_191919_MaStrategySaveProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
