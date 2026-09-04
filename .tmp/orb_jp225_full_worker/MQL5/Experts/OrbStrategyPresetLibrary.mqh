#ifndef ORB_STRATEGY_PRESET_LIBRARY_MQH
#define ORB_STRATEGY_PRESET_LIBRARY_MQH

// Screenshot-derived ORB strategy presets. Risk, publisher, channel, native,
// FTMO and account-safety controls are intentionally outside this schema.
#define ORB_PRESET_FAMILY_ANY    0
#define ORB_PRESET_FAMILY_JP225  1
#define ORB_PRESET_FAMILY_USDJPY 2
#define ORB_PRESET_FAMILY_USTEC  3

struct OrbStrategyPreset
{
   string id;
   string name;
   string searchTerms;
   string sourceImage;
   int family;
   ENUM_TIMEFRAMES signalTf;
   int delayMinutes;
   int targetLeg;
   int halfBeLeg;
   ORB_ENTRY_MODE entryMode;
   ORB_EXIT_ENGINE_MODE exitMode;
   ORB_TARGET_MODE targetMode;
   bool pipSlMode;
   double pipSlPips;
   bool atrFilter;
   bool volumeFilter;
   double volumeMultiplier;
   bool dayFilter;
   bool timeExit;
   bool displacementFilter;
   ORB_FVG_MODE fvgMode;
   bool invertMode;
   bool utc00Mode;
   bool entryWindow;
   int entryWindowStart;
   int entryWindowEnd;
   bool reverseWindowExit;
   bool postTradeDispExit;
   bool regime0;
   bool regime1;
   bool regime2;
   bool regime3;
   bool regime4;
   bool regime5;
   bool rfMaster;
   bool rf01;
   bool rf02;
   bool rf03;
   bool rf04;
   bool rf05;
   bool rf06;
   bool rf07;
   bool rf08;
   bool rf09;
   bool rf10;
   bool rf11;
   bool rf12;
   bool nasEntryGate;
   bool nasStateGate;
   bool nasOppositeExit;
   bool nasAdditionalExit;
   int nasSensitivity;
   int nasLookbackMinutes;
   int nasExitWaitMinutes;
   bool nasStateVolumeFilter;
   double nasStateVolumeMultiplier;
   bool nasFlowVolumeFilter;
   double nasFlowVolumeMultiplier;
   bool metric1yReady;
   string metric1yAsOf;
   int metric1yTotal;
   int metric1yWins;
   int metric1yLosses;
   double metric1yNetR;
   double metric1yMinCumR;
   double metric1yWr;
};

int OrbStrategyPresetCount(){return 46;}

void OrbPresetDefaults(OrbStrategyPreset &p)
{
   p.id="";p.name="";p.searchTerms="";p.sourceImage="";p.family=ORB_PRESET_FAMILY_ANY;
   p.signalTf=PERIOD_M15;p.delayMinutes=5;p.targetLeg=(int)ORB_TARGET_R050;p.halfBeLeg=0;
   p.entryMode=ORB_ENTRY_BREAKOUT;p.exitMode=ORB_EXIT_FIXED_TARGET;p.targetMode=ORB_TARGET_R_LEG;
   p.pipSlMode=true;p.pipSlPips=4000.0;
   p.atrFilter=false;p.volumeFilter=true;p.volumeMultiplier=1.0;p.dayFilter=false;p.timeExit=false;
   p.displacementFilter=true;p.fvgMode=ORB_FVG_OFF;p.invertMode=false;p.utc00Mode=false;
   p.entryWindow=false;p.entryWindowStart=0;p.entryWindowEnd=0;
   p.reverseWindowExit=false;p.postTradeDispExit=false;
   p.regime0=true;p.regime1=true;p.regime2=true;p.regime3=true;p.regime4=true;p.regime5=true;
   p.rfMaster=false;
   p.rf01=false;p.rf02=true;p.rf03=true;p.rf04=false;p.rf05=false;p.rf06=false;
   p.rf07=false;p.rf08=false;p.rf09=false;p.rf10=false;p.rf11=true;p.rf12=false;
   p.nasEntryGate=false;p.nasStateGate=false;p.nasOppositeExit=false;p.nasAdditionalExit=false;
   p.nasSensitivity=4;p.nasLookbackMinutes=120;p.nasExitWaitMinutes=0;
   p.nasStateVolumeFilter=false;p.nasStateVolumeMultiplier=1.0;
   p.nasFlowVolumeFilter=false;p.nasFlowVolumeMultiplier=1.0;
   p.metric1yReady=false;p.metric1yAsOf="";p.metric1yTotal=0;p.metric1yWins=0;p.metric1yLosses=0;
   p.metric1yNetR=0.0;p.metric1yMinCumR=0.0;p.metric1yWr=0.0;
}

