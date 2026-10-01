#ifndef LAB_POLICY_RUNTIME_MQH
#define LAB_POLICY_RUNTIME_MQH
datetime g_labHistLastClose=0,g_labNativeLastClose=0,g_labNativeHistoryBar=0;
bool LabPolicyEnabled(){return g_rtMaCrossMode==MA_CROSS_LAB_RULES&&g_labEngine.policy;}
int LabPolicyFirstIn(const LabPolicyBar &bars[],datetime at)
{int lo=0,hi=ArraySize(bars);while(lo<hi){int mid=(lo+hi)/2;if(bars[mid].time<at)lo=mid+1;else hi=mid;}return lo;}
int LabPolicyFirst(datetime at){return LabPolicyFirstIn(g_labPolicyBars,at);}
bool LabPolicyGeometryAt(datetime bar)
{
   g_labGeometryAtr=0;if(!LabPolicyEnabled())return true;
   int i=LabPolicyFirst(bar);if(i>=ArraySize(g_labPolicyBars)||g_labPolicyBars[i].time!=bar)return false;
   double atr=g_labPolicyBars[i].atr;if(atr==EMPTY_VALUE||!MathIsValidNumber(atr)||atr<=0)return false;
   g_labGeometryAtr=atr;return true;
}
bool LabPolicyShape(string &reason)
{
   reason="";if(!LabPolicyEnabled())return true;
   if(InpExecutionMode!=ORB_EXEC_SINGLE||g_rtEntryMode!=ORB_ENTRY_BREAKOUT||g_rtExitMode!=ORB_EXIT_FIXED_TARGET
      ||g_rtTargetMode!=ORB_TARGET_R_LEG||g_maIndependent||RuntimeHalfBeLeg()>0||g_rtBEOnTp1)
   {reason="LAB POLICY requires LEGACY SINGLE FIXED R, HC/BE OFF, BREAK entry";return false;}
   return true;
}
bool LabCooldownAllows(datetime candidate,datetime lastClose)
{
   if(!LabPolicyEnabled()||g_labEngine.cooldown==0||lastClose==0)return true;
   if(candidate<lastClose)return false;
   int a=iBarShift(_Symbol,g_rtSignalTf,lastClose,false),b=iBarShift(_Symbol,g_rtSignalTf,candidate,false);
   return a>=0&&b>=0&&a-b>=g_labEngine.cooldown;
}
datetime LabPolicyExitFrom(const LabPolicyBar &bars[],datetime opened,int direction,datetime until,string &reason)
{
   reason="";if(!LabPolicyEnabled())return 0;
   int seconds=PeriodSeconds(g_rtSignalTf);if(seconds<1)return 0;
   datetime result=0;
   if(g_labEngine.maxMinutes>0){datetime at=opened+(datetime)(g_labEngine.maxMinutes*60);
      if(at<=until){result=at;reason="LAB_TIME_EXIT";}}
   int completed=0,mask=direction>0?1:2;
   for(int i=LabPolicyFirstIn(bars,opened-seconds+1);i<ArraySize(bars);i++)
   {
      datetime at=bars[i].time+seconds;
      if(at<=opened)continue;if(at>until||(result>0&&at>=result))break;
      completed++;
      if((bars[i].exits&mask)!=0){result=at;reason="LAB_RULE_EXIT";break;}
      if(g_labEngine.maxBars>0&&completed>=g_labEngine.maxBars){result=at;reason="LAB_TIME_EXIT";break;}
   }
   return result;
}
datetime LabPolicyExitAt(datetime opened,int direction,datetime until,string &reason)
{return LabPolicyExitFrom(g_labPolicyBars,opened,direction,until,reason);}
void LabPolicyMergeTickExit(datetime filled,int direction,datetime until,datetime &exitAt,string &reason)
{
   if(!LabPolicyEnabled())return;
   string label="";datetime at=LabPolicyExitAt(filled,direction,until,label);
   if(at>0&&(exitAt==0||at<exitAt)){exitAt=at;reason=label;}
}
bool LabNativeEntryPolicy(datetime signalBar)
{
   if(!LabPolicyEnabled())return true;
   string reason="";if(!LabPolicyShape(reason)){g_lastExecStatus=reason;return false;}
   // This family has no verified listener implementation for time/rule exits.
   if(g_orbBridgeEnabled||!g_orbNativeWithBridgeOnly){g_lastExecStatus="LAB POLICY is MT5 native only; PUB must be OFF, NAT ON";return false;}
   if(!MaExitLoadKernel(signalBar))
   {g_lastExecStatus="LAB ATR DATA unavailable";return false;}
   int index=LabPolicyFirstIn(g_labLivePolicyBars,signalBar);
   if(index>=ArraySize(g_labLivePolicyBars)||g_labLivePolicyBars[index].time!=signalBar
      ||g_labLivePolicyBars[index].atr==EMPTY_VALUE||g_labLivePolicyBars[index].atr<=0)
   {g_lastExecStatus="LAB ATR DATA unavailable";return false;}
   g_labGeometryAtr=g_labLivePolicyBars[index].atr;
   if(g_labEngine.cooldown==0)return true;
   if(g_labNativeHistoryBar!=signalBar)
   {
      if(!HistorySelect(0,TimeCurrent())){g_lastExecStatus="LAB cooldown history unavailable";return false;}
      datetime last=0;
      for(int i=HistoryDealsTotal()-1;i>=0;i--){ulong ticket=HistoryDealGetTicket(i);if(ticket==0)continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol||!MagicOwned((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)))continue;
         long kind=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(kind==DEAL_ENTRY_OUT||kind==DEAL_ENTRY_OUT_BY||kind==DEAL_ENTRY_INOUT){last=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);break;}}
      g_labNativeLastClose=last;g_labNativeHistoryBar=signalBar;
   }
   if(!LabCooldownAllows(OrbSignalAvailableTime(signalBar),g_labNativeLastClose)){g_lastExecStatus="LAB COOLDOWN";return false;}
   return true;
}
#endif
