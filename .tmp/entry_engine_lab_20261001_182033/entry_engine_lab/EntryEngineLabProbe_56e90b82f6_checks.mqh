// Test-only formulas independent of builder rows/comparators.
void CheckScalperFormulas(const MqlRates &rates[])
{
   double stops[]={.9,.7,.65,.55,.5,.45,.55,.35,.3,.2},targets[]={1.2,.9,.8,.7,.6,.55,.7,.4,.35,.25};
   int cooldown[]={5,3,2,1,1,1,1,0,0,0},hold[]={0,0,0,10,0,8,0,6,4,3};
   for(int k=0;k<10;k++)
   {
      LabEngine e,d;Check(LabScalperPreset(k,e),"valid preset "+(string)k);
      Check(e.policy&&!e.edge&&e.slAtr==stops[k]&&e.tpAtr==targets[k]&&e.cooldown==cooldown[k]
         &&e.maxBars==hold[k]&&e.maxMinutes==(k==6?12:0),"recipe policy "+e.name);
      Check(LabEngineRead(LabEngineText(e),d)&&LabEngineText(e)==LabEngineText(d),"LAB3 round trip "+e.name);
      e.policy=false;Check(LabEngineRead(LabEngineText(e),d)&&LabEngineText(e)==LabEngineText(d),"disabled policy settings retained "+e.name);e.policy=true;
      LabRuleStream engine;engine.Reset(e);LabOperandStream fast,slow,rsi,adx,sma,atr,bbTop,bbBottom,hh,ll;
      int fp=k==0?12:(k==1?8:(k==7||k==9?3:(k==8?20:5)));
      int sp=k==0?26:(k==1?21:(k==6?12:(k==7?8:13))),rp=k==0?14:(k==1?9:(k==7?5:(k==9?3:7)));
      fast.Reset(32,fp);slow.Reset(32,sp);rsi.Reset(34,rp);adx.Reset(36,k==0?14:7);sma.Reset(33,50);atr.Reset(35,e.atrPeriod);
      bbTop.Reset(38,20);bbBottom.Reset(39,20);hh.Reset(41,5);ll.Reset(42,5);
      bool same=true,exitSame=true,atrSame=true,bbSame=true,breakoutSame=true;
      for(int i=0;i<ArraySize(rates);i++)
      {
         MqlRates b=rates[i];fast.Push(b);slow.Push(b);rsi.Push(b);adx.Push(b);sma.Push(b);atr.Push(b);
         bbTop.Push(b);bbBottom.Push(b);hh.Push(b);ll.Push(b);
         double f=fast.Current(),s=slow.Current(),r=rsi.Current(),a=adx.Current(),m=sma.Current(),v=atr.Current();
         bool buy=false,sell=false;int exits=0;
         if(i>=200)switch(k)
         {
            case 0:buy=f>s&&r>55&&a>22;sell=f<s&&r<45&&a>22;break;
            case 1:buy=f>s&&b.low<=f&&b.close>f&&r>50;sell=f<s&&b.high>=f&&b.close<f&&r<50;break;
            case 2:buy=b.close>m&&r>52&&rsi.Previous()<=52;sell=b.close<m&&r<48&&rsi.Previous()>=48;exits=(r<48?1:0)|(r>52?2:0);break;
            case 3:buy=f>s&&r>52;sell=f<s&&r<48;break;
            case 4:{double mean=0,variance=0;for(int j=i-19;j<=i;j++)mean+=rates[j].close;mean/=20;
               for(int j=i-19;j<=i;j++)variance+=(rates[j].close-mean)*(rates[j].close-mean);
               double upper=mean+1.5*MathSqrt(variance/20),lower=mean-1.5*MathSqrt(variance/20);
               buy=b.low<lower&&r<40&&b.close>lower;sell=b.high>upper&&r>60&&b.close<upper;
               if(MathAbs(bbTop.Current()-upper)>1e-8||MathAbs(bbBottom.Current()-lower)>1e-8)bbSame=false;break;}
            case 5:{double highest=rates[i-1].high,lowest=rates[i-1].low;
               for(int j=i-5;j<i;j++){highest=MathMax(highest,rates[j].high);lowest=MathMin(lowest,rates[j].low);}
               buy=b.close>highest;sell=b.close<lowest;if(hh.Current()!=highest||ll.Current()!=lowest)breakoutSame=false;break;}
            case 6:buy=f>s&&b.close>m&&r>52&&a>12;sell=f<s&&b.close<m&&r<48&&a>12;break;
            case 7:buy=f>s&&r>51;sell=f<s&&r<49;exits=(f<s?1:0)|(f>s?2:0);break;
            case 8:buy=b.close>b.open&&b.close>f&&MathAbs(b.close-b.open)>.2*v;sell=b.close<b.open&&b.close<f&&MathAbs(b.close-b.open)>.2*v;break;
            case 9:buy=b.close>f&&r>50;sell=b.close<f&&r<50;break;
         }
         int actual=engine.Push(b);if(i>=200){if(actual!=(buy==sell?0:(buy?1:-1)))same=false;
            if(engine.ExitMask()!=exits)exitSame=false;if(MathAbs(engine.PolicyAtr()-v)>1e-10)atrSame=false;}
      }
      Check(same,"independent entry formula "+e.name);Check(exitSame,"independent exit formula "+e.name);
      Check(atrSame,"frozen ATR "+e.name);Check(bbSame,"two-pass BB variance "+e.name);Check(breakoutSame,"prior five excludes current "+e.name);
   }
}
void CheckScalperPolicy()
{
   LabScalperPreset(3,g_labEngine);g_rtMaCrossMode=MA_CROSS_LAB_RULES;g_rtSignalTf=PERIOD_M1;
   LabPolicyBar bars[];ArrayResize(bars,12);datetime opened=D'2026.09.01 09:00';
   for(int i=0;i<12;i++){bars[i].time=opened+(i-1)*60;bars[i].atr=.2;bars[i].exits=0;}
   string reason="";bars[0].exits=1;
   Check(LabPolicyExitFrom(bars,opened,1,opened+3600,reason)==opened+600&&reason=="LAB_TIME_EXIT","hold ignores pre-entry rule");
   bars[4].exits=1;Check(LabPolicyExitFrom(bars,opened,1,opened+3600,reason)==opened+240&&reason=="LAB_RULE_EXIT","first post-entry exit beats hold");
   Check(LabPolicyExitFrom(bars,opened,-1,opened+3600,reason)==opened+600,"separate long/short exits");
   bars[4].exits=0;g_labEngine.maxMinutes=2;Check(LabPolicyExitFrom(bars,opened,1,opened+3600,reason)==opened+120,"earliest minutes vs candles");
   Check(LabPolicyExitFrom(bars,opened,1,opened+30,reason)==0,"no premature exit");
   g_labEngine.cooldown=5;datetime last=iTime(_Symbol,PERIOD_M1,10);
   Check(last>0&&!LabCooldownAllows(iTime(_Symbol,PERIOD_M1,6),last)&&LabCooldownAllows(iTime(_Symbol,PERIOD_M1,5),last),"five candle cooldown boundaries");
   g_labEngine.cooldown=0;Check(LabCooldownAllows(last,last),"zero cooldown");
   g_labGeometryAtr=.2;double entry=150,sl=ApplyRuntimeSlFromEntry(true,entry,0),tp=0,r=0,tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   Check(MathAbs(entry-sl-.2*g_labEngine.slAtr)<=tick,"ATR stop geometry");
   Check(ResolveSourceTargetPriceAndR(true,entry,entry-sl,tp,r,reason)&&MathAbs(tp-entry-.2*g_labEngine.tpAtr)<=tick,"ATR target overrides pip UI");
   Check(!LabPolicyQuoteAllows(true,150.01,150.10,150,150.02)&&LabPolicyQuoteAllows(true,149.95,150.10,150,150.02),"unplaceable stop inside spread is blocked");
   g_labEngine=MakeEngine();Check(StringFind(LabEngineText(g_labEngine),"LAB2~")==0,"legacy serialization unchanged");
   LabScalperPreset(2,g_labEngine);LabOpenBuilder();Click(LabUiPrefix()+"POLICY");
   Check(ObjectGetInteger(0,LabUiPrefix()+"P_APPLY",OBJPROP_ZORDER)>DASH_Z+100
      &&ObjectGetInteger(0,LabUiPrefix()+"P_ATR",OBJPROP_ZORDER)>ObjectGetInteger(0,LabUiPrefix()+"BG",OBJPROP_ZORDER),"modal is above dashboard and background");
   ChartRedraw();ChartScreenShot(0,"EntryEngineLabPolicy.png",1600,900);
   ObjectSetString(0,LabUiPrefix()+"P_COOLDOWN",OBJPROP_TEXT,"8");ObjectSetString(0,LabUiPrefix()+"P_SL",OBJPROP_TEXT,"0.75");Click(LabUiPrefix()+"P_APPLY");
   Check(g_labUi==2&&g_labDraft.cooldown==8&&g_labDraft.slAtr==.75,"policy Apply reads current edits");
   Click(LabUiPrefix()+"LONGEXIT");ObjectSetString(0,LabUiPrefix()+"VALUE_0",OBJPROP_TEXT,"47");Click(LabUiPrefix()+"SHORTEXIT");
   Check(g_labDraft.exitBuy[0].threshold==47&&g_labDraft.exitSell[0].threshold==52,"independent exit editing");Click(LabUiPrefix()+"CLOSE");
}
void RunScalperAudits()
{
   g_probeClock=TimeCurrent();
   string report="engine\ttrades\twins\tlosses\topen\tdata\tnet_R\trule_exits\ttime_exits\telapsed_seconds\n";bool all=true;
   for(int k=0;k<10&&!IsStopped();k++)
   {
      LabScalperPreset(k,g_labEngine);g_labPreviewOnly=true;g_rtMaCrossMode=MA_CROSS_LAB_RULES;g_rtSignalTf=PERIOD_M1;
      g_maIndependent=false;g_maReverseExit=false;g_rtCustomR=g_labEngine.tpAtr/g_labEngine.slAtr;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;
      g_orbReplayMemo.Reset("SCALPER_"+(string)k);MaCrossAuditInvalidate();DeleteHist();ulong started=GetTickCount64();bool ok=RunAudit(2);
      int rules=0,times=0;bool overlap=false,spacing=true,geometry=true;datetime priorExit=0;double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      for(int i=0;i<ArraySize(g_axTrades);i++){AxTrade t=g_axTrades[i];if(!t.valid){Print("SCALPER_DATA ",g_labEngine.name," signal=",TimeToString(t.signalTime)," reason=",t.reason," ATR=",g_labGeometryAtr," SL=",t.plannedSl," entry=",t.plannedEntry);continue;}
         if(t.entryTime<priorExit)overlap=true;if(!LabCooldownAllows(t.availableTime,priorExit))spacing=false;
         priorExit=t.closed?t.exitTime:g_histRunNow;if(t.outcome=="LAB_RULE_EXIT")rules++;if(t.outcome=="LAB_TIME_EXIT")times++;
         if(!LabPolicyGeometryAt(t.signalTime))geometry=false;
         else if(MathAbs(MathAbs(t.plannedEntry-t.plannedSl)-g_labGeometryAtr*g_labEngine.slAtr)>tick*1.01)geometry=false;}
      Check(ok,"M1 2W tick audit "+g_labEngine.name);Check(!overlap,"single position "+g_labEngine.name);
      Check(spacing,"audit cooldown "+g_labEngine.name);Check(geometry,"audit ATR geometry "+g_labEngine.name);all=all&&ok&&!overlap&&spacing&&geometry;
      report+=g_labEngine.name+"\t"+(string)g_histTotal+"\t"+(string)g_histWins+"\t"+(string)g_histLosses+"\t"+(string)(g_histTotal-g_histWins-g_histLosses-g_histInvalid)
         +"\t"+(string)g_histInvalid+"\t"+DoubleToString(g_histNetR,8)+"\t"+(string)rules+"\t"+(string)times+"\t"+DoubleToString((GetTickCount64()-started)/1000.0,3)+"\n";
      Print("SCALPER_RESULT ",g_labEngine.name," trades=",g_histTotal," DATA=",g_histInvalid," rules=",rules," times=",times);if(!ok)break;
   }
   if(all){bool broad=RunAudit(5),warm=RunAudit(2);string identity=AuditIdentity();g_orbReplayMemo.Reset("SCALPER_FORCE_COLD");MaCrossAuditInvalidate();DeleteHist();bool cold=RunAudit(2);
      Check(broad&&warm&&cold&&identity==AuditIdentity(),"policy 5W -> 2W warm/cold parity");
      string name="LAB_POLICY_SNAPSHOT_"+(string)GetTickCount64(),snapshot=LabEngineIdentity();Check(OrbUserSaveLocked(name),"policy strategy save");
      int index=g_strategyPresetIndex;OrbStrategyPreset p;bool loaded=OrbStrategyPresetLoad(index,p);Check(loaded,"policy strategy load");
      if(loaded){g_labEngine=MakeEngine();g_maRestoringPreset=true;bool restored=OrbUserApply(p);g_maRestoringPreset=false;
         Check(restored&&snapshot==LabEngineIdentity(),"strategy restores all policy fields");FileDelete(OrbUserFile(index),FILE_COMMON);FileDelete("EntryEngineLabStrategyLibrary\\"+p.id+".metrics",FILE_COMMON);}}
   int f=FileOpen("EntryEngineLabProbe_56e90b82f6_scalpers.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}else Check(false,"scalper report written");
   FileDelete(LabActiveFile(),FILE_COMMON);
   // A deliberately wider test-only fixture exercises exits before SL/TP.
   LabScalperPreset(2,g_labEngine);g_labEngine.name="Wide exit verification fixture";
   g_labEngine.slAtr=3;g_labEngine.tpAtr=3;g_labEngine.maxBars=3;g_labPreviewOnly=true;
   g_maIndependent=false;g_maReverseExit=false;g_rtSignalTf=PERIOD_M1;g_rtCustomR=1;
   g_orbReplayMemo.Reset("WIDE_POLICY");MaCrossAuditInvalidate();DeleteHist();
   Check(RunAudit(2),"wide exit fixture tick coverage");int forced=0;bool exact=true,clock=true;
   Check(MaExitLoadKernel(g_histRunNow-14*86400),"native policy cache ready without orders");
   for(int i=0;i<ArraySize(g_axTrades);i++){AxTrade t=g_axTrades[i];
      if(t.outcome!="LAB_RULE_EXIT"&&t.outcome!="LAB_TIME_EXIT")continue;forced++;
      double risk=MathAbs(t.entry-t.sl),expected=SimSignedR(t.direction>0,t.entry,t.exitPrice,risk)-t.costR;
      if(risk<=0||MathAbs(expected-t.netR)>1e-8)exact=false;
      string a="",b="";datetime auditAt=LabPolicyExitFrom(g_labPolicyBars,t.entryTime,t.direction,g_histRunNow,a);
      datetime nativeAt=LabPolicyExitFrom(g_labLivePolicyBars,t.entryTime,t.direction,g_histRunNow,b);
      if(auditAt!=nativeAt||a!=b||t.exitTime<auditAt)clock=false;}
   Check(forced>0&&exact,"forced exits use actual price R, not the TP R");Check(clock,"native and audit exit clocks agree");
   string legacy=AuditIdentity();g_rtAdvancedAuditEngine=true;g_orbReplayMemo.Reset("WIDE_ADV_POLICY");DeleteHist();
   Check(RunAudit(2)&&legacy==AuditIdentity(),"advanced / legacy policy replay exact parity");g_rtAdvancedAuditEngine=false;
   g_orbBridgeEnabled=true;Check(!LabNativeEntryPolicy(iTime(_Symbol,PERIOD_M1,1)),"policy refuses unverified listener publication");g_orbBridgeEnabled=false;
   g_orbNativeWithBridgeOnly=false;Check(!LabNativeEntryPolicy(iTime(_Symbol,PERIOD_M1,1)),"policy respects NAT OFF");
   g_probeClock=0;
}
