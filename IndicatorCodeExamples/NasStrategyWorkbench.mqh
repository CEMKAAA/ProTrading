#ifndef NAS_STRATEGY_WORKBENCH_MQH
#define NAS_STRATEGY_WORKBENCH_MQH
#include "NasStrategyMLCore.mqh"
#include "NasStrategyModelSlot.mqh"
#include "NasStrategyInputProfile.mqh"

input group "NAS Strategy Library"
input bool InpNasLibraryAllowLive = false; // Research defaults: no orders or bridge publication
input bool InpNasLibraryConfirmPngDefaults = false; // Hidden PNG inputs cannot be recovered

struct NasLibraryPreset
{
   string id,name,symbol,profile,settings;
   int tf;
   bool user,favorite;
};
NasLibraryPreset g_nasLibrary[];
int g_nasLibrarySelected=-1,g_nasLibraryPage=0;
int g_nasLibraryVisible[];
bool g_nasLibraryOpen=false,g_nasLibraryFavorites=false;
string g_nasLibrarySearch="",g_nasLibrarySymbol="",g_nasLibraryR="";
string g_nasLibraryStatus="Research mode. PNG hidden inputs require confirmation.";
string g_nasLibraryAppliedConfig="";
string NAS_LIB_PREFIX="NAS_WORKBENCH_";
bool g_nasLibraryExport=false,g_nasLibraryMlEnabled=false;
int g_nasLibraryModelMode=0;
NasMlNetwork g_nasLibraryNetwork;
NasSlotModel g_nasLibrarySlot;

string NasLibrarySymbol(string symbol)
{
   StringToUpper(symbol);
   string roots[]={"BTCUSD","USDJPY","JP225","JPN225","US500","SP500","USTEC","US100","NAS100"};
   for(int i=0;i<ArraySize(roots);i++)
      if(StringFind(symbol,roots[i])==0)
      {
         if(i==3)return "JP225";
         if(i==5)return "US500";
         if(i>=7)return "USTEC";
         return roots[i];
      }
   return symbol;
}

bool NasLibrarySafeToken(const string value,const bool name=false)
{
   if(StringLen(value)<1||StringLen(value)>(name?80:96))return false;
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(c<32||c=='|'||c=='\\'||c=='/'||c==':'||c=='*'||c=='?'||c=='"'||c=='<'||c=='>')return false;
      if(!name&&!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'))return false;
   }
   return true;
}

bool NasLibraryRead(const string path,string &value)
{
   value="";int h=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)return false;
   long size=(long)FileSize(h);
   if(size<=0||size>134217728){FileClose(h);return false;}
   uchar bytes[];ArrayResize(bytes,(int)size);
   uint n=FileReadArray(h,bytes,0,(int)size);FileClose(h);
   if(n!=(uint)size)return false;
   value=CharArrayToString(bytes,0,(int)size,CP_UTF8);return true;
}

