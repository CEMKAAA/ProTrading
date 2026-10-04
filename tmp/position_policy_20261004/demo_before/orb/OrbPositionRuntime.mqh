#ifndef ORB_POSITION_RUNTIME_MQH
#define ORB_POSITION_RUNTIME_MQH
OrbWindowSignal g_orbPositionLiveEvents[];
string g_orbPositionShown="";
int OrbPositionNativeCount(int direction=0)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(direction==0||dir==direction)count++;
   }
   return count;
}
bool OrbPositionNativeCompatible()
{
   return g_orbNativeWithBridgeOnly&&!g_orbBridgeEnabled
      &&AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING
      &&InpExecutionMode==ORB_EXEC_SINGLE;
}
void OrbPositionObserve(string direction,datetime at)
{
   int n=ArraySize(g_orbPositionLiveEvents);
   if(at<=0||(n>0&&at<g_orbPositionLiveEvents[n-1].availableTime))return;
   if(n>0&&g_orbPositionLiveEvents[n-1].availableTime==at
      &&g_orbPositionLiveEvents[n-1].executionDirection==direction)return;
   ArrayResize(g_orbPositionLiveEvents,n+1,32);
   ZeroMemory(g_orbPositionLiveEvents[n]);
   g_orbPositionLiveEvents[n].availableTime=at;
   g_orbPositionLiveEvents[n].executionDirection=direction;
}
datetime OrbPositionExitFrom(const OrbWindowSignal &events[],datetime opened,string direction,datetime now)
{
   datetime at=0;string detail="";
   FindNewDayAcceptedReverseExit(events,opened,direction,now,at,detail);return at;
}
void OrbPositionGraceState(const OrbWindowSignal &events[],datetime opened,datetime through,datetime &seen,int &state)
{
   for(int e=FirstOrbSignalAfter(events,MathMax(opened,seen));e<ArraySize(events);e++)
   {
      datetime at=events[e].availableTime;if(at>through)break;
      seen=at;state=events[e].executionDirection=="BUY"?1:-1;
   }
}
datetime OrbPositionNextOpposite(const OrbWindowSignal &events[],datetime after,string direction,datetime now)
{
   for(int e=FirstOrbSignalAfter(events,after);e<ArraySize(events);e++)
   {
      if(events[e].availableTime>now)break;
      if(events[e].executionDirection!=direction)return events[e].availableTime;
   }
   return 0;
}
datetime OrbPositionObservedExit(datetime opened,string direction,datetime now,datetime &seen,int &state)
{
   bool historyReady=!g_histAuditRunning&&!g_histRedrawQueued;
   if(!g_orbPositions.reverse)
   {
      datetime at=OrbPositionExitFrom(g_orbPositionLiveEvents,opened,direction,now);
      datetime historical=historyReady?OrbPositionExitFrom(g_histAcceptedSignals,opened,direction,now):0;
      return at==0?historical:historical==0?at:MathMin(at,historical);
   }
   datetime eligible=opened+(datetime)(g_orbPositions.waitMinutes*60);
   if(seen>eligible){seen=opened;state=0;}
   // Combine the latest state across both streams before choosing a close.
   datetime through=MathMin(eligible,now);
   if(historyReady)OrbPositionGraceState(g_histAcceptedSignals,opened,through,seen,state);
   OrbPositionGraceState(g_orbPositionLiveEvents,opened,through,seen,state);
   int dir=direction=="BUY"?1:-1;
   if(now>=eligible&&state==-dir)return eligible;
   datetime at=OrbPositionNextOpposite(g_orbPositionLiveEvents,MathMax(opened,eligible),direction,now);
   datetime historical=historyReady?OrbPositionNextOpposite(g_histAcceptedSignals,MathMax(opened,eligible),direction,now):0;
   return at==0?historical:historical==0?at:MathMin(at,historical);
}
void OrbPositionManageReverse()
{
   if(!g_orbPositions.reverse&&!(g_orbPositions.independent&&g_orbPositions.nextDay))return;
   datetime now=TimeCurrent();
   if(!g_orbPositions.independent&&g_orbBridgePlanActive&&g_orbPositions.reverse)
   {
      datetime opened=CurrentOrbLifecycleStartTime();
      string direction=g_orbBridgePlanDir>0?"BUY":"SELL";
      datetime seen=opened;int state=0;
      datetime at=OrbPositionObservedExit(opened,direction,now,seen,state);
      if(at>opened&&at<=now&&OrbProPublishCloseOnly(g_orbBridgePlanDir,"orb_reverse_exit",true))
      {ClearOrbBridgePlan();ClearNasManagedLifecycle("orb_reverse_exit");}
   }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      string direction=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";
      // Persist the latest causal state during the grace period in the existing
      // position plan. A same-side event cancels an earlier opposite latch.
      datetime seen=(datetime)OrbProGet(pid,"revSeen",opened);
      int state=(int)OrbProGet(pid,"revState",0);
      int config=g_orbPositions.waitMinutes*4+(g_orbPositions.reverse?2:0)+(g_orbPositions.nextDay?1:0);
      if((int)OrbProGet(pid,"revCfg",-1)!=config)
      {seen=opened;state=0;OrbProSet(pid,"revPending",0);OrbProSet(pid,"revCfg",config);}
      datetime exitAt=OrbPositionObservedExit(opened,direction,now,seen,state);
      OrbProSet(pid,"revSeen",seen);OrbProSet(pid,"revState",state);
      int dir=direction=="BUY"?1:-1;
      datetime pending=(datetime)OrbProGet(pid,"revPending",0);
      if(pending>0)exitAt=pending;
      if(exitAt<=0||exitAt>now)continue;
      OrbProSet(pid,"revPending",exitAt);GlobalVariablesFlush();
      if(!g_orbPositions.independent&&g_orbBridgeEnabled)
         OrbProPublishCloseOnly(dir,"orb_reverse_exit",true);
      bool closed=trade.PositionClose(ticket)&&trade.ResultRetcode()==TRADE_RETCODE_DONE;
      Audit(closed?"orb_reverse_exit":"orb_reverse_exit_retry",direction,0,0,0,0,
         "ticket="+(string)ticket+" event="+FmtTime(exitAt)+" wait="+DurationMinutesText(g_orbPositions.waitMinutes));
   }
}
// Restrict the proven manager to one ticket and restore its scalar context.
// Broker SL/TP remain per position; trailing/half/time policies must also be.
void ManagePositions()
{
   if(!g_orbPositions.independent){ManagePositionScope();return;}
   int oldDir=g_tradeDir;datetime oldOpen=g_tradeOpenTime,oldEnd=g_tradeEndServer,oldBar=g_tradeLastDynamicExitBar;
   double oldEntry=g_tradeEntry,oldSl=g_tradeSl,oldRisk=g_tradeRisk,oldHigh=g_tradeBestHigh,oldLow=g_tradeBestLow;
   double oldTp[]={g_tradeTp1,g_tradeTp2,g_tradeTp3,g_tradeTp4,g_tradeTp5,g_tradeTp6};
   bool oldBe=g_beMoved,oldHalf=g_halfClosed;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      g_tradeDir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      g_tradeEntry=PositionGetDouble(POSITION_PRICE_OPEN);
      g_tradeSl=OrbProGet(pid,"sl",PositionGetDouble(POSITION_SL));g_tradeRisk=MathAbs(g_tradeEntry-g_tradeSl);
      g_tradeOpenTime=(datetime)PositionGetInteger(POSITION_TIME);
      g_tradeEndServer=(datetime)OrbProGet(pid,"endTs",oldEnd);
      g_beMoved=OrbProGet(pid,"beDone",0)>0.5;g_halfClosed=OrbProGet(pid,"halfDone",0)>0.5;
      g_tradeBestHigh=OrbProGet(pid,"bestHigh",g_tradeEntry);g_tradeBestLow=OrbProGet(pid,"bestLow",g_tradeEntry);
      g_tradeLastDynamicExitBar=(datetime)OrbProGet(pid,"dynamicBar",0);
      g_tradeTp1=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,1);g_tradeTp2=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,2);
      g_tradeTp3=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,3);g_tradeTp4=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,4);
      g_tradeTp5=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,5);g_tradeTp6=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,6);
      g_orbManagedTicket=ticket;
      ManagePositionScope();
      if(PositionSelectByTicket(ticket)&&RuntimeNasExitEnabled())
      {
         bool saved=g_histNasCacheActive;g_histNasCacheActive=false;
         datetime bar=0,at=0;double price=0;string detail="";
         datetime through=g_rtNasAdditionalExit?TimeCurrent():g_tradeEndServer;
         bool found=FindNasOppositeExitWithGrace(g_tradeDir,g_tradeOpenTime,MathMin(TimeCurrent(),through),bar,at,price,detail);
         g_histNasCacheActive=saved;
         if(found&&at>g_tradeOpenTime&&at<=TimeCurrent())trade.PositionClose(ticket);
      }
      if(PositionSelectByTicket(ticket))
      {
         OrbProSet(pid,"bestHigh",g_tradeBestHigh);OrbProSet(pid,"bestLow",g_tradeBestLow);
         OrbProSet(pid,"dynamicBar",g_tradeLastDynamicExitBar);OrbProSet(pid,"beDone",g_beMoved?1:0);
         OrbProSet(pid,"halfDone",g_halfClosed?1:0);
      }
      g_orbManagedTicket=0;
   }
   g_tradeDir=oldDir;g_tradeOpenTime=oldOpen;g_tradeEndServer=oldEnd;g_tradeLastDynamicExitBar=oldBar;
   g_tradeEntry=oldEntry;g_tradeSl=oldSl;g_tradeRisk=oldRisk;g_tradeBestHigh=oldHigh;g_tradeBestLow=oldLow;
   g_tradeTp1=oldTp[0];g_tradeTp2=oldTp[1];g_tradeTp3=oldTp[2];g_tradeTp4=oldTp[3];g_tradeTp5=oldTp[4];g_tradeTp6=oldTp[5];
   g_beMoved=oldBe;g_halfClosed=oldHalf;
}
void OrbPositionDraw()
{
   int x=InpDashboardX+656,y=InpDashboardY+310;
   CreateLabel("DASH_POS",x,y,"POSITIONS | MT5 native",C'90,178,255',8);
   CreateButton("BTN_POS_MODE",x,y+20,118,22,g_orbPositions.independent?"INDEPENDENT":"LEGACY",C'38,101,176');
   CreateLabel("DASH_POS_MAX",x+128,y+24,"MAX SAME",clrWhite,8);
   CreateEdit("EDIT_POS_MAX",x+203,y+20,50,22,(string)g_orbPositions.maxSameOpen);
   CreateLabel("DASH_POS_OPEN",x+265,y+24,"OPEN "+(string)OrbPositionNativeCount(1)+"B / "+(string)OrbPositionNativeCount(-1)+"S",clrWhite,8);
   CreateButton("BTN_POS_DAY",x+402,y+20,166,22,g_orbPositions.nextDay?"NEXT DAY EXIT ON":"NEXT DAY EXIT OFF",C'80,80,80');
   CreateButton("BTN_POS_REV",x,y+48,146,22,g_orbPositions.reverse?"MA REV EXIT ON":"MA REV EXIT OFF",g_orbPositions.reverse?C'184,103,22':C'80,80,80');
   CreateLabel("DASH_POS_WAIT",x+156,y+52,"WAIT HH:MM",clrWhite,8);
   CreateEdit("EDIT_POS_WAIT",x+253,y+48,65,22,DurationMinutesText(g_orbPositions.waitMinutes));
   CreateButton("BTN_POS_APPLY",x+330,y+48,110,22,"APPLY EXIT",C'38,101,176');
   string packed=OrbPositionPack(g_orbPositions);
   if(packed!=g_orbPositionShown)
   {
      ObjectSetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT,(string)g_orbPositions.maxSameOpen);
      ObjectSetString(0,PREFIX+"EDIT_POS_WAIT",OBJPROP_TEXT,DurationMinutesText(g_orbPositions.waitMinutes));
      g_orbPositionShown=packed;
   }
}
bool OrbPositionEvent(string object)
{
   if(object!=PREFIX+"BTN_POS_MODE"&&object!=PREFIX+"BTN_POS_DAY"
      &&object!=PREFIX+"BTN_POS_REV"&&object!=PREFIX+"BTN_POS_APPLY")return false;
   OrbPositionPolicy previous=g_orbPositions,next=previous;int wait=0;
   string maximum=ObjectGetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT);
   int cap=(int)StringToInteger(maximum);
   if((string)cap!=maximum||cap<1||cap>100
      ||!OrbPositionWaitRead(ObjectGetString(0,PREFIX+"EDIT_POS_WAIT",OBJPROP_TEXT),wait))
   {g_lastExecStatus="POSITION_FIELDS_INVALID";return true;}
   next.maxSameOpen=cap;next.waitMinutes=wait;
   if(object==PREFIX+"BTN_POS_MODE")next.independent=!next.independent;
   if(object==PREFIX+"BTN_POS_DAY")next.nextDay=!next.nextDay;
   if(object==PREFIX+"BTN_POS_REV")next.reverse=!next.reverse;
   if(previous.independent&&!next.independent&&OrbPositionNativeCount()>1)
   {g_lastExecStatus="CLOSE_EXTRA_POSITIONS_BEFORE_LEGACY";return true;}
   g_orbPositions=next;
   if(!OrbPositionSave()){g_orbPositions=previous;g_lastExecStatus="POSITION_SAVE_FAILED";return true;}
   ClearNewDayReverseRetry("position_policy_changed");
   CancelHistoricalAuditBuild();QueueHistoricalRedraw(0);g_lastExecStatus="POSITION_SETTINGS_APPLIED";
   return true;
}
#endif
