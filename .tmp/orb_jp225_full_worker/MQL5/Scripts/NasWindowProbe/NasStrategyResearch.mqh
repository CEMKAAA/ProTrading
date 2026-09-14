#ifndef NAS_STRATEGY_RESEARCH_MQH
#define NAS_STRATEGY_RESEARCH_MQH
#include "NasStrategyFeatures.mqh"

struct NasResearchTrade
{
   datetime signal,entryAt,deadline;
   int direction,bucket,closeDirection;
   double entry,sl,tp,hc;
   double features[40];
   bool featuresValid,entryValid;
   string featureReason;
};
NasResearchTrade g_nasResearchTrades[];
int g_nasResearchNextBuy[],g_nasResearchNextSell[],g_nasResearchNextAny[];
datetime g_nasResearchCloseTimes[];
int g_nasResearchCloseDirections[];
bool g_nasResearchWriting=false,g_nasResearchCaptureReady=false;
int g_nasResearchCursor=0,g_nasResearchRows=0,g_nasResearchValid=0,g_nasResearchFile=INVALID_HANDLE;
int g_nasResearchOldWeeks=2;
datetime g_nasResearchAsOf=0,g_nasResearchFrom=0;
string g_nasResearchDataset="",g_nasResearchConfig="",g_nasResearchPreset="",g_nasResearchPath="";
string g_nasResearchJob="",g_nasResearchJobModel="",g_nasResearchJobConfig="";
double g_nasResearchProgress=0;
datetime g_nasLibraryAuditExits[];
double g_nasLibraryAuditReturns[];
int g_nasLibraryAuditData=0;

#include "AuditMemoIndex.mqh"
struct NasReplayMemoValue
{
   datetime at;double px,gross,mfe,mae;string reason,quality;
};
AuditMemoIndex g_nasReplayMemo;
NasReplayMemoValue g_nasReplayValues[];
long g_nasReplayMemoHits=0,g_nasReplayMemoMisses=0;


bool NasLibraryStrictAudit()
{
   return InpSignalBarMode==NAS_SIGNAL_BAR_CLOSED&&UseSingleOrderTpMode()
      &&g_hcBeTpLegRuntime==0&&g_invertHcBeProgressPctRuntime==0;
}

void NasLibraryDrawResearch()
{
   NasLibraryUi("EXPORT",OBJ_BUTTON,36,382,158,24,"CREATE 5Y CSV",C'28,80,112');
   NasLibraryUi("TRAIN",OBJ_BUTTON,204,382,132,24,"TRAIN MODEL",C'28,80,112');
   NasLibraryUi("MODEL",OBJ_BUTTON,346,382,160,24,g_nasLibraryModelMode==0?"MODEL: LEGACY":"MODEL: CHAMPION",C'28,80,112');
   NasLibraryUi("USE",OBJ_BUTTON,516,382,124,24,"USE RESULT",C'28,80,112');
   NasLibraryUi("ML",OBJ_BUTTON,650,382,122,24,g_nasLibraryMlEnabled?"ML FILTER ON":"ML FILTER OFF",g_nasLibraryMlEnabled?C'130,90,20':C'48,57,68');
   NasLibraryUi("CANCEL",OBJ_BUTTON,782,382,100,24,"CANCEL CSV",C'80,48,48');
   NasLibraryUi("CANCELTRAIN",OBJ_BUTTON,890,382,120,24,"CANCEL TRAIN",C'80,48,48');
   NasLibraryUi("TRACK",OBJ_RECTANGLE_LABEL,36,423,974,8,"",C'48,57,68');
   NasLibraryUi("PROGRESS",OBJ_RECTANGLE_LABEL,36,423,MathMax(1,(int)(974*g_nasResearchProgress/100)),8,"",C'37,151,130');
   NasLibraryUi("PROGRESS_TEXT",OBJ_LABEL,36,441,0,0,DoubleToString(g_nasResearchProgress,1)+"% | Training needs the NAS worker; no orders from research jobs.");
}

