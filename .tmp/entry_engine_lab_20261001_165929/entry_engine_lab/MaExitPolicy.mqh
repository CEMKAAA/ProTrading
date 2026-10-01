#ifndef MA_EXIT_POLICY_MQH
#define MA_EXIT_POLICY_MQH
bool g_maReverseExit=true;
int g_maReverseWait=0;

// A closed kernel event is available at the next bar boundary. Pre-entry
// events never close a position; only the latest state survives the grace.
datetime MaKernelExitAt(const MaCrossAuditEvent &events[],datetime opened,int direction,
                       datetime until,int waitMinutes,int seconds,bool invert)
{
   datetime eligible=opened+(datetime)(MathMax(0,waitMinutes)*60);
   int lo=0,hi=ArraySize(events);
   while(lo<hi){int mid=(lo+hi)/2;if(events[mid].signalTime+seconds<=opened)lo=mid+1;else hi=mid;}
   int state=0;
   for(int i=lo;i<ArraySize(events);i++)
   {
      datetime at=events[i].signalTime+seconds;
      if(at>until)break;
      int dir=events[i].direction*(invert?-1:1);
      if(at<=eligible){state=dir;continue;}
      if(state==-direction&&eligible<=until)return eligible;
      if(dir==-direction)return at;
      state=dir;
   }
   return state==-direction&&eligible<=until?eligible:0;
}

