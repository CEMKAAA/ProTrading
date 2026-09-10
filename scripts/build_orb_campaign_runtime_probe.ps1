$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbCampaignRuntimeProbe'
[IO.Directory]::CreateDirectory($dest)|Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
$source+=@'
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;
   int checked=0,vectors=0,failed=0;
   OrbUserReload(true);
   for(int i=0;i<OrbStrategyPresetCount();i++)
   {
      OrbStrategyPreset p;OrbCampaignInfo info;
      if(!OrbStrategyPresetLoad(i,p)||!OrbCampaignRecord(p.id,info)||info.symbol!=_Symbol)continue;
      g_strategyPresetIndex=i;g_strategyCandidateIndex=i;
      OrbStrategyPresetApplyValues(p);
      string values[];ArrayResize(values,50);
      int f=FileOpen("OrbMLCampaign_20260909_v3\\Settings\\"+p.id+".txt",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
      if(f==INVALID_HANDLE){failed++;continue;}
      for(int v=0;v<50;v++)values[v]=FileReadString(f);FileClose(f);
      if(!OrbCustomRuntimeRead(values,4,true)||!OrbCampaignLoad())
      {
         Print("CAMPAIGN_RUNTIME_FAIL ",p.id," ",g_mlStatus," matches=",OrbStrategyPresetMatchesRuntime(p),
            " runtime=",OrbCampaignRuntimeHash()==info.runtime_hash," custom=",OrbMlSha256(OrbCustomPresetDump(p))==info.custom_hash,
            " symbol=",_Symbol==info.symbol," tf=",(int)_Period==info.tf," broker=",AccountInfoString(ACCOUNT_SERVER)==info.broker);
         string actual[];StringSplit(OrbCustomRuntimeDump(),'\n',actual);
         for(int v=0;v<40;v++)if(actual[v]!=values[v+4])Print("CAMPAIGN_SETTING_DIFF ",p.id," field=",v," actual=",actual[v]," expected=",values[v+4]);
         failed++;continue;
      }
      checked++;
      ArrayResize(g_mlJobs,0);g_mlJobChoice=-1;ArrayResize(g_mlDatasets,0);g_mlDatasetChoice=-1;
      if(!OrbMlJobUiEvent(PREFIX+"BTN_ML_USE")||!g_campaignReady||!g_mlUsingCampaign)
      {failed++;Print("CAMPAIGN_USE_RESULT_FAIL ",p.id," ",g_mlJobNote);}
      int h=FileOpen("OrbML\\CampaignModels\\probe_vectors.txt",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,';',CP_UTF8);
      if(h==INVALID_HANDLE){failed++;continue;}
      while(!FileIsEnding(h))
      {
         string id=FileReadString(h);if(id=="")break;
         double expected=StringToDouble(FileReadString(h)),threshold=StringToDouble(FileReadString(h));
         bool keep=FileReadString(h)=="1";double x[];ArrayResize(x,40);
         for(int k=0;k<40;k++)x[k]=StringToDouble(FileReadString(h));
         if(id!=p.id)continue;
         double actual=0;
         if(!OrbCampaignPredict(x,actual)||MathAbs(actual-expected)>1e-10||(!g_campaignActive||actual>=threshold)!=keep)
         {Print("CAMPAIGN_PARITY_FAIL ",id," actual=",actual," expected=",expected);failed++;}
         vectors++;
      }
      FileClose(h);
      double old=g_rtPipSlPips;g_rtPipSlPips+=1;
      if(OrbCampaignBinding(info)){failed++;Print("CAMPAIGN_MUTATION_NOT_BLOCKED ",p.id);}
      g_rtPipSlPips=old;
      string broker=info.broker;info.broker="WRONG_BROKER";
      if(OrbCampaignBinding(info)){failed++;Print("CAMPAIGN_BROKER_NOT_BLOCKED ",p.id);}
      info.broker=broker;
      if(g_mlEnabled){failed++;Print("CAMPAIGN_AUTO_ACTIVATION ",p.id);}
   }
   int out=FileOpen("campaign_runtime_"+_Symbol+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(out!=INVALID_HANDLE){FileWrite(out,"models="+(string)checked+" vectors="+(string)vectors+" failures="+(string)failed);FileClose(out);}
   Print("CAMPAIGN_RUNTIME ",_Symbol," models=",checked," vectors=",vectors," failures=",failed);
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'OrbCampaignRuntimeProbe.mq5'),$source,[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $seed -Filter '*.mqh'|ForEach-Object {
    $text=[IO.File]::ReadAllText($_.FullName)
    $text=$text.Replace('OrbStrategyUserLibrary\\','OrbMLCampaign_20260909_v3\\UserStrategies\\')
    [IO.File]::WriteAllText((Join-Path $dest $_.Name),$text,[Text.UTF8Encoding]::new($false))
}
foreach($symbol in @('JP225m','USDJPYm','USTECm')){
    $ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbCampaignRuntimeProbe\OrbCampaignRuntimeProbe`r`nSymbol=$symbol`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
    [IO.File]::WriteAllText((Join-Path $root "logs/demo_sync_20260909_v687/probe_$symbol.ini"),$ini)
}
Write-Output 'No-order model parity probes generated'
