#ifndef LAB_SCALPER_PRESETS_MQH
#define LAB_SCALPER_PRESETS_MQH
void LabAddRule(LabRule &rows[],int left,int period,int compare,int right,int rightPeriod,double threshold)
{
   LabRule r;LabRuleDefaults(r);r.feature=left;r.period=period;r.compare=compare;
   r.rhsFeature=right;r.rhsPeriod=rightPeriod;r.threshold=threshold;
   int n=ArraySize(rows);ArrayResize(rows,n+1);rows[n]=r;
}
bool LabScalperPreset(int index,LabEngine &e)
{
   string names[]={"01 Slow EMA + ADX Trend Scalper","02 EMA Pullback Continuation","03 RSI 50-Line Momentum Scalper",
      "04 Fast EMA + RSI Momentum","05 Bollinger Band Mean-Reversion Scalper","06 ATR Micro-Breakout",
      "07 EMA + RSI Re-Entry Scalper","08 Ultra-Fast EMA State Scalper","09 One-Minute Candle Momentum Machine",
      "10 Hyperactive Directional Flip System"};
   if(index<0||index>=10)return false;
   e.name=names[index];e.edge=false;e.policy=true;e.pipSl=false;e.pipSlPips=500;e.atrPeriod=14;
   e.cooldown=e.maxBars=e.maxMinutes=0;ArrayResize(e.buy,0);ArrayResize(e.sell,0);ArrayResize(e.exitBuy,0);ArrayResize(e.exitSell,0);
   double stops[]={0.9,0.7,0.65,0.55,0.5,0.45,0.55,0.35,0.3,0.2};
   double targets[]={1.2,0.9,0.8,0.7,0.6,0.55,0.7,0.4,0.35,0.25};
   int cooldown[]={5,3,2,1,1,1,1,0,0,0},hold[]={0,0,0,10,0,8,0,6,4,3};
   e.slAtr=stops[index];e.tpAtr=targets[index];e.cooldown=cooldown[index];e.maxBars=hold[index];
   if(index==6)e.maxMinutes=12;if(index==7||index==8)e.atrPeriod=10;if(index==9)e.atrPeriod=7;
   int fast=index==0?12:(index==1?8:(index==7?3:5));
   int slow=index==0?26:(index==1?21:(index==6?12:(index==7?8:13)));
   if(index==0||index==1||index==3||index==6||index==7)
   {LabAddRule(e.buy,32,fast,0,32,slow,0);LabAddRule(e.sell,32,fast,1,32,slow,0);}
   if(index==1)
   {
      LabAddRule(e.buy,3,14,3,32,8,0);LabAddRule(e.buy,0,14,0,32,8,0);LabAddRule(e.buy,34,9,0,-1,14,50);
      LabAddRule(e.sell,2,14,2,32,8,0);LabAddRule(e.sell,0,14,1,32,8,0);LabAddRule(e.sell,34,9,1,-1,14,50);
   }
   if(index==2||index==6)
   {LabAddRule(e.buy,0,14,0,33,50,0);LabAddRule(e.sell,0,14,1,33,50,0);}
   if(index==0||index==2||index==3||index==6||index==7)
   {
      int rsi=index==0?14:(index==7?5:7);double up=index==0?55:(index==7?51:52),down=index==0?45:(index==7?49:48);
      LabAddRule(e.buy,34,rsi,index==2?6:0,-1,14,up);LabAddRule(e.sell,34,rsi,index==2?7:1,-1,14,down);
   }
   if(index==0||index==6)
   {int period=index==0?14:7;double threshold=index==0?22:12;
      LabAddRule(e.buy,36,period,0,-1,14,threshold);LabAddRule(e.sell,36,period,0,-1,14,threshold);}
   if(index==2)
   {LabAddRule(e.exitBuy,34,7,1,-1,14,48);LabAddRule(e.exitSell,34,7,0,-1,14,52);}
   if(index==4)
   {
      LabAddRule(e.buy,3,14,1,39,20,0);LabAddRule(e.buy,34,7,1,-1,14,40);LabAddRule(e.buy,0,14,0,39,20,0);
      LabAddRule(e.sell,2,14,0,38,20,0);LabAddRule(e.sell,34,7,0,-1,14,60);LabAddRule(e.sell,0,14,1,38,20,0);
   }
   if(index==5)
   {LabAddRule(e.buy,0,14,0,41,5,0);LabAddRule(e.sell,0,14,1,42,5,0);}
   if(index==7)
   {LabAddRule(e.exitBuy,32,3,1,32,8,0);LabAddRule(e.exitSell,32,3,0,32,8,0);}
   if(index==8)
   {
      LabAddRule(e.buy,0,14,0,1,14,0);LabAddRule(e.buy,0,14,0,32,20,0);LabAddRule(e.buy,43,10,0,-1,14,0.2);
      LabAddRule(e.sell,0,14,1,1,14,0);LabAddRule(e.sell,0,14,1,32,20,0);LabAddRule(e.sell,43,10,0,-1,14,0.2);
   }
   if(index==9)
   {
      LabAddRule(e.buy,0,14,0,32,3,0);LabAddRule(e.buy,34,3,0,-1,14,50);
      LabAddRule(e.sell,0,14,1,32,3,0);LabAddRule(e.sell,34,3,1,-1,14,50);
   }
   return LabValidEngine(e);
}
bool LabConfigurePolicySelection()
{
   if(!g_labEngine.policy)return true;
   if(!MaIndependentApply(false,1))return false;
   g_rtPipSlMode=true;if(g_labEngine.pipSl)g_rtPipSlPips=g_labEngine.pipSlPips;
   g_rtSignalTf=PERIOD_M1;g_rtEntryMode=ORB_ENTRY_BREAKOUT;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtTargetMode=ORB_TARGET_R_LEG;g_rtCustomR=g_labEngine.tpAtr/g_labEngine.slAtr;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;
   g_rtHalfBeLeg=0;g_rtBEOnTp1=false;g_rtTimeExit=false;
   g_maIndependent=false;g_maMaxConsecutive=1;g_maReverseExit=false;g_maReverseWait=0;
   MaExitSave();return true;
}
#endif
