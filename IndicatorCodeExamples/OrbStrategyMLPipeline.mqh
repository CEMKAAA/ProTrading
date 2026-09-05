#ifndef ORB_STRATEGY_ML_PIPELINE_MQH
#define ORB_STRATEGY_ML_PIPELINE_MQH
#include "OrbStrategyMLCore.mqh"

void OrbMlConfigField(string &out,const string name,const string value)
{out+=name+":"+(string)StringLen(value)+":"+value+";";}
#include "OrbStrategyMLConfig.mqh"

struct OrbMlTrade
{
   datetime signalBar,entryBar;
   string rawDirection;
   double orbHigh,orbLow;
   datetime orbEnd;
   HistResult result;
};
OrbMlTrade g_mlTrades[];
OrbMlNetwork g_mlModel;
bool g_mlEnabled=false,g_mlExport=false,g_mlWriting=false;
int g_mlFile=INVALID_HANDLE,g_mlWritten=0,g_mlMissing=0;
string g_mlConfig="",g_mlPreset="",g_mlDataset="",g_mlFilePath="",g_mlStatus="ML OFF";
datetime g_mlRequestedAt=0,g_mlAsOf=0;
double g_mlProgress=0;

bool OrbMlWriteUtf8(int handle,const string text)
{
   uchar bytes[];int size=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   // Binary mode preserves canonical LF bytes instead of FILE_TXT's CRLF conversion.
   return size>0&&FileWriteArray(handle,bytes,0,size-1)==(uint)(size-1);
}

string OrbMlFileDigest(const string path)
{
   int handle=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON);
   if(handle==INVALID_HANDLE)return "";
   ulong size=FileSize(handle);uchar bytes[];
   if(size==0||size>33554432){FileClose(handle);return "";}
   ArrayResize(bytes,(int)size);uint copied=FileReadArray(handle,bytes,0,(int)size);FileClose(handle);
   return copied==size?OrbMlBytesSha256(bytes):"";
}

