#property strict

#include "NasUltimate_Core.mqh"

struct NasV2Settings
{
   NasSettings base;
   bool adaptiveSuperTrend;
   int fastAtrLen;
   int slowAtrLen;
   double adaptiveBase;
   double adaptiveVolWeight;
   double minMultiplier;
   double maxMultiplier;
};

struct NasV2LearningStats
{
   int wins;
   int losses;
   int unresolved;
   double winRate;
   double confidence;
};

double NASV2_Clamp(const double value, const double low, const double high)
{
   return MathMax(low, MathMin(high, value));
}

double NASV2_ATRAt(const MqlRates &rates[], const int index, const int length)
{
   int len = MathMax(1, length);
   if(index < len - 1)
      return 0.0;
   double value = 0.0;
   for(int i = 0; i <= index; i++)
   {
      double tr = NAS_TrueRange(rates, i);
      if(i < len - 1)
         continue;
      if(i == len - 1)
      {
         double sum = 0.0;
         for(int k = 0; k <= i; k++)
            sum += NAS_TrueRange(rates, k);
         value = sum / (double)len;
      }
      else
         value = (value * (len - 1) + tr) / (double)len;
   }
   return value;
}

double NASV2_RSIAt(const MqlRates &rates[], const int index, const int length)
{
   int len = MathMax(2, length);
   if(index < len)
      return 50.0;
   double avgGain = 0.0;
   double avgLoss = 0.0;
   for(int i = 1; i <= index; i++)
   {
      double change = rates[i].close - rates[i - 1].close;
      double gain = MathMax(0.0, change);
      double loss = MathMax(0.0, -change);
      if(i < len)
         continue;
      if(i == len)
      {
         double gainSum = 0.0;
         double lossSum = 0.0;
         for(int k = 1; k <= len; k++)
         {
            double seedChange = rates[k].close - rates[k - 1].close;
            gainSum += MathMax(0.0, seedChange);
            lossSum += MathMax(0.0, -seedChange);
         }
         avgGain = gainSum / (double)len;
         avgLoss = lossSum / (double)len;
      }
      else
      {
         avgGain = (avgGain * (len - 1) + gain) / (double)len;
         avgLoss = (avgLoss * (len - 1) + loss) / (double)len;
      }
   }
   if(avgLoss <= 0.0)
      return avgGain > 0.0 ? 100.0 : 50.0;
   double rs = avgGain / avgLoss;
   return 100.0 - 100.0 / (1.0 + rs);
}

double NASV2_AdaptiveMultiplier(const double fastAtr, const double slowAtr, const NasV2Settings &cfg)
{
   double fallback = MathMax(0.1, (double)cfg.base.sensitivity);
   if(!cfg.adaptiveSuperTrend || fastAtr <= 0.0 || slowAtr <= 0.0)
      return fallback;
   double ratio = fastAtr / slowAtr;
   double value = cfg.adaptiveBase + ratio * cfg.adaptiveVolWeight;
   return NASV2_Clamp(value, cfg.minMultiplier, cfg.maxMultiplier);
}

