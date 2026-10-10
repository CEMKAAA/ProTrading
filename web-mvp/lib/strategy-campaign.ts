export const campaignWindows=[{weeks:2,label:'2W'},{weeks:5,label:'5W'},{weeks:10,label:'10W'},{weeks:20,label:'20W'},
 {weeks:52,label:'1Y'},{weeks:104,label:'2Y'},{weeks:156,label:'3Y'},{weeks:208,label:'4Y'},{weeks:260,label:'5Y'}] as const;
export type CampaignMetrics={total:number;wins:number;losses:number;open:number;flat:number;winRate:number|null;netR:number;minCumR:number};
export type CampaignWindow={weeks:number;status:string;available:boolean;metrics:CampaignMetrics|null;detail?:string};
export type StrategyCampaign={version:1;kind:'MEGA';strategySourceHash:string;engineHash:string;asOf:number;symbol:string;chartTimeframe:number;
 independent:boolean;windows:CampaignWindow[]};

export function campaignWindow(campaign:StrategyCampaign|null|undefined,weeks:number){
 return campaign?.windows.find(w=>w.weeks===weeks);
}

export type CampaignSort={key:'winRate'|'total'|'wins'|'losses'|'netR'|'minCumR';direction:'desc'|'asc'};
export function cycleCampaignSort(sorts:CampaignSort[],key:CampaignSort['key']):CampaignSort[]{
 const prior=sorts.find(s=>s.key===key);
 if(!prior)return [...sorts,{key,direction:'desc'}];
 return prior.direction==='desc'?sorts.map(s=>s.key===key?{...s,direction:'asc'}:s):sorts.filter(s=>s.key!==key);
}

export function rankCampaignStrategies<T extends {id:string;name:string;campaign?:StrategyCampaign|null}>(items:T[],weeks:number,sorts:CampaignSort[]):T[]{
 if(!sorts.length)return [...items];
 return [...items].sort((a,b)=>{
  const aw=campaignWindow(a.campaign,weeks),bw=campaignWindow(b.campaign,weeks);
  const am=aw?.available?aw.metrics:null,bm=bw?.available?bw.metrics:null;
  // Missing results always come last, in either direction. Never borrow another window.
  if(!!am!==!!bm)return am?-1:1;
  for(const sort of sorts){
   const av=am?.[sort.key],bv=bm?.[sort.key];
   const aValid=typeof av==='number'&&Number.isFinite(av),bValid=typeof bv==='number'&&Number.isFinite(bv);
   if(aValid!==bValid)return aValid?-1:1;
   if(aValid&&bValid&&av!==bv)return sort.direction==='desc'?bv-av:av-bv;
  }
  return a.name.localeCompare(b.name)||a.id.localeCompare(b.id);
 });
}

export function campaignTimeframe(minutes:number){
 return minutes<60?`M${minutes}`:minutes%60===0?`H${minutes/60}`:`M${minutes}`;
}

// MT5 campaign timestamps encode broker wall-clock time, not the viewer's timezone.
export function campaignCutoff(asOf:number){
 return new Date(asOf*1000).toISOString().slice(0,19).replace('T',' ');
}
