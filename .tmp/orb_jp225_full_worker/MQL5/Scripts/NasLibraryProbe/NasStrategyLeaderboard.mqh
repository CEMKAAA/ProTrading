#ifndef NAS_STRATEGY_LEADERBOARD_MQH
#define NAS_STRATEGY_LEADERBOARD_MQH
bool g_nasLeaderboard=false;
int g_nasLeaderboardMode=0,g_nasLeaderboardRegime=-1;
struct NasLeaderboardCell
{
   string id,symbol,config,mode;
   int regime,n,w,l,excluded;
   double net,dd,minCum,score;
};
NasLeaderboardCell g_nasLeaderboardCells[];

string NasLeaderboardModeName()
{
   return g_nasLeaderboardMode==0?"VANILLA":(g_nasLeaderboardMode==1?"LEGACY":"CANDIDATE");
}

bool NasLeaderboardLoad()
{
   ArrayFree(g_nasLeaderboardCells);string text,lines[];
   if(!NasLibraryRead("NasML\\leaderboard.txt",text))return false;
   int n=StringSplit(text,'\n',lines);
   if(n<4||lines[0]!="NAS_LB1"||lines[1]!="ELIGIBLE_CANDIDATE_MASK_NOT_EXECUTION_REPLAY"||lines[n-1]!="")return false;
   string body="";for(int i=0;i<n-2;i++)body+=lines[i]+"\n";
   if(NasMlSha256(body)!=lines[n-2])return false;
   NasLeaderboardCell temp[];
   for(int i=2;i<n-2;i++)
   {
      string a[];if(StringSplit(lines[i],'|',a)!=19)return false;
      double v[];ArrayResize(v,19);ArrayInitialize(v,0);
      for(int j=6;j<=16;j++)if(!NasMlNumber(a[j],v[j]))return false;
      if(v[6]<-1||v[6]>6||v[7]<0||v[8]<0||v[9]<0||v[8]+v[9]>v[7]||v[11]<0||v[13]<0||v[16]<0)return false;
      if(StringLen(a[4])!=64||StringLen(a[17])!=64||(a[18]!="-"&&StringLen(a[18])!=64))return false;
      if(a[5]!="VANILLA"&&a[5]!="LEGACY"&&a[5]!="CANDIDATE")return false;
      int k=ArraySize(temp);ArrayResize(temp,k+1);
      temp[k].id=a[0];temp[k].symbol=a[2];temp[k].config=a[4];temp[k].mode=a[5];temp[k].regime=(int)v[6];
      temp[k].n=(int)v[7];temp[k].w=(int)v[8];temp[k].l=(int)v[9];temp[k].net=v[10];temp[k].dd=v[11];
      temp[k].minCum=v[12];temp[k].score=v[13];temp[k].excluded=(int)v[16];
   }
   int count=ArraySize(temp);
   if(ArrayResize(g_nasLeaderboardCells,count)!=count)return false;
   for(int i=0;i<count;i++)g_nasLeaderboardCells[i]=temp[i];
   return true;
}

string NasLibraryCanonicalSettings(string settings)
{
   string a[];double n[];if(!NasLibraryParseSettings(settings,a,n))return "";
   string result="";
   for(int i=0;i<21;i++)
   {
      string value=a[i];
      if(i==2||i==3||i==4||i==5||i==8||i==16||i==20)value=DoubleToString(n[i],12);
      else if(i!=0&&i!=1&&i!=9)value=(string)(int)n[i];
      result+=(i>0?"|":"")+value;
   }
   return result;
}

int NasLeaderboardFind(int preset)
{
   NasLibraryPreset p=g_nasLibrary[preset];string settings=NasLibraryCanonicalSettings(p.settings);
   if(p.user&&p.profile!=NasLibraryInputProfile())return -1;
   for(int i=0;i<ArraySize(g_nasLeaderboardCells);i++)
   {
      NasLeaderboardCell c=g_nasLeaderboardCells[i];
      if(c.id!=p.id||c.mode!=NasLeaderboardModeName()||c.regime!=g_nasLeaderboardRegime)continue;
      string hash=NasMlSha256("nas-library-v1|"+p.id+"|"+c.symbol+"|"+(string)(p.tf*60)+"|"
         +AccountInfoString(ACCOUNT_SERVER)+"|"+NasLibraryInputProfile()+"|"+settings);
      if(hash==c.config)return i;
   }
   return -1;
}

string NasLeaderboardText(int preset)
{
   int i=NasLeaderboardFind(preset);if(i<0)return " | metrics N/A";
   NasLeaderboardCell c=g_nasLeaderboardCells[i];
   return " | "+DoubleToString(c.net,2)+"R WR "+(c.n>0?DoubleToString(100.0*c.w/c.n,1):"N/A")
      +"% DD "+DoubleToString(c.dd,2)+"R Min "+DoubleToString(c.minCum,2)+"R N="+(string)c.n
      +(c.excluded>0?" PARTIAL":"")+(c.n<30?" LOW N":"");
}

void NasLeaderboardSort()
{
   if(!g_nasLeaderboard)return;
   for(int i=1;i<ArraySize(g_nasLibraryVisible);i++)
   {
      int value=g_nasLibraryVisible[i],metric=NasLeaderboardFind(value);
      double score=metric>=0?g_nasLeaderboardCells[metric].score:-1;
      int j=i-1;
      while(j>=0)
      {
         int prior=NasLeaderboardFind(g_nasLibraryVisible[j]);
         double previous=prior>=0?g_nasLeaderboardCells[prior].score:-1;
         if(previous>=score)break;
         g_nasLibraryVisible[j+1]=g_nasLibraryVisible[j];j--;
      }
      g_nasLibraryVisible[j+1]=value;
   }
}
#endif
