#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label);}}
void E(MaCrossAuditEvent &a[],int i,datetime available,int dir){a[i].signalTime=available-60;a[i].direction=dir;}
datetime SlowReference(const MaCrossAuditEvent &events[],int opened,int dir,int until,int wait,bool invert)
{
   int state=0;
   for(int t=opened+1;t<=until;t++)
   {
      for(int j=0;j<ArraySize(events);j++)if(events[j].signalTime+60==t)state=events[j].direction*(invert?-1:1);
      if(t>=opened+wait*60&&state==-dir)return (datetime)t;
   }
   return 0;
}
void OnStart()
{
   MaCrossAuditEvent a[];ArrayResize(a,4);
   E(a,0,900,-1);E(a,1,1100,-1);E(a,2,1600,1);E(a,3,2000,-1);
   Check(MaKernelExitAt(a,1000,1,3000,0,60,false)==1100,"first post-entry opposite");
   Check(MaKernelExitAt(a,1000,1,1200,5,60,false)==0,"grace not expired");
   Check(MaKernelExitAt(a,1000,1,1400,5,60,false)==1300,"latched opposite at expiry");
   Check(MaKernelExitAt(a,1000,1,1900,10,60,false)==0,"same-side at expiry cancels latch");
   Check(MaKernelExitAt(a,1000,1,2200,10,60,false)==2000,"opposite after grace");
   Check(MaKernelExitAt(a,1100,1,1500,0,60,false)==0,"entry-time signal excluded");
   Check(MaKernelExitAt(a,1000,-1,2200,0,60,false)==1600,"sell independent direction");
   Check(MaKernelExitAt(a,1000,-1,1500,5,60,true)==1300,"inverted effective direction");
   Check(MaKernelExitAt(a,2100,1,5000,0,60,false)==0,"all pre-entry excluded");
   Check(MaKernelExitAt(a,1700,1,2200,10,60,false)==0,"later position has its own grace");
   Check(MaKernelExitAt(a,1700,1,2500,10,60,false)==2300,"later position expiry");
   MathSrand(9719);MaCrossAuditEvent random[];ArrayResize(random,20);
   for(int trial=0;trial<1000;trial++)
   {
      int t=800;for(int j=0;j<20;j++){t+=1+MathRand()%60;E(random,j,t,MathRand()%2==0?1:-1);}
      int opened=850+MathRand()%300,dir=MathRand()%2==0?1:-1,wait=MathRand()%11,until=1100+MathRand()%700;
      bool invert=MathRand()%2==0;
      Check(MaKernelExitAt(random,opened,dir,until,wait,60,invert)==SlowReference(random,opened,dir,until,wait,invert),"independent second-by-second oracle "+(string)trial);
   }
   g_maReverseExit=false;g_maIndependent=false;g_rtSignalTf=PERIOD_M1;
   ArrayCopy(g_maCrossAuditEvents,a);OrbWindowSignal dummy[];datetime at=0;string detail="";
   Check(!FindNewDayAcceptedReverseExit(dummy,940,"BUY",3000,at,detail),"reverse default OFF");
   g_maReverseExit=true;g_maReverseWait=5;g_rtInvertMode=false;
   Check(!FindNewDayAcceptedReverseExit(dummy,940,"BUY",3000,at,detail),"legacy rejects raw events absent from accepted stream");
   ArrayResize(dummy,3);
   dummy[0].availableTime=1100;dummy[0].executionDirection="SELL";
   dummy[1].availableTime=1600;dummy[1].executionDirection="BUY";
   dummy[2].availableTime=2000;dummy[2].executionDirection="SELL";
   Check(FindNewDayAcceptedReverseExit(dummy,940,"BUY",3000,at,detail)&&at==1300,"legacy accepted grace latch");
   g_maReverseWait=0;
   Check(FindNewDayAcceptedReverseExit(dummy,940,"BUY",3000,at,detail)&&at==1100,"legacy accepted immediate reverse");
   g_maReverseWait=5;
   g_maIndependent=true;
   Check(FindNewDayAcceptedReverseExit(dummy,940,"BUY",3000,at,detail)&&at==1300,"independent history reverse");
   Check(!IsAcceptedNewDayReverseCandidate("SELL",D'2026.09.20',detail),"inherited ORB reverse disabled");
   g_histNasCacheActive=true;g_rtNasFlowVolumeFilter=false;
   ArrayResize(g_histNasEvents,3);
   g_histNasEvents[0].availableTime=1100;g_histNasEvents[0].barTime=1040;g_histNasEvents[0].dir="SELL";
   g_histNasEvents[1].availableTime=1600;g_histNasEvents[1].barTime=1540;g_histNasEvents[1].dir="BUY";
   g_histNasEvents[2].availableTime=2000;g_histNasEvents[2].barTime=1940;g_histNasEvents[2].dir="SELL";
   datetime bar;double price;g_rtNasOppositeExitWaitMinutes=10;
   for(int mode=0;mode<2;mode++)
   {
      g_rtNasAdditionalExit=mode==1;g_rtNasExitOnOppositeSignal=mode==0;
      Check(FindNasOppositeExitWithGrace(1,1000,2500,bar,at,price,detail)&&at==2000,"NAS grace same-side reset mode "+(string)mode);
      g_rtNasOppositeExitWaitMinutes=5;
      Check(FindNasOppositeExitWithGrace(1,1000,1500,bar,at,price,detail)&&at==1300,"NAS grace latch mode "+(string)mode);
      g_rtNasOppositeExitWaitMinutes=10;
   }
   int minutes;Check(ParseStrictDurationMinutes("04:30",minutes)&&minutes==270,"duration parsing");
   Check(!ParseStrictDurationMinutes("01:60",minutes),"invalid duration");
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   g_runtimeMagic=9192026000+(long)(GetTickCount64()%1000000);
   g_orbBridgeEnabled=false;g_maIndependent=true;g_maMaxConsecutive=20;g_maReverseExit=true;g_maReverseWait=270;
   string name="__MA_EXIT_PROBE_"+(string)GetTickCount64();
   Check(OrbUserSave(name),"save exit policy");
   OrbStrategyPreset p;Check(OrbStrategyPresetLoad(g_strategyPresetIndex,p),"reload policy record");
   int slot=OrbUserSlot(p.id);
   if(slot>=0)
   {
      Check(g_userStrategies[slot].reverseExit&&g_userStrategies[slot].reverseWait==270,"policy metadata");
      g_maReverseExit=false;g_maReverseWait=0;g_maRestoringPreset=true;OrbUserApply(p);g_maRestoringPreset=false;
      Check(g_maReverseExit&&g_maReverseWait==270&&OrbUserMatches(p),"apply restores policy");
      // Rewrite only this probe's temporary record into both old metadata forms.
      string lines[];
      Check(OrbMlReadLines(OrbUserFile(slot),lines,113,true),"read migration fixture");
      for(int legacy=0;legacy<2;legacy++)
      {
         lines[5]=OrbCustomInputSignature()+(legacy==0?"|MAENTRY1=1,20":"");
         string payload="";for(int j=0;j<112;j++)payload+=lines[j]+"\n";
         int fixture=FileOpen(OrbUserFile(slot),FILE_WRITE|FILE_BIN|FILE_COMMON);
         bool written=fixture!=INVALID_HANDLE;
         if(written){written=OrbMlWriteUtf8(fixture,payload+OrbMlSha256(payload)+"\n");FileClose(fixture);}
         Check(written,"write old metadata fixture");OrbUserReload(true);
         Check(g_userStrategies[slot].valid&&g_userStrategies[slot].reverseExit==(legacy==1)
            &&g_userStrategies[slot].reverseWait==0,"old mode determines default reverse");
      }
      FileDelete(OrbUserFile(slot),FILE_COMMON);FileDelete("MaCrossOrbStrategyLibrary\\"+p.id+".metrics",FILE_COMMON);
   }
   GlobalVariableDel(MaExitSettingsKey()+".ON");GlobalVariableDel(MaExitSettingsKey()+".WAIT");
   GlobalVariableDel(OrbStrategyPresetSelectionKey());GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("20260920_201514_MaExitPolicyProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
