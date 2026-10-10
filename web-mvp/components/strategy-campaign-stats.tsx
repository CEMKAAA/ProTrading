"use client";
import type {StrategyCampaign} from '@/lib/strategy-campaign';
import {campaignWindow,campaignTimeframe,campaignCutoff} from '@/lib/strategy-campaign';
import {UiText,useLanguage} from './language-provider';

export default function StrategyCampaignStats({campaign,weeks}:{campaign?:StrategyCampaign|null;weeks:number}){
 const {number,t}=useLanguage(),window=campaignWindow(campaign,weeks);
 if(!campaign)return <p className="campaign-unavailable"><UiText>Verified campaign results are not available for this version.</UiText></p>;
 const metrics=window?.available?window.metrics:null;
 return <div className="strategy-campaign-stats">
  <div className="campaign-context"><span>MEGA / {campaign.symbol} / {campaignTimeframe(campaign.chartTimeframe)}</span><span>{campaign.independent?'INDEPENDENT':'LEGACY'}</span></div>
  {metrics?<dl className="campaign-metrics">
   <div><dt><UiText>Trades</UiText></dt><dd>{number(metrics.total)}</dd></div>
   <div><dt>W / L / O</dt><dd>{number(metrics.wins)} / {number(metrics.losses)} / {number(metrics.open)}</dd></div>
   <div><dt title={t('Win rate uses closed wins and losses only. Open trades are not wins.')}>WR</dt><dd>{metrics.winRate===null?'—':number(metrics.winRate,2)+'%'}</dd></div>
   <div><dt><UiText>Net R</UiText></dt><dd className={metrics.netR>0?'campaign-positive':metrics.netR<0?'campaign-negative':''}>{number(metrics.netR,4)}R</dd></div>
   <div><dt>MinCum</dt><dd>{number(metrics.minCumR,4)}R</dd></div>
   <div><dt><UiText>Flat</UiText></dt><dd>{number(metrics.flat)}</dd></div>
  </dl>:<p className="campaign-unavailable" title={window?.detail}><UiText>Data unavailable for this window</UiText><small>{window?.status??'NOT_AUDITED'}</small></p>}
  <p className="campaign-cutoff"><span><UiText>Audit cutoff (broker time)</UiText></span><time>{campaignCutoff(campaign.asOf)}</time></p>
  {metrics&&<span className="sr-only">{t('Win rate uses closed wins and losses only. Open trades are not wins.')}</span>}
 </div>;
}
