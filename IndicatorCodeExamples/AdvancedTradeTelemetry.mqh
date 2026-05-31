#property strict

ulong    g_telTickets[];
double   g_telMaxPnl[];
double   g_telMinPnl[];
datetime g_telPeakTime[];
datetime g_telOpenTime[];
datetime g_telLastLogTime[];

int g_telRsiHandle = INVALID_HANDLE;
int g_telAdxHandle = INVALID_HANDLE;
int g_telAtrHandle = INVALID_HANDLE;
int g_telEmaFastHandle = INVALID_HANDLE;
int g_telEmaSlowHandle = INVALID_HANDLE;
int g_telSmaHandle = INVALID_HANDLE;
int g_telMacdHandle = INVALID_HANDLE;

string TelemetrySafeName(string s)
{
   StringReplace(s, "\\", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, ":", "_");
   StringReplace(s, " ", "_");
   return s;
}

string TelemetryFileName()
{
   string tf = EnumToString(_Period);
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "advanced_trade_telemetry_"
          + TelemetrySafeName(PREFIX) + "_"
          + TelemetrySafeName(_Symbol) + "_"
          + TelemetrySafeName(tf) + "_magic"
          + IntegerToString((int)InpMagic) + "_acct"
          + IntegerToString((int)login) + ".csv";
}

void TelemetryReleaseHandle(int &handle)
{
   if(handle != INVALID_HANDLE)
   {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
   }
}

void TelemetryInit()
{
   if(!InpTelemetryEnabled)
      return;
   g_telRsiHandle = iRSI(_Symbol, _Period, InpTelemetryRsiLen, PRICE_CLOSE);
   g_telAdxHandle = iADX(_Symbol, _Period, InpTelemetryAdxLen);
   g_telAtrHandle = iATR(_Symbol, _Period, InpTelemetryAtrLen);
   g_telEmaFastHandle = iMA(_Symbol, _Period, InpTelemetryEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   g_telEmaSlowHandle = iMA(_Symbol, _Period, InpTelemetryEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   g_telSmaHandle = iMA(_Symbol, _Period, InpTelemetrySmaLen, 0, MODE_SMA, PRICE_CLOSE);
   g_telMacdHandle = iMACD(_Symbol, _Period, InpTelemetryMacdFast, InpTelemetryMacdSlow, InpTelemetryMacdSignal, PRICE_CLOSE);
   Print("Telemetry initialized file=", TelemetryFileName(), " common_files=", InpTelemetryUseCommonFiles);
}

void TelemetryDeinit()
{
   TelemetryReleaseHandle(g_telRsiHandle);
   TelemetryReleaseHandle(g_telAdxHandle);
   TelemetryReleaseHandle(g_telAtrHandle);
   TelemetryReleaseHandle(g_telEmaFastHandle);
   TelemetryReleaseHandle(g_telEmaSlowHandle);
   TelemetryReleaseHandle(g_telSmaHandle);
   TelemetryReleaseHandle(g_telMacdHandle);
}

double TelemetryBufferValue(const int handle, const int buffer, const int shift)
{
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double v[];
   ArraySetAsSeries(v, true);
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1)
      return EMPTY_VALUE;
   return v[0];
}

double TelemetryWmaAt(const double &series[], const int shift, const int len)
{
   int size = ArraySize(series);
   if(len <= 0 || shift < 0 || shift + len > size)
      return EMPTY_VALUE;
   double num = 0.0;
   double den = 0.0;
   for(int i = 0; i < len; i++)
   {
      int weight = len - i;
      double value = series[shift + i];
      num += value * (double)weight;
      den += (double)weight;
   }
   return den == 0.0 ? EMPTY_VALUE : num / den;
}

double TelemetryHmaValue(const int shift)
{
   int len = MathMax(2, InpTelemetryHmaLen);
   int half = MathMax(1, len / 2);
   int root = MathMax(1, (int)MathSqrt((double)len));
   int need = shift + len + root + 10;
   double closeSeries[];
   ArraySetAsSeries(closeSeries, true);
   if(CopyClose(_Symbol, _Period, 0, need, closeSeries) < need)
      return EMPTY_VALUE;

   double tmp[];
   ArrayResize(tmp, root);
   for(int i = 0; i < root; i++)
   {
      double wHalf = TelemetryWmaAt(closeSeries, shift + i, half);
      double wFull = TelemetryWmaAt(closeSeries, shift + i, len);
      if(wHalf == EMPTY_VALUE || wFull == EMPTY_VALUE)
         return EMPTY_VALUE;
      tmp[i] = 2.0 * wHalf - wFull;
   }

   double num = 0.0;
   double den = 0.0;
   for(int i = 0; i < root; i++)
   {
      int weight = root - i;
      num += tmp[i] * (double)weight;
      den += (double)weight;
   }
   return den == 0.0 ? EMPTY_VALUE : num / den;
}

int TelemetryFindTicket(const ulong ticket)
{
   int n = ArraySize(g_telTickets);
   for(int i = 0; i < n; i++)
      if(g_telTickets[i] == ticket)
         return i;
   return -1;
}

int TelemetryEnsureTicket(const ulong ticket, const double pnl, const datetime openTime)
{
   int idx = TelemetryFindTicket(ticket);
   if(idx >= 0)
      return idx;
   int n = ArraySize(g_telTickets);
   ArrayResize(g_telTickets, n + 1);
   ArrayResize(g_telMaxPnl, n + 1);
   ArrayResize(g_telMinPnl, n + 1);
   ArrayResize(g_telPeakTime, n + 1);
   ArrayResize(g_telOpenTime, n + 1);
   ArrayResize(g_telLastLogTime, n + 1);
   g_telTickets[n] = ticket;
   g_telMaxPnl[n] = pnl;
   g_telMinPnl[n] = pnl;
   g_telPeakTime[n] = TimeCurrent();
   g_telOpenTime[n] = openTime;
   g_telLastLogTime[n] = 0;
   return n;
}

void TelemetryHeader(const int file)
{
   FileWrite(file,
             "server_time", "event", "ea_prefix", "symbol", "timeframe", "magic",
             "ticket", "deal", "position_id", "direction", "volume", "entry_price",
             "current_price", "sl", "tp", "pnl", "max_pnl", "min_pnl",
             "drawdown_from_peak", "age_sec", "seconds_since_peak",
             "bid", "ask", "spread_points",
             "bar_time", "bar_open", "bar_high", "bar_low", "bar_close", "bar_tick_volume",
             "atr", "rsi", "adx", "di_plus", "di_minus",
             "ema_fast", "ema_slow", "sma", "hma",
             "macd_main", "macd_signal", "macd_hist",
             "last_direction", "last_entry", "last_sl", "last_tp1", "last_tp2", "last_tp3",
             "trailing_active", "learning_score", "learning_samples", "learning_wins", "learning_losses",
             "liquidity_context", "fvg_context");
}

int TelemetryOpenFile()
{
   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpTelemetryUseCommonFiles)
      flags |= FILE_COMMON;
   int file = FileOpen(TelemetryFileName(), flags, ',');
   if(file == INVALID_HANDLE)
   {
      Print("Telemetry file open failed err=", GetLastError(), " file=", TelemetryFileName());
      return INVALID_HANDLE;
   }
   if(FileSize(file) == 0)
      TelemetryHeader(file);
   FileSeek(file, 0, SEEK_END);
   return file;
}