bool OrbMlFeatures(datetime bar,const string raw,double hi,double lo,datetime orbEnd,
   double &x[],double &observed[],string &reason)
{
   ArrayResize(x,ORB_ML_FEATURES);ArrayInitialize(x,0);
   ArrayResize(observed,7);ArrayInitialize(observed,0);reason="FEATURE_HISTORY";
   int seconds=PeriodSeconds(g_rtSignalTf);
   if(seconds<=0||bar<=0||!InpUseClosedBarBreakout){reason="CLOSED_SIGNALS_REQUIRED";return false;}
   datetime cutoff=bar+seconds;
   if(cutoff>TimeCurrent()){reason="SIGNAL_NOT_CLOSED";return false;}
   int shift=iBarShift(_Symbol,g_rtSignalTf,bar,true);
   if(shift<0)return false;
   MqlRates rates[];ArraySetAsSeries(rates,false);
   if(CopyRates(_Symbol,g_rtSignalTf,shift,256,rates)!=256)return false;
   if(rates[255].time!=bar)return false;
   double ema20=rates[0].close,ema50=ema20,old20=ema20,old50=ema50;
   double atr=0,gain=0,loss=0,atr64=0;
   for(int i=0;i<256;i++)
   {
      if(rates[i].time+seconds>cutoff||rates[i].close<=0||rates[i].high<rates[i].low
         ||(i>0&&rates[i].time<=rates[i-1].time))return false;
      if(i==0)continue;
      double diff=rates[i].close-rates[i-1].close;
      double tr=MathMax(rates[i].high-rates[i].low,MathMax(MathAbs(rates[i].high-rates[i-1].close),MathAbs(rates[i].low-rates[i-1].close)));
      if(i<=14){atr+=tr/14.0;gain+=MathMax(0.0,diff)/14.0;loss+=MathMax(0.0,-diff)/14.0;}
      else {atr=(atr*13+tr)/14;gain=(gain*13+MathMax(0.0,diff))/14;loss=(loss*13+MathMax(0.0,-diff))/14;}
      if(i>191)atr64+=tr/64;
      old20=ema20;old50=ema50;
      ema20+=(rates[i].close-ema20)*2/21;ema50+=(rates[i].close-ema50)*2/51;
   }
   if(atr<=0||atr64<=0)return false;
   MqlRates last=rates[255];double vol=0,path=0;
   for(int i=235;i<255;i++){vol+=(double)rates[i].tick_volume/20;path+=MathAbs(rates[i+1].close-rates[i].close);}
   if(vol<=0){reason="VOLUME_HISTORY";return false;}
   double rsi=(gain+loss)>0?100*gain/(gain+loss):50;
   double close=last.close;
   x[0]=EffectiveOrbDirection(raw)=="BUY"?1:-1;
   x[1]=(close-last.open)/atr;x[2]=(last.high-last.low)/atr;
   x[3]=(last.high-MathMax(close,last.open))/atr;x[4]=(MathMin(close,last.open)-last.low)/atr;
   x[5]=(close-rates[254].close)/atr;x[6]=(close-rates[250].close)/atr;x[7]=(close-rates[235].close)/atr;
   x[8]=rsi/100;x[9]=(close-ema20)/atr;x[10]=(close-ema50)/atr;x[11]=(ema20-ema50)/atr;
   x[12]=(old20<=old50&&ema20>ema50)?1:((old20>=old50&&ema20<ema50)?-1:0);
   x[13]=(double)last.tick_volume/vol;x[14]=atr/atr64;
   x[15]=path>0?MathAbs(close-rates[235].close)/path:0;x[16]=last.spread*_Point/atr;
   MqlDateTime time;TimeToStruct(cutoff,time);double pi=3.141592653589793;
   double hour=time.hour+(double)time.min/60;
   x[17]=MathSin(2*pi*hour/24);x[18]=MathCos(2*pi*hour/24);
   x[19]=MathSin(2*pi*time.day_of_week/7);x[20]=MathCos(2*pi*time.day_of_week/7);
   RegimeV3Snapshot state;int bucket=OrbRegimeBucketAt(bar,state);
   // Never substitute today's regime for unavailable history.
   if(!state.valid||state.availableTime>cutoff){reason="REGIME_HISTORY";return false;}
   x[21]=1;if(bucket>=0&&bucket<6)x[22+bucket]=1;
   x[28]=state.trendDepthScore;x[29]=state.volatilityDepthScore;x[30]=state.effectiveAge;
   x[31]=state.transitionConfidence;x[32]=state.transitionPending;
   int rf=-1;string rule="",detail="";OrbRfEvaluate(raw,state,rf,rule,detail);x[33]=rf+1;
   x[34]=(hi-lo)/atr;x[35]=(close-hi)/atr;x[36]=(close-lo)/atr;x[37]=(double)(cutoff-orbEnd)/60;
   x[38]=(ema20-old20)/atr;x[39]=g_rtInvertMode?1:0;
   observed[0]=last.open;observed[1]=last.high;observed[2]=last.low;observed[3]=close;
   observed[4]=atr;observed[5]=ema20;observed[6]=ema50;
   for(int i=0;i<ORB_ML_FEATURES;i++)if(!MathIsValidNumber(x[i]))return false;
   reason="OK";return true;
}

void OrbMlAbort(const string reason)
{
   if(g_mlFile!=INVALID_HANDLE){FileClose(g_mlFile);g_mlFile=INVALID_HANDLE;}
   g_mlExport=false;g_mlWriting=false;g_mlStatus=reason;ArrayResize(g_mlTrades,0);
   if(!g_histAuditRunning&&!g_histRedrawQueued&&!IsTesterMode())EventSetTimer(5);
   // Partial artifacts deliberately have no completion marker and cannot train a model.
}

void OrbMlCapture(datetime signalBar,datetime entryBar,const string raw,double hi,double lo,datetime orbEnd,const HistResult &result)
{
   if(!g_mlExport||g_mlWriting)return;
   int n=ArraySize(g_mlTrades);ArrayResize(g_mlTrades,n+1,512);
   g_mlTrades[n].signalBar=signalBar;g_mlTrades[n].entryBar=entryBar;
   g_mlTrades[n].rawDirection=raw;g_mlTrades[n].orbHigh=hi;g_mlTrades[n].orbLow=lo;
   g_mlTrades[n].orbEnd=orbEnd;g_mlTrades[n].result=result;
}

