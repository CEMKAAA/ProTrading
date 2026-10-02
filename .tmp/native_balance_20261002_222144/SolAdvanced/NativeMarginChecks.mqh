void NmChecks()
{
   MqlTick tick;ZeroMemory(tick);ulong wait=GetTickCount64();
   while(GetTickCount64()-wait<20000)
   {if(TerminalInfoInteger(TERMINAL_CONNECTED)&&SymbolInfoTick(_Symbol,tick)&&tick.bid>0&&tick.ask>=tick.bid)break;Sleep(100);}
   NbCheck(tick.bid>0&&tick.ask>=tick.bid,"margin broker quote ready");
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   for(int i=0;i<2;i++)
   {
      bool buy=i==0;double entry=buy?tick.ask:tick.bid;
      // Use executable tick-grid distances; indices may round fractional-price probes.
      double step=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_POINT));
      double distance=MathMax(step*10,MathFloor(entry*0.005/(step*10))*step*10);
      double stop=entry+(buy?-1:1)*distance;
      NativeMarginQuote quote;double margin=0,profit=0,volume=0;
      NbCheck(NativeMarginCalculate(_Symbol,buy,entry,stop,minLot,quote),"margin quote valid");
      NbCheck(OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,minLot,entry,margin)
         &&MathAbs(margin-quote.margin)<1e-8,"margin exactly matches native broker API");
      NbCheck(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,minLot,entry,stop,profit)
         &&MathAbs(profit+quote.slRisk)<1e-8,"separate SL loss equals profit API");
      NbCheck(NativeMinimumMargin(buy,volume,margin)&&volume==minLot,"broker minimum lot margin available");
      double loss=0,smallerLoss=0;
      NbCheck(NativeMinimumSlLoss(buy,entry,stop,loss)&&MathAbs(loss-quote.slRisk)<1e-8,"minimum SL risk uses broker minimum volume and exact profit API");
      double smallerStop=entry+(stop-entry)/10;
      // OrderCalcProfit can round each result to the account currency precision.
      double cashStep=MathPow(10.0,-(int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS));
      NbCheck(NativeMinimumSlLoss(buy,entry,smallerStop,smallerLoss)
         &&MathAbs(smallerLoss*10-loss)<=5.5*cashStep+1e-7,"tenfold narrower SL reduces loss within broker cash rounding");
      NbCheck(MathAbs(NativeMinimumRiskCapital(loss,1)-loss*100)<1e-8,"one percent reference capital is one hundred times minimum loss");
   }
   NativeMarginQuote invalid;
   NbCheck(!NativeMarginCalculate(_Symbol,true,100,101,minLot,invalid)&&!invalid.valid,"invalid SL is N/A not money");
   double invalidLoss=99;
   NbCheck(!NativeMinimumSlLoss(true,100,101,invalidLoss)&&invalidLoss==0,"invalid minimum SL geometry not fabricated");
   NbCheck(NativeMinimumRiskCapital(0.6,0)<0&&NativeMinimumRiskCapital(0.6,101)<0,"invalid risk percent is unavailable");
   NbCheck(MathAbs(NativeMinimumRiskCapital(0.6,1)-60)<1e-8,"0.60 dollar loss at one percent requires 60 dollar reference");
   NbCheck(StringFind(NativeMinimumCapitalText(true,0.006001,false,0,1),"0.61")>=0,"capital rounds upward instead of below minimum threshold");
   g_nativeRiskBalance=30;
#ifdef NM_SOL
   g_riskPerTradePct=1;g_ftmoMode=false;g_pipSlMode=true;g_pipSlPips=10;
   g_liqLibraryPanel=true;g_liqLibraryOpen=false;g_liqLibraryRPicker=false;
   DrawDashboard();LiqLibraryDraw();
   string buy=LiqLibraryObject("MARGIN_BUY"),sell=LiqLibraryObject("MARGIN_SELL"),minimum=LiqLibraryObject("MARGIN_MIN");
   string slLabel=LiqLibraryObject("MARGIN_MIN_SL"),capitalLabel=LiqLibraryObject("MARGIN_MIN_CAPITAL");
   NbCheck(ObjectGetInteger(0,LiqLibraryObject("BG"),OBJPROP_YSIZE)==530,"Sol library includes readable minimum risk space");
   long marginBottom=ObjectGetInteger(0,LiqLibraryObject("MARGIN_NOTE"),OBJPROP_YDISTANCE)+15;
   NbCheck(marginBottom<ObjectGetInteger(0,LiqLibraryObject("SAVE_TITLE"),OBJPROP_YDISTANCE),"Sol margin does not overlap strategy save");
   g_pipSlMode=false;LiqLibraryDraw();
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")>=0,"Sol percent SL unavailable estimate explicit");
   NbCheck(StringFind(ObjectGetString(0,minimum,OBJPROP_TEXT),"N/A")<0,"Sol minimum margin still visible without pip mode");
   NbCheck(StringFind(ObjectGetString(0,slLabel,OBJPROP_TEXT),"N/A")>=0,"Sol minimum SL unknown when pip off");
   g_pipSlMode=true;LiqLibraryDraw();
