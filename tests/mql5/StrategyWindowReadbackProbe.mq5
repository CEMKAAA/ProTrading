#property strict
#include "../../IndicatorCodeExamples/orb/StrategyWindowMetrics.mqh"
input string ReadbackManifest="MegaCampaignReadback.csv";
string ReadbackCell(int file)
{
   string value=FileReadString(file);int n=StringLen(value);
   if(n>=2&&StringGetCharacter(value,0)==34&&StringGetCharacter(value,n-1)==34)
   {value=StringSubstr(value,1,n-2);StringReplace(value,"\"\"","\"");}
   return value;
}
bool ReadbackMatches(const SwMetric &m,string &v[])
{
   return m.ready&&m.asOf==(datetime)StringToInteger(v[7])&&m.total==(int)StringToInteger(v[8])
      &&m.wins==(int)StringToInteger(v[9])&&m.losses==(int)StringToInteger(v[10])
      &&m.open==(int)StringToInteger(v[11])&&m.flat==(int)StringToInteger(v[12])
      &&MathAbs(m.netR-StringToDouble(v[13]))<1e-8&&MathAbs(m.minCum-StringToDouble(v[14]))<1e-8;
}
void OnStart()
{
   int f=FileOpen(ReadbackManifest,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(f==INVALID_HANDLE){Print("READBACK_MANIFEST_MISSING");return;}
   string v[];ArrayResize(v,16);
   for(int i=0;i<16;i++)ReadbackCell(f);
   int rows=0,checks=0,failed=0,current=0,baseline=0,unavailable=0;
   while(!FileIsEnding(f)&&!IsStopped())
   {
      for(int i=0;i<16;i++)v[i]=ReadbackCell(f);
      if(v[0]=="")continue;
      rows++;bool ready=v[6]=="1";int weeks=(int)StringToInteger(v[5]);SwMetric m;
      bool found=SwRead(v[2],v[3],v[4],weeks,m);checks++;
      if(found!=ready||(ready&&!ReadbackMatches(m,v)))
      {failed++;Print("READBACK_CURRENT_FAIL ",v[0]," ",weeks);}
      if(found)current++;
      g_swFrozen=true;g_swLegacyArchive=false;
      found=SwReadView(v[2],v[3],v[4],weeks,m);checks++;
      if(found!=ready||(ready&&(!ReadbackMatches(m,v)||m.snapshotIndependent!=(v[15]=="1"))))
      {failed++;Print("READBACK_BASELINE_FAIL ",v[0]," ",weeks);}
      if(found)baseline++;
      if(!ready)unavailable++;
   }
   FileClose(f);
   string report=StringFormat("{\"rows\":%d,\"checks\":%d,\"failed\":%d,\"current\":%d,\"baseline\":%d,\"unavailable\":%d,\"order_attempts\":0}",
      rows,checks,failed,current,baseline,unavailable);
   f=FileOpen("StrategyWindowReadbackProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}
   Print("READBACK_RESULT ",report);
}