bool NasLibraryWrite(const string path,const string value)
{
   string tmp=path+"."+(string)ChartID()+".tmp";
   int h=FileOpen(tmp,FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h==INVALID_HANDLE)return false;
   uchar bytes[];int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   uint written=n>=0?FileWriteArray(h,bytes,0,n):0;
   FileFlush(h);FileClose(h);
   if(n<0||written!=(uint)n)return false;
   return FileMove(tmp,FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
}

string NasLibrarySettings()
{
   int mask=0;for(int i=0;i<6;i++)if(g_macroRegimeAllowed[i])mask|=1<<i;
   return g_tradeStartTimeRuntime+"|"+g_tradeEndTimeRuntime+"|"+DoubleToString(g_pipSlDistanceRuntime,12)
      +"|"+DoubleToString(g_selectedTargetRRuntime,12)+"|"+DoubleToString(g_finalRiskScalePctRuntime,12)
      +"|"+DoubleToString(g_swingBufferAtrRuntime,12)+"|"+(string)(int)g_windowReverseExitRuntime
      +"|"+(string)(int)g_volumeFilterRuntime+"|"+DoubleToString(g_volumeMultiplierRuntime,12)
      +"|"+g_timedExitTimeRuntime+"|"+(string)(int)g_historyUseAcceptedFilterRuntime
      +"|"+(string)(int)g_nasRegimeFilterRuntime+"|"+(string)mask+"|"+(string)(int)g_riskGeometryModeRuntime
      +"|"+(string)g_hcBeTpLegRuntime+"|"+(string)(int)g_invertTradeModeRuntime
      +"|"+DoubleToString(g_invertTargetRRuntime,12)+"|"+(string)(int)g_tpManagementModeRuntime
      +"|"+(string)g_invertReferenceTpLegRuntime+"|"+(string)g_invertHcBeProgressPctRuntime
      +"|"+DoubleToString(g_spreadMaxPointsRuntime,12);
}

string NasLibraryConfig()
{
   string id=g_nasLibrarySelected>=0?g_nasLibrary[g_nasLibrarySelected].id:"unsaved";
   return NasMlSha256("nas-library-v1|"+id+"|"+_Symbol+"|"+(string)PeriodSeconds(_Period)
      +"|"+AccountInfoString(ACCOUNT_SERVER)+"|"+NasLibraryInputProfile()+"|"+NasLibrarySettings());
}

bool NasLibraryTime(const string text,const bool blank=false)
{
   if(text=="")return blank;
   if(StringLen(text)!=5||StringSubstr(text,2,1)!=":")return false;
   for(int i=0;i<5;i++)if(i!=2&&(StringGetCharacter(text,i)<'0'||StringGetCharacter(text,i)>'9'))return false;
   int h=(int)StringToInteger(StringSubstr(text,0,2)),m=(int)StringToInteger(StringSubstr(text,3,2));
   return m<60&&(h<24||(h==24&&m==0));
}

bool NasLibraryParseSettings(const string value,string &a[],double &n[])
{
   if(StringSplit(value,'|',a)!=21)return false;
   if(!NasLibraryTime(a[0])||!NasLibraryTime(a[1])||!NasLibraryTime(a[9],true))return false;
   ArrayResize(n,21);ArrayInitialize(n,0);
   for(int i=2;i<21;i++)if(i!=9&&!NasMlNumber(a[i],n[i]))return false;
   if(n[2]<=0||n[3]<.05||n[3]>3||n[4]<10||n[4]>500||n[5]<0||n[5]>1
      ||n[8]<=0||n[8]>1000||n[12]<0||n[12]>63||n[13]<0||n[13]>3
      ||n[14]<0||n[14]>6||n[16]<0||n[16]>3||n[17]<0||n[17]>1
      ||n[18]<0||n[18]>6||n[20]<0)return false;
   int flags[]={6,7,10,11,15};
   for(int i=0;i<ArraySize(flags);i++)if(n[flags[i]]!=0&&n[flags[i]]!=1)return false;
   int ints[]={12,13,14,17,18,19};
   for(int i=0;i<ArraySize(ints);i++)if(n[ints[i]]!=MathFloor(n[ints[i]]))return false;
   if(n[19]!=0&&n[19]!=25&&n[19]!=50&&n[19]!=75)return false;
   return true;
}

void NasLibraryAddBuiltin(string id,string name,string symbol,int tf,string start,string end,
   double pip,double rr,double scale,bool reverse,bool volume,double multiplier)
{
   int i=ArraySize(g_nasLibrary);ArrayResize(g_nasLibrary,i+1);
   g_nasLibrary[i].id=id;g_nasLibrary[i].name=name;g_nasLibrary[i].symbol=symbol;g_nasLibrary[i].tf=tf;
   g_nasLibrary[i].profile="";g_nasLibrary[i].user=false;g_nasLibrary[i].favorite=false;
   g_nasLibrary[i].settings=start+"|"+end+"|"+DoubleToString(pip,12)+"|"+DoubleToString(rr,12)
      +"|"+DoubleToString(scale,12)+"|0.2|"+(string)(int)reverse+"|"+(string)(int)volume
      +"|"+DoubleToString(multiplier,12)+"||0|0|63|2|0|0|0|1|0|0|0";
}
#include "NasStrategyPresets.mqh"

bool NasLibraryBusy()
{
   if(g_historyAuditRunning||g_nasLibraryExport||g_pendingAccountRiskLockRetry
      ||g_nasRegimeCloseRetry.active||g_nasTimedExitClose.active||ArraySize(g_nasProBridgePending)>0
      ||g_nasBridgeEnabledRuntime||ManagedPositionDirection()!=0||g_timedExitBridgePlanDirection!=0)
   {g_nasLibraryStatus="Cannot switch: audit/export, open position or bridge lifecycle. PUB must be OFF.";return true;}
   return false;
}

bool NasLibraryApply(const int index)
{
   if(index<0||index>=ArraySize(g_nasLibrary)||NasLibraryBusy())return false;
   NasLibraryPreset p=g_nasLibrary[index];string a[];double n[];
   if(p.symbol!=NasLibrarySymbol(_Symbol)||p.tf*60!=PeriodSeconds(_Period))
   {g_nasLibraryStatus="Wrong chart: strategy needs "+p.symbol+" M"+(string)p.tf;return false;}
   if(p.user&&p.profile!=NasLibraryInputProfile())
   {g_nasLibraryStatus="Immutable input profile differs. Restore the saved EA inputs first.";return false;}
   if(!p.user&&!InpNasLibraryConfirmPngDefaults)
   {g_nasLibraryStatus="Confirm PNG hidden-input defaults in EA Inputs before applying imported strategies.";return false;}
   if(!p.user && (InpNasSensitivity!=4||InpNasRsiLength!=14||InpNasAtrRisk!=1||InpNasAtrLen!=14
      ||InpSignalBarMode!=NAS_SIGNAL_BAR_CLOSED||!InpUseTradingTimeWindow||!InpCloseExistingOnNewSignal
      ||InpExecutionMode!=NAS_EXEC_PARTIAL_NO_BE))
   {g_nasLibraryStatus="PNG baseline mismatch: restore default NAS core, CLOSED, window and single-target partial-no-BE inputs.";return false;}
   if(!NasLibraryParseSettings(p.settings,a,n))
   {g_nasLibraryStatus="Invalid settings: nothing applied.";return false;}
   // Validation is complete before committing any runtime field.
   g_tradeStartTimeRuntime=a[0];g_tradeEndTimeRuntime=a[1];g_pipSlDistanceRuntime=n[2];
   g_selectedTargetRRuntime=n[3];g_selectedTpLegRuntime=ClampTpLeg((int)MathCeil(n[3]*2));
   g_finalRiskScalePctRuntime=n[4];g_swingBufferAtrRuntime=n[5];g_windowReverseExitRuntime=(bool)n[6];
   g_volumeFilterRuntime=(bool)n[7];g_volumeMultiplierRuntime=n[8];g_timedExitTimeRuntime=a[9];
   g_historyUseAcceptedFilterRuntime=(bool)n[10];g_nasRegimeFilterRuntime=(bool)n[11];
   for(int i=0;i<6;i++)g_macroRegimeAllowed[i]=((int)n[12]&(1<<i))!=0;
   g_riskGeometryModeRuntime=(NAS_RISK_GEOMETRY_MODE)(int)n[13];g_hcBeTpLegRuntime=(int)n[14];
   g_invertTradeModeRuntime=(bool)n[15];g_invertTargetRRuntime=n[16];
   g_tpManagementModeRuntime=(NAS_TP_MANAGEMENT_MODE)(int)n[17];g_invertReferenceTpLegRuntime=(int)n[18];
   g_invertHcBeProgressPctRuntime=(int)n[19];g_spreadMaxPointsRuntime=n[20];
   g_nasLibrarySelected=index;g_nasLibraryMlEnabled=false;g_nasLibraryNetwork.ready=false;
   g_nasResearchJob="";
   g_nasLibraryAppliedConfig=NasLibraryConfig();ArrayFree(g_historySimCache);
   ClearAccountRiskLockRetry();g_lastSignalTime=iTime(_Symbol,_Period,1);
   MarkDirectionProcessedOnBar(g_lastSignalTime,1);MarkDirectionProcessedOnBar(g_lastSignalTime,-1);
   g_lastExecutedDirection=0;g_nasLibraryStatus="Applied "+p.name+"; ML OFF; account/risk/PUB/ONLY/NAT unchanged.";
   // Recreate edit objects so stale text/focus cannot overwrite applied values.
   ClearDashboardObjects();g_dashboardForceNextUpdate=true;RequestHistoryRefresh();UpdateDashboard();
   return true;
}

bool NasLibrarySave(const string name)
{
   if(!NasLibrarySafeToken(name,true)||NasLibraryBusy())return false;
   string profile=NasLibraryInputProfile(),settings=NasLibrarySettings(),a[];double n[];
   if(!NasLibraryParseSettings(settings,a,n)){g_nasLibraryStatus="Unsupported runtime settings; not saved.";return false;}
   string id="user_"+StringSubstr(NasMlSha256(name+"|"+_Symbol+"|"+(string)_Period+"|"+profile+"|"+settings),0,24);
   string body="NAS_USER1\n"+id+"\n"+name+"\n"+NasLibrarySymbol(_Symbol)+"\n"
      +(string)(PeriodSeconds(_Period)/60)+"\n"+profile+"\n"+settings+"\n";
   FolderCreate("NasML",FILE_COMMON);FolderCreate("NasML\\Strategies",FILE_COMMON);
   if(!NasLibraryWrite("NasML\\Strategies\\"+id+".strategy",body+NasMlSha256(body)+"\n"))
   {g_nasLibraryStatus="Strategy write failed; previous files preserved.";return false;}
   NasLibraryReload();
   for(int i=0;i<ArraySize(g_nasLibrary);i++)if(g_nasLibrary[i].id==id)
   {g_nasLibrarySelected=i;g_nasLibraryAppliedConfig=NasLibraryConfig();break;}
   g_nasLibraryStatus="Saved "+name+". Metrics are N/A until this exact configuration is audited.";
   return true;
}

void NasLibraryReload()
{
   string selected=g_nasLibrarySelected>=0?g_nasLibrary[g_nasLibrarySelected].id:"";
   ArrayFree(g_nasLibrary);g_nasLibrarySelected=-1;NasLibraryLoadBuiltins();
   string file;long h=FileFindFirst("NasML\\Strategies\\*.strategy",file,FILE_COMMON);
   if(h!=INVALID_HANDLE)
   {
      do
      {
         string text,a[];if(!NasLibraryRead("NasML\\Strategies\\"+file,text))continue;
         if(StringSplit(text,'\n',a)!=9||a[0]!="NAS_USER1"||a[8]!=""||!NasLibrarySafeToken(a[1])||!NasLibrarySafeToken(a[2],true))continue;
         string body="";for(int j=0;j<7;j++)body+=a[j]+"\n";
         if(NasMlSha256(body)!=a[7]||StringLen(a[5])!=64)continue;
         double tf=0;if(!NasMlNumber(a[4],tf)||tf<=0||tf!=MathFloor(tf))continue;
         string fields[];double values[];if(!NasLibraryParseSettings(a[6],fields,values))continue;
         int i=ArraySize(g_nasLibrary);ArrayResize(g_nasLibrary,i+1);
         g_nasLibrary[i].id=a[1];g_nasLibrary[i].name=a[2];g_nasLibrary[i].symbol=a[3];g_nasLibrary[i].tf=(int)tf;
         g_nasLibrary[i].profile=a[5];g_nasLibrary[i].settings=a[6];g_nasLibrary[i].user=true;
      }while(FileFindNext(h,file));FileFindClose(h);
   }
   for(int i=0;i<ArraySize(g_nasLibrary);i++)
   {
      string value;g_nasLibrary[i].favorite=NasLibraryRead("NasML\\Favorites\\"+g_nasLibrary[i].id+".txt",value)&&value=="1";
      if(g_nasLibrary[i].id==selected)g_nasLibrarySelected=i;
   }
}

void NasLibraryInit()
{
   FolderCreate("NasML",FILE_COMMON);FolderCreate("NasML\\Favorites",FILE_COMMON);
   NasLibraryReload();g_nasLibraryNetwork.ready=false;
   if(!InpNasLibraryAllowLive)g_eaEnabledRuntime=false;
}
#include "NasStrategyLeaderboard.mqh"

void NasLibraryUi(string key,int type,int x,int y,int w,int h,string text,color bg=clrNONE)
{
   string name=NAS_LIB_PREFIX+key;
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,(ENUM_OBJECT)type,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,name,OBJPROP_XSIZE,w);ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,key=="BG"?100:110);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   if(bg!=clrNONE)ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   if(type==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
   if(type==OBJ_EDIT)ObjectSetInteger(0,name,OBJPROP_READONLY,false);
}

