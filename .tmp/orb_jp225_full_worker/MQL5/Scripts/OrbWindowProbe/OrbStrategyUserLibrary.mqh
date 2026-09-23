#ifndef ORB_STRATEGY_USER_LIBRARY_MQH
#define ORB_STRATEGY_USER_LIBRARY_MQH
#include "OrbStrategyUserContract.mqh"
#define ORB_CUSTOM_MAX 1024
struct OrbUserRecord
{
   bool valid;
   OrbStrategyPreset preset;
   string symbol,inputSignature,runtime;
   int chartTf;
   double brokerOffset;
   int clockProfile,brokerSeason,exchangeSeason,clockSession;
};
OrbUserRecord g_userStrategies[];
bool g_userLoaded=false;
int g_userCount=0;
string g_userStrategyNote="Save applied strategy settings; risk/channel/PUB/NAT stay separate";

int OrbUserSymbolFamily(string symbol)
{
   StringToUpper(symbol);
   if(StringFind(symbol,"USDJPY")>=0)return ORB_PRESET_FAMILY_USDJPY;
   if(StringFind(symbol,"JP225")>=0||StringFind(symbol,"JPN225")>=0||StringFind(symbol,"NIKKEI")>=0)return ORB_PRESET_FAMILY_JP225;
   if(StringFind(symbol,"USTEC")>=0||StringFind(symbol,"US100")>=0||StringFind(symbol,"NAS100")>=0)return ORB_PRESET_FAMILY_USTEC;
   return ORB_PRESET_FAMILY_ANY;
}

string OrbUserFile(int slot){return "OrbStrategyUserLibrary\\"+(string)slot+".preset";}

void OrbUserReload(bool force=false)
{
   if(g_userLoaded&&!force)return;
   g_userLoaded=true;g_userCount=0;ArrayResize(g_userStrategies,ORB_CUSTOM_MAX);
   for(int i=0;i<ORB_CUSTOM_MAX;i++)g_userStrategies[i].valid=false;
   string name="";long find=FileFindFirst("OrbStrategyUserLibrary\\*.preset",name,FILE_COMMON);
   if(find==INVALID_HANDLE)return;
   do
   {
      string v[];int count=6+ORB_CUSTOM_PRESET_TOKENS+ORB_CUSTOM_RUNTIME_TOKENS+1;
      bool extended=OrbMlReadLines("OrbStrategyUserLibrary\\"+name,v,count+1,true);
      if(!extended&&!OrbMlReadLines("OrbStrategyUserLibrary\\"+name,v,count,true))continue;
      double n=0,tf=0;
      if(v[0]!="ORB_USER_STRATEGY1"||v[1]!=ORB_CUSTOM_SCHEMA||!OrbMlNumber(v[2],n)||n!=MathFloor(n)
         ||n<0||n>=ORB_CUSTOM_MAX||!OrbMlNumber(v[4],tf)||tf!=MathFloor(tf))continue;
      int slot=(int)n;if(name!=(string)slot+".preset")continue;
      // Reserve existing slots even if a record cannot be decoded; never overwrite them.
      g_userCount=MathMax(g_userCount,slot+1);
      OrbStrategyPreset p;OrbPresetDefaults(p);
      if(!OrbCustomPresetRead(v,6,p)||StringFind(p.id,"user_")!=0||!OrbMlSafeId(p.id))continue;
      if((p.targetLeg==(int)ORB_TARGET_CUSTOM)!=extended)continue;
      if(!OrbCustomRuntimeRead(v,6+ORB_CUSTOM_PRESET_TOKENS,false))continue;
      OrbUserRecord record;record.valid=true;record.preset=p;record.symbol=v[3];record.chartTf=(int)tf;
      if(record.preset.family==ORB_PRESET_FAMILY_ANY)record.preset.family=OrbUserSymbolFamily(record.symbol);
      string clockMeta[];int metaCount=StringSplit(v[5],'|',clockMeta);
      record.inputSignature=clockMeta[0];record.brokerOffset=0;
      record.clockProfile=0;record.brokerSeason=0;record.exchangeSeason=0;record.clockSession=0;
      if(metaCount>1)
      {
         double offset=0;
         if((metaCount!=2&&metaCount!=3)||StringFind(clockMeta[1],"TZ=")!=0||!OrbMlNumber(StringSubstr(clockMeta[1],3),offset)
            ||offset < -12||offset > 14)continue;
         record.brokerOffset=offset;
         if(metaCount==3&&(StringFind(clockMeta[2],"CLK1=")!=0
            ||!OrbClockReadMeta(StringSubstr(clockMeta[2],5),record.clockProfile,record.brokerSeason,record.exchangeSeason,record.clockSession)))continue;
      }
      record.runtime="";
      for(int i=0;i<ORB_CUSTOM_RUNTIME_TOKENS;i++)record.runtime+=v[6+ORB_CUSTOM_PRESET_TOKENS+i]+"\n";
      if(extended)record.runtime+=v[6+ORB_CUSTOM_PRESET_TOKENS+ORB_CUSTOM_RUNTIME_TOKENS]+"\n";
      g_userStrategies[slot]=record;
      OrbUserLoadMetrics(slot);
   }while(FileFindNext(find,name));
   FileFindClose(find);
}