bool NasLibrarySelectedClean()
{
   if(g_nasLibrarySelected<0||g_nasLibraryAppliedConfig==""||g_nasLibraryAppliedConfig!=NasLibraryConfig())
   {g_nasLibraryStatus="Apply or save the current configuration first. Settings changed since selection.";return false;}
   return true;
}

void NasResearchAbort(string reason)
{
   if(g_nasResearchFile!=INVALID_HANDLE){FileClose(g_nasResearchFile);g_nasResearchFile=INVALID_HANDLE;}
   g_nasLibraryExport=false;g_nasResearchWriting=false;g_nasResearchCaptureReady=false;
   g_auditWeeksRuntime=g_nasResearchOldWeeks;
   g_nasLibraryStatus=reason;ArrayFree(g_nasResearchTrades);
   // Incomplete files have no .complete marker and cannot enter training.
}

bool NasResearchStart()
{
   if(!NasLibrarySelectedClean()||NasLibraryBusy())return false;
   if(g_eaEnabledRuntime||g_nasBridgeEnabledRuntime)
   {g_nasLibraryStatus="Pause native entries and PUB before starting a multi-year research export.";return false;}
   if(InpSignalBarMode!=NAS_SIGNAL_BAR_CLOSED||!UseSingleOrderTpMode())
   {g_nasLibraryStatus="Research requires CLOSED signals and single-order geometry.";return false;}
   if(g_hcBeTpLegRuntime!=0||g_invertHcBeProgressPctRuntime!=0)
   {g_nasLibraryStatus="HCBE research replay has not passed parity yet; export refused (no fabricated labels).";return false;}
   g_nasLibraryMlEnabled=false;g_nasResearchOldWeeks=g_auditWeeksRuntime;g_auditWeeksRuntime=260;
   g_nasResearchAsOf=iTime(_Symbol,PERIOD_M1,0);g_nasResearchFrom=g_nasResearchAsOf-260*7*86400;
   g_nasResearchConfig=NasLibraryConfig();g_nasResearchPreset=g_nasLibrary[g_nasLibrarySelected].id;
   g_nasResearchDataset=g_nasResearchPreset+"_"+StringSubstr(g_nasResearchConfig,0,12)+"_"+(string)(long)TimeLocal()+"_"+(string)ChartID();
   g_nasResearchPath="NasML\\Datasets\\"+g_nasResearchDataset+".csv";
   FolderCreate("NasML\\Datasets",FILE_COMMON);
   ArrayFree(g_nasResearchTrades);g_nasResearchCaptureReady=false;g_nasResearchRows=0;g_nasResearchValid=0;
   g_nasResearchProgress=0;g_nasLibraryExport=true;g_nasLibraryStatus="Preparing unfiltered 5Y NAS candidate geometry.";
   ArrayFree(g_historySimCache);RequestHistoryRefresh();return true;
}

void NasResearchPrepare(const MqlRates &rates[],const NasPoint &p[],const int &closeSignal[])
{
   if(!g_nasLibraryExport&&!NasLibraryStrictAudit())return;
   if(!g_nasLibraryExport)g_nasResearchAsOf=iTime(_Symbol,PERIOD_M1,0);
   ArrayFree(g_nasLibraryAuditExits);ArrayFree(g_nasLibraryAuditReturns);g_nasLibraryAuditData=0;
   int n=ArraySize(rates);ArrayResize(g_nasResearchNextBuy,n);ArrayResize(g_nasResearchNextSell,n);
   ArrayResize(g_nasResearchNextAny,n);ArrayResize(g_nasResearchCloseTimes,n);ArrayResize(g_nasResearchCloseDirections,n);
   int buy=-1,sell=-1,any=-1;
   for(int i=n-1;i>=0;i--)
   {
      g_nasResearchNextBuy[i]=buy;g_nasResearchNextSell[i]=sell;g_nasResearchNextAny[i]=any;
      g_nasResearchCloseTimes[i]=(i+1<n)?rates[i+1].time:0;
      int d=p[i].buy?1:(p[i].sell?-1:0);if(g_invertTradeModeRuntime)d=-d;
      g_nasResearchCloseDirections[i]=d;
      if(i>=ArraySize(closeSignal)||closeSignal[i]<=0||d==0||i+1>=n)continue;
      if(closeSignal[i]==2)any=i;
      else if(d>0)buy=i;
      else sell=i;
   }
   g_nasResearchCaptureReady=true;
}

