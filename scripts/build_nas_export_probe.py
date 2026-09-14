"""Generate a no-order pilot/batch exporter using the actual NAS EA audit path."""
from pathlib import Path
import argparse
import re
import shutil

ROOT=Path(__file__).resolve().parents[1]
INC=ROOT/'IndicatorCodeExamples'
STAGE=ROOT/'.tmp/orb_jp225_full_worker/MQL5/Scripts/NasExportProbe'

def build(symbol='BTCUSDm',limit=1):
    if symbol not in ('BTCUSDm','US500m','USTECm'):raise ValueError('Unreviewed NAS symbol')
    if not 1<=limit<=19:raise ValueError('Invalid batch limit')
    STAGE.mkdir(parents=True,exist_ok=True);seen=set()
    def copy(name):
        if name in seen:return
        seen.add(name);p=INC/name;t=p.read_text(encoding='utf-8-sig');shutil.copy2(p,STAGE/name)
        for child in re.findall(r'^\s*#include\s+"([^"]+)"',t,re.M):copy(child)
    copy('NasUltimate_StrategyLibrary.mq5')
    code=r'''#property strict
#define OnInit NasExportOriginalInit
#define OnDeinit NasExportOriginalDeinit
#define OnTick NasExportOriginalTick
#define OnTimer NasExportOriginalTimer
#define OnChartEvent NasExportOriginalEvent
#define OnTradeTransaction NasExportOriginalTransaction
#include "NasUltimate_StrategyLibrary.mq5"
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0||_Symbol!="__SYMBOL__")return;
   if(InpNasLibraryAllowLive||InpNasBridgeEnabled)return;
   FolderCreate("NasExportProbe");
   int log=FileOpen("NasExportProbe\\__SYMBOL___results.jsonl",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(log==INVALID_HANDLE)return;
   int init=NasExportOriginalInit();EventKillTimer();
   if(init!=INIT_SUCCEEDED){FileWriteString(log,"{\"error\":\"initialization_failed\"}\n");FileClose(log);return;}
   g_historyRefreshPending=false;g_eaEnabledRuntime=false;g_nasBridgeEnabledRuntime=false;
   int done=0;
   for(int i=0;i<ArraySize(g_nasLibrary)&&done<__LIMIT__;i++)
   {
      if(g_nasLibrary[i].symbol!=NasLibrarySymbol(_Symbol))continue;
      // The campaign explicitly uses documented hidden-input defaults; no live
      // instance or user preset is altered by this in-memory provenance flag.
      g_nasLibrary[i].user=true;g_nasLibrary[i].profile=NasLibraryInputProfile();
      ulong started=GetTickCount64();
      if(!NasLibraryApply(i)||!NasResearchStart())
      {FileWriteString(log,"{\"id\":\""+g_nasLibrary[i].id+"\",\"error\":\"start_failed\"}\n");FileFlush(log);continue;}
      g_historyRefreshPending=false;EventKillTimer();DrawRecentSignalHistory();
      if(g_nasLibraryExport&&!g_nasResearchWriting)NasResearchAbort("History/capture did not complete: "+g_historyCoverageDetail);
      while(g_nasLibraryExport&&!IsStopped()&&GetTickCount64()-started<7200000)
      {
         if(FileIsExist("NasExportProbe\\STOP")){NasResearchAbort("Pilot cancelled by operator.");break;}
         NasResearchTick();Sleep(1);
      }
      if(g_nasLibraryExport)NasResearchAbort("Pilot interrupted/timeout.");
      string status=g_nasLibraryStatus;StringReplace(status,"\"","'");StringReplace(status,"\\","/");
      string result="{\"id\":\""+g_nasLibrary[i].id+"\",\"name\":\""+g_nasLibrary[i].name
         +"\",\"csv\":\""+g_nasResearchDataset+".csv\",\"rows\":"+(string)g_nasResearchRows
         +",\"eligible\":"+(string)g_nasResearchValid+",\"elapsed_ms\":"+(string)(GetTickCount64()-started)+",\"status\":\""+status+"\"}";
      FileWriteString(log,result+"\n");FileFlush(log);Print("NAS_EXPORT_PROBE ",result);done++;
      g_historyRefreshPending=false;
   }
   FileClose(log);EventKillTimer();ObjectsDeleteAll(0,PREFIX);ObjectsDeleteAll(0,NAS_LIB_PREFIX);
}
'''.replace('__SYMBOL__',symbol).replace('__LIMIT__',str(limit))
    (STAGE/'NasExportProbe.mq5').write_text(code,encoding='ascii')
    report=ROOT/'logs/NasStrategyLibrary_20260912'
    (report/'export.ini').write_text(f'[Experts]\nEnabled=0\nAllowDllImport=0\n[StartUp]\nScript=NasExportProbe\\NasExportProbe\nSymbol={symbol}\nPeriod=M5\nShutdownTerminal=1\n',encoding='ascii')
    print('Staged guarded NAS export probe:',symbol,limit)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--symbol',default='BTCUSDm');p.add_argument('--limit',type=int,default=1)
    a=p.parse_args();build(a.symbol,a.limit)
