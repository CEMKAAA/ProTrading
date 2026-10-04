#ifndef MA_INDEPENDENT_ENTRIES_MQH
#define MA_INDEPENDENT_ENTRIES_MQH

bool g_maIndependent=false;
bool g_maRestoringPreset=false,g_maPresetModeRestored=false;
int g_maMaxConsecutive=1;
int g_maSeriesDir=0,g_maSeriesCount=0;
datetime g_maSeriesBar=0;
bool g_maSeriesUncertain=false;
int g_maSeriesLock=INVALID_HANDLE;
string g_maSeriesFile="",g_maSeriesIdentity="";
long g_maRecoveredMagic=0;
int g_maRecoveredLock=INVALID_HANDLE;
ulong g_maRecoveryRetryUntil=0,g_maRecoveryRetryAt=0;
int g_maHistSeriesDir=0,g_maHistSeriesCount=0;

bool MaRecoveredMagicOwned(long magic){return magic>0&&magic==g_maRecoveredMagic;}
string MaIndependentStateIdentity(long magic)
{return AccountInfoString(ACCOUNT_SERVER)+"/"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"/"+_Symbol+"/"+(string)magic;}
string MaIndependentStateFile(long magic)
{
   string identity=MaIndependentStateIdentity(magic);ulong hash=1469598103934665603;
   for(int i=0;i<StringLen(identity);i++)hash=(hash^(ulong)StringGetCharacter(identity,i))*1099511628211;
   return "EntryLabIndependent_"+(string)hash+".state";
}
bool MaRecoveryFamilyMagic(long magic)
{
   if(!RiskEnabled()&&!InpUseChartScopedMagic)return false;
   return magic>0&&magic!=RuntimeMagic()&&magic/1000000==RuntimeMagic()/1000000;
}
bool MaRecoveryChartActive(long magic)
{
   for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart))
      if(chart!=ChartID()&&chart%1000000==magic%1000000&&ChartSymbol(chart)==_Symbol
         &&StringFind(ChartGetString(chart,CHART_EXPERT_NAME),"EntryEngineLab")>=0)return true;
   return false;
}
bool MaRecoveryStateValid(long magic)
{
   int h=FileOpen(MaIndependentStateFile(magic),FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE)return false;
   string line=FileReadString(h);FileClose(h);string fields[];
   if(StringSplit(line,'|',fields)!=6||fields[0]!="2"||fields[1]!=MaIndependentStateIdentity(magic)||fields[5]!="0")return false;
   int dir=(int)StringToInteger(fields[2]),count=(int)StringToInteger(fields[3]);
   long bar=StringToInteger(fields[4]);
   return MathAbs(dir)<=1&&count>=0&&count<=1000&&bar>=0
      &&(count==0||(dir!=0&&bar>0))&&fields[2]==(string)dir&&fields[3]==(string)count&&fields[4]==(string)bar;
}
string MaRecoveryKey()
{return "ELREC."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID()+"."+(string)InpMagic;}
bool MaRecoveryClaim(long magic)
{
   if(!MaRecoveryFamilyMagic(magic)||MaRecoveryChartActive(magic)||!MaRecoveryStateValid(magic))return false;
   // Reuse the original owner's exclusive state lock, never claim an active instance.
   int lock=FileOpen(MaIndependentStateFile(magic)+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(lock==INVALID_HANDLE)return false;
   if(!MaRecoveryStateValid(magic)){FileClose(lock);return false;}
   g_maRecoveredMagic=magic;g_maRecoveredLock=lock;
   return true;
}
void MaRecoveryRelease()
{
   if(g_maRecoveredLock!=INVALID_HANDLE)FileClose(g_maRecoveredLock);
   g_maRecoveredLock=INVALID_HANDLE;g_maRecoveredMagic=0;
}
bool MaRecoverIndependentOwner()
{
   if(IsTesterMode()||!g_maIndependent||g_maRecoveredMagic>0)return true;
   string key=MaRecoveryKey();
   if(GlobalVariableCheck(key+".HI")&&GlobalVariableCheck(key+".LO"))
   {
      double hi=GlobalVariableGet(key+".HI"),lo=GlobalVariableGet(key+".LO");
      if(hi>=0&&hi<=4294967295.0&&lo>=0&&lo<=4294967295.0&&hi==MathFloor(hi)&&lo==MathFloor(lo))
      {
         long saved=(long)(((ulong)hi<<32)|(ulong)lo);
         if(MaRecoveryClaim(saved))return true;
      }
   }
   long candidate=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0||PositionGetString(POSITION_SYMBOL)!=_Symbol
         ||StringFind(PositionGetString(POSITION_COMMENT),"MAI|")!=0)continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if(!MaRecoveryFamilyMagic(magic)||MaRecoveryChartActive(magic)||!MaRecoveryStateValid(magic))continue;
      int lock=FileOpen(MaIndependentStateFile(magic)+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(lock==INVALID_HANDLE)continue;FileClose(lock);
      if(candidate!=0&&candidate!=magic)
      {Print("ENTRYLAB recovery ambiguous: multiple orphan instance owners; no ownership changed");return false;}
      candidate=magic;
   }
   if(candidate==0)return true;
   if(!MaRecoveryClaim(candidate))return false;
   // Split the 64-bit magic: storing it directly as a terminal double loses bits.
   if(GlobalVariableSet(key+".HI",(double)((ulong)candidate>>32))==0
      ||GlobalVariableSet(key+".LO",(double)((ulong)candidate&0xFFFFFFFF))==0)
   {MaRecoveryRelease();return false;}
   GlobalVariablesFlush();
   Print("ENTRYLAB recovered independent owner old_magic=",candidate," current_magic=",RuntimeMagic());
   return true;
}
void MaRecoveryRetry()
{
   ulong now=GetTickCount64();
   if(IsTesterMode()||!g_maIndependent||g_maRecoveredMagic>0||now>g_maRecoveryRetryUntil
      ||now<g_maRecoveryRetryAt||!TerminalInfoInteger(TERMINAL_CONNECTED))return;
   g_maRecoveryRetryAt=now+2000;
   if(!MaRecoverIndependentOwner()){g_lastExecStatus="RECOVERY: owner ambiguous or locked";return;}
   if(g_maRecoveredMagic>0)
   {OrbProRestoreRuntimeState();LabNativeVisualRestore();DrawOrbLiveTradeLevels();MaRenderOpenCounter(true);}
}

