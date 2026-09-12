#property strict
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