void OrbPresetMetric1Y(OrbStrategyPreset &p,const string asOf,const int total,const int wins,const int losses,
                       const double netR,const double minCumR,const double wr)
{
   p.metric1yReady=true;p.metric1yAsOf=asOf;p.metric1yTotal=total;p.metric1yWins=wins;p.metric1yLosses=losses;
   p.metric1yNetR=netR;p.metric1yMinCumR=minCumR;p.metric1yWr=wr;
}

void OrbPresetIdentity(OrbStrategyPreset &p,const string id,const string name,const string searchTerms,
                       const string sourceImage,const int family,const ENUM_TIMEFRAMES tf,
                       const int targetLeg,const ORB_ENTRY_MODE entryMode,const double pipSlPips)
{
   p.id=id;p.name=name;p.searchTerms=searchTerms;p.sourceImage=sourceImage;p.family=family;
   p.signalTf=tf;p.targetLeg=targetLeg;p.entryMode=entryMode;p.pipSlPips=pipSlPips;
}

void OrbPresetLegacyNasVolume(OrbStrategyPreset &p,const bool enabled,const double multiplier)
{
   // Before the v6.67 split the single NAS-volume policy controlled both
   // causal-state admission and entry/exit event flow.
   p.nasStateVolumeFilter=enabled;p.nasStateVolumeMultiplier=multiplier;
   p.nasFlowVolumeFilter=enabled;p.nasFlowVolumeMultiplier=multiplier;
}

void OrbPresetRfOnly03(OrbStrategyPreset &p)
{
   p.rf01=false;p.rf02=false;p.rf03=true;p.rf04=false;p.rf05=false;p.rf06=false;
   p.rf07=false;p.rf08=false;p.rf09=false;p.rf10=false;p.rf11=false;p.rf12=false;
}

