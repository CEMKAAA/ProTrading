HistResult BeforeSimulateTrade(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                             double tp1,double tp2,double tp3,int halfBeLeg,bool scheduledEndReached=true,
                             datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ulong tickReadFailures=g_auditTickReadFailures;
   HistResult res;
   res.maxTp=0;res.outcome="open";res.netR=0;res.isWin=false;
   res.simEntry=entry;res.entryTime=0;res.entrySpreadPoints=EMPTY_VALUE;res.simSl=sl;res.simTarget=0;res.costR=0;
   res.exitMode=RuntimeExitLabel();res.exitPrice=0;res.exitTime=0;
   res.valid=false;res.invalidReason="NO_MARKET_DATA";res.modeledReverseExit=false;
   res.targetLeg=RuntimeTargetLeg();res.hcLeg=ClampHalfBeLeg(halfBeLeg,res.targetLeg);
   if(g_rtAdvancedAuditEngine&&!g_rtAdvancedReverse)
   {
      HistResult advanced=res;
      if(SimulateTradeTicksAdvanced(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,advanced,forcedExitTime,forcedExitOutcome))
      {
         if(InpAdvancedAuditShadowParity)
         {
            HistResult legacy=res;
            bool savedResumeAllowed=g_histTickResumeAllowed;
            g_histTickResumeAllowed=false;
            ClearHistoricalTickResume();
            bool legacyAvailable=SimulateTradeTicks(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,legacy,forcedExitTime,forcedExitOutcome);
            g_histTickResumeAllowed=savedResumeAllowed;
            ClearHistoricalTickResume();
            if(legacyAvailable)
            {
               g_orbAdvParityChecks++;
               string parityDetail="";
               if(!OrbAdvancedAuditEquivalent(advanced,legacy,parityDetail))
               {
                  g_orbAdvParityMismatches++;
                  Print("ORB15v3 ADV PARITY MISMATCH; legacy selected | ",parityDetail);
                  return legacy;
               }
            }
         }
         return advanced;
      }
   }
   if(SimulateTradeTicks(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,res,forcedExitTime,forcedExitOutcome))
      return res;
   if(res.invalidReason=="INVERSE_GAP_BLOCK")return res;
   if(g_auditTickReadFailures!=tickReadFailures){res.valid=false;res.invalidReason="TICK_HISTORY_PENDING";res.netR=0;res.isWin=false;return res;}
   if(g_rtInvertMode){res.valid=false;res.invalidReason="INVERSE_TICKS_REQUIRED";res.netR=0;res.isWin=false;return res;}
   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();
   ResetLastError();
   MqlRates r[];int c=CopyRates(_Symbol,entryTf,sigTime,tradeEnd,r);
   int ratesError=GetLastError();
   if(ratesError!=0){res.invalidReason="BAR_HISTORY_PENDING";return res;}
   if(c<=1)return res;
   int signalSeconds=PeriodSeconds(entryTf);if(signalSeconds<=0)signalSeconds=60;
   if(r[0].time>sigTime||r[0].time+signalSeconds<=sigTime){res.invalidReason="BAR_HISTORY_PREFIX_MISSING";return res;}
   int fillBarIndex=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?0:1);
   double historicalSpreadPts=r[fillBarIndex].spread>0?(double)r[fillBarIndex].spread:g_btSpreadPts;
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && c>1) entry=r[1].open;
   else if(g_btFillMode==BT_FILL_CONSERVATIVE && c>1)
   {
      double no=r[1].open;
      entry=isBuy?MathMax(entry,no):MathMin(entry,no);
   }
   entry=NormalizeTradePrice(entry);
   double risk=0.0;
   double gt1=0,gt2=0,gt3=0,gt4=0,gt5=0,gt6=0;
   string barGeometryDetail="";
   if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,gt1,gt2,gt3,gt4,gt5,gt6,0.0,barGeometryDetail))
   {res.invalidReason="INVALID_GEOMETRY";return res;}

   int sec=PeriodSeconds(entryTf);if(sec<=0)sec=60;
   int ctxBars=MathMax(320,MathMax(MathMax(InpExitEmaPeriod*4,InpExitAtrPeriod*4),100));
   MqlRates ctx[];int ctxCount=CopyRates(_Symbol,entryTf,sigTime-(datetime)(ctxBars*sec),tradeEnd,ctx);

   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   double tps[6];
   tps[0]=gt1;tps[1]=gt2;tps[2]=gt3;tps[3]=gt4;tps[4]=gt5;tps[5]=gt6;
   double targetPrice=0.0,targetR=0.0;string targetDetail="";
   if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail)){res.invalidReason="INVALID_TARGET";return res;}
   res.valid=true;
   res.invalidReason="";
   bool fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
   res.simEntry=NormalizePrice(entry);
   res.entryTime=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?BarCloseTime(entryTf,r[0].time):r[1].time);
   res.entrySpreadPoints=EMPTY_VALUE; // Bar fallback has no observed entry quote.
   res.simSl=NormalizePrice(sl);
   res.simTarget=fixedTarget?targetPrice:0.0;

   bool exactTimedReverse=g_maReverseExit&&g_maReverseWait>0&&forcedExitTime>sigTime&&forcedExitOutcome=="MA_REVERSE_EXIT";
   bool reverseM1Model=exactTimedReverse&&g_rtExitMode==ORB_EXIT_FIXED_TARGET&&!g_rtTimeExit;
   bool reverseMinuteScan=false;
   double effSl=sl;bool beApplied=false;
   double bestHigh=entry,bestLow=entry;
   datetime brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(sigTime):0);
   for(int i=1;i<c;i++) // skip signal bar itself
   {
      if(r[i].time>tradeEnd)break;
      // Preserve the existing bar policy before the deadline. Only refine
      // the boundary itself; never use extrema from after the forced exit.
      if(reverseM1Model&&!reverseMinuteScan&&r[i].time+sec>forcedExitTime)
      {
         MqlRates minutes[];ResetLastError();
         int copied=CopyRates(_Symbol,PERIOD_M1,r[i].time,tradeEnd,minutes);
         int error=GetLastError();
         if(error!=0||copied<1||minutes[0].time<r[i].time||minutes[0].time>=r[i].time+sec
            ||(minutes[0].time>r[i].time&&NormalizeTradePrice(minutes[0].open)!=NormalizeTradePrice(r[i].open)))
         {res.valid=false;res.invalidReason="REVERSE_M1_HISTORY_REQUIRED";return res;}
         ArraySwap(r,minutes);c=copied;sec=60;reverseMinuteScan=true;i=-1;
         continue;
      }
      if(exactTimedReverse&&r[i].time+sec>forcedExitTime
         &&(!reverseM1Model||r[i].time<forcedExitTime))
      {res.valid=false;res.invalidReason="REVERSE_TICKS_REQUIRED";return res;}
      if(forcedExitTime>sigTime && r[i].time>=forcedExitTime)
      {
         double forcedPrice=0.0;datetime resolvedAt=forcedExitTime;
         if(reverseM1Model)
         {
            double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
            double spread=MathMax(0.0,r[i].spread>0?(double)r[i].spread:g_btSpreadPts);
            if(point<=0||r[i].open<=0){res.valid=false;res.invalidReason="REVERSE_M1_QUOTE_INVALID";return res;}
            forcedPrice=NormalizeTradePrice(r[i].open+(isBuy?0:spread*point));
            resolvedAt=r[i].time;res.modeledReverseExit=true;
         }
         else ResolveHistoricalForcedExitPrice(forcedExitTime,isBuy,r[i].open,(double)r[i].spread,forcedPrice,resolvedAt);
         bool forcedSlHit=isBuy?(forcedPrice<=effSl):(forcedPrice>=effSl);
         bool forcedTargetHit=fixedTarget&&(isBuy?(forcedPrice>=targetPrice):(forcedPrice<=targetPrice));
         if(forcedSlHit)
         {
            res.outcome=beApplied?"BE":"SL";
            res.exitPrice=effSl;
         }
         else if(forcedTargetHit)
         {
            res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");
            res.exitPrice=targetPrice;
         }
         else
         {
            int forcedHitLeg=0;
            for(int k=0;k<6;k++)
               if(isBuy?(forcedPrice>=tps[k]):(forcedPrice<=tps[k]))forcedHitLeg=k+1;
            if(forcedHitLeg>res.maxTp)res.maxTp=forcedHitLeg;
            if(hcLeg>0&&res.maxTp>=hcLeg&&!beApplied){effSl=entry;beApplied=true;}
            res.outcome=forcedExitOutcome!=""?forcedExitOutcome:"FILTER_REVERSE_EXIT";
            res.exitPrice=forcedPrice;
         }
         res.exitTime=resolvedAt;
         break;
      }
      if(reverseMinuteScan&&r[i].time+sec>tradeEnd)break;
      bool slHit=isBuy?(r[i].low<=effSl):(r[i].high>=effSl);

      int hitLeg=0;
      if(fixedTarget)
      {
         for(int k=0;k<6;k++)
         {
            bool hit=isBuy?(r[i].high>=tps[k]):(r[i].low<=tps[k]);
            if(hit)hitLeg=k+1;
         }
         bool customTargetHit=isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice);
         if(customTargetHit&&g_rtTargetMode!=ORB_TARGET_R_LEG)hitLeg=MathMax(hitLeg,MathMin(6,targetLeg));
      }

      // Resolve a same-bar SL/profit collision against the actual configured target.
      // The special 0.75R target is not a numbered TP milestone and must never index tps[].
      bool targetTouched=fixedTarget&&(isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice));
      if(slHit&&(hitLeg>0||targetTouched))
      {
         int compareLeg=MathMax(1,MathMin(6,hitLeg));
         double profitTouchPrice=targetTouched?targetPrice:tps[compareLeg-1];
         if(BtTpFirst(isBuy,r[i].open,effSl,profitTouchPrice))
         {
            res.maxTp=hitLeg;
            if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
            if(targetTouched){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;res.exitTime=r[i].time;break;}
            // Profit milestone came first, then the same bar also crossed protection.
            res.outcome=beApplied?"BE":"SL";
            res.exitPrice=effSl;
            res.exitTime=r[i].time;
            break;
         }
         else{res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;res.exitTime=r[i].time;break;}
      }
      else
      {
         if(slHit){res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;res.exitTime=r[i].time;break;}
         if(hitLeg>res.maxTp)res.maxTp=hitLeg;
      }

      if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
      if(fixedTarget)
      {
         bool targetHit=isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice);
         if(targetHit){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;res.exitTime=r[i].time;break;}
      }

      if(g_rtTimeExit && InpTimeExitMinutes>0 && r[i].time>=sigTime+InpTimeExitMinutes*60)
      {
         double progressR=SimSignedR(isBuy,entry,r[i].close,risk);
         if(progressR<InpTimeExitMinProgress)
         {
            res.outcome="TIME_EXIT";
            res.exitPrice=r[i].close;
            res.exitTime=r[i].time;
            break;
         }
      }

      if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&r[i].time>=brokerExitAt)
      {
         res.outcome="BROKER_TIME_EXIT";
         res.exitPrice=r[i].close;
         res.exitTime=r[i].time;
         break;
      }

      bestHigh=MathMax(bestHigh,r[i].high);
      bestLow=MathMin(bestLow,r[i].low);
      bool dynStart=(g_rtExitTrailStartLeg<=0||res.maxTp>=g_rtExitTrailStartLeg);
      int grace=MathMax(0,InpExitGraceBars);
      bool graceDone=(i>grace);
      if(res.outcome=="open"&&dynStart&&graceDone)
      {
         if(g_rtExitMode==ORB_EXIT_ORB_MID_INVALIDATION)
         {
            double mid=(g_orbHigh>g_orbLow?NormalizePrice((g_orbHigh+g_orbLow)/2.0):0.0);
            bool ex=mid>0.0&&(isBuy?(r[i].close<mid):(r[i].close>mid));
            if(ex){res.outcome="MID_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
         else if(g_rtExitMode==ORB_EXIT_VWAP_STOP)
         {
            double vwap=SessionVwap(g_orbStartServer,r[i].time+sec,PERIOD_M1);
            bool ex=vwap>0.0&&(isBuy?(r[i].close<vwap):(r[i].close>vwap));
            if(ex){res.outcome="VWAP_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
         else if(g_rtExitMode==ORB_EXIT_EMA_STOP&&ctxCount>0)
         {
            double alpha=2.0/(double)(ClampEmaPeriod(g_rtExitEmaPeriod)+1);
            double ema=0.0;bool found=false;
            for(int e=0;e<ctxCount;e++)
            {
               ema=(e==0?ctx[e].close:ema+alpha*(ctx[e].close-ema));
               if(ctx[e].time==r[i].time){found=true;break;}
            }
            bool ex=found&&ema>0.0&&(isBuy?(r[i].close<ema):(r[i].close>ema));
            if(ex){res.outcome="EMA_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
      }
      if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_ATR_TRAIL&&dynStart&&ctxCount>0)
      {
         int ctxIdx=-1;for(int a=0;a<ctxCount;a++)if(ctx[a].time==r[i].time){ctxIdx=a;break;}
         if(ctxIdx>InpExitAtrPeriod+1)
         {
            double atr=0.0;int n=0;
            for(int a=ctxIdx-InpExitAtrPeriod+1;a<=ctxIdx&&a>0;a++)
            {
               double tr=ctx[a].high-ctx[a].low;
               tr=MathMax(tr,MathAbs(ctx[a].high-ctx[a-1].close));
               tr=MathMax(tr,MathAbs(ctx[a].low-ctx[a-1].close));
               atr+=tr;n++;
            }
            if(n>0)
            {
               atr/=n;
               double trail=isBuy?NormalizePrice(bestHigh-atr*g_rtExitAtrMultiplier):NormalizePrice(bestLow+atr*g_rtExitAtrMultiplier);
               if(isBuy&&trail>effSl&&trail<r[i].close)effSl=trail;
               if(!isBuy&&trail<effSl&&trail>r[i].close)effSl=trail;
            }
         }
      }
   }
   if(res.outcome=="open"&&scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&c>1){res.outcome="EOD_EXIT";res.exitPrice=r[c-1].close;res.exitTime=r[c-1].time;}
   else if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&tradeEnd>=brokerExitAt&&c>1){res.outcome="BROKER_TIME_EXIT";res.exitPrice=r[c-1].close;res.exitTime=r[c-1].time;}

   // Net R calculation.
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      bool marketExit=IsSimMarketExitOutcome(res.outcome);
      double marketPx=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
      double runnerR=marketExit?SimSignedR(isBuy,entry,marketPx,risk):0.0;
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0));
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      if((g_rtTargetMode==ORB_TARGET_R_LEG&&res.outcome==TargetOutcomeLabel(targetLeg))||(g_rtTargetMode!=ORB_TARGET_R_LEG&&res.outcome=="TARGET"))
      {
         if(hcLeg>0)res.netR=0.5*LegR(hcLeg)+0.5*targetR;
         else res.netR=targetR;
      }
      else if(IsSimMarketExitOutcome(res.outcome))
      {
         double px=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
         double runnerR=SimSignedR(isBuy,entry,px,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))&&hcLeg>0&&res.maxTp>=hcLeg)
         res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   // Tick history is not available for every historical interval. In OHLC
   // fallback use that entry bar's recorded spread, never today's snapshot.
   double costSpread=res.modeledReverseExit&&!isBuy&&IsSimMarketExitOutcome(res.outcome)?0.0:historicalSpreadPts;
   res.costR=BtCostRForSpread(risk,costSpread);
   res.netR-=res.costR;
   res.isWin=res.netR>0;
   return res;
}