void NasLibraryDraw()
{
   if(!InpShowDashboard)return;
   if(!g_nasLibraryOpen)
   {
      NasLibraryUi("OPEN",OBJ_BUTTON,450,78,178,22,"STRATEGIES / ML",C'28,80,112');return;
   }
   NasLibraryUi("BG",OBJ_RECTANGLE_LABEL,22,48,1020,430,"",C'20,29,40');
   NasLibraryUi("TITLE",OBJ_LABEL,36,60,0,0,"NAS STRATEGY LIBRARY | research data is not a profit guarantee");
   NasLibraryUi("CLOSE",OBJ_BUTTON,995,55,30,24,"X",C'105,44,48');
   NasLibraryUi("SEARCH",OBJ_EDIT,36,88,270,24,g_nasLibrarySearch,C'32,42,56');
   NasLibraryUi("SYMBOL",OBJ_EDIT,316,88,110,24,g_nasLibrarySymbol,C'32,42,56');
   NasLibraryUi("R",OBJ_EDIT,436,88,80,24,g_nasLibraryR,C'32,42,56');
   ObjectSetString(0,NAS_LIB_PREFIX+"SYMBOL",OBJPROP_TOOLTIP,"Symbol filter: BTCUSD / USDJPY / JP225 / US500 / USTEC; blank = all");
   ObjectSetString(0,NAS_LIB_PREFIX+"R",OBJPROP_TOOLTIP,"Exact R filter, e.g. 0.35; blank = all");
   NasLibraryUi("FILTER",OBJ_BUTTON,526,88,84,24,"SEARCH",C'28,80,112');
   NasLibraryUi("FAVONLY",OBJ_BUTTON,620,88,154,24,g_nasLibraryFavorites?"FAVORITES ONLY":"ALL STRATEGIES",C'28,80,112');
   NasLibraryUi("PREV",OBJ_BUTTON,784,88,40,24,"<",C'28,80,112');
   NasLibraryUi("NEXT",OBJ_BUTTON,834,88,40,24,">",C'28,80,112');
   NasLibraryUi("LEADERBOARD",OBJ_BUTTON,884,88,136,24,g_nasLeaderboard?"RANK ON":"LEADERBOARD",C'28,80,112');
   ArrayFree(g_nasLibraryVisible);string search=g_nasLibrarySearch;StringToLower(search);
   double rr=0;bool filterR=g_nasLibraryR!="";bool validR=!filterR||NasMlNumber(g_nasLibraryR,rr);
   for(int i=0;i<ArraySize(g_nasLibrary);i++)
   {
      NasLibraryPreset p=g_nasLibrary[i];string name=p.name;StringToLower(name);
      string a[];StringSplit(p.settings,'|',a);
      if(!validR||(search!=""&&StringFind(name,search)<0)||(g_nasLibrarySymbol!=""&&NasLibrarySymbol(g_nasLibrarySymbol)!=p.symbol)
         ||(filterR&&MathAbs(StringToDouble(a[3])-rr)>1e-8)||(g_nasLibraryFavorites&&!p.favorite))continue;
      int j=ArraySize(g_nasLibraryVisible);ArrayResize(g_nasLibraryVisible,j+1);g_nasLibraryVisible[j]=i;
   }
   NasLeaderboardSort();
   int pages=MathMax(1,(ArraySize(g_nasLibraryVisible)+5)/6);g_nasLibraryPage=MathMax(0,MathMin(pages-1,g_nasLibraryPage));
   for(int row=0;row<6;row++)
   {
      string key="ROW"+(string)row,star="FAV"+(string)row;
      int item=g_nasLibraryPage*6+row;
      if(item>=ArraySize(g_nasLibraryVisible)){ObjectDelete(0,NAS_LIB_PREFIX+key);ObjectDelete(0,NAS_LIB_PREFIX+star);continue;}
      NasLibraryPreset p=g_nasLibrary[g_nasLibraryVisible[item]];string a[];StringSplit(p.settings,'|',a);
      string label=p.symbol+" M"+(string)p.tf+" "+DoubleToString(StringToDouble(a[3]),2)+"R | "+p.name;
      if(g_nasLeaderboard)label+=NasLeaderboardText(g_nasLibraryVisible[item]);
      NasLibraryUi(key,OBJ_BUTTON,36,124+row*29,930,25,label,C'34,55,73');
      NasLibraryUi(star,OBJ_BUTTON,975,124+row*29,45,25,p.favorite?"YES":"FAV",p.favorite?C'149,98,22':C'45,52,66');
   }
   NasLibraryUi("NAME",OBJ_EDIT,36,307,330,24,"",C'32,42,56');
   NasLibraryUi("SAVE",OBJ_BUTTON,376,307,164,24,"SAVE CURRENT AS",C'28,80,112');
   NasLibraryUi("LBMODE",OBJ_BUTTON,550,307,188,24,"SCORE: "+NasLeaderboardModeName(),C'28,80,112');
   string regime=g_nasLeaderboardRegime<0?"ALL":(g_nasLeaderboardRegime==6?"UNKNOWN":LiqMacroRegimeShortName(g_nasLeaderboardRegime));
   NasLibraryUi("LBREGIME",OBJ_BUTTON,748,307,270,24,"LEADERBOARD REGIME: "+regime,C'28,80,112');
   NasLibraryUi("STATUS",OBJ_LABEL,36,348,0,0,StringSubstr(g_nasLibraryStatus,0,122));
   ObjectSetString(0,NAS_LIB_PREFIX+"STATUS",OBJPROP_TOOLTIP,g_nasLibraryStatus);
   NasLibraryDrawResearch();
   ChartRedraw(0);
}

