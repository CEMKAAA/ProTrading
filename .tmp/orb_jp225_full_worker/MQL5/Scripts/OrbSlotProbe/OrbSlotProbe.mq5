#property strict
#include "OrbStrategyModelSlot.mqh"
string Read(string name)
{
 int h=FileOpen("OrbSlotProbe\\"+name,FILE_READ|FILE_BIN);if(h==INVALID_HANDLE)return "";
 int n=(int)FileSize(h);uchar b[];ArrayResize(b,n);FileReadArray(h,b);FileClose(h);return CharArrayToString(b,0,n,CP_UTF8);
}
void OnStart()
{
 if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
 string rows[];StringSplit(Read("vectors.txt"),'\n',rows);
 int tested=0,failed=0,packs=0,negative=0;double error=0;string current="",reason="";
 OrbSlotModel model;ZeroMemory(model);OrbSlotManifest manifest;ZeroMemory(manifest);
 for(int row=0;row<ArraySize(rows);row++)
 {
  if(rows[row]=="")continue;string a[];if(StringSplit(rows[row],';',a)!=43){failed++;continue;}
  if(current!=a[0])
  {
   current=a[0];packs++;
   string text=Read(current+".slot"),artifact=Read(current+".model");
   if(!OrbSlotParse(text,current,manifest,reason)||!OrbSlotModelParse(manifest,artifact,model,reason)){failed++;Print(current," ",reason);continue;}
   OrbSlotManifest bad;ZeroMemory(bad);OrbSlotModel badModel;ZeroMemory(badModel);
   negative++;if(OrbSlotParse(text,current+"wrong",bad,reason))failed++;
   negative++;if(OrbSlotParse(text+"corrupt",current,bad,reason))failed++;
   negative++;if(OrbSlotModelParse(manifest,artifact+"corrupt",badModel,reason))failed++;
   double x[];ArrayResize(x,40);ArrayInitialize(x,0);double score=0;
   negative++;if(OrbSlotScore(model,x,manifest.fromTime-1,score,reason))failed++;
   negative++;if(OrbSlotScore(model,x,manifest.untilTime,score,reason))failed++;
  }
  double x[];ArrayResize(x,40);for(int i=0;i<40;i++)x[i]=StringToDouble(a[i+3]);
  double actual=0,expected=StringToDouble(a[2]);
  if(!OrbSlotScore(model,x,(datetime)StringToInteger(a[1]),actual,reason)){failed++;continue;}
  double delta=MathAbs(actual-expected);error=MathMax(error,delta);
  double threshold=manifest.provider=="ORB_MLP1"?model.mlp.threshold:0;
  if(delta>1e-10||(actual>=threshold)!=(expected>=threshold))failed++;
  if((reason=="ALLOW")!=(expected>=threshold))failed++;
  tested++;
 }
 string bads[];StringSplit(Read("bad.txt"),'\n',bads);
 for(int i=0;i<ArraySize(bads);i++)if(bads[i]!="")
 {negative++;if(OrbSlotParse(Read(bads[i]),"probe_mlp",manifest,reason))failed++;}
 string result=StringFormat("{\"packs\":%d,\"vectors\":%d,\"negative\":%d,\"failed\":%d,\"max_error\":%.17g}",packs,tested,negative,failed,error);
 int o=FileOpen("OrbSlotProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
 if(o!=INVALID_HANDLE){FileWriteString(o,result);FileClose(o);}Print("SLOT_PROBE ",result);
}