bool OrbMlStartExport()
{
   if(g_mlExport||g_histAuditRunning||g_histRedrawQueued||g_btRunning){g_mlStatus="WAIT FOR CURRENT AUDIT";return false;}
   if(!InpDrawHistoricalSignals){g_mlStatus="ENABLE HISTORICAL AUDIT FIRST";return false;}
   OrbStrategyPresetSyncSelection();OrbStrategyPreset p;
   if(!OrbStrategyPresetLoad(g_strategyPresetIndex,p)){g_mlStatus="APPLY A STRATEGY FIRST";return false;}
   if(!InpUseClosedBarBreakout){g_mlStatus="CLOSED SIGNALS REQUIRED";return false;}
   string config=OrbMlConfiguration();if(config==""){g_mlStatus="CONFIG HASH FAILED";return false;}
   g_mlConfig=config;g_mlPreset=p.id;
   g_mlDataset=p.id+"_"+StringSubstr(config,0,12)+"_"+(string)(long)TimeLocal()+"_"+(string)ChartID()+"_"+(string)GetTickCount64();
   g_mlFilePath="OrbML\\Datasets\\"+g_mlDataset+".csv";
   g_mlWritten=0;g_mlMissing=0;g_mlProgress=0;ArrayResize(g_mlTrades,0);
   g_mlRequestedAt=TimeLocal();g_mlAsOf=0;g_mlWriting=false;
   SetHistoricalWeeks(260);QueueHistoricalRedraw(0);
   g_mlExport=true;g_mlStatus="5Y AUDIT QUEUED";return true;
}