void NasResearchTradePlan(const MqlRates &rates[],int i,int direction,double entry,double sl,double tp,double hc,bool entryValid,NasResearchTrade &t)
{
   ZeroMemory(t);
   t.signal=rates[i].time;t.entryAt=rates[i+1].time;t.entry=entry;t.sl=sl;t.tp=tp;t.hc=hc;t.direction=direction;t.entryValid=entryValid;
   t.deadline=NasTimedExitDeadlineForEntry(t.entryAt);t.closeDirection=0;
   int next=g_nasResearchNextAny[i],opposite=direction>0?g_nasResearchNextSell[i]:g_nasResearchNextBuy[i];
   if(next<0||(opposite>=0&&opposite<next))next=opposite;
   if(next>=0)
   {
      datetime when=g_nasResearchCloseTimes[next];
      if(t.deadline<=0||when<t.deadline){t.deadline=when;t.closeDirection=g_nasResearchCloseDirections[next];}
   }
}

void NasResearchCapture(const MqlRates &rates[],const NasPoint &p[],int i,int direction,double entry,double sl,double tp,double hc,bool entryValid)
{
   if(!g_nasLibraryExport||!g_nasResearchCaptureReady||i+1>=ArraySize(rates))return;
   if(rates[i].time<g_nasResearchFrom||rates[i+1].time>=g_nasResearchAsOf)return;
   int n=ArraySize(g_nasResearchTrades);ArrayResize(g_nasResearchTrades,n+1,512);
   NasResearchTrade t;NasResearchTradePlan(rates,i,direction,entry,sl,tp,hc,entryValid,t);
   double features[];string reason;
   t.featuresValid=NasLibraryFeatures(rates,i,p[i],direction,features,reason);t.featureReason=reason;
   for(int k=0;k<40;k++)t.features[k]=features[k];
   RegimeV3Snapshot snapshot;t.bucket=LiqMacroRegimeBucketAt(t.signal+PeriodSeconds(_Period),snapshot);
   g_nasResearchTrades[n]=t;
}

