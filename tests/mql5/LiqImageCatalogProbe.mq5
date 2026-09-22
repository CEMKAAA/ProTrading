#property strict
string probeFamily="",probeSymbol="";
string LiqLibraryFamily(){return probeFamily;}
string LiqLibraryFolder(){return "probe/"+probeFamily+"/"+probeSymbol;}
string LiqLibraryHash(string text){return text;}
int LiqLibraryCapture(double &v[]){int n=StringFind(probeFamily,"Advanced")>=0?41:22;ArrayResize(v,n);return n;}
#define _Symbol probeSymbol
#include "../../IndicatorCodeExamples/LiqImagePresets.mqh"
#undef _Symbol
int checks=0,failed=0;
void Check(bool ok){checks++;if(!ok){failed++;Print("FAIL check ",checks);}}
void OnStart()
{
   int htf[]={16386,16386,16386,16386,16385,16385,16388,16386,90};
   int tf[]={15,15,15,15,16385,16385,16385,16385,15};
   int tp[]={2,1,1,3,2,2,1,2,3};
   int pip[]={20000,30000,3000,600,2000,3000,30000,20000,4000};
   int dup[]={1,1,1,1,0,0,1,1,1};
   int weeks[]={2,2,20,2,10,2,2,2,10};
   Check(ArraySize(g_liqImagePresets)==9);
   for(int i=0;i<9;i++)for(int channel=0;channel<2;channel++)
   {
      probeFamily=g_liqImagePresets[i].family+(channel==1?"_Channel":"");
      probeSymbol=g_liqImagePresets[i].symbol;string name="";double v[];
      Check(LiqImageRead(LiqImagePath(i),name,v));Check(name==g_liqImagePresets[i].name);
      Check(v[0]==htf[i]&&v[1]==tf[i]&&v[2]==5&&v[3]==tp[i]);
      Check(v[4]==0&&v[5]==0&&v[6]==0&&v[7]==1&&v[8]==0);
      Check(v[9]==0&&v[10]==0&&v[11]==0&&v[12]==0&&v[13]==1&&v[14]==0);
      Check(v[15]==dup[i]&&v[16]==(i==3?1:0));
      Check(v[17]==100&&v[18]==10&&v[19]==1&&v[20]==pip[i]&&v[21]==weeks[i]);
      if(ArraySize(v)==41){Check(v[22]==0);for(int j=23;j<41;j++)Check(v[j]==1);}
      probeSymbol="WRONG";Check(!LiqImageRead(LiqImagePath(i),name,v));
      probeSymbol=g_liqImagePresets[i].symbol;probeFamily="LiqNarrativeSolVersion";
      Check(!LiqImageRead(LiqImagePath(i),name,v));
   }
   int f=FileOpen("LiqImageCatalogProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}");FileClose(f);}
}
