$path=Join-Path $PWD 'IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5'
$s=[IO.File]::ReadAllText($path)
$s=$s.Replace('#include "MaIndependentEntries.mqh"','#include "MaIndependentEntries.mqh"'+"`r`n"+'#include "MaExitPolicy.mqh"')
$start=$s.IndexOf('bool FindNewDayAcceptedReverseExit(');$end=$s.IndexOf('bool FindFilteredWindowExit(', $start)
$s=$s.Substring(0,$start)+@'
bool FindNewDayAcceptedReverseExit(const OrbWindowSignal &signals[],datetime afterTime,string tradeDirection,
                                    datetime limitTime,datetime &exitTime,string &exitDetail)
{
   exitTime=0;exitDetail="";
   if(!g_maReverseExit)return false;
   exitTime=MaKernelExitAt(g_maCrossAuditEvents,OrbSignalAvailableTime(afterTime),tradeDirection=="BUY"?1:-1,
      limitTime,g_maReverseWait,PeriodSeconds(g_rtSignalTf),g_rtInvertMode);
   if(exitTime>0)exitDetail="MA_REVERSE wait="+DurationMinutesText(g_maReverseWait);
   return exitTime>0;
}

'@+$s.Substring($end)
$start=$s.IndexOf('bool IsAcceptedNewDayReverseCandidate(');$end=$s.IndexOf('bool CloseAcceptedNewDayReverseLifecycle(', $start)
$s=$s.Substring(0,$start)+@'
bool IsAcceptedNewDayReverseCandidate(string execDir,datetime candidateAvailable,string &detail)
{
   // ORB's implicit reverse/re-entry path is disabled. MA manages exits separately.
   detail="MA: automatic ORB reverse disabled";return false;
}

'@+$s.Substring($end)
$s=$s.Replace('"NEW_DAY_REVERSE_EXIT"','"MA_REVERSE_EXIT"')
$s=$s.Replace('datetime nasSearchEnd=g_rtNasAdditionalExit?g_histRunNow:te;','datetime nasSearchEnd=g_histRunNow;')
$s=$s.Replace('datetime nasSearchEnd=g_rtNasAdditionalExit?TimeCurrent():g_btDays[di].tradeEnd;','datetime nasSearchEnd=TimeCurrent();')
$s=$s.Replace('MaObserveClosedSignal();TryOpenSignal();ManagePositions();ProcessNasOppositeExit();','MaObserveClosedSignal();if(!MaProcessExitManagement())TryOpenSignal();ManagePositions();')
$s=$s.Replace('g_maRestoringPreset=true;OrbStrategyPresetRestore();','MaExitLoad();g_maRestoringPreset=true;OrbStrategyPresetRestore();')
$s=$s.Replace('   RestoreNewDayReverseRetry();','   ClearNewDayReverseRetry("ma_orb_reverse_disabled");')
$s=$s.Replace('   key+="|g_rtFilterAtr="','   key+="|MAEXIT2="+(string)g_maReverseExit+","+(string)g_maReverseWait;'+"`r`n"+'   key+="|g_rtFilterAtr="')
$s=$s.Replace('   y=rootY+290;',@'
   CreateButton("BTN_MA_REV_EXIT",x+12,rootY+309,140,18,g_maReverseExit?"MA REV EXIT ON":"MA REV EXIT OFF",g_maReverseExit?C'30,150,95':C'80,80,80');
   CreateLabel("DASH_MA_REV_WAIT",x+160,rootY+313,"WAIT HH:MM",C'134,158,182',7);
   CreateEdit("EDIT_MA_REV_WAIT",x+245,rootY+309,60,18,DurationMinutesText(g_maReverseWait));
   CreateButton("BTN_MA_REV_APPLY",x+313,rootY+309,90,18,"APPLY EXIT",C'38,101,176');
   y=rootY+312;
'@)
$s=$s.Replace('   bool needRedraw=false;',@'
   if(sparam==PREFIX+"BTN_MA_REV_EXIT"||sparam==PREFIX+"BTN_MA_REV_APPLY")
   {
      int minutes=0;
      if(!ParseStrictDurationMinutes(ObjectGetString(0,PREFIX+"EDIT_MA_REV_WAIT",OBJPROP_TEXT),minutes))
         g_lastExecStatus="MA EXIT WAIT: HH:MM (00:00..99:59)";
      else
      {
         if(sparam==PREFIX+"BTN_MA_REV_EXIT")g_maReverseExit=!g_maReverseExit;
         g_maReverseWait=minutes;MaExitSave();
         CancelHistoricalAuditBuild();g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
         g_lastExecStatus=g_maReverseExit?"MA_REVERSE_EXIT_ON":"MA_REVERSE_EXIT_OFF";
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   bool needRedraw=false;
'@)
$s=$s.Replace('   ObjectSetString(0,PREFIX+"EDIT_MA_MAX",OBJPROP_TEXT,(string)g_maMaxConsecutive);','   ObjectSetString(0,PREFIX+"EDIT_MA_MAX",OBJPROP_TEXT,(string)g_maMaxConsecutive);'+"`r`n"+'   ObjectSetString(0,PREFIX+"EDIT_MA_REV_WAIT",OBJPROP_TEXT,DurationMinutesText(g_maReverseWait));')
[IO.File]::WriteAllText($path,$s,[Text.UTF8Encoding]::new($false))
$p=Join-Path $PWD 'IndicatorCodeExamples/macrossover_orb/MaIndependentEntries.mqh'
$s=[IO.File]::ReadAllText($p).Replace('||g_rtTimeExit||RuntimeNasExitEnabled()||g_rtFilteredWindowReverseExit','||g_rtTimeExit||g_rtFilteredWindowReverseExit').Replace('HCBE/TIME/NAS EXIT/WINDOW EXIT/ENTRY WAIT/FIXED REF','HCBE/TIME/WINDOW EXIT/ENTRY WAIT/FIXED REF')
[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))
