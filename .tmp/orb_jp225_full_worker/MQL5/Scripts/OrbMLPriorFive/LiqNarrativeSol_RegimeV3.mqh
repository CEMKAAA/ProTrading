#ifndef LIQ_NARRATIVE_SOL_REGIME_V3_MQH
#define LIQ_NARRATIVE_SOL_REGIME_V3_MQH

input group "Regime V3 Observer"
input bool InpRegimeV3Observer = true;
input int  InpRegimeV3HistorySessions = 2200;
input int  InpRegimeV3RetrySeconds = 30;

#define REGIME_V3_TREND_ENTER 0.62
#define REGIME_V3_TREND_EXIT 0.42
#define REGIME_V3_TREND_DECISIVE_HIGH 0.76
#define REGIME_V3_TREND_DECISIVE_LOW 0.28
#define REGIME_V3_VOL_ENTER 0.62
#define REGIME_V3_VOL_EXIT 0.42
#define REGIME_V3_VOL_DECISIVE_HIGH 0.76
#define REGIME_V3_VOL_DECISIVE_LOW 0.28
#define REGIME_V3_FAST_CONFIRM 3
#define REGIME_V3_NORMAL_CONFIRM 5
#define REGIME_V3_DIRECTION_ENTER_Z 0.35
#define REGIME_V3_DIRECTION_DECISIVE_Z 0.75

struct RegimeV3Snapshot
{
   bool     valid;
   datetime availableTime;
   string   core;
   int      effectiveAge;
   int      confirmedAge;
   string   ageBucket;
   string   transitionStatus;
   string   transitionType;
   string   transitionCandidate;
   int      transitionPending;
   int      transitionRequired;
   double   transitionConfidence;
   string   macroDirection;
   string   directionPending;
   int      directionPendingSessions;
   string   h1h2Phase;
   string   volatilityDepth;
   string   volatilityImpulse;
   string   structuralHint;
   double   trendDepthScore;
   double   volatilityDepthScore;
   string   detail;
};

RegimeV3Snapshot g_regimeV3;
RegimeV3Snapshot g_regimeV3Timeline[];
datetime g_regimeV3LastSourceOpen = 0;
datetime g_regimeV3LastAttemptLocal = 0;
string   g_regimeV3LastLogSignature = "";

bool RegimeV3Finite(double value)
{
   return MathIsValidNumber(value) && value != DBL_MAX && value != -DBL_MAX;
}

double RegimeV3Clamp01(double value)
{
   if(!RegimeV3Finite(value)) return 0.0;
   return MathMax(0.0, MathMin(1.0, value));
}

int RegimeV3Sign(double value)
{
   if(value > 0.0) return 1;
   if(value < 0.0) return -1;
   return 0;
}

string RegimeV3DirectionName(int direction)
{
   if(direction > 0) return "UP";
   if(direction < 0) return "DOWN";
   return "UNKNOWN";
}

string RegimeV3AgeBucket(int age)
{
   if(age <= 10) return "FRESH";
   if(age <= 40) return "ESTABLISHED";
   if(age <= 80) return "MATURE";
   return "LATE";
}

int RegimeV3UpperBoundTime(const MqlRates &rates[], datetime value)
{
   int left = 0;
   int right = ArraySize(rates);
   while(left < right)
   {
      int mid = left + (right - left) / 2;
      if(rates[mid].time <= value) left = mid + 1;
      else right = mid;
   }
   return left;
}

bool RegimeV3TfReturn(const MqlRates &rates[], datetime available, datetime anchorTime, int barSeconds, double &value)
{
   value = 0.0;
   // Select the newest bar guaranteed closed at available. The old index
   // depended on whether MT5 had synchronized the newly opened bar.
   int safeBarSeconds = MathMax(1, barSeconds);
   int currentIndex = RegimeV3UpperBoundTime(rates, available - safeBarSeconds) - 1;
   int anchorIndex = RegimeV3UpperBoundTime(rates, anchorTime) - 1;
   if(currentIndex < 0 || anchorIndex < 0 || currentIndex >= ArraySize(rates) || anchorIndex >= ArraySize(rates))
      return false;
   double currentClose = rates[currentIndex].close;
   double anchorClose = rates[anchorIndex].close;
   if(currentClose <= 0.0 || anchorClose <= 0.0) return false;
   value = (currentClose / anchorClose - 1.0) * 100.0;
   return RegimeV3Finite(value);
}

