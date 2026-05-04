//+------------------------------------------------------------------+
//| MT4 TMA Pro Preset Performance Audit                             |
//| Groups closed TMA_MACD_ProTrader_EA history by preset/base/TF.    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int InpLookbackHours = 24;
input string InpSymbolFilter = ""; // Empty = all symbols.
input string InpTmaMagicBasesCsv = "860500,860600,860700,860800,860900";
input int InpTmaMagicOffsetM1 = 10000;
input int InpTmaMagicOffsetM5 = 20000;
input int InpTmaMagicOffsetM15 = 30000;
input int InpTmaMagicOffsetM30 = 40000;
input int InpTmaMagicOffsetH1 = 50000;

#define MAX_GROUPS 64

string g_keys[MAX_GROUPS];
double g_pnl[MAX_GROUPS];
double g_volume[MAX_GROUPS];
int g_count[MAX_GROUPS];
int g_wins[MAX_GROUPS];
int g_losses[MAX_GROUPS];
int g_be[MAX_GROUPS];
int g_partials[MAX_GROUPS];
int g_group_count = 0;

string TrimText(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

string PresetNameByBase(const int base)
{
   if(base == 860500) return "StateWinner";
   if(base == 860600) return "EventProduction";
   if(base == 860700) return "OriginalAlertFaithful";
   if(base == 860800) return "ColorFollower";
   if(base == 860900) return "ClosedBarArrows";
   return "Base" + IntegerToString(base);
}

string TfByOffset(const int offset)
{
   if(offset == InpTmaMagicOffsetM1) return "M1";
   if(offset == InpTmaMagicOffsetM5) return "M5";
   if(offset == InpTmaMagicOffsetM15) return "M15";
   if(offset == InpTmaMagicOffsetM30) return "M30";
   if(offset == InpTmaMagicOffsetH1) return "H1";
   return "?";
}

string ModeByMagic(const int magic, const int base, const int offset)
{
   if(magic == base + offset + 1) return "normal";
   if(magic == base + offset + 2) return "advanced";
   if(magic == base + 1) return "legacy_normal";
   if(magic == base + 2) return "legacy_advanced";
   return "?";
}

bool DecodeTmaMagic(const int magic, int &baseOut, string &presetOut, string &tfOut, string &modeOut)
{
   int offsets[5];
   offsets[0] = InpTmaMagicOffsetM1;
   offsets[1] = InpTmaMagicOffsetM5;
   offsets[2] = InpTmaMagicOffsetM15;
   offsets[3] = InpTmaMagicOffsetM30;
   offsets[4] = InpTmaMagicOffsetH1;

   string csv = InpTmaMagicBasesCsv;
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int base = (int)StringToInteger(TrimText(part));
      if(base > 0)
      {
         for(int i = 0; i < 5; i++)
         {
            int offset = offsets[i];
            if(magic == base + offset + 1 || magic == base + offset + 2)
            {
               baseOut = base;
               presetOut = PresetNameByBase(base);
               tfOut = TfByOffset(offset);
               modeOut = ModeByMagic(magic, base, offset);
               return true;
            }
         }

         if(magic == base + 1 || magic == base + 2)
         {
            baseOut = base;
            presetOut = PresetNameByBase(base);
            tfOut = "LEGACY_NO_TF";
            modeOut = ModeByMagic(magic, base, 0);
            return true;
         }
      }

      if(comma < 0) break;
      start = comma + 1;
   }
   return false;
}

int GroupIndex(const string key)
{
   for(int i = 0; i < g_group_count; i++)
      if(g_keys[i] == key)
         return i;

   if(g_group_count >= MAX_GROUPS)
      return -1;

   int idx = g_group_count;
   g_keys[idx] = key;
   g_pnl[idx] = 0.0;
   g_volume[idx] = 0.0;
   g_count[idx] = 0;
   g_wins[idx] = 0;
   g_losses[idx] = 0;
   g_be[idx] = 0;
   g_partials[idx] = 0;
   g_group_count++;
   return idx;
}

