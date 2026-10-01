#ifndef AUDIT_TRADE_CSV_MQH
#define AUDIT_TRADE_CSV_MQH
// Read-only export of completed audit records. Never submits orders or runs an audit.
#define AX_EVENT 28831
struct AxTrade
{
   datetime signalTime,availableTime,entryTime,exitTime,localTime;
   int direction,rawDirection,regime,rf;
   bool valid,closed,won;
   double entry,sl,tp,exitPrice,netR,costR,plannedEntry,plannedSl,plannedTp;
   double regionHigh,regionLow,entrySpreadPoints;
   string outcome,reason,context,entryClock,signalFeatures,spreadBasis;
};
AxTrade g_axTrades[];
bool g_axReady=false,g_axBusy=false;
int g_axFile=INVALID_HANDLE,g_axIndex=0,g_axMissing=0;
int g_axMissingRolling=0,g_axMissingMtf=0,g_axMissingKiv=0;
string g_axPath="",g_axSettingsHead="",g_axSettingsRow="",g_axStrategy="",g_axEa="";
string g_axSignalMode="SIGNAL";
datetime g_axAsOf=0;
ENUM_TIMEFRAMES g_axTf=PERIOD_CURRENT;
int g_axHandles[],g_axBuffers[];
string g_axNames[];
ulong g_axGeneration=0,g_axUiAt=0;
bool g_axNotify=true;
bool g_axSchedule=true;
ulong g_axIndicatorsAt=0;
ulong g_axRetryAt=0;
uint g_axPrepareTimeoutMs=30000;
bool g_axHistoryPrepared=false;
datetime g_axEarliest=0,g_axLatest=0;

datetime AxEntryAt(datetime entryTime,datetime availableTime)
{return entryTime>0?entryTime:availableTime;}
string AxEntryClock(datetime entryTime,double spreadPoints)
{return entryTime<=0?"UNAVAILABLE":(spreadPoints!=EMPTY_VALUE?"AUDIT_FILL":"MODELED_BAR_TIME");}
string AxExitReason(bool valid,bool closed,string reason,string outcome)
{return valid&&closed&&StringLen(reason)==0?outcome:reason;}

