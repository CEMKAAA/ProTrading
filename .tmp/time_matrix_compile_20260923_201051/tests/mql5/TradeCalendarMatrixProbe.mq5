#property strict
#include "../../TradeCalendarMatrix.mqh"

void OnStart()
{
   int checks=0,failed=0;
   datetime monday=StringToTime("2026.09.21 13:15");
   datetime mondayNext=StringToTime("2026.09.21 14:15");
   datetime tuesday=StringToTime("2026.09.22 13:15");
   g_tcalDays=1<<1;g_tcalHours=1<<13;g_tcalEnabled=false;
   checks++;if(!TCalAllows(mondayNext))failed++;
   g_tcalEnabled=true;
   checks++;if(!TCalAllows(monday))failed++;
   checks++;if(TCalAllows(mondayNext))failed++;
   checks++;if(TCalAllows(tuesday))failed++;
   TCalReset();TCalRecord(monday,0.5);TCalRecord(monday,1.0);
   TCalRecord(monday,-1.0);TCalRecord(monday,0.0);
   checks++;if(g_tcalWins[1][13]!=2||g_tcalLosses[1][13]!=1)failed++;
   checks++;if(MathAbs(TCalWr(2,1)-66.6666667)>0.0001)failed++;
   checks++;if(TCalValidMasks(0,1)||TCalValidMasks(127,0)||!TCalValidMasks(127,16777215))failed++;
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("TradeCalendarMatrixProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
