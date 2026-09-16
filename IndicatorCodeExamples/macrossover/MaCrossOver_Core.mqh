#ifndef MA_CROSSOVER_CORE_MQH
#define MA_CROSSOVER_CORE_MQH
// MA entry formula ported from MaCrossOver.pine by yigdeli (MPL-2.0).
// EMA(fast), EMA(medium), HMA(slow); crossover + closed HTF HMA filter.
struct MaConfig
{
   int fast,medium,slow,cross,htf,htfLen,atrLen,riskMode,management;
   double slPct,tpPct,atrMult,rr,pips,beR,partialR,partialPct,trailMult;
   bool htfOn,volOn,adxOn,divOn,atrOn,fvgOn,dispOn,invert;
   double volMult,adxMin,atrMin,atrMax,dispMin;
   int adxLen,rsiLen,pivot,divAge,mask,startMin,endMin,weekMask;
};
bool MaValid(double v){return MathIsValidNumber(v)&&v!=EMPTY_VALUE;}
void MaDefaults(MaConfig &c)
{
   ZeroMemory(c);c.fast=9;c.medium=27;c.slow=200;c.htf=PERIOD_H4;c.htfLen=200;
   c.atrLen=14;c.slPct=2;c.tpPct=4;c.atrMult=1.5;c.rr=2;c.pips=500;
   c.beR=1;c.partialR=1.5;c.partialPct=50;c.trailMult=1;c.htfOn=true;
   c.volMult=1;c.adxMin=20;c.adxLen=14;c.rsiLen=14;c.pivot=3;c.divAge=30;
   c.atrMax=100;c.dispMin=.5;c.mask=63;c.weekMask=127;
}
string MaPack(const MaConfig &c)
{
   return (string)c.fast+"|"+(string)c.medium+"|"+(string)c.slow+"|"+(string)c.cross+"|"+(string)c.htf+"|"+(string)c.htfLen
      +"|"+(string)c.atrLen+"|"+(string)c.riskMode+"|"+(string)c.management
      +"|"+DoubleToString(c.slPct,8)+"|"+DoubleToString(c.tpPct,8)+"|"+DoubleToString(c.atrMult,8)+"|"+DoubleToString(c.rr,8)
      +"|"+DoubleToString(c.pips,8)+"|"+DoubleToString(c.beR,8)+"|"+DoubleToString(c.partialR,8)
      +"|"+DoubleToString(c.partialPct,8)+"|"+DoubleToString(c.trailMult,8)
      +"|"+(string)(int)c.htfOn+"|"+(string)(int)c.volOn+"|"+(string)(int)c.adxOn+"|"+(string)(int)c.divOn
      +"|"+(string)(int)c.atrOn+"|"+(string)(int)c.fvgOn+"|"+(string)(int)c.dispOn+"|"+(string)(int)c.invert
      +"|"+DoubleToString(c.volMult,8)+"|"+DoubleToString(c.adxMin,8)+"|"+DoubleToString(c.atrMin,8)
      +"|"+DoubleToString(c.atrMax,8)+"|"+DoubleToString(c.dispMin,8)+"|"+(string)c.adxLen+"|"+(string)c.rsiLen
      +"|"+(string)c.pivot+"|"+(string)c.divAge+"|"+(string)c.mask+"|"+(string)c.startMin+"|"+(string)c.endMin+"|"+(string)c.weekMask;
}
bool MaNumber(string s,double &v)
{
   StringTrimLeft(s);StringTrimRight(s);StringReplace(s,",",".");if(s=="")return false;
   int digits=0,dots=0;for(int i=0;i<StringLen(s);i++)
   {ushort ch=StringGetCharacter(s,i);if(ch>='0'&&ch<='9'){digits++;continue;}if(ch=='.'&&++dots==1)continue;if(i==0&&(ch=='+'||ch=='-'))continue;return false;}
   v=StringToDouble(s);return digits>0&&MathIsValidNumber(v);
}
bool MaConfigValid(const MaConfig &c)
{
   return c.fast>=1&&c.fast<=2000&&c.medium>=1&&c.medium<=2000&&c.slow>=2&&c.slow<=2000
      &&c.cross>=0&&c.cross<=2&&PeriodSeconds((ENUM_TIMEFRAMES)c.htf)>0&&c.htfLen>=2&&c.htfLen<=2000
      &&c.atrLen>=2&&c.atrLen<=1000&&c.riskMode>=0&&c.riskMode<=2&&c.management>=0&&c.management<=3
      &&c.slPct>0&&c.slPct<100&&c.tpPct>0&&c.atrMult>0&&c.rr>0&&c.pips>0
      &&c.beR>0&&c.partialR>0&&c.partialPct>0&&c.partialPct<100&&c.trailMult>0
      &&c.volMult>0&&c.adxMin>=0&&c.adxMin<=100&&c.atrMin>=0&&c.atrMax>=c.atrMin
      &&c.dispMin>=0&&c.adxLen>=2&&c.adxLen<=1000&&c.rsiLen>=2&&c.rsiLen<=1000
      &&c.pivot>=1&&c.pivot<=30&&c.divAge>=1&&c.divAge<=1000&&c.mask>=0&&c.mask<=63
      &&c.startMin>=0&&c.startMin<1440&&c.endMin>=0&&c.endMin<1440&&c.weekMask>=0&&c.weekMask<=127;
}
bool MaUnpack(string text,MaConfig &c)
{
   string a[];if(StringSplit(text,'|',a)!=39)return false;double v[39];
   for(int i=0;i<39;i++)if(!MaNumber(a[i],v[i]))return false;
   for(int i=0;i<39;i++)if((i<=8||(i>=18&&i<=25)||i>=31)&&v[i]!=MathFloor(v[i]))return false;
   for(int i=18;i<=25;i++)if(v[i]!=0&&v[i]!=1)return false;
   MaConfig n;ZeroMemory(n);
   n.fast=(int)v[0];n.medium=(int)v[1];n.slow=(int)v[2];n.cross=(int)v[3];n.htf=(int)v[4];n.htfLen=(int)v[5];
   n.atrLen=(int)v[6];n.riskMode=(int)v[7];n.management=(int)v[8];
   n.slPct=v[9];n.tpPct=v[10];n.atrMult=v[11];n.rr=v[12];n.pips=v[13];n.beR=v[14];n.partialR=v[15];n.partialPct=v[16];n.trailMult=v[17];
   n.htfOn=(bool)v[18];n.volOn=(bool)v[19];n.adxOn=(bool)v[20];n.divOn=(bool)v[21];n.atrOn=(bool)v[22];n.fvgOn=(bool)v[23];n.dispOn=(bool)v[24];n.invert=(bool)v[25];
   n.volMult=v[26];n.adxMin=v[27];n.atrMin=v[28];n.atrMax=v[29];n.dispMin=v[30];n.adxLen=(int)v[31];n.rsiLen=(int)v[32];
   n.pivot=(int)v[33];n.divAge=(int)v[34];n.mask=(int)v[35];n.startMin=(int)v[36];n.endMin=(int)v[37];n.weekMask=(int)v[38];
   if(!MaConfigValid(n))return false;c=n;return true;
}
void MaEma(const double &x[],int len,double &out[])
{
   int n=ArraySize(x);ArrayResize(out,n);double a=2.0/(len+1),last=EMPTY_VALUE;
   for(int i=0;i<n;i++){if(!MaValid(x[i])){out[i]=EMPTY_VALUE;continue;}last=MaValid(last)?a*x[i]+(1-a)*last:x[i];out[i]=last;}
}
void MaWma(const double &x[],int len,double &out[])
{
   int n=ArraySize(x),valid=0;ArrayResize(out,n);double sum=0,weight=0,den=(double)len*(len+1)/2;
   for(int i=0;i<n;i++)
   {
      if(!MaValid(x[i])){valid=0;sum=0;weight=0;out[i]=EMPTY_VALUE;continue;}
      if(valid<len){valid++;sum+=x[i];weight+=valid*x[i];}
      else {weight=weight-sum+len*x[i];sum+=x[i]-x[i-len];}
      out[i]=valid>=len?weight/den:EMPTY_VALUE;
   }
}
void MaHma(const double &x[],int len,double &out[])
{
   double half[],full[],delta[];MaWma(x,MathMax(1,len/2),half);MaWma(x,len,full);ArrayResize(delta,ArraySize(x));
   for(int i=0;i<ArraySize(x);i++)delta[i]=MaValid(half[i])&&MaValid(full[i])?2*half[i]-full[i]:EMPTY_VALUE;
   MaWma(delta,MathMax(1,(int)MathRound(MathSqrt(len))),out);
}
void MaRma(const double &x[],int len,double &out[])
{
   int n=ArraySize(x),count=0;double sum=0,last=EMPTY_VALUE;ArrayResize(out,n);
   for(int i=0;i<n;i++)
   {if(!MaValid(x[i])){out[i]=EMPTY_VALUE;continue;}if(count<len){sum+=x[i];count++;if(count==len)last=sum/len;}else last=(last*(len-1)+x[i])/len;out[i]=last;}
}
struct MaSeries
{
   double fast[],medium[],slow[],atr[],adx[],rsi[],volume[];
   int direction[],bearDiv[],bullDiv[];
};
void MaCalculate(const MqlRates &r[],const MaConfig &c,MaSeries &s)
{
   int n=ArraySize(r);double close[],tr[],plus[],minus[],gain[],loss[];
   ArrayResize(close,n);ArrayResize(tr,n);ArrayResize(plus,n);ArrayResize(minus,n);ArrayResize(gain,n);ArrayResize(loss,n);
   for(int i=0;i<n;i++)
   {
      close[i]=r[i].close;tr[i]=r[i].high-r[i].low;plus[i]=0;minus[i]=0;gain[i]=EMPTY_VALUE;loss[i]=EMPTY_VALUE;
      if(i>0){tr[i]=MathMax(tr[i],MathMax(MathAbs(r[i].high-r[i-1].close),MathAbs(r[i].low-r[i-1].close)));
         double up=r[i].high-r[i-1].high,down=r[i-1].low-r[i].low;plus[i]=up>down&&up>0?up:0;minus[i]=down>up&&down>0?down:0;
         double d=close[i]-close[i-1];gain[i]=MathMax(0,d);loss[i]=MathMax(0,-d);}
   }
   MaEma(close,c.fast,s.fast);MaEma(close,c.medium,s.medium);MaHma(close,c.slow,s.slow);MaRma(tr,c.atrLen,s.atr);
   double atrD[],p[],m[],dx[],g[],l[];MaRma(tr,c.adxLen,atrD);MaRma(plus,c.adxLen,p);MaRma(minus,c.adxLen,m);
   ArrayResize(dx,n);for(int i=0;i<n;i++)dx[i]=MaValid(p[i])&&MaValid(m[i])?(p[i]+m[i]>0?100*MathAbs(p[i]-m[i])/(p[i]+m[i]):0):EMPTY_VALUE;
   MaRma(dx,c.adxLen,s.adx);MaRma(gain,c.rsiLen,g);MaRma(loss,c.rsiLen,l);
   ArrayResize(s.rsi,n);ArrayResize(s.volume,n);ArrayResize(s.direction,n);ArrayResize(s.bearDiv,n);ArrayResize(s.bullDiv,n);
   int high=-1,low=-1,bear=-1000000,bull=-1000000;double vol=0;
   for(int i=0;i<n;i++)
   {
      s.rsi[i]=MaValid(g[i])&&MaValid(l[i])?(l[i]==0?(g[i]==0?50:100):100-100/(1+g[i]/l[i])):EMPTY_VALUE;
      s.volume[i]=i>=20?vol/20:EMPTY_VALUE;vol+=(double)r[i].tick_volume;if(i>=20)vol-=(double)r[i-20].tick_volume;
      double a=c.cross==2?s.medium[i]:s.fast[i],b=c.cross==0?s.medium[i]:s.slow[i];s.direction[i]=0;
      if(i>0){double ap=c.cross==2?s.medium[i-1]:s.fast[i-1],bp=c.cross==0?s.medium[i-1]:s.slow[i-1];
         if(MaValid(a)&&MaValid(b)&&MaValid(ap)&&MaValid(bp))s.direction[i]=a>b&&ap<=bp?1:(a<b&&ap>=bp?-1:0);}
      int k=i-c.pivot;
      if(k>=c.pivot&&MaValid(s.rsi[k]))
      {
         bool ph=true,pl=true;for(int j=k-c.pivot;j<=i;j++)if(j!=k){if(r[j].high>=r[k].high)ph=false;if(r[j].low<=r[k].low)pl=false;}
         if(ph){if(high>=0&&r[k].high>r[high].high&&s.rsi[k]<s.rsi[high])bear=i;high=k;}
         if(pl){if(low>=0&&r[k].low<r[low].low&&s.rsi[k]>s.rsi[low])bull=i;low=k;}
      }
      s.bearDiv[i]=i-bear<=c.divAge?1:0;s.bullDiv[i]=i-bull<=c.divAge?1:0;
   }
}
int MaLastClosed(const MqlRates &r[],datetime at,int seconds)
{
   int lo=0,hi=ArraySize(r);while(lo<hi){int mid=(lo+hi)/2;if(r[mid].time+seconds<=at)lo=mid+1;else hi=mid;}return lo-1;
}
bool MaWindow(int minute,int start,int end){return start==end||(start<end?(minute>=start&&minute<end):(minute>=start||minute<end));}
bool MaFilter(const MqlRates &r[],int i,const MaSeries &s,const MaConfig &c,const MqlRates &htf[],const double &hma[],int sec,int offsetMinutes,int &dir,string &reason)
{
   dir=s.direction[i];reason="";if(dir==0)return false;datetime available=r[i].time+sec;
   if(c.htfOn){int h=MaLastClosed(htf,available,PeriodSeconds((ENUM_TIMEFRAMES)c.htf));
      if(h<0||h>=ArraySize(hma)||!MaValid(hma[h])){reason="HTF DATA";return false;}
      if(dir*(r[i].close-hma[h])<=0){reason="HTF";return false;}}
   if(c.invert)dir=-dir;
   MqlDateTime dt;TimeToStruct(available-offsetMinutes*60,dt);
   if(!(c.weekMask&(1<<dt.day_of_week))||!MaWindow(dt.hour*60+dt.min,c.startMin,c.endMin)){reason="WINDOW";return false;}
   if(!MaValid(s.atr[i])||s.atr[i]<=0){reason="ATR DATA";return false;}
   if(c.volOn&&(!MaValid(s.volume[i])||s.volume[i]<=0||r[i].tick_volume<s.volume[i]*c.volMult)){reason="VOL";return false;}
   if(c.adxOn&&(!MaValid(s.adx[i])||s.adx[i]<c.adxMin)){reason="ADX";return false;}
   if(c.divOn&&(dir>0?s.bearDiv[i]:s.bullDiv[i])!=0){reason="RSI DIV";return false;}
   double pct=100*s.atr[i]/r[i].close;
   if(c.atrOn&&(pct<c.atrMin||pct>c.atrMax)){reason="ATR RANGE";return false;}
   if(c.dispOn&&(dir*(r[i].close-r[i].open)<s.atr[i]*c.dispMin)){reason="DISPLACEMENT";return false;}
   if(c.fvgOn){bool found=false;for(int k=i;k>=MathMax(2,i-19);k--)
      if(dir>0?r[k].low>r[k-2].high:r[k].high<r[k-2].low){found=true;break;}
      if(!found){reason="FVG";return false;}}
   return true;
}
#endif