datetime g_maHistOpenUntil[1000];
int g_maHistOpenCount=0;
datetime g_maHistLastClosed=0;
void MaHistoricalCapacityReset(){g_maHistOpenCount=0;g_maHistLastClosed=0;}
bool MaOpenCapacityAllows(int opened,int maximum){return maximum>=1&&maximum<=1000&&opened>=0&&opened<maximum;}
int MaNativeOpenCount(int &buys,int &sells)
{
   buys=0;sells=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0||!IsOwnPosition())continue;
      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)buys++;else sells++;
   }
   return buys+sells;
}
int MaNativeOpenCount(){int buys=0,sells=0;return MaNativeOpenCount(buys,sells);}
// A bounded exit-time heap releases real closed trades; direction changes never reset capacity.
void MaHistoricalCapacityRelease(datetime at)
{
   while(g_maHistOpenCount>0&&g_maHistOpenUntil[0]<=at)
   {
      if(g_maHistOpenUntil[0]>g_maHistLastClosed)g_maHistLastClosed=g_maHistOpenUntil[0];
      g_maHistOpenCount--;if(g_maHistOpenCount==0)break;
      g_maHistOpenUntil[0]=g_maHistOpenUntil[g_maHistOpenCount];int i=0;
      while(2*i+1<g_maHistOpenCount)
      {
         int child=2*i+1;
         if(child+1<g_maHistOpenCount&&g_maHistOpenUntil[child+1]<g_maHistOpenUntil[child])child++;
         if(g_maHistOpenUntil[i]<=g_maHistOpenUntil[child])break;
         datetime value=g_maHistOpenUntil[i];g_maHistOpenUntil[i]=g_maHistOpenUntil[child];g_maHistOpenUntil[child]=value;i=child;
      }
   }
}
bool MaHistoricalCapacityAllows(datetime at)
{MaHistoricalCapacityRelease(at);return MaOpenCapacityAllows(g_maHistOpenCount,g_maMaxConsecutive);}
void MaHistoricalCapacityOccupy(datetime until)
{
   if(g_maHistOpenCount>=1000)return;
   int i=g_maHistOpenCount++;g_maHistOpenUntil[i]=until;
   while(i>0)
   {
      int parent=(i-1)/2;if(g_maHistOpenUntil[parent]<=g_maHistOpenUntil[i])break;
      datetime value=g_maHistOpenUntil[parent];g_maHistOpenUntil[parent]=g_maHistOpenUntil[i];g_maHistOpenUntil[i]=value;i=parent;
   }
}
string MaOpenCounterText(int opened){return "OPEN "+(string)opened+"/"+(string)(g_maIndependent?g_maMaxConsecutive:1);}
void MaRenderOpenCounter(bool force=false)
{
   if(IsTesterMode()||!InpShowDashboard)return;
   int buys=0,sells=0,opened=MaNativeOpenCount(buys,sells),limit=g_maIndependent?g_maMaxConsecutive:1;
   string text=MaOpenCounterText(opened),name=PREFIX+"DASH_MA_OPEN";
   string tip="Instance-owned native MT5 positions: BUY="+(string)buys+", SELL="+(string)sells
      +". MAX SERIES is TOTAL simultaneously open positions, not consecutive signals. Applied limit="+(string)limit+".";
   if(g_maRecoveredMagic>0)tip+=" Recovered previous chart magic="+(string)g_maRecoveredMagic+".";
   if(!force&&ObjectFind(0,name)>=0&&ObjectGetString(0,name,OBJPROP_TEXT)==text&&ObjectGetString(0,name,OBJPROP_TOOLTIP)==tip)return;
   CreateLabel("DASH_MA_OPEN",InpDashboardX+420,InpDashboardY+313,text,opened>=limit?clrTomato:C'80,255,180',8);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
}