void NasResearchFinishCapture()
{
   if(!g_nasLibraryExport)return;
   if(g_historyCoverageBlocked||!g_nasResearchCaptureReady||ArraySize(g_nasResearchTrades)==0)
   {NasResearchAbort("Export blocked: "+g_historyCoverageDetail+"; no complete candidate set.");return;}
   g_nasResearchFile=FileOpen(g_nasResearchPath,FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(g_nasResearchFile==INVALID_HANDLE){NasResearchAbort("Cannot create dataset.");return;}
   string header="schema,source_hash,config_hash,dataset_id,preset_id,symbol,broker,signal_tf_seconds,chart_tf_seconds,window_from_broker,asof_broker,signal_bar_broker,features_at_broker,entry_at_broker,execution_direction,exit_at_broker,label_valid,features_valid,label_win,net_r,gross_r,commission_r,entry,sl,tp,exit_price,exit_reason,label_quality,regime_bucket,mfe_confirmed_lower_r,mae_confirmed_upper_r,feature_quality,entry_valid,"+NasMlFeatureNames()+"\n";
   uchar bytes[];int length=StringToCharArray(header,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(FileWriteArray(g_nasResearchFile,bytes,0,length)!=(uint)length){NasResearchAbort("CSV header write failed.");return;}
   g_nasResearchCursor=ArraySize(g_nasResearchTrades)-1;g_nasResearchWriting=true;g_nasResearchProgress=20;
   g_auditWeeksRuntime=g_nasResearchOldWeeks;g_nasLibraryStatus="M1 bid/ask-estimate replay; ambiguous labels excluded from training.";
}

// No approximate-bar winner is sold as a certain ML label. Bid OHLC plus the
// recorded spread estimates Ask for shorts; absent data invalidates the label.
bool NasResearchReplay(const NasResearchTrade &t,const MqlRates &m1[],datetime asOf,double pointSize,datetime &exitAt,double &exitPx,double &gross,string &reason,string &quality,double &mfe,double &mae)
{
   exitAt=0;exitPx=0;gross=0;mfe=0;mae=0;reason="OPEN";quality="M1_SPREAD_ESTIMATE";
   double risk=MathAbs(t.entry-t.sl);
   if(risk<=0||t.direction*(t.tp-t.entry)<=0||t.direction*(t.entry-t.sl)<=0)
   {quality="INVALID_GEOMETRY";return false;}
   if(!t.entryValid){quality="ENTRY_UNRESOLVED";return false;}
   datetime end=asOf;
   if(t.deadline>0&&t.deadline<end)end=t.deadline;
   int n=ArraySize(m1);
   if(n<=0||m1[0].time!=t.entryAt){quality="MISSING_M1_START";return false;}
   bool exact=true;
   for(int i=0;i<n;i++)
   {
      if(m1[i].time>=asOf)break;
      if(m1[i].high<m1[i].low||m1[i].open<=0||m1[i].open>m1[i].high||m1[i].open<m1[i].low)
      {quality="INVALID_M1_QUOTE";return false;}
      if(i>0&&m1[i].time!=m1[i-1].time+60){exact=false;quality="M1_GAP";}
      if(m1[i].spread<=0){exact=false;quality="SPREAD_UNKNOWN";}
      double spread=MathMax(0,m1[i].spread)*pointSize;
      double open=m1[i].open+(t.direction<0?spread:0);
      double high=m1[i].high+(t.direction<0?spread:0),low=m1[i].low+(t.direction<0?spread:0);
      bool stopOpen=t.direction>0?open<=t.sl:open>=t.sl;
      bool tpOpen=t.direction>0?open>=t.tp:open<=t.tp;
      bool boundary=t.deadline>0&&m1[i].time>=t.deadline;
      if(stopOpen||tpOpen||boundary)
      {
         exitAt=m1[i].time;exitPx=stopOpen?open:(tpOpen?t.tp:open);
         reason=stopOpen?"SL_GAP":(tpOpen?"TP":(t.closeDirection==0?"TIME_EXIT":(t.closeDirection==t.direction?"REPLACE":"REVERSE")));
         gross=t.direction*(exitPx-t.entry)/risk;
         mfe=MathMax(mfe,gross);mae=MathMin(mae,gross);return exact;
      }
      bool sl=t.direction>0?low<=t.sl:high>=t.sl;
      bool tp=t.direction>0?high>=t.tp:low<=t.tp;
      if(sl&&tp){quality="AMBIGUOUS_M1";reason="DATA";return false;}
      // Only fully traversed bars contribute exact excursion bounds. The exit
      // bar's unseen tail must not inflate MFE/MAE after the position closed.
      if(sl||tp)
      {
         exitAt=m1[i].time+60;exitPx=sl?t.sl:t.tp;reason=sl?"SL":"TP";
         gross=t.direction*(exitPx-t.entry)/risk;
         mfe=MathMax(mfe,gross);mae=MathMin(mae,gross);return exact;
      }
      mfe=MathMax(mfe,t.direction*((t.direction>0?high:low)-t.entry)/risk);
      mae=MathMin(mae,t.direction*((t.direction>0?low:high)-t.entry)/risk);
   }
   if(m1[n-1].time+60<end)quality="MISSING_M1_END";
   else if(exact&&end==asOf)
   {
      exitPx=m1[n-1].close+(t.direction<0?MathMax(0,m1[n-1].spread)*pointSize:0);
      gross=t.direction*(exitPx-t.entry)/risk;
   }
   return false;
}

bool NasResearchOutcome(const NasResearchTrade &t,datetime &exitAt,double &exitPx,double &gross,string &reason,string &quality,double &mfe,double &mae)
{
   string epoch=AuditMemoDataEpoch(_Symbol);
   g_nasReplayMemo.Reset(epoch);
   string key=(string)t.entryAt+"|"+(string)t.deadline+"|"+(string)t.direction+"|"+(string)t.closeDirection
      +"|"+AuditMemoPrice(t.entry)+"|"+AuditMemoPrice(t.sl)+"|"+AuditMemoPrice(t.tp)
      +"|"+(string)t.entryValid+"|"+AuditMemoPrice(_Point);
   int cached=g_nasReplayMemo.Find(key);
   if(cached>=0&&g_nasReplayValues[cached].at<=g_nasResearchAsOf)
   {
      NasReplayMemoValue v=g_nasReplayValues[cached];
      exitAt=v.at;exitPx=v.px;gross=v.gross;reason=v.reason;quality=v.quality;mfe=v.mfe;mae=v.mae;
      g_nasReplayMemoHits++;return true;
   }
   g_nasReplayMemoMisses++;
   datetime end=g_nasResearchAsOf;
   if(t.deadline>0&&t.deadline<end)end=t.deadline;
   MqlRates m1[];ArraySetAsSeries(m1,false);
   CopyRates(_Symbol,PERIOD_M1,t.entryAt,MathMin(g_nasResearchAsOf-1,end+300),m1);
   bool valid=NasResearchReplay(t,m1,g_nasResearchAsOf,_Point,exitAt,exitPx,gross,reason,quality,mfe,mae);
   // An asynchronous history download during CopyRates must not seal stale data.
   if(valid&&reason!="OPEN"&&reason!="DATA"&&exitAt>0&&exitAt<=g_nasResearchAsOf&&epoch==AuditMemoDataEpoch(_Symbol))
   {
      int slot=g_nasReplayMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_nasReplayValues)<=slot)ArrayResize(g_nasReplayValues,slot+1,512);
         g_nasReplayValues[slot].at=exitAt;g_nasReplayValues[slot].px=exitPx;g_nasReplayValues[slot].gross=gross;
         g_nasReplayValues[slot].reason=reason;g_nasReplayValues[slot].quality=quality;
         g_nasReplayValues[slot].mfe=mfe;g_nasReplayValues[slot].mae=mae;
      }
   }
   return valid;
}