int OrbStrategyPresetCount(){OrbUserReload();return OrbBuiltinStrategyPresetCount()+g_userCount;}
bool OrbStrategyPresetLoad(const int index,OrbStrategyPreset &p)
{
   if(index<OrbBuiltinStrategyPresetCount())return OrbBuiltinStrategyPresetLoad(index,p);
   OrbUserReload();int slot=index-OrbBuiltinStrategyPresetCount();
   if(slot<0||slot>=g_userCount||!g_userStrategies[slot].valid)return false;
   p=g_userStrategies[slot].preset;return true;
}

int OrbUserSlot(const string id)
{
   OrbUserReload();for(int i=0;i<g_userCount;i++)if(g_userStrategies[i].valid&&g_userStrategies[i].preset.id==id)return i;
   return -1;
}
bool OrbUserPreset(const OrbStrategyPreset &p){return StringFind(p.id,"user_")==0;}
double OrbUserCustomR(const OrbStrategyPreset &p)
{
   int slot=OrbUserSlot(p.id);
   if(slot<0||p.targetLeg!=(int)ORB_TARGET_CUSTOM)return 0.0;
   string values[];StringSplit(g_userStrategies[slot].runtime,'\n',values);
   double value=0.0;
   if(ArraySize(values)<=ORB_CUSTOM_RUNTIME_TOKENS
      ||!OrbMlNumber(values[ORB_CUSTOM_RUNTIME_TOKENS],value))return 0.0;
   return value;
}
bool OrbUserValidate(const OrbStrategyPreset &p,string &reason)
{
   int i=OrbUserSlot(p.id);reason="CUSTOM_RECORD_MISSING";if(i<0)return false;
   reason="CUSTOM_SYMBOL_OR_CHART_TF_MISMATCH";
   if(g_userStrategies[i].symbol!=_Symbol||g_userStrategies[i].chartTf!=(int)_Period)return false;
   reason="CUSTOM_EA_INPUTS_MISMATCH";
   double savedClock=g_orbStrategyTimezone;g_orbStrategyTimezone=0;
   string expectedSignature=OrbCustomInputSignature();g_orbStrategyTimezone=savedClock;
   if(g_userStrategies[i].inputSignature!=expectedSignature)return false;
   string v[];StringSplit(g_userStrategies[i].runtime,'\n',v);
   reason="CUSTOM_RUNTIME_INVALID";if(!OrbCustomRuntimeRead(v,0,false))return false;
   reason="";return true;
}
void OrbUserApply(const OrbStrategyPreset &p)
{
   string reason="";if(!OrbUserValidate(p,reason))return;
   int i=OrbUserSlot(p.id);string v[];StringSplit(g_userStrategies[i].runtime,'\n',v);
   g_orbStrategyTimezone=g_userStrategies[i].brokerOffset;
   OrbClockUseSaved(g_userStrategies[i].clockProfile,g_userStrategies[i].brokerSeason,g_userStrategies[i].exchangeSeason,g_userStrategies[i].clockSession);
   OrbCustomRuntimeRead(v,0,true);
   for(int r=0;r<ORB_REGIME_COUNT;r++)g_regimeAllowed[r]=OrbPresetRegimeAllowed(p,r);
   g_orbRfEnabled=p.rfMaster;
   for(int r=0;r<ORB_RF_COUNT;r++)g_orbRfBlocked[r]=OrbPresetRfBlocked(p,r);
}
bool OrbUserMatches(const OrbStrategyPreset &p)
{
   string reason="";if(!OrbUserValidate(p,reason))return false;
   int i=OrbUserSlot(p.id);
   if(MathAbs(OrbBrokerOffsetHours()-g_userStrategies[i].brokerOffset)>0.0000001)return false;
   if((int)OrbClockProfile()!=g_userStrategies[i].clockProfile||(int)OrbClockBrokerSeason()!=g_userStrategies[i].brokerSeason
      ||(int)OrbClockExchangeSeason()!=g_userStrategies[i].exchangeSeason||g_orbClockSession!=g_userStrategies[i].clockSession)return false;
   if(OrbCustomRuntimeDump()!=g_userStrategies[i].runtime||g_orbRfEnabled!=p.rfMaster)return false;
   for(int r=0;r<ORB_REGIME_COUNT;r++)if(g_regimeAllowed[r]!=OrbPresetRegimeAllowed(p,r))return false;
   for(int r=0;r<ORB_RF_COUNT;r++)if(g_orbRfBlocked[r]!=OrbPresetRfBlocked(p,r))return false;
   return true;
}