bool MaSeriesAllows(int direction,int &seriesDirection,int &count,int maximum)
{
   if(direction!=1&&direction!=-1)return false;
   if(direction!=seriesDirection){seriesDirection=direction;count=0;}
   return maximum>=1&&count<maximum;
}

bool MaParseSeriesLimit(string value,int &result)
{
   StringTrimLeft(value);StringTrimRight(value);
   if(StringLen(value)<1||StringLen(value)>4)return false;
   for(int i=0;i<StringLen(value);i++)
      if(StringGetCharacter(value,i)<'0'||StringGetCharacter(value,i)>'9')return false;
   result=(int)StringToInteger(value);
   return result>=1&&result<=1000;
}

bool MaIndependentDefiniteRejection(uint code)
{
   return code==TRADE_RETCODE_REQUOTE||code==TRADE_RETCODE_REJECT
      ||code==TRADE_RETCODE_INVALID||code==TRADE_RETCODE_INVALID_VOLUME
      ||code==TRADE_RETCODE_INVALID_PRICE||code==TRADE_RETCODE_INVALID_STOPS
      ||code==TRADE_RETCODE_TRADE_DISABLED||code==TRADE_RETCODE_MARKET_CLOSED
      ||code==TRADE_RETCODE_NO_MONEY||code==TRADE_RETCODE_PRICE_CHANGED
      ||code==TRADE_RETCODE_PRICE_OFF||code==TRADE_RETCODE_INVALID_FILL
      ||code==TRADE_RETCODE_TOO_MANY_REQUESTS||code==TRADE_RETCODE_CLIENT_DISABLES_AT
      ||code==TRADE_RETCODE_SERVER_DISABLES_AT;
}

string MaIndependentSettingsKey()
{
   return "ENTRYLAB_MULTI."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID()
      +"."+(string)InpIndependentEntries+"."+(string)InpMaxConsecutiveEntries;
}

