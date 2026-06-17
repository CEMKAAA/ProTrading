#property strict

enum SATS_PRESET
{
   SATS_PRESET_AUTO = 0,
   SATS_PRESET_CUSTOM = 1,
   SATS_PRESET_SCALPING = 2,
   SATS_PRESET_DEFAULT = 3,
   SATS_PRESET_SWING = 4,
   SATS_PRESET_CRYPTO = 5
};

struct SATSSettings
{
   SATS_PRESET preset;
   int    atrLen;
   double baseMult;
   bool   useAdaptive;
   int    erLen;
   double adaptStrength;
   int    atrBaselineLen;
   bool   useTqi;
   double qualityStrength;
   double qualityCurve;
   bool   smoothMult;
   bool   useAsymBands;
   double asymStrength;
   bool   useEffAtr;
   bool   useCharFlip;
   int    charFlipMinAge;
   double charFlipHigh;
   double charFlipLow;
   double tqiWeightEr;
   double tqiWeightVol;
   double tqiWeightStruct;
   double tqiWeightMom;
   int    tqiStructLen;
   int    tqiMomLen;
   int    pivotLen;
   int    rsiLen;
   int    volLen;
   double slAtrMult;
   double tp1R;
   double tp2R;
   double tp3R;
   int    tradeMaxAge;
   bool   useAutoCalib;
   int    calibWindow;
   double calibBadR;
   double calibGoodR;
   double calibStepQ;
   int    calibCooldown;
   double calibMinQ;
   double calibMaxQ;
};

struct SATSPoint
{
   int    trend;
   bool   buy;
   bool   sell;
   double stLine;
   double lowerBand;
   double upperBand;
   double entry;
   double sl;
   double tp1;
   double tp2;
   double tp3;
   double atr;
   double er;
   double tqi;
   double qualityStrength;
};

struct SATSLearningSummary
{
   double qualityStrength;
   int    samples;
   double allTimeR;
   double allTimeDD;
   int    winStreak;
   int    lossStreak;
   int    maxWinStreak;
   int    maxLossStreak;
};

double SATS_Empty()
{
   return EMPTY_VALUE;
}

bool SATS_IsValid(const double v)
{
   return MathIsValidNumber(v) && v != EMPTY_VALUE;
}

double SATS_Nz(const double v, const double fallback = 0.0)
{
   return SATS_IsValid(v) ? v : fallback;
}

double SATS_Clamp(const double v, const double lo, const double hi)
{
   return MathMax(lo, MathMin(hi, v));
}

double SATS_SafeDiv(const double num, const double den, const double fallback = 0.0)
{
   if(den != 0.0 && MathIsValidNumber(num) && MathIsValidNumber(den))
      return num / den;
   return fallback;
}

double SATS_MapClamp(const double v, const double inLo, const double inHi, const double outLo, const double outHi)
{
   double t = SATS_Clamp(SATS_SafeDiv(v - inLo, inHi - inLo, 0.0), 0.0, 1.0);
   return outLo + t * (outHi - outLo);
}

double SATS_TrueRange(const MqlRates &rates[], const int i)
{
   if(i <= 0)
      return rates[i].high - rates[i].low;
   double h_l = rates[i].high - rates[i].low;
   double h_c = MathAbs(rates[i].high - rates[i - 1].close);
   double l_c = MathAbs(rates[i].low - rates[i - 1].close);
   return MathMax(h_l, MathMax(h_c, l_c));
}

double SATS_SmaArray(const double &arr[], const int i, const int len)
{
   if(i < len - 1)
      return SATS_Empty();
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; k++)
   {
      if(!SATS_IsValid(arr[k]))
         return SATS_Empty();
      sum += arr[k];
   }
   return sum / (double)len;
}

double SATS_SmaVolume(const MqlRates &rates[], const int i, const int len)
{
   if(i < len - 1)
      return SATS_Empty();
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; k++)
      sum += (double)rates[k].tick_volume;
   return sum / (double)len;
}