double RegimeV3Median2(double a, double b)
{
   return (a + b) * 0.5;
}

double RegimeV3Median4(double a, double b, double c, double d)
{
   double values[4] = {a, b, c, d};
   for(int i = 0; i < 3; ++i)
      for(int j = i + 1; j < 4; ++j)
         if(values[j] < values[i])
         {
            double tmp = values[i];
            values[i] = values[j];
            values[j] = tmp;
         }
   return (values[1] + values[2]) * 0.5;
}

double RegimeV3RealizedVol(const MqlRates &daily[], int index, int count)
{
   if(index < count || count < 2) return 0.0;
   double sum = 0.0;
   int n = 0;
   for(int i = index - count + 1; i <= index; ++i)
   {
      if(i <= 0 || daily[i - 1].close <= 0.0 || daily[i].close <= 0.0) continue;
      sum += MathLog(daily[i].close / daily[i - 1].close);
      n++;
   }
   if(n < 2) return 0.0;
   double mean = sum / n;
   double squared = 0.0;
   for(int i = index - count + 1; i <= index; ++i)
   {
      if(i <= 0 || daily[i - 1].close <= 0.0 || daily[i].close <= 0.0) continue;
      double value = MathLog(daily[i].close / daily[i - 1].close);
      squared += (value - mean) * (value - mean);
   }
   return MathSqrt(squared / (n - 1));
}

double RegimeV3Efficiency(const MqlRates &daily[], int index, int horizon)
{
   int first = index - horizon;
   if(first < 0 || index >= ArraySize(daily)) return 0.0;
   double travel = 0.0;
   for(int i = first + 1; i <= index; ++i)
      travel += MathAbs(daily[i].close - daily[i - 1].close);
   if(travel <= 0.0) return 0.0;
   return MathAbs(daily[index].close - daily[first].close) / travel;
}

double RegimeV3TrailingPercentile(const double &history[], int currentIndex, bool &valid)
{
   valid = false;
   if(currentIndex < 59 || currentIndex >= ArraySize(history)) return 0.0;
   int first = MathMax(0, currentIndex - 251);
   int count = 0;
   int lessOrEqual = 0;
   double current = history[currentIndex];
   for(int i = first; i <= currentIndex; ++i)
   {
      if(!RegimeV3Finite(history[i])) continue;
      count++;
      if(history[i] <= current) lessOrEqual++;
   }
   if(count < 60) return 0.0;
   valid = true;
   return (double)lessOrEqual / (double)count;
}

bool RegimeV3IsTrend(string core)
{
   return StringFind(core, "TREND") == 0;
}

bool RegimeV3IsHighVol(string core)
{
   return StringFind(core, "HIGH_VOL") >= 0;
}

string RegimeV3TransitionType(string active, string candidate)
{
   if(active == "" || candidate == "" || active == candidate) return "NONE";
   bool trendChanged = RegimeV3IsTrend(active) != RegimeV3IsTrend(candidate);
   bool volChanged = RegimeV3IsHighVol(active) != RegimeV3IsHighVol(candidate);
   if(trendChanged && volChanged) return "COMPOUND";
   if(trendChanged) return RegimeV3IsTrend(candidate) ? "RANGE_TO_TREND" : "TREND_TO_RANGE";
   return RegimeV3IsHighVol(candidate) ? "VOL_EXPANSION" : "VOL_CONTRACTION";
}

string RegimeV3ClassifyVolatility(double score, double ratio20, double percentile, bool percentileValid)
{
   if(score >= 0.85 || ratio20 >= 1.50 || (percentileValid && percentile >= 0.90)) return "EXTREME";
   if(score >= REGIME_V3_VOL_ENTER) return "ELEVATED";
   if(score <= 0.28 && (!percentileValid || percentile <= 0.35)) return "COMPRESSED";
   return "NORMAL";
}

