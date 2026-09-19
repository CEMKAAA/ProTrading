#ifndef MA_EXIT_POLICY_MQH
#define MA_EXIT_POLICY_MQH
bool g_maReverseExit=false;
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

string MaExitSettingsKey(){return "MA_EXIT."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
void MaExitLoad()
{
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
bool MaExitLoadKernel(datetime from)
{
   datetime closed=iTime(_Symbol,g_rtSignalTf,1),seed=McHistorySeed(_Symbol,g_rtSignalTf);
   string key=(string)g_rtSignalTf+"|"+(string)g_rtMaCrossMode+"|"+(string)g_rtMaCrossPair+"|"+(string)seed
      +"|"+(string)McHistorySeed(_Symbol,PERIOD_H4);
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
   McRollingHma hma;hma.Reset(200);double hv=0;int h=0;
   ArrayResize(g_maLiveExitEvents,0);
   for(int i=0;i<n;i++)
   {
      if(g_rtMaCrossMode==MA_CROSS_ORIGINAL_MTF)McFeedHtf(higher,h,rates[i].time+seconds,hma,hv);
      int dir=kernel.Push(rates[i],hv);
      if(dir==0||rates[i].time+seconds<=from)continue;
      int k=ArraySize(g_maLiveExitEvents);ArrayResize(g_maLiveExitEvents,k+1,4096);
      g_maLiveExitEvents[k].signalTime=rates[i].time;g_maLiveExitEvents[k].direction=dir;
   }
   g_maLiveExitClosed=closed;g_maLiveExitFrom=from;g_maLiveExitKey=key;return true;
}

datetime MaLiveExitAt(datetime opened,int dir,datetime now,string &reason)
{
   datetime exitAt=0;reason="";
   if(g_maReverseExit&&MaExitLoadKernel(opened))
   {
      exitAt=MaKernelExitAt(g_maLiveExitEvents,opened,dir,now,g_maReverseWait,PeriodSeconds(g_rtSignalTf),g_rtInvertMode);
      if(exitAt>0)reason="ma_reverse_exit";
   }
   if(RuntimeNasExitEnabled())
   {
      // Historical replay can be suspended between timer slices. Never let its
      // older cache pretend to be the live NAS signal source.
      bool saved=g_histNasCacheActive;g_histNasCacheActive=false;
      datetime bar=0,at=0;double price=0;string detail="";
      bool found=FindNasOppositeExitWithGrace(dir,opened,now,bar,at,price,detail);
      g_histNasCacheActive=saved;
      if(found&&at>0&&(exitAt==0||at<exitAt))
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
   static ulong lastAttempt=0;static bool pending=false;
   if(GetTickCount64()-lastAttempt<1000)return pending;
   lastAttempt=GetTickCount64();pending=false;
   if(!g_maIndependent&&g_nasManagedClosePending&&!CloseNasManagedLifecycle())return true;
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