void MaIndependentRelease()
{
   if(g_maSeriesLock!=INVALID_HANDLE)FileClose(g_maSeriesLock);
   g_maSeriesLock=INVALID_HANDLE;
}

bool MaIndependentShape(string &reason)
{
   reason="";
   if(InpExecutionMode!=ORB_EXEC_SINGLE||g_rtExitMode!=ORB_EXIT_FIXED_TARGET
      ||g_rtTargetMode!=ORB_TARGET_R_LEG||RuntimeHalfBeLeg()>0||g_rtBEOnTp1
      ||g_rtTimeExit||g_rtFilteredWindowReverseExit
      ||g_rtPostTradeDispBlockExit||g_rtEntryMode!=ORB_ENTRY_BREAKOUT
      ||g_rtNasConfirmation||FixedReferenceRiskMode())
   {reason="INDEPENDENT: SINGLE + FIXED TP; HCBE/TIME/WINDOW EXIT/ENTRY WAIT/FIXED REF must be OFF";return false;}
   return true;
}

bool MaIndependentExecutionAllowed(string &reason)
{
   if(!MaIndependentShape(reason))return false;
   if(g_orbBridgeEnabled){reason="INDEPENDENT: PUB must be OFF (listeners not supported)";return false;}
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {reason="INDEPENDENT: hedging account required";return false;}
   return true;
}

bool MaIndependentWrite()
{
   string temp=g_maSeriesFile+".tmp";
   int h=FileOpen(temp,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE)return false;
   string record="2|"+g_maSeriesIdentity+"|"+(string)g_maSeriesDir+"|"
      +(string)g_maSeriesCount+"|"+(string)(long)g_maSeriesBar+"|"+(g_maSeriesUncertain?"1":"0");
   uchar bytes[];int size=StringToCharArray(record,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   bool ok=(int)FileWriteString(h,record)==size;
   FileFlush(h);FileClose(h);
   return ok&&FileMove(temp,0,g_maSeriesFile,FILE_REWRITE);
}

void MaIndependentIdentity()
{
   g_maSeriesIdentity=MaIndependentStateIdentity(RuntimeMagic());
   g_maSeriesFile=MaIndependentStateFile(RuntimeMagic());
}

bool MaIndependentOrdersPending()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0&&OrderGetString(ORDER_SYMBOL)==_Symbol
         &&MagicOwned(OrderGetInteger(ORDER_MAGIC)))return true;
   return false;
}

bool MaIndependentAcquire()
{
   if(g_maSeriesLock!=INVALID_HANDLE)return true;
   MaIndependentIdentity();
   // Exclusive lifetime lock prevents two charts from consuming the same series.
   g_maSeriesLock=FileOpen(g_maSeriesFile+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_maSeriesLock==INVALID_HANDLE)return false;
   g_maSeriesDir=0;g_maSeriesCount=0;g_maSeriesBar=0;g_maSeriesUncertain=false;
   if(FileIsExist(g_maSeriesFile))
   {
      int h=FileOpen(g_maSeriesFile,FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
      if(h==INVALID_HANDLE){MaIndependentRelease();return false;}
      string line=FileReadString(h);FileClose(h);string fields[];
      if(StringSplit(line,'|',fields)!=6||fields[0]!="2"||fields[1]!=g_maSeriesIdentity
         ||(fields[5]!="0"&&fields[5]!="1"))
      {MaIndependentRelease();return false;}
      g_maSeriesDir=(int)StringToInteger(fields[2]);g_maSeriesCount=(int)StringToInteger(fields[3]);
      g_maSeriesBar=(datetime)StringToInteger(fields[4]);
      g_maSeriesUncertain=fields[5]=="1";
      if(MathAbs(g_maSeriesDir)>1||g_maSeriesCount<0||g_maSeriesCount>1000||g_maSeriesBar<0
         ||(g_maSeriesCount>0&&(g_maSeriesDir==0||g_maSeriesBar==0))
         ||fields[2]!=(string)g_maSeriesDir||fields[3]!=(string)g_maSeriesCount||fields[4]!=(string)(long)g_maSeriesBar)
      {MaIndependentRelease();return false;}
      return true;
   }
   // Never silently invent a fresh allowance for existing independent exposure.
   bool currentExposure=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0&&PositionGetString(POSITION_SYMBOL)==_Symbol
         &&PositionGetInteger(POSITION_MAGIC)==RuntimeMagic()){currentExposure=true;break;}
   if(currentExposure||MaIndependentOrdersPending()){MaIndependentRelease();return false;}
   if(!MaIndependentWrite()){MaIndependentRelease();return false;}
   return true;
}