string RegimeV3ClassifyPhase(double fastZ, double mediumZ, bool fastAgreement, bool mediumAgreement,
   int direction, int pendingDirection, int pendingDirectionCount)
{
   if(direction == 0) return "NEUTRAL_ROTATION";
   double fast = direction * fastZ;
   double medium = direction * mediumZ;
   if(pendingDirection == -direction && pendingDirectionCount >= 2) return "REVERSAL_PRESSURE";
   if(medium <= -0.35 && fast <= -0.35 && mediumAgreement) return "REVERSAL_PRESSURE";
   if(fast <= -0.75) return direction > 0 ? "DEEP_PULLBACK" : "DEEP_REBOUND";
   if(fast <= -0.20) return direction > 0 ? "SHALLOW_PULLBACK" : "SHALLOW_REBOUND";
   if(fast >= 0.75 && fastAgreement) return "ALIGNED_IMPULSE";
   if(fast >= 0.20) return "ALIGNED";
   return "NEUTRAL_ROTATION";
}

string RegimeV3StructuralHint(string core, string status, string phase, string volDepth, string ageBucket)
{
   if(status == "WATCH" || status == "DEVELOPING") return "TRANSITION_UNCERTAIN";
   if(phase == "REVERSAL_PRESSURE") return "REVERSAL_RISK";
   if(ageBucket == "FRESH" && volDepth == "EXTREME") return "PRICE_DISCOVERY_RISK";
   if(RegimeV3IsTrend(core) && (phase == "ALIGNED" || phase == "ALIGNED_IMPULSE"))
      return "TREND_CONTINUATION_SUPPORT";
   if(RegimeV3IsTrend(core) && (StringFind(phase, "PULLBACK") >= 0 || StringFind(phase, "REBOUND") >= 0))
      return "TREND_RETRACE_SETUP";
   if(!RegimeV3IsTrend(core) && volDepth == "COMPRESSED") return "RANGE_COMPRESSION";
   if(!RegimeV3IsTrend(core) && (volDepth == "ELEVATED" || volDepth == "EXTREME"))
      return "RANGE_EXPANSION_RISK";
   return "NEUTRAL_STRUCTURE";
}

bool RegimeV3LoadRates(MqlRates &d1[], MqlRates &h1[], MqlRates &h2[], MqlRates &h4[], string &reason)
{
   reason = "";
   int requested = MathMax(400, InpRegimeV3HistorySessions + 102);
   int dCount = CopyRates(_Symbol, PERIOD_D1, D'2021.09.09 00:00:00', requested, d1);
   ArraySetAsSeries(d1, false);
   if(dCount < 202)
   {
      reason = "D1_HISTORY_" + IntegerToString(dCount);
      return false;
   }
   datetime from = d1[0].time - 86400;
   datetime until = D'2021.09.09 00:00:00' + 86400;
   int h1Count = CopyRates(_Symbol, PERIOD_H1, from, until, h1);
   int h2Count = CopyRates(_Symbol, PERIOD_H2, from, until, h2);
   int h4Count = CopyRates(_Symbol, PERIOD_H4, from, until, h4);
   ArraySetAsSeries(h1, false);
   ArraySetAsSeries(h2, false);
   ArraySetAsSeries(h4, false);
   if(h1Count < 100 || h2Count < 100 || h4Count < 100)
   {
      reason = "MTF_HISTORY_" + IntegerToString(h1Count) + "_" + IntegerToString(h2Count) + "_" + IntegerToString(h4Count);
      return false;
   }
   return true;
}

