$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$dest=Join-Path $worker 'MQL5/Scripts/OrbR7Probe'
$files=Join-Path $worker 'MQL5/Files/OrbR7Probe'
[IO.Directory]::CreateDirectory($dest)|Out-Null
[IO.Directory]::CreateDirectory($files)|Out-Null
foreach($name in @('OrbStrategyMLCore.mqh','OrbStrategyR7Core.mqh','OrbStrategyR7Registry.mqh')){
 Copy-Item -LiteralPath (Join-Path $root "IndicatorCodeExamples/$name") -Destination $dest
}
Get-ChildItem -LiteralPath (Join-Path $root 'logs/OrbR7Runtime_20260912/Files/OrbML/R7') -Filter '*.r7' | Copy-Item -Destination $files
Copy-Item -LiteralPath (Join-Path $root 'logs/OrbR7Runtime_20260912/probe_vectors.txt') -Destination $files
$source=@'
#property strict
#include "OrbStrategyR7Core.mqh"
struct OrbCampaignInfo {string id,config,dataset,model_sha,kind,runtime_hash,custom_hash,symbol,broker,inputs,csv;int tf;};
#include "OrbStrategyR7Registry.mqh"
string ReadBinary(string path)
{
 int h=FileOpen(path,FILE_READ|FILE_BIN);if(h==INVALID_HANDLE)return "";
 uchar b[];int n=(int)FileSize(h);ArrayResize(b,n);FileReadArray(h,b);FileClose(h);return CharArrayToString(b,0,n,CP_UTF8);
}
void OnStart()
{
 if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
 int h=FileOpen("OrbR7Probe\\probe_vectors.txt",FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
 if(h==INVALID_HANDLE){Print("R7_PROBE missing vectors");return;}
 int tested=0,failed=0,packs=0;double maxError=0;string current="",reason="";OrbR7Pack pack;ZeroMemory(pack);OrbCampaignInfo info;
 while(!FileIsEnding(h))
 {
  string line=FileReadString(h);if(line=="")continue;string a[];
  if(StringSplit(line,';',a)!=43){failed++;continue;}
  if(current!=a[0])
  {
   current=a[0];packs++;
   string text=ReadBinary("OrbR7Probe\\"+current+".r7");
   if(!OrbR7Record(current,info)||!OrbR7Parse(text,current,info.config,info.dataset,pack,reason)){failed++;Print(current," ",reason);continue;}
   OrbR7Pack bad;
   if(OrbR7Parse(text,current+"wrong",info.config,info.dataset,bad,reason))failed++;
   if(OrbR7Parse(text+"corrupt",current,info.config,info.dataset,bad,reason))failed++;
   double empty[];ArrayResize(empty,40);ArrayInitialize(empty,0);double s=0;
   if(OrbR7Score(pack,empty,pack.state[0].update-1,s,reason))failed++;
   if(OrbR7Score(pack,empty,pack.state[pack.states-1].stop,s,reason))failed++;
  }
  double x[];ArrayResize(x,40);for(int i=0;i<40;i++)x[i]=StringToDouble(a[i+3]);
  double actual=0,expected=StringToDouble(a[2]);
  if(!OrbR7Score(pack,x,(datetime)StringToInteger(a[1]),actual,reason)){failed++;continue;}
  double error=MathAbs(actual-expected);maxError=MathMax(maxError,error);
  if(error>1e-10||(actual>=0)!=(expected>=0))failed++;tested++;
 }
 FileClose(h);
 string result=StringFormat("{\"packs\":%d,\"vectors\":%d,\"failed\":%d,\"max_error\":%.17g}",packs,tested,failed,maxError);
 int o=FileOpen("OrbR7Probe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);if(o!=INVALID_HANDLE){FileWriteString(o,result);FileClose(o);}
 Print("R7_PROBE ",result);
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'OrbR7Probe.mq5'),$source)
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbR7Probe\OrbR7Probe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $root 'logs/OrbR7Runtime_20260912/probe.ini'),$ini)
Write-Output 'No-order R7 probe prepared; no terminal launched.'
