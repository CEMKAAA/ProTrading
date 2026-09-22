// Exercise layout at explicit viewport sizes; screenshot uses the same canvas.
int probeWidth=1600,probeHeight=900;
long ProbeChartGetInteger(long chart,ENUM_CHART_PROPERTY_INTEGER property,int sub=0)
{
   if(property==CHART_WIDTH_IN_PIXELS)return probeWidth;
   if(property==CHART_HEIGHT_IN_PIXELS)return probeHeight;
   return ChartGetInteger(chart,property,sub);
}
#define ChartGetInteger ProbeChartGetInteger
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef ChartGetInteger
int checks=0,failed=0;
void Check(bool condition,string name){checks++;if(!condition){failed++;Print("FAIL ",name);}}
void ClickLibrary(string id)
{
   string name=LiqLibraryObject(id);
   long x=ObjectGetInteger(0,name,OBJPROP_XDISTANCE)+5;
   double y=(double)ObjectGetInteger(0,name,OBJPROP_YDISTANCE)+5;
   g_liqLibraryOpenedAt=0;
   LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y);
}
void OnStart()
{
   PFX="LIQ_UI_PROBE_";g_eaEnabled=false;g_liqLibraryStarted=true;g_liqLibraryPanel=false;
   string found="";long fh=FileFindFirst(LiqLibraryFolder()+"\\*.lns",found,FILE_COMMON);
   if(fh!=INVALID_HANDLE){do{string nm="";double vv[];Print("LIB_DISCOVERY found=",found," unpack=",LiqLibraryUnpack(LiqLibraryFolder()+"\\"+found,nm,vv,false)," name=",nm);}while(FileFindNext(fh,found));FileFindClose(fh);}
   g_liqLibraryQuery="";g_liqLibraryFavorites=false;LiqLibraryScan();Print("LIB_DISCOVERY count=",ArraySize(g_liqLibraryFiles)," folder=",LiqLibraryFolder());
   Check(ArraySize(g_liqLibraryFiles)>0,"empty query includes presets");
   string testName="__liq_save_probe_"+(string)GetTickCount64(),testPath=LiqLibraryPath(testName);
   Check(LiqLibrarySave(testName),"save current settings");
   string loaded="";double before[],after[];LiqLibraryCapture(before);
   Check(LiqLibraryUnpack(testPath,loaded,after)&&loaded==testName,"read saved settings");
   bool equal=ArraySize(before)==ArraySize(after);
   for(int i=0;i<ArraySize(after)&&equal;i++)if(before[i]!=after[i])equal=false;
   Check(equal,"saved values round trip");
   LiqLibraryScan();bool listed=false;for(int i=0;i<ArraySize(g_liqLibraryNames);i++)if(g_liqLibraryNames[i]==testName)listed=true;
   Check(listed,"saved record visible for empty query");
   g_liqLibraryQuery=testName;LiqLibraryScan();Check(ArraySize(g_liqLibraryFiles)==1,"search exact name");
   g_liqLibraryFavorites=true;LiqLibraryScan();Check(ArraySize(g_liqLibraryFiles)==0,"favorites excludes unstarred");
   Check(LiqLibraryAtomicWrite(testPath+".fav","1"),"star saved preset");
   LiqLibraryScan();Check(ArraySize(g_liqLibraryFiles)==1,"favorites includes starred");
   FileDelete(testPath+".fav",FILE_COMMON);FileDelete(testPath+".fav.lock",FILE_COMMON);
   FileDelete(testPath,FILE_COMMON);FileDelete(testPath+".lock",FILE_COMMON);
   g_liqLibraryQuery="";g_liqLibraryFavorites=false;LiqLibraryScan();
   double preset[];Check(LiqImageRead(LiqImagePath(8),loaded,preset),"JP225 image preset decoded");
   Check(ArraySize(preset)==41&&preset[0]==90&&preset[1]==15&&preset[20]==4000&&preset[22]==0,"JP225 screenshot values");
   Check(!LiqImageRead(LiqImagePath(0),loaded,preset),"wrong symbol and family rejected");
   DrawDashboard();
   ChartRedraw(0);Sleep(100);ChartScreenShot(0,"LiqReadableUiMain.png",1600,900,ALIGN_LEFT);
   Check(LiqDashboardScale()==1.0,"no scaling");
   for(int font=5;font<=12;font++)Check(LiqFitFont(font)>=9,"readable font");
   Check(ObjectFind(0,PFX+"BTN_R_SELECT")>=0,"single R selector");
   Check(ObjectFind(0,PFX+"BTN_TP_1")<0,"old TP buttons absent");
   ObjectSetString(0,PFX+"EDIT_SL_PCT",OBJPROP_TEXT,"123.45");
   ClickLibrary("NAV_DOWN");
   ChartRedraw(0);Sleep(100);ChartScreenShot(0,"LiqReadableUiLower.png",1600,900,ALIGN_LEFT);
   Check(g_liqDashScroll>=0,"scroll bounded");
   Check(ObjectGetString(0,PFX+"EDIT_SL_PCT",OBJPROP_TEXT)=="123.45","unapplied edit preserved");
   ClickLibrary("NAV_UP");
   Check(g_liqDashScroll==0,"return to top");
   ClickLibrary("NAV_LIBRARY");
   Check(g_liqLibraryPanel,"strategy panel open");
   Check(ObjectFind(0,LiqLibraryObject("SAVE"))>=0,"save control");
   Check(ObjectFind(0,LiqLibraryObject("APPLY"))>=0,"apply control");
   ObjectSetString(0,LiqLibraryObject("QUERY"),OBJPROP_TEXT,"");
   ClickLibrary("SEARCH");Check(ObjectFind(0,LiqLibraryObject("PICK0"))>=0,"empty search renders first row");
   ClickLibrary("CLOSE");
   ObjectSetString(0,LiqLibraryObject("QUERY"),OBJPROP_TEXT,"__no_such_probe_strategy__");
   ClickLibrary("SEARCH");Check(g_liqLibraryOpen,"search dropdown open");
   Check(g_liqLibraryQuery=="__no_such_probe_strategy__","query consumed");
   ClickLibrary("CLOSE");Check(!g_liqLibraryOpen&&g_liqLibraryPanel,"dropdown X keeps panel");
   ChartRedraw(0);Sleep(100);
   ChartScreenShot(0,"LiqReadableUiProbe.png",1600,900,ALIGN_LEFT);
   ClickLibrary("CLOSE_PANEL");Check(!g_liqLibraryPanel,"panel close");
   LiqLibraryEvent(CHARTEVENT_OBJECT_CLICK,PFX+"BTN_R_SELECT");Check(g_liqLibraryRPicker,"R picker open");
   int count=0;for(int step=1;step<=100;step++)if(ObjectFind(0,LiqLibraryObject("RSTEP"+(string)step))>=0)count++;
   Check(count==28,"28 R choices");ClickLibrary("CLOSE");Check(!g_liqLibraryRPicker,"R picker close");
   probeWidth=800;probeHeight=600;
   LiqLibraryEvent(CHARTEVENT_CHART_CHANGE,"");
   ClickLibrary("NAV_DOWN");Check(g_liqDashScroll>0,"600px viewport scrolls");
   ClickLibrary("NAV_LIBRARY");Check(g_liqLibraryPanel&&!LiqLibraryWide(),"narrow strategy view");
   Check(ObjectGetInteger(0,LiqLibraryObject("QUERY"),OBJPROP_FONTSIZE)>=9,"narrow font unchanged");
   int f=FileOpen("LiqReadableUiProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}");FileClose(f);}
   DeleteByPrefix(PFX);
}
