void NmChecks()
{
   MqlTick tick;ZeroMemory(tick);ulong wait=GetTickCount64();
   while(GetTickCount64()-wait<20000)
   {if(TerminalInfoInteger(TERMINAL_CONNECTED)&&SymbolInfoTick(_Symbol,tick)&&tick.bid>0&&tick.ask>=tick.bid)break;Sleep(100);}
   NbCheck(tick.bid>0&&tick.ask>=tick.bid,"margin broker quote ready");
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   for(int i=0;i<2;i++)
   {
      bool buy=i==0;double entry=buy?tick.ask:tick.bid,stop=entry+(buy?-1:1)*entry*0.005;
      NativeMarginQuote quote;double margin=0,profit=0,volume=0;
      NbCheck(NativeMarginCalculate(_Symbol,buy,entry,stop,minLot,quote),"margin quote valid");
      NbCheck(OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,minLot,entry,margin)
         &&MathAbs(margin-quote.margin)<1e-8,"margin exactly matches native broker API");
      NbCheck(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,minLot,entry,stop,profit)
         &&MathAbs(profit+quote.slRisk)<1e-8,"separate SL loss equals profit API");
      NbCheck(NativeMinimumMargin(buy,volume,margin)&&volume==minLot,"broker minimum lot margin available");
   }
   NativeMarginQuote invalid;
   NbCheck(!NativeMarginCalculate(_Symbol,true,100,101,minLot,invalid)&&!invalid.valid,"invalid SL is N/A not money");
   g_nativeRiskBalance=30;
#ifdef NM_SOL
   g_riskPerTradePct=1;g_ftmoMode=false;g_pipSlMode=true;g_pipSlPips=10;
   g_liqLibraryPanel=true;g_liqLibraryOpen=false;g_liqLibraryRPicker=false;
   DrawDashboard();LiqLibraryDraw();
   string buy=LiqLibraryObject("MARGIN_BUY"),sell=LiqLibraryObject("MARGIN_SELL"),minimum=LiqLibraryObject("MARGIN_MIN");
   NbCheck(ObjectGetInteger(0,LiqLibraryObject("BG"),OBJPROP_YSIZE)==490,"Sol library includes readable margin space");
   long marginBottom=ObjectGetInteger(0,LiqLibraryObject("MARGIN_NOTE"),OBJPROP_YDISTANCE)+15;
   NbCheck(marginBottom<ObjectGetInteger(0,LiqLibraryObject("SAVE_TITLE"),OBJPROP_YDISTANCE),"Sol margin does not overlap strategy save");
   g_pipSlMode=false;LiqLibraryDraw();
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")>=0,"Sol percent SL unavailable estimate explicit");
   NbCheck(StringFind(ObjectGetString(0,minimum,OBJPROP_TEXT),"N/A")<0,"Sol minimum margin still visible without pip mode");
   g_pipSlMode=true;LiqLibraryDraw();
#else
   g_rtRiskPerTradePct=1;g_rtPipSlMode=true;g_rtPipSlPips=10;
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_strategyPopupOpen=false;
   // The balance test creates child widgets before a dashboard shell exists.
   // A fresh lifecycle must create backgrounds before controls, as OnInit does.
   DeleteDash();DrawDashboard();
   string buy=PREFIX+"DASH_MARGIN_BUY",sell=PREFIX+"DASH_MARGIN_SELL",minimum=PREFIX+"DASH_MARGIN_MIN";
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_XDISTANCE)==OrbLibraryX(InpDashboardX+644),"margin in right STRATEGIES column");
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_YDISTANCE)==OrbLibraryY(InpDashboardY+460),"visible margin panel coordinates");
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_FONTSIZE)>=9,"margin estimate readable normal font");
   long bottom=ObjectGetInteger(0,PREFIX+"DASH_MARGIN_NOTE",OBJPROP_YDISTANCE)+12;
   NbCheck(bottom<ObjectGetInteger(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_YDISTANCE),"margin does not overlap balance inputs");
   ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,"500");UpdateDashboard();
   NbCheck(g_rtPipSlPips==10,"unapplied pip edit cannot change margin sizing");
   g_rtPipSlMode=false;RenderNativeMarginPreview(InpDashboardX+644,InpDashboardY+440);
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")>=0,"percent SL unavailable estimate explicit");
   NbCheck(StringFind(ObjectGetString(0,minimum,OBJPROP_TEXT),"N/A")<0,"minimum margin still visible without pip mode");
   g_rtPipSlMode=true;UpdateDashboard();
#endif
   NbCheck(ObjectFind(0,buy)>=0&&ObjectFind(0,sell)>=0&&ObjectFind(0,minimum)>=0,"both sides and minimum margin objects exist");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TEXT),"N/A")<0,"BUY cash amount actually rendered");
   NbCheck(StringFind(ObjectGetString(0,sell,OBJPROP_TEXT),"N/A")<0,"SELL cash amount actually rendered");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TOOLTIP),"risk budget=0.30")>=0,"applied risk budget feeds preview");
   NbCheck(StringFind(ObjectGetString(0,buy,OBJPROP_TOOLTIP),"Lot=")>=0,"tooltip explains volume");
   NbCheck(ObjectGetInteger(0,buy,OBJPROP_COLOR)==clrOrange,"minimum lot exceeding small reference risk warns");
   ChartRedraw();
}
