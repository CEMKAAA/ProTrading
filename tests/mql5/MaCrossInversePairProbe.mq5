#define OnInit MaUnusedInit
#define OnDeinit MaUnusedDeinit
#define OnTimer MaUnusedTimer
#define OnTick MaUnusedTick
#define OnChartEvent MaUnusedChartEvent
#define OnTradeTransaction MaUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label);}}
void OnStart()
{
   g_rtInvertMode=true;g_rtPipSlMode=true;g_rtPipSlPips=10.0;
   g_rtTargetLeg=(int)ORB_TARGET_R100;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   Check(MathAbs(InpAdvancedReverseMaxCostPctDefault-10.0)<0.000001,
      "new instances default to the 10 percent quote-gap guard");
   double pip=OrbPipSize(),bid=150.000,ask=bid+1.3*pip;
   OrbPureSwapGeometry g;string detail="";
   g_rtAdvancedReverse=false;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail),"inverse buy-to-sell resolves");
   Check(MathAbs(g.execSl-g.sourceTp)<TickSize()&&MathAbs(g.execTp-g.sourceSl)<TickSize(),"ordinary inverse swaps absolute levels");
   Check(MathAbs(g.execTargetR-8.7/11.3)<0.0002,"1.3 pip spread gives executable inverse R");
   double candleLow=1.13700,candleHigh=1.13720;
   Check(MaCrossCandleArrowPrice(true,candleHigh,candleLow)<candleLow,
      "BUY marker below signal candle independent of risk");
   Check(MaCrossCandleArrowPrice(false,candleHigh,candleLow)>candleHigh,
      "SELL marker above signal candle independent of risk");

   g_rtAdvancedReverse=true;
   g_rtAdvancedReverseMaxCostPct=100.0;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true),"advanced buy-to-sell resolves");
   Check(MathAbs(g.execSl-g.sourceTp)<TickSize(),"advanced sell stop equals source buy target");
   Check(MathAbs(g.execTp-(g.sourceSl+1.3*pip))<TickSize()*0.5,
      "inverse sell target reserves entry ask gap");
   Check(MathAbs(g.execTargetR-7.4/11.3)<0.0002,"inverse sell R uses shifted TP");
   Check(ResolvePureSwapGeometry(false,true,bid,ask,bid+10*pip,g,detail,true),"advanced sell-to-buy resolves");
   Check(MathAbs(g.execSl-g.sourceTp)<TickSize(),"advanced buy stop equals source sell target");
   Check(MathAbs(g.execTp-(g.sourceSl-1.3*pip))<TickSize()*0.5,
      "inverse buy target reserves entry bid gap");
   ask=bid+0.2*pip;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true),"tight spread resolves");
   Check(MathAbs(g.execTargetR-9.6/10.2)<0.0002,"0.2 pip gap gives executable ask-proof R");
   double liveSl=0.0,liveRisk=0.0,liveTp=0.0,liveTargetR=0.0;
   Check(ResolveExecutionStop(true,false,bid,ask-10*pip,liveSl,liveRisk,detail,ask)
      &&ResolveTargetPriceAndR(false,bid,liveRisk,liveTp,liveTargetR,detail,ask)
      &&MathAbs(liveSl-g.sourceTp)<TickSize()*0.5
      &&MathAbs(liveTp-(g.sourceSl+0.2*pip))<TickSize()*0.5,
      "live inverse TP uses the same ask-proof level");
   ask=bid+1.3*pip;
   g_rtAdvancedReverse=false;g_rtTargetLeg=(int)ORB_TARGET_R350;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail),"3.5R inverse resolves");
   Check(MathAbs(g.execTargetR-8.7/36.3)<0.0002,"3.5R source inverse uses swapped distances");
   g_rtTargetLeg=(int)ORB_TARGET_R100;g_rtAdvancedReverse=true;
   g_rtAdvancedReverseMaxCostPct=10.0;
   Check(!ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true)
      &&StringFind(detail,"INVERSE_GAP_BLOCK")==0,"10 percent quote-gap gate blocks 13 percent spread");
   ask=bid+0.8*pip;
   Check(!ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true)
      &&StringFind(detail,"INVERSE_GAP_BLOCK r_floor")==0,
      "1R quote conversion below 0.90R TP is blocked even inside the gap cap");
   Check(!ResolveExecutionStop(true,false,bid,ask-10*pip,liveSl,liveRisk,detail,ask)
      &&StringFind(detail,"INVERSE_GAP_BLOCK r_floor")==0,
      "live 1R inverse cannot bypass the TP floor");
   ask=bid+0.2*pip;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true)
      &&g.execTargetR>=0.90,
      "1R inverse above the 0.90R TP floor is admitted");
   ask=bid+8.2*pip;
   Check(!ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true)
      &&StringFind(detail,"INVERSE_GAP_BLOCK")==0,
      "rollover quote gap is rejected before inverse entry");
   ask=bid+1.3*pip;
   g_rtAdvancedReverseMaxCostPct=35.0;
   Check(ResolvePureSwapGeometry(true,false,ask,bid,ask-10*pip,g,detail,true),
      "35 percent TP-erosion tolerance admits 13 percent quote gap");
   g_rtAdvancedReverseMaxCostPct=100.0;
   OrbStrategyPreset metricPreset;OrbPresetDefaults(metricPreset);metricPreset.invertMode=true;
   string fullMetric=OrbUserMetricKey("EURUSDm",(int)PERIOD_M1,"inputs","runtime",metricPreset,false,100.0);
   string advancedMetric=OrbUserMetricKey("EURUSDm",(int)PERIOD_M1,"inputs","runtime",metricPreset,true,100.0);
   string gatedMetric=OrbUserMetricKey("EURUSDm",(int)PERIOD_M1,"inputs","runtime",metricPreset,true,10.0);
   Check(fullMetric!=advancedMetric,"FULL and ADV stored metrics are isolated");
   Check(advancedMetric!=gatedMetric,"ADV max quote gap changes metric identity");

   g_maIndependent=false;g_maReverseExit=false;g_rtTimeExit=false;
   g_rtFilteredWindowReverseExit=false;g_rtPostTradeDispBlockExit=false;
   g_rtHalfBeLeg=0;g_rtBEOnTp1=false;
   g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_orbBridgeEnabled=false;g_orbNativeWithBridgeOnly=false;
   Check(AdvancedReverseShape(detail),"NAT OFF permits audit-only advanced reverse");
   g_orbBridgeEnabled=true;
   Check(!AdvancedReverseShape(detail)&&detail=="MT5_NATIVE_ONLY_PUB_OFF","PUB ON remains blocked");
   g_orbBridgeEnabled=false;

   datetime entry=D'2026.09.21 10:00';
   HistResult sim;sim.valid=true;sim.outcome="TP2";sim.exitTime=entry+3600;
   datetime actualUntil=MaLegacyAuditPositionUntil(sim,entry+7200,0,"");
   Check(actualUntil==sim.exitTime,"inverse actual exit owns legacy calendar");
   Check(entry+1800<actualUntil,"candidate before inverse exit remains blocked");
   sim.outcome="MA_REVERSE_EXIT";sim.exitTime=entry+1860;
   Check(MaLegacyAuditPositionUntil(sim,entry+7200,entry+1800,"MA_REVERSE_EXIT")==entry+1800,
      "reverse candidate may close before its own entry");
   sim.valid=false;
   Check(MaLegacyAuditPositionUntil(sim,entry+7200,0,"")==entry+7201,
      "unknown exit fails closed rather than admitting overlap");

   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int f=FileOpen("MaCrossInversePairProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,payload);FileClose(f);}
   Print(payload);
}
