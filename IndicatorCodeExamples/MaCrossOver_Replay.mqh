#ifndef MA_CROSSOVER_REPLAY_MQH
#define MA_CROSSOVER_REPLAY_MQH
struct MaTrade
{
   datetime signal,at,exitAt;
   int direction,regime;
   double entry,initialStop,initialTarget,stop,target,risk,remaining,realized,gross,net,exitPrice;
   bool done,data,be,partial,pendingPartial;
   string reason;
};
bool MaStartTrade(MaTrade &t,datetime signal,datetime at,int direction,int regime,double entry,double atr,double pip,const MaConfig &c)
{
   ZeroMemory(t);double stopDistance=c.riskMode==0?entry*c.slPct/100:(c.riskMode==1?atr*c.atrMult:pip*c.pips);
   double targetDistance=c.riskMode==0?entry*c.tpPct/100:stopDistance*c.rr;
   if(!MathIsValidNumber(stopDistance)||stopDistance<=0||targetDistance<=0||entry<=0)return false;
   if(c.invert){double swap=stopDistance;stopDistance=targetDistance;targetDistance=swap;}
   t.signal=signal;t.at=at;t.direction=direction;t.regime=regime;t.entry=entry;
   t.risk=stopDistance;t.stop=t.initialStop=entry-direction*stopDistance;
   t.target=t.initialTarget=entry+direction*targetDistance;t.remaining=1;t.reason="OPEN";
   return t.stop>0&&t.target>0;
}
void MaFinish(MaTrade &t,double price,datetime at,string reason,double feePct)
{
   t.gross=t.realized+t.remaining*t.direction*(price-t.entry)/t.risk;
   t.net=t.gross-t.entry/t.risk*feePct/100;
   t.exitPrice=price;t.exitAt=at;t.reason=reason;t.done=true;
}
bool MaAtOpen(MaTrade &t,double bid,double spread,datetime at,double feePct,const MaConfig &c)
{
   double px=bid+(t.direction<0?spread:0);
   if(t.direction*(px-t.stop)<=0){MaFinish(t,px,at,"SL GAP",feePct);return true;}
   if(t.direction*(px-t.target)>=0){MaFinish(t,t.target,at,"TP",feePct);return true;}
   if(t.pendingPartial)
   {
      double fraction=MathMin(t.remaining,c.partialPct/100);
      t.realized+=fraction*t.direction*(px-t.entry)/t.risk;t.remaining-=fraction;
      t.pendingPartial=false;t.partial=true;
   }
   return false;
}
void MaWithinBar(MaTrade &t,const MqlRates &q,double point,double feePct)
{
   double spread=t.direction<0?q.spread*point:0,hi=q.high+spread,lo=q.low+spread;
   bool sl=t.direction>0?lo<=t.stop:hi>=t.stop,tp=t.direction>0?hi>=t.target:lo<=t.target;
   if(sl&&tp){t.done=true;t.data=true;t.exitAt=q.time+60;t.reason="DATA: SL+TP same M1";return;}
   if(sl||tp)MaFinish(t,sl?t.stop:t.target,q.time+60,sl?"SL":"TP",feePct);
}
void MaAtClose(MaTrade &t,double bid,double spread,double atr,const MaConfig &c)
{
   double px=bid+(t.direction<0?spread:0),r=t.direction*(px-t.entry)/t.risk;
   if(c.management>=1&&r>=c.beR)t.be=true;
   if(c.management>=2&&!t.partial&&!t.pendingPartial&&r>=c.partialR)t.pendingPartial=true;
   if(t.be)
   {
      double stop=t.entry;
      if(c.management==3&&atr>0)stop=t.direction>0?MathMax(t.entry,bid-atr*c.trailMult):MathMin(t.entry,bid+spread+atr*c.trailMult);
      t.stop=t.direction>0?MathMax(t.stop,stop):MathMin(t.stop,stop);
   }
}
#endif
