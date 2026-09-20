#property strict

struct NasSettings
{
   int sensitivity;
   int rsiLength;
   int atrRisk;
   int atrLen;
};

struct NasPoint
{
   bool buy;
   bool sell;
   double superTrend;
   int direction;
   double sma8;
   double sma9;
   double sma13;
   double nasEntry;
   double nasSl;
   double nasTp1;
   double nasTp2;
   double nasTp3;
};

double NAS_Empty()
{
   return EMPTY_VALUE;
}

bool NAS_IsValid(const double v)
{
   return MathIsValidNumber(v) && v != EMPTY_VALUE;
}

double NAS_Nz(const double v, const double fallback = 0.0)
{
   return NAS_IsValid(v) ? v : fallback;
}

double NAS_TrueRange(const MqlRates &rates[], const int i)
{
   if(i <= 0)
      return rates[i].high - rates[i].low;
   double hl = rates[i].high - rates[i].low;
   double hc = MathAbs(rates[i].high - rates[i - 1].close);
   double lc = MathAbs(rates[i].low - rates[i - 1].close);
   return MathMax(hl, MathMax(hc, lc));
}

void NAS_WilderATR(const MqlRates &rates[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double tr[];
   ArrayResize(tr, n);
   for(int i = 0; i < n; i++)
   {
      tr[i] = NAS_TrueRange(rates, i);
      if(len <= 1)
         out[i] = tr[i];
      else if(i < len - 1)
         out[i] = NAS_Empty();
      else if(i == len - 1)
      {
         double sum = 0.0;
         for(int k = 0; k <= i; k++)
            sum += tr[k];
         out[i] = sum / (double)len;
      }
      else
         out[i] = (out[i - 1] * (len - 1) + tr[i]) / (double)len;
   }
}

double NAS_SMA(const double &arr[], const int i, const int len)
{
   if(i < len - 1)
      return NAS_Empty();
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; k++)
   {
      if(!NAS_IsValid(arr[k]))
         return NAS_Empty();
      sum += arr[k];
   }
   return sum / (double)len;
}

bool NAS_Crossover(const double a, const double b, const double prevA, const double prevB)
{
   if(!NAS_IsValid(a) || !NAS_IsValid(b) || !NAS_IsValid(prevA) || !NAS_IsValid(prevB))
      return false;
   return a > b && prevA <= prevB;
}

bool NAS_Crossunder(const double a, const double b, const double prevA, const double prevB)
{
   if(!NAS_IsValid(a) || !NAS_IsValid(b) || !NAS_IsValid(prevA) || !NAS_IsValid(prevB))
      return false;
   return a < b && prevA >= prevB;
}

int NAS_Calculate(const MqlRates &rates[], const int n, const NasSettings &cfg, NasPoint &out[])
{
   if(n <= 0)
      return 0;

   ArrayResize(out, n);

   double closeArr[], atr11[], atrRiskSeries[], lowerBand[], upperBand[], st[];
   ArrayResize(closeArr, n);
   ArrayResize(lowerBand, n);
   ArrayResize(upperBand, n);
   ArrayResize(st, n);

   for(int i = 0; i < n; i++)
      closeArr[i] = rates[i].close;

   NAS_WilderATR(rates, n, 11, atr11);
   NAS_WilderATR(rates, n, cfg.atrLen, atrRiskSeries);
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

      double upperRaw = NAS_IsValid(atr11[i]) ? rates[i].close + (double)cfg.sensitivity * atr11[i] : NAS_Empty();
      double lowerRaw = NAS_IsValid(atr11[i]) ? rates[i].close - (double)cfg.sensitivity * atr11[i] : NAS_Empty();

      double prevLower = (i > 0 ? NAS_Nz(lowerBand[i - 1], 0.0) : 0.0);
      double prevUpper = (i > 0 ? NAS_Nz(upperBand[i - 1], 0.0) : 0.0);
      bool lowerCond = NAS_IsValid(lowerRaw) && (lowerRaw > prevLower || (i > 0 && rates[i - 1].close < prevLower));
      bool upperCond = NAS_IsValid(upperRaw) && (upperRaw < prevUpper || (i > 0 && rates[i - 1].close > prevUpper));

      lowerBand[i] = lowerCond ? lowerRaw : prevLower;
      upperBand[i] = upperCond ? upperRaw : prevUpper;

      int direction = 1;
      double prevSuperTrend = (i > 0 ? st[i - 1] : NAS_Empty());
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
                  && NAS_IsValid(out[i].sma13)
                  && rates[i].close >= out[i].sma13;
      bool bear = i > 0
                  && NAS_Crossunder(rates[i].close, st[i], rates[i - 1].close, st[i - 1])
                  && NAS_IsValid(out[i].sma13)
                  && rates[i].close <= out[i].sma13;

      out[i].buy = bull;
      out[i].sell = bear;

      int countBull = bull ? 0 : (lastBull < 0 ? i : i - lastBull);
      int countBear = bear ? 0 : (lastBear < 0 ? i : i - lastBear);
      int trigger = countBull < countBear ? 1 : 0;
      double atrBand = NAS_IsValid(atrRiskSeries[i]) ? atrRiskSeries[i] * (double)cfg.atrRisk : NAS_Empty();
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
         out[i].nasTp1 = (lastEntry - lastStop) * 1.0 + lastEntry;
         out[i].nasTp2 = (lastEntry - lastStop) * 2.0 + lastEntry;
         out[i].nasTp3 = (lastEntry - lastStop) * 3.0 + lastEntry;
      }
   }

   return n;
}
