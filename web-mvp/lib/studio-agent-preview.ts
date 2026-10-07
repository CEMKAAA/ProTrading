import {eaCatalog,type UniversalConfiguration} from './universal-contract.ts';
import {controlLabel} from './studio-help.ts';

export const entryPresetNames=['Built-in / Custom selection','Slow EMA + ADX','EMA Pullback','RSI 50-Line Momentum','Fast EMA + RSI','Bollinger Mean-Reversion','ATR Micro-Breakout','EMA + RSI Re-entry','Ultra-Fast EMA State','Candle Momentum','Hyperactive Directional Flip'];
export const builderFeatureNames=['Close','Open','High','Low','RSI14','ADX14','ATR14','EMA9','EMA20','EMA50','EMA200','HMA200','Tick volume','Volume/prior20 mean','Body/range','Range/ATR','RSI change','ADX change','(Close-EMA20)/ATR','EMA50 cross above EMA200','EMA50 cross below EMA200','Bull FVG inside','Bear FVG inside','Bull FVG touch','Bear FVG touch','Bull FVG exists','Bear FVG exists','Hour','Weekday','Close change %','Upper wick/range','Lower wick/range','EMA(period)','SMA(period)','RSI(period)','ATR(period)','ADX Wilder(period)','HMA(period)','BB upper 1.5SD','BB lower 1.5SD','BB middle','Prior highest high','Prior lowest low','Body/Wilder ATR'];
// Reviewed against LabScalperPresets.mqh. Descriptions only: MT5 still computes signals.
export const presetReferenceSha256='db949d32d9cf201507fa5c08ae864ec19bad74c970eb525af112e487677e3e76';
const presetRules=[
 {buy:'EMA(12)>EMA(26) AND RSI(14)>55 AND ADX Wilder(14)>22',sell:'EMA(12)<EMA(26) AND RSI(14)<45 AND ADX Wilder(14)>22',cooldown:5,maxBars:0,maxMinutes:0},
 {buy:'EMA(8)>EMA(21) AND Low<=EMA(8) AND Close>EMA(8) AND RSI(9)>50',sell:'EMA(8)<EMA(21) AND High>=EMA(8) AND Close<EMA(8) AND RSI(9)<50',cooldown:3,maxBars:0,maxMinutes:0},
 {buy:'Close>SMA(50) AND RSI(7) crosses above 52',sell:'Close<SMA(50) AND RSI(7) crosses below 48',exitBuy:'RSI(7)<48',exitSell:'RSI(7)>52',cooldown:2,maxBars:0,maxMinutes:0},
 {buy:'EMA(5)>EMA(13) AND RSI(7)>52',sell:'EMA(5)<EMA(13) AND RSI(7)<48',cooldown:1,maxBars:10,maxMinutes:0},
 {buy:'Low<BB lower(20,1.5 population SD) AND RSI(7)<40 AND Close>BB lower(20,1.5 population SD)',sell:'High>BB upper(20,1.5 population SD) AND RSI(7)>60 AND Close<BB upper(20,1.5 population SD)',cooldown:1,maxBars:0,maxMinutes:0},
 {buy:'Close>Highest high of previous 5 bars (current bar excluded)',sell:'Close<Lowest low of previous 5 bars (current bar excluded)',cooldown:1,maxBars:8,maxMinutes:0},
 {buy:'EMA(5)>EMA(12) AND Close>SMA(50) AND RSI(7)>52 AND ADX Wilder(7)>12',sell:'EMA(5)<EMA(12) AND Close<SMA(50) AND RSI(7)<48 AND ADX Wilder(7)>12',cooldown:1,maxBars:0,maxMinutes:12},
 {buy:'EMA(3)>EMA(8) AND RSI(5)>51',sell:'EMA(3)<EMA(8) AND RSI(5)<49',exitBuy:'EMA(3)<EMA(8)',exitSell:'EMA(3)>EMA(8)',cooldown:0,maxBars:6,maxMinutes:0},
 {buy:'Close>Open AND Close>EMA(20) AND abs(Close-Open)/Wilder ATR(10)>0.2',sell:'Close<Open AND Close<EMA(20) AND abs(Close-Open)/Wilder ATR(10)>0.2',cooldown:0,maxBars:4,maxMinutes:0},
 {buy:'Close>EMA(3) AND RSI(3)>50',sell:'Close<EMA(3) AND RSI(3)<50',cooldown:0,maxBars:3,maxMinutes:0},
];
export const entryPresetGuide=presetRules.map((p,i)=>({value:i+1,name:entryPresetNames[i+1],...p,edge:false,policy:true,exitsEnabled:true}));
const families={entrylab:'Entry Lab',macross:'MA Crossover',orb:'Opening Range',sol:'Liquidity Narrative'};
const signalModes=['MA MTF','EMA 50/200','Trendline','Close/Reverse','Scalp arrows','Trender IQ','Custom BUY / SELL rules'];
const wait=(v:unknown)=>`${String(Math.floor(Number(v)/60)).padStart(2,'0')}:${String(Number(v)%60).padStart(2,'0')}`;

