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

bool CEMKA_PivotHigh(const MqlRates &rates[], const int n, const int confirmIndex, const int len, double &value)
{
   value = NAS_Empty();
   int p = confirmIndex - len;
   if(p < len || p + len >= n)
      return false;
   double v = rates[p].high;
   for(int i = p - len; i <= p + len; i++)
   {
      if(i == p)
         continue;
      if(rates[i].high > v)
         return false;
   }
   value = v;
   return true;
}

bool CEMKA_PivotLow(const MqlRates &rates[], const int n, const int confirmIndex, const int len, double &value)
{
   value = NAS_Empty();
   int p = confirmIndex - len;
   if(p < len || p + len >= n)
      return false;
   double v = rates[p].low;
   for(int i = p - len; i <= p + len; i++)
   {
      if(i == p)
         continue;
      if(rates[i].low < v)
         return false;
   }
   value = v;
   return true;
}

int NAS_Calculate(const MqlRates &rates[], const int n, const NasSettings &cfg, NasPoint &out[])
{
   if(n <= 0)
      return 0;

   ArrayResize(out, n);
   double closeArr[], atr[];
   ArrayResize(closeArr, n);
   for(int i = 0; i < n; i++)
      closeArr[i] = rates[i].close;

   // Pine source: "MEGA TREND LINES" section.
   // prd=2, Factor=3, Pd=10, bsignal = Trend==1 && Trend[1]==-1, ssignal = Trend==-1 && Trend[1]==1.
   const int prd = 2;
   const double factor = 3.0;
   const int pd = 10;
   NAS_WilderATR(rates, n, pd, atr);

   double center = NAS_Empty();
   double prevTUp = NAS_Empty();
   double prevTDown = NAS_Empty();
   int prevTrend = 0;
   double lastEntry = NAS_Empty();
   double lastStop = NAS_Empty();
   int lastDirection = 0;

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

      double ph = NAS_Empty();
      double pl = NAS_Empty();
      bool hasPh = CEMKA_PivotHigh(rates, n, i, prd, ph);
      bool hasPl = CEMKA_PivotLow(rates, n, i, prd, pl);
      double lastpp = hasPh ? ph : (hasPl ? pl : NAS_Empty());
      if(NAS_IsValid(lastpp))
      {
         if(!NAS_IsValid(center))
            center = lastpp;
         else
            center = (center * 2.0 + lastpp) / 3.0;
      }

      double up = (NAS_IsValid(center) && NAS_IsValid(atr[i])) ? center - factor * atr[i] : NAS_Empty();
      double dn = (NAS_IsValid(center) && NAS_IsValid(atr[i])) ? center + factor * atr[i] : NAS_Empty();

      double tUp = up;
      double tDown = dn;
      if(i > 0 && NAS_IsValid(prevTUp) && rates[i - 1].close > prevTUp && NAS_IsValid(up))
         tUp = MathMax(up, prevTUp);
      if(i > 0 && NAS_IsValid(prevTDown) && rates[i - 1].close < prevTDown && NAS_IsValid(dn))
         tDown = MathMin(dn, prevTDown);

      int trend = prevTrend == 0 ? 1 : prevTrend;
      if(NAS_IsValid(prevTDown) && rates[i].close > prevTDown)
         trend = 1;
      else if(NAS_IsValid(prevTUp) && rates[i].close < prevTUp)
         trend = -1;

      double trailingSl = trend == 1 ? tUp : tDown;
      bool bsignal = trend == 1 && prevTrend == -1;
      bool ssignal = trend == -1 && prevTrend == 1;

      out[i].buy = bsignal;
      out[i].sell = ssignal;
      out[i].direction = trend;
      out[i].superTrend = trailingSl;

      if(bsignal || ssignal)
      {
         lastDirection = bsignal ? 1 : -1;
         lastEntry = rates[i].close;
         lastStop = trailingSl;
         if(!NAS_IsValid(lastStop) || (lastDirection > 0 && lastStop >= lastEntry) || (lastDirection < 0 && lastStop <= lastEntry))
         {
            double riskAtr = NAS_IsValid(atr[i]) ? atr[i] * MathMax(1, cfg.atrRisk) : NAS_Empty();
            if(NAS_IsValid(riskAtr))
               lastStop = lastDirection > 0 ? rates[i].low - riskAtr : rates[i].high + riskAtr;
         }
      }

      out[i].nasEntry = lastEntry;
      out[i].nasSl = lastStop;
      if(NAS_IsValid(lastEntry) && NAS_IsValid(lastStop) && lastDirection != 0)
      {
         double risk = MathAbs(lastEntry - lastStop);
         out[i].nasTp1 = lastDirection > 0 ? lastEntry + risk * 1.0 : lastEntry - risk * 1.0;
         out[i].nasTp2 = lastDirection > 0 ? lastEntry + risk * 2.0 : lastEntry - risk * 2.0;
         out[i].nasTp3 = lastDirection > 0 ? lastEntry + risk * 3.0 : lastEntry - risk * 3.0;
      }

      prevTUp = tUp;
      prevTDown = tDown;
      prevTrend = trend;
   }

   return n;
}