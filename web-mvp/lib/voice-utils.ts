export const speechLocale={en:'en-US',tr:'tr-TR',de:'de-DE'} as const;
export function speechText(text:string){
 return text.replace(/```[\s\S]*?```/g,' ').replace(/https?:\/\/\S+/g,' ').replace(/[*_#`]/g,'').replace(/\s+/g,' ').trim().slice(0,3000);
}
export function selectVoice<T extends {lang:string;localService:boolean}>(voices:T[],language:string):T|undefined{
 const base=language.split('-')[0].toLowerCase(),matching=voices.filter(v=>v.lang.toLowerCase().split('-')[0]===base);
 return matching.find(v=>v.localService)??matching[0];
}