int NASV2_Calculate(const MqlRates &rates[], const int n, const NasV2Settings &cfg, NasPoint &out[])
{
   if(n <= 0)
      return 0;

   ArrayResize(out, n);
   double closeArr[], atr11[], atrFast[], atrSlow[], atrRiskSeries[], lowerBand[], upperBand[], st[];
   ArrayResize(closeArr, n);
   ArrayResize(lowerBand, n);
   ArrayResize(upperBand, n);
   ArrayResize(st, n);
   for(int i = 0; i < n; i++)
      closeArr[i] = rates[i].close;

   NAS_WilderATR(rates, n, 11, atr11);
   NAS_WilderATR(rates, n, MathMax(2, cfg.fastAtrLen), atrFast);
   NAS_WilderATR(rates, n, MathMax(3, cfg.slowAtrLen), atrSlow);
   NAS_WilderATR(rates, n, cfg.base.atrLen, atrRiskSeries);

   int lastBull = -1;
   int lastBear = -1;
   double lastEntry = NAS_Empty();
   double lastStop = NAS_Empty();

   for(int i = 0; i < n; i++)
   {
      out[i].buy = false;
      out[i].sell = false;
      out[i].superTrend = NAS_Empty();
      out[i].direction = 0;
      out[i].sma8 = NAS_SMA(closeArr, i, 8);
      out[i].sma9 = NAS_SMA(closeArr, i, 9);
      out[i].sma13 = NAS_SMA(closeArr, i, 13);
      out[i].nasEntry = lastEntry;
      out[i].nasSl = lastStop;
      out[i].nasTp1 = out[i].nasTp2 = out[i].nasTp3 = NAS_Empty();

      double factor = NASV2_AdaptiveMultiplier(
         NAS_IsValid(atrFast[i]) ? atrFast[i] : 0.0,
         NAS_IsValid(atrSlow[i]) ? atrSlow[i] : 0.0,
         cfg
      );
      double upperRaw = NAS_IsValid(atr11[i]) ? rates[i].close + factor * atr11[i] : NAS_Empty();
      double lowerRaw = NAS_IsValid(atr11[i]) ? rates[i].close - factor * atr11[i] : NAS_Empty();
      double prevLower = i > 0 ? NAS_Nz(lowerBand[i - 1], 0.0) : 0.0;
      double prevUpper = i > 0 ? NAS_Nz(upperBand[i - 1], 0.0) : 0.0;
      bool lowerCond = NAS_IsValid(lowerRaw) && (lowerRaw > prevLower || (i > 0 && rates[i - 1].close < prevLower));
      bool upperCond = NAS_IsValid(upperRaw) && (upperRaw < prevUpper || (i > 0 && rates[i - 1].close > prevUpper));
      lowerBand[i] = lowerCond ? lowerRaw : prevLower;
      upperBand[i] = upperCond ? upperRaw : prevUpper;

      int direction = 1;
      double prevSuperTrend = i > 0 ? st[i - 1] : NAS_Empty();
      if(i == 0 || !NAS_IsValid(atr11[i - 1]))
         direction = 1;
      else if(NAS_IsValid(prevSuperTrend) && prevSuperTrend == prevUpper)
         direction = rates[i].close > upperBand[i] ? -1 : 1;
      else
         direction = rates[i].close < lowerBand[i] ? 1 : -1;

      st[i] = direction == -1 ? lowerBand[i] : upperBand[i];
      out[i].direction = direction;
      out[i].superTrend = st[i];
      bool bull = i > 0
         && NAS_Crossover(rates[i].close, st[i], rates[i - 1].close, st[i - 1])
         && NAS_IsValid(out[i].sma13) && rates[i].close >= out[i].sma13;
      bool bear = i > 0
         && NAS_Crossunder(rates[i].close, st[i], rates[i - 1].close, st[i - 1])
         && NAS_IsValid(out[i].sma13) && rates[i].close <= out[i].sma13;
      out[i].buy = bull;
      out[i].sell = bear;

      int countBull = bull ? 0 : (lastBull < 0 ? i : i - lastBull);
      int countBear = bear ? 0 : (lastBear < 0 ? i : i - lastBear);
      int trigger = countBull < countBear ? 1 : 0;
      double atrBand = NAS_IsValid(atrRiskSeries[i]) ? atrRiskSeries[i] * (double)cfg.base.atrRisk : NAS_Empty();
      double atrStop = NAS_IsValid(atrBand) ? (trigger == 1 ? rates[i].low - atrBand : rates[i].high + atrBand) : NAS_Empty();
      if(bull || bear)
      {
         lastEntry = rates[i].close;
         lastStop = atrStop;
      }
      if(bull)
         lastBull = i;
      if(bear)
         lastBear = i;

      out[i].nasEntry = lastEntry;
      out[i].nasSl = lastStop;
      if(NAS_IsValid(lastEntry) && NAS_IsValid(lastStop))
      {
         out[i].nasTp1 = (lastEntry - lastStop) + lastEntry;
         out[i].nasTp2 = (lastEntry - lastStop) * 2.0 + lastEntry;
         out[i].nasTp3 = (lastEntry - lastStop) * 3.0 + lastEntry;
      }
   }
   return n;
}

NasV2LearningStats NASV2_WalkForwardStats(
   const MqlRates &rates[],
   const NasPoint &points[],
   const int currentIndex,
   const int lookbackBars,
   const int resolutionBars
)
{
   NasV2LearningStats stats;
   stats.wins = 0;
   stats.losses = 0;
   stats.unresolved = 0;
   stats.winRate = 0.5;
   stats.confidence = 0.0;
   int horizon = MathMax(2, resolutionBars);
   int first = MathMax(1, currentIndex - MathMax(100, lookbackBars));
   int lastSignal = currentIndex - horizon;
   for(int i = first; i <= lastSignal; i++)
   {
      int direction = points[i].buy ? 1 : (points[i].sell ? -1 : 0);
      if(direction == 0 || !NAS_IsValid(points[i].nasSl) || !NAS_IsValid(points[i].nasTp1))
         continue;
      bool resolved = false;
      int end = MathMin(currentIndex - 1, i + horizon);
      for(int j = i + 1; j <= end; j++)
      {
         bool tpHit = direction > 0 ? rates[j].high >= points[i].nasTp1 : rates[j].low <= points[i].nasTp1;
         bool slHit = direction > 0 ? rates[j].low <= points[i].nasSl : rates[j].high >= points[i].nasSl;
         if(tpHit && slHit)
         {
            stats.losses++;
            resolved = true;
            break;
         }
         if(slHit)
         {
            stats.losses++;
            resolved = true;
            break;
         }
         if(tpHit)
         {
            stats.wins++;
            resolved = true;
            break;
         }
      }
      if(!resolved)
         stats.unresolved++;
   }
   int samples = stats.wins + stats.losses;
   if(samples > 0)
      stats.winRate = (double)stats.wins / (double)samples;
   stats.confidence = NASV2_Clamp((double)samples / 30.0, 0.0, 1.0);
   return stats;
}
