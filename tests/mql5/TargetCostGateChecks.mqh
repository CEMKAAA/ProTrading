void CheckTargetCostMath()
{
   g_tpCostKey="";string reason="";double value=0;
   Check(TpCostSet(false,20)&&TpCostCheck(0,-1,reason),"OFF preserves old semantics even without a target");
   Check(TpCostIdentity()=="","OFF cache identity unchanged");
   Check(TpCostSet(true,20)&&TpCostCheck(1,0.20,reason),"exact 20 percent boundary allowed");
   Check(!TpCostCheck(1,0.20001,reason)&&reason=="COST_TP_BLOCK","above boundary rejected");
   Check(!TpCostCheck(0,0.01,reason)&&reason=="COST_TP_NO_FIXED_TARGET","unknown profit budget fails closed");
   Check(!TpCostCheck(1,-1,reason)&&reason=="COST_TP_DATA","unknown cost is DATA, not a filtered win");
   Check(TpCostSet(true,0)&&TpCostCheck(1,0,reason)&&!TpCostCheck(1,0.001,reason),"zero percent requires zero estimated cost");
   Check(TpCostSet(true,100)&&TpCostCheck(1,1,reason)&&!TpCostCheck(1,1.001,reason),"100 percent does not disable filter");
   Check(!TpCostSet(true,101)&&!TpCostSet(true,-1),"invalid limit cannot change state");
   Check(TpCostPercent("20,5",value)&&value==20.5&&!TpCostPercent("nan",value)&&!TpCostPercent("1.2.3",value),"strict percentage editor");
   string meta="BASE|OLD=1";bool enabled=true;double maximum=99;
   Check(TpCostStripMeta(meta,enabled,maximum)&&!enabled&&maximum==20&&meta=="BASE|OLD=1","old strategies default OFF without inheritance");
   meta="BASE|OLD=1|"+TpCostPack(true,17.125);
   Check(TpCostStripMeta(meta,enabled,maximum)&&enabled&&maximum==17.125&&meta=="BASE|OLD=1","new metadata round trip");
   meta="BASE|TCOST1=1,20|TCOST1=1,99";
   Check(!TpCostStripMeta(meta,enabled,maximum),"duplicate or malformed cost suffix rejected");
   string lines[];ArrayResize(lines,2);lines[0]="OLD";lines[1]="TCOST1=1,25.00000000";
   Check(TpCostStripLines(lines,enabled,maximum)&&enabled&&maximum==25&&ArraySize(lines)==1,"Sol optional extension round trip");
   double distance=0;
   Check(TpCostEstimate(_Symbol,10,5,0,distance)&&MathAbs(distance-15*_Point)<1e-12,"spread and configured slippage included once");
   double size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(size>0&&tickValue>0)
   {Check(TpCostEstimate(_Symbol,0,0,2,distance)&&MathAbs(distance-2*size/tickValue)<1e-12,"configured commission converted to price units");}
   Check(!TpCostEstimate(_Symbol,-1,0,0,distance),"negative spread never treated as free");
   TpCostSet(false,20);
}
