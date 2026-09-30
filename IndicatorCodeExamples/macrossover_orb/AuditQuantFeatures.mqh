#ifndef AUDIT_QUANT_FEATURES_MQH
#define AUDIT_QUANT_FEATURES_MQH
// Causal research features, not a replacement for any EA's signal kernel.
// Prefix f_ is available at entry; label_ and audit outcome columns are targets.
string AxBlankFields(int count)
{string row="";for(int i=0;i<count;i++)AxCell(row,"");return row;}
bool AxClosedRates(ENUM_TIMEFRAMES tf,datetime cutoff,int count,MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);int seconds=PeriodSeconds(tf);
   if(seconds<=0||!SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED))return false;
   int shift=iBarShift(_Symbol,tf,cutoff-seconds,false);
   if(shift<1||Bars(_Symbol,tf)<shift+count)return false;
   datetime last=iTime(_Symbol,tf,shift);
   if(last<=0||last+seconds>cutoff)return false;
   return CopyRates(_Symbol,tf,shift,count,rates)==count&&rates[0].time==last;
}
string AxRollingNames()
{
   return "return,log_return,mean_return,realized_vol,downside_vol,upside_vol,return_skew,return_excess_kurtosis,lag1_autocorr,efficiency,positive_fraction,sign_entropy,sma,close_zscore,linear_slope,linear_r2,true_range_mean,range_mean,high,low,range_position,drawdown_from_high,runup_from_low,tick_volume_mean,tick_volume_cv,tick_volume_zscore,tick_vwap_typical,tick_vwap_distance,quote_volume_direction_proxy,real_volume_mean,spread_mean_points,spread_max_points";
}
string AxPrefixedNames(string names,string prefix)
{
   string fields[],out="";int n=StringSplit(names,',',fields);
   for(int i=0;i<n;i++)AxCell(out,prefix+fields[i]);return out;
}
string AxRollingValues(const MqlRates &r[],int n)
{
   if(ArraySize(r)<=n||n<3)return AxBlankFields(32);
   double ret[],sum=0,sq=0,down=0,up=0,path=0,price=0,priceSq=0;
   double volume=0,volumeSq=0,realVolume=0,tr=0,range=0,spread=0,maxSpread=0;
   double hi=r[0].high,lo=r[0].low,weighted=0,signedVolume=0,xy=0;
   int positive=0,negative=0;ArrayResize(ret,n);
   for(int i=0;i<n;i++)
   {
      if(r[i].close<=0||r[i+1].close<=0)return AxBlankFields(32);
      ret[i]=MathLog(r[i].close/r[i+1].close);sum+=ret[i];sq+=ret[i]*ret[i];
      if(ret[i]>0){up+=ret[i]*ret[i];positive++;}else if(ret[i]<0){down+=ret[i]*ret[i];negative++;}
      path+=MathAbs(r[i].close-r[i+1].close);price+=r[i].close;priceSq+=r[i].close*r[i].close;
      double v=(double)r[i].tick_volume;volume+=v;volumeSq+=v*v;realVolume+=(double)r[i].real_volume;
      range+=r[i].high-r[i].low;
      tr+=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
      spread+=r[i].spread;maxSpread=MathMax(maxSpread,r[i].spread);
      hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);
      weighted+=(r[i].high+r[i].low+r[i].close)/3*v;
      signedVolume+=(r[i].close>r[i].open?1:(r[i].close<r[i].open?-1:0))*v;
      xy+=(n-1-i)*r[i].close;
   }
   double mean=sum/n,variance=MathMax(0.0,sq/n-mean*mean),vol=MathSqrt(variance),third=0,fourth=0,cov=0;
   double lagA=0,lagB=0,lagAA=0,lagBB=0,lagAB=0;
   for(int i=0;i<n;i++)
   {
      double d=ret[i]-mean;third+=d*d*d;fourth+=d*d*d*d;
      if(i<n-1){lagA+=ret[i];lagB+=ret[i+1];lagAA+=ret[i]*ret[i];lagBB+=ret[i+1]*ret[i+1];lagAB+=ret[i]*ret[i+1];}
   }
   double lagDen=MathSqrt(MathMax(0.0,((n-1)*lagAA-lagA*lagA)*((n-1)*lagBB-lagB*lagB)));
   double p=(double)positive/n,q=(double)negative/n,z=1-p-q,entropy=0;
   if(p>0)entropy-=p*MathLog(p);if(q>0)entropy-=q*MathLog(q);if(z>0)entropy-=z*MathLog(z);
   double pxMean=price/n,pxVar=MathMax(0.0,priceSq/n-pxMean*pxMean),pxStd=MathSqrt(pxVar);
   double xMean=(n-1)/2.0,xVar=(n*n-1)/12.0;
   cov=xy/n-xMean*pxMean;
   double vMean=volume/n,vStd=MathSqrt(MathMax(0.0,volumeSq/n-vMean*vMean));
   double vwap=volume>0?weighted/volume:EMPTY_VALUE;string out="";
   AxCell(out,AxNumber(r[0].close/r[n].close-1));AxCell(out,AxNumber(MathLog(r[0].close/r[n].close)));
   AxCell(out,AxNumber(mean));AxCell(out,AxNumber(vol));AxCell(out,AxNumber(MathSqrt(down/n)));AxCell(out,AxNumber(MathSqrt(up/n)));
   AxCell(out,vol>0?AxNumber(third/n/MathPow(vol,3)):"");AxCell(out,variance>0?AxNumber(fourth/n/(variance*variance)-3):"");
   AxCell(out,lagDen>0?AxNumber(((n-1)*lagAB-lagA*lagB)/lagDen):"");
   AxCell(out,path>0?AxNumber(MathAbs(r[0].close-r[n].close)/path):"0");AxCell(out,AxNumber(p));AxCell(out,AxNumber(entropy));
   AxCell(out,AxNumber(pxMean));AxCell(out,pxStd>0?AxNumber((r[0].close-pxMean)/pxStd):"");
   AxCell(out,AxNumber(cov/xVar));AxCell(out,pxVar>0?AxNumber(cov*cov/(xVar*pxVar)):"");
   AxCell(out,AxNumber(tr/n));AxCell(out,AxNumber(range/n));AxCell(out,AxNumber(hi));AxCell(out,AxNumber(lo));
   AxCell(out,hi>lo?AxNumber((r[0].close-lo)/(hi-lo)):"");AxCell(out,AxNumber(r[0].close/hi-1));AxCell(out,lo>0?AxNumber(r[0].close/lo-1):"");
   AxCell(out,AxNumber(vMean));AxCell(out,vMean>0?AxNumber(vStd/vMean):"");AxCell(out,vStd>0?AxNumber(((double)r[0].tick_volume-vMean)/vStd):"");
   AxCell(out,AxNumber(vwap));AxCell(out,vwap!=EMPTY_VALUE?AxNumber(r[0].close-vwap):"");
   AxCell(out,volume>0?AxNumber(signedVolume/volume):"");AxCell(out,AxNumber(realVolume/n));
   AxCell(out,AxNumber(spread/n));AxCell(out,AxNumber(maxSpread));return out;
}
string AxQuantHeader()
{
   string out="f_signal_age_seconds,f_entry_delay_seconds,f_stop_distance_price,f_target_distance_price,f_effective_target_r,f_stop_distance_points,f_target_distance_points,f_hour_sin,f_hour_cos,f_weekday_sin,f_weekday_cos,f_month,f_day_of_month,f_is_month_start,f_is_month_end";
   int windows[4]={5,20,60,120};
   for(int i=0;i<4;i++)out+=","+AxPrefixedNames(AxRollingNames(),"f_roll_"+(string)windows[i]+"_");
   string tfNames[6]={"M1","M5","M15","H1","H4","D1"};
   for(int i=0;i<6;i++)
   {
      out+=",f_"+tfNames[i]+"_status,f_"+tfNames[i]+"_last_closed_bar,f_"+tfNames[i]+"_staleness_seconds";
      out+=","+AxPrefixedNames(AxRollingNames(),"f_"+tfNames[i]+"_20_");
   }
   return out;
}
string AxQuantRow(const AxTrade &t)
{
   datetime at=t.entryTime>0?t.entryTime:t.availableTime;MqlDateTime dt;TimeToStruct(t.localTime,dt);
   string out="";double risk=MathAbs(t.entry-t.sl),reward=MathAbs(t.tp-t.entry);
   AxCell(out,at>=t.signalTime?(string)(long)(at-t.signalTime):"");
   AxCell(out,at>=t.availableTime?(string)(long)(at-t.availableTime):"");
   AxCell(out,t.valid?AxNumber(risk):"");AxCell(out,t.valid&&t.tp>0?AxNumber(reward):"");
   AxCell(out,t.valid&&risk>0&&t.tp>0?AxNumber(reward/risk):"");
   AxCell(out,t.valid&&_Point>0?AxNumber(risk/_Point):"");AxCell(out,t.valid&&_Point>0&&t.tp>0?AxNumber(reward/_Point):"");
   double hour=dt.hour+dt.min/60.0,pi=3.14159265358979323846;
   AxCell(out,AxNumber(MathSin(2*pi*hour/24)));AxCell(out,AxNumber(MathCos(2*pi*hour/24)));
   AxCell(out,AxNumber(MathSin(2*pi*dt.day_of_week/7)));AxCell(out,AxNumber(MathCos(2*pi*dt.day_of_week/7)));
   AxCell(out,(string)dt.mon);AxCell(out,(string)dt.day);AxCell(out,(string)(dt.day==1));
   MqlDateTime tomorrow;TimeToStruct(t.localTime+86400,tomorrow);AxCell(out,(string)(dt.mon!=tomorrow.mon));
   MqlRates rates[];bool mainOk=AxClosedRates(g_axTf,at,121,rates);int windows[4]={5,20,60,120};
   if(!mainOk)g_axMissingRolling++;
   for(int i=0;i<4;i++)out+=","+(mainOk?AxRollingValues(rates,windows[i]):AxBlankFields(32));
   ENUM_TIMEFRAMES tfs[6]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H4,PERIOD_D1};
   bool mtfMissing=false;
   for(int i=0;i<6;i++)
   {
      bool ok=AxClosedRates(tfs[i],at,21,rates);
      if(!ok)mtfMissing=true;
      AxCell(out,ok?"OK":"DATA_MISSING");AxCell(out,ok?AxTime(rates[0].time):"");
      AxCell(out,ok?(string)(long)(at-rates[0].time-PeriodSeconds(tfs[i])):"");
      out+=","+(ok?AxRollingValues(rates,20):AxBlankFields(32));
   }
   if(mtfMissing)g_axMissingMtf++;
   return out;
}
#endif