export function settingValue(c:UniversalConfiguration,kind:'inputs'|'runtime',key:string):string{
 const value=c[kind][key],spec=eaCatalog[c.family][kind].find(s=>s.key===key);
 if(key==='entryPreset')return entryPresetNames[Number(value)]??String(value);
 if(key==='InpMaCrossMode')return signalModes[Number(value)]??String(value);
 if(key==='nasGate')return ['OFF','ENTRY GATE','STATE GATE'][Number(value)];
 if(key==='nasExit')return ['OFF','OPP EXIT','ADD EXIT'][Number(value)];
 if(key==='nasWaitMinutes'||key==='reverseWaitMinutes')return wait(value);
 if(typeof value==='boolean')return value?'ON':'OFF';
 return spec?.options?.find(o=>o.value===value)?.label??String(value);
}

export function strategyPreview(c:UniversalConfiguration,weeks:number,symbol:string|null){
 const preset=Number(c.runtime.entryPreset??0);
 const engine=preset?entryPresetNames[preset]:c.inputs.InpMaCrossMode!==undefined?settingValue(c,'inputs','InpMaCrossMode'):families[c.family];
 const rows=[{label:'Strategy',value:c.name},{label:'Entry engine',value:engine===families[c.family]?engine:`${families[c.family]} / ${engine}`},
  {label:'Chart instrument',value:symbol??'Not connected'},
  {label:'Audit window',value:weeks%52===0?`${weeks/52}Y / ${weeks}W`:`${weeks}W`},
  {label:'Profit target (R)',value:`${c.runtime.targetR}R`},
  {label:'Stop model',value:c.inputs.InpPipSlModeDefault?`${c.inputs.InpPipSlPips} pips`:'Engine stop model'},
  {label:'Position mode',value:c.runtime.independent?`INDEPENDENT / ${c.runtime.maxOpen}`:'LEGACY / 1'},
  {label:'Risk per trade (%)',value:`${c.inputs.InpRiskPerTradePct}%`},
  {label:'Close on reverse signal',value:`${settingValue(c,'runtime','reverseExit')} / ${wait(c.runtime.reverseWaitMinutes)}`},
  {label:'Inverse direction',value:settingValue(c,'runtime','inversion')},
  {label:'NAS entry gate',value:settingValue(c,'runtime','nasGate')},
  {label:'NAS exit mode',value:`${settingValue(c,'runtime','nasExit')} / ${wait(c.runtime.nasWaitMinutes)}`},
  {label:'Use selected trade hours',value:settingValue(c,'runtime','timeMatrixEnabled')}];
 for(const key of ['InpSignalTimeframe','InpDefaultEntryTf','InpDefaultHtf','InpBrokerTimezone','InpBrokerClockSeason','InpExchangeClockSeason'])if(c.inputs[key]!==undefined)rows.push({label:controlLabel(key),value:settingValue(c,'inputs',key)});
 return {rows,settings:(['runtime','inputs'] as const).flatMap(kind=>eaCatalog[c.family][kind].map(s=>({kind,key:s.key,label:controlLabel(s.key),group:s.group,value:settingValue(c,kind,s.key)}))),
  dayHourMasks:c.dayHourMasks.map((mask,day)=>({day,hours:Array.from({length:24},(_,h)=>h).filter(h=>!!(mask&(1<<h)))})),builder:c.builder,
  selectedPreset:c.family==='entrylab'&&preset>0?entryPresetGuide[preset-1]:null};
}

export function builderExpression(rows:NonNullable<UniversalConfiguration['builder']>['buy']):string{
 const ops=['>','<','>=','<=','==','!=','crosses above','crosses below'],gates=['AND','OR','XOR'];
 const feature=(id:number,period:number)=>builderFeatureNames[id].replace('(period)',`(${period})`);
 let expression='';
 for(const row of rows){
  const lhs=feature(row.feature,row.period),rhs=row.rhsFeature<0?String(row.threshold):feature(row.rhsFeature,row.rhsPeriod);
  const condition=`${row.negate?'NOT ':''}(${lhs} ${ops[row.comparator]} ${rhs})`;
  expression=expression?`(${expression} ${gates[row.gate]} ${condition})`:condition;
 }
 return expression||'No rules';
}
