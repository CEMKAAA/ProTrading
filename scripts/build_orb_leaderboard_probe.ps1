$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbLeaderboardProbe'
[IO.Directory]::CreateDirectory($dest)|Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
$source=[regex]::Replace($source,'(input\s+bool\s+InpShowDashboard\s*=)\s*false','$1 true')
$source+=@'
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;PREFIX="LBPROBE_";
   OrbStrategyPreset p;OrbStrategyPresetLoad(7,p);OrbStrategyPresetApplyValues(p);
   g_strategyPresetIndex=7;g_strategyCandidateIndex=7;
   OrbLibraryRefreshLayout();g_lbOpen=true;g_lbMl=false;OrbLbSort();OrbLbDraw();ChartRedraw(0);
   bool ok=ArraySize(g_lbOrder)==53;
   for(int mode=0;mode<2;mode++)
   {
      g_lbMl=(mode==1);OrbLbSort();double previous=1e20;
      for(int i=0;i<ArraySize(g_lbOrder);i++)
      {
         OrbLbRow r;OrbLbSnapshot(g_lbOrder[i],r);
         double value=g_lbMl?(r.hasMl?r.mlScore:-1):r.baseScore;
         if(value>previous+1e-9)ok=false;previous=value;
      }
      // Hidden terminal chart dimensions can be tiny; render the screenshot's 1500px canvas.
      g_libraryDashScale=1;g_libraryDashX=InpDashboardX;g_libraryDashY=InpDashboardY;
      OrbLbDraw();ChartRedraw(0);Sleep(100);
      if(!ChartScreenShot(0,mode==0?"leaderboard_base.png":"leaderboard_ml.png",1500,850,ALIGN_LEFT))ok=false;
   }
   bool consumed=OrbLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,PREFIX+"BTN_FILT_ATR");
   if(!consumed||!g_lbOpen||g_mlEnabled)ok=false;
   if(!OrbLbEvent(CHARTEVENT_OBJECT_ENDEDIT,0,0,PREFIX+"EDIT_RISK_PCT"))ok=false;
   OrbLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,PREFIX+"BTN_LB_NEXT");
   if(g_lbPage!=1)ok=false;
   OrbLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,PREFIX+"BTN_LB_PREV");
   if(g_lbPage!=0)ok=false;
   OrbLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,PREFIX+"BTN_LB_CLOSE");
   if(g_lbOpen||ObjectFind(0,PREFIX+"BTN_LB_CLOSE")>=0)ok=false;
   int h=FileOpen("leaderboard_probe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE){FileWrite(h,ok?"PASS:53 rows, both sorts, modal guards, pagination, cleanup, ML stays OFF":"FAIL");FileClose(h);}
   Print("ORB_LEADERBOARD_PROBE ",ok?"PASS":"FAIL");
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'OrbLeaderboardProbe.mq5'),$source,[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $seed -Filter '*.mqh'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dest -Force}
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbLeaderboardProbe\OrbLeaderboardProbe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $root 'logs/demo_sync_20260909_v686/leaderboard_probe.ini'),$ini)
Write-Output 'Isolated no-order leaderboard probe generated'
