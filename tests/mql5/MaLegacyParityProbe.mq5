#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int probeFile=INVALID_HANDLE;
string probeId="";
bool ReadSnapshot(string path,string &v[])
{
   int f=FileOpen(path,FILE_READ|FILE_BIN);if(f==INVALID_HANDLE)return false;
   uchar bytes[];int n=(int)FileSize(f);ArrayResize(bytes,n);FileReadArray(f,bytes);FileClose(f);
   return StringSplit(CharArrayToString(bytes,0,n,CP_UTF8),'\n',v)==114;
}
void ProbeTrade(datetime entry,string direction,const HistResult &sim)
{
   string reason=sim.outcome=="NEW_DAY_REVERSE_EXIT"?"MA_REVERSE_EXIT":sim.outcome;
   FileWriteString(probeFile,"{\"kind\":\"trade\",\"id\":\""+probeId+"\",\"signal\":"+(string)(long)entry
      +",\"dir\":\""+direction+"\",\"valid\":"+(sim.valid?"true":"false")+",\"outcome\":\""+reason
      +"\",\"exit\":"+(string)(long)sim.exitTime+",\"price\":"+DoubleToString(sim.exitPrice,10)
      +",\"r\":"+DoubleToString(sim.netR,12)+",\"data\":\""+sim.invalidReason+"\"}\n");
}
void OnStart()
{
   probeFile=FileOpen("MaLegacyParity.jsonl",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(probeFile==INVALID_HANDLE)return;
   FileWriteString(probeFile,"{\"kind\":\"run\",\"symbol\":\""+_Symbol+"\"}\n");FileFlush(probeFile);
   for(int retry=0;retry<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   datetime until=D'2026.09.19 00:00',from=until-14*86400;
   for(int slot=0;slot<16;slot++)
   {
      string v[];
      if(!ReadSnapshot("MaLegacyParity\\"+(string)slot+".preset",v))
      {FileWriteString(probeFile,"{\"kind\":\"error\",\"slot\":"+(string)slot+",\"reason\":\"snapshot_read\"}\n");continue;}
      if(v[3]!=_Symbol)continue;
      OrbStrategyPreset p;OrbPresetDefaults(p);
      if(!OrbCustomPresetRead(v,6,p))continue;
      probeId=p.id;
      string meta[];StringSplit(v[5],'|',meta);
      if(meta[0]!=OrbCustomInputSignature())
      {FileWriteString(probeFile,"{\"kind\":\"error\",\"id\":\""+p.id+"\",\"reason\":\"input_signature\"}\n");continue;}
      g_maIndependent=false;g_maMaxConsecutive=1;
      if(ArraySize(meta)>=2){string mode[];StringSplit(StringSubstr(meta[1],9),',',mode);g_maIndependent=mode[0]=="1";g_maMaxConsecutive=(int)StringToInteger(mode[1]);}
      OrbStrategyPresetApplyValues(p);OrbCustomRuntimeRead(v,64,true);
#ifdef MA_MIGRATION_CANDIDATE
      g_maReverseExit=!g_maIndependent;g_maReverseWait=0;
#endif
      g_runtimeMagic=91919001;g_orbBridgeEnabled=false;g_auditRuntime=false;
      g_rtAdvancedAuditEngine=true;g_rtHistoricalWeeks=2;
      g_histRunNow=until;g_histRunDays=14;g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      g_histRunNyMid=until;g_histNeedsRedraw=true;
      g_maAuditPositionUntil=0;g_maHistSeriesDir=0;g_maHistSeriesCount=0;
      OrbResetHistoricalStats();BeginHistoricalSnapshot();
      ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);ArrayResize(g_histWindowSignals,0);
      ArrayResize(g_regimeReferenceSignals,0);ArrayResize(g_regimeReferenceWindows,0);
      string detail="";bool hard=false;
      for(int retry=0;retry<30;retry++){if(EnsureOrbAuditHistoryCoverage(14,detail,hard))break;Sleep(500);}
      bool ready=false;
      for(int retry=0;retry<30;retry++)
      {
         if(MaCrossAuditBuild(_Symbol,g_rtSignalTf,from,until,g_rtMaCrossMode,g_rtMaCrossPair,InpMaFastLength,InpMaMediumLength,InpMaSlowLength)
            &&BuildHistoricalNasEventCache(14,until,detail)){ready=true;break;}
         Sleep(500);
      }
      if(!ready){FileWriteString(probeFile,"{\"kind\":\"error\",\"id\":\""+p.id+"\",\"reason\":\"history\"}\n");continue;}
      int count=ArraySize(g_maCrossAuditEvents);ArrayResize(g_histDaySnapshots,count);
      InitializeHistoricalTickReplayCoverage();
      for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
      for(int i=0;i<count;i++){if(IsStopped())break;ProcessHistoricalCalcDay(i);}
      FileWriteString(probeFile,"{\"kind\":\"summary\",\"id\":\""+p.id+"\",\"slot\":"+(string)slot
         +",\"independent\":"+(g_maIndependent?"true":"false")+",\"raw\":"+(string)count
         +",\"total\":"+(string)g_histTotal+",\"w\":"+(string)g_histWins+",\"l\":"+(string)g_histLosses
         +",\"o\":"+(string)g_histOpen+",\"data\":"+(string)g_histInvalid+",\"r\":"+DoubleToString(g_histNetR,12)+"}\n");
      FileFlush(probeFile);Print("PARITY slot=",slot," total=",g_histTotal," R=",g_histNetR," DATA=",g_histInvalid);
      g_histNasCacheActive=false;
   }
   FileClose(probeFile);
}
