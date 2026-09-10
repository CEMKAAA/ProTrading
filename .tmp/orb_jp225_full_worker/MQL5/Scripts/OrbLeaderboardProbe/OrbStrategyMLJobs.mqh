#ifndef ORB_STRATEGY_ML_JOBS_MQH
#define ORB_STRATEGY_ML_JOBS_MQH
string g_mlBrowseConfig="",g_mlBrowsePreset="",g_mlDatasets[],g_mlJobs[];
int g_mlDatasetChoice=-1,g_mlJobChoice=-1;
ulong g_mlBrowseLast=0,g_mlJobPaint=0;
bool g_mlJobTimer=false;
string g_mlJobNote="Local training service",g_mlPublishJob="";

bool OrbMlReadLines(const string path,string &lines[],int fields,bool checksum)
{
   int file=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file==INVALID_HANDLE)return false;
   ulong size=FileSize(file);uchar bytes[];
   if(size==0||size>8192){FileClose(file);return false;}
   ArrayResize(bytes,(int)size);uint got=FileReadArray(file,bytes,0,(int)size);FileClose(file);
   if(got!=size)return false;
   string text=CharArrayToString(bytes,0,(int)size,CP_UTF8);
   int count=StringSplit(text,'\n',lines);
   if(count!=fields+1||lines[fields]!="")return false;
   if(checksum)
   {
      string payload="";for(int i=0;i<fields-1;i++)payload+=lines[i]+"\n";
      if(OrbMlSha256(payload)!=lines[fields-1])return false;
   }
   return true;
}

bool OrbMlSafeId(const string value)
{
   if(StringLen(value)<1||StringLen(value)>240)return false;
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'))return false;
   }
   return true;
}

string OrbMlSelectedDataset()
{return g_mlDatasetChoice>=0&&g_mlDatasetChoice<ArraySize(g_mlDatasets)?g_mlDatasets[g_mlDatasetChoice]:"";}
string OrbMlSelectedJob()
{return g_mlJobChoice>=0&&g_mlJobChoice<ArraySize(g_mlJobs)?g_mlJobs[g_mlJobChoice]:"";}

bool OrbMlJobStatus(const string job,string &lines[])
{
   if(!OrbMlSafeId(job)||!OrbMlReadLines("OrbML\\Jobs\\"+job+".status",lines,11,true))return false;
   double pct=0,updated=0;
   return lines[0]=="ORB_ML_STATUS1"&&lines[1]==job&&lines[2]==g_mlBrowseConfig
      &&lines[3]==OrbMlSelectedDataset()&&OrbMlNumber(lines[6],pct)&&pct>=0&&pct<=100
      &&OrbMlNumber(lines[7],updated)&&updated>0;
}

bool OrbMlWorkerOnline()
{
   int file=FileOpen("OrbML\\worker.heartbeat",FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file==INVALID_HANDLE)return false;
   ulong size=FileSize(file);if(size<1||size>20){FileClose(file);return false;}
   uchar bytes[];ArrayResize(bytes,(int)size);uint got=FileReadArray(file,bytes,0,(int)size);FileClose(file);
   if(got!=size)return false;
   string value=CharArrayToString(bytes,0,(int)size,CP_UTF8);double stamp=0;
   if(!OrbMlNumber(value,stamp))return false;
   double age=(double)TimeGMT()-stamp;return age>=-5&&age<=30;
}

