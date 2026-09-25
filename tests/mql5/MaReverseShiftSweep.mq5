#property strict

struct SweepTrade
{
   datetime signalTime;
   datetime endTime;
   bool sourceBuy;
   bool sourceWin;
   bool recordedInverseWin;
   double sourceEntry;
   double sourceSl;
   double sourceTp;
   double inverseEntry;
};

bool ReadRow(const int file,string &fields[])
{
   ArrayResize(fields,31);
   for(int i=0;i<31;i++)
   {
      if(FileIsEnding(file))return false;
      fields[i]=FileReadString(file);
   }
   return true;
}

void OnStart()
{
   int inputFile=FileOpen("MaAdvancedReverseInput.csv",FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(inputFile==INVALID_HANDLE){Print("SWEEP input missing");return;}
   string f[];
   if(!ReadRow(inputFile,f)){FileClose(inputFile);return;}
   SweepTrade trades[];
   ArrayResize(trades,452);
   bool valid=true;
   for(int i=0;i<904;i++)
   {
      if(!ReadRow(inputFile,f)){valid=false;break;}
      int index=i%452;
      if(i<452)
      {
         trades[index].signalTime=StringToTime(f[8]);
         trades[index].endTime=StringToTime(f[9]);
         trades[index].sourceBuy=f[7]=="BUY";
         trades[index].sourceWin=StringToDouble(f[26])>0.0;
         trades[index].sourceEntry=StringToDouble(f[16]);
         trades[index].sourceSl=StringToDouble(f[17]);
         trades[index].sourceTp=StringToDouble(f[18]);
      }
      else
      {
         if(trades[index].signalTime!=StringToTime(f[8]))valid=false;
         trades[index].inverseEntry=StringToDouble(f[16]);
         trades[index].recordedInverseWin=StringToDouble(f[26])>0.0;
      }
   }
   FileClose(inputFile);
   if(!valid){Print("SWEEP paired input invalid");return;}

   double alpha[5]={0.0,0.25,0.5,0.75,1.0};
   int resolved[5]={0,0,0,0,0},opposite[5]={0,0,0,0,0};
   int win[5]={0,0,0,0,0},oldMismatch=0,missing=0;
   double netR[5]={0,0,0,0,0},meanWinR[5]={0,0,0,0,0};
   int halfResolved[2][5],halfOpposite[2][5];
   ArrayInitialize(halfResolved,0);ArrayInitialize(halfOpposite,0);
   for(int i=0;i<452;i++)
   {
      SweepTrade t=trades[i];
      if(t.endTime<=t.signalTime||t.inverseEntry<=0.0){missing++;continue;}
      MqlTick ticks[];
      ulong from=(ulong)(t.signalTime+60)*1000;
      ulong to=(ulong)(t.endTime+1)*1000-1;
      int n=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,from,to);
      if(n<=0){missing++;continue;}
      int state[5]={0,0,0,0,0};
      double payout[5];
      double shift=t.sourceEntry-t.inverseEntry;
      bool inverseBuy=!t.sourceBuy;
      double sl[5],tp[5];
      for(int k=0;k<5;k++)
      {
         sl[k]=t.sourceTp+alpha[k]*shift;
         tp[k]=t.sourceSl+alpha[k]*shift;
         payout[k]=MathAbs(tp[k]-t.inverseEntry)/MathAbs(sl[k]-t.inverseEntry);
      }
      for(int j=0;j<n;j++)
      {
         if(ticks[j].bid<=0.0||ticks[j].ask<=0.0)continue;
         double closePrice=inverseBuy?ticks[j].bid:ticks[j].ask;
         for(int k=0;k<5;k++)
         {
            if(state[k]!=0)continue;
            bool stop=inverseBuy?closePrice<=sl[k]:closePrice>=sl[k];
            bool target=inverseBuy?closePrice>=tp[k]:closePrice<=tp[k];
            if(stop)state[k]=-1;
            else if(target)state[k]=1;
         }
      }
      for(int k=0;k<5;k++)
      {
         if(state[k]==0)continue;
         resolved[k]++;
         halfResolved[i<226?0:1][k]++;
         if((state[k]>0)!=t.sourceWin){opposite[k]++;halfOpposite[i<226?0:1][k]++;}
         if(state[k]>0){win[k]++;netR[k]+=payout[k];meanWinR[k]+=payout[k];}
         else netR[k]-=1.0;
      }
      if(state[0]!=0&&((state[0]>0)!=t.recordedInverseWin))oldMismatch++;
   }
   int out=FileOpen("MaReverseShiftSweep.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"alpha","resolved","opposite","opposite_pct","wins","net_r","avg_win_r",
      "early_opposite","early_resolved","late_opposite","late_resolved","old_mismatch","missing");
   for(int k=0;k<5;k++)
      FileWrite(out,DoubleToString(alpha[k],2),resolved[k],opposite[k],
         resolved[k]>0?DoubleToString(100.0*opposite[k]/resolved[k],3):"NA",win[k],
         DoubleToString(netR[k],4),win[k]>0?DoubleToString(meanWinR[k]/win[k],4):"NA",
         halfOpposite[0][k],halfResolved[0][k],halfOpposite[1][k],halfResolved[1][k],oldMismatch,missing);
   FileClose(out);
   Print("SWEEP old_inverse_mismatch=",oldMismatch," missing=",missing);
}
