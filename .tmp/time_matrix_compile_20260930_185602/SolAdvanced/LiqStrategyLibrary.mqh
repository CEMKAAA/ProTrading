#ifndef LIQ_STRATEGY_LIBRARY_MQH
#define LIQ_STRATEGY_LIBRARY_MQH
// Shared UI/storage only. Signal generation and transport ownership remain in the EA.
bool g_liqLibraryOpen=false,g_liqLibraryFavorites=false;
bool g_liqLibraryRPicker=false;
bool g_liqLibraryPanel=false,g_liqLibraryStarted=false;
string g_liqLibrarySelected="";
ulong g_liqLibraryOpenedAt=0;
int g_liqLibraryPage=0;
string g_liqLibraryQuery="",g_liqLibraryName="",g_liqLibraryStatus="";
string g_liqLibraryFiles[],g_liqLibraryNames[];
bool LiqLibraryRStepAllowed(int step)
{
   return step>=1&&step<=100&&(step<=20||step%10==0);
}
bool LiqLibraryCustomR(string raw,double &value)
{
   StringTrimLeft(raw);StringTrimRight(raw);
   if(raw=="")return false;
   int dots=0;
   for(int i=0;i<StringLen(raw);i++)
   {
      ushort c=StringGetCharacter(raw,i);
      if(c=='.'){if(++dots>1)return false;}
      else if(c<'0'||c>'9')return false;
   }
   value=StringToDouble(raw);
   return MathIsValidNumber(value)&&value>=0.00000001&&value<=10000.0;
}

