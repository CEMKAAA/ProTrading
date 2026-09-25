#define OnInit MaProbeUnusedInit
#define OnDeinit MaProbeUnusedDeinit
#define OnTimer MaProbeUnusedTimer
#define OnTick MaProbeUnusedTick
#define OnChartEvent MaProbeUnusedChartEvent
#define OnTradeTransaction MaProbeUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

int g_checks=0,g_failures=0;
void ProbeCheck(bool pass,string label)
{
   g_checks++;
   if(!pass){g_failures++;Print("ADV_REVERSE_STRATEGY_FAIL ",label);}
}

void ProbeRecord(int slot,string id,bool advanced,double maxCostPct)
{
   g_rtInvertMode=true;
   g_rtAdvancedReverse=advanced;
   OrbStrategyPreset p;OrbCustomCapturePreset(p);
   p.id=id;p.name=id;p.family=OrbUserSymbolFamily(_Symbol);
   g_userStrategies[slot].valid=true;
   g_userStrategies[slot].preset=p;
   g_userStrategies[slot].symbol=_Symbol;
   g_userStrategies[slot].chartTf=(int)_Period;
   g_userStrategies[slot].inputSignature=OrbCustomInputSignature();
   g_userStrategies[slot].runtime=OrbCustomRuntimeDump();
   g_userStrategies[slot].independent=false;
   g_userStrategies[slot].maxSeries=1;
   g_userStrategies[slot].reverseExit=false;
   g_userStrategies[slot].reverseWait=0;
   g_userStrategies[slot].advancedReverse=advanced;
   g_userStrategies[slot].advancedReverseMaxCostPct=maxCostPct;
   g_userStrategies[slot].orderFlow=g_mcOf;
   g_userStrategies[slot].timeMatrix=TCalStrategyOffText();
}

void OnStart()
{
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);
   OrbStrategyPresetApplyValues(defaults);
   g_rtSignalTf=PERIOD_M1;
   g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtTargetLeg=ORB_TARGET_R100;
   g_maIndependent=false;g_maMaxConsecutive=1;
   g_maReverseExit=false;g_maReverseWait=0;
   g_rtTimeExit=false;g_rtFilteredWindowReverseExit=false;
   g_rtPostTradeDispBlockExit=false;g_rtBEOnTp1=false;g_rtHalfBeLeg=0;
   g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_orbBridgeEnabled=false;g_orbNativeWithBridgeOnly=true;
   McOfConfigRead("0,24,32,0.70000000,1.00000000,0.10000000",g_mcOf);
   g_userLoaded=true;g_userCount=2;ArrayResize(g_userStrategies,2);
   ProbeRecord(0,"user_probe_full_inverse",false,100.0);
   ProbeRecord(1,"user_probe_advanced_reverse",true,1.0);
   ProbeCheck(g_userStrategies[0].preset.invertMode&&g_userStrategies[1].preset.invertMode,
      "both records have inverted direction");
   ProbeCheck(!g_userStrategies[0].advancedReverse&&g_userStrategies[1].advancedReverse,
      "distinct reverse metadata");
   g_rtInvertMode=false;g_rtAdvancedReverse=false;g_rtAdvancedReverseMaxCostPct=100.0;
   ProbeCheck(OrbUserApply(g_userStrategies[1].preset),"apply advanced strategy");
   ProbeCheck(g_rtInvertMode&&g_rtAdvancedReverse,"advanced mode restored");
   ProbeCheck(MathAbs(g_rtAdvancedReverseMaxCostPct-1.0)<1e-8,"advanced max cost restored");
   ProbeCheck(OrbUserMatches(g_userStrategies[1].preset),"advanced exact match");
   g_rtAdvancedReverse=false;LoadRuntimeAdvancedReverse();
   ProbeCheck(g_rtAdvancedReverse,"advanced survives restart load");
   ProbeCheck(MathAbs(g_rtAdvancedReverseMaxCostPct-1.0)<1e-8,"advanced cost survives restart load");
   ProbeCheck(OrbUserApply(g_userStrategies[0].preset),"apply full inverse strategy");
   ProbeCheck(g_rtInvertMode&&!g_rtAdvancedReverse,"full inverse excludes advanced");
   ProbeCheck(MathAbs(g_rtAdvancedReverseMaxCostPct-100.0)<1e-8,"full inverse does not inherit cost gate");
   ProbeCheck(OrbUserMatches(g_userStrategies[0].preset),"full inverse exact match");
   g_rtAdvancedReverse=true;LoadRuntimeAdvancedReverse();
   ProbeCheck(!g_rtAdvancedReverse,"full inverse survives restart separately");
   g_rtAdvancedReverse=true;g_rtAdvancedReverseMaxCostPct=1.0;
   g_rtPipSlMode=false;g_rtTargetMode=ORB_TARGET_R_LEG;g_rtTargetLeg=ORB_TARGET_R100;
   double tick=TickSize(),price=NormalizeTradePrice(SymbolInfoDouble(_Symbol,SYMBOL_BID));
   for(int side=0;side<2;side++)
   {
      bool sourceBuy=(side==0);
      double sourceSl=NormalizeTradePrice(price+(sourceBuy?-1.0:1.0)*100.0*tick);
      double oppositeEntry=NormalizeTradePrice(price+(sourceBuy?-1.0:1.0)*tick);
      OrbPureSwapGeometry geometry;string detail="";
      ProbeCheck(!ResolvePureSwapGeometry(sourceBuy,!sourceBuy,price,oppositeEntry,sourceSl,geometry,detail,true)
         &&StringFind(detail,"ADV_REVERSE_SPREAD_BLOCK")==0,"one-tick spread rejected at 1% side="+(string)side);
      ProbeCheck(ResolvePureSwapGeometry(sourceBuy,!sourceBuy,price,price,sourceSl,geometry,detail,true)
         &&geometry.execTargetR>=0.99,"zero spread passes 1% side="+(string)side);
      ProbeCheck(ResolvePureSwapGeometry(sourceBuy,!sourceBuy,price,oppositeEntry,sourceSl,geometry,detail,false),
         "quote-less preflight does not fabricate a spread block side="+(string)side);
   }
   int out=FileOpen("MaAdvancedReverseStrategyProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out!=INVALID_HANDLE){FileWrite(out,"checks","failures");FileWrite(out,g_checks,g_failures);FileClose(out);}
   Print("ADV_REVERSE_STRATEGY_CHECKS=",g_checks," FAILURES=",g_failures);
}
