$ErrorActionPreference='Stop'
$root=Join-Path $PWD 'IndicatorCodeExamples'
$utf=New-Object Text.UTF8Encoding($false)
function WriteFile($p,$s){[IO.File]::WriteAllText($p,$s,$utf)}
foreach($name in @('OrbUltimateEA.mq5','OrbUltimateEA_Channel.mq5','OrbUltimateEA_StrategyLibrary.mq5')){
$p=Join-Path $root $name;$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('InpExchangeClockSeason','OrbClockExchangeSeason()')
$s=$s.Replace('#include "OrbUltimate_ProfessionalPipeline.mqh"','#include "OrbUltimate_ProfessionalPipeline.mqh"'+"`r`n"+'#include "OrbClockDashboard.mqh"')
$s=$s.Replace('g_orbStrategyTimezone=0; // Existing built-in strategies were researched on GMT0.','g_orbStrategyTimezone=0; OrbClockUseSaved(0,0,0,0); // Preserve built-in research defaults.')
$s=$s.Replace('   OrbUserDraw();','   OrbUserDraw(); OrbClockUiDraw();')
$s=$s.Replace('   if(OrbLbEvent(id,lparam,dparam,sparam))return;','   if(OrbClockUiEvent(id,sparam))return;'+"`r`n"+'   if(OrbLbEvent(id,lparam,dparam,sparam))return;')
$s=$s.Replace('void DeleteDash(){','void DeleteDash(){DeleteByPrefix(PREFIX+"TZUI_");')
$s=$s.Replace('   ORB_SESSION_PROFILE p=ResolveSessionProfile();'+"`r`n"+'   if(p==ORB_SESSION_MANUAL_NY)return NyLocalToServer', '   if(g_orbClockSession==1)return OrbUtcToServer(MakeDateTime(y,mo,d,minOfDay/60,minOfDay%60,0)-10800);'+"`r`n"+'   ORB_SESSION_PROFILE p=ResolveSessionProfile();'+"`r`n"+'   if(p==ORB_SESSION_MANUAL_NY)return NyLocalToServer')
$s=$s.Replace('   if(p==ORB_SESSION_MANUAL_NY)return ServerToNyLocal(s);','   if(g_orbClockSession==1)return OrbServerToUtc(s)+10800;'+"`r`n"+'   if(p==ORB_SESSION_MANUAL_NY)return ServerToNyLocal(s);')
$s=$s.Replace('   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY){sm=', '   if(g_orbClockSession==1){sm=600;em=615;tem=1080;return;}'+"`r`n"+'   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY){sm=')
$s=$s.Replace('return SessionProfileLabel(ResolveSessionProfile())+" "+StringFormat','return (g_orbClockSession==1&&!g_rtUtcMidnightSession?"BIST CASH TRT":SessionProfileLabel(ResolveSessionProfile()))+" "+StringFormat')
WriteFile $p $s
}
# Same-name saves retain slot and identity under the existing cross-terminal lock.
foreach($rel in @('OrbStrategyUserLibrary.mqh','macrossover_orb/OrbStrategyUserLibrary.mqh')){
$p=Join-Path $root $rel;$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('   OrbUserReload(true);'+"`r`n"+'   for(int i=0;i<OrbStrategyPresetCount();i++)','   OrbUserReload(true); int updateSlot=-1; string updateId="";'+"`r`n"+'   for(int i=0;i<OrbStrategyPresetCount();i++)')
$s=$s.Replace('if(a==b){g_userStrategyNote="Name already exists; choose another name";return false;}','if(a==b){if(!OrbUserPreset(other)){g_userStrategyNote="Built-in strategy is read-only; use a new name";return false;} updateSlot=OrbUserSlot(other.id);updateId=other.id;break;}')
$s=$s.Replace('   int saved=-1;','   if(updateSlot>=0)p.id=updateId;'+"`r`n"+'   int saved=-1;')
$s=$s.Replace('string path=OrbUserFile(slot);if(FileIsExist(path,FILE_COMMON))continue;','if(updateSlot>=0&&slot!=updateSlot)continue;'+"`r`n"+'      string path=OrbUserFile(slot);if(updateSlot<0&&FileIsExist(path,FILE_COMMON))continue;')
$s=$s.Replace('// No FILE_REWRITE: simultaneous charts cannot overwrite another record.','// Save lock serializes updates; replacement is committed only after complete temporary write.')
$s=$s.Replace('FileMove(temp,FILE_COMMON,path,FILE_COMMON)','FileMove(temp,FILE_COMMON,path,FILE_COMMON|(updateSlot>=0?FILE_REWRITE:0))')
WriteFile $p $s
}