bool RegimeV3Rebuild(RegimeV3Snapshot &snapshot, RegimeV3Snapshot &timeline[])
{
   ArrayFree(timeline);
   snapshot.valid = false;
   snapshot.detail = "LOADING";
   MqlRates d1[], h1[], h2[], h4[];
   string loadReason = "";
   if(!RegimeV3LoadRates(d1, h1, h2, h4, loadReason))
   {
      snapshot.detail = loadReason;
      return false;
   }

   bool trendOn = false;
   bool highVol = false;
   string activeCore = "";
   string pendingCore = "";
   int pendingCount = 0;
   int pendingRequired = 0;
   int effectiveAge = 0;
   int confirmedAge = 0;
   int direction = 0;
   int pendingDirection = 0;
   int pendingDirectionCount = 0;
   int pendingDirectionRequired = 0;
   double rv20History[];
   int rvCount = 0;
   int rowsBuilt = 0;

   for(int index = 100; index < ArraySize(d1) - 1; ++index)
   {
      datetime available = d1[index + 1].time;
      double ret5[4], ret20[4], ret100[4];
      datetime anchor5 = d1[index - 5].time;
      datetime anchor20 = d1[index - 20].time;
      datetime anchor100 = d1[index - 100].time;
      bool ok = true;
      ok = ok && RegimeV3TfReturn(h1, available, anchor5, PeriodSeconds(PERIOD_H1), ret5[0]);
      ok = ok && RegimeV3TfReturn(h2, available, anchor5, PeriodSeconds(PERIOD_H2), ret5[1]);
      ok = ok && RegimeV3TfReturn(h4, available, anchor5, PeriodSeconds(PERIOD_H4), ret5[2]);
      ok = ok && RegimeV3TfReturn(d1, available, anchor5, PeriodSeconds(PERIOD_D1), ret5[3]);
      ok = ok && RegimeV3TfReturn(h1, available, anchor20, PeriodSeconds(PERIOD_H1), ret20[0]);
      ok = ok && RegimeV3TfReturn(h2, available, anchor20, PeriodSeconds(PERIOD_H2), ret20[1]);
      ok = ok && RegimeV3TfReturn(h4, available, anchor20, PeriodSeconds(PERIOD_H4), ret20[2]);
      ok = ok && RegimeV3TfReturn(d1, available, anchor20, PeriodSeconds(PERIOD_D1), ret20[3]);
      ok = ok && RegimeV3TfReturn(h1, available, anchor100, PeriodSeconds(PERIOD_H1), ret100[0]);
      ok = ok && RegimeV3TfReturn(h2, available, anchor100, PeriodSeconds(PERIOD_H2), ret100[1]);
      ok = ok && RegimeV3TfReturn(h4, available, anchor100, PeriodSeconds(PERIOD_H4), ret100[2]);
      ok = ok && RegimeV3TfReturn(d1, available, anchor100, PeriodSeconds(PERIOD_D1), ret100[3]);
      if(!ok) continue;

      double rv20 = RegimeV3RealizedVol(d1, index, 20);
      double rv60 = RegimeV3RealizedVol(d1, index, 60);
      double rv100 = RegimeV3RealizedVol(d1, index, 100);
      if(rv20 <= 0.0 || rv60 <= 0.0 || rv100 <= 0.0) continue;
      ArrayResize(rv20History, rvCount + 1);
      rv20History[rvCount] = rv20;
      bool percentileValid = false;
      double percentile = RegimeV3TrailingPercentile(rv20History, rvCount, percentileValid);
      rvCount++;

      double all100 = RegimeV3Median4(ret100[0], ret100[1], ret100[2], ret100[3]);
      double noise100 = rv100 * MathSqrt(100.0) * 100.0;
      double macroZ = noise100 > 0.0 ? all100 / noise100 : 0.0;
      double efficiency100 = RegimeV3Efficiency(d1, index, 100);
      bool slowAgreement = RegimeV3Sign(ret100[2]) != 0 && RegimeV3Sign(ret100[2]) == RegimeV3Sign(ret100[3]);
      int macroSign = RegimeV3Sign(all100);
      int persistenceCount = 0;
      for(int p = 0; p < 4; ++p)
         if(macroSign != 0 && RegimeV3Sign(ret20[p]) == macroSign) persistenceCount++;
      double directionalPersistence = (double)persistenceCount / 4.0;
      double trendScore = 0.40 * RegimeV3Clamp01(MathAbs(macroZ) / 1.50)
         + 0.30 * RegimeV3Clamp01(efficiency100 / 0.35)
         + 0.15 * (slowAgreement ? 1.0 : 0.0)
         + 0.15 * directionalPersistence;

      double ratio20 = rv20 / rv100;
      double ratio60 = rv60 / rv100;
      double percentileForScore = percentileValid ? percentile : 0.50;
      double volScore = 0.40 * RegimeV3Clamp01((ratio60 - 0.75) / 0.70)
         + 0.35 * RegimeV3Clamp01(percentileForScore)
         + 0.25 * RegimeV3Clamp01((ratio20 - 0.75) / 0.80);
      double volImpulse = ratio20 - ratio60;

      bool targetTrend = trendOn ? trendScore >= REGIME_V3_TREND_EXIT : trendScore >= REGIME_V3_TREND_ENTER;
      bool targetHighVol = highVol ? volScore >= REGIME_V3_VOL_EXIT : volScore >= REGIME_V3_VOL_ENTER;
      string candidate = (targetTrend ? "TREND" : "RANGE") + (targetHighVol ? "_HIGH_VOL" : "_LOW_VOL");
      bool switchEvent = false;
      string switchedType = "NONE";

      if(activeCore == "")
      {
         trendOn = targetTrend;
         highVol = targetHighVol;
         activeCore = candidate;
         effectiveAge = 1;
         confirmedAge = 1;
      }
      else if(candidate == activeCore)
      {
         pendingCore = "";
         pendingCount = 0;
         pendingRequired = 0;
         effectiveAge++;
         confirmedAge++;
      }
      else
      {
         bool changedTrend = RegimeV3IsTrend(candidate) != RegimeV3IsTrend(activeCore);
         bool changedVol = RegimeV3IsHighVol(candidate) != RegimeV3IsHighVol(activeCore);
         bool decisiveTrend = !changedTrend
            || (RegimeV3IsTrend(candidate) && trendScore >= REGIME_V3_TREND_DECISIVE_HIGH)
            || (!RegimeV3IsTrend(candidate) && trendScore <= REGIME_V3_TREND_DECISIVE_LOW);
         bool decisiveVol = !changedVol
            || (RegimeV3IsHighVol(candidate) && volScore >= REGIME_V3_VOL_DECISIVE_HIGH)
            || (!RegimeV3IsHighVol(candidate) && volScore <= REGIME_V3_VOL_DECISIVE_LOW);
         int required = decisiveTrend && decisiveVol ? REGIME_V3_FAST_CONFIRM : REGIME_V3_NORMAL_CONFIRM;
         if(candidate == pendingCore)
            pendingCount++;
         else
         {
            pendingCore = candidate;
            pendingCount = 1;
            pendingRequired = required;
         }
         effectiveAge++;
         confirmedAge++;
         if(pendingCount >= pendingRequired)
         {
            switchedType = RegimeV3TransitionType(activeCore, candidate);
            trendOn = RegimeV3IsTrend(candidate);
            highVol = RegimeV3IsHighVol(candidate);
            activeCore = candidate;
            effectiveAge = pendingCount;
            confirmedAge = 1;
            pendingCore = "";
            pendingCount = 0;
            pendingRequired = 0;
            switchEvent = true;
         }
      }

      int directionCandidate = direction;
      if(macroZ >= REGIME_V3_DIRECTION_ENTER_Z) directionCandidate = 1;
      else if(macroZ <= -REGIME_V3_DIRECTION_ENTER_Z) directionCandidate = -1;
      if(direction == 0 && directionCandidate != 0)
         direction = directionCandidate;
      else if(directionCandidate == direction)
      {
         pendingDirection = 0;
         pendingDirectionCount = 0;
         pendingDirectionRequired = 0;
      }
      else if(directionCandidate != 0)
      {
         int required = MathAbs(macroZ) >= REGIME_V3_DIRECTION_DECISIVE_Z ? REGIME_V3_FAST_CONFIRM : REGIME_V3_NORMAL_CONFIRM;
         if(directionCandidate == pendingDirection)
            pendingDirectionCount++;
         else
         {
            pendingDirection = directionCandidate;
            pendingDirectionCount = 1;
            pendingDirectionRequired = required;
         }
         if(pendingDirectionCount >= pendingDirectionRequired)
         {
            direction = directionCandidate;
            pendingDirection = 0;
            pendingDirectionCount = 0;
            pendingDirectionRequired = 0;
         }
      }

      double h1h2Fast = RegimeV3Median2(ret5[0], ret5[1]);
      double h1h2Medium = RegimeV3Median2(ret20[0], ret20[1]);
      double fastNoise = rv20 * MathSqrt(5.0) * 100.0;
      double mediumNoise = rv60 * MathSqrt(20.0) * 100.0;
      double fastZ = fastNoise > 0.0 ? h1h2Fast / fastNoise : 0.0;
      double mediumZ = mediumNoise > 0.0 ? h1h2Medium / mediumNoise : 0.0;
      bool fastAgreement = RegimeV3Sign(ret5[0]) == RegimeV3Sign(ret5[1]);
      bool mediumAgreement = RegimeV3Sign(ret20[0]) == RegimeV3Sign(ret20[1]);
      string phase = RegimeV3ClassifyPhase(fastZ, mediumZ, fastAgreement, mediumAgreement,
         direction, pendingDirection, pendingDirectionCount);
      string volDepth = RegimeV3ClassifyVolatility(volScore, ratio20, percentile, percentileValid);
      string ageName = RegimeV3AgeBucket(effectiveAge);
      string status = switchEvent ? "FRESH_CONFIRMED" : (pendingCore != "" ? (pendingCount == 1 ? "WATCH" : "DEVELOPING") : "STABLE");
      string activeTransitionType = switchEvent ? switchedType : RegimeV3TransitionType(activeCore, pendingCore);
      string volImpulseState = volImpulse >= 0.15 ? "EXPANDING" : (volImpulse <= -0.15 ? "CONTRACTING" : "STEADY");
      string hint = RegimeV3StructuralHint(activeCore, status, phase, volDepth, ageName);

      snapshot.valid = true;
      snapshot.availableTime = available;
      snapshot.core = activeCore;
      snapshot.effectiveAge = effectiveAge;
      snapshot.confirmedAge = confirmedAge;
      snapshot.ageBucket = ageName;
      snapshot.transitionStatus = status;
      snapshot.transitionType = activeTransitionType;
      snapshot.transitionCandidate = pendingCore;
      snapshot.transitionPending = pendingCount;
      snapshot.transitionRequired = pendingRequired;
      snapshot.transitionConfidence = pendingRequired > 0 ? (double)pendingCount / pendingRequired : 0.0;
      snapshot.macroDirection = RegimeV3DirectionName(direction);
      snapshot.directionPending = RegimeV3DirectionName(pendingDirection);
      snapshot.directionPendingSessions = pendingDirectionCount;
      snapshot.h1h2Phase = phase;
      snapshot.volatilityDepth = volDepth;
      snapshot.volatilityImpulse = volImpulseState;
      snapshot.structuralHint = hint;
      snapshot.trendDepthScore = trendScore;
      snapshot.volatilityDepthScore = volScore;
      snapshot.detail = "OK";
      int timelineIndex = ArraySize(timeline);
      ArrayResize(timeline, timelineIndex + 1);
      timeline[timelineIndex] = snapshot;
      rowsBuilt++;
   }
   if(!snapshot.valid)
   {
      snapshot.detail = "NO_CAUSAL_ROWS";
      return false;
   }
   snapshot.detail = "OK rows=" + IntegerToString(rowsBuilt);
   return true;
}

