#ifndef STRATEGY_WINDOW_METRICS_MQH
#define STRATEGY_WINDOW_METRICS_MQH
struct SwMetric
{
   bool ready;int total,wins,losses,open,flat;double netR,minCum;datetime asOf;
};
int g_swWeeks=52,g_swSortCount=0;
int g_swOrder[5],g_swDirection[5];
int SwWeeks(int i){int values[]={2,5,10,20,52,104,156,208,260};return i>=0&&i<9?values[i]:0;}
string SwWindow(int weeks){return weeks<52?(string)weeks+"W":(string)(weeks/52)+"Y";}
bool SwValidWindow(int weeks){for(int i=0;i<9;i++)if(SwWeeks(i)==weeks)return true;return false;}
string SwHash(string value)
{
   uchar bytes[],key[],digest[];int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   ArrayResize(bytes,n);if(CryptEncode(CRYPT_HASH_SHA256,bytes,key,digest)<=0)return "";
   string out="";for(int i=0;i<ArraySize(digest);i++)out+=StringFormat("%02x",digest[i]);return out;
}
string SwPath(string folder,string id,int weeks){return folder+"\\"+SwHash(id)+"."+(string)weeks+".swm";}
bool SwRead(string folder,string id,string settings,int weeks,SwMetric &m)
{
   ZeroMemory(m);if(!SwValidWindow(weeks))return false;
   int f=FileOpen(SwPath(folder,id,weeks),FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
   if(f==INVALID_HANDLE)return false;
   int n=(int)FileSize(f);if(n<=0||n>8192){FileClose(f);return false;}
   uchar b[];ArrayResize(b,n);bool ok=FileReadArray(f,b)==(uint)n;FileClose(f);if(!ok)return false;
   string text=CharArrayToString(b,0,n,CP_UTF8);int pos=StringFind(text,"\nSHA256=");
   if(pos<0||StringSubstr(text,pos+8)!=SwHash(StringSubstr(text,0,pos)))return false;
   string v[];if(StringSplit(StringSubstr(text,0,pos),'\n',v)!=12||v[0]!="SW_METRICS_1"||v[1]!=id||v[2]!=settings||v[3]!=(string)weeks)return false;
   double nums[8];for(int i=0;i<8;i++)
   {nums[i]=StringToDouble(v[i+4]);if(!MathIsValidNumber(nums[i])||DoubleToString(nums[i],12)!=v[i+4])return false;}
   for(int i=0;i<6;i++)if(nums[i]<0||nums[i]!=MathFloor(nums[i])||(nums[i]>2147483647&&i>0))return false;
   if(nums[0]<=0||nums[2]+nums[3]+nums[4]+nums[5]>nums[1]||nums[7]>1e-8)return false;
   m.asOf=(datetime)nums[0];m.total=(int)nums[1];m.wins=(int)nums[2];m.losses=(int)nums[3];
   m.open=(int)nums[4];m.flat=(int)nums[5];m.netR=nums[6];m.minCum=nums[7];m.ready=true;return true;
}
bool SwWrite(string folder,string id,string settings,int weeks,int total,int wins,int losses,int open,int flat,double netR,double minCum,datetime asOf)
{
   if(!SwValidWindow(weeks)||asOf<=0||total<0||wins<0||losses<0||open<0||flat<0
      ||wins+losses+open+flat>total||!MathIsValidNumber(netR)||!MathIsValidNumber(minCum)||minCum>1e-8)return false;
   FolderCreate(folder,FILE_COMMON);string path=SwPath(folder,id,weeks);
   int lock=FileOpen(path+".lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);if(lock==INVALID_HANDLE)return false;
   string text="SW_METRICS_1\n"+id+"\n"+settings+"\n"+(string)weeks;
   double values[8];values[0]=(double)asOf;values[1]=total;values[2]=wins;values[3]=losses;values[4]=open;values[5]=flat;values[6]=netR;values[7]=minCum;
   for(int i=0;i<8;i++)text+="\n"+DoubleToString(values[i],12);
   text+="\nSHA256="+SwHash(text);string temp=path+"."+(string)ChartID()+".pending";
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN|FILE_COMMON);bool ok=false;
   if(f!=INVALID_HANDLE){uchar bytes[];int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
      ok=FileWriteArray(f,bytes,0,n)==(uint)n;FileFlush(f);FileClose(f);
      if(ok)ok=FileMove(temp,FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);if(!ok)FileDelete(temp,FILE_COMMON);}
   FileClose(lock);return ok;
}
double SwWr(const SwMetric &m){return m.wins+m.losses>0?100.0*m.wins/(m.wins+m.losses):0.0;}
string SwSortName(int key){string names[]={"WR","TRADES","WINS","NET R","MIN CUM"};return key>=0&&key<5?names[key]:"";}
void SwSortCycle(int key)
{
   if(key<0||key>=5)return;
   if(g_swDirection[key]==0){g_swDirection[key]=-1;g_swOrder[g_swSortCount++]=key;return;}
   if(g_swDirection[key]<0){g_swDirection[key]=1;return;}
   g_swDirection[key]=0;for(int i=0;i<g_swSortCount;i++)if(g_swOrder[i]==key)
   {for(int j=i;j<g_swSortCount-1;j++)g_swOrder[j]=g_swOrder[j+1];g_swSortCount--;break;}
}
string SwSortCaption(int key)
{
   string label=SwSortName(key);if(g_swDirection[key]==0)return label+" OFF";
   for(int i=0;i<g_swSortCount;i++)if(g_swOrder[i]==key)return (string)(i+1)+" "+label+(g_swDirection[key]<0?" v":" ^");return label;
}
int SwCompare(const SwMetric &a,const SwMetric &b)
{
   if(a.ready!=b.ready)return a.ready?-1:1;if(!a.ready||g_swSortCount==0)return 0;
   for(int i=0;i<g_swSortCount;i++)
   {
      int key=g_swOrder[i];double av=0,bv=0;
      if(key==0){int an=a.wins+a.losses,bn=b.wins+b.losses;
         if((an==0)!=(bn==0))return an>0?-1:1;
         av=(double)a.wins*bn;bv=(double)b.wins*an;}
      if(key==1){av=a.total;bv=b.total;}if(key==2){av=a.wins;bv=b.wins;}
      if(key==3){av=a.netR;bv=b.netR;}if(key==4){av=a.minCum;bv=b.minCum;}
      if(av<bv)return -g_swDirection[key];if(av>bv)return g_swDirection[key];
   }
   return 0;
}
#endif
