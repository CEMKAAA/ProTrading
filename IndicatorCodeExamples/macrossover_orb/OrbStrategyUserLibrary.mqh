#ifndef ORB_STRATEGY_USER_LIBRARY_MQH
#define ORB_STRATEGY_USER_LIBRARY_MQH
#include "OrbStrategyUserContract.mqh"
#define ORB_CUSTOM_MAX 1024
struct OrbUserRecord
{
   bool valid;
   OrbStrategyPreset preset;
   string symbol,inputSignature,runtime;
   int chartTf; bool independent; int maxSeries;
   bool reverseExit; int reverseWait;
   bool advancedReverse;
   double advancedReverseMaxCostPct;
   McOfConfig orderFlow;
   string timeMatrix;
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

string OrbUserFile(int slot){return "MaCrossOrbStrategyLibrary\\"+(string)slot+".preset";}

void OrbUserReload(bool force=false)
{
   if(g_userLoaded&&!force)return;
   g_userLoaded=true;g_userCount=0;ArrayResize(g_userStrategies,ORB_CUSTOM_MAX);
   for(int i=0;i<ORB_CUSTOM_MAX;i++)g_userStrategies[i].valid=false;
   string name="";long find=FileFindFirst("MaCrossOrbStrategyLibrary\\*.preset",name,FILE_COMMON);
   if(find==INVALID_HANDLE)return;
   do
   {
      string v[];int count=6+ORB_CUSTOM_PRESET_TOKENS+ORB_CUSTOM_RUNTIME_TOKENS+1;
      bool extended=OrbMlReadLines("MaCrossOrbStrategyLibrary\\"+name,v,count+1,true);
      if(!extended&&!OrbMlReadLines("MaCrossOrbStrategyLibrary\\"+name,v,count,true))continue;
      double n=0,tf=0;
      if(v[0]!="MACROSS_ORB_USER_STRATEGY1"||v[1]!=ORB_CUSTOM_SCHEMA||!OrbMlNumber(v[2],n)||n!=MathFloor(n)
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
      record.independent=false;record.maxSeries=1;record.reverseExit=false;record.reverseWait=0;
      record.advancedReverse=false;
      record.advancedReverseMaxCostPct=100.0;
      string meta[];int parts=StringSplit(v[5],'|',meta);
      if(parts<1||parts>7)continue;
      record.timeMatrix=TCalStrategyOffText();
      McOfConfigRead("0,24,32,0.70000000,1.00000000,0.10000000",record.orderFlow);
      if(parts==4)
      {
         if(StringFind(meta[3],"MAOF1=")!=0||!McOfConfigRead(StringSubstr(meta[3],6),record.orderFlow))continue;
      }
      if(parts>=5)
      {
         bool enabled=false;int hours[];
         if(StringFind(meta[3],"MAOF1=")!=0||!McOfConfigRead(StringSubstr(meta[3],6),record.orderFlow)
            ||!TCalStrategyRead(meta[4],enabled,hours))continue;
         record.timeMatrix=meta[4];
      }
      if(parts>=2)
      {
         string mode[];
         if(StringFind(meta[1],"MAENTRY1=")!=0||StringSplit(StringSubstr(meta[1],9),',',mode)!=2)continue;
         int independent=(int)StringToInteger(mode[0]),maximum=(int)StringToInteger(mode[1]);
         if(mode[0]!=(string)independent||mode[1]!=(string)maximum||independent<0||independent>1||maximum<1||maximum>1000)continue;
         record.independent=independent==1;record.maxSeries=maximum;
      }
      // Records predating explicit exit metadata used automatic filtered reverse
      // in LEGACY and no reverse in INDEPENDENT. Do not infer mode from the name.
      record.reverseExit=!record.independent;
      if(parts>=3)
      {
         string exit[];
         if(StringFind(meta[2],"MAEXIT2=")!=0||StringSplit(StringSubstr(meta[2],8),',',exit)!=2)continue;
         int enabled=(int)StringToInteger(exit[0]),wait=(int)StringToInteger(exit[1]);
         if(exit[0]!=(string)enabled||exit[1]!=(string)wait||enabled<0||enabled>1||wait<0||wait>5999)continue;
         record.reverseExit=enabled==1;record.reverseWait=wait;
      }
      if(parts>=6)
      {
         if(meta[5]!="MAADV1=0"&&meta[5]!="MAADV1=1")continue;
         record.advancedReverse=(meta[5]=="MAADV1=1");
      }
      if(parts==7)
      {
         double pct=0.0;
         if(StringFind(meta[6],"MAADVCOST1=")!=0||!OrbMlNumber(StringSubstr(meta[6],11),pct)
            ||pct<0.0||pct>100.0)continue;
         record.advancedReverseMaxCostPct=pct;
      }
      record.inputSignature=meta[0];record.runtime="";
      for(int i=0;i<ORB_CUSTOM_RUNTIME_TOKENS;i++)record.runtime+=v[6+ORB_CUSTOM_PRESET_TOKENS+i]+"\n";
      if(extended)record.runtime+=v[6+ORB_CUSTOM_PRESET_TOKENS+ORB_CUSTOM_RUNTIME_TOKENS]+"\n";
      g_userStrategies[slot]=record;
      OrbUserLoadMetrics(slot);
   }while(FileFindNext(find,name));
   FileFindClose(find);
}

int OrbStrategyPresetCount(){OrbUserReload();return g_userCount;}
bool OrbStrategyPresetLoad(const int index,OrbStrategyPreset &p)
{
   OrbUserReload();int slot=index;
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
   if(g_userStrategies[i].inputSignature!=OrbCustomInputSignature())return false;
   string v[];StringSplit(g_userStrategies[i].runtime,'\n',v);
   reason="CUSTOM_RUNTIME_INVALID";if(!OrbCustomRuntimeRead(v,0,false))return false;
   reason="";return true;
}
bool OrbUserApply(const OrbStrategyPreset &p)
{
   string reason="";if(!OrbUserValidate(p,reason))return false;
   int i=OrbUserSlot(p.id);string v[];StringSplit(g_userStrategies[i].runtime,'\n',v);
   if(g_userStrategies[i].advancedReverse&&!p.invertMode)return false;
   string previousTimeMatrix=TCalStrategyText();
   if(!TCalStrategyApplyText(g_userStrategies[i].timeMatrix))return false;
   string oldTokens[];StringSplit(OrbCustomRuntimeDump(),'\n',oldTokens);
   OrbCustomRuntimeRead(v,0,true);
   if(g_maRestoringPreset){g_maIndependent=g_userStrategies[i].independent;g_maMaxConsecutive=g_userStrategies[i].maxSeries;g_maPresetModeRestored=true;}
   else if(!MaIndependentApply(g_userStrategies[i].independent,g_userStrategies[i].maxSeries))
   {OrbCustomRuntimeRead(oldTokens,0,true);TCalStrategyApplyText(previousTimeMatrix);return false;}
   g_maReverseExit=g_userStrategies[i].reverseExit;g_maReverseWait=g_userStrategies[i].reverseWait;MaExitSave();
   g_rtAdvancedReverse=g_userStrategies[i].advancedReverse;
   g_rtAdvancedReverseMaxCostPct=g_userStrategies[i].advancedReverseMaxCostPct;
   g_mcOf=g_userStrategies[i].orderFlow;McOfReset();
   MaCrossAuditInvalidate();
   g_lastSignalBarTime=0;
   g_lastCheckedSignalBarTime=0;
   SetRuntimeMaCrossMode(g_rtMaCrossMode);
   for(int r=0;r<ORB_REGIME_COUNT;r++)g_regimeAllowed[r]=OrbPresetRegimeAllowed(p,r);
   g_orbRfEnabled=p.rfMaster;
   for(int r=0;r<ORB_RF_COUNT;r++)g_orbRfBlocked[r]=OrbPresetRfBlocked(p,r);
   if(GlobalVariableSet(RuntimeAdvancedReverseKey(),g_rtAdvancedReverse?1.0:0.0)<=0)return false;
   if(GlobalVariableSet(RuntimeAdvancedReverseMaxCostKey(),g_rtAdvancedReverseMaxCostPct)<=0)return false;
   return true;
}
bool OrbUserMatches(const OrbStrategyPreset &p)
{
   string reason="";if(!OrbUserValidate(p,reason))return false;
   int i=OrbUserSlot(p.id);
   if(g_maIndependent!=g_userStrategies[i].independent||g_maMaxConsecutive!=g_userStrategies[i].maxSeries)return false;
   if(g_maReverseExit!=g_userStrategies[i].reverseExit||g_maReverseWait!=g_userStrategies[i].reverseWait)return false;
   if(g_rtAdvancedReverse!=g_userStrategies[i].advancedReverse)return false;
   if(MathAbs(g_rtAdvancedReverseMaxCostPct-g_userStrategies[i].advancedReverseMaxCostPct)>0.000001)return false;
   if(McOfConfigText(g_mcOf)!=McOfConfigText(g_userStrategies[i].orderFlow))return false;
   if(OrbCustomRuntimeDump()!=g_userStrategies[i].runtime||g_orbRfEnabled!=p.rfMaster)return false;
   if(!TCalStrategyMatchesText(g_userStrategies[i].timeMatrix))return false;
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
   string advancedReason="";
   if(g_rtAdvancedReverse&&(!g_rtInvertMode||!AdvancedReverseShape(advancedReason)))
   {g_userStrategyNote="ADV REV settings invalid: "+advancedReason;return false;}
   StringTrimLeft(name);StringTrimRight(name);
   if(StringLen(name)<1||StringLen(name)>64){g_userStrategyNote="Name must contain 1-64 characters";return false;}
   for(int i=0;i<StringLen(name);i++)if(StringGetCharacter(name,i)<32)
      {g_userStrategyNote="Name cannot contain control characters";return false;}
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
   string signature=OrbCustomInputSignature()+"|MAENTRY1="+(g_maIndependent?"1":"0")+","+(string)g_maMaxConsecutive
      +"|MAEXIT2="+(g_maReverseExit?"1":"0")+","+(string)g_maReverseWait
      +"|MAOF1="+McOfConfigText(g_mcOf)+"|"+TCalStrategyText()
      +"|MAADV1="+(g_rtAdvancedReverse?"1":"0")
      +"|MAADVCOST1="+DoubleToString(g_rtAdvancedReverseMaxCostPct,6),runtime=OrbCustomRuntimeDump();
   string tokens[];StringSplit(runtime,'\n',tokens);
   if(!OrbCustomRuntimeRead(tokens,0,false)){g_userStrategyNote="Runtime validation failed";return false;}
   if(updateSlot>=0)p.id=updateId;
   int saved=-1;
   for(int slot=0;slot<ORB_CUSTOM_MAX;slot++)
   {
      if(updateSlot>=0&&slot!=updateSlot)continue;
      string path=OrbUserFile(slot);if(updateSlot<0&&FileIsExist(path,FILE_COMMON))continue;
      string payload="MACROSS_ORB_USER_STRATEGY1\n"+string(ORB_CUSTOM_SCHEMA)+"\n"+(string)slot+"\n"+_Symbol+"\n"+(string)(int)_Period+"\n"+signature+"\n"
         +OrbCustomPresetDump(p)+runtime;
      string temp="MaCrossOrbStrategyLibrary\\"+p.id+".tmp";
      int f=FileOpen(temp,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(f==INVALID_HANDLE){g_userStrategyNote="Cannot open strategy file";return false;}
      bool ok=OrbMlWriteUtf8(f,payload+OrbMlSha256(payload)+"\n");FileFlush(f);FileClose(f);
      if(!ok){g_userStrategyNote="Strategy write failed";return false;}
      // Save lock serializes updates; replacement is committed only after complete temporary write.
      if(FileMove(temp,FILE_COMMON,path,FILE_COMMON|(updateSlot>=0?FILE_REWRITE:0))){saved=slot;break;}
   }
   if(saved<0){g_userStrategyNote="Library full or save collision; retry";return false;}
   OrbUserReload(true);int index=saved;OrbStrategyPreset check;
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
   int lock=FileOpen("MaCrossOrbStrategyLibrary\\save.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE){g_userStrategyNote="Another chart is saving, or library is unavailable; retry";return false;}
   bool saved=OrbUserSaveLocked(name);FileClose(lock);return saved;
}

void OrbUserDraw()
{
   int x=InpDashboardX+644,y=InpDashboardY+600;
   CreateLabel("DASH_USER_TITLE",x,y,"SAVE CURRENT STRATEGY (APPLY parameter edits first)",C'255,187,92',8);
   CreateEdit("EDIT_USER_NAME",x,y+19,380,22,"");
   CreateButton("BTN_USER_SAVE",x+390,y+19,202,22,"SAVE STRATEGY",C'38,101,176');
   CreateLabel("DASH_USER_NOTE",x,y+48,StringSubstr(g_userStrategyNote,0,105),C'184,196,210',7);
}
#endif