#else
   g_rtRiskPerTradePct=1;g_rtPipSlMode=true;g_rtPipSlPips=10;
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_strategyPopupOpen=false;
   // The balance test creates child widgets before a dashboard shell exists.
   // A fresh lifecycle must create backgrounds before controls, as OnInit does.
   DeleteDash();DrawDashboard();
   string buy=PREFIX+"DASH_MARGIN_BUY",sell=PREFIX+"DASH_MARGIN_SELL",minimum=PREFIX+"DASH_MARGIN_MIN";
   string slLabel=PREFIX+"DASH_MARGIN_MIN_SL",capitalLabel=PREFIX+"DASH_MARGIN_MIN_CAPITAL";
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_XDISTANCE)==OrbLibraryX(InpDashboardX+644),"margin in right STRATEGIES column");
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_YDISTANCE)==OrbLibraryY(InpDashboardY+420),"visible margin panel coordinates");
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_FONTSIZE)>=9,"margin estimate readable normal font");
   long bottom=ObjectGetInteger(0,PREFIX+"DASH_MARGIN_NOTE",OBJPROP_YDISTANCE)+12;
   NbCheck(bottom<ObjectGetInteger(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_YDISTANCE),"margin does not overlap balance inputs");
   ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,"500");UpdateDashboard();
   NbCheck(g_rtPipSlPips==10,"unapplied pip edit cannot change margin sizing");
   g_rtPipSlMode=false;RenderNativeMarginPreview(InpDashboardX+644,InpDashboardY+400);
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")>=0,"percent SL unavailable estimate explicit");
   NbCheck(StringFind(ObjectGetString(0,minimum,OBJPROP_TEXT),"N/A")<0,"minimum margin still visible without pip mode");
   NbCheck(StringFind(ObjectGetString(0,slLabel,OBJPROP_TEXT),"N/A")>=0,"minimum SL unknown when pip off");
   g_rtPipSlMode=true;UpdateDashboard();
#endif
   NbCheck(ObjectFind(0,buy)>=0&&ObjectFind(0,sell)>=0&&ObjectFind(0,minimum)>=0,"both sides and minimum margin objects exist");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")<0,"BUY cash amount actually rendered");
   NbCheck(StringFind(ObjectGetString(0,sell,OBJPROP_TEXT),"N/A")<0,"SELL cash amount actually rendered");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TOOLTIP),"risk budget=0.30")>=0,"applied risk budget feeds preview");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TOOLTIP),"Lot=")>=0,"tooltip explains volume");
   double previewEntry=tick.ask,previewStop=0,previewLots=0;
#ifdef NM_SOL
   previewEntry=NormTradePrice(previewEntry);previewStop=ApplyRuntimeSlDistance(1,previewEntry,previewEntry);
   previewLots=NormalizeVolume(NativeBalanceBudget(1)/(MathAbs(previewEntry-previewStop)*ValuePerPriceUnitPerLot()));
#else
   previewEntry=NormalizeTradePrice(previewEntry);previewStop=ApplyRuntimeSlFromEntry(true,previewEntry,0);
   previewLots=CalculateLot(previewEntry,previewStop);
#endif
   NativeMarginQuote displayedQuote;
   bool previewValid=NativeMarginCalculate(_Symbol,true,previewEntry,previewStop,previewLots,displayedQuote);
   bool expectedWarning=previewValid&&(NativeBalanceOverBudget(displayedQuote.slRisk,NativeBalanceBudget(1))
      ||displayedQuote.margin>MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
   NbCheck(previewValid&&ObjectGetInteger(0,buy,OBJPROP_COLOR)==(expectedWarning?clrOrange:C'80,255,180'),"warning color matches broker cash risk and free margin");
   NbCheck(ObjectFind(0,slLabel)>=0&&ObjectFind(0,capitalLabel)>=0,"minimum SL and reference capital visible");
   NbCheck(StringFind(ObjectGetString(0,slLabel,OBJPROP_TEXT),"N/A")<0,"minimum SL dollar amounts rendered");
   NbCheck(StringFind(ObjectGetString(0,capitalLabel,OBJPROP_TEXT),"@1.00%")>=0,"reference capital follows applied percent");
   NbCheck(StringFind(ObjectGetString(0,slLabel,OBJPROP_TOOLTIP),"slippage")>=0,"SL quote discloses excluded execution costs");
   NbCheck(StringFind(ObjectGetString(0,capitalLabel,OBJPROP_TOOLTIP),"Not a safe deposit")>=0,"capital not presented as safe deposit guarantee");
#ifdef NM_SOL
   string before=ObjectGetString(0,slLabel,OBJPROP_TEXT);g_pipSlPips=1;LiqLibraryDraw();
#else
   string before=ObjectGetString(0,slLabel,OBJPROP_TEXT);g_rtPipSlPips=1;UpdateDashboard();
#endif
   NbCheck(ObjectGetString(0,slLabel,OBJPROP_TEXT)!=before,"applied pip change updates minimum SL amount");
#ifdef NM_SOL
   g_riskPerTradePct=2;LiqLibraryDraw();
#else
   g_rtRiskPerTradePct=2;UpdateDashboard();
#endif
   NbCheck(StringFind(ObjectGetString(0,capitalLabel,OBJPROP_TEXT),"@2.00%")>=0,"applied risk update refreshes reference capital");
   ChartRedraw();
}