string MaExitSettingsKey(){return "ENTRYLAB_EXIT."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
void MaExitLoad()
{
   g_maReverseExit=!InpIndependentEntries;
   string key=MaExitSettingsKey();
   if(GlobalVariableCheck(key+".ON"))g_maReverseExit=GlobalVariableGet(key+".ON")>0.5;
   if(GlobalVariableCheck(key+".WAIT"))g_maReverseWait=(int)MathMax(0,MathMin(5999,GlobalVariableGet(key+".WAIT")));
}
void MaExitSave()
{
   string key=MaExitSettingsKey();
   GlobalVariableSet(key+".ON",g_maReverseExit?1:0);
   GlobalVariableSet(key+".WAIT",g_maReverseWait);GlobalVariablesFlush();
}

MaCrossAuditEvent g_maLiveExitEvents[];
datetime g_maLiveExitClosed=0,g_maLiveExitFrom=0;
string g_maLiveExitKey="";
// Preserve already resolved asynchronous exit candidates across polls. This
// avoids repeatedly replaying/evicting the first 256 flow snapshots on a long hold.
string g_maExitBuildKey="";
datetime g_maExitBuildFrom=0,g_maExitBuildClosed=0,g_maExitBuildThrough=0;
bool MaExitAcceptedEvent(const MqlRates &bar,double priorVolume,datetime now,datetime &available)
{
   string raw="",reason="",detail="";
   // Caller supplies the raw direction through the last event slot.
   int last=ArraySize(g_maLiveExitEvents)-1;
   raw=g_maLiveExitEvents[last].direction>0?"BUY":"SELL";
   MqlDateTime dt;TimeToStruct(ServerToSessionLocal(bar.time),dt);
   if(!EntryWindowAllowsAt(OrbSignalAvailableTime(bar.time))||!HistCheckDay(dt.day_of_week,reason)
      ||!HistCheckVol((double)bar.tick_volume,priorVolume,reason))return false;
   datetime end=MathMin(now,bar.time+86400);
   if(!ModernFilterAllows(bar.time,end,g_rtSignalTf,bar.time,raw,g_rtDisplacement,g_rtFvgMode,reason,detail))return false;
   datetime entry=bar.time;double price=bar.close;
   bool savedCache=g_histNasCacheActive;g_histNasCacheActive=false;
   bool allowed=ResolveHistoricalEntry(g_rtEntryMode,raw,bar.time,bar.close,bar.high,bar.low,end,entry,price,detail);
   g_histNasCacheActive=savedCache;
   if(!allowed)return false;
   available=OrbSignalAvailableTime(entry);if(available>now)return false;
   double oldHi=g_orbHigh,oldLo=g_orbLow;datetime os=g_orbStartServer,oe=g_orbEndServer,te=g_tradeEndServer;
   g_orbHigh=bar.high;g_orbLow=bar.low;g_orbStartServer=bar.time;g_orbEndServer=bar.time;g_tradeEndServer=end;
   bool sourceBuy=raw=="BUY",buy=EffectiveOrbDirection(raw)=="BUY";double sl=0,risk=0;
   double buffer=InpSlBufferPoints*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   allowed=ResolveExecutionStop(sourceBuy,buy,price,sourceBuy?bar.low-buffer:bar.high+buffer,sl,risk,detail);
   g_orbHigh=oldHi;g_orbLow=oldLo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;
   if(!allowed)return false;
   RegimeV3Snapshot regime;int bucket=OrbRegimeBucketAt(bar.time,regime),rule=-1;string code="";
   return OrbRegimeAllowed(bucket)&&OrbRfEvaluate(raw,regime,rule,code,detail);
}
bool MaExitLoadKernel(datetime from)
{
   datetime closed=iTime(_Symbol,g_rtSignalTf,1),seed=McHistorySeed(_Symbol,g_rtSignalTf);
   string key=(string)g_rtSignalTf+"|"+(string)g_rtMaCrossMode+"|"+(string)g_rtMaCrossPair+"|"+(string)seed
      +"|"+(string)McHistorySeed(_Symbol,PERIOD_H4)+"|"+(string)g_maIndependent;
   if(g_rtMaCrossMode==MA_CROSS_LAB_RULES)key+="|"+LabEngineIdentity();
   if(!g_maIndependent)key+="|"+OrbUserRuntimeMetricKey();
   if(closed==g_maLiveExitClosed&&key==g_maLiveExitKey&&from>=g_maLiveExitFrom)return true;
   MqlRates rates[],higher[];ArraySetAsSeries(rates,false);ArraySetAsSeries(higher,false);
   ResetLastError();int n=CopyRates(_Symbol,g_rtSignalTf,seed,closed,rates);
   if(n<=0||GetLastError()!=0||rates[0].time!=seed||rates[n-1].time!=closed)return false;
   int seconds=PeriodSeconds(g_rtSignalTf);
   if(g_rtMaCrossMode==MA_CROSS_ORIGINAL_MTF)
   {
      datetime hs=McHistorySeed(_Symbol,PERIOD_H4);ResetLastError();
      int hn=CopyRates(_Symbol,PERIOD_H4,hs,closed+seconds-PeriodSeconds(PERIOD_H4),higher);
      if(hn<=0||GetLastError()!=0||higher[0].time!=hs)return false;
   }
   McPineKernel kernel;kernel.Reset(g_rtMaCrossMode,g_rtMaCrossPair,InpMaFastLength,InpMaMediumLength,InpMaSlowLength);
   McRollingHma hma;hma.Reset(200);double hv=0,volumeSum=0;int h=0;
   bool resume=g_mcOf.mode!=0&&!g_maIndependent&&g_maExitBuildKey==key
      &&g_maExitBuildFrom==from&&g_maExitBuildClosed==closed;
   if(!resume)
   {
      ArrayResize(g_maLiveExitEvents,0);g_maExitBuildThrough=0;
      ArrayResize(g_labLivePolicyBars,0);
      g_maExitBuildKey=key;g_maExitBuildFrom=from;g_maExitBuildClosed=closed;
   }
   for(int i=0;i<n;i++)
   {
      if(g_rtMaCrossMode==MA_CROSS_ORIGINAL_MTF)McFeedHtf(higher,h,rates[i].time+seconds,hma,hv);
      int dir=kernel.Push(rates[i],hv);
      if(LabPolicyEnabled()&&rates[i].time>=from)
      {int k=ArraySize(g_labLivePolicyBars);if(k==0||g_labLivePolicyBars[k-1].time<rates[i].time)
         {ArrayResize(g_labLivePolicyBars,k+1,4096);g_labLivePolicyBars[k].time=rates[i].time;
            g_labLivePolicyBars[k].atr=kernel.LabAtr();g_labLivePolicyBars[k].exits=kernel.LabExits();}}
      double priorVolume=i>0?volumeSum/MathMin(i,20):0;
      volumeSum+=(double)rates[i].tick_volume;if(i>=20)volumeSum-=(double)rates[i-20].tick_volume;
      if(dir==0||rates[i].time+seconds<=from)continue;
      if(resume&&rates[i].time<=g_maExitBuildThrough)continue;
      int k=ArraySize(g_maLiveExitEvents);ArrayResize(g_maLiveExitEvents,k+1,4096);
      g_maLiveExitEvents[k].signalTime=rates[i].time;g_maLiveExitEvents[k].direction=dir;
      if(!g_maIndependent)
      {
         if(g_mcOf.mode!=0)
         {
            string error="";
            if(McOfPrepare(_Symbol,g_rtSignalTf,rates[i].time,false,error,2)!=1)
            {
               // Missing asynchronous data is not a rejected market event.
               // Do not seal this exit cache until its required data is ready.
               ArrayResize(g_maLiveExitEvents,k);g_lastExecStatus=error;return false;
            }
         }
         datetime acceptedAt=0;
         g_maExitBuildThrough=rates[i].time;
         if(!MaExitAcceptedEvent(rates[i],priorVolume,TimeCurrent(),acceptedAt)){ArrayResize(g_maLiveExitEvents,k);continue;}
         g_maLiveExitEvents[k].signalTime=acceptedAt-seconds;
         // Retest/NAS confirmation can change event order; preserve availability order.
         for(int j=k;j>0&&g_maLiveExitEvents[j].signalTime<g_maLiveExitEvents[j-1].signalTime;j--)
         {MaCrossAuditEvent tmp=g_maLiveExitEvents[j-1];g_maLiveExitEvents[j-1]=g_maLiveExitEvents[j];g_maLiveExitEvents[j]=tmp;}
      }
   }
   g_maLiveExitClosed=closed;g_maLiveExitFrom=from;g_maLiveExitKey=key;return true;
}

MaCrossAuditEvent g_maLiveNasExitEvents[];
datetime g_maLiveNasClosed=0,g_maLiveNasFrom=0;
string g_maLiveNasKey="";
bool MaExitLoadNas(datetime from,datetime now)
{
   ENUM_TIMEFRAMES tf=NasConfirmationTf();datetime closed=iTime(_Symbol,tf,1);
   NasSettings settings=BuildOrbNasSettings();
   string key=(string)tf+"|"+(string)settings.sensitivity+"|"+(string)settings.rsiLength+"|"
      +(string)settings.atrRisk+"|"+(string)settings.atrLen+"|"+(string)g_rtNasFlowVolumeFilter+"|"+(string)g_rtNasFlowVolumeMultiplier
      +"|"+(string)McHistorySeed(_Symbol,tf);
   if(closed==g_maLiveNasClosed&&key==g_maLiveNasKey&&from>=g_maLiveNasFrom)return true;
   int shift=iBarShift(_Symbol,tf,from,false);if(shift<0||closed<=0)return false;
   MqlRates rates[];
   ResetLastError();int n=LoadOrbNasRatesThrough(rates,tf,now,shift+NasCalcWarmupBars()+2);
   if(n<20||GetLastError()!=0||rates[0].time>from)return false;
   NasPoint points[];if(NAS_Calculate(rates,n,settings,points)!=n)return false;
   ArrayResize(g_maLiveNasExitEvents,0);
   for(int i=1;i<=n-2;i++)
   {
      datetime at=OrbNasSignalAvailableTime(rates,n,i);
      if(at<=from||at>now||points[i].buy==points[i].sell)continue;
      string reason="";double vol=0,avg=0;
      if(!OrbNasFlowVolumeFilterAllows(rates,i,reason,vol,avg))continue;
      int k=ArraySize(g_maLiveNasExitEvents);ArrayResize(g_maLiveNasExitEvents,k+1,4096);
      // NAS availability follows the next existing bar, including market gaps.
      g_maLiveNasExitEvents[k].signalTime=at;g_maLiveNasExitEvents[k].direction=points[i].buy?1:-1;
   }
   g_maLiveNasClosed=closed;g_maLiveNasFrom=from;g_maLiveNasKey=key;return true;
}

datetime MaLiveExitAt(datetime opened,int dir,datetime now,string &reason)
{
   datetime exitAt=0;reason="";
   if(LabPolicyEnabled()&&MaExitLoadKernel(opened-PeriodSeconds(g_rtSignalTf)))
      exitAt=LabPolicyExitFrom(g_labLivePolicyBars,opened,dir,now,reason);
   if(g_maReverseExit&&(g_maIndependent||g_maReverseWait>0)&&MaExitLoadKernel(opened))
   {
      exitAt=MaKernelExitAt(g_maLiveExitEvents,opened,dir,now,g_maReverseWait,PeriodSeconds(g_rtSignalTf),g_rtInvertMode);
      if(exitAt>0)reason="ma_reverse_exit";
   }
   if(RuntimeNasExitEnabled()&&MaExitLoadNas(opened,now))
   {
      // The live cache is separate from timer-sliced historical replay.
      datetime at=MaKernelExitAt(g_maLiveNasExitEvents,opened,dir,now,g_rtNasOppositeExitWaitMinutes,0,false);
      if(at>0&&(exitAt==0||at<exitAt))
      {exitAt=at;reason=g_rtNasAdditionalExit?"nas_additional_exit":"nas_opposite_exit";}
   }
   return exitAt;
}

string MaBridgeExitKey()
{
   return "MA_BX."+StringSubstr(OrbMlSha256(AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)
      +"|"+_Symbol+"|"+(string)RuntimeMagic()+"|"+(string)g_orbBridgePlanTime),0,40);
}