void TelemetryWriteRow(const string eventName,
                       const ulong ticket,
                       const ulong deal,
                       const ulong positionId,
                       const string direction,
                       const double volume,
                       const double entryPrice,
                       const double currentPrice,
                       const double sl,
                       const double tp,
                       const double pnl,
                       const double maxPnl,
                       const double minPnl,
                       const datetime openTime,
                       const datetime peakTime)
{
   if(!InpTelemetryEnabled)
      return;
   int file = TelemetryOpenFile();
   if(file == INVALID_HANDLE)
      return;

   datetime now = TimeCurrent();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spreadPoints = point > 0.0 ? (ask - bid) / point : 0.0;

   datetime barTime = iTime(_Symbol, _Period, 1);
   double barOpen = iOpen(_Symbol, _Period, 1);
   double barHigh = iHigh(_Symbol, _Period, 1);
   double barLow = iLow(_Symbol, _Period, 1);
   double barClose = iClose(_Symbol, _Period, 1);
   long barVol = iVolume(_Symbol, _Period, 1);

   double atr = TelemetryBufferValue(g_telAtrHandle, 0, 1);
   double rsi = TelemetryBufferValue(g_telRsiHandle, 0, 1);
   double adx = TelemetryBufferValue(g_telAdxHandle, 0, 1);
   double diPlus = TelemetryBufferValue(g_telAdxHandle, 1, 1);
   double diMinus = TelemetryBufferValue(g_telAdxHandle, 2, 1);
   double emaFast = TelemetryBufferValue(g_telEmaFastHandle, 0, 1);
   double emaSlow = TelemetryBufferValue(g_telEmaSlowHandle, 0, 1);
   double sma = TelemetryBufferValue(g_telSmaHandle, 0, 1);
   double hma = TelemetryHmaValue(1);
   double macdMain = TelemetryBufferValue(g_telMacdHandle, 0, 1);
   double macdSignal = TelemetryBufferValue(g_telMacdHandle, 1, 1);
   double macdHist = (macdMain == EMPTY_VALUE || macdSignal == EMPTY_VALUE) ? EMPTY_VALUE : macdMain - macdSignal;

   FileWrite(file,
             TimeToString(now, TIME_DATE | TIME_SECONDS),
             eventName,
             PREFIX,
             _Symbol,
             EnumToString(_Period),
             (long)InpMagic,
             (long)ticket,
             (long)deal,
             (long)positionId,
             direction,
             DoubleToString(volume, 8),
             DoubleToString(entryPrice, _Digits),
             DoubleToString(currentPrice, _Digits),
             DoubleToString(sl, _Digits),
             DoubleToString(tp, _Digits),
             DoubleToString(pnl, 2),
             DoubleToString(maxPnl, 2),
             DoubleToString(minPnl, 2),
             DoubleToString(maxPnl - pnl, 2),
             (long)(now - openTime),
             (long)(now - peakTime),
             DoubleToString(bid, _Digits),
             DoubleToString(ask, _Digits),
             DoubleToString(spreadPoints, 1),
             TimeToString(barTime, TIME_DATE | TIME_SECONDS),
             DoubleToString(barOpen, _Digits),
             DoubleToString(barHigh, _Digits),
             DoubleToString(barLow, _Digits),
             DoubleToString(barClose, _Digits),
             (long)barVol,
             DoubleToString(atr, _Digits),
             DoubleToString(rsi, 2),
             DoubleToString(adx, 2),
             DoubleToString(diPlus, 2),
             DoubleToString(diMinus, 2),
             DoubleToString(emaFast, _Digits),
             DoubleToString(emaSlow, _Digits),
             DoubleToString(sma, _Digits),
             DoubleToString(hma, _Digits),
             DoubleToString(macdMain, _Digits),
             DoubleToString(macdSignal, _Digits),
             DoubleToString(macdHist, _Digits),
             g_lastDirection,
             DoubleToString(g_lastEntry, _Digits),
             DoubleToString(g_lastSl, _Digits),
             DoubleToString(g_lastTp1, _Digits),
             DoubleToString(g_lastTp2, _Digits),
             DoubleToString(g_lastTp3, _Digits),
             (g_trailingActive ? "1" : "0"),
             DoubleToString(g_learningScore, 4),
             g_learningSamples,
             g_learningWins,
             g_learningLosses,
             "NA",
             "NA");
   FileFlush(file);
   FileClose(file);
}

