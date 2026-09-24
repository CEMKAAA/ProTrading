#property strict
string probeFamily="LiqNarrativeSol_Advanced",probeSymbol="";
string LiqLibraryFamily(){return probeFamily;}
string LiqLibraryFolder(){return "probe/"+probeFamily+"/"+probeSymbol;}
string LiqLibraryHash(string value){return value;}
int LiqLibraryCapture(double &v[]){ArrayResize(v,41);return 41;}
#define _Symbol probeSymbol
#include "../../IndicatorCodeExamples/SolAdvanced/LiqImagePresets.mqh"
#undef _Symbol
int checks=0,failed=0;
void Check(bool ok){checks++;if(!ok){failed++;Print("FAIL check ",checks);}}
void OnStart()
{
   Check(ArraySize(g_liqImagePresets)==26);
   for(int i=9;i<ArraySize(g_liqImagePresets);i++)
   {
      LiqImagePreset p=g_liqImagePresets[i];
      probeSymbol=p.symbol;string name="";double v[];
      Check(LiqImageCompatible(i));
      Check(LiqImageRead(LiqImagePath(i),name,v));
      Check(name==p.name&&ArraySize(v)==41);
      Check(v[0]==p.htf&&v[1]==p.entry&&v[2]==5&&v[3]==p.target);
      Check(v[7]==1&&v[13]==1&&v[15]==p.duplicate&&v[16]==p.invert);
      Check(v[19]==1&&v[20]==p.pips&&v[21]==p.weeks&&v[22]==p.regimeFilter);
      for(int j=0;j<6;j++)Check(v[23+j]==(((p.macroBlockedMask&(1<<j))!=0)?0:1));
      for(int j=0;j<12;j++)Check(v[29+j]==(((p.rfAllowedMask&(1<<j))!=0)?0:1));
      probeSymbol="WRONG";Check(!LiqImageRead(LiqImagePath(i),name,v));
      probeSymbol=p.symbol;probeFamily="LiquidityNarrative_MT5_EA";
      Check(!LiqImageRead(LiqImagePath(i),name,v));
      probeFamily="LiqNarrativeSol_Advanced";
   }
   int f=FileOpen("LiqSolAdvancedImageCatalogProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE)
   {FileWriteString(f,"{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}");FileClose(f);}
}