bool RegimeV3EnsureTimeline(bool force = false)
{
   datetime currentD1Open = iTime(_Symbol, PERIOD_D1, 0);
   if(currentD1Open <= 0)
   {
      g_regimeV3.valid = false;
      g_regimeV3.detail = "WAITING_D1";
      return false;
   }
   if(!force && g_regimeV3.valid && ArraySize(g_regimeV3Timeline) > 0
      && currentD1Open == g_regimeV3LastSourceOpen) return true;
   datetime nowLocal = TimeLocal();
   if(!force && g_regimeV3LastAttemptLocal > 0
      && nowLocal - g_regimeV3LastAttemptLocal < MathMax(5, InpRegimeV3RetrySeconds)) return false;
   g_regimeV3LastAttemptLocal = nowLocal;

   RegimeV3Snapshot next;
   RegimeV3Snapshot nextTimeline[];
   if(!RegimeV3Rebuild(next, nextTimeline))
   {
      g_regimeV3.valid = false;
      g_regimeV3.detail = next.detail;
      return false;
   }

   g_regimeV3 = next;
   ArrayFree(g_regimeV3Timeline);
   int count = ArraySize(nextTimeline);
   ArrayResize(g_regimeV3Timeline, count);
   for(int i = 0; i < count; ++i) g_regimeV3Timeline[i] = nextTimeline[i];
   g_regimeV3LastSourceOpen = currentD1Open;
   return count > 0;
}

