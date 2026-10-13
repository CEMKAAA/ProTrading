double BeforeSimulateSignal(const ErlSignal &sig, ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel,
   ENUM_TIMEFRAMES entryTf, datetime maxTime, bool &closed, bool &won, bool &valid)
{
   bool reverseExitMode = (targetModel == ERL_TARGET_OPPOSITE_SIGNAL);
   if(reverseExitMode) hc = ERL_HC_OFF;
   closed = false;
   won = false;
   valid = false;
   g_lastSimInvalidReason = "";
   ResetLastSimulationTrace();
   if(g_invertMode && reverseExitMode)
   {
      g_lastSimInvalidReason = "INV_REVERSE";
      return 0.0;
   }

   bool delayedNasEntry=LnNasDelayed(sig.id);
   ENUM_TIMEFRAMES replayTf=delayedNasEntry?(ENUM_TIMEFRAMES)_Period:entryTf;
   int tfSeconds = PeriodSeconds(replayTf);
   if(tfSeconds <= 0) tfSeconds = 60;
   datetime requiredCutoff = (delayedNasEntry?sig.availableTime:sig.entryTime) - tfSeconds * 4;
   if(g_btCutoff > 0 && g_btCutoff < requiredCutoff) requiredCutoff = g_btCutoff;
   if(!EnsureSimulationSeries(replayTf, requiredCutoff))
   {
      g_lastSimInvalidReason = "SERIES";
      return 0.0;
   }
   int setupIdx = FindEntryBarIndex(g_simRates, delayedNasEntry?sig.availableTime:sig.entryTime);
   if(setupIdx < (delayedNasEntry?0:1))
   {
      g_lastSimInvalidReason = "ENTRY_BAR";
      return 0.0;
   }
   if(sig.availableTime <= 0)
   {
      g_lastSimInvalidReason = "AVAIL_TIME";
      return 0.0;
   }
   int entryIdx = delayedNasEntry?setupIdx:setupIdx-1;
   if(delayedNasEntry && g_simRates[entryIdx].time!=sig.availableTime)
   {
      g_lastSimInvalidReason="NAS_CONFIRM_BAR";
      return 0.0;
   }
   int pricingDir = EffectiveTradeDir(sig.dir);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   double rawEntry = sig.entry;
   if(delayedNasEntry||g_btFillMode == BT_FILL_NEXT_BAR_OPEN)
      rawEntry = g_simRates[entryIdx].open;
   else if(g_btFillMode == BT_FILL_CONSERVATIVE)
      rawEntry = pricingDir > 0 ? g_simRates[entryIdx].high : g_simRates[entryIdx].low;

   // With zero configured spread use the spread recorded on the historical
   // entry bar. Reusing today's live/weekend spread across years distorts
   // index audits, especially when spread is a material fraction of the SL.
   double effectiveSpreadPts = g_btSpreadPts;
   if(effectiveSpreadPts <= 0.0 && entryIdx >= 0 && entryIdx < ArraySize(g_simRates)
      && g_simRates[entryIdx].spread > 0)
      effectiveSpreadPts = (double)g_simRates[entryIdx].spread;
   double executionCost = MathMax(0.0, effectiveSpreadPts + g_btSlippagePts) * point;
   double spreadCost = MathMax(0.0, effectiveSpreadPts) * point;
   double slipCost = MathMax(0.0, g_btSlippagePts) * point;
   double simEntry = NormTradePrice(rawEntry + pricingDir * executionCost);
   if(g_invertMode)
      simEntry = NormTradePrice(rawEntry + (pricingDir > 0 ? spreadCost + slipCost : -slipCost));
   double barSimEntry = simEntry;
   double barSourceEntry = NormTradePrice(rawEntry + (g_invertMode
      ? (sig.dir > 0 ? spreadCost + slipCost : -slipCost) : sig.dir * executionCost));
   int simDir = pricingDir;
   double activeSl = 0.0, tp = 0.0, half = 0.0, simRisk = 0.0, commissionR = 0.0;
   ERL_HC_MODE activeHc = ERL_HC_OFF;
   string geometryDetail = "";
   if(!ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, barSourceEntry, reverseExitMode, simDir,
      activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, false))
   {
      g_lastSimInvalidReason = "GEOMETRY";
      return 0.0;
   }

   valid = true;
   g_lastSimEntryTime=sig.availableTime;g_lastSimEntrySpread=effectiveSpreadPts;g_lastSimEntryBasis=g_btSpreadPts>0?"CONFIGURED_BAR_SPREAD":"HISTORICAL_BAR_SPREAD";
   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
   bool halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
   double pnlR = 0.0;

   if(InpBacktestUseTickReplay)
   {
      datetime tickStart = sig.availableTime;
      datetime tickEnd = maxTime > 0 ? maxTime : TimeCurrent();
      if(tickEnd > tickStart)
      {

         // Read chronologically and stop at the first terminal event. Loading
         // the whole lifespan first can copy months of unused quotes per trade.
         ulong tickLimit = (ulong)tickEnd * 1000;
         bool tickInitialized = false;
         datetime lastTickAt = 0;
         double lastClosePx = 0.0;
         for(ulong cursor = (ulong)tickStart * 1000; cursor <= tickLimit;)
         {
            if(g_lnQuoteAcceleration&&tickInitialized)
            {
               cursor=LnQuoteSkipRange(cursor,tickLimit,simDir,activeSl,tp,half,!halfDone,reverseExitMode,lastTickAt,lastClosePx);
               if(cursor>tickLimit)break;
            }
            ulong chunkEnd = cursor + 3600000 - 1;
            if(chunkEnd > tickLimit) chunkEnd = tickLimit;
            int rangeFirst=0,rangeAfter=0;
            int copied=0;
            if(g_lnQuoteAcceleration)
               copied=LnQuoteLoad(cursor,tickLimit,rangeFirst,rangeAfter,chunkEnd);
            else
            {
               g_lnQuoteReady=false;
               copied=CopyTicksRange(_Symbol,g_lnQuoteTicks,COPY_TICKS_ALL,cursor,chunkEnd);
               rangeAfter=MathMax(0,copied);
            }
            if(copied < 0) break;
            cursor = chunkEnd + 1;
            if(copied == 0)
            {
               if(!tickInitialized && chunkEnd >= (ulong)(tickStart + tfSeconds) * 1000) break;
               continue;
            }
            int first = -1;
            for(int k = rangeFirst; k < rangeAfter; ++k)
            {
               if(g_lnQuoteTicks[k].bid > 0.0 && g_lnQuoteTicks[k].ask > 0.0) { first = k; break; }
            }
            if(first < 0)
            {
               if(!tickInitialized && chunkEnd >= (ulong)(tickStart + tfSeconds) * 1000) break;
               continue;
            }
            // A terminal TP/SL observed in an early tick chunk is final. Do
            // not discard that causal ordering merely because quotes after
            // the exit do not cover the later reverse-signal boundary.
            if(!tickInitialized)
            {
               if((datetime)g_lnQuoteTicks[first].time > tickStart + tfSeconds) break;
               double slip = MathMax(0.0, g_btSlippagePts) * point;
               simEntry = NormTradePrice(simDir > 0 ? g_lnQuoteTicks[first].ask + slip : g_lnQuoteTicks[first].bid - slip);
               double sourceTickEntry = NormTradePrice(sig.dir > 0 ? g_lnQuoteTicks[first].ask + slip : g_lnQuoteTicks[first].bid - slip);
               if(!ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, sourceTickEntry, reverseExitMode, simDir,
                  activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, true))
               {
                  g_lastSimInvalidReason=StringFind(geometryDetail,"INVERSE_GAP_BLOCK")==0 ? "INVERSE_GAP_BLOCK" : "GEOMETRY";
                  valid=false;
                  return 0.0;
               }
               g_lastSimEntryTime=sig.availableTime;g_lastSimEntrySpread=effectiveSpreadPts;g_lastSimEntryBasis=g_btSpreadPts>0?"CONFIGURED_BAR_SPREAD":"HISTORICAL_BAR_SPREAD";
   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
               g_lastSimEntryTime=(datetime)g_lnQuoteTicks[first].time;g_lastSimEntrySpread=(g_lnQuoteTicks[first].ask-g_lnQuoteTicks[first].bid)/point;g_lastSimEntryBasis="ENTRY_BID_ASK_QUOTE";
               halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
               pnlR = 0.0;
               tickInitialized = true;
            }
            for(int k = first; k < rangeAfter; ++k)
            {
               if(g_lnQuoteAcceleration)
               {
                  int next=LnQuoteSkip(k,rangeAfter,simDir,activeSl,tp,half,!halfDone,reverseExitMode);
                  if(next>k)
                  {
                     int last=g_lnQuoteBlocks[k/LN_QUOTE_BLOCK].lastValid;
                     if(last>=0)
                     {
                        lastTickAt=(datetime)g_lnQuoteTicks[last].time;
                        lastClosePx=simDir>0?g_lnQuoteTicks[last].bid:g_lnQuoteTicks[last].ask;
                     }
                     k=next-1;continue;
                  }
               }
               double bid = g_lnQuoteTicks[k].bid;
               double ask = g_lnQuoteTicks[k].ask;
               if(bid <= 0.0 || ask <= 0.0) continue;
               double closePx = simDir > 0 ? bid : ask;
               lastTickAt = (datetime)g_lnQuoteTicks[k].time;
               lastClosePx = closePx;

               if(!reverseExitMode && !halfDone)
               {
                  bool hitHalf = simDir > 0 ? closePx >= half : closePx <= half;
                  if(hitHalf)
                  {
                     double halfR = MathAbs(half - simEntry) / simRisk;
                     pnlR += halfR * 0.5;
                     activeSl = simEntry;
                     halfDone = true;
                  }
               }

               bool hitSl = !reverseExitMode && (simDir > 0 ? closePx <= activeSl : closePx >= activeSl);
               if(hitSl)
               {
                  double slR = MathAbs(simEntry - activeSl) / simRisk;
                  pnlR -= halfDone && activeHc != ERL_HC_OFF ? slR * 0.5 : slR;
                  pnlR -= commissionR;
                  closed = true;
                  won = pnlR > 0.0;
                  CaptureLastSimulationExit("TICK_SL", (datetime)g_lnQuoteTicks[k].time);
                  return pnlR;
               }

               bool hitTp = !reverseExitMode && tp > 0.0 && (simDir > 0 ? closePx >= tp : closePx <= tp);
               if(hitTp)
               {
                  double targetR = MathAbs(tp - simEntry) / simRisk;
                  pnlR += halfDone && activeHc != ERL_HC_OFF ? targetR * 0.5 : targetR;
                  pnlR -= commissionR;
                  closed = true;
                  won = pnlR > 0.0;
                  CaptureLastSimulationExit("TICK_TP", (datetime)g_lnQuoteTicks[k].time);
                  return pnlR;
               }
            }
         }
         if(tickInitialized && maxTime > 0 && lastTickAt >= maxTime)
         {
            pnlR = ApplyForcedSignalExit(simDir, lastClosePx, simEntry, simRisk, halfDone, activeHc, pnlR, commissionR);
            closed = true;
            won = pnlR > 0.0;
            CaptureLastSimulationExit("TICK_REVERSE_EXIT", maxTime);
            return pnlR;
         }
         else if(tickInitialized && maxTime <= 0 && lastTickAt >= tickEnd - tfSeconds)
         {
            CaptureLastSimulationExit("TICK_OPEN", lastTickAt);
            return pnlR;
         }
      }
   }

   // Tick coverage was unavailable/incomplete and no terminal event was
   // observed. Restart the deterministic OHLC fallback from its own entry
   // geometry; never carry a partial tick HC/BE state into the bar replay.
   if(g_invertMode || LnNasNeedsExactTicks(sig,maxTime))
   {
      valid=false;closed=false;won=false;
      g_lastSimInvalidReason=g_invertMode ? "INVERSE_TICKS_REQUIRED" : "NAS_EXIT_TICKS_MISSING";
      return 0.0;
   }
   simEntry = barSimEntry;
   if(!ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, barSourceEntry, reverseExitMode, simDir,
      activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, false))
   {
      valid = false;
      g_lastSimInvalidReason = "GEOMETRY_FALLBACK";
      return 0.0;
   }
   g_lastSimEntryTime=sig.availableTime;g_lastSimEntrySpread=effectiveSpreadPts;g_lastSimEntryBasis=g_btSpreadPts>0?"CONFIGURED_BAR_SPREAD":"HISTORICAL_BAR_SPREAD";
   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
   halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
   pnlR = 0.0;

   for(int i = entryIdx; i >= 0; --i)
   {
      if(maxTime > 0 && g_simRates[i].time >= maxTime)
      {
         pnlR = ApplyForcedSignalExit(simDir, g_simRates[i].open, simEntry, simRisk, halfDone, activeHc, pnlR, commissionR);
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit("BAR_REVERSE_EXIT", maxTime);
         return pnlR;
      }
      if(delayedNasEntry&&!reverseExitMode)
      {
         bool hitSl=simDir>0?g_simRates[i].low<=activeSl:g_simRates[i].high>=activeSl;
         bool hitTp=tp>0.0&&(simDir>0?g_simRates[i].high>=tp:g_simRates[i].low<=tp);
         bool hitHalf=!halfDone&&half>0.0&&(simDir>0?g_simRates[i].high>=half:g_simRates[i].low<=half);
         if(hitSl&&(hitTp||hitHalf))
         {
            valid=false;closed=false;won=false;
            g_lastSimInvalidReason="NAS_BAR_AMBIGUOUS";
            return 0.0;
         }
      }
      if(!reverseExitMode && !halfDone)
      {
         bool hitHalf = simDir > 0 ? g_simRates[i].high >= half : g_simRates[i].low <= half;
         if(hitHalf)
         {
            double halfR = MathAbs(half - simEntry) / simRisk;
            pnlR += halfR * 0.5;
            activeSl = simEntry;
            halfDone = true;
         }
      }

      double openRef = (i == entryIdx ? simEntry : g_simRates[i].open);
      bool barHitTp = !reverseExitMode && tp > 0.0 && (simDir > 0 ? g_simRates[i].high >= tp : g_simRates[i].low <= tp);
      bool barHitSl = !reverseExitMode && (simDir > 0 ? g_simRates[i].low <= activeSl : g_simRates[i].high >= activeSl);
      int res = reverseExitMode ? 0 : ResolveSameBar(g_simRates[i], simDir, openRef, tp, activeSl);
      if(res > 0)
      {
         double targetR = MathAbs(tp - simEntry) / simRisk;
         pnlR += halfDone && activeHc != ERL_HC_OFF ? targetR * 0.5 : targetR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit(barHitTp && barHitSl ? "BAR_BOTH_TP_POLICY" : "BAR_TP", g_simRates[i].time);
         return pnlR;
      }
      if(res < 0)
      {
         double slR = MathAbs(simEntry - activeSl) / simRisk;
         pnlR -= halfDone && activeHc != ERL_HC_OFF ? slR * 0.5 : slR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit(barHitTp && barHitSl ? "BAR_BOTH_SL_POLICY" : "BAR_SL", g_simRates[i].time);
         return pnlR;
      }
   }
   CaptureLastSimulationExit("BAR_OPEN", g_simRates[0].time);
   return pnlR;
}
