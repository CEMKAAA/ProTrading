#ifndef ORB_STRATEGY_CAMPAIGN_MODELS_MQH
#define ORB_STRATEGY_CAMPAIGN_MODELS_MQH
struct OrbCampaignInfo
{
   string id,config,dataset,model_sha,kind,runtime_hash,custom_hash,symbol,broker,inputs,csv;
   int tf;
};
#include "OrbStrategyCampaignRegistry.mqh"
struct OrbReturnNode {int leaf,feature,left,right;double threshold,value;};
OrbCampaignInfo g_campaignInfo;
OrbMlNetwork g_campaignMlp;
OrbReturnNode g_campaignNodes[];
int g_campaignRoots[];
double g_campaignMean[50],g_campaignScale[50],g_campaignCoef[50];
double g_campaignBias=0,g_campaignThreshold=0;
bool g_campaignReady=false,g_campaignActive=false,g_mlUsingCampaign=false;
datetime g_campaignCutoff=0;
string g_campaignRuntimeConfig="";

string OrbCampaignNumericHash(string text,int start,int count)
{
   string values[];if(StringSplit(text,'\n',values)<start+count)return "";
   string canonical="";
   for(int i=start;i<start+count;i++)
   {
      double value=0;if(!OrbMlNumber(values[i],value))return "";
      canonical+=DoubleToString(value,12)+"\n";
   }
   return OrbMlSha256(canonical);
}
string OrbCampaignRuntimeHash(){return OrbCampaignNumericHash(OrbCustomRuntimeDump(),0,40);}

bool OrbCampaignSelected(OrbCampaignInfo &r)
{
   OrbStrategyPreset p;
   return OrbStrategyPresetLoad(g_strategyPresetIndex,p)&&OrbCampaignRecord(p.id,r);
}

bool OrbCampaignBinding(const OrbCampaignInfo &r)
{
   // Old campaign manifests do not bind a broker seasonal policy.
   if(OrbBrokerClockKey()!="")return false;
   OrbStrategyPreset p;
   if(!OrbStrategyPresetLoad(g_strategyPresetIndex,p)||p.id!=r.id||!OrbStrategyPresetMatchesRuntime(p))return false;
   if(_Symbol!=r.symbol||(int)_Period!=r.tf||AccountInfoString(ACCOUNT_SERVER)!=r.broker)return false;
   if(OrbCustomInputSignature()!=r.inputs||OrbCampaignRuntimeHash()!=r.runtime_hash)return false;
   if(r.custom_hash!=""&&OrbCampaignNumericHash(OrbCustomPresetDump(p),5,53)!=r.custom_hash)return false;
   return true;
}

bool OrbCampaignInt(string value,int minimum,int maximum,int &result)
{
   double n=0;if(!OrbMlNumber(value,n)||n!=MathFloor(n)||n<minimum||n>maximum)return false;
   result=(int)n;return true;
}

bool OrbCampaignParseReturn(const string text,const OrbCampaignInfo &info)
{
   string v[];int n=StringSplit(text,'\n',v);
   if(n<12||v[n-1]!="")return false;
   string payload="";for(int i=0;i<n-2;i++)payload+=v[i]+"\n";
   if(OrbMlSha256(payload)!=v[n-2]||v[0]!="ORB_RETURN1"||v[1]!=info.config
      ||v[2]!=OrbMlSha256(OrbMlFeatureNames())||v[3]!=info.dataset||v[7]!=info.kind)return false;
   double cutoff=0;if(!OrbMlNumber(v[4],cutoff)||cutoff<=0||cutoff!=MathFloor(cutoff))return false;
   if(!OrbMlNumber(v[5],g_campaignThreshold)||!OrbMlNumber(v[9],g_campaignBias))return false;
   if(v[6]!="0"&&v[6]!="1")return false;
   g_campaignActive=v[6]=="1";g_campaignCutoff=(datetime)cutoff;
   int trees=0;if(!OrbCampaignInt(v[8],0,256,trees))return false;
   if(info.kind=="RIDGE")
   {
      if(trees!=0||n!=162)return false;
      int pos=10;
      for(int i=0;i<50;i++)
         if(!OrbMlNumber(v[pos++],g_campaignMean[i])||!OrbMlNumber(v[pos++],g_campaignScale[i])||g_campaignScale[i]<=1e-12)return false;
      for(int i=0;i<50;i++)if(!OrbMlNumber(v[pos++],g_campaignCoef[i]))return false;
      return true;
   }
   if(info.kind!="HGB"||trees<1)return false;
   ArrayResize(g_campaignNodes,0);ArrayResize(g_campaignRoots,trees);int pos=10;
   for(int t=0;t<trees;t++)
   {
      int count=0;if(pos>=n-2||!OrbCampaignInt(v[pos++],1,63,count)||pos+count*6>n-2)return false;
      int root=ArraySize(g_campaignNodes);g_campaignRoots[t]=root;ArrayResize(g_campaignNodes,root+count);
      for(int i=0;i<count;i++)
      {
         OrbReturnNode node;
         if(!OrbCampaignInt(v[pos++],0,1,node.leaf)||!OrbCampaignInt(v[pos++],0,49,node.feature)
            ||!OrbMlNumber(v[pos++],node.threshold)||!OrbMlNumber(v[pos++],node.value)
            ||!OrbCampaignInt(v[pos++],0,count-1,node.left)||!OrbCampaignInt(v[pos++],0,count-1,node.right))return false;
         if(node.leaf==0&&(node.left<=i||node.right<=i))return false;
         node.left+=root;node.right+=root;g_campaignNodes[root+i]=node;
      }
   }
   return pos==n-2;
}

