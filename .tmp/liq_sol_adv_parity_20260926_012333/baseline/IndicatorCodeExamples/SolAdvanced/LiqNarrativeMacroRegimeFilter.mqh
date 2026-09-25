#ifndef LIQ_NARRATIVE_MACRO_REGIME_FILTER_MQH
#define LIQ_NARRATIVE_MACRO_REGIME_FILTER_MQH

int ApplyLiqMacroRegimeFilter(ErlSignal &signals[])
{
   g_macroRegimeRejected = 0;
   g_macroRegimeUnclassified = 0;
   if(ArraySize(signals) <= 0 || !LiqMacroRegimeHasBlocks()) return ArraySize(signals);

   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true))
   {
      g_macroRegimeUnclassified = ArraySize(signals);
      return ArraySize(signals);
   }

   ErlSignal filtered[];
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      RegimeV3Snapshot state;
      int bucket = LiqMacroRegimeBucketAt(signals[i].availableTime, state);
      if(bucket < 0)
      {
         int unknown = ArraySize(filtered);
         ArrayResize(filtered, unknown + 1);
         filtered[unknown] = signals[i];
         g_macroRegimeUnclassified++;
         continue;
      }
      if(!LiqMacroRegimeAllowed(bucket))
      {
         g_macroRegimeRejected++;
         continue;
      }
      int keep = ArraySize(filtered);
      ArrayResize(filtered, keep + 1);
      filtered[keep] = signals[i];
   }

   ArrayFree(signals);
   ArrayResize(signals, ArraySize(filtered));
   for(int i = 0; i < ArraySize(filtered); ++i) signals[i] = filtered[i];
   return ArraySize(signals);
}

bool LiqMacroRegimeDecision(const ErlSignal &sig, bool &rejected, string &rule)
{
   rejected = false;
   rule = "";
   if(!LiqMacroRegimeHasBlocks()) return true;
   RegimeV3Snapshot state;
   int bucket = LiqMacroRegimeBucketAt(sig.availableTime, state);
   if(bucket < 0) return false;
   rule = "MACRO_" + LiqMacroRegimeShortName(bucket);
   rejected = !LiqMacroRegimeAllowed(bucket);
   return true;
}

void CalculateLiqMacroRegimeStats(ErlSignal &signals[], const ErlSignal &exitSignals[])
{
   for(int i = 0; i < LIQ_MACRO_REGIME_COUNT; ++i)
   {
      g_macroRegimeWins[i] = 0;
      g_macroRegimeLosses[i] = 0;
   }
   if(ArraySize(signals) <= 0) return;
   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true)) return;
   if(!g_allowDuplicateEntries) FilterAlternatingSignals(signals);

   int total = ArraySize(signals);
   for(int i = 0; i < total; ++i)
   {
      if(g_histAuditRunning)
         SetHistoricalAuditProgress("REGIMES", 56.0 + 20.0 * (double)(i + 1) / (double)MathMax(1, total));
      RegimeV3Snapshot state;
      int bucket = LiqMacroRegimeBucketAt(signals[i].availableTime, state);
      if(bucket < 0 || bucket >= LIQ_MACRO_REGIME_COUNT) continue;

      bool closed = false, won = false, valid = false;
      datetime nextSignalTime = NextOppositeSignalTime(exitSignals, signals[i].availableTime, signals[i].dir);
      string simKey = SimCacheKey(signals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime);
      double r = 0.0;
      if(!SimCacheGet(simKey, r, closed, won, valid))
      {
         r = SimulateSignal(signals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime, closed, won, valid);
         if(valid && closed) SimCachePut(simKey, r, closed, won, valid);
      }
      if(!valid || !closed) continue;
      if(won) g_macroRegimeWins[bucket]++;
      else g_macroRegimeLosses[bucket]++;
   }
}

#endif