void AddGroup(const string key, const double pnl, const double lots, const bool partialLike)
{
   int idx = GroupIndex(key);
   if(idx < 0) return;

   g_pnl[idx] += pnl;
   g_volume[idx] += lots;
   g_count[idx]++;
   if(pnl > 0.000001) g_wins[idx]++;
   else if(pnl < -0.000001) g_losses[idx]++;
   else g_be[idx]++;
   if(partialLike) g_partials[idx]++;
}

void SortGroupsByPnlDesc()
{
   for(int i = 0; i < g_group_count - 1; i++)
   {
      for(int j = i + 1; j < g_group_count; j++)
      {
         if(g_pnl[j] <= g_pnl[i]) continue;

         string sk = g_keys[i]; g_keys[i] = g_keys[j]; g_keys[j] = sk;
         double dp = g_pnl[i]; g_pnl[i] = g_pnl[j]; g_pnl[j] = dp;
         double dv = g_volume[i]; g_volume[i] = g_volume[j]; g_volume[j] = dv;
         int ic = g_count[i]; g_count[i] = g_count[j]; g_count[j] = ic;
         int iw = g_wins[i]; g_wins[i] = g_wins[j]; g_wins[j] = iw;
         int il = g_losses[i]; g_losses[i] = g_losses[j]; g_losses[j] = il;
         int ib = g_be[i]; g_be[i] = g_be[j]; g_be[j] = ib;
         int ip = g_partials[i]; g_partials[i] = g_partials[j]; g_partials[j] = ip;
      }
   }
}

void PrintGroups(const string title)
{
   Print("TMA_PRESET_AUDIT ", title);
   for(int i = 0; i < g_group_count; i++)
   {
      double wr = (g_wins[i] + g_losses[i] > 0) ? (100.0 * g_wins[i] / (g_wins[i] + g_losses[i])) : 0.0;
      Print("TMA_PRESET_AUDIT rank=", i + 1,
            " pnl=", DoubleToString(g_pnl[i], 2),
            " trades=", g_count[i],
            " wins=", g_wins[i],
            " losses=", g_losses[i],
            " be=", g_be[i],
            " winrate=", DoubleToString(wr, 1),
            "% volume=", DoubleToString(g_volume[i], 2),
            " partial_like=", g_partials[i],
            " key=", g_keys[i]);
   }
}

void OnStart()
{
   datetime since = 0;
   if(InpLookbackHours > 0)
      since = TimeCurrent() - InpLookbackHours * 3600;

   int scanned = 0;
   int matched = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      if(since > 0 && OrderCloseTime() < since) continue;
      if(InpSymbolFilter != "" && StringCompare(OrderSymbol(), InpSymbolFilter, false) != 0) continue;

      scanned++;
      int base = 0;
      string preset = "";
      string tf = "";
      string mode = "";
      if(!DecodeTmaMagic(OrderMagicNumber(), base, preset, tf, mode))
         continue;

      matched++;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      string side = (type == OP_BUY) ? "BUY" : "SELL";
      bool partialLike = (OrderLots() < 0.099999);
      AddGroup(preset, pnl, OrderLots(), partialLike);
      AddGroup(preset + "|" + tf, pnl, OrderLots(), partialLike);
      AddGroup(preset + "|" + tf + "|" + mode, pnl, OrderLots(), partialLike);
      AddGroup(preset + "|" + tf + "|" + mode + "|" + side, pnl, OrderLots(), partialLike);
   }

   SortGroupsByPnlDesc();
   Print("TMA_PRESET_AUDIT since=", TimeToString(since, TIME_DATE | TIME_SECONDS),
         " symbol_filter=", (InpSymbolFilter == "" ? "ALL" : InpSymbolFilter),
         " scanned=", scanned,
         " matched=", matched,
         " groups=", g_group_count);
   PrintGroups("BY_PRESET_AND_DETAIL");
}
