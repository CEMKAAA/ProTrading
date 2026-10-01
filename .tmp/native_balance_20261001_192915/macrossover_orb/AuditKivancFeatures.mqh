#ifndef AUDIT_KIVANC_FEATURES_MQH
#define AUDIT_KIVANC_FEATURES_MQH
// Source-derived calculations: ../KivancOzbilginc/*.pine (source manifest in research/kivanc).
// MPL-2.0 https://mozilla.org/MPL/2.0/ for adaptations of the MPL sources.
// Authors: Kivanc Ozbilgic, Anil Ozeksi, Kamil Hasan Alpay, John Ehlers,
// Tim Tillson, Gerald Appel, mertriver1, lucidreamer15, LonesomeTheBlue, everget.
// CSV research only. Defaults from the supplied files; no execution side effects.
#define AK_SLOTS AK_COUNT
#define AK_RING 512
enum AkSlot
{
 AK_CLOSE,AK_HIGH,AK_LOW,AK_HL2,AK_HLC3,AK_HLCC4,AK_CHANGE,AK_UP,AK_DOWN,AK_TR,
 AK_ATR5,AK_ATR10,AK_ATR22,AK_RSI,AK_RSIUP,AK_RSIDOWN,AK_MFIPOS,AK_MFINEG,
 AK_MFIREALPOS,AK_MFIREALNEG,AK_MFI,AK_MFIREAL,AK_ALPHA,AK_ALPHA_RSI,AK_ALPHA_REAL,
 AK_CCI,AK_MAGIC,AK_BBMID,AK_BBSTD,AK_FOLLOW,AK_FOLLOW_BB,AK_FOLLOW_DIR,
 AK_SUPER_UP,AK_SUPER_DOWN,AK_SUPER_DIR,AK_SUPER,
 AK_VAR2,AK_VAR3,AK_VAR12,AK_VAR26,AK_MACD,AK_MACDTRIGGER,AK_MACDHIST,
 AK_MOST_UP,AK_MOST_DOWN,AK_MOST_DIR,AK_MOST,
 AK_BOOT_BASIS,AK_BOOT_RAWUP,AK_BOOT_RAWLOW,AK_BOOT_MAUP,AK_BOOT_MALOW,
 AK_BOOT_LS1,AK_BOOT_SS1,AK_BOOT_DIR1,AK_BOOT1,AK_BOOT_LS2,AK_BOOT_SS2,AK_BOOT_DIR2,AK_BOOT2,
 AK_HH10,AK_LL10,AK_HVAR,AK_LVAR,AK_HLS,AK_HSS,AK_HDIR,AK_HOTT,AK_LLS,AK_LSS,AK_LDIR,AK_LOTT,
 AK_OTTO_FAST,AK_OTTO_MID,AK_OTTO_SLOW,AK_OTTO_SRC,AK_OTTO_MA,AK_OTTO_LS,AK_OTTO_SS,AK_OTTO_DIR,AK_OTTO,
 AK_STOCH,AK_STOCHK,AK_STOCHSRC,AK_STOCHMA,AK_STOCHLS,AK_STOCHSS,AK_STOCHDIR,AK_STOCHOTT,
 AK_MAV1,AK_MAV2,AK_MAV3,AK_MAV4,AK_MAV5,AK_MAV6,
 AK_T3E1,AK_T3E2,AK_T3E3,AK_T3E4,AK_T3E5,AK_T3E6,AK_T3,
 AK_FIBE1,AK_FIBE2,AK_FIBE3,AK_FIBE4,AK_FIBE5,AK_FIBE6,AK_T3FIB,
 AK_L0,AK_L1,AK_L2,AK_L3,AK_CU,AK_CD,AK_LARSI,
 AK_QFAST,AK_QTR,AK_QWW,AK_QATR,AK_QUP,AK_QDN,AK_QSLOW,
 AK_STOPLONG,AK_STOPSHORT,
 AK_PRUP,AK_PRDOWN,AK_PRSI,AK_PRSIH,AK_PRSIL,AK_PRTR,AK_PRATR,
 AK_PE1,AK_PE2,AK_PE3,AK_PE4,AK_PE5,AK_PE6,AK_PT3,AK_PLS,AK_PSS,AK_PDIR,AK_PMAX,
 AK_TURTLE_HI,AK_TURTLE_LO,AK_TURTLE_EXHI,AK_TURTLE_EXLO,AK_TURTLE_LINE,AK_TURTLE_EXIT,
 AK_ABSCHANGE,AK_RANGE27,AK_RANGE53,AK_RANGE55,AK_RANGE109,AK_RANGE,AK_FILT,AK_FUB,AK_FLB,AK_TRF,AK_FILTUP,AK_FILTDOWN,
 AK_RSX28,AK_RSX30,AK_RSX38,AK_RSX40,AK_RSX48,AK_RSX50,AK_RSX58,AK_RSX60,AK_RSX68,AK_RSX70,AK_RSX78,AK_RSX80,AK_RSX88,AK_RSX90,AK_RSX,
 AK_PIVOTHI,AK_PIVOTLO,AK_PIVOTCENTER,AK_PIVOTUP,AK_PIVOTDOWN,AK_PIVOTDIR,AK_PIVOTST,
 AK_TR_RAW,AK_GAIN_ZERO,AK_LOSS_ZERO,AK_ALPHA_SIGNAL,AK_ALPHA_RSI_SIGNAL,AK_ALPHA_REAL_SIGNAL,
 AK_TURTLE_BUY,AK_TURTLE_SELL,AK_TURTLE_BUYEXIT,AK_TURTLE_SELLEXIT,
 AK_TURTLE_BUY_AGE,AK_TURTLE_SELL_AGE,AK_TURTLE_BUYEXIT_AGE,AK_TURTLE_SELLEXIT_AGE,
 AK_TURTLE_ENTRY_LONG,AK_TURTLE_ENTRY_SHORT,AK_TURTLE_EXIT_LONG,AK_TURTLE_EXIT_SHORT,
 AK_ZIGTOP,AK_ZIGBOTTOM,AK_ZIGBUY,AK_ZIGSELL,AK_ZIGDIR,AK_COUNT
};
string AkRawNames(){return "close,high,low,hl2,hlc3,hlcc4,change,up,down,tr,atr5,atr10,atr22,rsi,rsiup,rsidown,mfipos,mfineg,mfirealpos,mfirealneg,mfi,mfireal,alpha,alpha_rsi,alpha_real,cci,magic,bbmid,bbstd,follow,follow_bb,follow_dir,super_up,super_down,super_dir,super,var2,var3,var12,var26,macd,macdtrigger,macdhist,most_up,most_down,most_dir,most,boot_basis,boot_rawup,boot_rawlow,boot_maup,boot_malow,boot_ls1,boot_ss1,boot_dir1,boot1,boot_ls2,boot_ss2,boot_dir2,boot2,hh10,ll10,hvar,lvar,hls,hss,hdir,hott,lls,lss,ldir,lott,otto_fast,otto_mid,otto_slow,otto_src,otto_ma,otto_ls,otto_ss,otto_dir,otto,stoch,stochk,stochsrc,stochma,stochls,stochss,stochdir,stochott,mav1,mav2,mav3,mav4,mav5,mav6,t3e1,t3e2,t3e3,t3e4,t3e5,t3e6,t3,fibe1,fibe2,fibe3,fibe4,fibe5,fibe6,t3fib,l0,l1,l2,l3,cu,cd,larsi,qfast,qtr,qww,qatr,qup,qdn,qslow,stoplong,stopshort,prup,prdown,prsi,prsih,prsil,prtr,pratr,pe1,pe2,pe3,pe4,pe5,pe6,pt3,pls,pss,pdir,pmax,turtle_hi,turtle_lo,turtle_exhi,turtle_exlo,turtle_line,turtle_exit,abschange,range27,range53,range55,range109,range,filt,fub,flb,trf,filtup,filtdown,rsx28,rsx30,rsx38,rsx40,rsx48,rsx50,rsx58,rsx60,rsx68,rsx70,rsx78,rsx80,rsx88,rsx90,rsx,pivothi,pivotlo,pivotcenter,pivotup,pivotdown,pivotdir,pivotst,tr_raw,gain_zero,loss_zero,alpha_signal,alpha_rsi_signal,alpha_real_signal,turtle_buy,turtle_sell,turtle_buyexit,turtle_sellexit,turtle_buy_age,turtle_sell_age,turtle_buyexit_age,turtle_sellexit_age,turtle_entry_long,turtle_entry_short,turtle_exit_long,turtle_exit_short,zigtop,zigbottom,zigbuy,zigsell,zigdir";}
bool AkValid(double v){return v!=EMPTY_VALUE&&MathIsValidNumber(v);}
double AkNz(double v,double fallback=0){return AkValid(v)?v:fallback;}
int AkSign(double v){return v>0?1:(v<0?-1:0);}
class AkEngine
{
private:
 double data[AK_SLOTS][AK_RING];
 int cursor,bars,ageBuy[32],ageSell[32];
 datetime first,last;
 int turtleHighAt,turtleLowAt;
 double zigStart[2],zigEnd[2];
 int zigCount,zigDirection;
 double MaxMin(int slot,int length,bool highest,int lag=0)
 {
   double v=EMPTY_VALUE;
   for(int j=lag;j<lag+length&&j<bars;j++)
   {double x=Get(slot,j);if(AkValid(x))v=!AkValid(v)?x:(highest?MathMax(v,x):MathMin(v,x));}
   return v;
 }
 double Mean(int slot,int length,bool weighted=false)
 {
   double sum=0,weight=0;int found=0;
   for(int j=0;j<AK_RING&&j<bars&&found<length;j++)
   {double x=Get(slot,j);if(!AkValid(x))continue;double w=weighted?length-found:1;sum+=x*w;weight+=w;found++;}
   return found==length?sum/weight:EMPTY_VALUE;
 }
 double Std(int slot,int length)
 {
   double mean=Mean(slot,length),sum=0;int found=0;if(!AkValid(mean))return EMPTY_VALUE;
   for(int j=0;j<AK_RING&&j<bars&&found<length;j++)
   {double x=Get(slot,j);if(AkValid(x)){sum+=(x-mean)*(x-mean);found++;}}
   return MathSqrt(sum/length);
 }
 double Ema(int dst,double x,double length)
 {double p=Get(dst,1);double v=!AkValid(x)?p:(!AkValid(p)?x:2/(length+1)*x+(1-2/(length+1))*p);Set(dst,v);return v;}
 double Rma(int dst,int source,int length)
 {double x=Get(source),p=Get(dst,1);double v=!AkValid(p)?Mean(source,length):(!AkValid(x)?p:(x+(length-1)*p)/length);Set(dst,v);return v;}
 double Var(int dst,int source,double length)
 {
   double u=0,d=0;bool ready=bars>=9;
   for(int j=0;j<9;j++){double x=Get(source,j),p=Get(source,j+1);if(AkValid(x)&&AkValid(p)){u+=MathMax(0,x-p);d+=MathMax(0,p-x);}}
   double cmo=ready&&u+d>0?(u-d)/(u+d):0,a=2/(length+1)*MathAbs(cmo);
   double v=(AkValid(Get(source))?a*Get(source):0)+(1-a)*AkNz(Get(dst,1));Set(dst,v);return v;
 }
 double T3(int firstSlot,int dst,double source,int length,double factor)
 {
   double x=source;for(int j=0;j<6;j++)x=Ema(firstSlot+j,x,length);
   if(!AkValid(x)){Set(dst,EMPTY_VALUE);return EMPTY_VALUE;}
   double a=factor,a2=a*a,a3=a2*a;
   x=-a3*Get(firstSlot+5)+(3*a2+3*a3)*Get(firstSlot+4)+(-6*a2-3*a-3*a3)*Get(firstSlot+3)+(1+3*a+a3+3*a2)*Get(firstSlot+2);
   Set(dst,x);return x;
 }
 void Trail(int source,double width,int ls,int ss,int dir,int output,double ottPercent=-1)
 {
   double x=Get(source);int direction=(int)AkNz(Get(dir,1),1);
   if(!AkValid(x)||!AkValid(width)){Set(dir,direction);return;}
   double l=x-width,s=x+width,lp=AkNz(Get(ls,1),l),sp=AkNz(Get(ss,1),s);
   Set(ls,x>lp?MathMax(l,lp):l);Set(ss,x<sp?MathMin(s,sp):s);
   if(direction==-1&&x>sp)direction=1;else if(direction==1&&x<lp)direction=-1;
   Set(dir,direction);double mt=Get(direction==1?ls:ss);
   Set(output,ottPercent<0?mt:mt*(200+(x>mt?ottPercent:-ottPercent))/200);
 }
 void Super(double center,double atr,int up,int down,int dir,int output,bool pivot=false)
 {
   int d=(int)AkNz(Get(dir,1),1);double c=Get(AK_CLOSE),p=Get(AK_CLOSE,1);
   if(!AkValid(center)||!AkValid(atr)){Set(dir,d);return;}
   double u=center-3*atr,v=center+3*atr,pu=AkNz(Get(up,1),u),pv=AkNz(Get(down,1),v);
   Set(up,AkValid(p)&&p>pu?MathMax(u,pu):u);Set(down,AkValid(p)&&p<pv?MathMin(v,pv):v);
   if(pivot){if(AkValid(Get(down,1))&&c>Get(down,1))d=1;else if(AkValid(Get(up,1))&&c<Get(up,1))d=-1;}
   else {if(d==-1&&c>pv)d=1;else if(d==1&&c<pu)d=-1;}
   Set(dir,d);Set(output,Get(d==1?up:down));
 }
 double Money(int pos,int neg)
 {double p=Mean(pos,14),n=Mean(neg,14);return AkValid(p)&&AkValid(n)&&p+n>0?100*p/(p+n):EMPTY_VALUE;}
 double RsiRatio(double u,double d)
 {return AkValid(u)&&AkValid(d)&&u+d>0?100*u/(u+d):EMPTY_VALUE;}
 void Event(string &head,string &row,string name,int event,int group,int direction)
 {
   // Source events + derived ages; unknown age stays missing, never zero.
   if(event==1)ageBuy[group]=bars;if(event==-1)ageSell[group]=bars;
   Field(head,row,name+"_event",event);Field(head,row,name+"_buy_age",ageBuy[group]>=0?bars-ageBuy[group]:EMPTY_VALUE);
   Field(head,row,name+"_sell_age",ageSell[group]>=0?bars-ageSell[group]:EMPTY_VALUE);
   Field(head,row,"derived_"+name+"_aligned",event==0?0:event*direction);
 }
public:
 AkEngine(){Reset();}
 void Reset()
 {
   cursor=-1;bars=0;first=0;last=0;turtleHighAt=-1;turtleLowAt=-1;
   zigCount=0;zigDirection=0;ArrayInitialize(zigStart,0);ArrayInitialize(zigEnd,0);
   for(int i=0;i<AK_SLOTS;i++)for(int j=0;j<AK_RING;j++)data[i][j]=EMPTY_VALUE;
   ArrayInitialize(ageBuy,-1);ArrayInitialize(ageSell,-1);
 }
 double Get(int slot,int lag=0)
 {if(slot<0||slot>=AK_SLOTS||lag<0||lag>=AK_RING||lag>=bars)return EMPTY_VALUE;return data[slot][(cursor-lag+AK_RING)%AK_RING];}
 void Set(int slot,double v){data[slot][cursor]=MathIsValidNumber(v)?v:EMPTY_VALUE;}
 int Count(){return bars;}
 datetime First(){return first;}
 datetime Last(){return last;}
 int Cross(double a,double b,double pa,double pb)
 {if(!AkValid(a)||!AkValid(b)||!AkValid(pa)||!AkValid(pb))return 0;return a>b&&pa<=pb?1:(a<b&&pa>=pb?-1:0);}
 int CrossSlots(int a,int b,int lagB=0)
 {return Cross(Get(a),Get(b,lagB),Get(a,1),Get(b,lagB+1));}
 void Push(const MqlRates &r)
 {
   cursor=(cursor+1)%AK_RING;bars++;last=r.time;if(first==0)first=last;
   for(int j=0;j<AK_SLOTS;j++)data[j][cursor]=EMPTY_VALUE;
   double c=r.close,h=r.high,l=r.low,p=Get(AK_CLOSE,1),ch=AkValid(p)?c-p:EMPTY_VALUE;
   Set(AK_CLOSE,c);Set(AK_HIGH,h);Set(AK_LOW,l);Set(AK_HL2,(h+l)/2);Set(AK_HLC3,(h+l+c)/3);Set(AK_HLCC4,(h+l+2*c)/4);
   Set(AK_CHANGE,ch);Set(AK_UP,AkValid(ch)?MathMax(0,ch):EMPTY_VALUE);Set(AK_DOWN,AkValid(ch)?MathMax(0,-ch):EMPTY_VALUE);
   Set(AK_TR,AkValid(p)?MathMax(h-l,MathMax(MathAbs(h-p),MathAbs(l-p))):h-l);
   Set(AK_TR_RAW,AkValid(p)?Get(AK_TR):EMPTY_VALUE);Set(AK_GAIN_ZERO,AkNz(Get(AK_UP)));Set(AK_LOSS_ZERO,AkNz(Get(AK_DOWN)));
   Rma(AK_ATR5,AK_TR,5);Rma(AK_ATR10,AK_TR,10);Rma(AK_ATR22,AK_TR,22);
   Rma(AK_RSIUP,AK_UP,14);Rma(AK_RSIDOWN,AK_DOWN,14);Set(AK_RSI,RsiRatio(Get(AK_RSIUP),Get(AK_RSIDOWN)));
   double typ=Get(AK_HLC3),prevtyp=Get(AK_HLC3,1);bool rising=AkValid(prevtyp)&&typ>prevtyp,falling=AkValid(prevtyp)&&typ<prevtyp;
   Set(AK_MFIPOS,rising?typ*(double)r.tick_volume:0);Set(AK_MFINEG,falling?typ*(double)r.tick_volume:0);
   Set(AK_MFIREALPOS,rising?typ*(double)r.real_volume:0);Set(AK_MFIREALNEG,falling?typ*(double)r.real_volume:0);
   Set(AK_MFI,Money(AK_MFIPOS,AK_MFINEG));Set(AK_MFIREAL,Money(AK_MFIREALPOS,AK_MFIREALNEG));
   double tr14=Mean(AK_TR_RAW,14),tr5=Mean(AK_TR_RAW,5);
   int alphas[3]={AK_ALPHA,AK_ALPHA_RSI,AK_ALPHA_REAL},osc[3]={AK_MFI,AK_RSI,AK_MFIREAL};
   for(int j=0;j<3;j++)
   {
     double old=AkNz(Get(alphas[j],1));bool up=AkValid(Get(osc[j]))&&Get(osc[j])>=50;
     double v=up?MathMax(l-tr14,old):MathMin(h+tr14,old);
     Set(alphas[j],AkValid(tr14)&&(j!=2||AkValid(Get(AK_MFIREAL)))?v:EMPTY_VALUE);
   }
   double mean20=Mean(AK_CLOSE,20),mad=0;
   if(AkValid(mean20)){for(int j=0;j<20;j++)mad+=MathAbs(Get(AK_CLOSE,j)-mean20);Set(AK_CCI,mad>0?(c-mean20)/(0.015*mad/20):EMPTY_VALUE);}
   Set(AK_MAGIC,AkValid(tr5)?(AkValid(Get(AK_CCI))&&Get(AK_CCI)>=0?MathMax(l-tr5,AkNz(Get(AK_MAGIC,1))):MathMin(h+tr5,AkNz(Get(AK_MAGIC,1)))):EMPTY_VALUE);
   Set(AK_BBMID,Mean(AK_CLOSE,21));Set(AK_BBSTD,Std(AK_CLOSE,21));
   int bb=(int)AkNz(Get(AK_FOLLOW_BB,1));double bm=Get(AK_BBMID),sd=Get(AK_BBSTD);
   if(AkValid(bm)&&AkValid(sd)){if(c>bm+sd)bb=1;else if(c<bm-sd)bb=-1;}Set(AK_FOLLOW_BB,bb);
   double fl=Get(AK_FOLLOW,1),af=Get(AK_ATR5);
   if(bb==1&&AkValid(af))fl=MathMax(l-af,AkNz(fl));else if(bb==-1&&AkValid(af))fl=MathMin(h+af,AkNz(fl));
   Set(AK_FOLLOW,fl);int fd=(int)AkNz(Get(AK_FOLLOW_DIR,1));double fc=AkNz(fl)-AkNz(Get(AK_FOLLOW,1));if(fc!=0)fd=AkSign(fc);Set(AK_FOLLOW_DIR,fd);
   Super(Get(AK_HL2),Get(AK_ATR10),AK_SUPER_UP,AK_SUPER_DOWN,AK_SUPER_DIR,AK_SUPER);
   Var(AK_VAR2,AK_CLOSE,2);Var(AK_VAR3,AK_CLOSE,3);Var(AK_VAR12,AK_CLOSE,12);Var(AK_VAR26,AK_CLOSE,26);
   Set(AK_MACD,Get(AK_VAR12)-Get(AK_VAR26));Var(AK_MACDTRIGGER,AK_MACD,9);Set(AK_MACDHIST,Get(AK_MACD)-Get(AK_MACDTRIGGER));
   Trail(AK_VAR3,Get(AK_VAR3)*0.02,AK_MOST_UP,AK_MOST_DOWN,AK_MOST_DIR,AK_MOST);
   Set(AK_BOOT_BASIS,Get(AK_VAR2));double dev=2*Std(AK_CLOSE,2);
   if(AkValid(dev)){Set(AK_BOOT_RAWUP,Get(AK_VAR2)+dev);Set(AK_BOOT_RAWLOW,Get(AK_VAR2)-dev);}
   Var(AK_BOOT_MAUP,AK_BOOT_RAWUP,2);Var(AK_BOOT_MALOW,AK_BOOT_RAWLOW,2);
   Trail(AK_BOOT_MAUP,Get(AK_BOOT_MAUP)*0.10,AK_BOOT_LS1,AK_BOOT_SS1,AK_BOOT_DIR1,AK_BOOT1,10);
   Trail(AK_BOOT_MALOW,Get(AK_BOOT_MALOW)*0.10,AK_BOOT_LS2,AK_BOOT_SS2,AK_BOOT_DIR2,AK_BOOT2,10);
   Set(AK_HH10,MaxMin(AK_HIGH,10,true));Set(AK_LL10,MaxMin(AK_LOW,10,false));Var(AK_HVAR,AK_HH10,2);Var(AK_LVAR,AK_LL10,2);
   Trail(AK_HVAR,Get(AK_HVAR)*0.006,AK_HLS,AK_HSS,AK_HDIR,AK_HOTT,0.6);
   Trail(AK_LVAR,Get(AK_LVAR)*0.006,AK_LLS,AK_LSS,AK_LDIR,AK_LOTT,0.6);
   Var(AK_OTTO_FAST,AK_CLOSE,12.5);Var(AK_OTTO_MID,AK_CLOSE,25);Var(AK_OTTO_SLOW,AK_CLOSE,250);
   double denom=Get(AK_OTTO_MID)-Get(AK_OTTO_SLOW)+100000;
   Set(AK_OTTO_SRC,denom!=0?Get(AK_OTTO_FAST)/denom:EMPTY_VALUE);Var(AK_OTTO_MA,AK_OTTO_SRC,2);
   Trail(AK_OTTO_MA,Get(AK_OTTO_MA)*0.006,AK_OTTO_LS,AK_OTTO_SS,AK_OTTO_DIR,AK_OTTO,0.6);
   double hh=MaxMin(AK_HIGH,250,true),ll=MaxMin(AK_LOW,250,false);
   Set(AK_STOCH,hh>ll?100*(c-ll)/(hh-ll):EMPTY_VALUE);Var(AK_STOCHK,AK_STOCH,50);Set(AK_STOCHSRC,Get(AK_STOCHK)+1000);Var(AK_STOCHMA,AK_STOCHSRC,3);
   Trail(AK_STOCHMA,Get(AK_STOCHMA)*0.00618,AK_STOCHLS,AK_STOCHSS,AK_STOCHDIR,AK_STOCHOTT,0.618);
   int lengths[6]={3,5,8,13,21,34};for(int j=0;j<6;j++)Set(AK_MAV1+j,Mean(j==0?AK_CLOSE:AK_MAV1+j-1,lengths[j],true));
   T3(AK_T3E1,AK_T3,Get(AK_HLCC4),8,0.7);T3(AK_FIBE1,AK_T3FIB,Get(AK_HLCC4),5,0.618);
   Set(AK_L0,0.2*c+0.8*AkNz(Get(AK_L0,1)));
   for(int j=1;j<4;j++)Set(AK_L0+j,-0.8*Get(AK_L0+j-1)+AkNz(Get(AK_L0+j-1,1))+0.8*AkNz(Get(AK_L0+j,1)));
   double cu=0,cd=0;for(int j=0;j<3;j++){double diff=Get(AK_L0+j)-Get(AK_L0+j+1);cu+=MathMax(0,diff);cd+=MathMax(0,-diff);}
   Set(AK_CU,cu);Set(AK_CD,cd);Set(AK_LARSI,cu+cd==0?0:100*cu/(cu+cd));
   Ema(AK_QFAST,Get(AK_RSI),5);double q=Get(AK_QFAST),qp=Get(AK_QFAST,1);
   Set(AK_QTR,AkValid(q)&&AkValid(qp)?MathAbs(q-qp):EMPTY_VALUE);
   Set(AK_QWW,AkValid(Get(AK_QTR))?Get(AK_QTR)/14+13.0/14*AkNz(Get(AK_QWW,1)):EMPTY_VALUE);
   Set(AK_QATR,AkValid(Get(AK_QWW))?Get(AK_QWW)/14+13.0/14*AkNz(Get(AK_QATR,1)):EMPTY_VALUE);
   double qu=AkValid(Get(AK_QATR))?q+4.236*Get(AK_QATR):EMPTY_VALUE,qd=AkValid(Get(AK_QATR))?q-4.236*Get(AK_QATR):EMPTY_VALUE,qs=AkNz(Get(AK_QSLOW,1));
   Set(AK_QUP,qu);Set(AK_QDN,qd);
   Set(AK_QSLOW,AkValid(qu)&&qu<qs?qu:AkValid(q)&&AkValid(qp)&&q>qs&&qp<qs?qd:AkValid(qd)&&qd>qs?qd:AkValid(q)&&AkValid(qp)&&q<qs&&qp>qs?qu:qs);
   double slp=AkNz(Get(AK_STOPLONG,1)),ssp=AkNz(Get(AK_STOPSHORT,1));
   Set(AK_STOPLONG,c*0.97>slp||(AkValid(p)&&p<slp)?c*0.97:slp);Set(AK_STOPSHORT,c*1.03<ssp||(AkValid(p)&&p>ssp)?c*1.03:ssp);
   // PMax RSI uses zero-seeded WWMA, SMA gain/loss for RSI high/low, not iRSI.
   Set(AK_PRUP,AkNz(Get(AK_UP))/14+13.0/14*AkNz(Get(AK_PRUP,1)));Set(AK_PRDOWN,AkNz(Get(AK_DOWN))/14+13.0/14*AkNz(Get(AK_PRDOWN,1)));
   Set(AK_PRSI,Get(AK_PRDOWN)>0?RsiRatio(Get(AK_PRUP),Get(AK_PRDOWN)):EMPTY_VALUE);
   double au=Mean(AK_GAIN_ZERO,14),ad=Mean(AK_LOSS_ZERO,14);
   if(AkValid(au)&&AkValid(ad)&&AkValid(p))
   {double dh=ad*13+MathMax(0,p-h),dl=ad*13+MathMax(0,p-l);Set(AK_PRSIH,dh>0?RsiRatio(au*13+MathMax(0,h-p),dh):EMPTY_VALUE);Set(AK_PRSIL,dl>0?RsiRatio(au*13+MathMax(0,l-p),dl):EMPTY_VALUE);}
   double rh=Get(AK_PRSIH),rl=Get(AK_PRSIL),rp=Get(AK_PRSI,1);
   Set(AK_PRTR,AkValid(rh)&&AkValid(rl)&&AkValid(rp)?MathMax(rh-rl,MathMax(MathAbs(rh-rp),MathAbs(rl-rp))):EMPTY_VALUE);
   Set(AK_PRATR,Mean(AK_PRTR,10));T3(AK_PE1,AK_PT3,Get(AK_PRSI),8,0.7);
   Trail(AK_PT3,AkValid(Get(AK_PRATR))?3*Get(AK_PRATR):EMPTY_VALUE,AK_PLS,AK_PSS,AK_PDIR,AK_PMAX);
   Set(AK_TURTLE_HI,MaxMin(AK_HIGH,20,true));Set(AK_TURTLE_LO,MaxMin(AK_LOW,20,false));Set(AK_TURTLE_EXHI,Get(AK_HH10));Set(AK_TURTLE_EXLO,Get(AK_LL10));
   if(AkValid(Get(AK_TURTLE_HI,1))&&h>=Get(AK_TURTLE_HI,1))turtleHighAt=bars;
   if(AkValid(Get(AK_TURTLE_LO,1))&&l<=Get(AK_TURTLE_LO,1))turtleLowAt=bars;
   bool turtleUp=turtleHighAt>=0&&turtleLowAt>=0&&turtleHighAt>=turtleLowAt;
   Set(AK_TURTLE_LINE,Get(turtleUp?AK_TURTLE_LO:AK_TURTLE_HI));Set(AK_TURTLE_EXIT,Get(turtleUp?AK_TURTLE_EXLO:AK_TURTLE_EXHI));
   bool te[4];
   te[0]=h==Get(AK_TURTLE_HI,1)||CrossSlots(AK_HIGH,AK_TURTLE_HI,1)==1;
   te[1]=l==Get(AK_TURTLE_LO,1)||CrossSlots(AK_LOW,AK_TURTLE_LO,1)==-1;
   te[2]=l==Get(AK_TURTLE_EXLO,1)||CrossSlots(AK_LOW,AK_TURTLE_EXLO,1)==-1;
   te[3]=h==Get(AK_TURTLE_EXHI,1)||CrossSlots(AK_HIGH,AK_TURTLE_EXHI,1)==1;
   for(int j=0;j<4;j++){Set(AK_TURTLE_BUY+j,te[j]);double prevAge=Get(AK_TURTLE_BUY_AGE+j,1);Set(AK_TURTLE_BUY_AGE+j,te[j]?0:AkValid(prevAge)?prevAge+1:EMPTY_VALUE);}
   int opposite[4]={2,3,0,1};
   for(int j=0;j<4;j++)Set(AK_TURTLE_ENTRY_LONG+j,te[j]&&AkValid(Get(AK_TURTLE_BUY_AGE+opposite[j]))&&AkValid(Get(AK_TURTLE_BUY_AGE+j,1))&&Get(AK_TURTLE_BUY_AGE+opposite[j])<Get(AK_TURTLE_BUY_AGE+j,1));
   Set(AK_ABSCHANGE,AkValid(ch)?MathAbs(ch):EMPTY_VALUE);Ema(AK_RANGE27,Get(AK_ABSCHANGE),27);Ema(AK_RANGE53,Get(AK_RANGE27),53);Ema(AK_RANGE55,Get(AK_ABSCHANGE),55);Ema(AK_RANGE109,Get(AK_RANGE55),109);
   double range=AkValid(Get(AK_RANGE53))&&AkValid(Get(AK_RANGE109))?(1.6*Get(AK_RANGE53)+2*Get(AK_RANGE109))/2:EMPTY_VALUE;
   Set(AK_RANGE,range);double old=AkNz(Get(AK_FILT,1));double filt=AkValid(range)?(c>old?MathMax(old,c-range):MathMin(old,c+range)):EMPTY_VALUE;Set(AK_FILT,filt);
   Set(AK_FILTUP,AkValid(filt)&&AkValid(Get(AK_FILT,1))&&filt>Get(AK_FILT,1)?AkNz(Get(AK_FILTUP,1))+1:AkValid(filt)&&AkValid(Get(AK_FILT,1))&&filt<Get(AK_FILT,1)?0:AkNz(Get(AK_FILTUP,1)));
   Set(AK_FILTDOWN,AkValid(filt)&&AkValid(Get(AK_FILT,1))&&filt<Get(AK_FILT,1)?AkNz(Get(AK_FILTDOWN,1))+1:AkValid(filt)&&AkValid(Get(AK_FILT,1))&&filt>Get(AK_FILT,1)?0:AkNz(Get(AK_FILTDOWN,1)));
   double ub=AkNz(Get(AK_FUB,1)),lb=AkNz(Get(AK_FLB,1)),trf=AkNz(Get(AK_TRF,1));
   if(AkValid(range)&&AkValid(filt)){double u=filt+range,d=filt-range;Set(AK_FUB,u<ub||(AkValid(p)&&p>ub)?u:ub);Set(AK_FLB,d>lb||(AkValid(p)&&p<lb)?d:lb);}
   double fu=Get(AK_FUB),flb=Get(AK_FLB);
   Set(AK_TRF,AkValid(Get(AK_FUB,1))&&trf==Get(AK_FUB,1)&&c<=fu?fu:AkValid(Get(AK_FUB,1))&&trf==Get(AK_FUB,1)&&c>=fu?flb:AkValid(Get(AK_FLB,1))&&trf==Get(AK_FLB,1)&&c>=flb?flb:AkValid(Get(AK_FLB,1))&&trf==Get(AK_FLB,1)&&c<=flb?fu:fu);
   // RSX stages and warmup counter from SuperTrendS, not an RSI substitute.
   double v=100*typ-AkNz(100*Get(AK_HLC3,1)),av=MathAbs(v),a=3.0/16,b=1-a;
   for(int j=0;j<3;j++)
   {int ix=AK_RSX28+j*2,iy=AK_RSX58+j*2;Set(ix,b*AkNz(Get(ix,1))+a*v);Set(ix+1,a*Get(ix)+b*AkNz(Get(ix+1,1)));v=1.5*Get(ix)-0.5*Get(ix+1);Set(iy,b*AkNz(Get(iy,1))+a*av);Set(iy+1,a*Get(iy)+b*AkNz(Get(iy+1,1)));av=1.5*Get(iy)-0.5*Get(iy+1);}
   double p90=AkNz(Get(AK_RSX90,1)),p88=AkNz(Get(AK_RSX88,1)),n90=p90==0?1:p88<=p90?p88+1:p90+1,n88=p90==0?13:5;
   Set(AK_RSX90,n90);Set(AK_RSX88,n88);double f0=n88>=n90&&100*typ!=AkNz(100*Get(AK_HLC3,1))?1:0,final90=n88==n90&&f0==0?0:n90;
   Set(AK_RSX,MathMax(0,MathMin(100,n88<final90&&av>0?(v/av+1)*50:50)));
   // Confirmed 2-left/2-right pivots. Equal more recent extremum takes precedence.
   bool ph=bars>=5,pl=bars>=5;double pivotH=Get(AK_HIGH,2),pivotL=Get(AK_LOW,2);
   for(int j=0;j<5;j++)if(j!=2){if(j<2?Get(AK_HIGH,j)>=pivotH:Get(AK_HIGH,j)>pivotH)ph=false;if(j<2?Get(AK_LOW,j)<=pivotL:Get(AK_LOW,j)<pivotL)pl=false;}
   Set(AK_PIVOTHI,ph?pivotH:Get(AK_PIVOTHI,1));Set(AK_PIVOTLO,pl?pivotL:Get(AK_PIVOTLO,1));
   double center=Get(AK_PIVOTCENTER,1),pp=ph?pivotH:pl?pivotL:EMPTY_VALUE;
   if(AkValid(pp))center=AkValid(center)?(2*center+pp)/3:pp;Set(AK_PIVOTCENTER,center);
   Super(center,Get(AK_ATR10),AK_PIVOTUP,AK_PIVOTDOWN,AK_PIVOTDIR,AK_PIVOTST,true);
   // SuperTrendS ZigZag default: history=2, waitForConfirmation=true.
   // Only the older completed segment contributes, never a hindsight final leg.
   bool zh=h==MaxMin(AK_HIGH,5,true),zl=l==MaxMin(AK_LOW,5,false);
   int oldDirection=zigDirection;if(zh&&!zl)zigDirection=1;else if(zl&&!zh)zigDirection=-1;
   if((zh||zl)&&zigDirection!=0)
   {
      double value=zigDirection==1?(zh?h:EMPTY_VALUE):(zl?l:EMPTY_VALUE);
      bool skip=zigCount>0&&zigDirection==oldDirection&&(zigDirection==1?value<zigEnd[0]:value>zigEnd[0]);
      if(!skip&&AkValid(value))
      {
         if(zigCount>0&&zigDirection==oldDirection){zigStart[0]=zigStart[1];zigEnd[0]=zigEnd[1];zigCount--;}
         double startValue=zigCount>0?zigEnd[0]:(zigDirection==1?MaxMin(AK_LOW,5,false):MaxMin(AK_HIGH,5,true));
         if(startValue!=0&&MathAbs(startValue-value)>0)
         {if(zigCount>0){zigStart[1]=zigStart[0];zigEnd[1]=zigEnd[0];}zigStart[0]=startValue;zigEnd[0]=value;zigCount=MathMin(2,zigCount+1);}
      }
   }
   if(zigCount>1){Set(AK_ZIGTOP,MathMax(zigStart[1],zigEnd[1]));Set(AK_ZIGBOTTOM,MathMin(zigStart[1],zigEnd[1]));}
   int zd=(int)AkNz(Get(AK_ZIGDIR,1),1);double za=Get(AK_ATR22),zt=Get(AK_ZIGTOP),zb=Get(AK_ZIGBOTTOM);
   if(AkValid(za)&&AkValid(zt)&&AkValid(zb))
   {
      double buy=zb-za,sell=zt+za,bp=AkNz(Get(AK_ZIGBUY,1),buy),sp=AkNz(Get(AK_ZIGSELL,1),sell);
      Set(AK_ZIGBUY,zd==1?MathMax(buy,bp):buy);Set(AK_ZIGSELL,zd==-1?MathMin(sell,sp):sell);
      if(zd==1&&Cross(c,bp,p,AkNz(Get(AK_ZIGBUY,2),Get(AK_ZIGBOTTOM,1)-Get(AK_ATR22,1)))==-1)zd=-1;
      else if(zd==-1&&Cross(c,sp,p,AkNz(Get(AK_ZIGSELL,2),Get(AK_ZIGTOP,1)+Get(AK_ATR22,1)))==1)zd=1;
   }
   Set(AK_ZIGDIR,zd);
 }
 void Field(string &head,string &row,string name,double value)
 {AxCell(head,"f_kiv_"+name);AxCell(row,AxNumber(value));}
 void Line(string &head,string &row,string name,int slot,int direction,bool price=true,int lag=0)
 {
   double x=Get(slot,lag),p=Get(slot,lag+1),a=Get(AK_ATR10);
   Field(head,row,name,x);Field(head,row,"derived_"+name+"_slope",AkValid(x)&&AkValid(p)?x-p:EMPTY_VALUE);
   if(price){Field(head,row,"derived_"+name+"_distance_atr",AkValid(x)&&AkValid(a)&&a>0?(Get(AK_CLOSE)-x)/a:EMPTY_VALUE);Field(head,row,"derived_"+name+"_side_alignment",AkValid(x)?direction*AkSign(Get(AK_CLOSE)-x):EMPTY_VALUE);}
 }
 string Snapshot(string &head,int direction)
 {
   head="";string row="";
   AxCell(head,"f_kiv_status");AxCell(row,bars>=500?"SEEDED_LOCAL_HISTORY":"WARMUP");
   AxCell(head,"f_kiv_seed_time");AxCell(row,AxTime(first));Field(head,row,"seed_bars",bars);
   AxCell(head,"f_kiv_last_closed_bar");AxCell(row,AxTime(last));
   Line(head,row,"alpha_tick_volume_proxy",AK_ALPHA,direction);Line(head,row,"alpha_rsi",AK_ALPHA_RSI,direction);Line(head,row,"alpha_real_volume",AK_ALPHA_REAL,direction);
   Line(head,row,"mfi_tick_volume_proxy",AK_MFI,direction,false);Line(head,row,"mfi_real_volume",AK_MFIREAL,direction,false);
   Line(head,row,"magic_cci_close",AK_CCI,direction,false);Line(head,row,"magic",AK_MAGIC,direction);
   Line(head,row,"follow",AK_FOLLOW,direction);Field(head,row,"follow_bb_state",Get(AK_FOLLOW_BB));Field(head,row,"follow_trend",Get(AK_FOLLOW_DIR));
   Line(head,row,"supertrend",AK_SUPER,direction);Line(head,row,"supertrend_up",AK_SUPER_UP,direction);Line(head,row,"supertrend_down",AK_SUPER_DOWN,direction);Field(head,row,"supertrend_direction",Get(AK_SUPER_DIR));
   Line(head,row,"var12",AK_VAR12,direction);Line(head,row,"var26",AK_VAR26,direction);Line(head,row,"macd_var",AK_MACD,direction,false);Line(head,row,"macd_var_trigger",AK_MACDTRIGGER,direction,false);Line(head,row,"macd_var_hist",AK_MACDHIST,direction,false);
   Line(head,row,"most_ma",AK_VAR3,direction);Line(head,row,"most",AK_MOST,direction);Field(head,row,"most_direction",Get(AK_MOST_DIR));
   Line(head,row,"boots_basis",AK_BOOT_BASIS,direction);Line(head,row,"boots_high_lag2",AK_BOOT1,direction,true,2);Line(head,row,"boots_low_lag2",AK_BOOT2,direction,true,2);
   Line(head,row,"hott_lag2",AK_HOTT,direction,true,2);Line(head,row,"lott_lag2",AK_LOTT,direction,true,2);
   Line(head,row,"otto_source",AK_OTTO_SRC,direction,false);Line(head,row,"otto_lag2",AK_OTTO,direction,false,2);
   Line(head,row,"sott_raw_stoch250",AK_STOCH,direction,false);Line(head,row,"sott_k_var50",AK_STOCHK,direction,false);Line(head,row,"sott_lag2",AK_STOCHOTT,direction,false,2);
   Line(head,row,"mavilim",AK_MAV6,direction);Line(head,row,"t3_hlcc4",AK_T3,direction);Line(head,row,"t3_fibo",AK_T3FIB,direction);
   Line(head,row,"laguerre_rsi",AK_LARSI,direction,false);Field(head,row,"laguerre_cu",Get(AK_CU));Field(head,row,"laguerre_cd",Get(AK_CD));
   Line(head,row,"qqe_fast",AK_QFAST,direction,false);Line(head,row,"qqe_slow",AK_QSLOW,direction,false);Field(head,row,"nqqe_fast",AkValid(Get(AK_QFAST))?Get(AK_QFAST)-50:EMPTY_VALUE);Field(head,row,"qqe_atr_rsi",Get(AK_QATR));Field(head,row,"qqe_region",AkValid(Get(AK_QFAST))?(Get(AK_QFAST)>60?1:Get(AK_QFAST)<40?-1:0):EMPTY_VALUE);
   Line(head,row,"stop_long",AK_STOPLONG,direction);Line(head,row,"stop_short",AK_STOPSHORT,direction);
   Line(head,row,"pmax_rsi",AK_PRSI,direction,false);Field(head,row,"pmax_rsi_high",Get(AK_PRSIH));Field(head,row,"pmax_rsi_low",Get(AK_PRSIL));Field(head,row,"pmax_rsi_atr",Get(AK_PRATR));Line(head,row,"pmax_t3",AK_PT3,direction,false);Line(head,row,"pmax",AK_PMAX,direction,false);
   Line(head,row,"turtle_high20",AK_TURTLE_HI,direction);Line(head,row,"turtle_low20",AK_TURTLE_LO,direction);Line(head,row,"turtle_exit_high10",AK_TURTLE_EXHI,direction);Line(head,row,"turtle_exit_low10",AK_TURTLE_EXLO,direction);Line(head,row,"turtle_trend_line",AK_TURTLE_LINE,direction);Line(head,row,"turtle_exit_line",AK_TURTLE_EXIT,direction);
   Line(head,row,"twin_range_filter",AK_FILT,direction);Line(head,row,"twin_range_trf",AK_TRF,direction);Field(head,row,"twin_range_width",Get(AK_RANGE));Field(head,row,"twin_up_run",Get(AK_FILTUP));Field(head,row,"twin_down_run",Get(AK_FILTDOWN));
   Line(head,row,"rsx",AK_RSX,direction,false);Field(head,row,"rsx_overbought",Get(AK_RSX)>70);Field(head,row,"rsx_oversold",Get(AK_RSX)<30);
   Line(head,row,"confirmed_pivot_resistance",AK_PIVOTHI,direction);Line(head,row,"confirmed_pivot_support",AK_PIVOTLO,direction);Line(head,row,"confirmed_pivot_center",AK_PIVOTCENTER,direction);Line(head,row,"pivot_supertrend",AK_PIVOTST,direction);
   Line(head,row,"zig_confirmed_top",AK_ZIGTOP,direction);Line(head,row,"zig_confirmed_bottom",AK_ZIGBOTTOM,direction);Line(head,row,"zig_buy_stop",AK_ZIGBUY,direction);Line(head,row,"zig_sell_stop",AK_ZIGSELL,direction);Field(head,row,"zig_direction",Get(AK_ZIGDIR));
   Field(head,row,"alpha_filtered_tick_signal",Get(AK_ALPHA_SIGNAL));Field(head,row,"alpha_filtered_rsi_signal",Get(AK_ALPHA_RSI_SIGNAL));Field(head,row,"alpha_filtered_real_signal",Get(AK_ALPHA_REAL_SIGNAL));
   string tn[4]={"turtle_buy","turtle_sell","turtle_buyexit","turtle_sellexit"};
   for(int j=0;j<4;j++){Field(head,row,tn[j]+"_raw",Get(AK_TURTLE_BUY+j));Field(head,row,tn[j]+"_age",Get(AK_TURTLE_BUY_AGE+j));Field(head,row,tn[j]+"_filtered",Get(AK_TURTLE_ENTRY_LONG+j));}
   Field(head,row,"magic_low_cross",CrossSlots(AK_LOW,AK_MAGIC)==1);Field(head,row,"magic_high_cross",CrossSlots(AK_HIGH,AK_MAGIC)==-1);
   Field(head,row,"stop_long_exit",CrossSlots(AK_CLOSE,AK_STOPLONG)==-1);Field(head,row,"stop_short_exit",CrossSlots(AK_CLOSE,AK_STOPSHORT)==1);
   double hi=Get(AK_BOOT1,2),lo=Get(AK_BOOT2,2);
   Field(head,row,"derived_boots_width",AkValid(hi)&&AkValid(lo)?hi-lo:EMPTY_VALUE);
   hi=Get(AK_HOTT,2);lo=Get(AK_LOTT,2);Field(head,row,"derived_hlott_range_position",AkValid(hi)&&AkValid(lo)&&hi!=lo?(Get(AK_CLOSE)-lo)/(hi-lo):EMPTY_VALUE);
   int ev[];Events(ev);
   string names[20]={"alpha_raw_tick","alpha_raw_rsi","alpha_raw_real","magic_price_cross","follow_flip","supertrend_flip","macd_cross","most_cross","hlott_break","otto_cross","sott_cross","mavilim_slope_flip","mavilim_price_cross","t3_slope_flip","t3_price_cross","laguerre_cross","qqe_cross","pmax_cross","twin_cross","pivot_st_flip"};
   for(int j=0;j<20;j++)Event(head,row,names[j],ev[j],j,direction);
   string rawNames[];StringSplit(AkRawNames(),',',rawNames);
   for(int j=0;j<ArraySize(rawNames);j++)Field(head,row,"source_"+rawNames[j],Get(j));
   return row;
 }
 // Ages must be updated on EVERY closed bar, including bars without trades.
 void Events(int &ev[])
 {
   ArrayResize(ev,20);
   ev[0]=CrossSlots(AK_ALPHA,AK_ALPHA,2);ev[1]=CrossSlots(AK_ALPHA_RSI,AK_ALPHA_RSI,2);ev[2]=CrossSlots(AK_ALPHA_REAL,AK_ALPHA_REAL,2);
   ev[3]=CrossSlots(AK_CLOSE,AK_MAGIC);ev[4]=Get(AK_FOLLOW_DIR)==1&&Get(AK_FOLLOW_DIR,1)==-1?1:Get(AK_FOLLOW_DIR)==-1&&Get(AK_FOLLOW_DIR,1)==1?-1:0;
   ev[5]=Get(AK_SUPER_DIR)==1&&Get(AK_SUPER_DIR,1)==-1?1:Get(AK_SUPER_DIR)==-1&&Get(AK_SUPER_DIR,1)==1?-1:0;
   ev[6]=CrossSlots(AK_MACD,AK_MACDTRIGGER);ev[7]=CrossSlots(AK_VAR3,AK_MOST);
   ev[8]=CrossSlots(AK_CLOSE,AK_HOTT,2)==1?1:CrossSlots(AK_CLOSE,AK_LOTT,2)==-1?-1:0;
   ev[9]=CrossSlots(AK_OTTO_SRC,AK_OTTO,2);ev[10]=CrossSlots(AK_STOCHSRC,AK_STOCHOTT,2);
   ev[11]=CrossSlots(AK_MAV6,AK_MAV6,1);ev[12]=CrossSlots(AK_CLOSE,AK_MAV6);ev[13]=CrossSlots(AK_T3,AK_T3,1);ev[14]=CrossSlots(AK_CLOSE,AK_T3);
   ev[15]=CrossSlots(AK_CU,AK_CD);ev[16]=CrossSlots(AK_QFAST,AK_QSLOW);ev[17]=CrossSlots(AK_PT3,AK_PMAX);ev[18]=CrossSlots(AK_CLOSE,AK_TRF);
   ev[19]=Get(AK_PIVOTDIR)==1&&Get(AK_PIVOTDIR,1)==-1?1:Get(AK_PIVOTDIR)==-1&&Get(AK_PIVOTDIR,1)==1?-1:0;
 }
 void UpdateEvents()
 {
   int ev[];Events(ev);
   for(int j=0;j<3;j++)
   {int accepted=ev[j]==1&&ageBuy[j]>=0&&ageSell[j]>=0&&ageBuy[j]<ageSell[j]?1:ev[j]==-1&&ageBuy[j]>=0&&ageSell[j]>=0&&ageSell[j]<ageBuy[j]?-1:0;Set(AK_ALPHA_SIGNAL+j,accepted);}
   for(int j=0;j<20;j++){if(ev[j]==1)ageBuy[j]=bars;if(ev[j]==-1)ageSell[j]=bars;}
 }
};
#endif
