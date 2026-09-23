#ifndef LIQ_NARRATIVE_MACRO_REGIME_MQH
#define LIQ_NARRATIVE_MACRO_REGIME_MQH

input group "JP225 Macro Regime Filter"
input bool InpMacroRegimeTrendLowVolAllowed       = true;
input bool InpMacroRegimeTrendHighVolAllowed      = true;
input bool InpMacroRegimeRangeLowVolAllowed       = true;
input bool InpMacroRegimeRangeHighVolAllowed      = true;
input bool InpMacroRegimeTransitionPendingAllowed = true;
input bool InpMacroRegimeTransitionFreshAllowed   = true;

#define LIQ_MACRO_REGIME_COUNT 6
bool g_macroRegimeAllowed[LIQ_MACRO_REGIME_COUNT];
int  g_macroRegimeWins[LIQ_MACRO_REGIME_COUNT];
int  g_macroRegimeLosses[LIQ_MACRO_REGIME_COUNT];
int  g_macroRegimeRejected = 0;
int  g_macroRegimeUnclassified = 0;

string LiqMacroRegimeName(int bucket)
{
   if(bucket == 0) return "TREND LOW VOL";
   if(bucket == 1) return "TREND HIGH VOL";
   if(bucket == 2) return "RANGE LOW VOL";
   if(bucket == 3) return "RANGE HIGH VOL";
   if(bucket == 4) return "TRANSITION PENDING";
   if(bucket == 5) return "TRANSITION FRESH";
   return "UNKNOWN";
}

string LiqMacroRegimeShortName(int bucket)
{
   if(bucket == 0) return "TLV";
   if(bucket == 1) return "THV";
   if(bucket == 2) return "RLV";
   if(bucket == 3) return "RHV";
   if(bucket == 4) return "TR PEND";
   if(bucket == 5) return "TR FRESH";
   return "UNK";
}

int LiqMacroRegimeBucket(const RegimeV3Snapshot &snapshot)
{
   if(!snapshot.valid) return -1;
   // Transition states take precedence over the underlying core bucket,
   // matching the production ORB classifier exactly.
   if(snapshot.transitionStatus == "WATCH" || snapshot.transitionStatus == "DEVELOPING") return 4;
   if(snapshot.transitionStatus == "FRESH_CONFIRMED") return 5;
   if(snapshot.core == "TREND_LOW_VOL") return 0;
   if(snapshot.core == "TREND_HIGH_VOL") return 1;
   if(snapshot.core == "RANGE_LOW_VOL") return 2;
   if(snapshot.core == "RANGE_HIGH_VOL") return 3;
   return -1;
}

int LiqMacroRegimeBucketAt(datetime signalAvailable, RegimeV3Snapshot &snapshot)
{
   snapshot.valid = false;
   if(!InpRegimeV3Observer) return -1;
   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true)) return -1;
   if(!RegimeV3SnapshotAt(signalAvailable, snapshot)) return -1;
   return LiqMacroRegimeBucket(snapshot);
}

bool LiqMacroRegimeAllowed(int bucket)
{
   // Unknown history fails open and is exposed separately on the dashboard.
   return bucket < 0 || bucket >= LIQ_MACRO_REGIME_COUNT ? true : g_macroRegimeAllowed[bucket];
}

bool LiqMacroRegimeHasBlocks()
{
   for(int i = 0; i < LIQ_MACRO_REGIME_COUNT; ++i)
      if(!g_macroRegimeAllowed[i]) return true;
   return false;
}

string LiqMacroRegimeStatsText(int bucket)
{
   int wins = g_macroRegimeWins[bucket];
   int losses = g_macroRegimeLosses[bucket];
   int resolved = wins + losses;
   double wr = resolved > 0 ? (double)wins / (double)resolved * 100.0 : 0.0;
   return LiqMacroRegimeShortName(bucket) + " " + IntegerToString(wins) + "W/"
      + IntegerToString(losses) + "L " + DoubleToString(wr, 1) + "%";
}

string LiqMacroRegimeMask()
{
   string mask = "";
   for(int i = 0; i < LIQ_MACRO_REGIME_COUNT; ++i)
      mask += (i > 0 ? "," : "") + LiqMacroRegimeShortName(i) + "=" + (g_macroRegimeAllowed[i] ? "ALLOW" : "BLOCK");
   return mask;
}

void LiqMacroRegimeInit()
{
   g_macroRegimeAllowed[0] = InpMacroRegimeTrendLowVolAllowed;
   g_macroRegimeAllowed[1] = InpMacroRegimeTrendHighVolAllowed;
   g_macroRegimeAllowed[2] = InpMacroRegimeRangeLowVolAllowed;
   g_macroRegimeAllowed[3] = InpMacroRegimeRangeHighVolAllowed;
   g_macroRegimeAllowed[4] = InpMacroRegimeTransitionPendingAllowed;
   g_macroRegimeAllowed[5] = InpMacroRegimeTransitionFreshAllowed;
   for(int i = 0; i < LIQ_MACRO_REGIME_COUNT; ++i)
   {
      g_macroRegimeWins[i] = 0;
      g_macroRegimeLosses[i] = 0;
   }
   g_macroRegimeRejected = 0;
   g_macroRegimeUnclassified = 0;
}

#endif
