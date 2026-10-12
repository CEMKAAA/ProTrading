#ifndef STRATEGY_SELECTION_FILTER_CHECKS_MQH
#define STRATEGY_SELECTION_FILTER_CHECKS_MQH
int selectionChecks=0,selectionFailed=0;
void SelectionCheck(bool ok,string label)
{
   selectionChecks++;
   if(!ok){selectionFailed++;Print("SELECTION FAIL: ",label);}
}
#ifdef SELECTION_SOL
bool SelectionSaveSol(string name,ERL_RR_MODE target,bool independent,double custom=1.0)
{
   g_target=target;g_targetModel=ERL_TARGET_FIXED_R;g_customTargetR=custom;
   LnNasDefaults(g_lnNas);g_lnNas.independent=independent;
   return LiqLibrarySave(name);
}
void SelectionSolChecks()
{
   for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215;
   bool enabled=false;double value=0.0;
   SelectionCheck(LiqLibraryParseFilterR(" 0,5 ",enabled,value)&&enabled&&value==0.5,"comma decimal");
   SelectionCheck(LiqLibraryParseFilterR("",enabled,value)&&!enabled,"blank disables R");
   SelectionCheck(!LiqLibraryParseFilterR("0",enabled,value),"zero invalid");
   SelectionCheck(!LiqLibraryParseFilterR("-1",enabled,value),"negative invalid");
   SelectionCheck(!LiqLibraryParseFilterR("1.2.3",enabled,value),"malformed invalid");
   SelectionCheck(!LiqLibraryParseFilterR("abc",enabled,value),"text invalid");
   string stem="__SELECTION_TEST_"+(string)GetTickCount64();
   string names[]={stem+"_LEG",stem+"_IND",stem+"_CUSTOM"};
   SelectionCheck(SelectionSaveSol(names[0],ERL_RR_TP1,false),"save legacy fixture");
   SelectionCheck(SelectionSaveSol(names[1],ERL_RR_TP1,true),"save independent fixture");
   SelectionCheck(SelectionSaveSol(names[2],ERL_RR_CUSTOM,true,0.00000001),"save custom R fixture");
   string paths[];ArrayResize(paths,3);
   for(int i=0;i<3;i++)paths[i]=LiqLibraryPath(names[i]);
   g_customTargetR=77.0;g_target=ERL_RR_TP6;g_lnNas.independent=true;
   for(int i=0;i<3;i++)
   {
      string name="";double v[];bool unpacked=LiqLibraryUnpack(paths[i],name,v,false);
      SelectionCheck(unpacked,"unpack fixture");if(!unpacked)continue;
      double ratio=0.0;SelectionCheck(LiqLibrarySavedR(paths[i],v,ratio)&&MathAbs(ratio-(i==2?0.00000001:0.5))<1e-15,"saved R does not inherit runtime");
      g_liqLibraryFilterREnabled=false;g_liqLibraryFilterMode=0;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v),"default filters pass");
      g_liqLibraryFilterMode=1;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v)==(i==0),"legacy only");
      g_liqLibraryFilterMode=2;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v)==(i!=0),"independent only");
      g_liqLibraryFilterREnabled=true;g_liqLibraryFilterR=0.5;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v)==(i==1),"R and mode combined");
      g_liqLibraryFilterMode=0;g_liqLibraryFilterR=0.00000001;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v)==(i==2),"custom tiny R");
      g_liqLibraryFilterR=0.00000002;
      SelectionCheck(!LiqLibraryPassesFilters(paths[i],v),"distinct tiny ratios");
      g_liqLibraryFilterR=0.5;v[16]=1;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v)==(i!=2),"inversion does not reciprocate R");
      v[8]=(double)ERL_TARGET_NEXT_EXTERNAL;
      SelectionCheck(!LiqLibraryPassesFilters(paths[i],v),"dynamic target excluded by exact R");
      g_liqLibraryFilterREnabled=false;
      SelectionCheck(LiqLibraryPassesFilters(paths[i],v),"dynamic target retained without R filter");
   }
   g_liqLibraryQuery=stem;g_liqLibraryFilterMode=0;g_liqLibraryFilterREnabled=false;
   LiqLibraryScan();SelectionCheck(ArraySize(g_liqLibraryFiles)==3,"scan all fixtures");
   g_liqLibraryFilterMode=2;LiqLibraryScan();SelectionCheck(ArraySize(g_liqLibraryFiles)==2,"scan independent fixtures");
   g_liqLibraryFilterR=0.5;g_liqLibraryFilterREnabled=true;LiqLibraryScan();SelectionCheck(ArraySize(g_liqLibraryFiles)==1,"scan combines filters");
   g_liqLibraryPanel=true;g_liqLibraryOpen=true;g_liqLibraryOpenedAt=0;LiqLibraryDraw();
   SelectionCheck(ObjectFind(0,LiqLibraryObject("FILTER_MODE"))>=0,"mode button rendered");
   SelectionCheck(ObjectFind(0,LiqLibraryObject("FILTER_R"))>=0,"R edit rendered");
   string a=LiqLibraryObject("FILTER_R"),b=LiqLibraryObject("FILTER_MODE"),c=LiqLibraryObject("POP_BG");
   SelectionCheck(ObjectGetInteger(0,a,OBJPROP_YDISTANCE)+ObjectGetInteger(0,a,OBJPROP_YSIZE)<=ObjectGetInteger(0,b,OBJPROP_YDISTANCE),"R and mode rows separated");
   SelectionCheck(ObjectGetInteger(0,b,OBJPROP_YDISTANCE)+ObjectGetInteger(0,b,OBJPROP_YSIZE)<=ObjectGetInteger(0,c,OBJPROP_YDISTANCE),"mode and results separated");
   ObjectSetString(0,a,OBJPROP_TEXT,"0.00000001");
   b=LiqLibraryObject("FILTER_APPLY");
   long x=ObjectGetInteger(0,b,OBJPROP_XDISTANCE)+2;double y=(double)ObjectGetInteger(0,b,OBJPROP_YDISTANCE)+2;
   SelectionCheck(LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y),"apply event handled");
   SelectionCheck(g_liqLibraryFilterREnabled&&g_liqLibraryFilterR==0.00000001&&ArraySize(g_liqLibraryFiles)==1,"apply current edit and rescan");
   b=LiqLibraryObject("FILTER_CLEAR");x=ObjectGetInteger(0,b,OBJPROP_XDISTANCE)+2;y=(double)ObjectGetInteger(0,b,OBJPROP_YDISTANCE)+2;
   SelectionCheck(LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y),"clear event handled");
   SelectionCheck(!g_liqLibraryFilterREnabled&&g_liqLibraryFilterMode==0&&ArraySize(g_liqLibraryFiles)==3,"clear restores all matches");
   SelectionCheck(g_customTargetR==77.0&&g_target==ERL_RR_TP6&&g_lnNas.independent,"filter never changes execution settings");
   ChartRedraw();ChartScreenShot(0,"StrategySelectionSol.png",1600,1000,ALIGN_LEFT);
   for(int i=0;i<3;i++)
   {FileDelete(paths[i],FILE_COMMON);FileDelete(paths[i]+".lock",FILE_COMMON);}
   DeleteByPrefix(LiqLibraryObject(""));
}
#else
void SelectionOrbChecks()
{
   g_userLoaded=true;g_userCount=3;ArrayResize(g_userStrategies,3);
   OrbStrategyPreset p;OrbPresetDefaults(p);p.id="user_selection_0";p.name="Selection fixture";
   for(int i=0;i<3;i++)
   {
      ZeroMemory(g_userStrategies[i]);g_userStrategies[i].valid=true;g_userStrategies[i].preset=p;
      g_userStrategies[i].preset.id="user_selection_"+(string)i;g_userStrategies[i].symbol=_Symbol;
#ifdef SELECTION_ORB
      g_userStrategies[i].positions.independent=i>0;
#else
      g_userStrategies[i].independent=i>0;
#endif
      if(i==2)
      {
         g_userStrategies[i].preset.targetLeg=(int)ORB_TARGET_CUSTOM;
         for(int j=0;j<ORB_CUSTOM_RUNTIME_TOKENS;j++)g_userStrategies[i].runtime+="0\n";
         g_userStrategies[i].runtime+="0.00000001\n";
      }
   }
   for(int i=0;i<3;i++)
   {
      p=g_userStrategies[i].preset;
      g_strategyFilterPositionMode=0;g_strategyFilterGeometryEnabled=false;
      SelectionCheck(OrbStrategyPresetPassesMetricFilters(p),"default filters pass even with missing metrics");
      g_strategyFilterPositionMode=1;SelectionCheck(OrbStrategyPresetPassesMetricFilters(p)==(i==0),"legacy only");
      g_strategyFilterPositionMode=2;SelectionCheck(OrbStrategyPresetPassesMetricFilters(p)==(i>0),"independent only");
      g_strategyFilterGeometryEnabled=true;g_strategyFilterGeometry=0.5;
      SelectionCheck(OrbStrategyPresetPassesMetricFilters(p)==(i==1),"combined R and independent");
      g_strategyFilterPositionMode=0;p.invertMode=true;
      SelectionCheck(OrbStrategyPresetPassesMetricFilters(p)==(i!=2),"inverted architecture unchanged");
      g_strategyFilterGeometry=0.00000001;
      SelectionCheck(OrbStrategyPresetPassesMetricFilters(p)==(i==2),"custom tiny R");
      g_strategyFilterGeometry=0.00000002;SelectionCheck(!OrbStrategyPresetPassesMetricFilters(p),"tiny ratios are distinct");
      g_strategyFilterGeometry=0.5;p.targetMode=ORB_TARGET_RANGE_HEIGHT;
      SelectionCheck(!OrbStrategyPresetPassesMetricFilters(p),"dynamic target not fixed R");
      g_strategyFilterGeometryEnabled=false;SelectionCheck(OrbStrategyPresetPassesMetricFilters(p),"dynamic target kept without filter");
      g_strategyFilterNetEnabled=true;g_strategyFilterNet=5.0;
      SelectionCheck(!OrbStrategyPresetPassesMetricFilters(p),"metric filter still excludes missing result");
      p.metric1yReady=true;p.metric1yNetR=6.0;
      SelectionCheck(OrbStrategyPresetPassesMetricFilters(p),"existing net filter still works");
      g_strategyFilterNetEnabled=false;
   }
   p=g_userStrategies[0].preset;p.id="builtin_selection";
   g_strategyFilterPositionMode=1;SelectionCheck(OrbStrategyPresetPassesMetricFilters(p),"pre-independent builtins default legacy");
   g_strategyFilterPositionMode=2;SelectionCheck(!OrbStrategyPresetPassesMetricFilters(p),"builtins not mislabeled independent");
   g_strategyFilterPositionMode=0;OrbStrategyPresetBuildMatches("Selection fixture");
   SelectionCheck(ArraySize(g_strategyMatches)==3,"scan all fixtures");
   g_strategyFilterPositionMode=2;OrbStrategyPresetBuildMatches("Selection fixture");
   SelectionCheck(ArraySize(g_strategyMatches)==2,"scan independent fixtures");
   g_strategyFilterGeometryEnabled=true;g_strategyFilterGeometry=0.5;OrbStrategyPresetBuildMatches("Selection fixture");
   SelectionCheck(ArraySize(g_strategyMatches)==1,"scan combines R and mode");
   g_strategyFilterGeometryEnabled=false;g_strategyFilterPositionMode=1;OrbStrategyPresetBuildMatches("Selection fixture");
   SelectionCheck(ArraySize(g_strategyMatches)==1,"scan legacy fixture");
   g_strategyFilterPositionMode=0;OrbStrategyPresetBuildMatches("Selection fixture");
   SelectionCheck(ArraySize(g_strategyMatches)==3,"clear restores all fixtures");
}
#endif
void OnStart()
{
#ifdef SELECTION_SOL
   SelectionSolChecks();
#else
   SelectionOrbChecks();
#endif
   string result=StringFormat("{\"checks\":%d,\"failed\":%d}",selectionChecks,selectionFailed);
   int f=FileOpen("StrategySelection_"+SELECTION_NAME+".json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print(result);
}
#endif