double OrbUserIdNumber(const string id)
{
   string digest=OrbMlSha256(id);double n=0;
   for(int i=0;i<12;i++){ushort c=StringGetCharacter(digest,i);n=n*16+(c<='9'?c-'0':c-'a'+10);}
   return n;
}
bool OrbUserRemember(const OrbStrategyPreset &p)
{return GlobalVariableSet(OrbStrategyPresetSelectionKey()+".id",OrbUserPreset(p)?OrbUserIdNumber(p.id):0)>0;}
bool OrbUserRemembered(const OrbStrategyPreset &p)
{
   if(!OrbUserPreset(p))return true;
   string key=OrbStrategyPresetSelectionKey()+".id";
   return GlobalVariableCheck(key)&&GlobalVariableGet(key)==OrbUserIdNumber(p.id);
}

bool OrbUserSaveLocked(string name)
{
   int updateSlot=-1;string updateId="";
   StringTrimLeft(name);StringTrimRight(name);
   if(StringLen(name)<1||StringLen(name)>64){g_userStrategyNote="Name must contain 1-64 characters";return false;}
   for(int i=0;i<StringLen(name);i++)if(StringGetCharacter(name,i)<32)
      {g_userStrategyNote="Name cannot contain control characters";return false;}
   if(OrbMlIsEnabled()){g_userStrategyNote="Turn ML FILTER OFF before creating a new strategy identity";return false;}
   if(OrbMlExportBusy()){g_userStrategyNote="Wait for CSV export or cancel it before saving";return false;}
   OrbUserReload(true);
   for(int i=0;i<OrbStrategyPresetCount();i++)
   {
      OrbStrategyPreset other;if(!OrbStrategyPresetLoad(i,other))continue;
      string a=other.name,b=name;StringToLower(a);StringToLower(b);
      if(a==b){if(!OrbUserPreset(other)){g_userStrategyNote="Built-in strategy is read-only; use a new name";return false;} updateSlot=OrbUserSlot(other.id);updateId=other.id;break;}
   }
   OrbStrategyPreset p;OrbCustomCapturePreset(p);
   p.family=OrbUserSymbolFamily(_Symbol);
   p.name=name;p.searchTerms=name+" "+_Symbol+" user saved";p.sourceImage="user-saved";
   p.id="user_"+StringSubstr(OrbMlSha256(name+(string)ChartID()+(string)TimeGMT()+(string)GetTickCount64()+OrbCustomRuntimeDump()),0,24);
   double offset=OrbBrokerOffsetHours(),savedClock=g_orbStrategyTimezone;g_orbStrategyTimezone=0;
   string signature=OrbCustomInputSignature()+"|TZ="+DoubleToString(offset,8)+"|CLK1="+OrbClockSavedMeta(),runtime=OrbCustomRuntimeDump();
   g_orbStrategyTimezone=savedClock;
   string tokens[];StringSplit(runtime,'\n',tokens);
   if(!OrbCustomRuntimeRead(tokens,0,false)){g_userStrategyNote="Runtime validation failed";return false;}
   if(updateSlot>=0)p.id=updateId;
   int saved=-1;
   for(int slot=0;slot<ORB_CUSTOM_MAX;slot++)
   {
      if(updateSlot>=0&&slot!=updateSlot)continue;
      string path=OrbUserFile(slot);if(updateSlot<0&&FileIsExist(path,FILE_COMMON))continue;
      string payload="ORB_USER_STRATEGY1\n"+string(ORB_CUSTOM_SCHEMA)+"\n"+(string)slot+"\n"+_Symbol+"\n"+(string)(int)_Period+"\n"+signature+"\n"
         +OrbCustomPresetDump(p)+runtime;
      string temp="OrbStrategyUserLibrary\\"+p.id+".tmp";
      int f=FileOpen(temp,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(f==INVALID_HANDLE){g_userStrategyNote="Cannot open strategy file";return false;}
      bool ok=OrbMlWriteUtf8(f,payload+OrbMlSha256(payload)+"\n");FileFlush(f);FileClose(f);
      if(!ok){g_userStrategyNote="Strategy write failed";return false;}
      // Save lock serializes updates; replacement is committed only after complete temporary write.
      if(FileMove(temp,FILE_COMMON,path,FILE_COMMON|(updateSlot>=0?FILE_REWRITE:0))){saved=slot;break;}
   }
   if(saved<0){g_userStrategyNote="Library full or save collision; retry";return false;}
   OrbUserReload(true);int index=OrbBuiltinStrategyPresetCount()+saved;OrbStrategyPreset check;
   if(!OrbStrategyPresetLoad(index,check)||!OrbUserMatches(check))
   {g_userStrategyNote="Saved file did not pass exact read-back; not selected";return false;}
   if(!OrbUserRemember(check)||GlobalVariableSet(OrbStrategyPresetSelectionKey(),index)<=0)
   {g_userStrategyNote="Saved, but selection could not be persisted. Select from SEARCH.";return false;}
   GlobalVariablesFlush();g_strategyPresetIndex=index;g_strategyCandidateIndex=index;
   OrbStrategyLoadFavorites();OrbStrategyPresetBuildMatches("");
   g_userStrategyNote="SAVED: "+name+" | computing 1Y metrics";
   OrbUserEnsureMetrics();
   return true;
}

bool OrbUserSave(const string name)
{
   // FILE_SHARE flags intentionally absent: also serialize saves across terminals.
   int lock=FileOpen("OrbStrategyUserLibrary\\save.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE){g_userStrategyNote="Another chart is saving, or library is unavailable; retry";return false;}
   bool saved=OrbUserSaveLocked(name);FileClose(lock);return saved;
}

void OrbUserDraw()
{
   int x=InpDashboardX+644,y=InpDashboardY+600;
   CreateLabel("DASH_USER_TITLE",x,y,"SAVE STRATEGY | GMT "+DoubleToString(OrbBrokerOffsetHours(),2),C'255,187,92',8);
   CreateButton("BTN_USER_TZ",x+390,y-3,202,18,"TIMEZONE SETTINGS",C'38,101,176');
   CreateEdit("EDIT_USER_NAME",x,y+19,380,22,"");
   CreateButton("BTN_USER_SAVE",x+390,y+19,202,22,"SAVE STRATEGY",C'38,101,176');
   CreateLabel("DASH_USER_NOTE",x,y+48,StringSubstr(g_userStrategyNote,0,105),C'184,196,210',7);
}
#endif
