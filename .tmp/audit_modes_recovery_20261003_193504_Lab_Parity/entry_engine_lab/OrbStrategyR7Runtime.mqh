#ifndef ORB_STRATEGY_R7_RUNTIME_MQH
#define ORB_STRATEGY_R7_RUNTIME_MQH
#include "OrbStrategyModelSlot.mqh"
bool g_mlR7=false;
OrbSlotModel g_r7Slot;
OrbCampaignInfo g_r7Info;
string g_r7RuntimeConfig="";
string OrbMlGenerationKey(){return "ORB_ML_GEN."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
bool OrbR7Load()
{
   // Failure leaves the slot unavailable, never stale weights or a Legacy fallback.
   g_r7Slot.ready=false;g_r7RuntimeConfig="";OrbStrategyPreset p;OrbSlotManifest m;
   if(ORB_CAMPAIGN_COMPATIBLE!=1||!OrbStrategyPresetLoad(g_strategyPresetIndex,p))
   {g_mlStatus="R7 SLOT STRATEGY UNAVAILABLE";return false;}
   if(!OrbSlotActive(p.id,m,g_mlStatus))return false;
   g_r7Info.id=m.id;g_r7Info.config=m.config;g_r7Info.dataset=m.dataset;g_r7Info.model_sha=m.artifact;
   g_r7Info.kind=m.provider;g_r7Info.runtime_hash=m.runtimeHash;g_r7Info.custom_hash=m.customHash;
   g_r7Info.symbol=m.symbol;g_r7Info.broker=m.broker;g_r7Info.inputs=m.inputs;g_r7Info.tf=m.tf;g_r7Info.csv="";
   if(!OrbCampaignBinding(g_r7Info)){g_mlStatus="R7 SLOT SYMBOL/TF/SETTINGS MISMATCH";return false;}
   string text,hash;
   if(!OrbSlotRead("OrbML\\Slots\\Artifacts\\"+m.artifact+".model",1000000,text,hash,g_mlStatus))return false;
   if(hash!=m.artifact){g_mlStatus="R7 SLOT FILE CHECKSUM";return false;}
   OrbSlotModel candidate;ZeroMemory(candidate);
   if(!OrbSlotModelParse(m,text,candidate,g_mlStatus))return false;
   g_r7Slot=candidate;g_r7RuntimeConfig=OrbMlConfiguration();return true;
}
string OrbR7Identity(){return g_r7Slot.ready?g_r7Slot.manifest.provider+"@"+g_r7Slot.manifest.revision:"SLOT NOT LOADED";}
#endif
