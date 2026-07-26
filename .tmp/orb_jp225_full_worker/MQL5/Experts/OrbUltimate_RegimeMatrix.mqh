#ifndef ORB_ULTIMATE_REGIME_MATRIX_MQH
#define ORB_ULTIMATE_REGIME_MATRIX_MQH

string OBT_RegimeMaskLabel(int mask)
{
   string label="";
   for(int bucket=0;bucket<ORB_REGIME_COUNT;bucket++)
   {
      if((mask&(1<<bucket))==0)continue;
      if(label!="")label+="+";
      label+=OrbRegimeShortName(bucket);
   }
   return label==""?"NONE":label;
}

string OBT_RfMaskLabel(int mask)
{
   if(mask==0)return "NONE";
   string label="";
   for(int i=0;i<ORB_RF_COUNT;i++)
   {
      if((mask&(1<<i))==0)continue;
      if(label!="")label+="+";
      label+=OrbRfRuleCode(i);
   }
   return label;
}

void OBT_RunRegimeMatrix()
{
   if(g_testerRegimeMatrixDone)return;
   g_testerRegimeMatrixDone=true;
   g_btWeeks=MathMax(1,InpTesterRegimeMatrixWeeks);
   uint started=GetTickCount();

   // Use the production fast-audit caches and simulation functions. Only the
   // six regime allow states vary; signal and execution math stay unchanged.
   OBT_PrecomputeDays();
   RegimeV3EnsureTimeline(true);

   OrbBtStats bucketStats[ORB_REGIME_COUNT];
   for(int bucket=0;bucket<ORB_REGIME_COUNT;bucket++)
   {
      bucketStats[bucket].total=0;bucketStats[bucket].wins=0;bucketStats[bucket].losses=0;
      bucketStats[bucket].wonR=0.0;bucketStats[bucket].lostR=0.0;bucketStats[bucket].netR=0.0;
   }

   OrbBtStats rfStats[ORB_RF_COUNT];
   for(int rf=0;rf<ORB_RF_COUNT;rf++)
   {
      rfStats[rf].total=0;rfStats[rf].wins=0;rfStats[rf].losses=0;
      rfStats[rf].wonR=0.0;rfStats[rf].lostR=0.0;rfStats[rf].netR=0.0;
   }
   OrbBtStats allStats;
   allStats.total=0;allStats.wins=0;allStats.losses=0;
   allStats.wonR=0.0;allStats.lostR=0.0;allStats.netR=0.0;

   string suffix=InpValidationJobId!=""?InpValidationJobId:
      (_Symbol+"_"+TfLabel(g_rtSignalTf)+"_"+IntegerToString((int)TimeCurrent()));
   StringReplace(suffix," ","_");StringReplace(suffix,":","_");StringReplace(suffix,"/","_");
   string eventFile="ORB_RegimeMatrix_Events_"+suffix+".csv";
   string matrixFile="ORB_RegimeMatrix_Summary_"+suffix+".csv";
   string rfMatrixFile="ORB_RFMatrix_Summary_"+suffix+".csv";
   int eh=FileOpen(eventFile,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(eh!=INVALID_HANDLE)
      FileWrite(eh,"job_id","build","symbol","chart_tf","signal_tf","signal_time","year","direction",
         "regime_bucket","regime","entry","sl","target","outcome","net_r","is_win",
         "pip_sl","target_r","delay_min","atr_filter","vol_filter","day_filter",
         "time_exit","entry_mode","fill_mode","same_bar_policy","native_parity",
         "sim_valid","invalid_reason","sim_end","exit_time","core","transition_status","age_bucket",
         "effective_age","h1h2_phase","volatility_depth","volatility_impulse","macro_direction",
         "structural_hint","route_known","orb_macro_route","rf_rule","rf_rule_if_cont","rf_rule_if_rev");

   int tfIdx=RuntimeBtTfIndex();
   int delayIdx=0;
   int bestDelayDistance=2147483647;
   int runtimeDelay=g_rtUseDelay?g_rtDelayMin:0;
   for(int i=0;i<OBT_DELAY_COUNT;i++)
   {
      int distance=MathAbs(g_btDelays[i]-runtimeDelay);
      if(distance<bestDelayDistance){bestDelayDistance=distance;delayIdx=i;}
   }
   int slots=OBT_TF_COUNT*OBT_DELAY_COUNT;
   int breakoutIdx=tfIdx*OBT_DELAY_COUNT+delayIdx;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.0001;
   int classified=0,unknown=0,invalid=0,rfMatched=0;
   datetime auditNow=TimeCurrent();

   for(int di=0;di<g_btDayCount;di++)
   {
      if(!g_btDays[di].valid)continue;
      OrbBtBreakout ob=g_btBreakouts[di*slots+breakoutIdx];
      if(!ob.found)continue;
      if(g_rtFilterAtr&&g_btDays[di].dailyAtr>0.0)
      {
         double pct=((g_btDays[di].orbHi-g_btDays[di].orbLo)/g_btDays[di].dailyAtr)*100.0;
         if(pct<InpMinRangeAtrPct||pct>InpMaxRangeAtrPct)continue;
      }
      if(g_rtFilterVol&&ob.preAvgVol>0.0&&ob.sigVol<ob.preAvgVol*InpVolumeMultiplier)continue;
      if(g_rtFilterDay)
      {
         int dow=g_btDays[di].dow;bool dayOk=false;
         if(dow==1&&InpTradeMonday)dayOk=true;if(dow==2&&InpTradeTuesday)dayOk=true;
         if(dow==3&&InpTradeWednesday)dayOk=true;if(dow==4&&InpTradeThursday)dayOk=true;
         if(dow==5&&InpTradeFriday)dayOk=true;
         if(!dayOk)continue;
      }
      string modernReason="",modernDetail="";
      if(!ModernFilterAllows(g_btDays[di].orbEnd,g_btDays[di].tradeEnd,g_rtSignalTf,ob.sigTime,ob.dir,
         g_rtDisplacement,g_rtFvgMode,modernReason,modernDetail))continue;

      datetime entryT=ob.sigTime;double entry=ob.sigClose;string entryDetail="";
      if(!ResolveHistoricalEntry(g_rtEntryMode,ob.dir,ob.sigTime,ob.sigClose,g_btDays[di].orbHi,g_btDays[di].orbLo,
         g_btDays[di].tradeEnd,entryT,entry,entryDetail))continue;
      bool isBuy=ob.dir=="BUY";
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      double rawSl=isBuy?(g_btDays[di].orbLo-buffer):(g_btDays[di].orbHi+buffer);
      double sl=ApplyRuntimeSlFromEntry(isBuy,entry,rawSl);
      double risk=MathAbs(entry-sl);if(risk<=pt)continue;
      double tp1=NormalizePrice(isBuy?entry+risk*LegR(1):entry-risk*LegR(1));
      double tp2=NormalizePrice(isBuy?entry+risk*LegR(2):entry-risk*LegR(2));
      double tp3=NormalizePrice(isBuy?entry+risk*LegR(3):entry-risk*LegR(3));

      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;
      datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=g_btDays[di].orbHi;g_orbLow=g_btDays[di].orbLo;
      g_orbStartServer=g_btDays[di].orbStart;g_orbEndServer=g_btDays[di].orbEnd;g_tradeEndServer=g_btDays[di].tradeEnd;
      datetime simEnd=0;
      HistResult sim=SimulateHistoricalLifecycle(entryT,g_btDays[di].tradeEnd,auditNow,entry,NormalizePrice(sl),isBuy,
         tp1,tp2,tp3,RuntimeHalfBeLeg(),simEnd);
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;

      RegimeV3Snapshot snapshot;
      int regimeBucket=OrbRegimeBucketAt(ob.sigTime,snapshot);
      if(regimeBucket<0||regimeBucket>=ORB_REGIME_COUNT){unknown++;continue;}
      bool continuation=false;string routeLabel="";
      bool routeKnown=OrbMacroRoute(ob.dir,snapshot,continuation,routeLabel);
      string rfRule="",rfIfCont="",rfIfRev="";
      OrbRfRule(snapshot,continuation,routeKnown,rfRule);
      OrbRfRule(snapshot,true,true,rfIfCont);
      OrbRfRule(snapshot,false,true,rfIfRev);
      int rfIndex=OrbRfRuleIndex(rfRule);
      if(!sim.valid)invalid++;
      OrbBtStats st=bucketStats[regimeBucket];
      st.total++;st.netR+=sim.netR;
      if(sim.netR>0.0){st.wins++;st.wonR+=sim.netR;}
      else if(sim.netR<0.0){st.losses++;st.lostR+=MathAbs(sim.netR);}
      bucketStats[regimeBucket]=st;classified++;
      allStats.total++;allStats.netR+=sim.netR;
      if(sim.netR>0.0){allStats.wins++;allStats.wonR+=sim.netR;}
      else if(sim.netR<0.0){allStats.losses++;allStats.lostR+=MathAbs(sim.netR);}
      if(rfIndex>=0&&rfIndex<ORB_RF_COUNT)
      {
         OrbBtStats rst=rfStats[rfIndex];
         rst.total++;rst.netR+=sim.netR;
         if(sim.netR>0.0){rst.wins++;rst.wonR+=sim.netR;}
         else if(sim.netR<0.0){rst.losses++;rst.lostR+=MathAbs(sim.netR);}
         rfStats[rfIndex]=rst;rfMatched++;
      }

      if(eh!=INVALID_HANDLE)
      {
         MqlDateTime sd;TimeToStruct(ob.sigTime,sd);
         FileWrite(eh,InpValidationJobId,ORB15_BUILD,_Symbol,EnumToString(_Period),TfLabel(g_rtSignalTf),
            TimeToString(ob.sigTime,TIME_DATE|TIME_SECONDS),IntegerToString(sd.year),ob.dir,
            IntegerToString(regimeBucket),OrbRegimeName(regimeBucket),
            DoubleToString(sim.simEntry,_Digits),DoubleToString(sim.simSl,_Digits),DoubleToString(sim.simTarget,_Digits),
            sim.outcome,DoubleToString(sim.netR,6),(sim.netR>0.0?"1":"0"),
            DoubleToString(g_rtPipSlPips,1),DoubleToString(RuntimeTargetR(),2),IntegerToString(runtimeDelay),
            (g_rtFilterAtr?"1":"0"),(g_rtFilterVol?"1":"0"),(g_rtFilterDay?"1":"0"),(g_rtTimeExit?"1":"0"),
            EntryModeLabel(g_rtEntryMode),BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),(g_btNativeParity?"1":"0"),
            (sim.valid?"1":"0"),sim.invalidReason,TimeToString(simEnd,TIME_DATE|TIME_SECONDS),
            (sim.exitTime>0?TimeToString(sim.exitTime,TIME_DATE|TIME_SECONDS):""),snapshot.core,snapshot.transitionStatus,
            snapshot.ageBucket,IntegerToString(snapshot.effectiveAge),snapshot.h1h2Phase,snapshot.volatilityDepth,
            snapshot.volatilityImpulse,snapshot.macroDirection,snapshot.structuralHint,(routeKnown?"1":"0"),routeLabel,
            rfRule,rfIfCont,rfIfRev);
      }
   }
   if(eh!=INVALID_HANDLE)FileClose(eh);

   int sh=FileOpen(matrixFile,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(sh!=INVALID_HANDLE)
   {
      FileWrite(sh,"job_id","build","symbol","chart_tf","signal_tf","weeks","pip_sl","target_r","mask",
         "allowed_regimes","total","wins","losses","win_rate","net_r","profit_factor","avg_r",
         "classified_events","unknown_regime_events");
      for(int mask=1;mask<(1<<ORB_REGIME_COUNT);mask++)
      {
         OrbBtStats total;total.total=0;total.wins=0;total.losses=0;total.wonR=0.0;total.lostR=0.0;total.netR=0.0;
         for(int bucket=0;bucket<ORB_REGIME_COUNT;bucket++)
         {
            if((mask&(1<<bucket))==0)continue;
            total.total+=bucketStats[bucket].total;total.wins+=bucketStats[bucket].wins;total.losses+=bucketStats[bucket].losses;
            total.wonR+=bucketStats[bucket].wonR;total.lostR+=bucketStats[bucket].lostR;total.netR+=bucketStats[bucket].netR;
         }
         int resolved=total.wins+total.losses;
         double wr=resolved>0?(double)total.wins/(double)resolved*100.0:0.0;
         double pf=total.lostR>0.0?total.wonR/total.lostR:(total.wonR>0.0?99.9:0.0);
         double avg=total.total>0?total.netR/(double)total.total:0.0;
         FileWrite(sh,InpValidationJobId,ORB15_BUILD,_Symbol,EnumToString(_Period),TfLabel(g_rtSignalTf),
            IntegerToString(g_btWeeks),DoubleToString(g_rtPipSlPips,1),DoubleToString(RuntimeTargetR(),2),
            IntegerToString(mask),OBT_RegimeMaskLabel(mask),IntegerToString(total.total),IntegerToString(total.wins),
            IntegerToString(total.losses),DoubleToString(wr,4),DoubleToString(total.netR,6),
            DoubleToString(pf,6),DoubleToString(avg,6),IntegerToString(classified),IntegerToString(unknown));
      }
      FileClose(sh);
   }
   int rh=FileOpen(rfMatrixFile,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(rh!=INVALID_HANDLE)
   {
      FileWrite(rh,"job_id","build","symbol","chart_tf","signal_tf","weeks","pip_sl","target_r","blocked_mask",
         "blocked_rules","total","wins","losses","win_rate","net_r","profit_factor","avg_r","retention_pct",
         "baseline_total","rf_matched","invalid_events","route_mapping");
      for(int mask=0;mask<(1<<ORB_RF_COUNT);mask++)
      {
         OrbBtStats kept=allStats;
         for(int rf=0;rf<ORB_RF_COUNT;rf++)
         {
            if((mask&(1<<rf))==0)continue;
            kept.total-=rfStats[rf].total;kept.wins-=rfStats[rf].wins;kept.losses-=rfStats[rf].losses;
            kept.wonR-=rfStats[rf].wonR;kept.lostR-=rfStats[rf].lostR;kept.netR-=rfStats[rf].netR;
         }
         int resolved=kept.wins+kept.losses;
         double wr=resolved>0?(double)kept.wins/(double)resolved*100.0:0.0;
         double pf=kept.lostR>0.0?kept.wonR/kept.lostR:(kept.wonR>0.0?99.9:0.0);
         double avg=kept.total>0?kept.netR/(double)kept.total:0.0;
         double retention=allStats.total>0?(double)kept.total/(double)allStats.total*100.0:0.0;
         FileWrite(rh,InpValidationJobId,ORB15_BUILD,_Symbol,EnumToString(_Period),TfLabel(g_rtSignalTf),
            IntegerToString(g_btWeeks),DoubleToString(g_rtPipSlPips,1),DoubleToString(RuntimeTargetR(),2),
            IntegerToString(mask),OBT_RfMaskLabel(mask),IntegerToString(kept.total),IntegerToString(kept.wins),
            IntegerToString(kept.losses),DoubleToString(wr,4),DoubleToString(kept.netR,6),DoubleToString(pf,6),
            DoubleToString(avg,6),DoubleToString(retention,4),IntegerToString(allStats.total),IntegerToString(rfMatched),
            IntegerToString(invalid),"ORB direction equals causal macro direction => continuation");
      }
      FileClose(rh);
   }
   Print("ORB_REGIME_MATRIX_DONE job=",InpValidationJobId," events=",classified," unknown=",unknown,
      " invalid=",invalid," rf_matched=",rfMatched," weeks=",g_btWeeks," elapsed_ms=",GetTickCount()-started,
      " events_file=",eventFile," summary_file=",matrixFile," rf_summary_file=",rfMatrixFile);
   ArrayFree(g_btDays);ArrayResize(g_btBreakouts,0);g_btDayCount=0;
}

#endif