bool NasLibraryReplayAudit(const MqlRates &rates[],int i,int direction,double entry,double sl,double tp,bool entryValid,
   bool accepted,int &maxTp,string &outcome,double &pnlR,bool &closed,bool &won)
{
   NasResearchTrade t;NasResearchTradePlan(rates,i,direction,entry,sl,tp,0,entryValid,t);
   datetime at;double px,mfe,mae;string reason,quality;
   closed=NasResearchOutcome(t,at,px,pnlR,reason,quality,mfe,mae);won=closed&&pnlR>0;maxTp=0;
   if(!closed&&!(reason=="OPEN"&&quality=="M1_SPREAD_ESTIMATE"))
   {outcome="DATA "+quality;if(accepted)g_nasLibraryAuditData++;return false;}
   outcome=reason=="TP"?"TP hit":reason;
   if(reason=="TP")maxTp=LegacyLegForTargetR(MathAbs(tp-entry)/MathAbs(entry-sl));
   if(reason=="OPEN")outcome="open M1";
   if(reason=="REVERSE")outcome="reverse M1";
   if(reason=="REPLACE")outcome="replace M1";
   if(closed&&accepted)
   {
      int n=ArraySize(g_nasLibraryAuditExits);ArrayResize(g_nasLibraryAuditExits,n+1,512);ArrayResize(g_nasLibraryAuditReturns,n+1,512);
      g_nasLibraryAuditExits[n]=at;
      g_nasLibraryAuditReturns[n]=pnlR-(InpAuditCommissionEnabled?entry/MathAbs(entry-sl)*InpAuditRoundTurnCommissionPct/100:0);
   }
   return true;
}