void OrbMlRefreshFiles(bool force=false)
{
   if(!force&&GetTickCount64()-g_mlBrowseLast<2000)return;
   g_mlBrowseLast=GetTickCount64();
   OrbStrategyPreset p;string config=OrbMlConfiguration();
   if(config!=g_mlBrowseConfig)
   {
      g_mlBrowseConfig=config;g_mlDatasetChoice=-1;g_mlJobChoice=-1;g_mlPublishJob="";
      ArrayResize(g_mlDatasets,0);ArrayResize(g_mlJobs,0);
      g_mlJobNote="Selection changed: only exact strategy/config files are shown";
   }
   if(config==""||!OrbStrategyPresetLoad(g_strategyPresetIndex,p))return;
   g_mlBrowsePreset=p.id;
   string previous=OrbMlSelectedDataset(),previousJob=OrbMlSelectedJob();
   ArrayResize(g_mlDatasets,0);g_mlDatasetChoice=-1;
   string name="";string prefix=p.id+"_"+StringSubstr(config,0,12)+"_";
   long search=FileFindFirst("OrbML\\Datasets\\"+prefix+"*.csv.complete",name,FILE_COMMON);
   if(search!=INVALID_HANDLE)
   {
      do
      {
         string marker[];
         if(!OrbMlReadLines("OrbML\\Datasets\\"+name,marker,4,false))continue;
         if(marker[0]!=config||!OrbMlSafeId(marker[2])||name!=marker[2]+".csv.complete")continue;
         if(StringFind(marker[2],prefix)!=0)continue;
         if(!FileIsExist("OrbML\\Datasets\\"+marker[2]+".csv",FILE_COMMON))continue;
         int n=ArraySize(g_mlDatasets);ArrayResize(g_mlDatasets,n+1);g_mlDatasets[n]=marker[2];
      }while(FileFindNext(search,name));
      FileFindClose(search);
   }
   for(int i=0;i<ArraySize(g_mlDatasets);i++)
   {
      if(g_mlDatasets[i]==previous){g_mlDatasetChoice=i;break;}
      if(g_mlDatasetChoice<0||StringCompare(g_mlDatasets[i],g_mlDatasets[g_mlDatasetChoice])>0)g_mlDatasetChoice=i;
   }
   ArrayResize(g_mlJobs,0);g_mlJobChoice=-1;
   if(OrbMlSelectedDataset()=="")return;
   search=FileFindFirst("OrbML\\Jobs\\"+StringSubstr(config,0,12)+"_*.status",name,FILE_COMMON);
   if(search!=INVALID_HANDLE)
   {
      do
      {
         string job=StringSubstr(name,0,StringLen(name)-7),status[];
         if(!OrbMlJobStatus(job,status)||status[4]!="TRAIN")continue;
         int n=ArraySize(g_mlJobs);ArrayResize(g_mlJobs,n+1);g_mlJobs[n]=job;
      }while(FileFindNext(search,name));
      FileFindClose(search);
   }
   for(int i=0;i<ArraySize(g_mlJobs);i++)
   {
      if(g_mlJobs[i]==previousJob){g_mlJobChoice=i;break;}
      if(g_mlJobChoice<0||StringCompare(g_mlJobs[i],g_mlJobs[g_mlJobChoice])>0)g_mlJobChoice=i;
   }
}