string AxNumber(double value)
{return MathIsValidNumber(value)&&value!=EMPTY_VALUE?DoubleToString(value,12):"";}
string AxTime(datetime value)
{return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"";}
string AxQuote(string value)
{
   // Excel must not interpret user strategy names or text as formulas.
   if(StringLen(value)>0)
   {ushort first=StringGetCharacter(value,0);if(first=='='||first=='+'||first=='@'||first=='\t'||first=='\r')value="'"+value;}
   StringReplace(value,"\"","\"\"");return "\""+value+"\"";
}
void AxCell(string &row,string value)
{if(row!="")row+=",";row+=AxQuote(value);}
void AxSetting(string &head,string &row,string name,string value)
{AxCell(head,"setting_"+name);AxCell(row,value);}
bool AxWrite(string value)
{
   uchar bytes[];int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   return n>=0&&FileWriteArray(g_axFile,bytes,0,n)==(uint)n;
}
void AxStatus(string text)
{
   g_tcalCsvStatus=text;g_tcalUiDirty=true;
   if(ObjectFind(0,TCalId("CSV_RIGHT"))>=0)
   {
      ObjectSetString(0,TCalId("CSV_RIGHT"),OBJPROP_TEXT,g_axBusy?"CSV "+DoubleToString(g_tcalCsvProgress,0)+"%":"EXPORT AUDIT CSV");
      ObjectSetString(0,TCalId("CSV_RIGHT"),OBJPROP_TOOLTIP,TCalCsvDirectory()+"\n"+text);
   }
   if(g_tcalOpen&&(!g_axBusy||GetTickCount64()-g_axUiAt>=200))
   {g_axUiAt=GetTickCount64();TCalDraw();ChartRedraw(0);}
}
void AxRelease()
{
   for(int i=0;i<ArraySize(g_axHandles);i++)
   {
      bool released=false;for(int j=0;j<i;j++)if(g_axHandles[j]==g_axHandles[i])released=true;
      if(!released&&g_axHandles[i]!=INVALID_HANDLE)IndicatorRelease(g_axHandles[i]);
   }
   ArrayFree(g_axHandles);ArrayFree(g_axBuffers);ArrayFree(g_axNames);
}
void AxAbort(string reason)
{
   bool wasBusy=g_axBusy;g_axBusy=false;g_axGeneration++;g_axRetryAt=0;
   if(g_axFile!=INVALID_HANDLE){FileClose(g_axFile);g_axFile=INVALID_HANDLE;}
   if(wasBusy&&g_axPath!="")FileDelete(g_axPath+".partial",FILE_COMMON);
   if(wasBusy)g_tcalCsvProgress=0;
   AxRelease();if(wasBusy){AkExportReset();AxStatus(reason);}
}
void AxReset()
{
   AxAbort("CSV cancelled: audit changed");g_axReady=false;ArrayFree(g_axTrades);
}
void AxCapture(const AxTrade &record)
{
   int n=ArraySize(g_axTrades);if(ArrayResize(g_axTrades,n+1,512)==n+1)g_axTrades[n]=record;
}
void AxSeal(string ea,string strategy,ENUM_TIMEFRAMES tf,datetime asOf,string settingsHead,string settingsRow,string signalMode="SIGNAL")
{
   g_axEa=ea;g_axStrategy=strategy;g_axTf=tf;g_axAsOf=asOf;
   g_axSignalMode=signalMode;
   g_axSettingsHead=settingsHead;g_axSettingsRow=settingsRow;g_axReady=true;
}
string AxFilePart(string value,int limit)
{
   string out="";
   for(int i=0;i<StringLen(value)&&StringLen(out)<limit;i++)
   {
      ushort c=StringGetCharacter(value,i);
      out+=(c<=32||StringFind("<>:\"/\\|?*",ShortToString(c))>=0)?"_":ShortToString(c);
   }
   while(StringLen(out)>0&&StringGetCharacter(out,StringLen(out)-1)=='.')out=StringSubstr(out,0,StringLen(out)-1);
   return StringLen(out)>0?out:"CUSTOM";
}
string AxFileName()
{
   string suffix="_"+(string)(long)TimeLocal()+"_"+(string)ChartID()+"_"+(string)GetTickCount64()+".csv";
   string prefix=AxFilePart(g_axEa,16)+"_"+AxFilePart(_Symbol,16)+"_"+AxFilePart(EnumToString(g_axTf),12)
      +"_"+AxFilePart(g_axSignalMode,28)+"_";
   int room=240-StringLen(TCalCsvDirectory())-1-StringLen(prefix)-StringLen(suffix);
   return prefix+AxFilePart(g_axStrategy,MathMax(1,MathMin(48,room)))+suffix;
}
void AxIndicator(string name,int handle,int buffer=0)
{
   int n=ArraySize(g_axHandles);ArrayResize(g_axHandles,n+1);ArrayResize(g_axBuffers,n+1);ArrayResize(g_axNames,n+1);
   g_axNames[n]=name;g_axHandles[n]=handle;g_axBuffers[n]=buffer;
}
void AxIndicators()
{
   AxRelease();
   int periods[8]={5,9,20,27,50,100,200,250};
   for(int i=0;i<8;i++)
   {
      AxIndicator("ema_"+(string)periods[i],iMA(_Symbol,g_axTf,periods[i],0,MODE_EMA,PRICE_CLOSE));
      AxIndicator("sma_"+(string)periods[i],iMA(_Symbol,g_axTf,periods[i],0,MODE_SMA,PRICE_CLOSE));
   }
   AxIndicator("rsi_7",iRSI(_Symbol,g_axTf,7,PRICE_CLOSE));
   AxIndicator("rsi_14",iRSI(_Symbol,g_axTf,14,PRICE_CLOSE));
   AxIndicator("rsi_21",iRSI(_Symbol,g_axTf,21,PRICE_CLOSE));
   AxIndicator("atr_14",iATR(_Symbol,g_axTf,14));AxIndicator("atr_50",iATR(_Symbol,g_axTf,50));
   AxIndicator("adx_14",iADX(_Symbol,g_axTf,14));
   AxIndicator("di_plus_14",iADX(_Symbol,g_axTf,14),1);AxIndicator("di_minus_14",iADX(_Symbol,g_axTf,14),2);
   AxIndicator("macd_12_26",iMACD(_Symbol,g_axTf,12,26,9,PRICE_CLOSE));
   AxIndicator("macd_signal_9",iMACD(_Symbol,g_axTf,12,26,9,PRICE_CLOSE),1);
   AxIndicator("bb_mid_20",iBands(_Symbol,g_axTf,20,0,2.0,PRICE_CLOSE));
   AxIndicator("bb_upper_20",iBands(_Symbol,g_axTf,20,0,2.0,PRICE_CLOSE),1);
   AxIndicator("bb_lower_20",iBands(_Symbol,g_axTf,20,0,2.0,PRICE_CLOSE),2);
   AxIndicator("stochastic_k_5_3_3",iStochastic(_Symbol,g_axTf,5,3,3,MODE_SMA,STO_LOWHIGH));
   AxIndicator("stochastic_d_5_3_3",iStochastic(_Symbol,g_axTf,5,3,3,MODE_SMA,STO_LOWHIGH),1);
   AxIndicator("cci_20",iCCI(_Symbol,g_axTf,20,PRICE_TYPICAL));
   AxIndicator("williams_r_14",iWPR(_Symbol,g_axTf,14));
   AxIndicator("mfi_14_tick_volume",iMFI(_Symbol,g_axTf,14,VOLUME_TICK));
   AxIndicator("momentum_14",iMomentum(_Symbol,g_axTf,14,PRICE_CLOSE));
}
string AxIndicatorValue(int index,int shift)
{
   double value[];int h=g_axHandles[index];
   if(shift<1||h==INVALID_HANDLE||BarsCalculated(h)<=shift||CopyBuffer(h,g_axBuffers[index],shift,1,value)!=1)return "";
   return AxNumber(value[0]);
}
double AxWma(const MqlRates &rates[],int at,int length)
{
   if(length<1||at+length>ArraySize(rates))return EMPTY_VALUE;
   double sum=0;for(int i=0;i<length;i++)sum+=rates[at+i].close*(length-i);
   return sum/(length*(length+1)/2.0);
}
double AxHma(const MqlRates &rates[],int length)
{
   int root=(int)MathRound(MathSqrt(length)),half=length/2;
   if(ArraySize(rates)<length+root-1)return EMPTY_VALUE;
   double sum=0;for(int i=0;i<root;i++)sum+=(2*AxWma(rates,i,half)-AxWma(rates,i,length))*(root-i);
   return sum/(root*(root+1)/2.0);
}
string AxFeatureHeader()
{
   string h="feature_clock,feature_cutoff,feature_last_closed_bar,feature_status";
   for(int i=0;i<ArraySize(g_axNames);i++)h+=","+g_axNames[i];
   return h+",open,high,low,close,tick_volume,real_volume,bar_spread_points,body,range,upper_wick,lower_wick,body_range_ratio,close_location,return_1,return_5,return_20,return_50,volume_mean_20,volume_ratio_20,real_volume_mean_20,range_mean_20,volatility_20,efficiency_20,high_20,low_20,break_high_20,break_low_20,gap_from_previous_close,bullish_fvg_gap,bearish_fvg_gap,hull_20,hull_50,hull_200,ema_9_27_cross,ema_50_200_cross";
}
string AxFeatures(datetime cutoff)
{
   string row="";AxCell(row,"BROKER_SERVER_CLOSED_BAR");AxCell(row,AxTime(cutoff));
   int seconds=PeriodSeconds(g_axTf),shift=-1;MqlRates rates[];ArraySetAsSeries(rates,true);
   bool ready=seconds>0&&SeriesInfoInteger(_Symbol,g_axTf,SERIES_SYNCHRONIZED);
   if(ready)shift=iBarShift(_Symbol,g_axTf,cutoff-seconds,false);
   datetime last=shift>=1?iTime(_Symbol,g_axTf,shift):0;
   int copied=0;
   if(last>0&&last+seconds<=cutoff&&Bars(_Symbol,g_axTf)>shift+255)
      copied=CopyRates(_Symbol,g_axTf,shift,256,rates);
   bool ratesOk=copied==256&&rates[0].time==last&&last+seconds<=cutoff;
   string features="";bool complete=ratesOk;
   for(int i=0;i<ArraySize(g_axNames);i++)
   {
      string v=ratesOk?AxIndicatorValue(i,shift):"";if(v=="")complete=false;AxCell(features,v);
   }
   AxCell(row,AxTime(ratesOk?last:0));AxCell(row,complete?"OK":"DATA_MISSING");
   if(!complete)g_axMissing++;
   row+=","+features;
   if(!ratesOk){for(int i=0;i<35;i++)AxCell(row,"");return row;}
   MqlRates r=rates[0];double range=r.high-r.low,body=MathAbs(r.close-r.open);
   AxCell(row,AxNumber(r.open));AxCell(row,AxNumber(r.high));AxCell(row,AxNumber(r.low));AxCell(row,AxNumber(r.close));
   AxCell(row,(string)r.tick_volume);AxCell(row,(string)r.real_volume);AxCell(row,(string)r.spread);
   AxCell(row,AxNumber(body));AxCell(row,AxNumber(range));
   AxCell(row,AxNumber(r.high-MathMax(r.open,r.close)));AxCell(row,AxNumber(MathMin(r.open,r.close)-r.low));
   AxCell(row,range>0?AxNumber(body/range):"");AxCell(row,range>0?AxNumber((r.close-r.low)/range):"");
   int lag[4]={1,5,20,50};for(int i=0;i<4;i++)AxCell(row,rates[lag[i]].close>0?AxNumber(r.close/rates[lag[i]].close-1):"");
   double vol=0,realVol=0,ranges=0,mean=0,square=0,path=0,hi=rates[1].high,lo=rates[1].low;
   for(int i=1;i<=20;i++)
   {
      vol+=(double)rates[i].tick_volume;realVol+=(double)rates[i].real_volume;ranges+=rates[i].high-rates[i].low;
      hi=MathMax(hi,rates[i].high);lo=MathMin(lo,rates[i].low);
      double change=rates[i-1].close/rates[i].close-1;mean+=change;square+=change*change;
      path+=MathAbs(rates[i-1].close-rates[i].close);
   }
   AxCell(row,AxNumber(vol/20));AxCell(row,vol>0?AxNumber((double)r.tick_volume/(vol/20)):"");
   AxCell(row,AxNumber(realVol/20));AxCell(row,AxNumber(ranges/20));
   AxCell(row,AxNumber(MathSqrt(MathMax(0.0,square/20-MathPow(mean/20,2)))));
   AxCell(row,path>0?AxNumber(MathAbs(r.close-rates[20].close)/path):"0");
   AxCell(row,AxNumber(hi));AxCell(row,AxNumber(lo));AxCell(row,(string)(r.close>hi));AxCell(row,(string)(r.close<lo));
   AxCell(row,AxNumber(r.open-rates[1].close));AxCell(row,AxNumber(MathMax(0.0,r.low-rates[2].high)));
   AxCell(row,AxNumber(MathMax(0.0,rates[2].low-r.high)));
   AxCell(row,AxNumber(AxHma(rates,20)));AxCell(row,AxNumber(AxHma(rates,50)));AxCell(row,AxNumber(AxHma(rates,200)));
   int fast[2]={2,8},slow[2]={6,12};
   for(int i=0;i<2;i++)
   {
      string a=AxIndicatorValue(fast[i],shift),b=AxIndicatorValue(slow[i],shift);
      string pa=AxIndicatorValue(fast[i],shift+1),pb=AxIndicatorValue(slow[i],shift+1);
      AxCell(row,a==""||b==""||pa==""||pb==""?"":(string)
         (StringToDouble(a)>StringToDouble(b)&&StringToDouble(pa)<=StringToDouble(pb)?1:
          (StringToDouble(a)<StringToDouble(b)&&StringToDouble(pa)>=StringToDouble(pb)?-1:0)));
   }
   return row;
}
#include "AuditQuantFeatures.mqh"
#include "AuditKivancExport.mqh"
bool AxHistoryReady()
{
   if(ArraySize(g_axTrades)==0)return true;
   bool ready=true;MqlRates rates[];
   ENUM_TIMEFRAMES tfs[7]={g_axTf,PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H4,PERIOD_D1};
   for(int i=0;i<7;i++)
   {
      int count=i==0?256:21,seconds=PeriodSeconds(tfs[i]);
      if(!AxClosedRates(tfs[i],g_axEarliest,count,rates)||!AxClosedRates(tfs[i],g_axLatest,count,rates))
      {
         ready=false;
         // Request the missing range without changing the closed-bar cutoff.
         CopyRates(_Symbol,tfs[i],g_axEarliest-seconds,count+2,rates);
         CopyRates(_Symbol,tfs[i],g_axLatest-seconds,count+2,rates);
      }
   }
   int shift=iBarShift(_Symbol,g_axTf,g_axEarliest-PeriodSeconds(g_axTf),false);
   for(int i=0;i<ArraySize(g_axHandles);i++)
      if(g_axHandles[i]==INVALID_HANDLE||shift<1||BarsCalculated(g_axHandles[i])<=shift+1)ready=false;
   return ready;
}
void AxDefer(string message)
{
   g_axRetryAt=GetTickCount64()+250;AxStatus(message);
   // Production OnTimer resumes this wait. Do not flood the chart event queue.
}
string AxCoverageSummary()
{
   return "missing rows core="+(string)g_axMissing+" rolling="+(string)g_axMissingRolling
      +" MTF="+(string)g_axMissingMtf+" Kivanc="+(string)g_axMissingKiv;
}
string AxHeader()
{
   return "schema,ea,strategy,symbol,signal_tf,chart_tf,audit_asof,record_id,signal_bar,available_time,entry_time,entry_time_basis,label_exit_time,label_duration_seconds,label_duration_is_open_age,calendar_clock,entry_day,entry_hour,entry_hour_bucket,raw_direction,direction,data_valid,label_outcome,label_exit_reason,label_won,label_closed,entry_price,initial_sl,target_price,label_exit_price,label_net_r,label_cost_r_reported,planned_entry,planned_sl,planned_tp,region_high,region_low,regime,rf_rule,signal_context,entry_spread_points,entry_spread_basis,measured_slippage_points,slippage_measurement_status,"+AxFeatureHeader()+","+AxQuantHeader()+","+AxSignalFeatureHeader()+","+g_axSettingsHead+","+AkExportHeader();
}
string AxRow(int index)
{
   AxTrade t=g_axTrades[index];string row="";MqlDateTime dt;TimeToStruct(t.localTime,dt);
   AxCell(row,"AUDIT_TRADES_V1");AxCell(row,g_axEa);AxCell(row,g_axStrategy);AxCell(row,_Symbol);
   AxCell(row,EnumToString(g_axTf));AxCell(row,EnumToString((ENUM_TIMEFRAMES)_Period));AxCell(row,AxTime(g_axAsOf));
   AxCell(row,(string)(index+1));AxCell(row,AxTime(t.signalTime));AxCell(row,AxTime(t.availableTime));
   AxCell(row,AxTime(t.entryTime));AxCell(row,t.entryClock);AxCell(row,AxTime(t.exitTime));
   datetime end=t.closed?t.exitTime:g_axAsOf;
   AxCell(row,t.valid&&t.entryTime>0&&end>=t.entryTime?(string)(long)(end-t.entryTime):"");
   AxCell(row,(string)(!t.closed));AxCell(row,g_tcalClockLabel);AxCell(row,TCalDayName(dt.day_of_week));
   AxCell(row,(string)dt.hour);AxCell(row,TCalHourName(dt.hour));AxCell(row,(string)t.rawDirection);AxCell(row,(string)t.direction);
   AxCell(row,(string)t.valid);AxCell(row,t.valid?t.outcome:"DATA");AxCell(row,AxExitReason(t.valid,t.closed,t.reason,t.outcome));
   AxCell(row,t.valid&&t.closed?(string)t.won:"");AxCell(row,(string)t.closed);
   AxCell(row,t.valid?AxNumber(t.entry):"");AxCell(row,t.valid?AxNumber(t.sl):"");AxCell(row,t.valid?AxNumber(t.tp):"");
   AxCell(row,t.valid&&t.closed&&t.exitPrice>0?AxNumber(t.exitPrice):"");
   AxCell(row,t.valid?AxNumber(t.closed?t.netR:0):"");AxCell(row,t.valid?AxNumber(t.costR):"");
   AxCell(row,AxNumber(t.plannedEntry));AxCell(row,AxNumber(t.plannedSl));AxCell(row,AxNumber(t.plannedTp));
   AxCell(row,AxNumber(t.regionHigh));AxCell(row,AxNumber(t.regionLow));AxCell(row,(string)t.regime);AxCell(row,(string)t.rf);
   AxCell(row,t.context);AxCell(row,t.valid?AxNumber(t.entrySpreadPoints):"");AxCell(row,t.spreadBasis);
   AxCell(row,"");AxCell(row,"NOT_MEASURED_HISTORICAL_SIMULATION");
   datetime featureAt=t.entryTime>0?t.entryTime:t.availableTime;
   string signalFeatures=AxSignalFeatures(featureAt,t.signalTime,t.direction);
   string kivanc=AkExportRow(index);
   if(StringFind(kivanc,"\"SEEDED_LOCAL_HISTORY\"")!=0)g_axMissingKiv++;
   return row+","+AxFeatures(featureAt)+","+AxQuantRow(t)+","+signalFeatures+","+g_axSettingsRow+","+kivanc+"\r\n";
}
bool AxStart()
{
   if(g_axBusy)return false;
   if(!g_axReady){AxStatus("Complete an audit first");return false;}
   FolderCreate("AuditExports",FILE_COMMON);
   g_axPath="AuditExports\\"+AxFileName();
   g_axFile=FileOpen(g_axPath+".partial",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(g_axFile==INVALID_HANDLE){AxStatus("CSV file could not be opened");return false;}
   g_axBusy=true;g_axIndex=0;g_axMissing=0;g_axMissingRolling=0;g_axMissingMtf=0;g_axMissingKiv=0;
   g_axGeneration++;g_tcalCsvProgress=0;g_axRetryAt=0;g_axHistoryPrepared=false;
   g_axEarliest=0;g_axLatest=0;
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      datetime at=AxEntryAt(g_axTrades[i].entryTime,g_axTrades[i].availableTime);
      if(g_axEarliest==0||at<g_axEarliest)g_axEarliest=at;
      g_axLatest=MathMax(g_axLatest,at);
   }
   AxIndicators();g_axIndicatorsAt=GetTickCount64();AkExportReset();
   if(!AxWrite(AxHeader()+"\r\n")){AxAbort("CSV header write failed");return false;}
   AxStatus("CSV 0% | "+(string)ArraySize(g_axTrades)+" rows");
   if(g_axSchedule&&!EventChartCustom(0,AX_EVENT,(long)g_axGeneration,0,"")){AxAbort("CSV scheduling failed");return false;}return true;
}
void AxStep()
{
   if(!g_axBusy)return;ulong started=GetTickCount64();int count=ArraySize(g_axTrades);
   if(g_axRetryAt>started)return;
   g_axRetryAt=0;
   if(!g_axHistoryPrepared)
   {
      if(!AxHistoryReady()&&started-g_axIndicatorsAt<g_axPrepareTimeoutMs)
      {AxDefer("CSV: preparing closed-bar history and indicator buffers");return;}
      g_axHistoryPrepared=true;AkExportBegin();
   }
   if(g_akPreparing)
   {
      AkExportStep();
      if(g_akPreparing)
      {
         if(g_akWaiting){AxDefer("CSV: retrying missing history chunk");return;}
         int done=g_akProcessed;
         g_tcalCsvProgress=g_akTotal>0?MathMin(85.0,85.0*done/g_akTotal):0;
         AxStatus("CSV features: "+(string)done+"/"+(string)g_akTotal+" history bars");
         if(g_axSchedule&&!EventChartCustom(0,AX_EVENT,(long)g_axGeneration,0,""))AxAbort("CSV feature scheduling failed");
         return;
      }
   }
   while(g_axIndex<count&&GetTickCount64()-started<12)
   {
      if(!AxWrite(AxRow(g_axIndex))){AxAbort("CSV row write failed");return;}g_axIndex++;
   }
   if(g_axIndex<count)
   {
      g_tcalCsvProgress=85.0+15.0*g_axIndex/count;
      AxStatus("CSV "+(string)(g_axIndex*100/count)+"% | "+(string)g_axIndex+"/"+(string)count);
      if(g_axSchedule&&!EventChartCustom(0,AX_EVENT,(long)g_axGeneration,0,""))AxAbort("CSV scheduling failed; retry");
      return;
   }
   FileFlush(g_axFile);FileClose(g_axFile);g_axFile=INVALID_HANDLE;
   if(!FileMove(g_axPath+".partial",FILE_COMMON,g_axPath,FILE_COMMON)){AxAbort("CSV finalize failed");return;}
   g_axBusy=false;g_tcalCsvProgress=100;AxRelease();
   string path=TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+g_axPath;
   string coverage=AxCoverageSummary();
   AxStatus("CSV saved: "+(string)count+" rows | "+coverage);
   ObjectSetString(0,TCalId("MOD_CSV"),OBJPROP_TOOLTIP,path);
   Print("AUDIT CSV SAVED: ",path," | rows=",count," | ",coverage);
   if(g_axNotify)Alert("Audit CSV saved:\n",path,"\nRows: ",count," | ",coverage);
}
void AxTimer()
{if(g_axBusy&&g_axRetryAt>0&&GetTickCount64()>=g_axRetryAt)AxStep();}
bool AxEvent(int id,long generation)
{
   if(id!=CHARTEVENT_CUSTOM+AX_EVENT)return false;
   if(g_axBusy&&(ulong)generation==g_axGeneration)AxStep();return true;
}
#endif