void NasLibraryAuditCurve(double &minimum,double &negativeDrawdown)
{
   datetime times[];ArrayCopy(times,g_nasLibraryAuditExits);ArraySort(times);
   double sums[];int n=ArraySize(times);ArrayResize(sums,n);ArrayInitialize(sums,0);
   for(int i=0;i<n;i++)
   {
      int lo=0,hi=n;
      while(lo<hi){int mid=(lo+hi)/2;if(times[mid]<g_nasLibraryAuditExits[i])lo=mid+1;else hi=mid;}
      sums[lo]+=g_nasLibraryAuditReturns[i];
   }
   minimum=0;negativeDrawdown=0;double net=0,peak=0;
   for(int i=0;i<n;i++){net+=sums[i];peak=MathMax(peak,net);minimum=MathMin(minimum,net);negativeDrawdown=MathMin(negativeDrawdown,net-peak);}
}

void NasResearchTick()
{
   if(!g_nasLibraryExport||!g_nasResearchWriting)return;
   if(g_nasResearchConfig!=NasLibraryConfig()){NasResearchAbort("Configuration changed during export; incomplete file rejected.");return;}
   ulong started=GetTickCount64();int budget=0;
   while(g_nasResearchCursor>=0&&budget<4&&GetTickCount64()-started<40)
   {
      NasResearchTrade t=g_nasResearchTrades[g_nasResearchCursor--];
      datetime exitAt;double exitPx,gross,mfe,mae;string reason,quality;
      bool valid=NasResearchOutcome(t,exitAt,exitPx,gross,reason,quality,mfe,mae);
      double fee=InpAuditCommissionEnabled? t.entry/MathAbs(t.entry-t.sl)*InpAuditRoundTurnCommissionPct/100:0;
      double net=gross-fee;
      string broker=AccountInfoString(ACCOUNT_SERVER);StringReplace(broker,",","_");
      string row=NAS_ML_SCHEMA+","+NAS_LIBRARY_SOURCE_HASH+","+g_nasResearchConfig+","+g_nasResearchDataset+","+g_nasResearchPreset+","+_Symbol+","+broker
         +","+(string)PeriodSeconds(_Period)+","+(string)PeriodSeconds(_Period)+","+(string)(long)g_nasResearchFrom+","+(string)(long)g_nasResearchAsOf
         +","+(string)(long)t.signal+","+(string)(long)(t.signal+PeriodSeconds(_Period))+","+(string)(long)t.entryAt+","+(string)t.direction
         +","+(string)(long)exitAt+","+(string)(int)valid+","+(string)(int)t.featuresValid+","+(valid?(string)(int)(net>0):"")
         +","+(valid?DoubleToString(net,12):"")+","+(valid?DoubleToString(gross,12):"")+","+DoubleToString(fee,12)
         +","+DoubleToString(t.entry,12)+","+DoubleToString(t.sl,12)+","+DoubleToString(t.tp,12)+","+DoubleToString(exitPx,12)
         +","+reason+","+quality+","+(string)t.bucket+","+DoubleToString(mfe,12)+","+DoubleToString(mae,12)
         +","+t.featureReason+","+(string)(int)t.entryValid;
      for(int k=0;k<40;k++)row+=","+DoubleToString(t.features[k],16);
      row+="\n";uchar bytes[];int length=StringToCharArray(row,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
      if(FileWriteArray(g_nasResearchFile,bytes,0,length)!=(uint)length){NasResearchAbort("CSV write failed.");return;}
      g_nasResearchRows++;if(valid&&t.featuresValid)g_nasResearchValid++;budget++;
   }
   g_nasResearchProgress=20+79*(double)g_nasResearchRows/MathMax(1,ArraySize(g_nasResearchTrades));
   g_nasLibraryStatus="CSV "+(string)g_nasResearchRows+"/"+(string)ArraySize(g_nasResearchTrades)+"; eligible labels "+(string)g_nasResearchValid;
   if(g_nasResearchCursor<0)
   {
      FileFlush(g_nasResearchFile);FileClose(g_nasResearchFile);g_nasResearchFile=INVALID_HANDLE;
      string text;
      if(!NasLibraryRead(g_nasResearchPath,text)||!NasLibraryWrite(g_nasResearchPath+".complete",g_nasResearchConfig+"\n"+(string)g_nasResearchRows+"\n"+g_nasResearchDataset+"\n"+NasMlSha256(text)+"\n"))
      {NasResearchAbort("Completion checksum/write failed; dataset must not train.");return;}
      string pointer=g_nasResearchPreset+"\n"+g_nasResearchConfig+"\n"+g_nasResearchDataset+"\n";
      NasLibraryWrite("NasML\\Datasets\\"+g_nasResearchConfig+".latest",pointer+NasMlSha256(pointer)+"\n");
      g_nasLibraryExport=false;g_nasResearchWriting=false;g_nasResearchProgress=100;
      g_nasLibraryStatus="CSV complete: "+(string)g_nasResearchRows+" rows, "+(string)g_nasResearchValid+" eligible. "+g_nasResearchPath;
      ArrayFree(g_nasResearchTrades);
   }
   if(g_nasLibraryOpen)NasLibraryDraw();
}

bool NasResearchTrain()
{
   if(!NasLibrarySelectedClean()||NasLibraryBusy())return false;
   string config=NasLibraryConfig(),pointer,a[];
   if(!NasLibraryRead("NasML\\Datasets\\"+config+".latest",pointer)||StringSplit(pointer,'\n',a)!=5
      ||a[0]!=g_nasLibrary[g_nasLibrarySelected].id||a[1]!=config||!NasLibrarySafeToken(a[2])
      ||NasMlSha256(a[0]+"\n"+a[1]+"\n"+a[2]+"\n")!=a[3])
   {g_nasLibraryStatus="No complete CSV for this exact NAS strategy/configuration.";return false;}
   FolderCreate("NasML\\Jobs",FILE_COMMON);
   g_nasResearchJob="job_"+(string)(long)TimeLocal()+"_"+(string)ChartID()+"_"+(string)GetTickCount64();
   g_nasResearchJobConfig=config;
   string body="NAS_JOB1\n"+g_nasResearchJob+"\n"+a[0]+"\n"+config+"\n"+a[2]+"\n"+(string)g_nasLibraryModelMode+"\n";
   if(!NasLibraryWrite("NasML\\Jobs\\"+g_nasResearchJob+".job",body+NasMlSha256(body)+"\n"))return false;
   g_nasResearchProgress=0;g_nasLibraryStatus="Queued training. Waiting for NAS worker heartbeat.";return true;
}

void NasResearchPollJob()
{
   if(g_nasResearchJob==""||g_nasResearchJobConfig!=NasLibraryConfig())return;
   string text,a[];
   if(!NasLibraryRead("NasML\\Jobs\\"+g_nasResearchJob+".status",text)||StringSplit(text,'\n',a)<4)return;
   double pct;if(!NasMlNumber(a[1],pct))return;
   double progress=MathMax(0,MathMin(100,pct));string status=a[0]+": "+a[2];
   if(progress==g_nasResearchProgress&&status==g_nasLibraryStatus)return;
   g_nasResearchProgress=progress;g_nasLibraryStatus=status;
   if(g_nasLibraryOpen)
   {
      // Updating progress must not overwrite unfinished search/name edits.
      NasLibraryDrawResearch();
      ObjectSetString(0,NAS_LIB_PREFIX+"STATUS",OBJPROP_TEXT,StringSubstr(status,0,122));
      ObjectSetString(0,NAS_LIB_PREFIX+"STATUS",OBJPROP_TOOLTIP,status);ChartRedraw(0);
   }
}

bool NasLibraryModelReady()
{
   string config=NasLibraryConfig();
   return g_nasLibraryModelMode==0?(g_nasLibraryNetwork.ready&&g_nasLibraryNetwork.config==config)
      :(g_nasLibrarySlot.ready&&g_nasLibrarySlot.manifest.config==config);
}

bool NasLibraryLiveFilter(const MqlRates &rates[],const NasPoint &p[],int i,int direction,bool historical=false)
{
   if(g_nasLibraryExport)return historical;
   if(!g_nasLibraryMlEnabled)return true;
   if(!NasLibraryModelReady())
   {g_nasLibraryStatus="ML BLOCK: model/config mismatch. Reapply or explicitly turn ML OFF.";return false;}
   datetime available=rates[i].time+PeriodSeconds(_Period);
   if(g_nasLibraryModelMode==0&&!historical&&available<=g_nasLibraryNetwork.lastLabelTime)
   {g_nasLibraryStatus="ML BLOCK: signal predates training cutoff.";return false;}
   double features[],probability;string reason;
   if(!NasLibraryFeatures(rates,i,p[i],direction,features,reason))
   {g_nasLibraryStatus="ML BLOCK: "+reason;return false;}
   if(g_nasLibraryModelMode==1)
   {
      if(historical&&g_nasLibrarySlot.manifest.provider=="ORB_MLP1")
      {
         // Explicitly retrospective; never presented as forward performance.
         return NasMlPredict(g_nasLibrarySlot.mlp,features,probability)&&probability>=g_nasLibrarySlot.mlp.threshold;
      }
      if(!NasSlotScore(g_nasLibrarySlot,features,available,probability,reason))
      {g_nasLibraryStatus="ML BLOCK: "+reason;return false;}
      return reason=="ALLOW";
   }
   if(!NasMlPredict(g_nasLibraryNetwork,features,probability))return false;
   return probability>=g_nasLibraryNetwork.threshold;
}

void NasLibraryResearchEvent(const string key)
{
   if(key=="EXPORT")NasResearchStart();
   else if(key=="CANCEL")NasResearchAbort("CSV cancelled; incomplete data cannot train.");
   else if(key=="CANCELTRAIN"&&g_nasResearchJob!="")
   {NasLibraryWrite("NasML\\Jobs\\"+g_nasResearchJob+".cancel","1");g_nasLibraryStatus="Training cancellation requested; current model unchanged.";}
   else if(key=="TRAIN")NasResearchTrain();
   else if(key=="MODEL"&&!NasLibraryBusy())
   {g_nasLibraryModelMode=1-g_nasLibraryModelMode;g_nasLibraryMlEnabled=false;g_nasLibraryNetwork.ready=false;g_nasLibrarySlot.ready=false;g_nasResearchJob="";}
   else if(key=="USE"&&!NasLibraryBusy()&&NasLibrarySelectedClean())
   {
      string config=NasLibraryConfig(),text,reason;
      g_nasLibraryMlEnabled=false;g_nasLibraryNetwork.ready=false;g_nasLibrarySlot.ready=false;
      if(g_nasLibraryModelMode==1)
      {
         NasSlotManifest m;string hash;
         string id=g_nasLibrary[g_nasLibrarySelected].id;
         if(!NasSlotActive(id,m,reason)||m.config!=config||m.symbol!=_Symbol||m.broker!=AccountInfoString(ACCOUNT_SERVER)
            ||m.tf!=PeriodSeconds(_Period)/60||m.runtimeHash!=NAS_LIBRARY_SOURCE_HASH
            ||!NasSlotRead("NasML\\Slots\\Artifacts\\"+m.artifact+".model",1000000,text,hash,reason)
            ||!NasSlotModelParse(m,text,g_nasLibrarySlot,reason))
         {g_nasLibrarySlot.ready=false;g_nasLibraryStatus="No compatible champion slot: "+reason;return;}
         g_nasLibraryStatus="Champion "+m.revision+" pinned. ML OFF; history scores include training data.";
         return;
      }
      string path="NasML\\Models\\"+(string)g_nasLibraryModelMode+"\\"+config+".model";
      if(!NasLibraryRead(path,text)||!NasMlParseModel(text,config,g_nasLibraryNetwork,reason))
      {g_nasLibraryStatus="No qualified NAS model for this strategy/mode: "+reason;return;}
      g_nasLibraryStatus="Model loaded; enable ML explicitly. Historical training-period results are IN-SAMPLE.";
   }
   else if(key=="ML"&&!NasLibraryBusy())
   {
      if(!g_nasLibraryMlEnabled&&!NasLibraryModelReady())
      {g_nasLibraryStatus="Load a matching qualified NAS model first.";return;}
      g_nasLibraryMlEnabled=!g_nasLibraryMlEnabled;ArrayFree(g_historySimCache);RequestHistoryRefresh();
   }
}
#endif