// Persist close intent per owned position, not per direction/account. A failed
// close remains retryable across restarts even if the next signal changes side.
bool MaProcessExitManagement()
{
   if(g_labPreviewOnly)return false;
   if(g_rtAdvancedReverse&&OwnPositionExists())return false;
   static ulong lastAttempt=0;static bool pending=false;
   if(GetTickCount64()-lastAttempt<(ulong)(pending?5000:1000))return pending;
   lastAttempt=GetTickCount64();pending=false;
   if(!g_maIndependent&&g_nasManagedClosePending&&!CloseNasManagedLifecycle())return true;
   datetime earliest=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      if(earliest==0||opened<earliest)earliest=opened;
   }
   if(earliest>0)
   {
      if(g_maReverseExit&&(g_maIndependent||g_maReverseWait>0))MaExitLoadKernel(earliest);
      if(RuntimeNasExitEnabled())MaExitLoadNas(earliest,TimeCurrent());
   }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      long id=PositionGetInteger(POSITION_IDENTIFIER);
      string key="MA_X."+StringSubstr(OrbMlSha256(AccountInfoString(ACCOUNT_SERVER)+"|"
         +(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+(string)id),0,40);
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);string reason="";
      bool intent=GlobalVariableCheck(key);
      if(!intent&&MaLiveExitAt(opened,dir,TimeCurrent(),reason)<=0)continue;
      if(!intent){if(GlobalVariableSet(key,(double)TimeCurrent())==0){pending=true;continue;}GlobalVariablesFlush();}
      bool published=true;
      string bridgeKey=MaBridgeExitKey();
      if(!g_maIndependent&&g_orbBridgePlanActive)
      {
         if(!GlobalVariableCheck(bridgeKey))
         {if(GlobalVariableSet(bridgeKey,(double)TimeCurrent())==0){pending=true;continue;}GlobalVariablesFlush();}
         published=OrbProPublishCloseOnly(dir,"ma_managed_exit",true);
      }
      bool sent=trade.PositionClose(ticket);
      bool closed=sent&&trade.ResultRetcode()==TRADE_RETCODE_DONE&&!PositionSelectByTicket(ticket);
      Audit(closed?"ma_managed_exit_closed":"ma_managed_exit_retry",dir>0?"BUY":"SELL",0,0,0,0,
         "ticket="+(string)ticket+" reason="+reason+" retcode="+(string)trade.ResultRetcode());
      if(closed)GlobalVariableDel(key);else pending=true;
      if(published&&closed&&!g_maIndependent&&!OwnPositionExists())
      {GlobalVariableDel(bridgeKey);ClearOrbBridgePlan();ClearNasManagedLifecycle("ma_exit_complete");g_tradeDir=0;g_tradeOpenTime=0;}
   }
   // Bridge-only has no native ticket; identify its existing plan by start time.
   if(!g_maIndependent&&g_orbBridgePlanActive&&!OwnPositionExists())
   {
      int dir=CurrentOrbLifecycleDirection();datetime opened=CurrentOrbLifecycleStartTime();
      string key=MaBridgeExitKey();
      string reason="";bool intent=GlobalVariableCheck(key);
      if(intent||MaLiveExitAt(opened,dir,TimeCurrent(),reason)>0)
      {
         if(!intent){if(GlobalVariableSet(key,(double)TimeCurrent())==0)return true;GlobalVariablesFlush();}
         if(OrbProPublishCloseOnly(dir,"ma_managed_exit",true))
         {GlobalVariableDel(key);ClearOrbBridgePlan();ClearNasManagedLifecycle("ma_exit_complete");g_tradeDir=0;g_tradeOpenTime=0;}
         else pending=true;
      }
   }
   return pending;
}
#endif