bool MaIndependentInit()
{
   g_maRecoveryRetryUntil=GetTickCount64()+120000;g_maRecoveryRetryAt=0;
   if(InpMaxConsecutiveEntries<1||InpMaxConsecutiveEntries>1000)return false;
   if(!g_maPresetModeRestored){g_maIndependent=InpIndependentEntries;g_maMaxConsecutive=InpMaxConsecutiveEntries;}
   string key=MaIndependentSettingsKey();
   if(!g_maPresetModeRestored&&GlobalVariableCheck(key))
   {
      int packed=(int)GlobalVariableGet(key);
      if(packed<1||packed>1001000||(packed%1000000)<1||(packed%1000000)>1000)return false;
      g_maIndependent=packed>=1000000;g_maMaxConsecutive=packed%1000000;
   }
   if(!MaRecoverIndependentOwner())return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      bool independent=StringFind(PositionGetString(POSITION_COMMENT),"MAI|")==0;
      if(independent!=g_maIndependent){Print("MA mode does not own the current lifecycle; close it before switching");return false;}
   }
   MaIndependentIdentity();
   if(!g_maIndependent)
   {
      if(FileIsExist(g_maSeriesFile))
      {
         if(!MaIndependentAcquire()||g_maSeriesUncertain||MaIndependentOrdersPending())return false;
         MaIndependentRelease();
      }
      return true;
   }
   string reason="";
   if(!MaIndependentExecutionAllowed(reason)){Print(reason);return false;}
   return MaIndependentAcquire();
}

bool MaIndependentApply(bool enabled,int maximum)
{
   if(maximum<1||maximum>1000)return false;
   bool hadNative=OwnPositionExists();long previousOwner=g_maRecoveredMagic;
   if(enabled)
   {
      string reason="";
      if(!MaIndependentExecutionAllowed(reason)){g_lastExecStatus=reason;return false;}
      bool prior=g_maIndependent;g_maIndependent=true;
      bool recovered=MaRecoverIndependentOwner();g_maIndependent=prior;
      if(!recovered){g_lastExecStatus="RECOVERY: owner ambiguous or locked";return false;}
   }
   bool adopting=enabled&&!hadNative&&g_maRecoveredMagic>0;
   if(enabled&&MaNativeOpenCount()>maximum)
   {g_lastExecStatus="MAX SERIES below current OPEN count; close exposure first";return false;}
   if(enabled!=g_maIndependent&&((OwnPositionExists()&&!adopting)||MaIndependentOrdersPending()
      ||g_maSeriesUncertain||g_orbBridgePlanActive||g_nasPending
      ||g_retestPending||g_imbPending||g_newDayReverseRetryPending))
   {g_lastExecStatus="MODE CHANGE: close existing lifecycle first";return false;}
   string reason="";
   if(enabled&&(!MaIndependentExecutionAllowed(reason)||!MaIndependentAcquire()))
   {g_lastExecStatus=reason!=""?reason:"SERIES STATE LOCK/IO ERROR";return false;}
   if(GlobalVariableSet(MaIndependentSettingsKey(),(enabled?1000000:0)+maximum)<=0)return false;
   GlobalVariablesFlush();g_maIndependent=enabled;g_maMaxConsecutive=maximum;
   g_maRecoveryRetryUntil=GetTickCount64()+120000;g_maRecoveryRetryAt=0;
   if(!enabled)MaIndependentRelease();
   // Do not replay the latest closed candle when changing the mode/allowance.
   g_lastSignalBarTime=iTime(_Symbol,g_rtSignalTf,1);
   g_lastCheckedSignalBarTime=g_lastSignalBarTime;
   if(previousOwner!=g_maRecoveredMagic)
   {OrbProRestoreRuntimeState();LabNativeVisualRestore();DrawOrbLiveTradeLevels();MaRenderOpenCounter(true);}
   return true;
}

