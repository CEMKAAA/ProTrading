// Generated from ORB versioned model-slot implementation.
#ifndef NAS_STRATEGY_R7_CORE_MQH
#define NAS_STRATEGY_R7_CORE_MQH
#include "NasStrategyMLCore.mqh"
struct NasR7Linear
{
   datetime label;
   double gain,loss,constant,bias;
   double mean[50],scale[50],coef[50];
};
struct NasR7State {int model;datetime update,stop,label;double offset;};
struct NasR7Pack
{
   bool ready;
   int models,states;
   NasR7Linear model[8];
   NasR7State state[128];
};
bool NasR7Integer(string text,long lo,long hi,long &value)
{
   double n=0;if(!NasMlNumber(text,n)||n!=MathFloor(n)||n<lo||n>hi)return false;
   value=(long)n;return true;
}
bool NasR7Parse(string text,string id,string config,string dataset,NasR7Pack &p,string &reason)
{
   p.ready=false;reason="R7 FORMAT";string v[];int n=StringSplit(text,'\n',v);
   if(n<9||v[n-1]!="")return false;
   string body="";for(int i=0;i<n-2;i++)body+=v[i]+"\n";
   if(NasMlSha256(body)!=v[n-2]){reason="R7 CHECKSUM";return false;}
   if(v[0]!="ORB_R7_LOGISTIC1"||v[1]!=NasMlSha256(NasMlFeatureNames())||v[2]!=id||v[3]!=config||v[4]!=dataset)
   {reason="R7 IDENTITY";return false;}
   long mc=0,sc=0;
   if(!NasR7Integer(v[5],1,8,mc)||!NasR7Integer(v[6],1,128,sc)||n!=9+155*mc+5*sc)return false;
   p.models=(int)mc;p.states=(int)sc;int pos=7;
   for(int j=0;j<p.models;j++)
   {
      long label=0;NasR7Linear m;
      if(!NasR7Integer(v[pos++],1,4102444800,label)||!NasMlNumber(v[pos++],m.gain)||m.gain<0
         ||!NasMlNumber(v[pos++],m.loss)||m.loss<0||!NasMlNumber(v[pos++],m.constant)
         ||(m.constant!=-1&&(m.constant<0||m.constant>1))||!NasMlNumber(v[pos++],m.bias))return false;
      m.label=(datetime)label;
      for(int i=0;i<50;i++)
         if(!NasMlNumber(v[pos++],m.mean[i])||!NasMlNumber(v[pos++],m.scale[i])||m.scale[i]<=1e-12
            ||!NasMlNumber(v[pos++],m.coef[i]))return false;
      p.model[j]=m;
   }
   for(int j=0;j<p.states;j++)
   {
      long model=0,update=0,stop=0,label=0;NasR7State s;
      if(!NasR7Integer(v[pos++],0,p.models-1,model)||!NasR7Integer(v[pos++],1,4102444800,update)
         ||!NasR7Integer(v[pos++],update+1,4102444800,stop)||!NasR7Integer(v[pos++],0,update-86401,label)
         ||!NasMlNumber(v[pos++],s.offset)||MathAbs(s.offset)>3.000000001)return false;
      if(p.model[(int)model].label+86400>=update||(j>0&&p.state[j-1].stop>update))return false;
      s.model=(int)model;s.update=(datetime)update;s.stop=(datetime)stop;s.label=(datetime)label;p.state[j]=s;
   }
   p.ready=true;reason="R7 LOGISTIC/P READY";return true;
}
double NasR7Sigmoid(double z)
{return z>=0?1.0/(1.0+MathExp(-z)):MathExp(z)/(1.0+MathExp(z));}
bool NasR7Score(const NasR7Pack &p,const double &features[],datetime when,double &score,string &reason)
{
   score=0;reason="R7 MODEL NOT READY";if(!p.ready)return false;
   int low=0,high=p.states-1,index=-1;
   while(low<=high){int mid=(low+high)/2;if(p.state[mid].update<=when){index=mid;low=mid+1;}else high=mid-1;}
   reason="R7 NO HISTORICAL COVERAGE";if(index<0)return false;
   reason="R7 STATE EXPIRED / REFRESH REQUIRED";if(when>=p.state[index].stop)return false;
   if(ArraySize(features)!=40){reason="R7 FEATURES";return false;}
   double x[50];for(int i=0;i<40;i++){if(!MathIsValidNumber(features[i]))return false;x[i]=features[i];}
   int aligned[]={5,6,7,9,10,11,38,1};for(int i=0;i<8;i++)x[40+i]=x[0]*x[aligned[i]];
   x[48]=x[28]*x[29];x[49]=x[32]*x[28];
   NasR7Linear m=p.model[p.state[index].model];double z=m.bias;
   for(int i=0;i<50;i++)z+=(x[i]-m.mean[i])/m.scale[i]*m.coef[i];
   if(!MathIsValidNumber(z)){reason="R7 NONFINITE";return false;}
   double probability=m.constant>=0?m.constant:NasR7Sigmoid(z),offset=p.state[index].offset;
   // Match scipy's clipped logit exactly; an offset of zero preserves raw p.
   if(offset!=0){probability=MathMax(1e-9,MathMin(1.0-1e-9,probability));probability=NasR7Sigmoid(MathLog(probability/(1-probability))+offset);}
   score=probability*m.gain-(1-probability)*m.loss;
   if(!MathIsValidNumber(score)){reason="R7 NONFINITE";return false;}
   reason=score>=0?"ALLOW":"SCORE_REJECT";return true;
}
#endif