bool RegimeV3SnapshotAt(datetime availableTime, RegimeV3Snapshot &snapshot)
{
   snapshot.valid = false;
   if(availableTime <= 0 || ArraySize(g_regimeV3Timeline) <= 0) return false;
   int left = 0;
   int right = ArraySize(g_regimeV3Timeline);
   while(left < right)
   {
      int mid = left + (right - left) / 2;
      if(g_regimeV3Timeline[mid].availableTime <= availableTime) left = mid + 1;
      else right = mid;
   }
   int index = left - 1;
   if(index < 0) return false;
   snapshot = g_regimeV3Timeline[index];
   return snapshot.valid && snapshot.availableTime <= availableTime;
}

void RegimeV3Update(bool force = false)
{
   if(!InpRegimeV3Observer)
   {
      g_regimeV3.valid = false;
      g_regimeV3.detail = "OFF";
      return;
   }
   if(!RegimeV3EnsureTimeline(force)) return;

   string signature = g_regimeV3.core + "|" + g_regimeV3.transitionStatus + "|"
      + g_regimeV3.transitionCandidate + "|" + g_regimeV3.macroDirection + "|"
      + g_regimeV3.h1h2Phase + "|" + g_regimeV3.volatilityDepth + "|"
      + g_regimeV3.volatilityImpulse + "|" + g_regimeV3.structuralHint;
   if(signature != g_regimeV3LastLogSignature)
   {
      Print("SOL_REGIME_V3 symbol=", _Symbol,
         " available=", TimeToString(g_regimeV3.availableTime, TIME_DATE|TIME_MINUTES),
         " core=", g_regimeV3.core,
         " age=", IntegerToString(g_regimeV3.effectiveAge), " ", g_regimeV3.ageBucket,
         " transition=", g_regimeV3.transitionStatus,
         " candidate=", (g_regimeV3.transitionCandidate == "" ? "-" : g_regimeV3.transitionCandidate),
         " pending=", IntegerToString(g_regimeV3.transitionPending), "/", IntegerToString(g_regimeV3.transitionRequired),
         " direction=", g_regimeV3.macroDirection,
         " h1h2=", g_regimeV3.h1h2Phase,
         " vol=", g_regimeV3.volatilityDepth, "/", g_regimeV3.volatilityImpulse,
         " hint=", g_regimeV3.structuralHint,
         " trend_score=", DoubleToString(g_regimeV3.trendDepthScore, 3),
         " vol_score=", DoubleToString(g_regimeV3.volatilityDepthScore, 3));
      g_regimeV3LastLogSignature = signature;
   }
}