bool MaIndependentOpen(string direction,datetime signalBar,double entry,double sl,double tp,string detail)
{
   string reason="";
   if(!MaIndependentExecutionAllowed(reason)||!g_orbNativeWithBridgeOnly)
   {g_lastExecStatus=reason!=""?reason:"NATIVE OFF";return false;}
   if(!MaRecoverIndependentOwner()){g_lastExecStatus="RECOVERY: owner ambiguous or locked";return false;}
   if(!MaIndependentAcquire()||signalBar<=g_maSeriesBar){g_lastExecStatus="SERIES STATE / DUPLICATE BLOCK";return false;}
   if(g_maSeriesUncertain){g_lastExecStatus="ORDER RECONCILIATION REQUIRED";return false;}
   if(OrbSignalAvailableTime(signalBar)<=g_instanceStartedAt){g_lastExecStatus="STALE SIGNAL BLOCK";return false;}
   int dir=direction=="BUY"?1:-1;
   if(MaIndependentOrdersPending()||!MaOpenCapacityAllows(MaNativeOpenCount(),g_maMaxConsecutive))
   {g_lastExecStatus="OPEN POSITION LIMIT / ORDER PENDING";return false;}
   int nextDirection=dir,nextCount=dir==g_maSeriesDir?g_maSeriesCount:0;
   string lotDetail="";double lot=ResolveLot(direction,entry,sl,lotDetail);
   if(lot<=0||!ValidateOpenStops(direction,entry,sl,tp,reason))
   {g_lastExecStatus="INDEPENDENT RISK/STOPS BLOCK";return false;}
   // Reserve BEFORE broker I/O: a crash or ambiguous response must not duplicate
   // the order. Ambiguous attempts conservatively consume one allowance.
   g_maSeriesDir=nextDirection;g_maSeriesCount=MathMin(1000,nextCount+1);
   g_maSeriesBar=signalBar;g_maSeriesUncertain=true;
   if(!MaIndependentWrite()){g_lastExecStatus="SERIES WRITE FAILED";return false;}
   trade.SetAsyncMode(false);trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   string comment="MAI|"+(string)(long)signalBar;
   // No naked-entry fallback and no close/modify of previous positions.
   bool sent=dir>0?trade.Buy(lot,_Symbol,0,sl,tp,comment):trade.Sell(lot,_Symbol,0,sl,tp,comment);
   uint rc=trade.ResultRetcode();
   bool filled=sent&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL);
   bool rejected=!filled&&MaIndependentDefiniteRejection(rc);
   if(filled||rejected)
   {
      if(rejected)g_maSeriesCount=nextCount;
      g_maSeriesUncertain=false;
      if(!MaIndependentWrite())
      {
         g_maSeriesUncertain=true;
         if(rejected)g_maSeriesCount=MathMin(1000,nextCount+1); // Keep the persisted reservation on I/O failure.
      }
   }
   g_lastExecStatus=filled?"INDEPENDENT OPENED":"INDEPENDENT ORDER NOT CONFIRMED (reserved)";
   if(rejected)g_lastExecStatus="INDEPENDENT ORDER REJECTED";
   Audit(filled?"independent_opened":"independent_reserved",direction,lot,entry,sl,tp,
      "series="+(string)g_maSeriesCount+" max="+(string)g_maMaxConsecutive+" rc="+(string)rc+" "+detail);
   if(filled)
   {
      OrbProStoreOpenPositions(dir,entry,sl,tp,0,signalBar,g_lastSignalRegime);
      DrawOrbLiveTradeLevels();
   }
   return filled;
}
#endif
