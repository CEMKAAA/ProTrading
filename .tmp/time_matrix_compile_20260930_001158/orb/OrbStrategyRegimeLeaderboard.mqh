#ifndef ORB_STRATEGY_REGIME_LEADERBOARD_MQH
#define ORB_STRATEGY_REGIME_LEADERBOARD_MQH
#include "OrbStrategyModelSlot.mqh"
struct OrbRegimeLbCell
{
   int bucket,n,w,l,flat;
   double netR,dd,minCum;
};
struct OrbRegimeLbReport {OrbRegimeLbCell cells[8];};
bool OrbRegimeLbParse(string text,string id,string config,string dataset,string mode,string model,
   datetime fromTime,datetime toTime,OrbRegimeLbReport &r)
{
   string v[];int n=StringSplit(text,'\n',v);if(n!=22||v[21]!="")return false;
   string body="";for(int i=0;i<20;i++)body+=v[i]+"\n";
   if(OrbMlSha256(body)!=v[20])return false;
   if(v[0]!="ORB_REGIME_LB1"||v[1]!="orb.regime.snapshot.v1"||v[2]!=OrbMlSha256(OrbMlFeatureNames())
      ||v[3]!=id||v[4]!=config||v[5]!=dataset||v[6]!=mode||v[7]!=model
      ||v[10]!="CLOSED_CANDIDATE_MASK_NOT_EXECUTION_REPLAY"||v[11]!="SIGNAL_FEATURE_SNAPSHOT")return false;
   long start=0,stop=0;
   if(!OrbR7Integer(v[8],1,4102444800,start)||!OrbR7Integer(v[9],start+1,4102444800,stop)
      ||start!=(long)fromTime||stop!=(long)toTime)return false;
   long sumN=0,sumW=0,sumL=0,sumF=0;double sumR=0;
   for(int i=0;i<8;i++)
   {
      string a[];if(StringSplit(v[12+i],';',a)!=8)return false;
      long bucket=0,count=0,w=0,l=0,flat=0;OrbRegimeLbCell c;
      if(!OrbR7Integer(a[0],-1,6,bucket)||bucket!=i-1||!OrbR7Integer(a[1],0,10000000,count)
         ||!OrbR7Integer(a[2],0,count,w)||!OrbR7Integer(a[3],0,count,l)||!OrbR7Integer(a[4],0,count,flat)||w+l+flat!=count
         ||!OrbMlNumber(a[5],c.netR)||!OrbMlNumber(a[6],c.dd)||c.dd<0||!OrbMlNumber(a[7],c.minCum)||c.minCum>0)return false;
      if(count==0&&(c.netR!=0||c.dd!=0||c.minCum!=0))return false;
      c.bucket=(int)bucket;c.n=(int)count;c.w=(int)w;c.l=(int)l;c.flat=(int)flat;r.cells[i]=c;
      if(i>0){sumN+=count;sumW+=w;sumL+=l;sumF+=flat;sumR+=c.netR;}
   }
   return sumN==r.cells[0].n&&sumW==r.cells[0].w&&sumL==r.cells[0].l&&sumF==r.cells[0].flat
      &&MathAbs(sumR-r.cells[0].netR)<1e-8;
}
bool OrbRegimeLbLoad(string id,string config,string dataset,string mode,string model,datetime start,datetime stop,OrbRegimeLbReport &r)
{
   if(!OrbSlotToken(id)||(mode!="VANILLA"&&mode!="LEGACY"&&mode!="R7"))return false;
   if((mode=="VANILLA"&&model!="-")||(mode!="VANILLA"&&!OrbSlotHash(model)))return false;
   string text,hash,reason;
   string name=id+"_"+mode+"_"+(mode=="VANILLA"?"vanilla":model)+".regime";
   return OrbSlotRead("OrbML\\RegimeLeaderboard\\"+name,16384,text,hash,reason)
      &&OrbRegimeLbParse(text,id,config,dataset,mode,model,start,stop,r);
}
double OrbRegimeLbScore(int w,int n,double dd)
{
   if(n<=0)return 0;double p=(double)w/n,z2=1.96*1.96;
   return 100*(p+z2/(2*n)-1.96*MathSqrt(p*(1-p)/n+z2/(4.0*n*n)))/(1+z2/n)/(1+dd);
}
#endif