void TelemetryLogOpenPositions()
{
   if(!InpTelemetryEnabled)
      return;
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int idx = TelemetryEnsureTicket(ticket, pnl, openTime);
      if(now - g_telLastLogTime[idx] < InpTelemetryEverySeconds)
         continue;
      g_telLastLogTime[idx] = now;
      if(pnl > g_telMaxPnl[idx])
      {
         g_telMaxPnl[idx] = pnl;
         g_telPeakTime[idx] = now;
      }
      if(pnl < g_telMinPnl[idx])
         g_telMinPnl[idx] = pnl;

      long type = PositionGetInteger(POSITION_TYPE);
      string direction = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      double currentPrice = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      TelemetryWriteRow("position_sample",
                        ticket,
                        0,
                        (ulong)PositionGetInteger(POSITION_IDENTIFIER),
                        direction,
                        PositionGetDouble(POSITION_VOLUME),
                        PositionGetDouble(POSITION_PRICE_OPEN),
                        currentPrice,
                        PositionGetDouble(POSITION_SL),
                        PositionGetDouble(POSITION_TP),
                        pnl,
                        g_telMaxPnl[idx],
                        g_telMinPnl[idx],
                        openTime,
                        g_telPeakTime[idx]);
   }
}

void TelemetryLogDeal(const ulong deal)
{
   if(!InpTelemetryEnabled || deal == 0 || !HistoryDealSelect(deal))
      return;
   string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   if(symbol != _Symbol)
      return;
   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
      return;

   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
   string eventName = entryType == DEAL_ENTRY_IN ? "deal_open" : (entryType == DEAL_ENTRY_OUT ? "deal_close" : "deal");
   string direction = (dealType == DEAL_TYPE_BUY ? "BUY" : (dealType == DEAL_TYPE_SELL ? "SELL" : "OTHER"));
   ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
                + HistoryDealGetDouble(deal, DEAL_SWAP)
                + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   double price = HistoryDealGetDouble(deal, DEAL_PRICE);
   double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
   datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   int idx = TelemetryEnsureTicket(positionId, pnl, t);
   if(pnl > g_telMaxPnl[idx])
   {
      g_telMaxPnl[idx] = pnl;
      g_telPeakTime[idx] = TimeCurrent();
   }
   if(pnl < g_telMinPnl[idx])
      g_telMinPnl[idx] = pnl;
   TelemetryWriteRow(eventName,
                     positionId,
                     deal,
                     positionId,
                     direction,
                     volume,
                     price,
                     price,
                     0.0,
                     0.0,
                     pnl,
                     g_telMaxPnl[idx],
                     g_telMinPnl[idx],
                     g_telOpenTime[idx],
                     g_telPeakTime[idx]);
}