void OrbMlAuditFinished()
{
   if(!g_mlExport)return;
   if(OrbMlConfiguration()!=g_mlConfig||g_histRunDays!=1820||ArraySize(g_mlTrades)!=g_histTotal)
   {OrbMlAbort("EXPORT CONFIG/ROW MISMATCH");return;}
   g_mlAsOf=g_histRunNow;
   g_mlFile=FileOpen(g_mlFilePath+".partial",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(g_mlFile==INVALID_HANDLE){OrbMlAbort("CSV OPEN FAILED");return;}
   string header="schema,source_hash,config_hash,dataset_id,preset_id,symbol,broker,signal_tf_seconds,chart_tf_seconds,"
      "window_from_broker,asof_broker,signal_bar_broker,features_at_broker,entry_at_broker,exit_at_broker,"
      "raw_direction,execution_direction,entry,sl,tp,net_r,cost_r,exit_reason,label_valid,label_win,"
      "features_valid,feature_status,obs_open,obs_high,obs_low,obs_close,obs_atr14,obs_ema20,obs_ema50,"+OrbMlFeatureNames()+"\n";
   if(!OrbMlWriteUtf8(g_mlFile,header)){OrbMlAbort("CSV HEADER FAILED");return;}
   g_mlWriting=true;g_mlProgress=85;g_mlStatus="WRITING FEATURES";
   EventSetMillisecondTimer(40);
}

string OrbMlCsv(string value){StringReplace(value,"\"","\"\"");return "\""+value+"\"";}
string OrbMlNum(double value){return DoubleToString(value,16);}

void OrbMlExportStep()
{
   if(!g_mlExport)return;
   if(g_rtHistoricalWeeks!=260||OrbMlConfiguration()!=g_mlConfig)
   {OrbMlAbort("EXPORT CANCELLED: SETTINGS CHANGED");return;}
   if(g_histCoverageHardBlocked){OrbMlAbort("5Y BROKER HISTORY UNAVAILABLE");return;}
   if(!g_mlWriting)
   {
      g_mlProgress=MathMin(84.9,g_histAuditProgressPct*0.85);
      g_mlStatus=g_histCoveragePending?"WAITING FOR BROKER HISTORY":"5Y AUDIT "+DoubleToString(g_mlProgress,1)+"%";
      return;
   }
   ulong start=GetTickCount64();int total=ArraySize(g_mlTrades);
   while(g_mlWritten<total&&GetTickCount64()-start<12)
   {
      OrbMlTrade record=g_mlTrades[g_mlWritten];HistResult result=record.result;
      double x[],observed[];string reason="";
      bool valid=OrbMlFeatures(record.signalBar,record.rawDirection,record.orbHigh,record.orbLow,record.orbEnd,x,observed,reason);
      if(!valid)g_mlMissing++;
      datetime available=record.signalBar+PeriodSeconds(g_rtSignalTf);
      datetime entryTime=OrbSignalAvailableTime(record.entryBar);
      bool label=result.valid&&result.outcome!="open"&&result.exitTime>=entryTime&&result.exitTime<=g_mlAsOf&&MathIsValidNumber(result.netR);
      string row=ORB_ML_SCHEMA+","+ORB_ML_SOURCE+","+g_mlConfig+","+g_mlDataset+","+g_mlPreset+","+OrbMlCsv(_Symbol)+","+OrbMlCsv(AccountInfoString(ACCOUNT_SERVER))+","
         +(string)PeriodSeconds(g_rtSignalTf)+","+(string)PeriodSeconds(_Period)+","+(string)(long)(g_mlAsOf-1820*86400)+","+(string)(long)g_mlAsOf+","
         +(string)(long)record.signalBar+","+(string)(long)available+","+(string)(long)entryTime+","+(string)(long)result.exitTime+","
         +record.rawDirection+","+EffectiveOrbDirection(record.rawDirection)+","+OrbMlNum(result.simEntry)+","+OrbMlNum(result.simSl)+","+OrbMlNum(result.simTarget)+","
         +(label?OrbMlNum(result.netR):"")+","+OrbMlNum(result.costR)+","+OrbMlCsv(result.outcome)+","+(label?"1":"0")+","+(label?(result.netR>0?"1":"0"):"")+","
         +(valid?"1":"0")+","+OrbMlCsv(reason);
      for(int i=0;i<7;i++)row+=","+(valid?OrbMlNum(observed[i]):"");
      for(int i=0;i<ORB_ML_FEATURES;i++)row+=","+(valid?OrbMlNum(x[i]):"");
      if(!OrbMlWriteUtf8(g_mlFile,row+"\n")){OrbMlAbort("CSV WRITE FAILED");return;}
      g_mlWritten++;
   }
   g_mlProgress=85+15*(double)g_mlWritten/MathMax(1,total);
   g_mlStatus="CSV "+(string)g_mlWritten+"/"+(string)total+" missing="+(string)g_mlMissing;
   if(g_mlWritten<total)return;
   FileFlush(g_mlFile);FileClose(g_mlFile);g_mlFile=INVALID_HANDLE;
   if(!FileMove(g_mlFilePath+".partial",FILE_COMMON,g_mlFilePath,FILE_COMMON))
   {OrbMlAbort("CSV FINALIZE FAILED");return;}
   string digest=OrbMlFileDigest(g_mlFilePath);
   if(digest==""){OrbMlAbort("CSV CHECKSUM FAILED");return;}
   int marker=FileOpen(g_mlFilePath+".complete",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(marker==INVALID_HANDLE){OrbMlAbort("COMPLETION MARKER FAILED");return;}
   bool written=OrbMlWriteUtf8(marker,g_mlConfig+"\n"+(string)total+"\n"+g_mlDataset+"\n"+digest+"\n");FileFlush(marker);FileClose(marker);
   if(!written){OrbMlAbort("COMPLETION WRITE FAILED");return;}
   g_mlExport=false;g_mlWriting=false;ArrayResize(g_mlTrades,0);
   g_mlStatus="CSV READY "+(string)total+" trades; missing="+(string)g_mlMissing;
   Print("ORB_ML_CSV_READY ",TerminalInfoString(TERMINAL_COMMONDATA_PATH),"\\Files\\",g_mlFilePath);
   if(!g_histAuditRunning&&!g_histRedrawQueued)EventSetTimer(5);
}

string OrbMlEnabledKey(){return "ORB_ML_ON."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
bool OrbMlLoad()
{
   g_mlModel.ready=false;string config=OrbMlConfiguration();
   if(config==""){g_mlStatus="APPLY A STRATEGY FIRST";return false;}
   string path="OrbML\\Models\\"+config+".model";
   int file=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
   if(file==INVALID_HANDLE){g_mlStatus="MODEL MISSING: "+StringSubstr(config,0,12);return false;}
   ulong size=FileSize(file);uchar bytes[];
   if(size==0||size>1000000){FileClose(file);g_mlStatus="MODEL SIZE INVALID";return false;}
   ArrayResize(bytes,(int)size);uint read=FileReadArray(file,bytes,0,(int)size);FileClose(file);
   if(read!=size){g_mlStatus="MODEL READ INCOMPLETE";return false;}
   return OrbMlParseModel(CharArrayToString(bytes,0,(int)size,CP_UTF8),config,g_mlModel,g_mlStatus);
}

void OrbMlInit()
{
   g_mlEnabled=GlobalVariableCheck(OrbMlEnabledKey())&&GlobalVariableGet(OrbMlEnabledKey())>0.5;
   if(g_mlEnabled)OrbMlLoad();
}

bool OrbMlAllow(const string raw,datetime bar)
{
   if(!g_mlEnabled)return true;
   string config=OrbMlConfiguration();double probability=0,x[],observed[];string reason="";
   bool ready=g_mlModel.ready&&config!=""&&g_mlModel.config==config;
   if(!ready)reason="MISSING_OR_MISMATCHED_MODEL";
   else if(bar+PeriodSeconds(g_rtSignalTf)<=g_mlModel.lastLabelTime)reason="NOT_OUT_OF_SAMPLE";
   else if(OrbMlFeatures(bar,raw,g_orbHigh,g_orbLow,g_orbEndServer,x,observed,reason))
   {
      if(!OrbMlPredict(g_mlModel,x,probability))reason="INFERENCE_ERROR";
      else reason=probability>=g_mlModel.threshold?"ALLOW":"SCORE_REJECT";
   }
   g_mlStatus="ML "+reason+" p="+DoubleToString(probability,3);
   Audit("ml_filter",EffectiveOrbDirection(raw),0,0,0,0,"bar="+(string)(long)bar+" config="+config
      +" dataset="+g_mlModel.dataset+" decision="+reason+" score="+DoubleToString(probability,8));
   return reason=="ALLOW";
}

#include "OrbStrategyMLJobs.mqh"

bool OrbMlUiEvent(const string object)
{
   if(OrbMlJobUiEvent(object)){ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;}
   if(object==PREFIX+"BTN_ML_EXPORT")OrbMlStartExport();
   else if(object==PREFIX+"BTN_ML_CANCEL")OrbMlAbort("EXPORT CANCELLED");
   else if(object==PREFIX+"BTN_ML_LOAD"||object==PREFIX+"BTN_ML_TOGGLE")
   {
      if(OrbStrategyPresetHasActiveLifecycle()||g_nasPending||g_retestPending||g_imbPending||g_newDayReverseRetryPending)
         g_mlStatus="WAIT: ACTIVE/PENDING TRADE";
      else if(object==PREFIX+"BTN_ML_LOAD")OrbMlLoad();
      else
      {
         bool requested=!g_mlEnabled;
         if(!requested||OrbMlLoad())
         {
            if(GlobalVariableSet(OrbMlEnabledKey(),requested?1:0)>0)
            {GlobalVariablesFlush();g_mlEnabled=requested;g_mlStatus=requested?"ML FILTER ON":"ML FILTER OFF";}
            else g_mlStatus="ML STATE SAVE FAILED";
         }
      }
   }
   else return false;
   ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;
}

void OrbMlDraw()
{
   if(!InpShowDashboard)return;
   int x=InpDashboardX+644,y=InpDashboardY+346;
   CreateLabel("DASH_ML_TITLE",x,y,"STRATEGY ML FILTER | base audit remains unfiltered",C'255,187,92',8);
   CreateButton("BTN_ML_EXPORT",x,y+20,176,22,"CREATE 5Y CSV",C'38,101,176');
   CreateButton("BTN_ML_CANCEL",x+184,y+20,70,22,"CANCEL",C'80,80,80');
   CreateButton("BTN_ML_LOAD",x+262,y+20,136,22,"LOAD MODEL",C'38,101,176');
   CreateButton("BTN_ML_TOGGLE",x+406,y+20,186,22,g_mlEnabled?"ML FILTER ON":"ML FILTER OFF",g_mlEnabled?C'184,103,22':C'80,80,80');
   CreateRect("DASH_ML_TRACK",x,y+49,592,8,C'38,46,60',C'38,46,60');
   CreateRect("DASH_ML_FILL",x,y+49,(int)(592*MathMax(0,MathMin(100,g_mlProgress))/100),8,C'90,178,255',C'90,178,255');
   CreateLabel("DASH_ML_STATUS",x,y+64,g_mlStatus,C'184,196,210',8);
   CreateLabel("DASH_ML_PATH",x,y+83,"Files/OrbML/Datasets | model keyed to strategy + config",C'134,158,182',7);
   OrbMlDrawJobs(x,y+111);
}
#endif
