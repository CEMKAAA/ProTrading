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
   string wanted="TCAL1=1,0,64,8192,0,0,0,0,1,3,4,360";
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
      string savedSymbol=g_userStrategies[slot].symbol;
      int savedFamily=g_userStrategies[slot].preset.family;
      g_userStrategies[slot].symbol="EURUSDm";
      g_userStrategies[slot].preset.family=ORB_PRESET_FAMILY_ANY;
      OrbStrategyPreset exotic=saved;exotic.family=ORB_PRESET_FAMILY_ANY;
      g_strategyFilterPair="EURUSDm";
      Check(OrbStrategyPresetPassesMetricFilters(exotic),"saved exotic pair passes its own filter");
      g_strategyFilterPair="USDJPY";
      Check(!OrbStrategyPresetPassesMetricFilters(exotic),"other pair excluded");
      g_strategyFilterPair="";
      bool exoticFound=false;
      for(int k=0;k<OrbStrategyPresetCount()+1;k++){OrbStrategyCyclePairFilter();if(g_strategyFilterPair=="EURUSDm"){exoticFound=true;break;}}
      Check(exoticFound,"PAIR cycle includes saved EURUSDm");
      g_strategyFilterPair="";
      g_userStrategies[slot].symbol=savedSymbol;
      g_userStrategies[slot].preset.family=savedFamily;
      int recordedTf=g_userStrategies[slot].chartTf;
      g_userStrategies[slot].chartTf=((int)_Period==(int)PERIOD_M1?(int)PERIOD_H1:(int)PERIOD_M1);
      string reason="";
      Check(OrbUserValidate(saved,reason),"same symbol accepts another recorded chart TF");
      g_maRestoringPreset=true;
      g_rtSignalTf=PERIOD_M5;
      Check(OrbUserApply(saved),"cross chart TF strategy applies");
      g_maRestoringPreset=false;
      Check(OrbUserMatches(saved),"cross chart TF runtime restored exactly");
      string recordedSymbol=g_userStrategies[slot].symbol;
      g_userStrategies[slot].symbol="__OTHER_SYMBOL__";
      Check(!OrbUserValidate(saved,reason)&&reason=="CUSTOM_SYMBOL_MISMATCH","another symbol still rejected");
      g_userStrategies[slot].symbol=recordedSymbol;
      g_userStrategies[slot].chartTf=recordedTf;
      FileDelete(OrbUserFile(slot),FILE_COMMON);
      FileDelete("MaCrossOrbStrategyLibrary\\"+saved.id+".metrics",FILE_COMMON);
   }
   GlobalVariableDel(OrbStrategyPresetSelectionKey());
   GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("MaTimeMatrixStrategyProbe_183948.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