double SATS_StdevVolume(const MqlRates &rates[], const int i, const int len)
{
   if(i < len - 1)
      return SATS_Empty();
   double mean = SATS_SmaVolume(rates, i, len);
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; k++)
   {
      double d = (double)rates[k].tick_volume - mean;
      sum += d * d;
   }
   return MathSqrt(sum / (double)len);
}

double SATS_HighestHigh(const MqlRates &rates[], const int i, const int len)
{
   if(i < len - 1)
      return SATS_Empty();
   double v = rates[i - len + 1].high;
   for(int k = i - len + 2; k <= i; k++)
      v = MathMax(v, rates[k].high);
   return v;
}

double SATS_LowestLow(const MqlRates &rates[], const int i, const int len)
{
   if(i < len - 1)
      return SATS_Empty();
   double v = rates[i - len + 1].low;
   for(int k = i - len + 2; k <= i; k++)
      v = MathMin(v, rates[k].low);
   return v;
}

double SATS_CalcEfficiencyRatio(const MqlRates &rates[], const int i, const int len)
{
   if(i < len)
      return 0.0;
   double change = MathAbs(rates[i].close - rates[i - len].close);
   double volatility = 0.0;
   for(int k = i - len + 1; k <= i; k++)
      volatility += MathAbs(rates[k].close - rates[k - 1].close);
   return SATS_SafeDiv(change, volatility, 0.0);
}

double SATS_PivotHigh(const MqlRates &rates[], const int i, const int len)
{
   int center = i - len;
   if(center < len || i < len * 2)
      return SATS_Empty();
   double v = rates[center].high;
   for(int k = center - len; k <= center + len; k++)
   {
      if(rates[k].high > v)
         return SATS_Empty();
   }
   return v;
}

double SATS_PivotLow(const MqlRates &rates[], const int i, const int len)
{
   int center = i - len;
   if(center < len || i < len * 2)
      return SATS_Empty();
   double v = rates[center].low;
   for(int k = center - len; k <= center + len; k++)
   {
      if(rates[k].low < v)
         return SATS_Empty();
   }
   return v;
}

void SATS_ResolvePreset(const SATSSettings &cfg,
                        int &atrLen,
                        double &baseMult,
                        int &erLen,
                        int &rsiLen,
                        double &slMult)
{
   SATS_PRESET p = cfg.preset;
   if(p == SATS_PRESET_AUTO)
   {
      int tfMinutes = PeriodSeconds(_Period) / 60;
      p = (tfMinutes <= 5 ? SATS_PRESET_SCALPING : (tfMinutes <= 240 ? SATS_PRESET_DEFAULT : SATS_PRESET_SWING));
   }

   if(p == SATS_PRESET_SCALPING)
   {
      atrLen = 10; baseMult = 1.5; erLen = 14; rsiLen = 9; slMult = 1.0;
   }
   else if(p == SATS_PRESET_DEFAULT)
   {
      atrLen = 14; baseMult = 2.0; erLen = 20; rsiLen = 14; slMult = 1.5;
   }
   else if(p == SATS_PRESET_SWING)
   {
      atrLen = 21; baseMult = 2.5; erLen = 30; rsiLen = 21; slMult = 2.0;
   }
   else if(p == SATS_PRESET_CRYPTO)
   {
      atrLen = 14; baseMult = 2.8; erLen = 20; rsiLen = 14; slMult = 2.5;
   }
   else
   {
      atrLen = cfg.atrLen; baseMult = cfg.baseMult; erLen = cfg.erLen; rsiLen = cfg.rsiLen; slMult = cfg.slAtrMult;
   }
}

int SATS_ErBin(const double er)
{
   if(er < 0.25)
      return 0;
   return er < 0.50 ? 1 : 2;
}

int SATS_VolBin(const double vRatio)
{
   if(vRatio < 0.7)
      return 0;
   return vRatio < 1.3 ? 1 : 2;
}

