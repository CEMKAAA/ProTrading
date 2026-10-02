#ifndef ORB_STRATEGY_MODEL_SLOT_MQH
#define ORB_STRATEGY_MODEL_SLOT_MQH
#include "OrbStrategyR7Core.mqh"
// Provider-independent manifest. Paths are derived, never supplied by a package.
struct OrbSlotManifest
{
   string id,config,dataset,runtimeHash,customHash,symbol,broker,inputs;
   string provider,revision,artifact,evaluation;
   int tf,n;
   datetime fromTime,untilTime,metricFrom,metricUntil;
   double wr,netR,dd;
};
bool OrbSlotToken(string s)
{
   if(StringLen(s)<1||StringLen(s)>96)return false;
   for(int i=0;i<StringLen(s);i++)
   {
      ushort c=StringGetCharacter(s,i);
      if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'))return false;
   }
   return true;
}
bool OrbSlotHash(string s)
{
   if(StringLen(s)!=64)return false;
   for(int i=0;i<64;i++){ushort c=StringGetCharacter(s,i);if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;}
   return true;
}
bool OrbSlotParse(string text,string id,OrbSlotManifest &m,string &reason)
{
   reason="SLOT MANIFEST FORMAT";string v[];int n=StringSplit(text,'\n',v);
   if(n!=26||v[25]!="")return false;
   string body="";for(int i=0;i<24;i++)body+=v[i]+"\n";
   if(OrbMlSha256(body)!=v[24]){reason="SLOT MANIFEST CHECKSUM";return false;}
   if(v[0]!="ORB_SLOT1"||v[1]!=ORB_ML_SCHEMA||v[2]!=OrbMlSha256(OrbMlFeatureNames())||v[3]!=id||!OrbSlotToken(id))return false;
   if(!OrbSlotHash(v[4])||!OrbSlotHash(v[5])||!OrbSlotHash(v[6])||(v[7]!=""&&!OrbSlotHash(v[7]))||!OrbSlotHash(v[10])||!OrbSlotHash(v[14]))return false;
   if(!OrbSlotToken(v[13])||v[8]==""||v[9]=="")return false;
   if(v[12]!="ORB_R7_LOGISTIC1"&&v[12]!="ORB_MLP1"){reason="SLOT UNSUPPORTED PROVIDER";return false;}
   long tf=0,start=0,stop=0,mstart=0,mstop=0,trades=0;
   if(!OrbR7Integer(v[11],1,49153,tf)||!OrbR7Integer(v[15],1,4102444800,start)||!OrbR7Integer(v[16],start+1,4102444800,stop)
      ||!OrbR7Integer(v[17],0,4102444800,mstart)||!OrbR7Integer(v[18],mstart,4102444800,mstop)||!OrbR7Integer(v[19],0,10000000,trades))return false;
   if(!OrbMlNumber(v[20],m.wr)||m.wr<0||m.wr>100||!OrbMlNumber(v[21],m.netR)||!OrbMlNumber(v[22],m.dd)||m.dd<0)return false;
   if(v[23]!="NONE"&&v[23]!="RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS")return false;
   if(v[23]=="NONE"&&(mstart!=0||mstop!=0||trades!=0||m.wr!=0||m.netR!=0||m.dd!=0))return false;
   if(v[23]!="NONE"&&(mstart==0||mstop<=mstart||trades==0))return false;
   m.id=id;m.config=v[4];m.dataset=v[5];m.runtimeHash=v[6];m.customHash=v[7];m.symbol=v[8];m.broker=v[9];m.inputs=v[10];
   m.tf=(int)tf;m.provider=v[12];m.revision=v[13];m.artifact=v[14];m.fromTime=(datetime)start;m.untilTime=(datetime)stop;
   m.metricFrom=(datetime)mstart;m.metricUntil=(datetime)mstop;m.n=(int)trades;m.evaluation=v[23];reason="SLOT MANIFEST READY";return true;
}
bool OrbSlotRead(string path,int limit,string &text,string &hash,string &reason)
{
   text="";hash="";
   int h=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE){reason="SLOT FILE NOT INSTALLED/BUSY";return false;}
   ulong size=FileSize(h);uchar bytes[];
   if(size==0||size>(ulong)limit){FileClose(h);reason="SLOT FILE SIZE";return false;}
   ArrayResize(bytes,(int)size);uint got=FileReadArray(h,bytes);FileClose(h);
   if(got!=size){reason="SLOT SHORT READ";return false;}
   text=CharArrayToString(bytes,0,(int)size,CP_UTF8);hash=OrbMlBytesSha256(bytes);return true;
}
bool OrbSlotActive(string id,OrbSlotManifest &m,string &reason)
{
   if(!OrbSlotToken(id)){reason="SLOT INVALID STRATEGY ID";return false;}
   string text,hash;
   return OrbSlotRead("OrbML\\Slots\\"+id+"\\active.slot",16384,text,hash,reason)&&OrbSlotParse(text,id,m,reason);
}
struct OrbSlotModel
{
   bool ready;
   OrbSlotManifest manifest;
   OrbR7Pack logistic;
   OrbMlNetwork mlp;
};
bool OrbSlotModelParse(const OrbSlotManifest &m,string text,OrbSlotModel &p,string &reason)
{
   p.ready=false;
   if(OrbMlSha256(text)!=m.artifact){reason="SLOT ARTIFACT CHECKSUM";return false;}
   if(m.provider=="ORB_R7_LOGISTIC1")
   {
      if(!OrbR7Parse(text,m.id,m.config,m.dataset,p.logistic,reason))return false;
      if(m.fromTime<p.logistic.state[0].update||m.untilTime>p.logistic.state[p.logistic.states-1].stop)
      {reason="SLOT VALIDITY EXCEEDS ARCHIVE";return false;}
   }
   else if(m.provider=="ORB_MLP1")
   {
      if(!OrbMlParseModel(text,m.config,p.mlp,reason))return false;
      if(p.mlp.dataset!=m.dataset||p.mlp.lastLabelTime+86400>=m.fromTime)
      {reason="SLOT TRAINING/VALIDITY BINDING";return false;}
   }
   else {reason="SLOT UNSUPPORTED PROVIDER";return false;}
   p.manifest=m;p.ready=true;reason="SLOT READY";return true;
}
bool OrbSlotScore(const OrbSlotModel &p,const double &features[],datetime when,double &score,string &reason)
{
   score=0;
   if(!p.ready){reason="SLOT NOT READY";return false;}
   if(when<p.manifest.fromTime||when>=p.manifest.untilTime){reason="SLOT OUTSIDE VALIDITY / REFRESH REQUIRED";return false;}
   if(p.manifest.provider=="ORB_R7_LOGISTIC1")return OrbR7Score(p.logistic,features,when,score,reason);
   if(p.manifest.provider!="ORB_MLP1"||!OrbMlPredict(p.mlp,features,score)){reason="SLOT INFERENCE ERROR";return false;}
   reason=score>=p.mlp.threshold?"ALLOW":"SCORE_REJECT";return true;
}
#endif