color RegimeV3CoreColor()
{
   if(!g_regimeV3.valid) return C'145,160,180';
   if(g_regimeV3.core == "TREND_HIGH_VOL") return C'30,220,180';
   if(g_regimeV3.core == "TREND_LOW_VOL") return C'80,255,180';
   if(g_regimeV3.core == "RANGE_HIGH_VOL") return C'255,166,70';
   return C'90,178,255';
}

color RegimeV3TransitionColor()
{
   if(!g_regimeV3.valid) return C'145,160,180';
   if(g_regimeV3.transitionStatus == "WATCH") return C'255,204,82';
   if(g_regimeV3.transitionStatus == "DEVELOPING") return C'255,166,70';
   if(g_regimeV3.transitionStatus == "FRESH_CONFIRMED") return C'80,255,180';
   return C'145,160,180';
}

color RegimeV3HintColor()
{
   if(!g_regimeV3.valid) return C'145,160,180';
   if(g_regimeV3.structuralHint == "REVERSAL_RISK" || g_regimeV3.structuralHint == "PRICE_DISCOVERY_RISK")
      return C'255,95,140';
   if(g_regimeV3.structuralHint == "TRANSITION_UNCERTAIN" || g_regimeV3.structuralHint == "RANGE_EXPANSION_RISK")
      return C'255,204,82';
   if(g_regimeV3.structuralHint == "TREND_CONTINUATION_SUPPORT" || g_regimeV3.structuralHint == "TREND_RETRACE_SETUP")
      return C'80,255,180';
   return C'145,160,180';
}

#endif