int SATS_CellIdx(const int eb, const int vb)
{
   return eb * 3 + vb;
}

double SATS_CalcRealizedR(const bool slHit, const bool tp1H, const bool tp2H, const bool tp3H,
                          const double tp1R, const double tp2R, const double tp3R)
{
   if(tp3H)
      return (tp1R + tp2R + tp3R) / 3.0;
   if(slHit)
   {
      double taken = 0.0;
      double remaining = 1.0;
      if(tp1H)
      {
         taken += (1.0 / 3.0) * tp1R;
         remaining -= 1.0 / 3.0;
      }
      if(tp2H)
      {
         taken += (1.0 / 3.0) * tp2R;
         remaining -= 1.0 / 3.0;
      }
      return taken + remaining * (-1.0);
   }
   return 0.0;
}

double SATS_CalcTimeoutR(const bool tp1H, const bool tp2H, const bool tp3H,
                         const double tp1R, const double tp2R, const double tp3R)
{
   double taken = 0.0;
   if(tp1H)
      taken += (1.0 / 3.0) * tp1R;
   if(tp2H)
      taken += (1.0 / 3.0) * tp2R;
   if(tp3H)
      taken += (1.0 / 3.0) * tp3R;
   return taken;
}

int SATS_Calculate(const MqlRates &rates[], const int n, const SATSSettings &cfg, SATSPoint &out[], SATSLearningSummary &summary)
{
   if(n <= 0)
      return 0;

   ArrayResize(out, n);

   int effectiveAtrLen, effectiveErLen, effectiveRsiLen;
   double effectiveBaseMult, effectiveSlMult;
   SATS_ResolvePreset(cfg, effectiveAtrLen, effectiveBaseMult, effectiveErLen, effectiveRsiLen, effectiveSlMult);

   double fixedTp1R = MathMin(cfg.tp1R, MathMin(cfg.tp2R, cfg.tp3R));
   double fixedTp3R = MathMax(cfg.tp1R, MathMax(cfg.tp2R, cfg.tp3R));
   double fixedTp2R = cfg.tp1R + cfg.tp2R + cfg.tp3R - fixedTp1R - fixedTp3R;
   int tradeMaxAge = cfg.tradeMaxAge > 0 ? cfg.tradeMaxAge : 100;

   int warmupBars = MathMax(50, MathMax(effectiveAtrLen, MathMax(effectiveErLen, MathMax(effectiveRsiLen, MathMax(cfg.volLen, MathMax(cfg.pivotLen * 2 + 1, MathMax(cfg.tqiMomLen, cfg.tqiStructLen))))))) + 10;

   double tr[], rawAtr[], atrBaseline[], er[], effAtr[], tqi[], activeSm[], passiveSm[], lowerBand[], upperBand[];
   int trend[];
   ArrayResize(tr, n); ArrayResize(rawAtr, n); ArrayResize(atrBaseline, n); ArrayResize(er, n); ArrayResize(effAtr, n); ArrayResize(tqi, n);
   ArrayResize(activeSm, n); ArrayResize(passiveSm, n); ArrayResize(lowerBand, n); ArrayResize(upperBand, n); ArrayResize(trend, n);

   double lastPivotHigh = SATS_Empty(), lastPivotLow = SATS_Empty();
   double tradeEntry = SATS_Empty(), tradeSl = SATS_Empty(), tradeTp1 = SATS_Empty(), tradeTp2 = SATS_Empty(), tradeTp3 = SATS_Empty();
   int trendStartBar = 0;

   double effectiveQualityStrength = cfg.qualityStrength;
   double signalRBuffer[];
   int signalCount = 0, signalsSinceCalib = 0;
   double allTimeCumR = 0.0, allTimePeak = 0.0, allTimeTrough = 0.0;
   int curWinStreak = 0, curLossStreak = 0, maxWinStreak = 0, maxLossStreak = 0;
   int gridCount[9];
   double gridEwm[9];
   for(int gi = 0; gi < 9; gi++)
   {
      gridCount[gi] = 0;
      gridEwm[gi] = 0.0;
   }

   int virtualTradeDir = 0, virtualEntryBar = 0, virtualCellIdx = -1;
   double virtualEntry = SATS_Empty(), virtualSl = SATS_Empty(), virtualTp1 = SATS_Empty(), virtualTp2 = SATS_Empty(), virtualTp3 = SATS_Empty();
   bool hitTp1 = false, hitTp2 = false, hitTp3 = false;

   for(int i = 0; i < n; i++)
   {
      out[i].trend = 0; out[i].buy = false; out[i].sell = false;
      out[i].stLine = out[i].lowerBand = out[i].upperBand = SATS_Empty();
      out[i].entry = tradeEntry; out[i].sl = tradeSl; out[i].tp1 = tradeTp1; out[i].tp2 = tradeTp2; out[i].tp3 = tradeTp3;
      out[i].atr = out[i].er = out[i].tqi = SATS_Empty(); out[i].qualityStrength = effectiveQualityStrength;

      tr[i] = SATS_TrueRange(rates, i);
      if(i == 0) rawAtr[i] = tr[i];
      else if(i < effectiveAtrLen) rawAtr[i] = SATS_Empty();
      else if(i == effectiveAtrLen)
      {
         double sum = 0.0; for(int k = i - effectiveAtrLen + 1; k <= i; k++) sum += tr[k]; rawAtr[i] = sum / (double)effectiveAtrLen;
      }
      else rawAtr[i] = (rawAtr[i - 1] * (effectiveAtrLen - 1) + tr[i]) / (double)effectiveAtrLen;

      atrBaseline[i] = SATS_SmaArray(rawAtr, i, cfg.atrBaselineLen);
      double rawAtrNz = SATS_Nz(rawAtr[i], 0.0);
      double baseAtr = SATS_Nz(atrBaseline[i], rawAtrNz);
      double volRatio = SATS_SafeDiv(rawAtrNz, baseAtr, 1.0);
      er[i] = SATS_CalcEfficiencyRatio(rates, i, effectiveErLen);
      effAtr[i] = cfg.useEffAtr ? rawAtrNz * (0.5 + 0.5 * er[i]) : rawAtrNz;

      double tqiEr = SATS_Clamp(er[i], 0.0, 1.0);
      bool hasVolume = rates[i].tick_volume > 0;
      double volZRaw = 0.0;
      if(hasVolume)
      {
         double vMean = SATS_SmaVolume(rates, i, cfg.volLen);
         double vStd = SATS_StdevVolume(rates, i, cfg.volLen);
         volZRaw = SATS_SafeDiv((double)rates[i].tick_volume - SATS_Nz(vMean, (double)rates[i].tick_volume), SATS_Nz(vStd, 0.0), 0.0);
      }
      double tqiVol = hasVolume ? SATS_MapClamp(volZRaw, -1.0, 2.0, 0.0, 1.0) : SATS_MapClamp(volRatio, 0.6, 1.8, 0.0, 1.0);
      double structHi = SATS_HighestHigh(rates, i, cfg.tqiStructLen);
      double structLo = SATS_LowestLow(rates, i, cfg.tqiStructLen);
      double pricePos = SATS_SafeDiv(rates[i].close - SATS_Nz(structLo, rates[i].close), SATS_Nz(structHi, rates[i].close) - SATS_Nz(structLo, rates[i].close), 0.5);
      double tqiStruct = SATS_Clamp(MathAbs(pricePos - 0.5) * 2.0, 0.0, 1.0);
      double tqiMom = 0.0;
      if(i >= cfg.tqiMomLen)
      {
         double windowChange = rates[i].close - rates[i - cfg.tqiMomLen].close; int alignedBars = 0;
         for(int k = 0; k < cfg.tqiMomLen; k++)
         {
            double barChange = rates[i - k].close - rates[i - k - 1].close;
            if((windowChange > 0.0 && barChange > 0.0) || (windowChange < 0.0 && barChange < 0.0)) alignedBars++;
         }
         tqiMom = (double)alignedBars / (double)cfg.tqiMomLen;
      }
      double tqiWeightSum = cfg.tqiWeightEr + cfg.tqiWeightVol + cfg.tqiWeightStruct + cfg.tqiWeightMom;
      double tqiWeightDenom = tqiWeightSum > 0.0 ? tqiWeightSum : 1.0;
      double tqiRaw = cfg.useTqi ? (tqiEr * cfg.tqiWeightEr + tqiVol * cfg.tqiWeightVol + tqiStruct * cfg.tqiWeightStruct + tqiMom * cfg.tqiWeightMom) / tqiWeightDenom : 0.5;
      tqi[i] = SATS_Clamp(tqiRaw, 0.0, 1.0);

      if(!cfg.useAutoCalib) effectiveQualityStrength = cfg.qualityStrength;
      double legacyAdaptFactor = cfg.useAdaptive ? (1.0 + cfg.adaptStrength * (0.5 - er[i])) : 1.0;
      double qualityDeviation = cfg.useTqi ? MathPow(1.0 - tqi[i], cfg.qualityCurve) : 0.5;
      double tqiMult = 1.0 - effectiveQualityStrength + effectiveQualityStrength * (0.6 + 0.8 * qualityDeviation);
      double symMult = effectiveBaseMult * legacyAdaptFactor * tqiMult;
      double activeRaw = symMult, passiveRaw = symMult;
      if(cfg.useTqi && cfg.useAsymBands)
      {
         double asymTighten = 1.0 - cfg.asymStrength * tqi[i] * 0.3;
         double asymWiden = 1.0 + cfg.asymStrength * tqi[i] * 0.4;
         activeRaw = symMult * asymTighten; passiveRaw = symMult * asymWiden;
      }
      if(i == 0){ activeSm[i] = activeRaw; passiveSm[i] = passiveRaw; }
      else
      {
         activeSm[i] = cfg.smoothMult ? activeSm[i - 1] * 0.85 + activeRaw * 0.15 : activeRaw;
         passiveSm[i] = cfg.smoothMult ? passiveSm[i - 1] * 0.85 + passiveRaw * 0.15 : passiveRaw;
      }

      int prevTrend = (i == 0 ? 1 : trend[i - 1]);
      double lowerMult = prevTrend == 1 ? activeSm[i] : passiveSm[i];
      double upperMult = prevTrend == 1 ? passiveSm[i] : activeSm[i];
      double lowerRaw = rates[i].close - lowerMult * effAtr[i];
      double upperRaw = rates[i].close + upperMult * effAtr[i];
      if(i == 0){ lowerBand[i] = lowerRaw; upperBand[i] = upperRaw; }
      else
      {
         lowerBand[i] = rates[i - 1].close > lowerBand[i - 1] ? MathMax(lowerRaw, lowerBand[i - 1]) : lowerRaw;
         upperBand[i] = rates[i - 1].close < upperBand[i - 1] ? MathMin(upperRaw, upperBand[i - 1]) : upperRaw;
      }

      bool priceFlipUp = (i > 0 && prevTrend == -1 && rates[i].close > upperBand[i - 1]);
      bool priceFlipDown = (i > 0 && prevTrend == 1 && rates[i].close < lowerBand[i - 1]);
      int trendAge = i - trendStartBar;
      double prevTqi = (i > 0 ? tqi[i - 1] : 0.5);
      bool charFlipCondBase = cfg.useCharFlip && cfg.useTqi && prevTqi > cfg.charFlipHigh && tqi[i] < cfg.charFlipLow && trendAge >= cfg.charFlipMinAge;
      bool charFlipDown = false, charFlipUp = false; // Pine default sourceInput is close, making these comparisons neutral.
      if(false && charFlipCondBase){ charFlipDown = prevTrend == 1; charFlipUp = prevTrend == -1; }
      bool finalFlipUp = priceFlipUp || charFlipUp;
      bool finalFlipDown = priceFlipDown || charFlipDown;
      trend[i] = (i == 0 ? 1 : (finalFlipUp ? 1 : (finalFlipDown ? -1 : prevTrend)));
      if(i > 0 && trend[i] != prevTrend) trendStartBar = i;

      double ph = SATS_PivotHigh(rates, i, cfg.pivotLen), pl = SATS_PivotLow(rates, i, cfg.pivotLen);
      if(SATS_IsValid(ph)) lastPivotHigh = ph;
      if(SATS_IsValid(pl)) lastPivotLow = pl;

      double stLine = trend[i] == 1 ? lowerBand[i] : upperBand[i];
      bool flipUp = (i > 0 && trend[i] == 1 && trend[i - 1] == -1);
      bool flipDown = (i > 0 && trend[i] == -1 && trend[i - 1] == 1);
      bool isWarmedUp = i >= warmupBars;
      out[i].trend = trend[i]; out[i].stLine = stLine; out[i].lowerBand = lowerBand[i]; out[i].upperBand = upperBand[i];
      out[i].atr = effAtr[i]; out[i].er = er[i]; out[i].tqi = tqi[i]; out[i].qualityStrength = effectiveQualityStrength;

      bool newBuy = false, newSell = false;
      int curCellIdx = SATS_CellIdx(SATS_ErBin(er[i]), SATS_VolBin(volRatio));
      if(flipUp && isWarmedUp)
      {
         double tEntry = rates[i].close, slBase = SATS_IsValid(lastPivotLow) ? lastPivotLow : rates[i].low;
         double tSl = MathMin(slBase - effectiveSlMult * effAtr[i], tEntry - effectiveSlMult * effAtr[i]);
         double risk = tEntry - tSl;
         tradeEntry = tEntry; tradeSl = tSl; tradeTp1 = tEntry + risk * fixedTp1R; tradeTp2 = tEntry + risk * fixedTp2R; tradeTp3 = tEntry + risk * fixedTp3R;
         out[i].buy = true; newBuy = true;
      }
      else if(flipDown && isWarmedUp)
      {
         double tEntry = rates[i].close, slBase = SATS_IsValid(lastPivotHigh) ? lastPivotHigh : rates[i].high;
         double tSl = MathMax(slBase + effectiveSlMult * effAtr[i], tEntry + effectiveSlMult * effAtr[i]);
         double risk = tSl - tEntry;
         tradeEntry = tEntry; tradeSl = tSl; tradeTp1 = tEntry - risk * fixedTp1R; tradeTp2 = tEntry - risk * fixedTp2R; tradeTp3 = tEntry - risk * fixedTp3R;
         out[i].sell = true; newSell = true;
      }
      if(newBuy || newSell)
      {
         virtualTradeDir = newBuy ? 1 : -1; virtualEntryBar = i; virtualEntry = tradeEntry; virtualSl = tradeSl;
         virtualTp1 = tradeTp1; virtualTp2 = tradeTp2; virtualTp3 = tradeTp3; hitTp1 = false; hitTp2 = false; hitTp3 = false; virtualCellIdx = curCellIdx;
      }
      out[i].entry = tradeEntry; out[i].sl = tradeSl; out[i].tp1 = tradeTp1; out[i].tp2 = tradeTp2; out[i].tp3 = tradeTp3;

      if(virtualTradeDir != 0 && SATS_IsValid(virtualEntry) && SATS_IsValid(virtualSl) && i > virtualEntryBar)
      {
         bool tp1Reached = virtualTradeDir == 1 ? rates[i].high >= virtualTp1 : rates[i].low <= virtualTp1;
         bool tp2Reached = virtualTradeDir == 1 ? rates[i].high >= virtualTp2 : rates[i].low <= virtualTp2;
         bool tp3Reached = virtualTradeDir == 1 ? rates[i].high >= virtualTp3 : rates[i].low <= virtualTp3;
         bool slHit = virtualTradeDir == 1 ? rates[i].low <= virtualSl : rates[i].high >= virtualSl;
         bool timeoutHit = (i - virtualEntryBar) >= tradeMaxAge;
         if(tp1Reached && !hitTp1) hitTp1 = true; if(tp2Reached && !hitTp2) hitTp2 = true; if(tp3Reached && !hitTp3) hitTp3 = true;
         if(hitTp3 || slHit || timeoutHit)
         {
            double realizedR = (hitTp3 || slHit) ? SATS_CalcRealizedR(slHit, hitTp1, hitTp2, hitTp3, fixedTp1R, fixedTp2R, fixedTp3R) : SATS_CalcTimeoutR(hitTp1, hitTp2, hitTp3, fixedTp1R, fixedTp2R, fixedTp3R);
            realizedR = SATS_Clamp(realizedR, -1.0, fixedTp3R);
            if(signalCount < 100){ ArrayResize(signalRBuffer, signalCount + 1); signalRBuffer[signalCount] = realizedR; signalCount++; }
            else{ for(int q = 1; q < 100; q++) signalRBuffer[q - 1] = signalRBuffer[q]; signalRBuffer[99] = realizedR; }
            allTimeCumR += realizedR; if(allTimeCumR > allTimePeak) allTimePeak = allTimeCumR;
            double curDD = allTimeCumR - allTimePeak; if(curDD < allTimeTrough) allTimeTrough = curDD;
            if(realizedR > 0.0){ curWinStreak++; curLossStreak = 0; if(curWinStreak > maxWinStreak) maxWinStreak = curWinStreak; }
            else{ curLossStreak++; curWinStreak = 0; if(curLossStreak > maxLossStreak) maxLossStreak = curLossStreak; }
            if(virtualCellIdx >= 0 && virtualCellIdx < 9){ gridCount[virtualCellIdx]++; int c = gridCount[virtualCellIdx]; double prevEwm = gridEwm[virtualCellIdx]; gridEwm[virtualCellIdx] = c == 1 ? realizedR : prevEwm * 0.8 + realizedR * 0.2; }
            signalsSinceCalib++;
            int calibWindow = cfg.calibWindow > 0 ? cfg.calibWindow : 20, calibCooldown = cfg.calibCooldown > 0 ? cfg.calibCooldown : 5;
            if(cfg.useAutoCalib && signalCount >= calibWindow && signalsSinceCalib >= calibCooldown)
            {
               int startIdx = MathMax(0, signalCount - calibWindow); double sumR = 0.0; for(int q = startIdx; q < signalCount; q++) sumR += signalRBuffer[q];
               double postAvgR = sumR / (double)(signalCount - startIdx);
               if(postAvgR < cfg.calibBadR){ double drift = effectiveQualityStrength > cfg.qualityStrength ? -cfg.calibStepQ : cfg.calibStepQ; effectiveQualityStrength = SATS_Clamp(effectiveQualityStrength + drift, cfg.calibMinQ, cfg.calibMaxQ); signalsSinceCalib = 0; }
               else if(postAvgR > cfg.calibGoodR) signalsSinceCalib = 0;
            }
            virtualTradeDir = 0; virtualCellIdx = -1;
         }
      }
   }

   summary.qualityStrength = effectiveQualityStrength; summary.samples = signalCount; summary.allTimeR = allTimeCumR; summary.allTimeDD = allTimeTrough;
   summary.winStreak = curWinStreak; summary.lossStreak = curLossStreak; summary.maxWinStreak = maxWinStreak; summary.maxLossStreak = maxLossStreak;
   return n;
}

int SATS_Calculate(const MqlRates &rates[], const int n, const SATSSettings &cfg, SATSPoint &out[])
{
   SATSLearningSummary summary;
   return SATS_Calculate(rates, n, cfg, out, summary);
}
