#ifndef ORB_REPLAY_MEMO_EPOCH_MQH
#define ORB_REPLAY_MEMO_EPOCH_MQH
// A new bar cannot change a completed historical fill. Retain completed replays
// across normal append-only M1 arrivals, but invalidate on backfill/reset/sync.
string ProbeOriginalEpoch()
{
   static string owner="";
   static long first=0,last=0,bars=0,synced=0,revision=0;
   string current=AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol;
   long f=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
   long l=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_LASTBAR_DATE);
   long b=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_BARS_COUNT);
   long s=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED);
   long appended=MathMax(0,(l-last)/60);
   if(current!=owner||f!=first||s!=synced||l<last||b<bars||b-bars>appended)revision++;
   owner=current;first=f;last=l;bars=b;synced=s;
   return current+"|"+(string)revision+"|"+(string)f+"|"+(string)s;
}
long g_probeEpochChanges=0;
string OrbReplayDataEpoch()
{
   static string previous="";string epoch=ProbeOriginalEpoch();
   if(epoch!=previous){g_probeEpochChanges++;Print("PROBE_EPOCH ",epoch);previous=epoch;}
   return epoch;
}
#endif
