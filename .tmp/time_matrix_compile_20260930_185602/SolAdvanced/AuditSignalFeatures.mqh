#ifndef AUDIT_SIGNAL_FEATURES_MQH
#define AUDIT_SIGNAL_FEATURES_MQH
string AxSignalFeatureHeader()
{
   return "f_regime_valid,f_regime_available,f_regime_core,f_regime_effective_age,f_regime_confirmed_age,f_regime_age_bucket,f_regime_transition_status,f_regime_transition_type,f_regime_candidate,f_regime_pending,f_regime_required,f_regime_confidence,f_regime_direction,f_regime_direction_pending,f_regime_direction_pending_sessions,f_regime_h1h2_phase,f_regime_vol_depth,f_regime_vol_impulse,f_regime_structural_hint,f_regime_trend_score,f_regime_vol_score,f_nas_status,f_nas_last_available,f_nas_age_seconds,f_nas_direction,f_nas_same_direction,f_nas_state_allowed,f_nas_flow_allowed,f_nas_tick_volume,f_nas_volume_average,f_nas_volume_ratio,f_of_status,f_of_poc,f_of_val,f_of_vah,f_of_profile_count,f_of_buy_proxy,f_of_sell_proxy,f_of_neutral_proxy,f_of_activity,f_of_delta_proxy";
}
string AxSignalFeatures(datetime at,datetime signalBar,int direction)
{
   string out="";RegimeV3Snapshot s;ZeroMemory(s);
   bool ok=RegimeV3SnapshotAt(at,s)&&s.valid&&s.availableTime<=at;
   AxCell(out,(string)ok);
   if(ok)
   {
      AxCell(out,AxTime(s.availableTime));AxCell(out,s.core);AxCell(out,(string)s.effectiveAge);AxCell(out,(string)s.confirmedAge);
      AxCell(out,s.ageBucket);AxCell(out,s.transitionStatus);AxCell(out,s.transitionType);AxCell(out,s.transitionCandidate);
      AxCell(out,(string)s.transitionPending);AxCell(out,(string)s.transitionRequired);AxCell(out,AxNumber(s.transitionConfidence));
      AxCell(out,s.macroDirection);AxCell(out,s.directionPending);AxCell(out,(string)s.directionPendingSessions);
      AxCell(out,s.h1h2Phase);AxCell(out,s.volatilityDepth);AxCell(out,s.volatilityImpulse);AxCell(out,s.structuralHint);
      AxCell(out,AxNumber(s.trendDepthScore));AxCell(out,AxNumber(s.volatilityDepthScore));
   }
   else for(int i=0;i<20;i++)AxCell(out,"");
   datetime nasAt=0;int nasDir=0;bool state=false,flow=false;double volume=EMPTY_VALUE,average=EMPTY_VALUE;
#ifdef AX_SOL
   if(LnNasActive())
   {
      int left=0,right=ArraySize(g_lnNasEvents);
      while(left<right){int mid=(left+right)/2;if(g_lnNasEvents[mid].at<=at)left=mid+1;else right=mid;}
      if(left>0){LnNasEvent e=g_lnNasEvents[left-1];nasAt=e.at;nasDir=e.dir;state=e.stateAllowed;flow=e.flowAllowed;}
   }
#else
   if(g_histNasCacheReady)
   {
      int left=0,right=ArraySize(g_histNasEvents);
      while(left<right){int mid=(left+right)/2;if(g_histNasEvents[mid].availableTime<=at)left=mid+1;else right=mid;}
      if(left>0)
      {
         OrbNasHistoricalEvent e=g_histNasEvents[left-1];nasAt=e.availableTime;nasDir=e.dir=="BUY"?1:-1;
         volume=e.signalVolume;average=e.averageVolume;
         state=!g_rtNasVolumeFilter||(average>0&&volume>=average*g_rtNasVolumeMultiplier);
         flow=!g_rtNasFlowVolumeFilter||(average>0&&volume>=average*g_rtNasFlowVolumeMultiplier);
      }
   }
#endif
   AxCell(out,nasAt>0?"CACHED_CAUSAL_EVENT":"NOT_COMPUTED_OR_NO_PRIOR_EVENT");
   AxCell(out,AxTime(nasAt));AxCell(out,nasAt>0?(string)(long)(at-nasAt):"");AxCell(out,nasAt>0?(string)nasDir:"");
   AxCell(out,nasAt>0?(string)(nasDir==direction):"");AxCell(out,nasAt>0?(string)state:"");AxCell(out,nasAt>0?(string)flow:"");
   AxCell(out,AxNumber(volume));AxCell(out,AxNumber(average));AxCell(out,volume!=EMPTY_VALUE&&average!=EMPTY_VALUE&&average>0?AxNumber(volume/average):"");
#ifdef AX_MA
   string key=McOfCacheKey(_Symbol,g_rtSignalTf,signalBar);int slot=g_mcOf.mode!=0?McOfCacheSlot(key):-1;
   if(slot>=0&&g_mcOfCache[slot].key==key&&g_mcOfCache[slot].snapshot.valid)
   {
      McOfSnapshot of=g_mcOfCache[slot].snapshot;AxCell(out,"BID_QUOTE_PROXY_NOT_AGGRESSOR_VOLUME");
      AxCell(out,AxNumber(of.poc));AxCell(out,AxNumber(of.val));AxCell(out,AxNumber(of.vah));AxCell(out,AxNumber(of.profileCount));
      AxCell(out,AxNumber(of.buy));AxCell(out,AxNumber(of.sell));AxCell(out,AxNumber(of.neutral));
      AxCell(out,AxNumber(of.activity));AxCell(out,AxNumber(of.delta));return out;
   }
#endif
   AxCell(out,"NOT_COMPUTED");for(int i=0;i<9;i++)AxCell(out,"");return out;
}
#endif