bool OrbMlAtomicProtocol(const string path,const string payload)
{
   int file=FileOpen(path+".tmp",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(file==INVALID_HANDLE)return false;
   bool ok=OrbMlWriteUtf8(file,payload+OrbMlSha256(payload)+"\n");FileFlush(file);FileClose(file);
   return ok&&FileMove(path+".tmp",FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
}

bool OrbMlSubmitJob(const string action,const string reference="")
{
   OrbMlRefreshFiles(true);
   string dataset=OrbMlSelectedDataset(),config=OrbMlConfiguration();
   if(dataset==""||config==""||config!=g_mlBrowseConfig){g_mlJobNote="Select a completed CSV first";return false;}
   if(!OrbMlWorkerOnline()){g_mlJobNote="SERVICE OFFLINE: install/restart ORB Strategy ML Worker";return false;}
   if(action=="TRAIN")
      for(int i=0;i<ArraySize(g_mlJobs);i++)
      {string s[];if(OrbMlJobStatus(g_mlJobs[i],s)&&(s[5]=="QUEUED"||s[5]=="RUNNING"))
         {g_mlJobNote="This CSV already has a queued/running job";return false;}}
   if(action=="PUBLISH")
   {
      string s[];
      if(!OrbMlJobStatus(reference,s)||s[5]!="READY"){g_mlJobNote="Select an eligible READY training result";return false;}
      if(OrbStrategyPresetHasActiveLifecycle()||g_nasPending||g_retestPending||g_imbPending||g_newDayReverseRetryPending)
      {g_mlJobNote="WAIT: ACTIVE/PENDING TRADE";return false;}
   }
   string job=StringSubstr(config,0,12)+"_"+(string)(long)TimeGMT()+"_"+(string)GetTickCount64()+"_"+(string)ChartID();
   string payload="ORB_ML_JOB1\n"+action+"\n"+job+"\n"+config+"\n"+dataset+"\n"+g_mlBrowsePreset+"\n"+reference+"\n"+(string)(long)TimeGMT()+"\n";
   string status="ORB_ML_STATUS1\n"+job+"\n"+config+"\n"+dataset+"\n"+action+"\nQUEUED\n0\n"+(string)(long)TimeGMT()+"\nQueued by dashboard\n"+reference+"\n";
   if(!OrbMlAtomicProtocol("OrbML\\Jobs\\"+job+".status",status))
   {g_mlJobNote="JOB WRITE FAILED";return false;}
   if(!OrbMlAtomicProtocol("OrbML\\Jobs\\"+job+".request",payload))
   {
      StringReplace(status,"\nQUEUED\n","\nFAILED\n");
      OrbMlAtomicProtocol("OrbML\\Jobs\\"+job+".status",status);
      g_mlJobNote="JOB REQUEST WRITE FAILED";return false;
   }
   g_mlJobNote=action+" queued; no automatic model activation";
   if(action=="PUBLISH")g_mlPublishJob=job;
   OrbMlRefreshFiles(true);
   for(int i=0;i<ArraySize(g_mlJobs);i++)if(g_mlJobs[i]==job)g_mlJobChoice=i;
   return true;
}

bool OrbMlJobUiEvent(const string object)
{
   g_mlJobPaint=0;
   if(object==PREFIX+"BTN_ML_REFRESH"){OrbMlRefreshFiles(true);return true;}
   if(object==PREFIX+"BTN_ML_DATA_PREV"||object==PREFIX+"BTN_ML_DATA_NEXT")
   {
      OrbMlRefreshFiles(true);int n=ArraySize(g_mlDatasets);
      if(n>0)g_mlDatasetChoice=(g_mlDatasetChoice+n+(object==PREFIX+"BTN_ML_DATA_NEXT"?1:-1))%n;
      g_mlJobChoice=-1;ArrayResize(g_mlJobs,0);g_mlPublishJob="";OrbMlRefreshFiles(true);return true;
   }
   if(object==PREFIX+"BTN_ML_JOB_PREV"||object==PREFIX+"BTN_ML_JOB_NEXT")
   {
      OrbMlRefreshFiles(true);int n=ArraySize(g_mlJobs);
      if(n>0)g_mlJobChoice=(g_mlJobChoice+n+(object==PREFIX+"BTN_ML_JOB_NEXT"?1:-1))%n;
      return true;
   }
   if(object==PREFIX+"BTN_ML_TRAIN"){OrbMlSubmitJob("TRAIN");return true;}
   if(object==PREFIX+"BTN_ML_USE"){OrbMlSubmitJob("PUBLISH",OrbMlSelectedJob());return true;}
   if(object==PREFIX+"BTN_ML_CANCEL_JOB")
   {
      string job=OrbMlSelectedJob(),s[];
      if(OrbMlJobStatus(job,s)&&(s[5]=="QUEUED"||s[5]=="RUNNING"))
      {
         int f=FileOpen("OrbML\\Jobs\\"+job+".cancel",FILE_WRITE|FILE_BIN|FILE_COMMON);
         if(f==INVALID_HANDLE)g_mlJobNote="CANCEL WRITE FAILED";
         else {FileClose(f);g_mlJobNote="Cancellation requested; active model unchanged";}
      }
      return true;
   }
   return false;
}

void OrbMlDrawJobs(int x,int y)
{
   if(GetTickCount64()-g_mlJobPaint<500)return;
   g_mlJobPaint=GetTickCount64();
   OrbMlRefreshFiles();
   CreateButton("BTN_ML_DATA_PREV",x,y,26,20,"<",C'55,68,88');
   CreateButton("BTN_ML_DATA_NEXT",x+30,y,26,20,">",C'55,68,88');
   CreateButton("BTN_ML_REFRESH",x+505,y,87,20,"REFRESH",C'55,68,88');
   string dataset=OrbMlSelectedDataset();
   string label=dataset==""?"CSV: none for this exact strategy/config":"CSV "+(string)(g_mlDatasetChoice+1)+"/"+(string)ArraySize(g_mlDatasets)+" "+StringSubstr(dataset,StringLen(g_mlBrowsePreset)+14,30);
   CreateLabel("DASH_ML_DATA",x+64,y+4,label,C'184,196,210',8);
   CreateButton("BTN_ML_JOB_PREV",x,y+25,26,20,"<",C'55,68,88');
   CreateButton("BTN_ML_JOB_NEXT",x+30,y+25,26,20,">",C'55,68,88');
   string status[],job=OrbMlSelectedJob();bool found=OrbMlJobStatus(job,status);
   string state=found?status[5]:"NO TRAINING RUN";
   CreateLabel("DASH_ML_JOB",x+64,y+29,"RUN "+(string)(g_mlJobChoice+1)+"/"+(string)ArraySize(g_mlJobs)+" "+state,C'184,196,210',8);
   bool online=OrbMlWorkerOnline();
   CreateLabel("DASH_ML_WORKER",x+410,y+29,online?"WORKER ONLINE":"WORKER OFFLINE",online?clrLightGreen:clrOrange,8);
   CreateButton("BTN_ML_TRAIN",x,y+51,184,22,"TRAIN MODEL",C'38,101,176');
   CreateButton("BTN_ML_CANCEL_JOB",x+194,y+51,184,22,"CANCEL TRAIN",C'80,80,80');
   CreateButton("BTN_ML_USE",x+388,y+51,204,22,"USE RESULT",C'38,101,176');
   double pct=found?StringToDouble(status[6]):0;
   CreateRect("DASH_ML_JOB_TRACK",x,y+80,592,8,C'38,46,60',C'38,46,60');
   CreateRect("DASH_ML_JOB_FILL",x,y+80,(int)(592*pct/100),8,C'110,205,146',C'110,205,146');
   string message=found?status[8]:"Select CSV, then TRAIN MODEL. Training does not enable the filter.";
   CreateLabel("DASH_ML_JOB_DETAIL",x,y+95,StringSubstr(message,0,108),C'184,196,210',7);
   if(g_mlPublishJob!="")
   {string publish[];if(OrbMlJobStatus(g_mlPublishJob,publish))g_mlJobNote=publish[5]+": "+publish[8];}
   CreateLabel("DASH_ML_JOB_NOTE",x,y+112,StringSubstr(g_mlJobNote,0,108),C'255,187,92',7);
   bool pending=found&&(state=="RUNNING"||state=="QUEUED");
   if(g_mlPublishJob!="")
   {string s[];if(OrbMlJobStatus(g_mlPublishJob,s))pending=pending||s[5]=="QUEUED"||s[5]=="RUNNING";}
   if(!IsTesterMode()&&!g_histAuditRunning&&!g_histRedrawQueued&&!g_mlExport&&!g_btRunning)
   {
      if(pending){EventSetMillisecondTimer(250);g_mlJobTimer=true;}
      else if(g_mlJobTimer){EventSetTimer(5);g_mlJobTimer=false;}
   }
}
#endif
