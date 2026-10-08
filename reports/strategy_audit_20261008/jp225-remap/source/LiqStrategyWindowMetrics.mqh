#ifndef LIQ_STRATEGY_WINDOW_METRICS_MQH
#define LIQ_STRATEGY_WINDOW_METRICS_MQH
string g_liqWindowAppliedFingerprint="";
string LiqWindowFolder(){return LiqLibraryFolder()+"\\WindowMetrics";}
string LiqWindowRuntimeFingerprint()
{
   double values[];int n=LiqLibraryCapture(values);string out=LiqLibraryInputContract()+TCalStrategyText()+LnNasPack(g_lnNas)+DoubleToString(g_customTargetR,12);
   for(int i=0;i<n;i++)out+="|"+DoubleToString(values[i],16);return SwHash(out);
}
string LiqWindowKey(string path)
{
   string text="";
   string name="";double values[];
   if(LiqImageRead(path,name,values)){
      text=path;for(int i=0;i<ArraySize(values);i++)text+="|"+DoubleToString(values[i],16);}
   else if(!LiqLibraryRead(path,text))return "";
   return SwHash(text+"|"+LiqLibraryInputContract());
}
bool LiqWindowIndependent(string path)
{
   string text="",v[];if(!LiqLibraryRead(path,text))return false;
   int n=StringSplit(text,'\n',v);if(n<7||v[0]=="LIQ_STRATEGY_V1")return false;
   int at=6+(int)StringToInteger(v[5]);LnNasPolicy p;LnNasDefaults(p);
   return at<n&&LnNasUnpack(v[at],p)&&p.independent;
}
string LiqWindowCaption(string path,string name)
{
   string mode=LiqWindowIndependent(path)?"IND":"LEG";SwMetric m;
   if(!SwRead(LiqWindowFolder(),path,LiqWindowKey(path),g_swWeeks,m))return name+" | "+SwWindow(g_swWeeks)+" N/A | "+mode;
   return name+" | "+SwWindow(g_swWeeks)+" N "+(string)m.total+" "+mode+" | WR "+DoubleToString(SwWr(m),1)+"% | "+DoubleToString(m.netR,2)+"R";
}
void LiqWindowAuditCompleted()
{
   if(g_liqLibrarySelected==""||g_liqWindowAppliedFingerprint==""||g_liqWindowAppliedFingerprint!=LiqWindowRuntimeFingerprint()||g_hist.invalid>0)return;
   datetime cutoff=TimeCurrent()-g_histWeeks*7*86400;
   if(SeriesInfoInteger(_Symbol,g_entryTf,SERIES_FIRSTDATE)<=0||SeriesInfoInteger(_Symbol,g_entryTf,SERIES_FIRSTDATE)>cutoff
      ||SeriesInfoInteger(_Symbol,g_htf,SERIES_FIRSTDATE)<=0||SeriesInfoInteger(_Symbol,g_htf,SERIES_FIRSTDATE)>cutoff
      ||SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE)<=0||SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE)>cutoff)return;
   SwWrite(LiqWindowFolder(),g_liqLibrarySelected,LiqWindowKey(g_liqLibrarySelected),g_histWeeks,g_hist.total,g_hist.wins,g_hist.losses,g_hist.open,0,g_hist.netR,g_directionMinCum,TimeCurrent());
}
void LiqWindowSort()
{
   SwMetric metrics[];int n=ArraySize(g_liqLibraryFiles);ArrayResize(metrics,n);
   for(int i=0;i<n;i++)SwRead(LiqWindowFolder(),g_liqLibraryFiles[i],LiqWindowKey(g_liqLibraryFiles[i]),g_swWeeks,metrics[i]);
   for(int i=1;i<n;i++)for(int j=i;j>0;j--)
   {if(SwCompare(metrics[j],metrics[j-1])>=0)break;SwMetric m=metrics[j];metrics[j]=metrics[j-1];metrics[j-1]=m;
    string text=g_liqLibraryFiles[j];g_liqLibraryFiles[j]=g_liqLibraryFiles[j-1];g_liqLibraryFiles[j-1]=text;
    text=g_liqLibraryNames[j];g_liqLibraryNames[j]=g_liqLibraryNames[j-1];g_liqLibraryNames[j-1]=text;}
}
void LiqWindowControls(int x,int y,int w,color bg)
{
   int cell=(w-24)/9;for(int i=0;i<9;i++)LiqLibraryWidget("SW_WINDOW_"+(string)i,OBJ_BUTTON,x+12+i*cell,y+98,cell-3,22,SwWindow(SwWeeks(i)),g_swWeeks==SwWeeks(i)?C'184,103,22':bg);
   cell=(w-24)/5;for(int i=0;i<5;i++)LiqLibraryWidget("SW_SORT_"+(string)i,OBJ_BUTTON,x+12+i*cell,y+124,cell-3,22,SwSortCaption(i),g_swDirection[i]==0?C'80,80,80':C'30,150,95');
}
#endif