string LiqLibraryHash(string text)
{
   uchar bytes[],key[],digest[];StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   ArrayResize(bytes,ArraySize(bytes)-1);
   if(CryptEncode(CRYPT_HASH_SHA256,bytes,key,digest)<=0)return "";
   string result="";for(int i=0;i<ArraySize(digest);i++)result+=StringFormat("%02x",digest[i]);
   return result;
}
string LiqLibraryLower(string value){StringToLower(value);return value;}
string LiqLibraryFolder(){return "LiqStrategies\\"+LiqLibraryHash(LiqLibraryFamily()+"|"+_Symbol);}
string LiqLibraryObject(string id){return PFX+"LIB_"+id;}
string LiqLibraryPath(string name){StringTrimLeft(name);StringTrimRight(name);return LiqLibraryFolder()+"\\"+LiqLibraryHash(LiqLibraryLower(name))+".lns";}
#include "LiqImagePresets.mqh"
bool LiqLibraryRead(string path,string &text)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   int count=(int)FileSize(f);if(count<=0||count>131072){FileClose(f);return false;}
   uchar bytes[];ArrayResize(bytes,count);bool ok=FileReadArray(f,bytes)==(uint)count;FileClose(f);
   if(!ok)return false;text=CharArrayToString(bytes,0,count,CP_UTF8);return true;
}
bool LiqLibraryAtomicWrite(string path,string text)
{
   FolderCreate("LiqStrategies",FILE_COMMON);FolderCreate(LiqLibraryFolder(),FILE_COMMON);
   // Exclusive per-record lock serializes identical-name saves from multiple charts.
   int lock=FileOpen(path+".lock",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE)return false;
   string temp=path+"."+(string)ChartID()+".tmp";
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN|FILE_COMMON);bool ok=false;
   if(f!=INVALID_HANDLE)
   {
      uchar bytes[];int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
      ok=FileWriteArray(f,bytes,0,n)==(uint)n;FileFlush(f);FileClose(f);
      if(ok){string verify="";ok=LiqLibraryRead(temp,verify)&&verify==text;}
      if(ok)ok=FileMove(temp,FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
      if(!ok)FileDelete(temp,FILE_COMMON);
   }
   FileClose(lock);return ok;
}
bool LiqLibraryUnpack(string path,string &name,double &values[],bool checkInputs=true)
{
   if(LiqImageRead(path,name,values))return true;
   string text="",lines[];if(!LiqLibraryRead(path,text))return false;
   int end=StringFind(text,"\nSHA256=");if(end<0)return false;
   string payload=StringSubstr(text,0,end);
   if(StringSubstr(text,end+8)!=LiqLibraryHash(payload))return false;
   int n=StringSplit(payload,'\n',lines);
   double current[];int count=LiqLibraryCapture(current);
   int storedCount=n>5 ? (int)StringToInteger(lines[5]) : 0;
   if(storedCount!=count&&storedCount!=count-1)return false;
   bool oldVersion=(n==6+storedCount&&lines[0]=="LIQ_STRATEGY_V1");
#ifdef LN_SOL_ADV_NAS_READY
   bool newVersion=(n==7+storedCount&&lines[0]=="LIQ_STRATEGY_NAS_V1");
   bool customVersion=(n==8+storedCount&&lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_V1");
   bool timeVersion=(n==8+storedCount&&lines[0]=="LIQ_STRATEGY_NAS_TCAL_V1");
   bool timeCustomVersion=(n==9+storedCount&&lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1");
   if(newVersion){LnNasPolicy parsed;if(!LnNasUnpack(lines[6+storedCount],parsed))return false;}
   if(timeVersion)
   {
      LnNasPolicy parsed;bool enabled=false;int hours[];
      if(!LnNasUnpack(lines[6+storedCount],parsed)||!TCalStrategyRead(lines[7+storedCount],enabled,hours))return false;
   }
   if(customVersion)
   {
      LnNasPolicy parsed;double custom=0;
      if(!LnNasUnpack(lines[6+storedCount],parsed)||!LiqLibraryCustomR(lines[7+storedCount],custom)
         ||(int)StringToInteger(lines[9])!=(int)ERL_RR_CUSTOM)return false;
   }
   if(timeCustomVersion)
   {
      LnNasPolicy parsed;double custom=0;bool enabled=false;int hours[];
      if(!LnNasUnpack(lines[6+storedCount],parsed)||!LiqLibraryCustomR(lines[7+storedCount],custom)
         ||!TCalStrategyRead(lines[8+storedCount],enabled,hours)
         ||(int)StringToInteger(lines[9])!=(int)ERL_RR_CUSTOM)return false;
   }
#else
   bool newVersion=false;
   bool customVersion=false;
   bool timeVersion=false;
   bool timeCustomVersion=false;
#endif
   if((!oldVersion&&!newVersion&&!customVersion&&!timeVersion&&!timeCustomVersion)
      ||lines[1]!=LiqLibraryFamily()||lines[2]!=_Symbol)return false;
   if(checkInputs&&lines[4]!=LiqLibraryHash(LiqLibraryInputContract()))return false;
   name=lines[3];ArrayResize(values,count);
   for(int i=0;i<storedCount;i++)
   {
      values[i]=StringToDouble(lines[6+i]);
      if(!MathIsValidNumber(values[i])||DoubleToString(values[i],16)!=lines[6+i])return false;
   }
   if(storedCount<count)values[count-1]=100.0;
   return true;
}
bool LiqLibrarySave(string name)
{
   StringTrimLeft(name);StringTrimRight(name);
   if(StringLen(name)<1||StringLen(name)>80||StringFind(name,"\n")>=0||StringFind(name,"\r")>=0)return false;
   double values[];int count=LiqLibraryCapture(values);
   string version="LIQ_STRATEGY_V1";
#ifdef LN_SOL_ADV_NAS_READY
   version=g_target==ERL_RR_CUSTOM?"LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1":"LIQ_STRATEGY_NAS_TCAL_V1";
#endif
   string payload=version+"\n"+LiqLibraryFamily()+"\n"+_Symbol+"\n"+name+"\n"
      +LiqLibraryHash(LiqLibraryInputContract())+"\n"+(string)count;
   for(int i=0;i<count;i++)payload+="\n"+DoubleToString(values[i],16);
#ifdef LN_SOL_ADV_NAS_READY
   payload+="\n"+LnNasPack(g_lnNas);
   if(g_target==ERL_RR_CUSTOM)payload+="\n"+DoubleToString(g_customTargetR,8);
#endif
   payload+="\n"+TCalStrategyText();
   return LiqLibraryAtomicWrite(LiqLibraryPath(name),payload+"\nSHA256="+LiqLibraryHash(payload));
}
bool LiqLibraryCanApply()
{
   if(g_btRunning||ArraySize(g_bridgePending)>0){g_liqLibraryStatus="Wait: backtest or pending bridge events";return false;}
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0)continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==RuntimeMagic())
      {g_liqLibraryStatus="Close owned positions before applying settings";return false;}
   }
   return true;
}
bool LiqLibraryApply(string path)
{
   if(!LiqLibraryCanApply())return false;
   string name="";double values[];
   if(!LiqLibraryUnpack(path,name,values))
   {g_liqLibraryStatus="Not applied: incompatible Inputs or damaged preset";return false;}
   string timeMatrix=TCalStrategyOffText();
#ifdef LN_SOL_ADV_NAS_READY
   LnNasPolicy policy;LnNasDefaults(policy);
   double customR=0.0;
   if(StringFind(path,"image://")!=0)
   {
      string record="",lines[];
      if(LiqLibraryRead(path,record))
      {
         int end=StringFind(record,"\nSHA256=");
         if(end<0){g_liqLibraryStatus="Damaged filter strategy";return false;}
         int count=StringSplit(StringSubstr(record,0,end),'\n',lines);
         if(count>0&&lines[0]=="LIQ_STRATEGY_NAS_V1"
            &&!LnNasUnpack(lines[count-1],policy))
         {g_liqLibraryStatus="Damaged filter strategy";return false;}
         if(count>0&&lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_V1")
         {
            if(count<2||!LnNasUnpack(lines[count-2],policy)||!LiqLibraryCustomR(lines[count-1],customR))
            {g_liqLibraryStatus="Damaged custom R strategy";return false;}
         }
         if(count>0&&(lines[0]=="LIQ_STRATEGY_NAS_TCAL_V1"
            ||lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1"))
         {
            int policyIndex=6+(int)StringToInteger(lines[5]);
            if(!LnNasUnpack(lines[policyIndex],policy))
            {g_liqLibraryStatus="Damaged filter strategy";return false;}
            if(lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1"
               &&!LiqLibraryCustomR(lines[policyIndex+1],customR))
            {g_liqLibraryStatus="Damaged custom R strategy";return false;}
            timeMatrix=lines[count-1];
         }
      }
   }
   if((int)values[8]==(int)ERL_TARGET_OPPOSITE_SIGNAL
      &&(policy.gate!=0||policy.exitMode!=0||policy.independent||policy.reverseExit!=InpCloseOnReverse||policy.reverseWaitMinutes>0))
   {g_liqLibraryStatus="NAS policy requires fixed target";return false;}
   if(!LnNasCompatible(policy)){g_liqLibraryStatus="Account does not support these position settings";return false;}
   string previousTime=TCalStrategyText();
   if(!TCalStrategyApplyText(timeMatrix))
   {g_liqLibraryStatus="Time matrix settings could not be saved";return false;}
   LnNasPolicy previous=g_lnNas;g_lnNas=policy;
   if(!LnNasSaveRuntime())
   {
      g_lnNas=previous;TCalStrategyApplyText(previousTime);
      g_liqLibraryStatus="Filter settings could not be saved";return false;
   }
   LnNasInvalidate();
   g_lnNasDraft=g_lnNas;
   if(g_lnNasPanel)
   {
      DeleteByPrefix(PFX+"NAS_");
      LnNasDrawNav();
      LnNasDrawPanel();
   }
#else
   if(!TCalStrategyApplyText(timeMatrix))
   {g_liqLibraryStatus="Time matrix settings could not be saved";return false;}
#endif
   LiqLibraryAssign(values);
#ifdef LN_SOL_ADV_NAS_READY
   g_customTargetR=customR;
#endif
   SanitizeHalfMode();
   g_liqLibraryName=name;g_liqLibraryStatus="Applied: "+name;
   RefreshAfterConfigChange(true);g_tcalChanged=false;return true;
}
void LiqLibraryScan()
{
   ArrayResize(g_liqLibraryFiles,0);ArrayResize(g_liqLibraryNames,0);
   string found="";long h=FileFindFirst(LiqLibraryFolder()+"\\*.lns",found,FILE_COMMON);
   if(h!=INVALID_HANDLE)do
   {
      string path=LiqLibraryFolder()+"\\"+found,name="";double values[];
      if(!LiqLibraryUnpack(path,name,values,false))continue;
      if(g_liqLibraryFavorites&&!FileIsExist(path+".fav",FILE_COMMON))continue;
      if(g_liqLibraryQuery!=""&&StringFind(LiqLibraryLower(name),LiqLibraryLower(g_liqLibraryQuery))<0)continue;
      int n=ArraySize(g_liqLibraryFiles);ArrayResize(g_liqLibraryFiles,n+1);ArrayResize(g_liqLibraryNames,n+1);
      g_liqLibraryFiles[n]=path;g_liqLibraryNames[n]=name;
   }while(FileFindNext(h,found));
   if(h!=INVALID_HANDLE)FileFindClose(h);
   for(int i=0;i<ArraySize(g_liqImagePresets);i++)
   {
      if(!LiqImageCompatible(i))continue;
      string name=g_liqImagePresets[i].name,path=LiqImagePath(i);
      // A same-name user save takes precedence over the immutable image preset.
      bool overridden=false;
      string own=LiqLibraryPath(name),saved="";double values[];
      if(LiqLibraryUnpack(own,saved,values,false))overridden=true;
      if(overridden)continue;
      if(g_liqLibraryFavorites&&!FileIsExist(path+".fav",FILE_COMMON))continue;
      if(g_liqLibraryQuery!=""&&StringFind(LiqLibraryLower(name),LiqLibraryLower(g_liqLibraryQuery))<0)continue;
      int n=ArraySize(g_liqLibraryFiles);ArrayResize(g_liqLibraryFiles,n+1);ArrayResize(g_liqLibraryNames,n+1);
      g_liqLibraryFiles[n]=path;g_liqLibraryNames[n]=name;
   }
   // Stable name order keeps paging consistent after file updates.
   for(int i=1;i<ArraySize(g_liqLibraryNames);i++)for(int j=i;j>0&&StringCompare(g_liqLibraryNames[j],g_liqLibraryNames[j-1],false)<0;j--)
   {string t=g_liqLibraryNames[j];g_liqLibraryNames[j]=g_liqLibraryNames[j-1];g_liqLibraryNames[j-1]=t;
    t=g_liqLibraryFiles[j];g_liqLibraryFiles[j]=g_liqLibraryFiles[j-1];g_liqLibraryFiles[j-1]=t;}
   g_liqLibraryPage=MathMax(0,MathMin(g_liqLibraryPage,(ArraySize(g_liqLibraryFiles)-1)/6));
}
void LiqLibraryWidget(string id,ENUM_OBJECT type,int x,int y,int w,int h,string text,color bg)
{
   string key=LiqLibraryObject(id);bool fresh=ObjectFind(0,key)<0;
   if(fresh)ObjectCreate(0,key,type,0,0,0);
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,w);ObjectSetInteger(0,key,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_FONTSIZE,9);ObjectSetInteger(0,key,OBJPROP_BACK,false);
   ObjectSetInteger(0,key,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL?DASH_Z+50:DASH_Z+60);
   ObjectSetString(0,key,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,key,OBJPROP_HIDDEN,true);
   if(type!=OBJ_EDIT||fresh)ObjectSetString(0,key,OBJPROP_TEXT,type==OBJ_LABEL&&text==""?" ":text);
}
bool LiqLibraryWide(){return ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)>=1420;}
int LiqLibraryLeft(){return LiqLibraryWide()?780:8;}
int LiqLibraryWidth(){return (int)MathMax(280,MathMin(620,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-LiqLibraryLeft()-8));}
void LiqLibraryReadEdits()
{
   if(ObjectFind(0,LiqLibraryObject("QUERY"))>=0)g_liqLibraryQuery=ObjectGetString(0,LiqLibraryObject("QUERY"),OBJPROP_TEXT);
   if(ObjectFind(0,LiqLibraryObject("NAME"))>=0)g_liqLibraryName=ObjectGetString(0,LiqLibraryObject("NAME"),OBJPROP_TEXT);
}
void LiqLibraryNavigation()
{
   color c=C'38,101,176';
   LiqLibraryWidget("NAV_UP",OBJ_BUTTON,8,8,58,25,"UP",c);
   LiqLibraryWidget("NAV_DOWN",OBJ_BUTTON,70,8,58,25,"DOWN",c);
   LiqLibraryWidget("NAV_LEFT",OBJ_BUTTON,132,8,30,25,"<",c);
   LiqLibraryWidget("NAV_RIGHT",OBJ_BUTTON,166,8,30,25,">",c);
   LiqLibraryWidget("NAV_LIBRARY",OBJ_BUTTON,202,8,140,25,"STRATEGIES",c);
#ifdef LN_SOL_ADV_NAS_READY
   ResearchLbLauncher(348,8);
#endif
}
void LiqLibraryDraw()
{
   int x=LiqLibraryLeft(),y=42,w=LiqLibraryWidth();color bg=C'24,30,42',button=C'38,101,176';
   if(g_liqLibraryRPicker||g_liqLibraryOpen)
   {ObjectDelete(0,TCalId("CSV_RIGHT"));ObjectDelete(0,TCalId("CSV_FOLDER_ROOT"));ObjectDelete(0,TCalId("CSV_FOLDER_SUFFIX"));}
   if(g_liqLibraryRPicker)
   {
      x=8;w=(int)MathMax(280,MathMin(650,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-16));
#ifdef LN_SOL_ADV_NAS_READY
      LiqLibraryWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,258,"",bg);
#else
      LiqLibraryWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,210,"",bg);
#endif
      LiqLibraryWidget("TITLE",OBJ_LABEL,x+12,y+10,w-50,20,"FIXED TARGET / SELECT R",bg);
      LiqLibraryWidget("CLOSE",OBJ_BUTTON,x+w-38,y+5,30,24,"X",clrMaroon);
      int cell=(w-24)/7;
      for(int index=0;index<28;index++)
      {
         int step=index<20?index+1:30+(index-20)*10;
         LiqLibraryWidget("RSTEP"+(string)step,OBJ_BUTTON,x+12+(index%7)*cell,y+40+(index/7)*33,
            cell-3,30,DoubleToString(step*0.05,2)+"R",MathAbs(TargetR(g_target)-step*0.05)<1e-8?C'184,103,22':button);
      }
#ifdef LN_SOL_ADV_NAS_READY
      LiqLibraryWidget("CUSTOM_LABEL",OBJ_LABEL,x+12,y+176,110,20,"CUSTOM R",bg);
      LiqLibraryWidget("CUSTOM_VALUE",OBJ_EDIT,x+120,y+170,160,28,
         g_target==ERL_RR_CUSTOM?DoubleToString(g_customTargetR,8):DoubleToString(TargetR(g_target),2),C'38,46,60');
      LiqLibraryWidget("CUSTOM_APPLY",OBJ_BUTTON,x+288,y+170,104,28,"APPLY",button);
      LiqLibraryWidget("STATUS",OBJ_LABEL,x+12,y+218,w-24,25,StringSubstr(g_liqLibraryStatus,0,75),bg);
#else
      LiqLibraryWidget("STATUS",OBJ_LABEL,x+12,y+183,w-24,20,StringSubstr(g_liqLibraryStatus,0,75),bg);
#endif
      return;
   }
   LiqLibraryWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,410,"",bg);
   LiqLibraryWidget("TITLE",OBJ_LABEL,x+12,y+10,w-50,20,"STRATEGIES // "+_Symbol,bg);
   LiqLibraryWidget("CLOSE_PANEL",OBJ_BUTTON,x+w-38,y+5,30,24,"X",clrMaroon);
   LiqLibraryWidget("QUERY",OBJ_EDIT,x+12,y+38,w-260,24,g_liqLibraryQuery,C'38,46,60');
   LiqLibraryWidget("SEARCH",OBJ_BUTTON,x+w-240,y+38,76,24,"SEARCH",button);
   LiqLibraryWidget("APPLY",OBJ_BUTTON,x+w-158,y+38,146,24,"APPLY STRATEGY",C'184,103,22');
   LiqLibraryWidget("FAV",OBJ_BUTTON,x+12,y+70,130,24,g_liqLibraryFavorites?"FAVORITES ON":"FAVORITES OFF",button);
   LiqLibraryWidget("SELECTED",OBJ_LABEL,x+12,y+106,w-24,20,"Selected: "+StringSubstr(g_liqLibraryName,0,50),bg);
   if(!g_liqLibraryOpen)TCalCsvLauncher(PFX,x+12,y+138,1.0,DASH_Z+60,true);
   LiqLibraryWidget("SAVE_TITLE",OBJ_LABEL,x+12,y+303,w-24,20,"SAVE CURRENT STRATEGY (APPLY edits first)",bg);
   LiqLibraryWidget("NAME",OBJ_EDIT,x+12,y+330,w-190,24,g_liqLibraryName,C'38,46,60');
   LiqLibraryWidget("SAVE",OBJ_BUTTON,x+w-170,y+330,158,24,"SAVE STRATEGY",button);
   LiqLibraryWidget("STATUS",OBJ_LABEL,x+12,y+368,w-24,20,StringSubstr(g_liqLibraryStatus,0,75),bg);
   if(g_liqLibraryOpen)
   {
      int py=y+132;
      LiqLibraryWidget("POP_BG",OBJ_RECTANGLE_LABEL,x+12,py,w-24,164,"",C'20,27,39');
      LiqLibraryWidget("PREV",OBJ_BUTTON,x+18,py+3,30,22,"<",button);
      LiqLibraryWidget("NEXT",OBJ_BUTTON,x+52,py+3,30,22,">",button);
      LiqLibraryWidget("PAGE",OBJ_LABEL,x+90,py+5,360,20,ArraySize(g_liqLibraryFiles)==0?"0 results (check symbol / favorites)":(string)(g_liqLibraryPage+1)+" / "+(string)((ArraySize(g_liqLibraryFiles)+5)/6)+" | "+(string)ArraySize(g_liqLibraryFiles)+" results",bg);
      LiqLibraryWidget("CLOSE",OBJ_BUTTON,x+w-50,py+3,30,22,"X",clrMaroon);
      for(int i=0;i<6;i++)
      {
         int n=g_liqLibraryPage*6+i;
         if(n>=ArraySize(g_liqLibraryFiles))
         {ObjectDelete(0,LiqLibraryObject("PICK"+(string)i));ObjectDelete(0,LiqLibraryObject("STAR"+(string)i));continue;}
         LiqLibraryWidget("STAR"+(string)i,OBJ_BUTTON,x+18,py+28+i*22,30,20,
            FileIsExist(g_liqLibraryFiles[n]+".fav",FILE_COMMON)?"*":"+",C'58,66,82');
         LiqLibraryWidget("PICK"+(string)i,OBJ_BUTTON,x+52,py+28+i*22,w-70,20,g_liqLibraryNames[n],C'38,46,60');
      }
   }
}
void LiqLibraryClearResults()
{
   string ids[]={"POP_BG","PREV","NEXT","PAGE","CLOSE"};
   for(int i=0;i<ArraySize(ids);i++)ObjectDelete(0,LiqLibraryObject(ids[i]));
   for(int i=0;i<6;i++){ObjectDelete(0,LiqLibraryObject("PICK"+(string)i));ObjectDelete(0,LiqLibraryObject("STAR"+(string)i));}
}
void LiqLibraryRedrawPreserve()
{
   string keys[],values[];
   for(int i=0;i<ObjectsTotal(0);i++)
   {
      string key=ObjectName(0,i);
      if(StringFind(key,PFX+"EDIT_")!=0)continue;
      int n=ArraySize(keys);ArrayResize(keys,n+1);ArrayResize(values,n+1);keys[n]=key;values[n]=ObjectGetString(0,key,OBJPROP_TEXT);
   }
   DrawDashboard();
   for(int i=0;i<ArraySize(keys);i++)if(ObjectFind(0,keys[i])>=0)ObjectSetString(0,keys[i],OBJPROP_TEXT,values[i]);
   ChartRedraw(0);
}
bool LiqLibraryDashboard()
{
   if(IsTesterMode()||!InpShowDashboard)return false;
   if(!g_liqLibraryStarted){g_liqLibraryPanel=LiqLibraryWide();g_liqLibraryStarted=true;}
   LiqLibraryNavigation();
   if(g_liqLibraryPanel||g_liqLibraryRPicker)LiqLibraryDraw();
   else {ObjectDelete(0,TCalId("CSV_RIGHT"));ObjectDelete(0,TCalId("CSV_FOLDER_ROOT"));ObjectDelete(0,TCalId("CSV_FOLDER_SUFFIX"));}
   return g_liqLibraryRPicker||g_liqLibraryOpen||(g_liqLibraryPanel&&!LiqLibraryWide());
}
bool LiqLibraryEvent(int id,string name,long mx=0,double my=0)
{
   if(id==CHARTEVENT_OBJECT_ENDEDIT&&StringFind(name,LiqLibraryObject(""))==0){LiqLibraryReadEdits();return true;}
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      LiqLibraryReadEdits();DeleteByPrefix(LiqLibraryObject(""));LiqLibraryRedrawPreserve();return true;
   }
   if(id==CHARTEVENT_OBJECT_CLICK&&name==PFX+"BTN_R_SELECT"&&!g_liqLibraryOpen&&!g_liqLibraryRPicker)
   {
      LiqLibraryReadEdits();DeleteByPrefix(LiqLibraryObject(""));g_liqLibraryRPicker=true;
      g_liqLibraryOpenedAt=GetTickCount64();LiqLibraryDraw();ChartRedraw(0);return true;
   }
   bool covers=(g_liqLibraryRPicker||g_liqLibraryOpen||
      (g_liqLibraryPanel&&mx>=LiqLibraryLeft()&&mx<LiqLibraryLeft()+LiqLibraryWidth()&&my>=42&&my<452));
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(name,LiqLibraryObject(""))==0||covers)
      {if(ObjectFind(0,name)>=0&&ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);return true;}
      return false;
   }
   if(id!=CHARTEVENT_CLICK)return g_liqLibraryRPicker||g_liqLibraryOpen;
   if(GetTickCount64()-g_liqLibraryOpenedAt<150)return covers;
   string action="";
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string key=ObjectName(0,i);
      if(StringFind(key,LiqLibraryObject(""))!=0||ObjectGetInteger(0,key,OBJPROP_TYPE)!=OBJ_BUTTON)continue;
      long x=ObjectGetInteger(0,key,OBJPROP_XDISTANCE),y=ObjectGetInteger(0,key,OBJPROP_YDISTANCE);
      if(mx>=x&&mx<x+ObjectGetInteger(0,key,OBJPROP_XSIZE)&&my>=y&&my<y+ObjectGetInteger(0,key,OBJPROP_YSIZE))
      {action=StringSubstr(key,StringLen(LiqLibraryObject("")));break;}
   }
   if(action=="")return covers;
   LiqLibraryReadEdits();
   if(g_liqLibraryRPicker)
   {
      bool close=action=="CLOSE";
#ifdef LN_SOL_ADV_NAS_READY
      if(action=="CUSTOM_APPLY")
      {
         double custom=0;
         if(!LiqLibraryCustomR(ObjectGetString(0,LiqLibraryObject("CUSTOM_VALUE"),OBJPROP_TEXT),custom))
            g_liqLibraryStatus="Enter R from 0.00000001 to 10000 (decimal point)";
         else if(LiqLibraryCanApply())
         {g_customTargetR=custom;g_target=ERL_RR_CUSTOM;g_targetModel=ERL_TARGET_FIXED_R;
          SanitizeHalfMode();RefreshAfterConfigChange(false);close=true;}
      }
#endif
      if(StringFind(action,"RSTEP")==0)
      {
         int step=(int)StringToInteger(StringSubstr(action,5));
         if(LiqLibraryRStepAllowed(step)&&LiqLibraryCanApply())
         {g_target=(ERL_RR_MODE)(100+step);g_targetModel=ERL_TARGET_FIXED_R;SanitizeHalfMode();RefreshAfterConfigChange(false);close=true;}
      }
      if(close){g_liqLibraryRPicker=false;DeleteByPrefix(LiqLibraryObject(""));LiqLibraryRedrawPreserve();}
      else {LiqLibraryDraw();ChartRedraw(0);}return true;
   }
   if(StringFind(action,"NAV_")==0)
   {
      if(action=="NAV_LIBRARY")g_liqLibraryPanel=!g_liqLibraryPanel;
      if(action=="NAV_UP")g_liqDashScroll-=MathMax(60,LiqViewportHeight()-60);
      if(action=="NAV_DOWN")g_liqDashScroll+=MathMax(60,LiqViewportHeight()-60);
      if(action=="NAV_LEFT")g_liqDashHorizontal-=200;
      if(action=="NAV_RIGHT")g_liqDashHorizontal+=200;
      LiqFitClamp();g_liqLibraryOpen=false;DeleteByPrefix(LiqLibraryObject(""));LiqLibraryRedrawPreserve();return true;
   }
   if(action=="CLOSE_PANEL")
   {g_liqLibraryPanel=g_liqLibraryOpen=false;DeleteByPrefix(LiqLibraryObject(""));LiqLibraryRedrawPreserve();return true;}
   if(action=="CLOSE"){g_liqLibraryOpen=false;LiqLibraryClearResults();}
   else if(action=="SEARCH"){g_liqLibraryOpen=true;g_liqLibraryPage=0;LiqLibraryScan();}
   else if(action=="FAV"){g_liqLibraryFavorites=!g_liqLibraryFavorites;g_liqLibraryOpen=true;g_liqLibraryPage=0;LiqLibraryScan();}
   else if(action=="PREV")g_liqLibraryPage=MathMax(0,g_liqLibraryPage-1);
   else if(action=="NEXT"){g_liqLibraryPage++;LiqLibraryScan();}
   else if(action=="APPLY"){if(g_liqLibrarySelected!="")LiqLibraryApply(g_liqLibrarySelected);else g_liqLibraryStatus="Select a strategy from SEARCH";}
   else if(action=="SAVE")
   {bool ok=LiqLibrarySave(g_liqLibraryName);g_liqLibraryStatus=ok?"SAVED: "+g_liqLibraryName:"Save failed: name or file lock";
    if(ok){g_liqLibrarySelected=LiqLibraryPath(g_liqLibraryName);g_liqLibraryQuery="";g_liqLibraryFavorites=false;g_liqLibraryPage=0;g_liqLibraryOpen=true;ObjectSetString(0,LiqLibraryObject("QUERY"),OBJPROP_TEXT,"");}
    LiqLibraryScan();}
   else if(StringFind(action,"PICK")==0||StringFind(action,"STAR")==0)
   {
      int n=g_liqLibraryPage*6+(int)StringToInteger(StringSubstr(action,4));
      if(n>=0&&n<ArraySize(g_liqLibraryFiles))
      {
         string path=g_liqLibraryFiles[n];
         if(StringFind(action,"PICK")==0)
         {
            g_liqLibrarySelected=path;
            if(LiqLibraryApply(path))
            {g_liqLibraryOpen=false;LiqLibraryClearResults();ObjectSetString(0,LiqLibraryObject("NAME"),OBJPROP_TEXT,g_liqLibraryName);}
         }
         else if(FileIsExist(path+".fav",FILE_COMMON))FileDelete(path+".fav",FILE_COMMON);
         else LiqLibraryAtomicWrite(path+".fav","1");
         LiqLibraryScan();
      }
   }
   LiqLibraryDraw();ChartRedraw(0);return true;
}
#endif
