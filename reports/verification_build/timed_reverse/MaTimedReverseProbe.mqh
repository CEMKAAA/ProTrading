int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("TIMED REVERSE FAIL: ",label);}}
void OnStart()
{
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   g_rtSignalTf=PERIOD_M5;g_rtAdvancedAuditEngine=false;g_rtInvertMode=false;
   g_rtPipSlMode=false;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btNativeParity=true;
   g_histTickCoverageKnown=true;g_histTickFirstAvailableMs=ULONG_MAX;
   g_rtTargetLeg=ORB_TARGET_CUSTOM;g_rtTargetMode=ORB_TARGET_R_LEG;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtTimeExit=false;g_maReverseExit=true;g_maReverseWait=2880;
   MqlRates friday[],reopening[];
   datetime signal=D'2025.10.24 08:00',deadline=signal+300+2880*60,through=D'2025.10.27 08:00';
   int fc=CopyRates(_Symbol,PERIOD_M5,signal,signal+300,friday);
   int nc=CopyRates(_Symbol,PERIOD_M1,deadline,through,reopening);
   Check(fc>=2&&nc>0,"recorded weekend bars available");
   if(fc>=2&&nc>0)
   {
      g_rtCustomR=100;double entry=friday[1].open,risk=0.5;
      for(int side=0;side<2;side++)
      {
         bool buy=side==0;
         HistResult result=SimulateTrade(signal,through,entry,entry+(buy?-risk:risk),buy,0,0,0,0,true,deadline,"MA_REVERSE_EXIT");
         Check(result.valid&&result.outcome=="MA_REVERSE_EXIT","weekend timed reverse resolves");
         Check(result.exitTime==reopening[0].time&&result.exitTime>deadline,"exit at real reopening, not closed-market deadline");
         Check(MaLegacyAuditPositionUntil(result,through,deadline,"MA_REVERSE_EXIT")==result.exitTime,
            "legacy slot stays reserved until actual exit");
         g_maMaxConsecutive=1;MaHistoricalCapacityReset();MaHistoricalCapacityOccupy(result.exitTime);
         Check(!MaHistoricalCapacityAllows(deadline),"Independent slot is not released in closed market");
         Check(MaHistoricalCapacityAllows(result.exitTime),"Independent slot releases at actual modeled exit");
         Print("WEEKEND side=",side," valid=",result.valid," exit=",TimeToString(result.exitTime,TIME_DATE|TIME_SECONDS)," R=",result.netR," reason=",result.invalidReason);
#ifdef PROBE_PARITY
         Check(result.modeledReverseExit,"modeled pricing explicitly tagged");
         double px=NormalizeTradePrice(reopening[0].open+(buy?0:MathMax(0,(double)reopening[0].spread)*_Point));
         Check(result.exitPrice==px,"reopening quote uses recorded M1 spread only for SELL");
         Check(MathAbs(result.netR-(SimSignedR(buy,entry,px,risk)-BtCostRForSpread(risk,buy?(double)friday[1].spread:0)))<1e-9,
            "modeled SELL spread charged once");
         g_rtAdvancedAuditEngine=true;datetime used=0;
         HistResult advanced=SimulateHistoricalLifecycleAdvanced(signal,through,through,entry,entry+(buy?-risk:risk),buy,0,0,0,0,used,deadline,"MA_REVERSE_EXIT");
         Check(advanced.valid&&advanced.exitTime==result.exitTime&&advanced.netR==result.netR&&advanced.modeledReverseExit,"ADV and normal fallback match");
         g_rtAdvancedAuditEngine=false;
#endif
      }
   }
   MqlRates bars[];int n=CopyRates(_Symbol,PERIOD_M5,D'2025.10.20 08:00',D'2025.10.20 15:00',bars);
   Check(n>5,"recorded parity bars available");
   int early=0;
   for(int i=1;i<n&&i<34;i++)for(int side=0;side<2;side++)
   {
      bool buy=side==0;double entry=bars[i].open,risk=4*(bars[i].high-bars[i].low);
      if(risk<=10*_Point)continue;
      g_rtCustomR=0.5;
      datetime at=bars[i-1].time,end=bars[MathMin(n-1,i+6)].time+300;
      g_maReverseExit=false;
      HistResult plain=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
#ifdef PROBE_PARITY
      HistResult before=BeforeSimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      Check(plain.valid==before.valid&&plain.outcome==before.outcome&&plain.netR==before.netR
         &&plain.costR==before.costR&&plain.exitTime==before.exitTime&&plain.simEntry==before.simEntry
         &&plain.simSl==before.simSl&&plain.simTarget==before.simTarget,"reverse OFF full result parity");
      g_maReverseExit=true;g_maReverseWait=0;
      plain=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0,true,at+600,"MA_REVERSE_EXIT");
      before=BeforeSimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0,true,at+600,"MA_REVERSE_EXIT");
      Check(plain.valid==before.valid&&plain.outcome==before.outcome&&plain.netR==before.netR
         &&plain.exitTime==before.exitTime,"legacy zero-wait result parity");
#endif
      g_maReverseExit=true;g_maReverseWait=2880;
      HistResult distant=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0,true,end+2880*60,"MA_REVERSE_EXIT");
      g_maReverseExit=false;
      plain=SimulateTrade(at,end,entry,entry+(buy?-risk:risk),buy,0,0,0,0);
      if(plain.valid&&plain.outcome!="open")
      {early++;Check(distant.valid&&distant.outcome==plain.outcome&&distant.netR==plain.netR&&distant.exitTime==plain.exitTime,"natural TP/SL before 48H preserved");}
   }
   Check(early>0,"earlier natural closures exercised");
#ifdef PROBE_PARITY
   if(fc>=2)
   {
      g_maReverseExit=true;g_maReverseWait=2880;g_rtCustomR=100;
      HistResult sub=SimulateTrade(signal,through,friday[1].open,friday[1].open-0.5,true,0,0,0,0,true,signal+330,"MA_REVERSE_EXIT");
      Check(!sub.valid&&sub.invalidReason=="REVERSE_TICKS_REQUIRED","subminute deadline stays DATA");
      g_rtInvertMode=true;
      sub=SimulateTrade(signal,through,friday[1].open,friday[1].open-0.5,true,0,0,0,0,true,deadline,"MA_REVERSE_EXIT");
      Check(!sub.valid&&sub.invalidReason=="INVERSE_TICKS_REQUIRED","inversion keeps tick requirement");
   }
#endif
   int f=FileOpen(PROBE_FILE,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
