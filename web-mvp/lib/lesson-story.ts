import { lessonEffect, type ChartFrame } from './lesson-chart.ts';
import type { HelpTopic } from './studio-help';

export type LessonStage='levels'|'quotes'|'slots'|'clock'|'gates'|'profile'|'indicator'|'zone'|'timeline'|'rules'|'evidence'|'candles';
export function clockKind(topic:HelpTopic) {
 const key=(topic.technical??topic.title).toLowerCase();
 if(/daily(maxloss|targetwin)|daily.*start|dayreset/.test(key))return 'daily';
 if(/timezone|clockseason|gmtoffset|utcoffset|nydst/.test(key))return 'zones';
 if(/trade(monday|tuesday|wednesday|thursday|friday)|dayfilter/.test(key))return 'days';
 if(/session|orb(start|end)|tradeend|window/.test(key))return 'session';
 return 'hours';
}
export function lessonStage(topic:HelpTopic):LessonStage {
 const effect=lessonEffect(topic);
 if(['target','stop','inverse','drawing'].includes(effect))return 'levels';
 if(effect==='cost')return 'quotes';
 if(effect==='positions')return 'slots';
 if(effect==='time')return 'clock';
 if(['nas','nas-volume','volume','regime'].includes(effect))return 'gates';
 if(effect==='profile')return 'profile';
 if(['ma','oscillator'].includes(effect))return 'indicator';
 if(['fvg','sweep','range','retest'].includes(effect))return 'zone';
 if(['reverse','wait','cooldown','holding'].includes(effect))return 'timeline';
 if(effect==='logic')return 'rules';
 if(['audit','sizing'].includes(effect))return 'evidence';
 return 'candles';
}
export function lessonCards(topic:HelpTopic,frame:ChartFrame,step:number) {
 const stage=lessonStage(topic),effect=lessonEffect(topic);
 if(stage==='clock'&&clockKind(topic)!=='hours'){
  const kind=clockKind(topic),labels=kind==='zones'?['Exchange clock','UTC instant','Broker clock']:kind==='daily'?['Configured day start','Count closed outcomes','Stop new entries at the limit']:kind==='days'?['Allowed day','Unselected day','Next allowed day']:['Range opens','Range ends','Entry window'];
  return labels.map((label,i)=>({label,value:String(i+1).padStart(2,'0'),tone:step===i?'gold':'blue'}));
 }
 if(stage==='levels')return frame.lines.slice(0,3).map(l=>({label:l.label,value:l.price.toFixed(2),tone:l.tone}));
 if(stage==='quotes')return frame.lines.slice(0,2).map(l=>({label:l.label,value:l.price.toFixed(2),tone:l.tone}));
 if(stage==='indicator')return frame.indicator?[{label:frame.indicator.label,value:frame.indicator.values[17].toFixed(2),tone:'blue'},{label:'Teaching threshold',value:frame.indicator.threshold.toFixed(2),tone:'gold'}]:frame.traces.map(t=>({label:t.label,value:t.values[17].toFixed(2),tone:t.tone}));
 if(stage==='evidence'&&effect==='sizing')return [{label:'Same setup',value:'01',tone:'blue'},{label:'Intended exposure',value:frame.size??'--',tone:'gold'},{label:'Broker constraints',value:'?',tone:'muted'}];
 if(stage==='evidence')return ['Candles','Tick evidence','Known or DATA'].map((label,i)=>({label,value:String(i+1).padStart(2,'0'),tone:step===i?'blue':'muted'}));
 if(stage==='timeline')return [{label:'First event',value:'01',tone:'mint'},{label:'Eligibility interval',value:'02',tone:'gold'},{label:'Later event',value:'03',tone:step===2?'coral':'muted'}];
 if(stage==='zone')return frame.bands.slice(0,2).map(b=>({label:b.label,value:b.low!==undefined&&b.high!==undefined?`${b.low.toFixed(2)} - ${b.high.toFixed(2)}`:`${b.from+1} - ${b.to+1}`,tone:b.tone}));
 if(stage==='gates'||stage==='rules')return [{label:'Illustrated candidates',value:String(frame.marks.length),tone:'blue'},{label:'Eligible candidates',value:String(frame.marks.filter(m=>!m.rejected).length),tone:'mint'},{label:'Rejected candidates',value:String(frame.marks.filter(m=>m.rejected).length),tone:'muted'}];
 return [];
}
