"""Prepare actual MQL report parser tests without orders or production charts."""
import json
from pathlib import Path
import shutil
import orb_regime_leaderboard as c

ROOT=c.ROOT;DEST=ROOT/'.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbRegimeLbProbe'
FILES=ROOT/'.tmp/orb_jp225_full_worker/MQL5/Files/OrbRegimeLbProbe'


def build():
    DEST.mkdir(parents=True,exist_ok=True);FILES.mkdir(parents=True,exist_ok=True)
    for name in ('OrbStrategyMLCore.mqh','OrbStrategyR7Core.mqh','OrbStrategyModelSlot.mqh','OrbStrategyRegimeLeaderboard.mqh'):
        shutil.copyfile(ROOT/'IndicatorCodeExamples'/name,DEST/name)
    campaign=json.loads((c.OUT/'campaign.json').read_text());vectors=[]
    for r,f in zip(campaign['rows'],campaign['files']):
        shutil.copyfile(c.OUT/'Files/OrbML/RegimeLeaderboard'/f['name'],FILES/f['name'])
        for x in r['cells']:
            vectors.append(';'.join(map(str,[f['name'],r['id'],r['config'],r['dataset'],r['mode'],r['model_sha'],r['from_time'],r['to_time'],
                                            x['bucket'],x['n'],x['w'],x['l'],x['flat'],x['net_r'],x['dd_r'],x['min_cum_r'],x['score']])))
    (FILES/'vectors.txt').write_text('\n'.join(vectors)+'\n')
    (DEST/'OrbRegimeLbProbe.mq5').write_text(SOURCE)
    (c.OUT/'probe.ini').write_text('[Experts]\nEnabled=0\nAllowDllImport=0\n[StartUp]\nScript=OrbRegimeLbProbe\\OrbRegimeLbProbe\nSymbol=JP225m\nPeriod=M5\nShutdownTerminal=1\n')
    print('Regime no-order MQL probe prepared:',len(campaign['rows']),'reports,',len(vectors),'cells')


SOURCE=r'''#property strict
#include "OrbStrategyRegimeLeaderboard.mqh"
string Read(string name)
{
 int h=FileOpen("OrbRegimeLbProbe\\"+name,FILE_READ|FILE_BIN);if(h==INVALID_HANDLE)return "";
 int n=(int)FileSize(h);uchar b[];ArrayResize(b,n);FileReadArray(h,b);FileClose(h);return CharArrayToString(b,0,n,CP_UTF8);
}
void OnStart()
{
 if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
 string rows[];StringSplit(Read("vectors.txt"),'\n',rows);string current="";
 int reports=0,cells=0,negative=0,failed=0;double maxError=0;OrbRegimeLbReport r;ZeroMemory(r);
 for(int row=0;row<ArraySize(rows);row++)
 {
  if(rows[row]=="")continue;string a[];if(StringSplit(rows[row],';',a)!=17){failed++;continue;}
  if(current!=a[0])
  {
   current=a[0];reports++;string text=Read(current);
   datetime start=(datetime)StringToInteger(a[6]),stop=(datetime)StringToInteger(a[7]);
   if(!OrbRegimeLbParse(text,a[1],a[2],a[3],a[4],a[5],start,stop,r)){failed++;Print(current," PARSE");continue;}
   OrbRegimeLbReport bad;ZeroMemory(bad);
   negative++;if(OrbRegimeLbParse(text,a[1]+"wrong",a[2],a[3],a[4],a[5],start,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text,a[1],"bad",a[3],a[4],a[5],start,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text,a[1],a[2],"bad",a[4],a[5],start,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text,a[1],a[2],a[3],"bad",a[5],start,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text,a[1],a[2],a[3],a[4],"wrong-model",start,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text,a[1],a[2],a[3],a[4],a[5],start+1,stop,bad))failed++;
   negative++;if(OrbRegimeLbParse(text+"corrupt",a[1],a[2],a[3],a[4],a[5],start,stop,bad))failed++;
  }
  int bucket=(int)StringToInteger(a[8]);if(bucket< -1||bucket>6){failed++;continue;}
  OrbRegimeLbCell x=r.cells[bucket+1];cells++;
  if(x.n!=(int)StringToInteger(a[9])||x.w!=(int)StringToInteger(a[10])||x.l!=(int)StringToInteger(a[11])||x.flat!=(int)StringToInteger(a[12]))failed++;
  double delta=MathMax(MathAbs(x.netR-StringToDouble(a[13])),MathMax(MathAbs(x.dd-StringToDouble(a[14])),MathAbs(x.minCum-StringToDouble(a[15]))));
  delta=MathMax(delta,MathAbs(OrbRegimeLbScore(x.w,x.n,x.dd)-StringToDouble(a[16])));
  maxError=MathMax(maxError,delta);if(delta>1e-8)failed++;
 }
 string result=StringFormat("{\"reports\":%d,\"cells\":%d,\"negative\":%d,\"failed\":%d,\"max_error\":%.17g}",reports,cells,negative,failed,maxError);
 int h=FileOpen("OrbRegimeLbProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
 if(h!=INVALID_HANDLE){FileWriteString(h,result);FileClose(h);}Print("REGIME_LB_PROBE ",result);
}
'''

if __name__=='__main__':build()