bool OrbStrategyPresetLoad(const int index,OrbStrategyPreset &p)
{
   OrbPresetDefaults(p);
   switch(index)
   {
      case 0:
         OrbPresetIdentity(p,"jp_05_adv","0.5RsetupAdvanced","0.5RsetupAdvanced jp225 advanced imb1m",
            "0.5Gang/0.5RsetupAdvanced.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_IMBALANCE_M1,4000.0);
         p.volumeFilter=false;p.volumeMultiplier=2.0;p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;p.regime2=false;
         break;
      case 1:
         OrbPresetIdentity(p,"jp_2r_retest","2RModeljp225","2RModeljp225 jp225 retest rf",
            "0.5Gang/2RModeljp225.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R200,ORB_ENTRY_PULLBACK_RETEST,1800.0);
         p.volumeMultiplier=1.40;p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;p.regime5=false;p.rfMaster=true;OrbPresetRfOnly03(p);
         break;
      case 2:
         OrbPresetIdentity(p,"jp_05_v2","jp2250.5RSetupV2","jp2250.5RSetupV2 jp225 break",
            "0.5Gang/jp2250.5RSetupV2.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,4000.0);
         break;
      case 3:
         OrbPresetIdentity(p,"jp_05_inv_retest","jp2250.5RUltimateSetup","jp2250.5RUltimateSetup jp225 swap invert retest",
            "0.5Gang/jp2250.5RUltimateSetup.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_PULLBACK_RETEST,5000.0);
         p.volumeMultiplier=0.70;p.fvgMode=ORB_FVG_OFF;p.invertMode=true;
         break;
      case 4:
         OrbPresetIdentity(p,"jp_05_long_wait","jp225HighProbaLongWait","jp225HighProbaLongWait jp225 high probability",
            "0.5Gang/jp225HighProbaLongWait.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,4000.0);
         p.volumeMultiplier=3.0;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 5:
         OrbPresetIdentity(p,"jp_05_holy","jp225HolyGrail","jp225HolyGrail jp225 holy grail Use/jp225HolyGrail",
            "0.5Gang/jp225HolyGrail.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_PULLBACK_RETEST,4000.0);
         p.volumeMultiplier=3.0;p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 6:
         OrbPresetIdentity(p,"jp_1r_nofilter","JP225nOFilter1R","JP225nOFilter1R jp225 no filter 1R Use/JP225nOFilter1R",
            "0.5Gang/JP225nOFilter1R.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R100,ORB_ENTRY_IMBALANCE_M1,4000.0);
         p.volumeFilter=false;p.volumeMultiplier=1.70;p.displacementFilter=false;p.fvgMode=ORB_FVG_OFF;
         p.entryWindow=true;p.entryWindowStart=0;p.entryWindowEnd=360;
         p.regime2=false;p.regime3=false;p.regime5=false;p.rfMaster=true;
         break;
      case 7:
         OrbPresetIdentity(p,"jp_025_none","0.25RFiltersNone","0.25RFiltersNone jp225 filters none GateStateOn Muhtesem4lu",
            "0.5Gang/Use/0.25RFiltersNone.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,12000.0);
         p.fvgMode=ORB_FVG_OFF;p.nasExitWaitMinutes=480;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.50;
         break;
      case 8:
         OrbPresetIdentity(p,"jp_05_imb4500","jp2250.5Model","jp2250.5Model jp225 imb1m 4500",
            "0.5Gang/Use/jp2250.5Model.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_IMBALANCE_M1,4500.0);
         p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 9:
         OrbPresetIdentity(p,"jp_075_hf","jp2250.5RHighFrequencyIfYouDontWannaWait","jp225 high frequency 0.75R dont wait",
            "0.5Gang/Use/jp2250.5RHighFrequencyIfYouDontWannaWait.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R075,ORB_ENTRY_BREAKOUT,3000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.regime2=false;
         break;
      case 10:
         OrbPresetIdentity(p,"jp_025_nas_opp","jp225Nas0.25RNewMode","jp225Nas0.25RNewMode jp225 nas opposite exit",
            "0.5Gang/Use/jp225Nas0.25RNewMode.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,12000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasOppositeExit=true;p.nasExitWaitMinutes=240;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 11:
         OrbPresetIdentity(p,"jp_025_8000","jp225Use8000pips","jp225Use8000pips jp225 8000 GateStateOn/jp225Use8000pips",
            "0.5Gang/Use/jp225Use8000pips.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,8000.0);
         p.fvgMode=ORB_FVG_OFF;p.nasExitWaitMinutes=600;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.50;
         break;
      case 12:
         OrbPresetIdentity(p,"jp_015_state_add","jp225VeryHighWRWithGateState","jp225VeryHighWRWithGateState jp225 state gate add exit",
            "0.5Gang/Use/jp225VeryHighWRWithGateState.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R015,ORB_ENTRY_BREAKOUT,12000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasStateGate=true;p.nasAdditionalExit=true;p.nasExitWaitMinutes=480;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.0;
         break;
      case 13:
         OrbPresetIdentity(p,"jp_020_nas_opp","jp225WithNas","jp225WithNas jp225 nas 0.20R",
            "0.5Gang/Use/jp225WithNas.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,13000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasOppositeExit=true;p.nasExitWaitMinutes=240;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 14:
         OrbPresetIdentity(p,"jp_015_nas_opp","veryHighWRjp225OrbNasNewMode","veryHighWRjp225OrbNasNewMode jp225 high wr nas",
            "0.5Gang/Use/veryHighWRjp225OrbNasNewMode.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R015,ORB_ENTRY_BREAKOUT,12000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasOppositeExit=true;p.nasExitWaitMinutes=240;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 15:
         OrbPresetIdentity(p,"uj_05_good","0.5RGoodUsdjpy","0.5RGoodUsdjpy usdjpy 25 pip",
            "0.5Gang/Use/usdjpy/0.5RGoodUsdjpy.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,25.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasOppositeExit=true;p.nasExitWaitMinutes=600;OrbPresetLegacyNasVolume(p,true,1.0);
         break;
      case 16:
         OrbPresetIdentity(p,"uj_020_40_master","40pipusdjpyMasterSystem","40pipusdjpyMasterSystem usdjpy master 40 pip GateStateOn",
            "0.5Gang/Use/usdjpy/40pipusdjpyMasterSystem.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,40.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasExitWaitMinutes=180;OrbPresetLegacyNasVolume(p,true,1.0);
         break;
      case 17:
         OrbPresetIdentity(p,"uj_020_good_practice","goodPractice","goodPractice usdjpy 60 pip optional fvg",
            "0.5Gang/Use/usdjpy/goodPractice.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,60.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OPTIONAL;p.nasOppositeExit=true;p.nasExitWaitMinutes=240;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 18:
         OrbPresetIdentity(p,"uj_020_inv_holy","HolyGrail [USDJPY]","HolyGrail usdjpy inverted 5R 13 pip",
            "0.5Gang/Use/usdjpy/HolyGrail.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,13.0);
         p.volumeFilter=false;p.displacementFilter=false;p.fvgMode=ORB_FVG_OFF;p.invertMode=true;p.utc00Mode=false;
         break;
      case 19:
         OrbPresetIdentity(p,"uj_05_gm0","usdjpyOrbGM0Edge","usdjpyOrbGM0Edge usdjpy gm0 no filter 25 pip",
            "0.5Gang/Use/usdjpy/usdjpyOrbGM0Edge.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,25.0);
         p.volumeFilter=false;p.displacementFilter=false;p.fvgMode=ORB_FVG_OFF;p.utc00Mode=true;
         break;
      case 20:
         OrbPresetIdentity(p,"uj_020_40_opp","0.20R [USDJPY]","0.20R usdjpy 40 pip opposite exit",
            "0.5Gang/Use/usdjpy/Use/0.20R.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,40.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasOppositeExit=true;p.nasExitWaitMinutes=600;OrbPresetLegacyNasVolume(p,true,1.0);
         break;
      case 21:
         OrbPresetIdentity(p,"uj_025_60_opp30","0.25RUsdJpy","0.25RUsdJpy usdjpy 60 pip opposite 0030",
            "0.5Gang/Use/usdjpy/Use/0.25RUsdJpy.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,60.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasOppositeExit=true;p.nasExitWaitMinutes=30;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 22:
         OrbPresetIdentity(p,"uj_010_state","0.10R_Setup","0.10R_Setup usdjpy state gate 80 pip",
            "0.5Gang/Use/usdjpy/Use/GateStateOn/0.10R_Setup.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R010,ORB_ENTRY_BREAKOUT,80.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;OrbPresetLegacyNasVolume(p,true,3.0);
         break;
      case 23:
         OrbPresetIdentity(p,"uj_025_star","0.25RYildiz","0.25RYildiz usdjpy state gate add exit 60 pip",
            "0.5Gang/Use/usdjpy/Use/GateStateOn/0.25RYildiz.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,60.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;p.nasAdditionalExit=true;p.nasExitWaitMinutes=480;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=3.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.0;
         break;
      case 24:
         OrbPresetIdentity(p,"uj_1r_alt","1RAlternatif","1RAlternatif usdjpy 12 pip no nas",
            "0.5Gang/Use/usdjpy/Use/GateStateOn/1RAlternatif.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,12.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasExitWaitMinutes=360;
         p.nasStateVolumeFilter=false;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=false;p.nasFlowVolumeMultiplier=1.50;
         break;
      case 25:
         OrbPresetIdentity(p,"uj_1r_star","1RYildiz","1Ryildiz usdjpy 15 pip state gate",
            "0.5Gang/Use/usdjpy/Use/GateStateOn/1Ryildiz.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,15.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;OrbPresetLegacyNasVolume(p,true,3.0);
         break;
      case 26:
         OrbPresetIdentity(p,"uj_025_state80","usdjpyGateStateOn","usdjpyGateStateOn usdjpy 80 pip state gate",
            "0.5Gang/Use/usdjpy/Use/GateStateOn/usdjpyGateStateOn.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,80.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;p.nasExitWaitMinutes=480;OrbPresetLegacyNasVolume(p,true,3.0);
         break;
      case 27:
         OrbPresetIdentity(p,"uj_040_pro","ProUsdJpySetup","ProUsdJpySetup usdjpy 0.40R 25 pip optional fvg",
            "0.5Gang/Use/usdjpy/Use/ProUsdJpySetup.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R040,ORB_ENTRY_BREAKOUT,25.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OPTIONAL;p.nasOppositeExit=true;p.nasExitWaitMinutes=30;OrbPresetLegacyNasVolume(p,false,1.0);
         break;
      case 28:
         OrbPresetIdentity(p,"uj_025_use","UsdJpyUse","UsdJpyUse usdjpy 0.25R 60 pip opposite exit",
            "0.5Gang/Use/usdjpy/Use/UsdJpyUse.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,60.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasOppositeExit=true;p.nasExitWaitMinutes=360;OrbPresetLegacyNasVolume(p,true,1.0);
         break;
      case 29:
         OrbPresetIdentity(p,"uj_020_try","usdjpyWorthTrying","usdjpyWorthTrying usdjpy 0.20R 70 pip opposite exit",
            "0.5Gang/Use/usdjpy/Use/usdjpyWorthTrying.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,70.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasOppositeExit=true;p.nasExitWaitMinutes=600;OrbPresetLegacyNasVolume(p,true,1.0);
         break;
      case 30:
         OrbPresetIdentity(p,"jp_1r_challenge","4Kaybetmeden4KazanmaChallengeModeli","4Kaybetmeden4KazanmaChallengeModeli jp225 1R challenge",
            "4Kaybetmeden4KazanmaChallengeModeli.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,4000.0);
         p.atrFilter=true;p.volumeFilter=false;p.volumeMultiplier=1.40;p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;
         p.regime5=false;p.rfMaster=true;OrbPresetRfOnly03(p);
         break;
      case 31:
         OrbPresetIdentity(p,"jp_1r_disp","DISP1RModelIsSolid","DISP1RModelIsSolid jp225 1R displacement",
            "DISP1RModelIsSolid.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,4000.0);
         p.atrFilter=true;p.volumeMultiplier=0.80;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 32:
         OrbPresetIdentity(p,"ustec_05_inv","DISPONUsefullFirstTimeUstecOrb0.5R","USTEC US100 DISP 0.5R invert retest",
            "DISPONUsefullFirstTimeUstecOrb0.5R.png",ORB_PRESET_FAMILY_USTEC,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_PULLBACK_RETEST,10000.0);
         p.volumeMultiplier=0.70;p.fvgMode=ORB_FVG_OFF;p.invertMode=true;p.regime2=false;p.regime3=false;p.rfMaster=true;
         p.rf01=false;p.rf02=false;p.rf03=true;p.rf04=false;p.rf05=false;p.rf06=true;
         p.rf07=false;p.rf08=false;p.rf09=false;p.rf10=false;p.rf11=true;p.rf12=false;
         break;
      case 33:
         OrbPresetIdentity(p,"jp_1r_m5","FirstTF5ChartJP225","FirstTF5ChartJP225 jp225 M5 1R",
            "FirstTF5ChartJP225.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,4000.0);
         p.volumeMultiplier=0.80;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 34:
         OrbPresetIdentity(p,"jp_1r_m15","JP2251RSetup","JP2251RSetup jp225 M15 1R",
            "JP2251RSetup.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,4000.0);
         p.volumeMultiplier=0.80;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 35:
         OrbPresetIdentity(p,"jp_05_imb_disp","JP225DISP_ON_IBM1_SETUP_Edge","JP225 DISP ON IMB1M setup edge",
            "JP225DISP_ON_IBM1_SETUP_Edge.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_IMBALANCE_M1,4000.0);
         p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 36:
         OrbPresetIdentity(p,"jp_15_imb","LiqNarrative1.5RModel","LiqNarrative1.5RModel ORB jp225 IMB1M",
            "LiqNarrative1.5RModel.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R150,ORB_ENTRY_IMBALANCE_M1,4000.0);
         p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 37:
         OrbPresetIdentity(p,"jp_15_retest","LiqNarrativeFvgONRetestVolOn1.5RSetup","LiqNarrative FVG retest volume 1.5R ORB jp225",
            "LiqNarrativeFvgONRetestVolOn1.5RSetup.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R150,ORB_ENTRY_PULLBACK_RETEST,4000.0);
         p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 38:
         OrbPresetIdentity(p,"jp_m4_1","Muhtesem4lu #1","Muhtesem4lu 1 jp225 0.15R state add",
            "Muhtesem4lu/1.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R015,ORB_ENTRY_BREAKOUT,12000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasStateGate=true;p.nasAdditionalExit=true;p.nasExitWaitMinutes=480;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.50;
         break;
      case 39:
         OrbPresetIdentity(p,"uj_m4_2","Muhtesem4lu #2","Muhtesem4lu 2 usdjpy 1R state gate 15 pip",
            "Muhtesem4lu/2.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,15.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;OrbPresetLegacyNasVolume(p,true,3.0);
         break;
      case 40:
         OrbPresetIdentity(p,"uj_m4_3","Muhtesem4lu #3","Muhtesem4lu 3 usdjpy 0.25R state add 60 pip",
            "Muhtesem4lu/3.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M15,(int)ORB_TARGET_R025,ORB_ENTRY_BREAKOUT,60.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;p.nasAdditionalExit=true;p.nasExitWaitMinutes=480;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=3.0;p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.0;
         break;
      case 41:
         OrbPresetIdentity(p,"uj_m4_4","Muhtesem4lu #4","Muhtesem4lu 4 usdjpy 1R 12 pip no nas",
            "Muhtesem4lu/4.png",ORB_PRESET_FAMILY_USDJPY,PERIOD_M5,(int)ORB_TARGET_R100,ORB_ENTRY_BREAKOUT,12.0);
         p.utc00Mode=true;p.fvgMode=ORB_FVG_OFF;p.nasExitWaitMinutes=360;
         p.nasStateVolumeFilter=false;p.nasStateVolumeMultiplier=2.0;p.nasFlowVolumeFilter=false;p.nasFlowVolumeMultiplier=1.50;
         break;
      case 42:
         OrbPresetIdentity(p,"jp_best_so_far","NikkeiOrbBestSoFar","NikkeiOrbBestSoFar jp225 best 0.5R retest",
            "NikkeiOrbBestSoFar.png",ORB_PRESET_FAMILY_JP225,PERIOD_M15,(int)ORB_TARGET_R050,ORB_ENTRY_PULLBACK_RETEST,4000.0);
         p.displacementFilter=false;p.fvgMode=ORB_FVG_REQUIRE;
         break;
      case 43:
         OrbPresetIdentity(p,"jp_020_star","0.20RStarJp225","0.20RStarJp225 jp225 0.20R state gate 8000",
            "Muhtesem4lu/0.20RStarJp225.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R020,ORB_ENTRY_BREAKOUT,8000.0);
         p.fvgMode=ORB_FVG_REQUIRE;p.nasStateGate=true;p.nasExitWaitMinutes=420;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=1.50;
         p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.0;
         break;
      case 44:
         OrbPresetIdentity(p,"jp_05_gate_6000","0.5RSetupJp225GateOn","0.5RSetupJp225GateOn jp225 0.5R state gate 6000",
            "Muhtesem4lu/0.5RSetupJp225GateOn.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,6000.0);
         p.fvgMode=ORB_FVG_OFF;p.nasStateGate=true;p.nasExitWaitMinutes=600;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=1.50;
         p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.0;
         break;
      case 45:
         OrbPresetIdentity(p,"jp_05_star_6000","jp225O.5RStar","jp225O.5RStar jp225 0.5R star 6000 no gate",
            "Muhtesem4lu/jp225O.5RStar.png",ORB_PRESET_FAMILY_JP225,PERIOD_M5,(int)ORB_TARGET_R050,ORB_ENTRY_BREAKOUT,6000.0);
         p.fvgMode=ORB_FVG_OFF;
         p.nasStateVolumeFilter=true;p.nasStateVolumeMultiplier=2.0;
         p.nasFlowVolumeFilter=true;p.nasFlowVolumeMultiplier=1.50;
         break;
      default:return false;
   }
   return true;
}

bool OrbPresetRegimeAllowed(const OrbStrategyPreset &p,const int index)
{
   if(index==0)return p.regime0;if(index==1)return p.regime1;if(index==2)return p.regime2;
   if(index==3)return p.regime3;if(index==4)return p.regime4;if(index==5)return p.regime5;
   return true;
}

bool OrbPresetRfBlocked(const OrbStrategyPreset &p,const int index)
{
   if(index==0)return p.rf01;if(index==1)return p.rf02;if(index==2)return p.rf03;if(index==3)return p.rf04;
   if(index==4)return p.rf05;if(index==5)return p.rf06;if(index==6)return p.rf07;if(index==7)return p.rf08;
   if(index==8)return p.rf09;if(index==9)return p.rf10;if(index==10)return p.rf11;if(index==11)return p.rf12;
   return false;
}

#endif
