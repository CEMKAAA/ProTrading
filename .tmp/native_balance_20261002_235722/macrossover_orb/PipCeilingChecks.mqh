void PcChecks()
{
   long clickX=0;double clickY=0;
   double samples[]={1000001.0,2500000.5,10000000000000.0};
   for(int i=0;i<ArraySize(samples);i++)
      NbCheck(ClampPipSlPips(samples[i])==samples[i],"pip clamp preserves value above former ceiling");
   double parsed=0;
   NbCheck(!NativeBalanceParse("10000000000000",parsed),"balance parser retains safety ceiling");
   NbCheck(NativeBalanceParse("10000000000000",parsed,DBL_MAX)&&parsed==samples[2],"pip parser has no balance ceiling");
   NbCheck(!NativeBalanceParse("invalid",parsed,DBL_MAX),"invalid pip text rejected");
#ifdef NM_SOL
   string pipApply=PFX+"BTN_PIPSL_APPLY";
   NbCheck(ClampPipSlPips(-1)==0,"Sol pip minimum unchanged");
   double before[];LiqLibraryCapture(before);
   LnNasPolicy oldNas=g_lnNas;LnNasDefaults(g_lnNas);
   g_pipSlMode=true;
   for(int i=0;i<ArraySize(samples);i++)
   {
      ObjectSetString(0,PFX+"EDIT_PIPSL_PIPS",OBJPROP_TEXT,DoubleToString(samples[i],1));
      BalanceChartEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,pipApply);
      NbCheck(g_pipSlPips==samples[i],"Sol actual pip Apply preserves high value");
   }
   string name="__pip_ceiling_probe_"+(string)GetTickCount64(),path=LiqLibraryPath(name);
   bool fresh=!FileIsExist(path,FILE_COMMON);
   bool saved=fresh&&LiqLibrarySave(name);
   NbCheck(saved,"Sol high pip strategy saved");
   string restoredName="";double restored[];
   bool loaded=saved&&LiqLibraryUnpack(path,restoredName,restored);
   NbCheck(loaded&&restoredName==name&&restored[20]==samples[2],"Sol high pip strategy file roundtrip");
   if(loaded){g_pipSlPips=10;LiqLibraryAssign(restored);NbCheck(g_pipSlPips==samples[2],"Sol high pip strategy assigned");}
   if(saved)NbCheck(FileDelete(path,FILE_COMMON),"Sol probe strategy removed");
   LiqLibraryAssign(before);g_lnNas=oldNas;DrawDashboard();
#else
   string pipApply=PREFIX+"BTN_SL_APPLY";
   NbCheck(ClampPipSlPips(-1)==0.1,"Orb-family pip minimum unchanged");
   bool oldMode=g_rtPipSlMode;double oldPips=g_rtPipSlPips;
   g_rtPipSlMode=true;
   for(int i=0;i<ArraySize(samples);i++)
   {
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,DoubleToString(samples[i],1));
      BalanceChartEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,pipApply);
      NbCheck(g_rtPipSlPips==samples[i],"actual pip Apply preserves high value");
      OrbStrategyPreset preset,restored;OrbCustomCapturePreset(preset);
      string lines[];StringSplit(OrbCustomPresetDump(preset),'\n',lines);
      bool read=OrbCustomPresetRead(lines,0,restored);
      NbCheck(read&&MathAbs(restored.pipSlPips-samples[i])<=samples[i]*1e-15,
         "high pip user preset serialization roundtrip "+StringFormat("expected=%.17g restored=%.17g read=%d",samples[i],restored.pipSlPips,(int)read));
      string reason="";OrbBuiltinStrategyPresetLoad(0,preset);preset.pipSlMode=true;preset.pipSlPips=samples[i];
      NbCheck(OrbStrategyPresetValuesValid(preset,reason),"high pip strategy validation accepts value");
   }
#ifdef NM_LAB
   LabEngine oldEngine=g_labEngine;bool oldPreview=g_labPreviewOnly;
   MA_CROSS_SIGNAL_MODE oldSignalMode=g_rtMaCrossMode;
   LabScalperPreset(0,g_labEngine);g_labPreviewOnly=true;g_rtMaCrossMode=MA_CROSS_LAB_RULES;
   for(int i=0;i<ArraySize(samples);i++)
   {
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,DoubleToString(samples[i],1));
      BalanceChartEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,pipApply);
      NbCheck(g_labEngine.pipSlPips==samples[i]&&g_rtPipSlPips==samples[i],"custom engine pip Apply has no ceiling");
      LabEngine restored;
      NbCheck(LabValidEngine(g_labEngine)&&LabEngineRead(LabEngineText(g_labEngine),restored)
         &&restored.pipSlPips==samples[i],"custom engine high pip serialization roundtrip");
   }
   NbCheck(!LabPolicySetPip(true,0.01),"custom engine pip minimum unchanged");
   g_labEngine=oldEngine;g_labPreviewOnly=oldPreview;g_rtMaCrossMode=oldSignalMode;
#endif
   g_rtPipSlMode=oldMode;g_rtPipSlPips=oldPips;UpdateDashboard();
#endif
}
