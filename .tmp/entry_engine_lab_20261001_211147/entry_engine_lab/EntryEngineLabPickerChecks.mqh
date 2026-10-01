int LabProbePickCount()
{
   int count=0;
   for(int i=0;i<ObjectsTotal(0,0,-1);i++)
      if(StringFind(ObjectName(0,i,0,-1),LabUiPrefix()+"PICK_")==0)count++;
   return count;
}
void CheckLabPickers()
{
   g_labUi=0;g_labEngine=MakeEngine();
   Print("PICKER_RAW_EMPTY_FIND=",StringFind("EMA",""));
   Click(PREFIX+"BTN_LAB_ENGINES");
   Check(g_labUi==1&&ArraySize(g_labLibrary)>=10,"engine picker library has ten recipes");
   Check(LabProbePickCount()==10,"empty engine search renders first ten choices");
   Check(StringFind(ObjectGetString(0,LabUiPrefix()+"PAGE",OBJPROP_TEXT),"16 matches")>=0
      ||ArraySize(g_labLibrary)>10,"all six builtins and ten recipes are listed");
   ChartRedraw();ChartScreenShot(0,"EntryEngineLabEngines.png",1600,900);
   Click(LabUiPrefix()+"NEXT");
   Check(LabProbePickCount()>=6,"second engine page has remaining recipes");
   for(int i=10;i<16;i++)Check(ObjectFind(0,LabUiPrefix()+"PICK_"+(string)i)>=0,"recipe selectable "+(string)i);
   ObjectSetString(0,LabUiPrefix()+"SEARCH",OBJPROP_TEXT,"  sLoW EmA  ");Click(LabUiPrefix()+"SEARCHGO");
   Check(ObjectFind(0,LabUiPrefix()+"PICK_6")>=0,"engine search ignores case and surrounding whitespace");
   ObjectSetString(0,LabUiPrefix()+"SEARCH",OBJPROP_TEXT,"___NO_MATCH___");Click(LabUiPrefix()+"SEARCHGO");
   Check(LabProbePickCount()==0,"unknown engine search has no stale choices");
   Check(ObjectFind(0,LabUiPrefix()+"EMPTY")>=0,"empty search results have explanation");
   ObjectSetString(0,LabUiPrefix()+"SEARCH",OBJPROP_TEXT,"");Click(LabUiPrefix()+"SEARCHGO");
   Check(LabProbePickCount()==10&&g_labPage==0,"clearing search restores first engine page");
   double scale=g_libraryDashScale;int ox=g_libraryDashX,oy=g_libraryDashY;
   g_libraryDashScale=.5;g_libraryDashX=7;g_libraryDashY=11;LabUiDraw();
   int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),w=MathMin(820,MathMax(620,width-32));
   Check(ObjectGetInteger(0,LabUiPrefix()+"BG",OBJPROP_XDISTANCE)==MathMax(8,(width-w)/2)
      &&ObjectGetInteger(0,LabUiPrefix()+"BG",OBJPROP_XSIZE)==w,"modal coordinates are not dashboard-scaled twice");
   Check(ObjectGetInteger(0,LabUiPrefix()+"PICK_0",OBJPROP_FONTSIZE)>=8,"picker text stays readable on scaled dashboard");
   g_libraryDashScale=scale;g_libraryDashX=ox;g_libraryDashY=oy;
   Click(LabUiPrefix()+"CLOSE");LabOpenBuilder();Click(LabUiPrefix()+"FEATURE_0");
   Check(g_labUi==3&&LabProbePickCount()==10,"feature picker empty search renders choices");
   ChartRedraw();ChartScreenShot(0,"EntryEngineLabFeatures.png",1600,900);
   int seen=0;
   for(int page=0;page<5;page++)
   {
      if(page>0)Click(LabUiPrefix()+"NEXT");
      for(int i=page*10;i<MathMin(LAB_FEATURES,(page+1)*10);i++)
         if(ObjectFind(0,LabUiPrefix()+"PICK_"+(string)i)>=0)seen++;
   }
   Check(seen==LAB_FEATURES,"all 44 features accessible across pages");
   ObjectSetString(0,LabUiPrefix()+"SEARCH",OBJPROP_TEXT,"  ema  ");Click(LabUiPrefix()+"SEARCHGO");
   Check(ObjectFind(0,LabUiPrefix()+"PICK_32")>=0,"parameterized EMA is searchable");
   Click(LabUiPrefix()+"PICK_32");Check(g_labUi==2&&g_labDraft.buy[0].feature==32,"feature selection updates draft");
   Click(LabUiPrefix()+"RHS_0");
   Check(g_labUi==3&&ObjectFind(0,LabUiPrefix()+"PICK_-1")>=0,"right operand includes selectable constant");
   Click(LabUiPrefix()+"PICK_-1");Check(g_labUi==2&&g_labDraft.buy[0].rhsFeature==-1,"constant selection updates draft");
   Click(LabUiPrefix()+"CLOSE");EventKillTimer();
}
