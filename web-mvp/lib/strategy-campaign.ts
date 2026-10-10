export const campaignWindows=[{weeks:2,label:'2W'},{weeks:5,label:'5W'},{weeks:10,label:'10W'},{weeks:20,label:'20W'},
 {weeks:52,label:'1Y'},{weeks:104,label:'2Y'},{weeks:156,label:'3Y'},{weeks:208,label:'4Y'},{weeks:260,label:'5Y'}] as const;
export type CampaignMetrics={total:number;wins:number;losses:number;open:number;flat:number;winRate:number|null;netR:number;minCumR:number};
export type CampaignWindow={weeks:number;status:string;available:boolean;metrics:CampaignMetrics|null;detail?:string};
export type StrategyCampaign={version:1;kind:'MEGA';strategySourceHash:string;engineHash:string;asOf:number;symbol:string;chartTimeframe:number;
 independent:boolean;windows:CampaignWindow[]};

export function campaignWindow(campaign:StrategyCampaign|null|undefined,weeks:number){
 return campaign?.windows.find(w=>w.weeks===weeks);
}

export function campaignTimeframe(minutes:number){
 return minutes<60?`M${minutes}`:minutes%60===0?`H${minutes/60}`:`M${minutes}`;
}

// MT5 campaign timestamps encode broker wall-clock time, not the viewer's timezone.
export function campaignCutoff(asOf:number){
 return new Date(asOf*1000).toISOString().slice(0,19).replace('T',' ');
}
