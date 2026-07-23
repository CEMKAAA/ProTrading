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

   string suffix=InpValidationJobId!=""?InpValidationJobId:
      (_Symbol+"_"+TfLabel(g_rtSignalTf)+"_"+IntegerToString((int)TimeCurrent()));
   StringReplace(suffix," ","_");StringReplace(suffix,":","_");StringReplace(suffix,"/","_");
   string eventFile="ORB_RegimeMatrix_Events_"+suffix+".csv";
   string matrixFile="ORB_RegimeMatrix_Summary_"+suffix+".csv";
   int eh=FileOpen(eventFile,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(eh!=INVALID_HANDLE)
      FileWrite(eh,"job_id","build","symbol","chart_tf","signal_tf","signal_time","year","direction",
         "regime_bucket","regime","entry","sl","target","outcome","net_r","is_win",
         "pip_sl","target_r","delay_min","atr_filter","vol_filter","day_filter",
         "time_exit","entry_mode","fill_mode","same_bar_policy","native_parity");

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
   int classified=0,unknown=0;

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
      HistResult sim=SimulateTrade(entryT,g_btDays[di].tradeEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,RuntimeHalfBeLeg());
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;

      RegimeV3Snapshot snapshot;
      int regimeBucket=OrbRegimeBucketAt(ob.sigTime,snapshot);
      if(regimeBucket<0||regimeBucket>=ORB_REGIME_COUNT){unknown++;continue;}
      OrbBtStats st=bucketStats[regimeBucket];
      st.total++;st.netR+=sim.netR;
      if(sim.netR>0.0){st.wins++;st.wonR+=sim.netR;}
      else if(sim.netR<0.0){st.losses++;st.lostR+=MathAbs(sim.netR);}
      bucketStats[regimeBucket]=st;classified++;

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
            EntryModeLabel(g_rtEntryMode),BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),(g_btNativeParity?"1":"0"));
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
   Print("ORB_REGIME_MATRIX_DONE job=",InpValidationJobId," events=",classified," unknown=",unknown,
      " weeks=",g_btWeeks," elapsed_ms=",GetTickCount()-started," events_file=",eventFile," summary_file=",matrixFile);
   ArrayFree(g_btDays);ArrayResize(g_btBreakouts,0);g_btDayCount=0;
}

#endif
