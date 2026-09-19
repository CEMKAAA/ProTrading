#ifndef LIQ_STRATEGY_LIBRARY_MQH
#define LIQ_STRATEGY_LIBRARY_MQH
// Shared UI/storage only. Signal generation and transport ownership remain in the EA.
bool g_liqLibraryOpen=false,g_liqLibraryFavorites=false;
int g_liqLibraryPage=0;
string g_liqLibraryQuery="",g_liqLibraryName="",g_liqLibraryStatus="";
string g_liqLibraryFiles[],g_liqLibraryNames[];

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
   string text="",lines[];if(!LiqLibraryRead(path,text))return false;
   int end=StringFind(text,"\nSHA256=");if(end<0)return false;
   string payload=StringSubstr(text,0,end);
   if(StringSubstr(text,end+8)!=LiqLibraryHash(payload))return false;
   int n=StringSplit(payload,'\n',lines);
   double current[];int count=LiqLibraryCapture(current);
   if(n!=6+count||lines[0]!="LIQ_STRATEGY_V1"||lines[1]!=LiqLibraryFamily()||lines[2]!=_Symbol)return false;
   if(checkInputs&&lines[4]!=LiqLibraryHash(LiqLibraryInputContract()))return false;
   if((int)StringToInteger(lines[5])!=count)return false;
   name=lines[3];ArrayResize(values,count);
   for(int i=0;i<count;i++)
   {
      values[i]=StringToDouble(lines[6+i]);
      if(!MathIsValidNumber(values[i])||DoubleToString(values[i],16)!=lines[6+i])return false;
   }
   return true;
}
bool LiqLibrarySave(string name)
{
   StringTrimLeft(name);StringTrimRight(name);
   if(StringLen(name)<1||StringLen(name)>80||StringFind(name,"\n")>=0||StringFind(name,"\r")>=0)return false;
   double values[];int count=LiqLibraryCapture(values);
   string payload="LIQ_STRATEGY_V1\n"+LiqLibraryFamily()+"\n"+_Symbol+"\n"+name+"\n"
      +LiqLibraryHash(LiqLibraryInputContract())+"\n"+(string)count;
   for(int i=0;i<count;i++)payload+="\n"+DoubleToString(values[i],16);
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
   LiqLibraryAssign(values);SanitizeHalfMode();
   g_liqLibraryName=name;g_liqLibraryStatus="Applied: "+name;
   RefreshAfterConfigChange(true);return true;
}
void LiqLibraryScan()
{
   ArrayResize(g_liqLibraryFiles,0);ArrayResize(g_liqLibraryNames,0);
   string found="";long h=FileFindFirst(LiqLibraryFolder()+"\\*.lns",found,FILE_COMMON);
   if(h==INVALID_HANDLE)return;
   do
   {
      string path=LiqLibraryFolder()+"\\"+found,name="";double values[];
      if(!LiqLibraryUnpack(path,name,values,false))continue;
      if(g_liqLibraryFavorites&&!FileIsExist(path+".fav",FILE_COMMON))continue;
      if(StringFind(LiqLibraryLower(name),LiqLibraryLower(g_liqLibraryQuery))<0)continue;
      int n=ArraySize(g_liqLibraryFiles);ArrayResize(g_liqLibraryFiles,n+1);ArrayResize(g_liqLibraryNames,n+1);
      g_liqLibraryFiles[n]=path;g_liqLibraryNames[n]=name;
   }while(FileFindNext(h,found));FileFindClose(h);
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
   ObjectSetInteger(0,key,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL?500:510);
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,key,OBJPROP_HIDDEN,true);
   if(type!=OBJ_EDIT||fresh)ObjectSetString(0,key,OBJPROP_TEXT,text);
}
void LiqLibraryDraw()
{
   DeleteByPrefix(LiqLibraryObject(""));
   int w=(int)MathMin(650,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-20);
   int x=10,y=40; color bg=C'22,32,46';
   LiqLibraryWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,365,"",bg);
   LiqLibraryWidget("CLOSE",OBJ_BUTTON,x+w-35,y+5,28,24,"X",clrMaroon);
   LiqLibraryWidget("TITLE",OBJ_LABEL,x+10,y+8,w-50,20,"STRATEGIES / "+_Symbol,bg);
   LiqLibraryWidget("QUERY",OBJ_EDIT,x+10,y+37,w-160,25,g_liqLibraryQuery,bg);
   LiqLibraryWidget("SEARCH",OBJ_BUTTON,x+w-144,y+37,64,25,"Search",clrDarkSlateGray);
   LiqLibraryWidget("FAV",OBJ_BUTTON,x+w-75,y+37,65,25,g_liqLibraryFavorites?"Fav ON":"Fav OFF",clrDarkSlateGray);
   for(int i=0;i<6;i++)
   {
      int index=g_liqLibraryPage*6+i;if(index>=ArraySize(g_liqLibraryFiles))break;
      LiqLibraryWidget("PICK"+(string)i,OBJ_BUTTON,x+10,y+70+i*28,w-60,25,g_liqLibraryNames[index],clrDarkSlateGray);
      LiqLibraryWidget("STAR"+(string)i,OBJ_BUTTON,x+w-45,y+70+i*28,35,25,
         FileIsExist(g_liqLibraryFiles[index]+".fav",FILE_COMMON)?"*":"+",clrDarkSlateGray);
   }
   LiqLibraryWidget("PREV",OBJ_BUTTON,x+10,y+242,35,23,"<",clrDarkSlateGray);
   LiqLibraryWidget("NEXT",OBJ_BUTTON,x+50,y+242,35,23,">",clrDarkSlateGray);
   LiqLibraryWidget("PAGE",OBJ_LABEL,x+100,y+245,100,20,(string)(g_liqLibraryPage+1)+" / "+(string)MathMax(1,(ArraySize(g_liqLibraryFiles)+5)/6),bg);
   LiqLibraryWidget("NAME",OBJ_EDIT,x+10,y+275,w-145,25,g_liqLibraryName,bg);
   LiqLibraryWidget("SAVE",OBJ_BUTTON,x+w-130,y+275,120,25,"Save / Update",clrDarkSlateGray);
   LiqLibraryWidget("RR",OBJ_EDIT,x+10,y+310,70,25,DoubleToString(TargetR(g_target),2),bg);
   LiqLibraryWidget("APPLY_R",OBJ_BUTTON,x+85,y+310,115,25,"Apply R (FIX)",clrDarkSlateGray);
   LiqLibraryWidget("R_HINT",OBJ_LABEL,x+210,y+314,w-220,20,"0.05 - 5.00 / step 0.05",bg);
   LiqLibraryWidget("STATUS",OBJ_LABEL,x+10,y+342,w-20,20,StringSubstr(g_liqLibraryStatus,0,85),bg);
   ChartRedraw(0);
}
bool LiqLibraryDashboard()
{
   if(IsTesterMode()||!InpShowDashboard)return false;
   if(g_liqLibraryOpen)return true;
   ButtonObj("BTN_LIBRARY",InpDashboardX+550,InpDashboardY+7,118,20,"STRATEGIES / R",C'25,90,125');
   return false;
}
bool LiqLibraryEvent(int id,string name)
{
   if(id==CHARTEVENT_OBJECT_CLICK&&name==PFX+"BTN_LIBRARY")
   {g_liqLibraryOpen=true;LiqLibraryScan();LiqLibraryDraw();return true;}
   if(!g_liqLibraryOpen)return false;
   if(id==CHARTEVENT_CHART_CHANGE){LiqLibraryDraw();return true;}
   // Modal capture also consumes clicks intended for underlying dashboard controls.
   if(id!=CHARTEVENT_OBJECT_CLICK)return true;
   string action=StringSubstr(name,StringLen(LiqLibraryObject("")));
   if(StringFind(name,LiqLibraryObject(""))!=0)return true;
   g_liqLibraryQuery=ObjectGetString(0,LiqLibraryObject("QUERY"),OBJPROP_TEXT);
   g_liqLibraryName=ObjectGetString(0,LiqLibraryObject("NAME"),OBJPROP_TEXT);
   if(action=="CLOSE"){g_liqLibraryOpen=false;DeleteByPrefix(LiqLibraryObject(""));DrawDashboard();ChartRedraw(0);return true;}
   if(action=="SEARCH"){g_liqLibraryPage=0;LiqLibraryScan();}
   else if(action=="FAV"){g_liqLibraryFavorites=!g_liqLibraryFavorites;g_liqLibraryPage=0;LiqLibraryScan();}
   else if(action=="PREV"){g_liqLibraryPage=MathMax(0,g_liqLibraryPage-1);}
   else if(action=="NEXT"){g_liqLibraryPage++;LiqLibraryScan();}
   else if(action=="SAVE")
   {g_liqLibraryStatus=LiqLibrarySave(g_liqLibraryName)?"Saved (same name updates existing strategy)":"Save failed: name or file lock";LiqLibraryScan();}
   else if(action=="APPLY_R")
   {
      string text=ObjectGetString(0,LiqLibraryObject("RR"),OBJPROP_TEXT);StringReplace(text,",",".");
      double r=StringToDouble(text);int step=(int)MathRound(r/0.05);
      if(!MathIsValidNumber(r)||step<1||step>100||MathAbs(r-step*0.05)>1e-8)g_liqLibraryStatus="R must be 0.05-5.00 in steps of 0.05";
      else if(LiqLibraryCanApply())
      {g_target=(ERL_RR_MODE)(100+step);g_targetModel=ERL_TARGET_FIXED_R;SanitizeHalfMode();RefreshAfterConfigChange(false);g_liqLibraryStatus="Applied FIX "+DoubleToString(r,2)+"R";}
   }
   else if(StringFind(action,"PICK")==0||StringFind(action,"STAR")==0)
   {
      int index=g_liqLibraryPage*6+(int)StringToInteger(StringSubstr(action,4));
      if(index>=0&&index<ArraySize(g_liqLibraryFiles))
      {
         string path=g_liqLibraryFiles[index];
         if(StringFind(action,"PICK")==0)LiqLibraryApply(path);
         else if(FileIsExist(path+".fav",FILE_COMMON))FileDelete(path+".fav",FILE_COMMON);
         else LiqLibraryAtomicWrite(path+".fav","1");
         LiqLibraryScan();
      }
   }
   else return true;
   LiqLibraryDraw();return true;
}
#endif
