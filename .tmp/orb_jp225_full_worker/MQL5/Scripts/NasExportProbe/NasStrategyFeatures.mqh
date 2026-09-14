// Generated from ORB closed256 feature math; NAS-specific fields 33..37.
bool NasLibraryFeatures(const MqlRates &source[],int index,const NasPoint &point,int direction,double &x[],string &reason)
{
   ArrayResize(x,40);ArrayInitialize(x,0);reason="FEATURE_HISTORY";
   int seconds=PeriodSeconds(_Period);
   if(InpSignalBarMode!=NAS_SIGNAL_BAR_CLOSED||index<255||index>=ArraySize(source))return false;
   datetime cutoff=source[index].time+seconds;
   MqlRates rates[];ArrayResize(rates,256);
   for(int k=0;k<256;k++)rates[k]=source[index-255+k];
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
   x[0]=direction;
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
   RegimeV3Snapshot state;int bucket=LiqMacroRegimeBucketAt(cutoff,state);
   // Never substitute today's regime for unavailable history.
   if(!state.valid||state.availableTime>cutoff){reason="REGIME_HISTORY";return false;}
   x[21]=1;if(bucket>=0&&bucket<6)x[22+bucket]=1;
   x[28]=state.trendDepthScore;x[29]=state.volatilityDepthScore;x[30]=state.effectiveAge;
   x[31]=state.transitionConfidence;x[32]=state.transitionPending;
   if(!NAS_IsValid(point.sma8)||!NAS_IsValid(point.sma9)||!NAS_IsValid(point.sma13)||!NAS_IsValid(point.superTrend))return false;
   x[33]=(close-point.sma8)/atr;x[34]=(close-point.sma9)/atr;
   x[35]=(close-point.sma13)/atr;x[36]=(close-point.superTrend)/atr;x[37]=point.direction;
   x[38]=(ema20-old20)/atr;x[39]=g_invertTradeModeRuntime?1:0;
   for(int i=0;i<NAS_ML_FEATURES;i++)if(!MathIsValidNumber(x[i]))return false;
   reason="OK";return true;
}
