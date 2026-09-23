#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label," ",g_userStrategyNote);}}
void OnStart()
{
   FolderCreate("MaCrossOrbStrategyLibrary",FILE_COMMON);
   g_runtimeMagic=9192026000+(long)(GetTickCount64()%1000000);
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);
   Check(OrbStrategyPresetApplyValues(defaults),"default preset applies");
   string wanted="TCAL1=1,0,64,8192,0,0,0,0";
   Check(TCalStrategyApplyText(wanted),"set per-day hours");
   string name="__MA_TCAL_PROBE_"+(string)GetTickCount64();
   Check(OrbUserSave(name),"save strategy");
   OrbStrategyPreset saved;int index=g_strategyPresetIndex;
   Check(OrbStrategyPresetLoad(index,saved),"load record");
   int slot=OrbUserSlot(saved.id);
   if(slot>=0)
   {
      Check(g_userStrategies[slot].timeMatrix==wanted,"record contains time matrix");
      Check(TCalStrategyApplyText(TCalStrategyOffText()),"clear current filter");
      g_maRestoringPreset=true;
      Check(OrbUserApply(saved),"apply saved strategy");
      g_maRestoringPreset=false;
      Check(TCalStrategyMatchesText(wanted),"restore exact schedule");
      Check(OrbUserMatches(saved),"strategy runtime matches");
      FileDelete(OrbUserFile(slot),FILE_COMMON);
      FileDelete("MaCrossOrbStrategyLibrary\\"+saved.id+".metrics",FILE_COMMON);
   }
   GlobalVariableDel(OrbStrategyPresetSelectionKey());
   GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("MaTimeMatrixStrategyProbe_022408.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