bool NasLibraryEvent(const int id,const string object)
{
   if(id!=CHARTEVENT_OBJECT_CLICK&&id!=CHARTEVENT_OBJECT_ENDEDIT)return false;
   if(object==NAS_LIB_PREFIX+"OPEN")
   {g_nasLibraryOpen=true;NasLibraryDraw();return true;}
   if(!g_nasLibraryOpen)
   {
      if(g_nasLibraryExport&&StringFind(object,PREFIX)==0)
      {g_nasLibraryStatus="Export running: cancel CSV before changing EA settings.";return true;}
      return false;
   }
   // A modal consumes all chart-object clicks, including underlying EA buttons.
   if(StringFind(object,NAS_LIB_PREFIX)!=0)return true;
   if(id==CHARTEVENT_OBJECT_ENDEDIT)return true;
   string key=StringSubstr(object,StringLen(NAS_LIB_PREFIX));
   if(key=="CLOSE")
   {g_nasLibraryOpen=false;ObjectsDeleteAll(0,NAS_LIB_PREFIX);NasLibraryDraw();return true;}
   g_nasLibrarySearch=ObjectGetString(0,NAS_LIB_PREFIX+"SEARCH",OBJPROP_TEXT);
   g_nasLibrarySymbol=ObjectGetString(0,NAS_LIB_PREFIX+"SYMBOL",OBJPROP_TEXT);
   g_nasLibraryR=ObjectGetString(0,NAS_LIB_PREFIX+"R",OBJPROP_TEXT);
   string name=ObjectGetString(0,NAS_LIB_PREFIX+"NAME",OBJPROP_TEXT);
   if(key=="PREV")g_nasLibraryPage--;
   else if(key=="NEXT")g_nasLibraryPage++;
   else if(key=="FILTER")g_nasLibraryPage=0;
   else if(key=="LEADERBOARD")
   {g_nasLeaderboard=!g_nasLeaderboard;NasLeaderboardLoad();g_nasLibraryStatus="Rank = Wilson WR lower bound / (1 + closed DD). PARTIAL = excluded labels; ML masks are retrospective, not OOS replay.";}
   else if(key=="LBMODE"){g_nasLeaderboardMode=(g_nasLeaderboardMode+1)%3;g_nasLibraryPage=0;NasLeaderboardLoad();}
   else if(key=="LBREGIME"){g_nasLeaderboardRegime++;if(g_nasLeaderboardRegime>6)g_nasLeaderboardRegime=-1;g_nasLibraryPage=0;}
   else if(key=="FAVONLY"){g_nasLibraryFavorites=!g_nasLibraryFavorites;g_nasLibraryPage=0;}
   else if(key=="SAVE")NasLibrarySave(name);
   else if(StringFind(key,"ROW")==0||StringFind(key,"FAV")==0)
   {
      int row=(int)StringToInteger(StringSubstr(key,3)),at=g_nasLibraryPage*6+row;
      if(row>=0&&row<6&&at<ArraySize(g_nasLibraryVisible))
      {
         int i=g_nasLibraryVisible[at];
         if(StringFind(key,"ROW")==0)NasLibraryApply(i);
         else
         {
            bool next=!g_nasLibrary[i].favorite;
            if(NasLibraryWrite("NasML\\Favorites\\"+g_nasLibrary[i].id+".txt",next?"1":"0"))g_nasLibrary[i].favorite=next;
            else g_nasLibraryStatus="Favorite write failed.";
         }
      }
   }
   else NasLibraryResearchEvent(key);
   NasLibraryDraw();ObjectSetString(0,NAS_LIB_PREFIX+"NAME",OBJPROP_TEXT,name);return true;
}
#include "NasStrategyResearch.mqh"
#endif
