void CheckOrbTargetCost()
{
   CheckTargetCostMath();
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   g_rtSignalTf=PERIOD_M5;g_rtAdvancedAuditEngine=false;g_rtInvertMode=false;
   g_rtPipSlMode=false;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btNativeParity=true;
   g_histTickCoverageKnown=true;g_histTickFirstAvailableMs=ULONG_MAX;
   g_rtTargetLeg=ORB_TARGET_CUSTOM;g_rtCustomR=0.01;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtTimeExit=false;g_btSlippagePts=0;g_btCommissionPerLot=0;g_btSpreadPts=10;
   MqlRates bars[];int n=CopyRates(_Symbol,PERIOD_M5,D'2025.10.20 08:00',D'2025.10.20 15:00',bars);
   Check(n>8,"recorded OHLC fixture ready");
   for(int i=1;i<n&&i<25;i++)for(int side=0;side<2;side++)
   {
      bool buy=side==0;double entry=bars[i].open,risk=0.5;
      datetime at=bars[i-1].time,end=bars[MathMin(n-1,i+6)].time+300;
      TpCostSet(false,20);
      HistResult a=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      HistResult b=BeforeSimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      Check(a.valid==b.valid&&a.outcome==b.outcome&&a.netR==b.netR&&a.costR==b.costR
         &&a.exitTime==b.exitTime&&a.simEntry==b.simEntry&&a.simSl==b.simSl&&a.simTarget==b.simTarget,"filter OFF pre-change full result parity");
      TpCostSet(true,0);
      a=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      Check(!a.valid&&a.invalidReason=="COST_TP_BLOCK"&&a.netR==0,"positive bar spread rejected before replay PnL");
      g_rtAdvancedAuditEngine=true;
      b=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      Check(!b.valid&&b.invalidReason==a.invalidReason,"ADV and normal reject same entry");g_rtAdvancedAuditEngine=false;
   }
   string reason="";
   TpCostSet(true,20);
   Check(OrbTargetCostAllow(1.30,1.29,1.31,true,1,0,reason),"cheap native planned geometry passes");
   Check(!OrbTargetCostAllow(1.30,1.29,1.30001,true,10,0,reason)&&reason=="COST_TP_BLOCK","expensive native target fails");
   Check(!OrbTargetCostAllow(1.30,1.29,0,false,1,0,reason)&&TpCostIsReject(reason),"no fixed target is explicit rejection");
   g_runtimeMagic=9192033000+(long)(GetTickCount64()%1000000);g_orbBridgeEnabled=false;g_rtEaEnabled=false;
   string prefix="__TARGET_COST_"+(string)GetTickCount64();
   TpCostSet(true,17.125);Check(OrbUserSave(prefix+"ON"),"save enabled strategy");
   OrbStrategyPreset on;bool haveOn=OrbStrategyPresetLoad(g_strategyPresetIndex,on);
   Check(haveOn,"read enabled preset");
   TpCostSet(false,20);Check(OrbUserSave(prefix+"OLD"),"save old-compatible OFF strategy");
   OrbStrategyPreset off;bool haveOff=OrbStrategyPresetLoad(g_strategyPresetIndex,off);
   Check(haveOff,"read OFF preset");
   if(haveOn&&haveOff)
   {
      int onSlot=OrbUserSlot(on.id),offSlot=OrbUserSlot(off.id);
      Check(g_userStrategies[onSlot].targetCostEnabled&&g_userStrategies[onSlot].targetCostMaxPct==17.125,"disk read restores exact cost settings");
      Check(!g_userStrategies[offSlot].targetCostEnabled&&g_userStrategies[offSlot].targetCostMaxPct==20,"old format defaults OFF");
      string oldKey=OrbUserWindowKey(g_userStrategies[offSlot]),newKey=OrbUserWindowKey(g_userStrategies[onSlot]);
      Check(oldKey!=newKey,"active filter has separate CURRENT results");
      TpCostSet(false,50);Check(OrbStrategyPresetApplyValues(on)&&g_tpCostEnabled&&g_tpCostMaxPct==17.125,"loading ON restores policy");
      Check(OrbStrategyPresetApplyValues(off)&&!g_tpCostEnabled&&g_tpCostMaxPct==20,"loading old OFF clears previous filter");
      FileDelete(OrbUserFile(onSlot),FILE_COMMON);FileDelete(OrbUserFile(offSlot),FILE_COMMON);
   }
   g_strategyPresetIndex=-1;g_strategyCandidateIndex=-1;TpCostSet(false,20);g_userCompletedReady=false;
   DrawDashboard();UpdateDashboard();string value=TpCostObject(PREFIX,"VALUE"),toggle=TpCostObject(PREFIX,"ON"),apply=TpCostObject(PREFIX,"APPLY");
   Check(ObjectFind(0,value)>=0&&ObjectFind(0,toggle)>=0&&ObjectFind(0,apply)>=0,"right-panel controls exist");
   long clickX=0;double clickY=0.0;
   ObjectSetString(0,value,OBJPROP_TEXT,"12.75");
   ProbeEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,toggle);
   Check(g_tpCostEnabled&&g_tpCostMaxPct==12.75,"actual dashboard toggle reads current edit");
   ObjectSetString(0,value,OBJPROP_TEXT,"7.25");ProbeEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,apply);
   Check(g_tpCostEnabled&&g_tpCostMaxPct==7.25&&g_histRedrawQueued,"Apply uses current edit and queues audit");
   ObjectSetString(0,value,OBJPROP_TEXT,"bad");ProbeEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,apply);
   Check(g_tpCostMaxPct==7.25,"invalid editor cannot change applied settings");
   if(g_tpCostKey!="")GlobalVariableDel(g_tpCostKey);
   ChartScreenShot(0,PROBE_IMAGE,1600,950,ALIGN_LEFT);
}
