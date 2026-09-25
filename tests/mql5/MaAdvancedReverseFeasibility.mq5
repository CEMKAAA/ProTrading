#property strict

input string InpPairsFile="MaAdvancedReverseInput.csv";

struct PairRow
{
   datetime signalTime;
   datetime exitTime;
   bool sourceBuy;
   bool sourceWin;
   double sourceEntry;
   double sourceSl;
   double sourceTp;
   double inverseEntry;
};

bool ReadAuditRow(const int file,string &fields[])
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
   int inputFile=FileOpen(InpPairsFile,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(inputFile==INVALID_HANDLE){Print("PAIR_ERROR input missing ",InpPairsFile);return;}
   string fields[];
   if(!ReadAuditRow(inputFile,fields)){FileClose(inputFile);return;}
   PairRow rows[];
   int total=0;
   while(ReadAuditRow(inputFile,fields))
   {
      if(total>=904)break;
      if(total<452)
      {
         ArrayResize(rows,total+1);
         rows[total].signalTime=StringToTime(fields[8]);
         rows[total].exitTime=StringToTime(fields[23]);
         rows[total].sourceBuy=(fields[7]=="BUY");
         rows[total].sourceWin=(StringToDouble(fields[26])>0.0);
         rows[total].sourceEntry=StringToDouble(fields[16]);
         rows[total].sourceSl=StringToDouble(fields[17]);
         rows[total].sourceTp=StringToDouble(fields[18]);
      }
      else
      {
         int pair=total-452;
         if(pair<ArraySize(rows) && rows[pair].signalTime==StringToTime(fields[8]))
            rows[pair].inverseEntry=StringToDouble(fields[16]);
      }
      total++;
   }
   FileClose(inputFile);
   if(total!=904){Print("PAIR_ERROR rows=",total);return;}
   int output=FileOpen("MaAdvancedReverseFeasibility.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(output==INVALID_HANDLE){Print("PAIR_ERROR output");return;}
   FileWrite(output,"signal_time","source_outcome","exit_time","inverse_entry","inverse_exit_quote","inverse_pnl_price","paired_opposite","entry_quote_error","status");
   int assessed=0,opposite=0,same=0,missing=0,entryMismatch=0,outcomeMismatch=0,timeMismatch=0;
   for(int i=0;i<451;i++)
   {
      PairRow row=rows[i];
      if(row.inverseEntry<=0||row.exitTime<=row.signalTime){missing++;continue;}
      MqlTick ticks[];
      int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)(row.signalTime+60)*1000,(ulong)(row.exitTime+1)*1000-1);
      if(copied<=0){missing++;continue;}
      int first=-1;
      for(int j=0;j<copied;j++)
         if(ticks[j].bid>0.0&&ticks[j].ask>0.0){first=j;break;}
      if(first<0){missing++;continue;}
      double observedEntry=row.sourceBuy?ticks[first].ask:ticks[first].bid;
      double entryError=MathAbs(observedEntry-row.sourceEntry);
      if(entryError>_Point*2){entryMismatch++;continue;}
      int hit=-1;
      bool observedWin=false;
      for(int j=first;j<copied;j++)
      {
         if(ticks[j].bid<=0.0||ticks[j].ask<=0.0)continue;
         double sourceClose=row.sourceBuy?ticks[j].bid:ticks[j].ask;
         bool sourceTarget=row.sourceBuy?(sourceClose>=row.sourceTp):(sourceClose<=row.sourceTp);
         bool sourceStop=row.sourceBuy?(sourceClose<=row.sourceSl):(sourceClose>=row.sourceSl);
         if(sourceTarget||sourceStop){hit=j;observedWin=sourceTarget&&!sourceStop;break;}
      }
      if(hit<0){missing++;FileWrite(output,TimeToString(row.signalTime),row.sourceWin?"W":"L",TimeToString(row.exitTime),DoubleToString(row.inverseEntry,_Digits),"","",0,DoubleToString(entryError,_Digits),"NO_MATCHED_TICK");continue;}
      if(observedWin!=row.sourceWin){outcomeMismatch++;continue;}
      if((datetime)ticks[hit].time!=row.exitTime){timeMismatch++;continue;}
      double inverseClose=row.sourceBuy?ticks[hit].ask:ticks[hit].bid;
      double pnl=row.sourceBuy?(row.inverseEntry-inverseClose):(inverseClose-row.inverseEntry);
      bool isOpposite=row.sourceWin?(pnl<0.0):(pnl>0.0);
      assessed++;
      if(isOpposite)opposite++;else same++;
      FileWrite(output,TimeToString(row.signalTime),row.sourceWin?"W":"L",TimeToString(ticks[hit].time,TIME_DATE|TIME_SECONDS),DoubleToString(row.inverseEntry,_Digits),DoubleToString(inverseClose,_Digits),DoubleToString(pnl,_Digits),isOpposite?1:0,DoubleToString(entryError,_Digits),"TICK_MARKET_CLOSE");
   }
   FileWrite(output,"SUMMARY",assessed,opposite,same,missing,entryMismatch,outcomeMismatch,timeMismatch,assessed>0?DoubleToString(100.0*opposite/assessed,3):"NA");
   FileClose(output);
   Print("PAIR_SUMMARY assessed=",assessed," opposite=",opposite," same=",same," missing=",missing," entry_mismatch=",entryMismatch," outcome_mismatch=",outcomeMismatch," time_mismatch=",timeMismatch);
}
