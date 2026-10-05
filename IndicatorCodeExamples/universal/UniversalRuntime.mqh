#ifndef UNIVERSAL_RUNTIME_MQH
#define UNIVERSAL_RUNTIME_MQH
input string InpInstallationId=""; // From installation pairing; no standalone execution.
string g_ucKey="",g_ucFolder="",g_ucAuditFamily="",g_ucLiveFamily="";
string g_ucJob="",g_ucAttempt="",g_ucConfig="",g_ucRequest="",g_ucError="";
string g_ucLiveHash="",g_ucLastCommand="";
bool g_ucAuditPending=false,g_ucAuditStarted=false;
datetime g_ucFromUtc=0,g_ucToUtc=0;
int g_ucWeeks=2;
ulong g_ucAuditUntil=0,g_ucNextRetry=0;
int g_ucLockHandle=INVALID_HANDLE;
string g_ucRecoveredHash="",g_ucRecoveredFamily="";

string UcRead(string path)
{
   int f=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(f==INVALID_HANDLE)return "";
   ulong size=FileSize(f);if(size>4194304){FileClose(f);return "";}
   uchar bytes[];ArrayResize(bytes,(int)size);FileReadArray(f,bytes);FileClose(f);
   return CharArrayToString(bytes,0,(int)size,CP_UTF8);
}
bool UcWrite(string path,string text)
{
   int f=FileOpen(path+".partial",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(f==INVALID_HANDLE)return false;uchar bytes[];int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   bool ok=FileWriteArray(f,bytes,0,n)==(uint)n;FileFlush(f);FileClose(f);
   return ok&&FileMove(path+".partial",FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
}
string UcHmac(string text)
{
   uchar key[],bytes[],inner[],digest[],outer[],result[],empty[];
   StringToCharArray(g_ucKey,key,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(key,ArraySize(key)-1);
   StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(bytes,ArraySize(bytes)-1);
   ArrayResize(inner,64+ArraySize(bytes));ArrayResize(outer,96);
   for(int i=0;i<64;i++){uchar k=i<ArraySize(key)?key[i]:0;inner[i]=(uchar)(k^0x36);outer[i]=(uchar)(k^0x5c);}
   ArrayCopy(inner,bytes,64);if(CryptEncode(CRYPT_HASH_SHA256,inner,empty,digest)!=32)return "";
   ArrayCopy(outer,digest,64);if(CryptEncode(CRYPT_HASH_SHA256,outer,empty,result)!=32)return "";
   string hex="";for(int i=0;i<32;i++)hex+=StringFormat("%02x",result[i]);return hex;
}
string UcField(string body,string key)
{
   string lines[];int n=StringSplit(body,'\n',lines),size=StringLen(key);
   for(int i=0;i<n;i++)if(StringSubstr(lines[i],0,size+1)==key+"=")return StringSubstr(lines[i],size+1);
   return "";
}
bool UcVerified(string packet,string &body)
{
   int at=StringFind(packet,"\nHMAC=");if(at<0)return false;body=StringSubstr(packet,0,at);
   if(StringSubstr(packet,at+6)!=UcHmac(body)||StringLen(g_ucKey)!=32)return false;
   datetime expires=(datetime)StringToInteger(UcField(body,"expires")),issued=(datetime)StringToInteger(UcField(body,"issued"));
   return issued<=TimeGMT()+5&&issued>=TimeGMT()-20&&expires>TimeGMT()&&expires-issued<=15;
}
void UcSignedWrite(string path,string body){UcWrite(path,body+"\nHMAC="+UcHmac(body));}
long UcMagic(string family)
{
   ulong h=2166136261;string seed=g_ucInstallation+family+(string)AccountInfoInteger(ACCOUNT_LOGIN);
   for(int i=0;i<StringLen(seed);i++)h=(h^(ulong)StringGetCharacter(seed,i))*16777619;
   return 4000000000000000000+(long)(h%2000000000)*1000000;
}
int UcOwned()
{
   int n=0;string families[]={"orb","macross","sol","entrylab"};
   for(int i=PositionsTotal()-1;i>=0;i--)if(PositionGetTicket(i)>0&&PositionGetString(POSITION_SYMBOL)==_Symbol)
      for(int f=0;f<4;f++)if(PositionGetInteger(POSITION_MAGIC)==UcMagic(families[f])){n++;break;}
   return n;
}
bool UcSetting(string family,string key,string value,bool live)
{
   if(family=="orb")return UcSetting_orb(key,value,live);
   if(family=="macross")return UcSetting_macross(key,value,live);
   if(family=="sol")return UcSetting_sol(key,value,live);
   if(family=="entrylab")return UcSetting_entrylab(key,value,live);
   return false;
}
void UcReset(string family,bool live)
{
   if(family=="orb")UcReset_orb(live);else if(family=="macross")UcReset_macross(live);
   else if(family=="sol")UcReset_sol(live);else if(family=="entrylab")UcReset_entrylab(live);
}
void UcForceInputs(string family,bool live)
{
   // RuntimeMagic is installation-scoped; the input seed stays in its original
   // safe numeric range for legacy arithmetic outside that function.
   long magic=700001+(live?0:10000);
   if(family=="sol")
   {
      if(live){live_sol_InpMagic=magic;live_sol_InpEaEnabled=false;live_sol_InpFileBridgeEnabled=false;live_sol_InpFileBridgeOnlyMode=false;live_sol_InpShowDashboard=false;live_sol_InpValidationInternalAudit=false;}
      else{sol_InpMagic=magic;sol_InpEaEnabled=false;sol_InpFileBridgeEnabled=false;sol_InpFileBridgeOnlyMode=false;sol_InpShowDashboard=false;sol_InpValidationInternalAudit=false;}
      return;
   }
   if(family=="orb")
   {
      if(live){live_orb_InpMagic=magic;live_orb_InpEaEnabled=false;live_orb_InpFileBridgeEnabled=false;live_orb_InpShowDashboard=false;live_orb_InpDrawHistoricalSignals=false;}
      else{orb_InpMagic=magic;orb_InpEaEnabled=false;orb_InpFileBridgeEnabled=false;orb_InpShowDashboard=false;orb_InpDrawHistoricalSignals=true;}
   }
   if(family=="macross")
   {
      if(live){live_macross_InpMagic=magic;live_macross_InpEaEnabled=false;live_macross_InpFileBridgeEnabled=false;live_macross_InpShowDashboard=false;live_macross_InpDrawHistoricalSignals=false;}
      else{macross_InpMagic=magic;macross_InpEaEnabled=false;macross_InpFileBridgeEnabled=false;macross_InpShowDashboard=false;macross_InpDrawHistoricalSignals=true;}
   }
   if(family=="entrylab")
   {
      if(live){live_entrylab_InpMagic=magic;live_entrylab_InpEaEnabled=false;live_entrylab_InpFileBridgeEnabled=false;live_entrylab_InpShowDashboard=false;live_entrylab_InpDrawHistoricalSignals=false;}
      else{entrylab_InpMagic=magic;entrylab_InpEaEnabled=false;entrylab_InpFileBridgeEnabled=false;entrylab_InpShowDashboard=false;entrylab_InpDrawHistoricalSignals=true;}
   }
}
int UcEngineInit(string f,bool live)
{
   g_ucRealm=(live?"L":"A")+f;g_ucLiveContext=false;
   if(live){if(f=="orb")return live_orb_OnInit();if(f=="macross")return live_macross_OnInit();if(f=="sol")return live_sol_OnInit();if(f=="entrylab"){live_entrylab_MA_CROSS_SIGNAL_MODE m=live_entrylab_InpMaCrossMode;live_entrylab_InpMaCrossMode=live_entrylab_MA_CROSS_ORIGINAL_MTF;int result=live_entrylab_OnInit();live_entrylab_InpMaCrossMode=m;return result;}}
   else{if(f=="orb")return orb_OnInit();if(f=="macross")return macross_OnInit();if(f=="sol")return sol_OnInit();if(f=="entrylab"){entrylab_MA_CROSS_SIGNAL_MODE m=entrylab_InpMaCrossMode;entrylab_InpMaCrossMode=entrylab_MA_CROSS_ORIGINAL_MTF;int result=entrylab_OnInit();entrylab_InpMaCrossMode=m;return result;}}
   return INIT_FAILED;
}
void UcEngineRelease(string f,bool live)
{
   g_ucRealm=(live?"L":"A")+f;g_ucLiveContext=false;
   if(live){if(f=="orb")live_orb_OnDeinit(REASON_PARAMETERS);else if(f=="macross")live_macross_OnDeinit(REASON_PARAMETERS);else if(f=="sol")live_sol_OnDeinit(REASON_PARAMETERS);else if(f=="entrylab")live_entrylab_OnDeinit(REASON_PARAMETERS);}
   else{if(f=="orb")orb_OnDeinit(REASON_PARAMETERS);else if(f=="macross")macross_OnDeinit(REASON_PARAMETERS);else if(f=="sol")sol_OnDeinit(REASON_PARAMETERS);else if(f=="entrylab")entrylab_OnDeinit(REASON_PARAMETERS);}
   EventSetTimer(1);
}

bool UcBuilder(string body,bool live)
{
   int preset=(int)StringToInteger(UcField(body,"r.entryPreset"));
   if(preset>0){
      if(live){live_entrylab_LabEngine e;if(!live_entrylab_LabScalperPreset(preset-1,e))return false;
         e.pipSl=live_entrylab_g_rtPipSlMode;e.pipSlPips=live_entrylab_g_rtPipSlPips;live_entrylab_g_labEngine=e;
         live_entrylab_g_rtMaCrossMode=live_entrylab_MA_CROSS_LAB_RULES;live_entrylab_g_labPreviewOnly=false;}
      else{entrylab_LabEngine e;if(!entrylab_LabScalperPreset(preset-1,e))return false;
         e.pipSl=entrylab_g_rtPipSlMode;e.pipSlPips=entrylab_g_rtPipSlPips;entrylab_g_labEngine=e;
         entrylab_g_rtMaCrossMode=entrylab_MA_CROSS_LAB_RULES;entrylab_g_labPreviewOnly=false;}
      return true;
   }
   if(UcField(body,"i.InpMaCrossMode")!="6")return true;
   if(live)
   {
      live_entrylab_LabEngine e;e.name=UcField(body,"name");e.edge=UcField(body,"b.edge")=="true";e.policy=UcField(body,"b.policy")=="true";
      e.exitsEnabled=UcField(body,"b.exitsEnabled")=="true";e.pipSl=live_entrylab_g_rtPipSlMode;e.pipSlPips=live_entrylab_g_rtPipSlPips;
      e.atrPeriod=(int)StringToInteger(UcField(body,"b.atrPeriod"));e.slAtr=StringToDouble(UcField(body,"b.slAtr"));e.tpAtr=StringToDouble(UcField(body,"b.tpAtr"));
      e.cooldown=(int)StringToInteger(UcField(body,"b.cooldown"));e.maxBars=(int)StringToInteger(UcField(body,"b.maxBars"));e.maxMinutes=(int)StringToInteger(UcField(body,"b.maxMinutes"));
      string sides[]={"buy","sell","exitBuy","exitSell"};
      for(int s=0;s<4;s++){int count=(int)StringToInteger(UcField(body,"b."+sides[s]+".count"));if(count<0||count>256)return false;
         if(s==0)ArrayResize(e.buy,count);else if(s==1)ArrayResize(e.sell,count);else if(s==2)ArrayResize(e.exitBuy,count);else ArrayResize(e.exitSell,count);
         for(int i=0;i<count;i++){string v[];if(StringSplit(UcField(body,"b."+sides[s]+"."+(string)i),',',v)!=8)return false;live_entrylab_LabRule r;
            r.feature=(int)StringToInteger(v[0]);r.compare=(int)StringToInteger(v[1]);r.threshold=StringToDouble(v[2]);r.gate=(int)StringToInteger(v[3]);r.negate=v[4]=="true";r.period=(int)StringToInteger(v[5]);r.rhsFeature=(int)StringToInteger(v[6]);r.rhsPeriod=(int)StringToInteger(v[7]);
            if(s==0)e.buy[i]=r;else if(s==1)e.sell[i]=r;else if(s==2)e.exitBuy[i]=r;else e.exitSell[i]=r;}}
      if(!live_entrylab_LabValidEngine(e))return false;live_entrylab_g_labEngine=e;live_entrylab_g_labPreviewOnly=false;
      return true;
   }
   entrylab_LabEngine e;e.name=UcField(body,"name");e.edge=UcField(body,"b.edge")=="true";e.policy=UcField(body,"b.policy")=="true";
   e.exitsEnabled=UcField(body,"b.exitsEnabled")=="true";e.pipSl=entrylab_g_rtPipSlMode;e.pipSlPips=entrylab_g_rtPipSlPips;
   e.atrPeriod=(int)StringToInteger(UcField(body,"b.atrPeriod"));e.slAtr=StringToDouble(UcField(body,"b.slAtr"));e.tpAtr=StringToDouble(UcField(body,"b.tpAtr"));
   e.cooldown=(int)StringToInteger(UcField(body,"b.cooldown"));e.maxBars=(int)StringToInteger(UcField(body,"b.maxBars"));e.maxMinutes=(int)StringToInteger(UcField(body,"b.maxMinutes"));
   string sides[]={"buy","sell","exitBuy","exitSell"};
   for(int s=0;s<4;s++){int count=(int)StringToInteger(UcField(body,"b."+sides[s]+".count"));if(count<0||count>256)return false;
      if(s==0)ArrayResize(e.buy,count);else if(s==1)ArrayResize(e.sell,count);else if(s==2)ArrayResize(e.exitBuy,count);else ArrayResize(e.exitSell,count);
      for(int i=0;i<count;i++){string v[];if(StringSplit(UcField(body,"b."+sides[s]+"."+(string)i),',',v)!=8)return false;entrylab_LabRule r;
         r.feature=(int)StringToInteger(v[0]);r.compare=(int)StringToInteger(v[1]);r.threshold=StringToDouble(v[2]);r.gate=(int)StringToInteger(v[3]);r.negate=v[4]=="true";r.period=(int)StringToInteger(v[5]);r.rhsFeature=(int)StringToInteger(v[6]);r.rhsPeriod=(int)StringToInteger(v[7]);
         if(s==0)e.buy[i]=r;else if(s==1)e.sell[i]=r;else if(s==2)e.exitBuy[i]=r;else e.exitSell[i]=r;}}
   if(!entrylab_LabValidEngine(e))return false;entrylab_g_labEngine=e;entrylab_g_labPreviewOnly=false;return true;
}

bool UcApply(string body,bool live)
{
   string f=UcField(body,"family");if(f!="orb"&&f!="macross"&&f!="sol"&&f!="entrylab")return false;
   if(UcField(body,"symbol")!=_Symbol||UcField(body,"brokerServer")!=AccountInfoString(ACCOUNT_SERVER)){g_ucError="TERMINAL_MARKET_MISMATCH";return false;}
   string previous=live?g_ucLiveFamily:g_ucAuditFamily;
   if(live&&UcOwned()>0&&(UcField(body,"configurationHash")!=g_ucRecoveredHash||f!=g_ucRecoveredFamily))
      {g_ucError="OPEN_POSITIONS_DIFFERENT_SETUP";return false;}
   if(previous!="")UcEngineRelease(previous,live);
   UcReset(f,live);string lines[];int n=StringSplit(body,'\n',lines);
   for(int i=0;i<n;i++){int eq=StringFind(lines[i],"=");if(eq<=0)continue;string k=StringSubstr(lines[i],0,eq),v=StringSubstr(lines[i],eq+1);
      if(StringFind(k,"i.")==0&&!UcSetting(f,k,v,live))return false;}
   UcForceInputs(f,live);
   if(f=="macross"||f=="entrylab"){
      if(!UcSetting(f,"i.InpIndependentEntries",UcField(body,"r.independent"),live)
         ||!UcSetting(f,"i.InpMaxConsecutiveEntries",UcField(body,"r.maxOpen"),live))return false;
   }
   int code=UcEngineInit(f,live);EventSetTimer(1);
   if(code!=INIT_SUCCEEDED){g_ucError="ENGINE_INIT_REJECTED";return false;}
   for(int i=0;i<n;i++){int eq=StringFind(lines[i],"=");if(eq<=0)continue;string k=StringSubstr(lines[i],0,eq),v=StringSubstr(lines[i],eq+1);
      if(StringFind(k,"r.")==0&&!UcSetting(f,k,v,live))return false;}
   int masks[7];for(int i=0;i<7;i++)masks[i]=(int)StringToInteger(UcField(body,"m."+(string)i));
   if(f=="orb")
   {
      if(live){live_orb_g_rtTargetLeg=(int)live_orb_ORB_TARGET_CUSTOM;live_orb_g_orbBridgeEnabled=false;live_orb_g_orbNativeWithBridgeOnly=true;live_orb_g_runtimeMagic=UcMagic(f);live_orb_g_rtEaEnabled=true;for(int i=0;i<7;i++)live_orb_g_tcalDayHours[i]=masks[i];}
      else{orb_g_rtTargetLeg=(int)orb_ORB_TARGET_CUSTOM;orb_g_orbBridgeEnabled=false;orb_g_rtEaEnabled=false;orb_g_rtHistoricalWeeks=g_ucWeeks;for(int i=0;i<7;i++)orb_g_tcalDayHours[i]=masks[i];}
   }
   if(f=="macross")
   {
      if(live){live_macross_g_rtTargetLeg=(int)live_macross_ORB_TARGET_CUSTOM;live_macross_g_rtAdvancedReverse=false;live_macross_g_orbBridgeEnabled=false;live_macross_g_orbNativeWithBridgeOnly=true;live_macross_g_runtimeMagic=UcMagic(f);live_macross_g_rtEaEnabled=true;live_macross_g_rtMaCrossMode=live_macross_InpMaCrossMode;live_macross_g_rtMaCrossPair=live_macross_InpMaCrossPair;for(int i=0;i<7;i++)live_macross_g_tcalDayHours[i]=masks[i];}
      else{macross_g_rtTargetLeg=(int)macross_ORB_TARGET_CUSTOM;macross_g_rtAdvancedReverse=false;macross_g_orbBridgeEnabled=false;macross_g_rtEaEnabled=false;macross_g_rtHistoricalWeeks=g_ucWeeks;macross_g_rtMaCrossMode=macross_InpMaCrossMode;macross_g_rtMaCrossPair=macross_InpMaCrossPair;for(int i=0;i<7;i++)macross_g_tcalDayHours[i]=masks[i];}
   }
   if(f=="entrylab")
   {
      if(live){live_entrylab_g_rtTargetLeg=(int)live_entrylab_ORB_TARGET_CUSTOM;live_entrylab_g_rtAdvancedReverse=false;live_entrylab_g_orbBridgeEnabled=false;live_entrylab_g_orbNativeWithBridgeOnly=true;live_entrylab_g_runtimeMagic=UcMagic(f);live_entrylab_g_rtEaEnabled=true;live_entrylab_g_rtMaCrossMode=live_entrylab_InpMaCrossMode;live_entrylab_g_rtMaCrossPair=live_entrylab_InpMaCrossPair;for(int i=0;i<7;i++)live_entrylab_g_tcalDayHours[i]=masks[i];}
      else{entrylab_g_rtTargetLeg=(int)entrylab_ORB_TARGET_CUSTOM;entrylab_g_rtAdvancedReverse=false;entrylab_g_orbBridgeEnabled=false;entrylab_g_rtEaEnabled=false;entrylab_g_rtHistoricalWeeks=g_ucWeeks;entrylab_g_rtMaCrossMode=entrylab_InpMaCrossMode;entrylab_g_rtMaCrossPair=entrylab_InpMaCrossPair;for(int i=0;i<7;i++)entrylab_g_tcalDayHours[i]=masks[i];}
      if(!UcBuilder(body,live)){g_ucError="BUILDER_REJECTED";return false;}
   }
   if(f=="sol")
   {
      if(live){live_sol_g_target=live_sol_ERL_RR_CUSTOM;live_sol_g_fileBridgeEnabled=false;live_sol_g_fileBridgeOnlyMode=false;live_sol_g_eaEnabled=true;for(int i=0;i<7;i++)live_sol_g_tcalDayHours[i]=masks[i];}
      else{sol_g_target=sol_ERL_RR_CUSTOM;sol_g_fileBridgeEnabled=false;sol_g_eaEnabled=false;sol_g_histWeeks=g_ucWeeks;for(int i=0;i<7;i++)sol_g_tcalDayHours[i]=masks[i];}
   }
   string reason="";
   if(f=="sol"){
      bool valid=live?live_sol_LnNasCompatible(live_sol_g_lnNas):sol_LnNasValid(sol_g_lnNas);
      if(!valid){g_ucError="SOL_POSITION_SETTINGS_INCOMPATIBLE";return false;}
   }
   if(f=="macross"||f=="entrylab"){
      bool independent=UcField(body,"r.independent")=="true",valid=true;
      if(independent){
         if(f=="macross")valid=live?live_macross_MaIndependentExecutionAllowed(reason):macross_MaIndependentShape(reason);
         else valid=live?live_entrylab_MaIndependentExecutionAllowed(reason):entrylab_MaIndependentShape(reason);
      }
      if(!valid){g_ucError="INDEPENDENT_SETTINGS_INCOMPATIBLE";return false;}
   }
   if(live){g_ucLiveFamily=f;g_ucLiveHash=UcField(body,"configurationHash");g_ucRecoveredHash=g_ucLiveHash;g_ucRecoveredFamily=f;
      UcSignedWrite(g_ucFolder+"resume.txt","family="+f+"\nconfigurationHash="+g_ucLiveHash);}
   else g_ucAuditFamily=f;
   g_ucError="";return true;
}

datetime UcUtc(string family,datetime at)
{
   if(at<=0)return 0;if(family=="orb")return orb_OrbServerToUtc(at);
   if(family=="macross")return at-(int)MathRound(macross_InpBrokerGmtOffsetHours*3600.0);
   if(family=="entrylab")return at-(int)MathRound(entrylab_InpBrokerGmtOffsetHours*3600.0);
   return at-sol_InpSolBrokerUtcOffsetMin*60;
}
string UcSafe(string s){StringReplace(s,"\n"," ");StringReplace(s,"\r"," ");StringReplace(s,"|","/");return s;}
string UcTradeRow(string family,datetime signal,datetime entry,datetime exit,int direction,double price,double sl,double tp,double exitPrice,double netR,bool valid,bool closed,string reason,double spread)
{
   return (string)UcUtc(family,signal)+"|"+(string)UcUtc(family,entry)+"|"+(string)UcUtc(family,exit)+"|"+(string)direction+"|"+DoubleToString(price,12)+"|"+DoubleToString(sl,12)+"|"+DoubleToString(tp,12)+"|"+DoubleToString(exitPrice,12)+"|"+DoubleToString(netR,12)+"|"+(string)(int)valid+"|"+(string)(int)closed+"|"+UcSafe(reason)+"|"+(spread==EMPTY_VALUE?"":DoubleToString(spread*SymbolInfoDouble(_Symbol,SYMBOL_POINT),12))+"\n";
}
void UcResult()
{
   string rows="";int count=0;
   if(g_ucAuditFamily=="orb"){count=ArraySize(orb_g_axTrades);for(int i=0;i<count;i++){orb_AxTrade t=orb_g_axTrades[i];rows+=UcTradeRow("orb",t.signalTime,t.entryTime,t.exitTime,t.direction,t.entry,t.sl,t.tp,t.exitPrice,t.netR,t.valid,t.closed,t.reason,t.entrySpreadPoints);}}
   if(g_ucAuditFamily=="macross"){count=ArraySize(macross_g_axTrades);for(int i=0;i<count;i++){macross_AxTrade t=macross_g_axTrades[i];rows+=UcTradeRow("macross",t.signalTime,t.entryTime,t.exitTime,t.direction,t.entry,t.sl,t.tp,t.exitPrice,t.netR,t.valid,t.closed,t.reason,t.entrySpreadPoints);}}
   if(g_ucAuditFamily=="entrylab"){count=ArraySize(entrylab_g_axTrades);for(int i=0;i<count;i++){entrylab_AxTrade t=entrylab_g_axTrades[i];rows+=UcTradeRow("entrylab",t.signalTime,t.entryTime,t.exitTime,t.direction,t.entry,t.sl,t.tp,t.exitPrice,t.netR,t.valid,t.closed,t.reason,t.entrySpreadPoints);}}
   if(g_ucAuditFamily=="sol"){count=ArraySize(sol_g_axTrades);for(int i=0;i<count;i++){sol_AxTrade t=sol_g_axTrades[i];rows+=UcTradeRow("sol",t.signalTime,t.entryTime,t.exitTime,t.direction,t.entry,t.sl,t.tp,t.exitPrice,t.netR,t.valid,t.closed,t.reason,t.entrySpreadPoints);}}
   if(count>10000){g_ucError="RESULT_ROW_LIMIT";UcSignedWrite(g_ucFolder+"result.txt","jobId="+g_ucJob+"\nattemptId="+g_ucAttempt+"\nerror="+g_ucError);}
   else UcSignedWrite(g_ucFolder+"result.txt","jobId="+g_ucJob+"\nattemptId="+g_ucAttempt+"\nconfigurationHash="+g_ucConfig+"\nrequestHash="+g_ucRequest+"\nrows="+(string)count+"\nTRADES\n"+rows);
   g_ucAuditPending=false;
}
void UcAuditStep()
{
   if(!g_ucAuditPending)return;
   g_ucLiveContext=false;g_ucRealm="A"+g_ucAuditFamily;
   if(GetTickCount64()>=g_ucAuditUntil){g_ucAuditPending=false;g_ucError="AUDIT_AUTHORITY_EXPIRED";return;}
   string phase="replaying";int done=0,total=0;bool ready=false;
   if(g_ucAuditFamily=="sol")
   {
      if(!g_ucAuditStarted){sol_RecalculateHistoricalStats();g_ucAuditStarted=true;}
      if(sol_g_auditMacroPending)sol_ContinueHistoricalMacroAudit(sol_g_auditGeneration,35);
      ready=!sol_g_auditMacroPending&&sol_g_axReady;
      done=(int)sol_g_histAuditProgressPct;total=100;
   }
   else
   {
      if(g_ucAuditFamily=="orb"){
         if(!g_ucAuditStarted){orb_g_histNeedsRedraw=true;orb_g_lastHistBuild=0;orb_DrawHistoricalSignals();g_ucAuditStarted=true;}
         orb_ProcessHistoricalAuditStep();ready=orb_g_axReady&&!orb_g_histAuditRunning&&!orb_g_histCoveragePending;
         done=(int)orb_g_histAuditProgressPct;total=100;
         if(orb_g_histCoveragePending){phase="downloading";done=0;total=0;if(GetTickCount64()>g_ucNextRetry){orb_g_histNeedsRedraw=true;orb_DrawHistoricalSignals();g_ucNextRetry=GetTickCount64()+5000;}}
      }
      if(g_ucAuditFamily=="macross"){
         if(!g_ucAuditStarted){macross_g_histNeedsRedraw=true;macross_g_lastHistBuild=0;macross_DrawHistoricalSignals();g_ucAuditStarted=true;}
         macross_ProcessHistoricalAuditStep();ready=macross_g_axReady&&!macross_g_histAuditRunning&&!macross_g_histCoveragePending;
         done=(int)macross_g_histAuditProgressPct;total=100;
         if(macross_g_histCoveragePending){phase="downloading";done=0;total=0;if(GetTickCount64()>g_ucNextRetry){macross_g_histNeedsRedraw=true;macross_DrawHistoricalSignals();g_ucNextRetry=GetTickCount64()+5000;}}
      }
      if(g_ucAuditFamily=="entrylab"){
         if(!g_ucAuditStarted){entrylab_g_histNeedsRedraw=true;entrylab_g_lastHistBuild=0;entrylab_DrawHistoricalSignals();g_ucAuditStarted=true;}
         entrylab_ProcessHistoricalAuditStep();ready=entrylab_g_axReady&&!entrylab_g_histAuditRunning&&!entrylab_g_histCoveragePending;
         done=(int)entrylab_g_histAuditProgressPct;total=100;
         if(entrylab_g_histCoveragePending){phase="downloading";done=0;total=0;if(GetTickCount64()>g_ucNextRetry){entrylab_g_histNeedsRedraw=true;entrylab_DrawHistoricalSignals();g_ucNextRetry=GetTickCount64()+5000;}}
      }
   }
   UcSignedWrite(g_ucFolder+"progress.txt","jobId="+g_ucJob+"\nattemptId="+g_ucAttempt+"\nphase="+phase+"\nprocessed="+(string)done+"\ntotal="+(string)total);
   if(ready)UcResult();
}

void UcStatus()
{
   UcSignedWrite(g_ucFolder+"status.txt","symbol="+_Symbol+"\nbrokerServer="+AccountInfoString(ACCOUNT_SERVER)+"\naccountLogin="+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"\nopenPositions="+(string)UcOwned()+"\ntrading="+(g_ucTrading&&GetTickCount64()<g_ucAuthorityUntil?"true":"false")+"\nconfigurationHash="+g_ucLiveHash+"\nerror="+g_ucError+"\nat="+(string)TimeGMT());
}
int UcInit()
{
   g_ucInstallation=InpInstallationId;StringToLower(g_ucInstallation);
   if(StringLen(g_ucInstallation)!=36||MQLInfoInteger(MQL_TESTER))return INIT_PARAMETERS_INCORRECT;
   for(int i=0;i<36;i++){ushort c=StringGetCharacter(g_ucInstallation,i);if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')||c=='-'))return INIT_PARAMETERS_INCORRECT;}
   g_ucFolder="Stratum\\"+g_ucInstallation+"\\";g_ucKey=UcRead(g_ucFolder+"local.key");
   if(StringLen(g_ucKey)!=32){Print("STRATUM: installation helper/key missing");return INIT_FAILED;}
   // Exclusive FILE_COMMON handle also fences duplicate terminals on this PC.
   g_ucLockHandle=FileOpen(g_ucFolder+"terminal.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(g_ucLockHandle==INVALID_HANDLE)return INIT_FAILED;
   string resume=UcRead(g_ucFolder+"resume.txt");int signature=StringFind(resume,"\nHMAC=");
   if(signature>=0){string body=StringSubstr(resume,0,signature);
      if(StringSubstr(resume,signature+6)==UcHmac(body)){g_ucRecoveredFamily=UcField(body,"family");g_ucRecoveredHash=UcField(body,"configurationHash");}}
   g_ucTrading=false;EventSetTimer(1);UcStatus();Comment("STRATUM / STANDBY\nWeb authority required. Trading OFF.");return INIT_SUCCEEDED;
}
void UcShutdown()
{
   g_ucTrading=false;g_ucAuditPending=false;UcEngineRelease(g_ucAuditFamily,false);UcEngineRelease(g_ucLiveFamily,true);
   if(g_ucLockHandle!=INVALID_HANDLE)FileClose(g_ucLockHandle);g_ucLockHandle=INVALID_HANDLE;EventKillTimer();Comment("");
}
void UcLiveTick()
{
   if(g_ucLiveFamily=="")return;g_ucRealm="L"+g_ucLiveFamily;g_ucLiveContext=true;
   if(g_ucLiveFamily=="orb")live_orb_OnTick();else if(g_ucLiveFamily=="macross")live_macross_OnTick();else if(g_ucLiveFamily=="sol")live_sol_OnTick();else if(g_ucLiveFamily=="entrylab")live_entrylab_OnTick();
   g_ucLiveContext=false;
}
void UcLiveManagement()
{
   if(g_ucLiveFamily=="")return;g_ucRealm="L"+g_ucLiveFamily;g_ucLiveContext=false;
   if(g_ucLiveFamily=="sol"){live_sol_RegimeV3Update(false);live_sol_EnforceRiskBreach();live_sol_ManagePositions();live_sol_ScanClosedHistory();}
   else if(g_ucLiveFamily=="orb"){live_orb_RegimeV3Update(false);live_orb_EnforceRiskBreach();live_orb_ManagePositions();}
   else if(g_ucLiveFamily=="macross"){live_macross_RegimeV3Update(false);live_macross_EnforceRiskBreach();live_macross_ManagePositions();}
   else if(g_ucLiveFamily=="entrylab"){live_entrylab_RegimeV3Update(false);live_entrylab_EnforceRiskBreach();live_entrylab_ManagePositions();}
}
void UcTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(g_ucLiveFamily=="")return;g_ucRealm="L"+g_ucLiveFamily;g_ucLiveContext=false;
   if(g_ucLiveFamily=="orb")live_orb_OnTradeTransaction(trans,request,result);else if(g_ucLiveFamily=="macross")live_macross_OnTradeTransaction(trans,request,result);else if(g_ucLiveFamily=="sol")live_sol_OnTradeTransaction(trans,request,result);else if(g_ucLiveFamily=="entrylab")live_entrylab_OnTradeTransaction(trans,request,result);
}
void UcTimer()
{
   string body="",packet=UcRead(g_ucFolder+"command.txt");
   if(UcVerified(packet,body))
   {
      string command=UcField(body,"command");
      g_ucAuditUntil=GetTickCount64()+(ulong)MathMax(0,(long)StringToInteger(UcField(body,"expires"))-(long)TimeGMT())*1000;
      if(command=="audit"&&UcField(body,"jobId")!=g_ucJob)
      {
         g_ucTrading=false;g_ucJob=UcField(body,"jobId");g_ucAttempt=UcField(body,"attemptId");g_ucConfig=UcField(body,"configurationHash");g_ucRequest=UcField(body,"requestHash");
         g_ucFromUtc=(datetime)StringToInteger(UcField(body,"from"));g_ucToUtc=(datetime)StringToInteger(UcField(body,"to"));g_ucWeeks=(int)StringToInteger(UcField(body,"weeks"));
         g_ucAuditAsOf=g_ucToUtc+(datetime)((long)TimeCurrent()-(long)TimeGMT());
         g_ucAuditStarted=false;g_ucAuditPending=UcApply(body,false);
         if(g_ucAuditPending){if(g_ucAuditFamily=="orb")g_ucAuditAsOf=orb_OrbUtcToServer(g_ucToUtc);
            else if(g_ucAuditFamily=="macross")g_ucAuditAsOf=g_ucToUtc+(int)MathRound(macross_InpBrokerGmtOffsetHours*3600);
            else if(g_ucAuditFamily=="entrylab")g_ucAuditAsOf=g_ucToUtc+(int)MathRound(entrylab_InpBrokerGmtOffsetHours*3600);
            else g_ucAuditAsOf=g_ucToUtc+sol_InpSolBrokerUtcOffsetMin*60;}
         if(!g_ucAuditPending)UcSignedWrite(g_ucFolder+"result.txt","jobId="+g_ucJob+"\nattemptId="+g_ucAttempt+"\nerror="+(g_ucError==""?"SETTINGS_REJECTED":g_ucError));
      }
      if(command=="stop"){g_ucTrading=false;g_ucAuditPending=false;}
      if(command=="live")
      {
         string hash=UcField(body,"configurationHash");
         if(hash==g_ucLiveHash||UcApply(body,true)){g_ucTrading=true;g_ucAuthorityUntil=g_ucAuditUntil;}
      }
   }
   else {g_ucTrading=false;g_ucAuditPending=false;}
   UcAuditStep();UcLiveManagement();UcStatus();
   Comment("STRATUM / "+(g_ucTrading?"TRADING ON":"TRADING OFF")+"\n"+(g_ucAuditPending?"AUDIT / "+g_ucAuditFamily:"STANDBY")+"\n"+g_ucError);
}
#endif
