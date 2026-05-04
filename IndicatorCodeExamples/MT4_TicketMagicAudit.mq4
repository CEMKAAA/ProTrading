//+------------------------------------------------------------------+
//| MT4 Ticket Magic Audit                                           |
//| Prints magic/comment/TF inference for specific open/history tickets. |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string InpTicketsCsv = "";
input string InpTmaMagicBasesCsv = "860500,860600,860700,860800,860900";
input int InpTmaMagicOffsetM1 = 10000;
input int InpTmaMagicOffsetM5 = 20000;
input int InpTmaMagicOffsetM15 = 30000;
input int InpTmaMagicOffsetM30 = 40000;
input int InpTmaMagicOffsetH1 = 50000;
input int InpIndicatorV2MagicM1 = 970101;
input int InpIndicatorV2MagicM5 = 970105;
input int InpIndicatorV2MagicM15 = 970115;
input int InpIndicatorV2MagicM30 = 970130;
input int InpIndicatorV2MagicH1 = 970160;

string TrimText(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

bool MagicMatchesTmaTf(const int magic, const int offset)
{
   string csv = InpTmaMagicBasesCsv;
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int base = (int)StringToInteger(TrimText(part));
      if(base > 0 && (magic == base + offset + 1 || magic == base + offset + 2))
         return true;
      if(comma < 0)
         break;
      start = comma + 1;
   }
   return false;
}

string InferMagicTf(const int magic)
{
   if(magic == InpIndicatorV2MagicM1 || MagicMatchesTmaTf(magic, InpTmaMagicOffsetM1)) return "M1";
   if(magic == InpIndicatorV2MagicM5 || MagicMatchesTmaTf(magic, InpTmaMagicOffsetM5)) return "M5";
   if(magic == InpIndicatorV2MagicM15 || MagicMatchesTmaTf(magic, InpTmaMagicOffsetM15)) return "M15";
   if(magic == InpIndicatorV2MagicM30 || MagicMatchesTmaTf(magic, InpTmaMagicOffsetM30)) return "M30";
   if(magic == InpIndicatorV2MagicH1 || MagicMatchesTmaTf(magic, InpTmaMagicOffsetH1)) return "H1";

   // Legacy non-TF-offset TMA Pro magic. ProfitGovernor cannot infer TF safely from this.
   string csv = InpTmaMagicBasesCsv;
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int base = (int)StringToInteger(TrimText(part));
      if(base > 0 && (magic == base + 1 || magic == base + 2))
         return "LEGACY_NO_TF";
      if(comma < 0)
         break;
      start = comma + 1;
   }
   return "UNKNOWN";
}

string OrderTypeText(const int type)
{
   if(type == OP_BUY) return "BUY";
   if(type == OP_SELL) return "SELL";
   if(type == OP_BUYLIMIT) return "BUYLIMIT";
   if(type == OP_SELLLIMIT) return "SELLLIMIT";
   if(type == OP_BUYSTOP) return "BUYSTOP";
   if(type == OP_SELLSTOP) return "SELLSTOP";
   return IntegerToString(type);
}

void PrintSelectedOrder(const int ticket, const string pool)
{
   int magic = OrderMagicNumber();
   string inferredTf = InferMagicTf(magic);
   bool governorOk = (inferredTf != "UNKNOWN" && inferredTf != "LEGACY_NO_TF");
   Print("MAGIC_AUDIT ticket=", ticket,
         " pool=", pool,
         " symbol=", OrderSymbol(),
         " type=", OrderTypeText(OrderType()),
         " lots=", DoubleToString(OrderLots(), 2),
         " open=", TimeToString(OrderOpenTime(), TIME_DATE | TIME_SECONDS),
         " close=", TimeToString(OrderCloseTime(), TIME_DATE | TIME_SECONDS),
         " magic=", magic,
         " inferred_tf=", inferredTf,
         " governor_tf_ok=", (governorOk ? "true" : "false"),
         " comment=", OrderComment(),
         " profit=", DoubleToString(OrderProfit() + OrderSwap() + OrderCommission(), 2));
}

bool AuditTicket(const int ticket)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderTicket() == ticket)
      {
         PrintSelectedOrder(ticket, "OPEN");
         return true;
      }
   }

   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderTicket() == ticket)
      {
         PrintSelectedOrder(ticket, "HISTORY");
         return true;
      }
   }

   Print("MAGIC_AUDIT ticket=", ticket, " pool=NOT_FOUND");
   return false;
}

void OnStart()
{
   if(StringLen(TrimText(InpTicketsCsv)) <= 0)
   {
      Print("MAGIC_AUDIT no tickets supplied. Set InpTicketsCsv to comma-separated ticket numbers.");
      return;
   }

   int found = 0;
   int total = 0;
   string csv = InpTicketsCsv;
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int ticket = (int)StringToInteger(TrimText(part));
      if(ticket > 0)
      {
         total++;
         if(AuditTicket(ticket))
            found++;
      }
      if(comma < 0)
         break;
      start = comma + 1;
   }

   Print("MAGIC_AUDIT completed found=", found, " total=", total);
}
