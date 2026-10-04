#property strict
#define OnInit PolicyInit
#define OnDeinit PolicyDeinit
#define OnTick PolicyTick
#define OnTimer PolicyTimer
#define OnChartEvent PolicyEvent
#define OnTradeTransaction PolicyTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "MaPositionReference.mqh"
int checks=0,failed=0;
void Check(bool value,string name){checks++;if(!value){failed++;Print("FAIL ",name);}}
void CheckMaReference()
{
   PolicyMaEvent reference[];ErlSignal events[];
   ArrayResize(reference,6);ArrayResize(events,6);
   int times[]={990,1000,1100,1250,1300,1450},opened[]={1000,1100,1300};
   int waits[]={0,1,5,30},through[]={950,1000,1100,1250,1300,1450,1500,3000};
   g_lnNas.reverseExit=true;
   for(int mask=0;mask<64;mask++)for(int inv=0;inv<2;inv++)
   {
      g_invertMode=inv!=0;
      for(int i=0;i<6;i++)
      {
         reference[i].signalTime=times[i]-60;reference[i].direction=(mask&(1<<i))!=0?1:-1;
         ZeroMemory(events[i]);events[i].availableTime=times[i];events[i].dir=reference[i].direction;
      }
      for(int d=-1;d<=1;d+=2)for(int o=0;o<3;o++)for(int w=0;w<4;w++)for(int u=0;u<8;u++)
         Check(LnNasReverseAt(events,d,opened[o],through[u],waits[w])
            ==ReferenceMaKernelExitAt(reference,opened[o],d,through[u],waits[w],60,inv!=0),
            "MaCross exact reverse reference");
   }
   g_invertMode=false;
}
void OnStart()
{
   LnNasDefaults(g_lnNas);g_invertMode=false;
   LnNasPolicy copy;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy)&&copy.reverseExit==InpCloseOnReverse&&!copy.independent,"existing defaults preserved");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=20;g_lnNas.reverseWaitMinutes=30;g_lnNas.reverseExit=false;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy)&&LnNasPack(copy)==LnNasPack(g_lnNas),"all position settings round trip");
   ErlSignal raw[];ArrayResize(raw,4);
   for(int i=0;i<4;i++)ZeroMemory(raw[i]);
   raw[0].availableTime=990;raw[0].dir=-1;
   raw[1].availableTime=1100;raw[1].dir=-1;
   raw[2].availableTime=1250;raw[2].dir=1;
   raw[3].availableTime=1450;raw[3].dir=-1;
   Check(LnNasReverseAt(raw,1,1000,5000,5)==0,"reverse OFF");
   g_lnNas.reverseExit=true;
   Check(LnNasReverseAt(raw,1,1000,1200,5)==0,"wait pending");
   Check(LnNasReverseAt(raw,1,1000,1400,5)==0,"latest same side cancels wait latch");
   Check(LnNasReverseAt(raw,1,1000,1500,5)==1450,"post-wait opposite closes");
   ArrayResize(raw,2);
   Check(LnNasReverseAt(raw,1,1000,1400,5)==1300,"grace latch expiry");
   ArrayResize(raw,1);
   Check(LnNasReverseAt(raw,1,1000,5000,5)==0,"pre-entry excluded");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=1;
   ArrayResize(g_histSignals,2);ArrayResize(g_histSignalValid,2);ArrayResize(g_histSignalClosed,2);
   ArrayResize(g_histSignalExitTime,2);ArrayResize(g_histSignalInvalidReason,2);
   ZeroMemory(g_histSignals[0]);ZeroMemory(g_histSignals[1]);
   g_histSignals[0].dir=1;g_histSignals[0].availableTime=1000;
   g_histSignals[1].dir=1;g_histSignals[1].availableTime=1100;
   g_histSignalValid[0]=true;g_histSignalClosed[0]=false;g_histSignalInvalidReason[0]="";
   Check(LnNasAuditCap(1)==1,"MAX total concurrent same-side");
   g_histSignals[1].dir=-1;
   Check(LnNasAuditCap(1)==1,"MAX total blocks independent opposite too");
   g_histSignals[1].dir=1;g_histSignalClosed[0]=true;g_histSignalExitTime[0]=1100;
   Check(LnNasAuditCap(1)==0,"same timestamp completed exit releases slot");
   g_lnNas.independent=false;g_lnNas.reverseExit=false;g_histSignals[1].dir=-1;g_histSignalClosed[0]=false;
   Check(LnNasAuditCap(1)==1,"legacy reverse OFF blocks second position");
   g_histSignalInvalidReason[0]="LEGACY_ACTIVE";g_histSignalValid[0]=false;
   Check(LnNasAuditCap(1)==0,"rejected entries consume no slot");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=10;g_lnNas.reverseExit=false;
   ArrayResize(g_histSignals,12);ArrayResize(g_histSignalValid,12);ArrayResize(g_histSignalClosed,12);
   ArrayResize(g_histSignalExitTime,12);ArrayResize(g_histSignalInvalidReason,12);
   for(int n=0;n<12;n++)
   {
      ZeroMemory(g_histSignals[n]);g_histSignals[n].availableTime=1000+n;g_histSignals[n].dir=n<6?1:-1;
      g_histSignalValid[n]=true;g_histSignalClosed[n]=false;g_histSignalExitTime[n]=0;
      g_histSignalInvalidReason[n]="";
      if(n<=10)Check((LnNasAuditCap(n)==0)==ReferenceMaOpenCapacityAllows(n,10),"MaCross total capacity reference");
   }
   g_histSignalInvalidReason[10]="MAX_OPEN";g_histSignalValid[10]=false;
   g_invertMode=true;
   Check(LnNasAuditCap(10)==1,"inverse capacity follows actual audited OPEN trades");
   g_invertMode=false;
   g_histSignalClosed[0]=true;g_histSignalExitTime[0]=1011;
   Check(LnNasAuditCap(11)==0,"mixed 6 BUY + 4 SELL releases total slot; blocked entry excluded");
   g_histSignalValid[0]=false;g_histSignalClosed[0]=false;
   Check(LnNasAuditCap(11)==-1,"unknown opposite-side capacity remains DATA");
   g_lnNas.maxSameOpen=1000;g_lnNas.reverseWaitMinutes=5999;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy),"MaCross MAX and duration ranges persist");
   int wait=0;
   Check(LnNasParseDuration("99:59",wait,5999)&&wait==5999,"MaCross reverse wait range");
   Check(!LnNasParseDuration("25:00",wait),"NAS wait range unchanged");
   CheckMaReference();
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed);FileClose(f);}
}
