void CheckOpenCapacity()
{
   bool saved=g_maIndependent;int limit=g_maMaxConsecutive;
   g_maIndependent=true;g_maMaxConsecutive=10;MaHistoricalCapacityReset();
   datetime t=D'2026.09.01 09:00';
   for(int i=0;i<10;i++){Check(MaHistoricalCapacityAllows(t+i),"capacity before slot "+(string)i);MaHistoricalCapacityOccupy(t+100+(9-i)*10);}
   Check(!MaHistoricalCapacityAllows(t+99)&&g_maHistOpenCount==10,"mixed direction cannot reset full total capacity");
   Check(MaHistoricalCapacityAllows(t+100)&&g_maHistOpenCount==9,"actual exit frees one slot at boundary");
   MaHistoricalCapacityOccupy(t+1000);Check(!MaHistoricalCapacityAllows(t+101),"replacement consumes freed slot");
   MaHistoricalCapacityRelease(t+190);Check(g_maHistOpenCount==1,"unsorted exits released by earliest exit heap");
   Check(MaOpenCounterText(7)=="OPEN 7/10","counter current over applied capacity");
   g_maMaxConsecutive=1;Check(!MaHistoricalCapacityAllows(t+999)&&MaHistoricalCapacityAllows(t+1000),"remaining open slot blocks MAX 1 then releases");
   Check(!MaOpenCapacityAllows(10,10)&&MaOpenCapacityAllows(9,10)&&!MaOpenCapacityAllows(0,0),"native total capacity boundary");
   MaHistoricalCapacityReset();for(int i=0;i<1000;i++)MaHistoricalCapacityOccupy(t+1000-i);
   Check(g_maHistOpenCount==1000,"maximum 1000 heap slots");MaHistoricalCapacityRelease(t+500);
   Check(g_maHistOpenCount==500,"heap releases 500 closed slots");MaHistoricalCapacityRelease(t+1000);
   Check(g_maHistOpenCount==0,"all positions closed restores full allowance");
   g_maMaxConsecutive=10;MaRenderOpenCounter(true);
   Check(ObjectGetString(0,PREFIX+"DASH_MA_OPEN",OBJPROP_TEXT)==MaOpenCounterText(MaNativeOpenCount()),"native counter reads instance-owned positions");
   g_maMaxConsecutive=3;MaRenderOpenCounter();
   Check(ObjectGetString(0,PREFIX+"DASH_MA_OPEN",OBJPROP_TEXT)==MaOpenCounterText(MaNativeOpenCount()),"counter updates denominator without full dashboard redraw");
   g_maIndependent=false;Check(MaOpenCounterText(1)=="OPEN 1/1","legacy counter uses single slot");
   Check(MaEntryMetricMeta(true,10)!="|MAENTRY1=1,10"&&MaEntryMetricMeta(false,1)=="","independent metric cache revised, legacy preserved");
   g_maIndependent=saved;g_maMaxConsecutive=limit;MaHistoricalCapacityReset();
}
void CheckCapacityAuditIntervals(string context)
{
   datetime exits[];int count=0,peak=0;bool correct=true;
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade item=g_axTrades[i];if(!item.valid)continue;
      datetime at=AxEntryAt(item.entryTime,item.availableTime);int remaining=0;
      for(int j=0;j<count;j++)if(exits[j]>at)exits[remaining++]=exits[j];count=remaining;
      ArrayResize(exits,count+1);exits[count++]=item.closed&&item.exitTime>0?item.exitTime:g_histRunNow+1;
      peak=MathMax(peak,count);if(count>g_maMaxConsecutive)correct=false;
   }
   Check(correct&&g_histOpen<=g_maMaxConsecutive,"interval occupancy / final OPEN <= MAX "+context);
   Print("CAPACITY_RESULT ",context," max=",g_maMaxConsecutive," trades=",g_histTotal," O=",g_histOpen," peak=",peak," DATA=",g_histInvalid);
}
void CheckLabCapacityAudit()
{
   LabEngine engine=MakeEngine();engine.name="Concurrent capacity audit fixture";engine.edge=false;
   engine.buy[0].feature=4;engine.buy[0].compare=0;engine.buy[0].threshold=50;
   engine.sell[0]=engine.buy[0];engine.sell[0].compare=1;g_labEngine=engine;
   g_rtMaCrossMode=MA_CROSS_LAB_RULES;g_labPreviewOnly=true;g_rtSignalTf=PERIOD_M5;
   g_rtAdvancedAuditEngine=true;g_maIndependent=true;g_maReverseExit=false;g_maMaxConsecutive=10;
   g_rtCustomR=1;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;g_rtPipSlMode=true;g_rtPipSlPips=8000;
   g_probeClock=TimeCurrent();MaCrossAuditInvalidate();g_orbReplayMemo.Reset("CAPACITY10");
   Check(RunAudit(5),"5W MAX10 capacity tick audit");CheckCapacityAuditIntervals("LAB 5W MAX10");
   Check(g_histTotal==10&&g_histOpen==10,"wide geometry saturates ten slots, not repeated directional series");
   g_maMaxConsecutive=3;Check(RunAudit(5),"5W MAX3 capacity audit");CheckCapacityAuditIntervals("LAB 5W MAX3");
   Check(g_histTotal==3&&g_histOpen==3,"lower audit limit recomputes admissions");
   Check(RunAudit(2),"capacity narrow warm window");string warm=AuditIdentity();
   g_orbReplayMemo.Reset("CAPACITY_COLD");MaCrossAuditInvalidate();DeleteHist();
   Check(RunAudit(2)&&warm==AuditIdentity(),"concurrent capacity warm/cold window parity");
   g_maReverseExit=true;g_maReverseWait=0;
   Check(RunAudit(2),"capacity slots recycle after reverse exits");CheckCapacityAuditIntervals("LAB 2W REVERSE");
   Check(g_histTotal>g_maMaxConsecutive&&g_histWins+g_histLosses>0,"closed positions free capacity for later trades");
   g_probeClock=0;g_maIndependent=false;g_maReverseExit=false;g_rtAdvancedAuditEngine=false;
}