bool OrbCampaignLoad()
{
   g_mlUsingCampaign=false;g_campaignReady=false;g_campaignMlp.ready=false;
   if(ORB_CAMPAIGN_COMPATIBLE!=1){g_mlStatus="CAMPAIGN ENGINE CHANGED: REVALIDATION REQUIRED";return false;}
   if(!OrbCampaignSelected(g_campaignInfo)){g_mlStatus="NO PRETRAINED MODEL FOR THIS STRATEGY";return false;}
   if(!OrbCampaignBinding(g_campaignInfo)){g_mlStatus="PRETRAINED: SYMBOL/TF/INPUT/STRATEGY MISMATCH";return false;}
   string path="OrbML\\CampaignModels\\"+g_campaignInfo.id+".experimental";
   int h=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
   if(h==INVALID_HANDLE){g_mlStatus="PRETRAINED FILE NOT INSTALLED";return false;}
   ulong size=FileSize(h);uchar data[];
   if(size==0||size>1000000){FileClose(h);g_mlStatus="PRETRAINED SIZE INVALID";return false;}
   ArrayResize(data,(int)size);uint read=FileReadArray(h,data);FileClose(h);
   if(read!=size||OrbMlBytesSha256(data)!=g_campaignInfo.model_sha){g_mlStatus="PRETRAINED CHECKSUM FAILED";return false;}
   string text=CharArrayToString(data,0,(int)size,CP_UTF8);bool ok=false;
   if(g_campaignInfo.kind=="MLP")
   {
      ok=OrbMlParseModel(text,g_campaignInfo.config,g_campaignMlp,g_mlStatus)&&g_campaignMlp.dataset==g_campaignInfo.dataset;
      g_campaignCutoff=g_campaignMlp.lastLabelTime;g_campaignThreshold=g_campaignMlp.threshold;g_campaignActive=true;
   }
   else ok=OrbCampaignParseReturn(text,g_campaignInfo);
   if(!ok){g_mlStatus="PRETRAINED MODEL FORMAT FAILED";return false;}
   g_campaignRuntimeConfig=OrbMlConfiguration();g_mlUsingCampaign=true;g_campaignReady=true;
   g_mlStatus="PRETRAINED "+g_campaignInfo.kind+" READY [EXPERIMENTAL]";return true;
}

bool OrbCampaignPredict(const double &features[],double &score)
{
   if(!g_campaignReady||ArraySize(features)!=40)return false;
   if(g_campaignInfo.kind=="MLP")return OrbMlPredict(g_campaignMlp,features,score);
   double x[50];for(int i=0;i<40;i++){if(!MathIsValidNumber(features[i]))return false;x[i]=features[i];}
   int aligned[]={5,6,7,9,10,11,38,1};
   for(int i=0;i<8;i++)x[40+i]=x[0]*x[aligned[i]];
   x[48]=x[28]*x[29];x[49]=x[32]*x[28];
   for(int i=40;i<50;i++)if(!MathIsValidNumber(x[i]))return false;
   score=g_campaignBias;
   if(g_campaignInfo.kind=="RIDGE")
      for(int i=0;i<50;i++)score+=(x[i]-g_campaignMean[i])/g_campaignScale[i]*g_campaignCoef[i];
   else
      for(int t=0;t<ArraySize(g_campaignRoots);t++)
      {
         int pos=g_campaignRoots[t],end=t+1<ArraySize(g_campaignRoots)?g_campaignRoots[t+1]:ArraySize(g_campaignNodes);
         bool leaf=false;
         for(int step=0;step<63;step++)
         {
            if(pos<g_campaignRoots[t]||pos>=end)return false;
            OrbReturnNode node=g_campaignNodes[pos];
            if(node.leaf==1){score+=node.value;leaf=true;break;}
            pos=x[node.feature]<=node.threshold?node.left:node.right;
         }
         if(!leaf)return false;
      }
   return MathIsValidNumber(score);
}

bool OrbMlUsePretrained()
{
   if(OrbStrategyPresetHasActiveLifecycle()||g_nasPending||g_retestPending||g_imbPending||g_newDayReverseRetryPending)
   {g_mlStatus="WAIT: ACTIVE/PENDING TRADE";return false;}
   return OrbCampaignLoad();
}
#endif
