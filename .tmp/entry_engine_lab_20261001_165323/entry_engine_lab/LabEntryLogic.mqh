#ifndef LAB_ENTRY_LOGIC_MQH
#define LAB_ENTRY_LOGIC_MQH
#define LAB_FEATURES 44
#define LAB_FIXED_FEATURES 32
#define LAB_MAX_RULES 4096
struct LabRule { int feature,compare,gate,period,rhsFeature,rhsPeriod; double threshold; bool negate; };
void LabRuleDefaults(LabRule &r){ZeroMemory(r);r.period=r.rhsPeriod=14;r.rhsFeature=-1;}
struct LabEngine { string name; bool edge; LabRule buy[],sell[],exitBuy[],exitSell[];
   bool policy;int atrPeriod,cooldown,maxBars,maxMinutes;double slAtr,tpAtr; };
LabEngine g_labEngine;
double g_labGeometryAtr=0;
bool g_labPreviewOnly=false;
bool LabPersistActive();
string LabFeatureName(int i)
{
   string names[]={"Close","Open","High","Low","RSI 14","ADX 14","ATR 14","EMA 9","EMA 20","EMA 50","EMA 200",
      "HMA 200","Tick volume","Volume / prior 20 avg","Body / range","Range / ATR","RSI change","ADX change",
      "Close - EMA20 / ATR","EMA50 crosses above EMA200","EMA50 crosses below EMA200","Bull FVG inside",
      "Bear FVG inside","Bull FVG touched","Bear FVG touched","Bull FVG exists","Bear FVG exists",
      "Hour (bar open broker)","Weekday (broker)","Close change %","Upper wick / range","Lower wick / range",
      "EMA(period)","SMA(period)","RSI(period)","ATR(period)","ADX Wilder(period)","HMA(period)",
      "BB upper 1.5 SD(period)","BB lower 1.5 SD(period)","BB middle(period)",
      "Prior highest high(period)","Prior lowest low(period)","Body / Wilder ATR(period)"};
   return i>=0&&i<LAB_FEATURES?names[i]:"INVALID";
}
string LabCompareName(int i){string a[]={">","<",">=","<=","=","!=","Cross above","Cross below"};return i>=0&&i<8?a[i]:"INVALID";}
string LabGateName(int i){string a[]={"AND","OR","XOR"};return i>=0&&i<3?a[i]:"INVALID";}
bool LabValidRule(const LabRule &r){return r.feature>=0&&r.feature<LAB_FEATURES&&r.rhsFeature>=-1&&r.rhsFeature<LAB_FEATURES&&r.period>=1&&r.period<=5000&&r.rhsPeriod>=1&&r.rhsPeriod<=5000&&r.compare>=0&&r.compare<8&&r.gate>=0&&r.gate<3&&MathIsValidNumber(r.threshold)&&r.threshold!=EMPTY_VALUE;}
bool LabValidEngine(const LabEngine &e)
{
   if(StringLen(e.name)<1||StringLen(e.name)>64||ArraySize(e.buy)>LAB_MAX_RULES||ArraySize(e.sell)>LAB_MAX_RULES
      ||ArraySize(e.exitBuy)>LAB_MAX_RULES||ArraySize(e.exitSell)>LAB_MAX_RULES)return false;
   if(e.policy&&(e.atrPeriod<1||e.atrPeriod>5000||e.cooldown<0||e.cooldown>5000||e.maxBars<0||e.maxBars>5000
      ||e.maxMinutes<0||e.maxMinutes>100000||!MathIsValidNumber(e.slAtr)||!MathIsValidNumber(e.tpAtr)
      ||e.slAtr<=0||e.tpAtr<=0||e.slAtr>1000||e.tpAtr>1000))return false;
   if(ArraySize(e.buy)+ArraySize(e.sell)==0)return false;
   for(int i=0;i<ArraySize(e.buy);i++)if(!LabValidRule(e.buy[i]))return false;
   for(int i=0;i<ArraySize(e.sell);i++)if(!LabValidRule(e.sell[i]))return false;
   for(int i=0;i<ArraySize(e.exitBuy);i++)if(!LabValidRule(e.exitBuy[i]))return false;
   for(int i=0;i<ArraySize(e.exitSell);i++)if(!LabValidRule(e.exitSell[i]))return false;
   string providers[];
   for(int side=0;side<4;side++)for(int i=0;i<(side==0?ArraySize(e.buy):(side==1?ArraySize(e.sell):(side==2?ArraySize(e.exitBuy):ArraySize(e.exitSell))));i++)
   {LabRule r;if(side==0)r=e.buy[i];else if(side==1)r=e.sell[i];else if(side==2)r=e.exitBuy[i];else r=e.exitSell[i];for(int operand=0;operand<2;operand++)
      {int f=operand==0?r.feature:r.rhsFeature,p=operand==0?r.period:r.rhsPeriod;if(f<LAB_FIXED_FEATURES)continue;string key=(string)f+":"+(string)p;bool found=false;
         for(int k=0;k<ArraySize(providers);k++)if(providers[k]==key){found=true;break;}if(!found){int n=ArraySize(providers);if(n>=64)return false;ArrayResize(providers,n+1);providers[n]=key;}}}
   return true;
}
string LabHex(string s){string out="";for(int i=0;i<StringLen(s);i++)out+=StringFormat("%04X",StringGetCharacter(s,i));return out;}
bool LabUnhex(string s,string &out)
{
   out="";if(StringLen(s)%4!=0)return false;
   for(int i=0;i<StringLen(s);i+=4){int value=0;for(int k=0;k<4;k++){int c=StringGetCharacter(s,i+k),d=c>='0'&&c<='9'?c-'0':(c>='A'&&c<='F'?c-'A'+10:-1);if(d<0)return false;value=value*16+d;}out+=ShortToString((ushort)value);}return true;
}
string LabRulesText(const LabRule &rules[])
{
   string s="";for(int i=0;i<ArraySize(rules);i++){if(i>0)s+=";";s+=(string)rules[i].feature+","+(string)rules[i].compare+","+StringFormat("%.17g",rules[i].threshold)+","+(string)rules[i].gate+","+(string)(int)rules[i].negate+","+(string)rules[i].period+","+(string)rules[i].rhsFeature+","+(string)rules[i].rhsPeriod;}return s;
}
string LabPolicyText(const LabEngine &e){return (string)(int)e.policy+","+(string)e.atrPeriod+","+StringFormat("%.17g",e.slAtr)+","+StringFormat("%.17g",e.tpAtr)+","+(string)e.cooldown+","+(string)e.maxBars+","+(string)e.maxMinutes;}
string LabEngineText(const LabEngine &e)
{
   string base=LabHex(e.name)+"~"+(string)(int)e.edge+"~"+LabRulesText(e.buy)+"~"+LabRulesText(e.sell);
   if(!e.policy&&ArraySize(e.exitBuy)==0&&ArraySize(e.exitSell)==0)return "LAB2~"+base;
   return "LAB3~"+base+"~"+LabRulesText(e.exitBuy)+"~"+LabRulesText(e.exitSell)+"~"+LabPolicyText(e);
}
bool LabInteger(string s,int &v){v=(int)StringToInteger(s);return s==(string)v;}
bool LabRulesRead(string s,LabRule &rules[])
{
   ArrayResize(rules,0);if(s=="")return true;string rows[];int n=StringSplit(s,';',rows);if(n<1||n>LAB_MAX_RULES)return false;
   ArrayResize(rules,n);
   for(int i=0;i<n;i++){string v[];int neg=0;if(StringSplit(rows[i],',',v)!=8||!LabInteger(v[0],rules[i].feature)||!LabInteger(v[1],rules[i].compare)||!LabInteger(v[3],rules[i].gate)||!LabInteger(v[4],neg)||(neg!=0&&neg!=1)
      ||!LabInteger(v[5],rules[i].period)||!LabInteger(v[6],rules[i].rhsFeature)||!LabInteger(v[7],rules[i].rhsPeriod))return false;
      // Accept only the canonical serializer's finite number representation.
      rules[i].threshold=StringToDouble(v[2]);rules[i].negate=neg==1;
      if(v[2]!=StringFormat("%.17g",rules[i].threshold)||!LabValidRule(rules[i]))return false;
   }return true;
}
bool LabEngineRead(string text,LabEngine &e)
{
   string v[];LabEngine candidate;int edge=0;
   int n=StringSplit(text,'~',v);candidate.policy=false;candidate.atrPeriod=14;candidate.slAtr=candidate.tpAtr=1;candidate.cooldown=candidate.maxBars=candidate.maxMinutes=0;
   if(!((n==5&&v[0]=="LAB2")||(n==8&&v[0]=="LAB3"))||!LabUnhex(v[1],candidate.name)||!LabInteger(v[2],edge)||(edge!=0&&edge!=1)
      ||!LabRulesRead(v[3],candidate.buy)||!LabRulesRead(v[4],candidate.sell))return false;
   if(n==8){string p[];int on=0;if(!LabRulesRead(v[5],candidate.exitBuy)||!LabRulesRead(v[6],candidate.exitSell)
      ||StringSplit(v[7],',',p)!=7||!LabInteger(p[0],on)||(on!=0&&on!=1)||!LabInteger(p[1],candidate.atrPeriod)
      ||!LabInteger(p[4],candidate.cooldown)||!LabInteger(p[5],candidate.maxBars)||!LabInteger(p[6],candidate.maxMinutes))return false;
      candidate.policy=on==1;candidate.slAtr=StringToDouble(p[2]);candidate.tpAtr=StringToDouble(p[3]);
      if(p[2]!=StringFormat("%.17g",candidate.slAtr)||p[3]!=StringFormat("%.17g",candidate.tpAtr))return false;}
   candidate.edge=edge==1;if(!LabValidEngine(candidate))return false;e=candidate;return true;
}
string LabEngineIdentity(){return LabEngineText(g_labEngine);}
int LabJoin(int a,int b,int gate)
{
   if(gate==0){if(a==0||b==0)return 0;return a<0||b<0?-1:1;}
   if(gate==1){if(a==1||b==1)return 1;return a<0||b<0?-1:0;}
   return a<0||b<0?-1:(a!=b?1:0);
}
int LabAtomValues(const LabRule &r,double a,double p,double b,double pb)
{
   if(a==EMPTY_VALUE||b==EMPTY_VALUE||!MathIsValidNumber(a)||!MathIsValidNumber(b)||(r.compare>=6&&(p==EMPTY_VALUE||pb==EMPTY_VALUE||!MathIsValidNumber(p)||!MathIsValidNumber(pb))))return -1;
   bool match=false;
   switch(r.compare){case 0:match=a>b;break;case 1:match=a<b;break;case 2:match=a>=b;break;case 3:match=a<=b;break;case 4:match=a==b;break;case 5:match=a!=b;break;case 6:match=a>b&&p<=pb;break;case 7:match=a<b&&p>=pb;break;}
   return (r.negate?!match:match)?1:0;
}
int LabAtom(const LabRule &r,const double &now[],const double &previous[])
{return LabAtomValues(r,now[r.feature],previous[r.feature],r.rhsFeature<0?r.threshold:now[r.rhsFeature],r.rhsFeature<0?r.threshold:previous[r.rhsFeature]);}
int LabEvaluate(const LabRule &rules[],const double &now[],const double &previous[])
{
   if(ArraySize(rules)==0)return 0;int result=LabAtom(rules[0],now,previous);
   // Explicit left fold: ((A gate B) gate C). NOT applies to its own atom.
   for(int i=1;i<ArraySize(rules);i++)result=LabJoin(result,LabAtom(rules[i],now,previous),rules[i].gate);
   return result;
}
class LabAverage
{
   int n,count;double sum,value;
public:
   void Reset(int length){n=length;count=0;sum=value=0;}
   bool Push(double x,double &out){count++;if(count<=n){sum+=x;if(count==n)value=sum/n;}else value+=(x-value)/n;out=count>=n?value:EMPTY_VALUE;return count>=n;}
};
#include "LabParameterizedFeatures.mqh"
class LabRuleStream
{
   LabEngine engine;LabAverage gain,loss,tr,plus,minus,adx;McRollingHma hma;
   MqlRates ring[21];double values[LAB_FEATURES],previous[LAB_FEATURES],emas[4];int count;bool oldBuy,oldSell;
   double bullLo,bullHi,bearLo,bearHi;bool bull,bear;
   LabOperandStream operands[],policyAtr;int buyLeft[],buyRight[],sellLeft[],sellRight[],exitBuyLeft[],exitBuyRight[],exitSellLeft[],exitSellRight[];
   int exitMask;
   int Bind(int feature,int period)
   {
      if(feature<LAB_FIXED_FEATURES)return -feature-2;
      for(int i=0;i<ArraySize(operands);i++)if(operands[i].Kind()==feature&&operands[i].Period()==period)return i;
      int n=ArraySize(operands);ArrayResize(operands,n+1);operands[n].Reset(feature,period);return n;
   }
   void BindRules(const LabRule &rules[],int &left[],int &right[])
   {ArrayResize(left,ArraySize(rules));ArrayResize(right,ArraySize(rules));for(int i=0;i<ArraySize(rules);i++){left[i]=Bind(rules[i].feature,rules[i].period);right[i]=rules[i].rhsFeature<0?-1:Bind(rules[i].rhsFeature,rules[i].rhsPeriod);}}
   double Operand(int slot,bool prior){return slot>=0?(prior?operands[slot].Previous():operands[slot].Current()):(prior?previous[-slot-2]:values[-slot-2]);}
   int EvaluateBound(const LabRule &rules[],const int &left[],const int &right[])
   {
      int result=0;for(int i=0;i<ArraySize(rules);i++){double b=right[i]==-1?rules[i].threshold:Operand(right[i],false),pb=right[i]==-1?rules[i].threshold:Operand(right[i],true);
         int atom=LabAtomValues(rules[i],Operand(left[i],false),Operand(left[i],true),b,pb);result=i==0?atom:LabJoin(result,atom,rules[i].gate);}return result;
   }
public:
   void Reset(const LabEngine &e){engine=e;count=0;oldBuy=oldSell=bull=bear=false;bullLo=bullHi=bearLo=bearHi=0;
      ArrayInitialize(values,EMPTY_VALUE);ArrayInitialize(previous,EMPTY_VALUE);ArrayInitialize(emas,0);gain.Reset(14);loss.Reset(14);tr.Reset(14);plus.Reset(14);minus.Reset(14);adx.Reset(14);hma.Reset(200);
      ArrayResize(operands,0);BindRules(engine.buy,buyLeft,buyRight);BindRules(engine.sell,sellLeft,sellRight);
      BindRules(engine.exitBuy,exitBuyLeft,exitBuyRight);BindRules(engine.exitSell,exitSellLeft,exitSellRight);
      policyAtr.Reset(35,e.policy?e.atrPeriod:14);exitMask=0;}
   double Value(int i){return i>=0&&i<LAB_FEATURES?values[i]:EMPTY_VALUE;}
   double PolicyAtr(){return policyAtr.Current();}int ExitMask(){return exitMask;}
   int Push(const MqlRates &b)
   {
      ArrayCopy(previous,values);ArrayInitialize(values,EMPTY_VALUE);MqlRates prior;ZeroMemory(prior);if(count>0)prior=ring[(count-1)%21];
      double range=b.high-b.low,delta=count>0?b.close-prior.close:0,gv,lv,tv,pv,mv,av,hv;
      double trueRange=count>0?MathMax(range,MathMax(MathAbs(b.high-prior.close),MathAbs(b.low-prior.close))):range;
      tr.Push(trueRange,tv);
      if(count>0){gain.Push(MathMax(delta,0),gv);loss.Push(MathMax(-delta,0),lv);
         if(gv!=EMPTY_VALUE&&lv!=EMPTY_VALUE)values[4]=lv==0?(gv==0?50:100):100-100/(1+gv/lv);
         double up=b.high-prior.high,down=prior.low-b.low;plus.Push(up>down&&up>0?up:0,pv);minus.Push(down>up&&down>0?down:0,mv);
         if(pv!=EMPTY_VALUE&&mv!=EMPTY_VALUE){double dx=pv+mv>0?100*MathAbs(pv-mv)/(pv+mv):0;adx.Push(dx,av);values[5]=av;}
      }
      values[0]=b.close;values[1]=b.open;values[2]=b.high;values[3]=b.low;values[6]=tv;
      int lengths[]={9,20,50,200};for(int i=0;i<4;i++){if(count==0)emas[i]=b.close;else emas[i]+=(b.close-emas[i])*2/(lengths[i]+1.0);if(count+1>=lengths[i])values[7+i]=emas[i];}
      if(hma.Push(b.close,hv))values[11]=hv;
      values[12]=(double)b.tick_volume;double sum=0;for(int i=MathMax(0,count-20);i<count;i++)sum+=(double)ring[i%21].tick_volume;
      if(count>=20&&sum>0)values[13]=(double)b.tick_volume/(sum/20);
      values[14]=range>0?MathAbs(b.close-b.open)/range:0;
      if(tv!=EMPTY_VALUE&&tv>0){values[15]=range/tv;if(values[8]!=EMPTY_VALUE)values[18]=(b.close-values[8])/tv;}
      if(previous[4]!=EMPTY_VALUE&&values[4]!=EMPTY_VALUE)values[16]=values[4]-previous[4];
      if(previous[5]!=EMPTY_VALUE&&values[5]!=EMPTY_VALUE)values[17]=values[5]-previous[5];
      if(previous[9]!=EMPTY_VALUE&&previous[10]!=EMPTY_VALUE&&values[9]!=EMPTY_VALUE&&values[10]!=EMPTY_VALUE){values[19]=values[9]>values[10]&&previous[9]<=previous[10]?1:0;values[20]=values[9]<values[10]&&previous[9]>=previous[10]?1:0;}
      // Zone tests use only a previously formed newest unfilled three-bar FVG.
      if(bull&&b.close<bullLo)bull=false;if(bear&&b.close>bearHi)bear=false;
      values[21]=bull&&b.close>=bullLo&&b.close<=bullHi?1:0;values[22]=bear&&b.close>=bearLo&&b.close<=bearHi?1:0;
      values[23]=bull&&b.low<=bullHi&&b.high>=bullLo?1:0;values[24]=bear&&b.low<=bearHi&&b.high>=bearLo?1:0;
      values[25]=bull?1:0;values[26]=bear?1:0;
      if(count>=2){MqlRates older=ring[(count-2)%21];if(b.low>older.high){bullLo=older.high;bullHi=b.low;bull=true;}if(b.high<older.low){bearLo=b.high;bearHi=older.low;bear=true;}}
      MqlDateTime dt;TimeToStruct(b.time,dt);values[27]=dt.hour;values[28]=dt.day_of_week;
      if(count>0&&prior.close!=0)values[29]=100*delta/prior.close;
      values[30]=range>0?(b.high-MathMax(b.open,b.close))/range:0;values[31]=range>0?(MathMin(b.open,b.close)-b.low)/range:0;
      ring[count%21]=b;count++;
      for(int i=0;i<ArraySize(operands);i++)operands[i].Push(b);
      policyAtr.Push(b);exitMask=0;
      if(engine.policy){if(EvaluateBound(engine.exitBuy,exitBuyLeft,exitBuyRight)==1)exitMask|=1;
         if(EvaluateBound(engine.exitSell,exitSellLeft,exitSellRight)==1)exitMask|=2;}
      bool buy=EvaluateBound(engine.buy,buyLeft,buyRight)==1,sell=EvaluateBound(engine.sell,sellLeft,sellRight)==1;
      bool fireBuy=buy&&(!engine.edge||!oldBuy),fireSell=sell&&(!engine.edge||!oldSell);oldBuy=buy;oldSell=sell;
      // Ambiguous simultaneous conditions never choose a side arbitrarily.
      if(buy&&sell)return 0;return fireBuy?1:(fireSell?-1:0);
   }
};
#endif
