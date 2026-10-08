import type { HelpTopic } from './studio-help';

export type Candle={open:number;high:number;low:number;close:number};
export type Effect='target'|'stop'|'sizing'|'positions'|'reverse'|'wait'|'inverse'|'cost'|'nas'|'nas-volume'|'time'|'timeframe'|'range'|'retest'|'ma'|'oscillator'|'fvg'|'sweep'|'volume'|'profile'|'regime'|'cooldown'|'holding'|'logic'|'audit'|'drawing';
type Tone='mint'|'coral'|'gold'|'blue'|'muted';
export type ChartLine={price:number;label:string;tone:Tone;from?:number;to?:number};
export type ChartMark={bar:number;label:string;tone:Tone;side:'buy'|'sell';rejected?:boolean};
export type ChartBand={from:number;to:number;label:string;tone:Tone;low?:number;high?:number};
export type ChartTrace={values:number[];label:string;tone:Tone};
export type ChartFrame={bars:Candle[];lines:ChartLine[];marks:ChartMark[];bands:ChartBand[];traces:ChartTrace[];activity:number[];note:string;badge:string;size?:string;indicator?:{label:string;values:number[];threshold:number}};

// Synthetic, normalized prices are a teaching canvas, never broker history.
export function teachingCandles(key:string,effect:Effect):Candle[] {
 let seed=2166136261;
 for(const char of key)seed=Math.imul(seed^char.charCodeAt(0),16777619)>>>0;
 const phase=(seed%1000)/1000*Math.PI*2,amplitude=.55+(seed%71)/100,pace=.20+(seed%29)/100;
 const center=(i:number)=>{
  if(effect==='range')return i<9?99.95+Math.sin(i*.8+phase)*.45:i<17?100.35+Math.sin(i*.7)*.35:101.25+(i-17)*.045+Math.sin(i*.8)*.12;
  if(effect==='retest')return i<12?100+Math.sin(i*.6+phase)*.35:i<17?101.15+(i-12)*.1:i<23?101.6-(i-17)*.10:101.15+(i-23)*.1;
  if(effect==='regime')return i<11?99.4+i*.13:i<22?100.8+Math.sin(i*1.1)*.25:100.7+Math.sin(i*.9)*.9;
  if(effect==='ma'||effect==='logic')return 100+Math.sin(i*pace+phase)*amplitude+(i-16)*.025;
  if(effect==='sweep')return 100+Math.sin(i*.47+phase)*.5;
  return 100+Math.sin(i*pace+phase)*amplitude+Math.sin(i*.83+phase)*.27+(i-16)*((seed%9)-4)*.011;
 };
 return Array.from({length:32},(_,i)=>{
  const open=i?center(i-1):center(0)-.16,close=center(i),wick=.13+((seed+i*13)%21)/100;
  return {open,close,high:Math.max(open,close)+wick,low:Math.min(open,close)-wick*.85};
 });
}
const eventBars=[5,9,12,17,22,27];
const n=(value:unknown,fallback:number)=>Number.isFinite(Number(value))?Number(value):fallback;
const clamp=(v:number,a:number,b:number)=>Math.max(a,Math.min(b,v));
const keyOf=(topic:HelpTopic)=>topic.technical??topic.title;

export function lessonEffect(topic:HelpTopic):Effect {
 const key=keyOf(topic),k=key.toLowerCase();
 if(/atrperiod|slatr|tpatr/.test(k)&&!key.startsWith('Inp'))return 'audit';
 if(/draw|dashboard/.test(k))return 'drawing';
 if(/advancedaudit|backtest|historical|audit|retry|calc.*bars|history.*bars|signalcalcbars|regimev3(history|retry)/.test(k))return 'audit';
 if(/inverse.*(gap|cost)|maxspread|slippage|commission|spreadpts|deviation|cost|tolerance.*%/.test(k))return 'cost';
 if(/invert|inversion|advancedreverse/.test(k))return 'inverse';
 if(/reversewait|naswait|oppositeexitwait|age|lookbackminutes|grace|delay/.test(k))return 'wait';
 if(/nasrsilength|nasatrlen/.test(k))return 'oscillator';
 if(/nas.*(volume|multiplier)|nasstatevolume|nasflowvolume|nasstatemultiplier|nasflowmultiplier/.test(k))return 'nas-volume';
 if(/nas|a second signal/.test(k))return 'nas';
 if(/nextdayexit|reverseexit|closeonreverse|filteredwindowreverse|opposite.*exit/.test(k))return 'reverse';
 if(/independent|maxopen|maxconsecutive|duplicate|blocksamedirection|positions|multiple/.test(k))return 'positions';
 if(/daily(maxloss|targetwin)|dayreset|daily.*start|timematrix|trade(monday|tuesday|wednesday|thursday|friday)|timezone|clockseason|gmtoffset|utcoffset|hour|nydst|window|session|orb(start|end)|tradeend|utc.*gmt/.test(k))return 'time';
 if(/timeframe|entrytf|htf/.test(k))return 'timeframe';
 if(/risk|balance|capital|lot|portfolio|maxmargin|liquidate|safetybuffer|unprotected|failclosed/.test(k))return 'sizing';
 if(/orderflow.*(bins|valuearea)|profile/.test(k))return 'profile';
 if(/orderflow|volume|activity/.test(k))return 'volume';
 if(/regime|rf\d|regimes/.test(k))return 'regime';
 if(/targetr|tp\d|singletp|targettp|targetmode|rangetarget|stop.*target|profittarget/.test(k))return 'target';
 if(/pipsl|sldistance|slbuffer|stopmodel|geometry|stop loss/.test(k))return 'stop';
 if(/halfbe|movetobe|beoffset|trail|exitatr|exitema|exitengine|exit.*leg/.test(k))return 'holding';
 if(/retest|entrymode|entrymodel/.test(k))return 'retest';
 if(/sweep|swing|smt|asia.*liquidity/.test(k))return 'sweep';
 if(/fvg|imbalance|displacement|wick/.test(k))return 'fvg';
 if(/rsi|adx|atrlen|atrperiod|rangeatr/.test(k))return 'oscillator';
 if(/ma(fast|medium|slow)length|crosspair|ema|sma|hma/.test(k))return 'ma';
 if(/cooldown/.test(k))return 'cooldown';
 if(/maxbars|maxminutes|exitsenabled|policy|timeexit|holding/.test(k))return 'holding';
 if(/logic|builder|edge|entrypreset|macrossmode|entrydirection|signal mode|signal generation/.test(k))return 'logic';
 if(/breakout|confirmbars|smallstop|range/.test(k))return 'range';
 if(topic.diagram==='clock')return 'time';
 if(topic.diagram==='risk')return 'sizing';
 if(topic.diagram==='signal'||topic.diagram==='logic')return 'logic';
 return 'audit';
}

export const effectSteps:Record<Effect,[string,string,string]>={
 target:['Locate the same entry and stop','Move only the target level','Compare the target distances'],
 stop:['Locate the entry candle','Change the stop-distance setting','See the stop move on the chart'],
 sizing:['Keep the same setup and price levels','Change the capital or risk setting','See intended exposure, not a new signal'],
 positions:['Show the candidate signals','Count positions that are still open','Block only when capacity is full'],
 reverse:['Open a position on the first signal','A later opposite signal appears','The enabled reverse rule may close it'],
 wait:['Open the trade and start its wait','Ignore an ineligible early signal','A later eligible event may act'],
 inverse:['Show the normal direction and levels','Request the opposite direction','Inspect inverse levels and costs'],
 cost:['Show bid and ask around the entry','Compare the gap with the allowed cost','Accept or reject this candidate'],
 nas:['Show engine candidates and NAS events','Compare the required direction','Allow matching setups or an eligible exit'],
 'nas-volume':['Show separate NAS state and flow events','Apply the relevant volume threshold','Only that NAS stream is qualified'],
 time:['Show the same historical candles','Select the allowed clock/day interval','Allow only candidates in that interval'],
 timeframe:['Show individual signal candles','Group them into a wider timeframe','Indicators use the selected candle series'],
 range:['Build the opening-range context','Check breakout and confirmation','The qualified candidate can be accepted'],
 retest:['Price breaks the marked level','Wait for the configured return/touch','Accept a qualifying continuation'],
 ma:['Show the same close-price series','Calculate the selected average context','Compare the smoother or faster trace'],
 oscillator:['Keep the same price candles','Inspect the derived indicator context','A selected threshold qualifies the setup'],
 fvg:['Identify the marked three-bar context','Check its gap, touch or strength rule','Permit a qualifying candidate'],
 sweep:['Mark a prior liquidity level','Price trades through that level','Inspect the required sweep confirmation'],
 volume:['Show activity under each candle','Compare with the reference threshold','Keep only qualifying activity'],
 profile:['Distribute activity across price bins','Mark the selected profile region','Compare price with that region'],
 regime:['Show different market-state regions','Choose which state is permitted','Block candidates in a disabled state'],
 cooldown:['A trade closes on this candle','Count the configured waiting candles','A later candidate is eligible again'],
 holding:['Open the trade','Inspect the selected exit/holding rule','A non-TP exit can have fractional R'],
 logic:['Show separate BUY and SELL candidates','Evaluate the selected rule or signal core','Accept only its qualifying candidates'],
 audit:['Keep entries and geometry unchanged','Process the required historical evidence','Display known results or missing data'],
 drawing:['Keep the exact same trade','Change only its chart presentation','Signal mathematics and PnL do not change'],
};

function average(values:number[],period:number,sma=false):number[] {
 const p=clamp(Math.round(period),1,5000),alpha=2/(p+1);let ema=values[0];
 return values.map((v,i)=>{ema=i===0?v:alpha*v+(1-alpha)*ema;return sma?values.slice(Math.max(0,i-p+1),i+1).reduce((a,b)=>a+b,0)/Math.min(i+1,p):ema;});
}
function rma(values:number[],period:number):number[] {
 let state=values[0];return values.map((v,i)=>{state=i===0?v:state+(v-state)/period;return state;});
}
function oscillator(bars:Candle[],period:number,kind:'RSI'|'ADX'|'ATR'):number[] {
 // Synthetic warm-up reduces initialization effects. This is not EA parity data.
 const prefix=Array.from({length:250},(_,i)=>bars[i%bars.length]),all=[...prefix,...bars];
 const ranges=all.map((b,i)=>Math.max(b.high-b.low,i?Math.abs(b.high-all[i-1].close):0,i?Math.abs(b.low-all[i-1].close):0)),atr=rma(ranges,period);
 if(kind==='ATR')return atr.slice(-bars.length);
 if(kind==='RSI'){
  const change=all.map((b,i)=>i?b.close-all[i-1].close:0),up=rma(change.map(c=>Math.max(c,0)),period),down=rma(change.map(c=>Math.max(-c,0)),period);
  return up.map((u,i)=>down[i]===0?u===0?50:100:100-100/(1+u/down[i])).slice(-bars.length);
 }
 const plus=all.map((b,i)=>{if(!i)return 0;const u=b.high-all[i-1].high,d=all[i-1].low-b.low;return u>d&&u>0?u:0;}),minus=all.map((b,i)=>{if(!i)return 0;const u=b.high-all[i-1].high,d=all[i-1].low-b.low;return d>u&&d>0?d:0;});
 const p=rma(plus,period),m=rma(minus,period),dx=p.map((v,i)=>v+m[i]===0?0:100*Math.abs(v-m[i])/(v+m[i]));
 return rma(dx,period).slice(-bars.length);
}
function marks(bars:number[],rejected=false):ChartMark[]{return bars.map((bar,i)=>({bar,label:rejected?'Blocked':i%2?'SELL':'BUY',side:i%2?'sell':'buy',tone:rejected?'muted':i%2?'coral':'mint',rejected}));}

export function chartLessonFrame(topic:HelpTopic,step:number):ChartFrame {
 const phase=clamp(Math.floor(step),0,2),key=keyOf(topic),k=key.toLowerCase(),effect=lessonEffect(topic);
 // Seed only by setting identity: changing values/phases preserves comparable history.
 const bars=teachingCandles(key,effect);
 const f:ChartFrame={bars,lines:[],marks:[],bands:[],traces:[],activity:[],badge:key,note:effectSteps[effect][phase]};
 const entry=bars[9].close,stop=entry-1.3;
 const value=topic.currentValue??topic.defaultValue;
 const line=(price:number,label:string,tone:Tone,from=9,to=28)=>f.lines.push({price,label,tone,from,to});
 const band=(from:number,to:number,label:string,tone:Tone,low?:number,high?:number)=>f.bands.push({from,to,label,tone,low,high});
 switch(effect){
  case 'target': {
   const selected=clamp(n(value,1),.1,3),base=selected===1?2:1;
   const r=phase===0?base:selected;
   line(entry,'Entry unchanged','blue');line(stop,'Stop unchanged','coral');line(entry+1.3*r,`Illustrated target ${r.toFixed(2)}R`,'mint');f.marks=marks([9]);
   f.note=`The target moves; this drawing uses ${r.toFixed(2)}R for readability. It is not a forecast or broker fill.`;break;
  }
  case 'stop': {
   const distance=phase===0?.7:1.6;line(entry,'Entry','blue');line(entry-distance,phase===0?'Shorter stop distance':'Wider stop distance','coral');line(entry+distance,'Illustrated 1R target','mint');f.marks=marks([9]);
   f.note=/mode/.test(k)?'The stop-mode switch chooses a distance model; editing a pip number alone does not turn pip mode ON.':'This lesson changes only the stop distance. Normalized chart units are not instrument pips.';break;
  }
  case 'sizing': {
   line(entry,'Same entry','blue');line(stop,'Same stop','coral');line(entry+1.3,'Same target','mint');f.marks=marks([9]);
   if(/lot|margin|portfolio|liquidate|failclosed|unprotected/.test(k)){f.size=phase===0?'Smaller intended volume':'Broker/exposure constraint';f.note='Position sizing and account guards act on exposure or eligibility; they do not move the original signal candle.';}
   else {const capital=k.includes('balance')||k.includes('capital')?Math.max(0,n(value,30))||30:30;const risk=k.includes('riskper')?Math.max(0,n(value,1)):1;f.size=phase===0?`${capital} illustrative account units`:`${(capital*risk/100).toFixed(2)} intended risk units`;f.note='Example percentage sizing only; zero reference capital uses the account/engine default, not a zero-risk account. Fixed-money/fixed-lot modes and broker minimums use their own rules.';}
   break;
  }
  case 'positions': {
   const max=clamp(n(value,2),1,3);f.marks=marks(phase===0?[5]:[5,9,12,17]);
   if(phase>0){band(5,20,'Position A remains open','mint');if(max>1)band(9,24,'Position B remains open','blue');}
   if(phase===2)f.marks=f.marks.map((m,i)=>i>=max?{...m,rejected:true,tone:'muted',label:'Capacity full'}:m);
   f.note='This picture illustrates up to three total open slots. The real MAX counts simultaneous instance-owned BUY plus SELL positions, not consecutive signals.';break;
  }
  case 'reverse': {
   f.marks=[{bar:5,label:'BUY opened',tone:'mint',side:'buy'},...(phase>0?[{bar:17,label:'Later SELL',tone:'coral' as const,side:'sell' as const}]:[])];
   band(5,phase===2?17:28,phase===2?'Reverse exit here':'BUY still open','mint');if(phase===2)line(bars[17].close,'Exit / not necessarily TP','gold',17,24);
   f.note=/nextday/.test(k)?'ORB-only illustration: the opposite setup belongs to a later day. This is separate from general reverse exit.':'A later reverse event can close the earlier position only when the selected existing exit rule permits it.';break;
  }
  case 'wait': {
   if(/age|lookbackminutes/.test(k)){
    f.marks=[{bar:3,label:'Previous NAS state',tone:'mint',side:'buy'},{bar:17,label:'New engine setup',tone:'blue',side:'buy'}];
    band(phase===1?1:13,17,'Accepted entry lookback interval','blue');
    if(phase===2)f.marks[1]={...f.marks[1],label:'Supporting state too old',tone:'muted',rejected:true};
    f.note='This is an entry age check looking backward from a new setup, not a waiting duration after entry. State Gate does not use this recent-age limit.';break;
   }
   if(/delay/.test(k)){band(2,8,'Range construction','blue');band(8,16,'Delay after range end','gold');f.marks=marks([12,20]);if(phase===2)f.marks[0]={...f.marks[0],label:'Delay not finished',tone:'muted',rejected:true};f.note='Breakout delay starts after range construction ends. It is not a position-exit wait.';break;}
   f.marks=[{bar:5,label:'Entry',tone:'mint',side:'buy'},{bar:3,label:'Before entry: ignore',tone:'muted',side:'sell',rejected:true}];
   band(5,16,'Waiting duration','gold');if(phase>0)f.marks.push({bar:10,label:'During wait',tone:'gold',side:'sell'});if(phase===2)f.marks.push({bar:20,label:'After wait',tone:'coral',side:'sell'});
   f.note=/age|lookbackminutes/.test(k)?'Entry-age limits concern whether a previous supporting event is still recent. They are not a post-entry exit wait.':'Illustrative timing, not a minute-to-bar conversion: pre-entry signals are not post-entry exits; SL/TP can still act during a wait.';break;
  }
  case 'inverse': {
   const inverse=phase>0;line(entry,'Same source entry candle','blue');line(stop,inverse?'Inverse target side':'Normal stop side',inverse?'mint':'coral');line(entry+1.3,inverse?'Inverse stop side':'Normal target side',inverse?'coral':'mint');
   f.marks=[{bar:9,label:inverse?'SELL / inverse':'BUY / normal',side:inverse?'sell':'buy',tone:inverse?'coral':'mint'}];f.note='Conceptual 1R level-swap illustration. Engine quote/gap rules and bid/ask still determine actual geometry and outcomes; this is not a W/L swap promise.';break;
  }
  case 'cost': {
   line(entry,'Bid','blue');line(entry+(phase===0?.06:.24),'Ask / quote gap','gold');band(8,12,'Entry quote check','gold');f.marks=marks([9]);if(phase===2)f.marks=[{...f.marks[0],label:'Reject if above limit',tone:'muted',rejected:true}];
   f.note=/slippage|deviation/.test(k)?'Observed quote and eventual fill can differ. A deviation setting is not a guaranteed stop-loss fill.':/commission/.test(k)?'Commission is a separate supported cost, not extra candle movement. This chart does not invent an unknown commission.':'Compare the observed quote cost with this specific setting. Spread in points and an inverse cost percentage are different units.';break;
  }
  case 'nas': {
   f.marks=marks([9,17,24]);line(bars[6].low-.2,'Illustrated latest NAS BUY','mint',6,15);if(phase>0)line(bars[20].high+.2,'Illustrated later NAS SELL','coral',20,29);
   if(phase===2)f.marks=f.marks.map((m,i)=>i===1?{...m,label:'Direction mismatch',tone:'muted',rejected:true}:m);
   f.note=/exit/.test(k)?'The exit stream acts on already open trades under its mode/wait rules. It is not the entry stream.':/sensitivity|rsi|atr/.test(k)?'Changing a NAS core parameter can change its signal stream. These event locations are schematic, not a reimplementation of NAS.':'Compare engine direction with the causal NAS state. State Gate and recent Entry Gate have different age rules.';break;
  }
  case 'nas-volume': {
   f.activity=bars.map((_,i)=>.3+(i%7)/8);f.marks=marks([9,17,24]);if(phase===2)f.marks=f.marks.map((m,i)=>i===1?{...m,label:'NAS volume rejected',tone:'muted',rejected:true}:m);
   band(16,18,/state/.test(k)?'State NAS event':'Flow NAS event','gold');f.note=`This setting qualifies the ${/state|(?<!flow)nasvolume/.test(k)?'state':'flow'} NAS stream. The underlying MA/ORB/Liq signal candles are unchanged. Activity bars are synthetic.`;break;
  }
  case 'time': {
   if(/daily(maxloss|targetwin)/.test(k)){
    const loss=k.includes('loss'),limit=clamp(n(value,2)||2,1,4);
    band(0,31,'One configured trading day','blue');f.marks=marks(eventBars);
    if(phase>0)line(bars[eventBars[limit-1]].close,loss?'Example loss-count limit reached':'Example win-count target reached','gold',eventBars[limit-1],30);
    if(phase===2)f.marks=f.marks.map((m,i)=>i>=limit?{...m,label:'Day count reached',rejected:true,tone:'muted'}:m);
    f.note=`Illustrated ${loss?'loss':'win'} counter blocks later entries once the count is reached. Zero disables the real limit; this illustration uses up to four events. Existing trades remain open under their exit rules.`;break;
   }
   f.marks=marks(eventBars);if(phase>0)band(8,19,'Selected broker-clock interval','blue');if(phase===2)f.marks=f.marks.map(m=>m.bar<8||m.bar>19?{...m,label:'Outside allowed interval',rejected:true,tone:'muted'}:m);
   f.note=/daily.*(loss|win)|dayreset|daily.*start/.test(k)?'Daily counters reset at the selected day boundary. Reaching the count stops subsequent entries, not existing protective exits.':'A clock filter shifts/allows entry eligibility, not the candles themselves. The clock/DST settings must match the broker and exchange.';break;
  }
  case 'timeframe': {
   if(phase>0){f.bars=[];for(let i=0;i<bars.length;i+=3){const chunk=bars.slice(i,i+3);f.bars.push({open:chunk[0].open,close:chunk.at(-1)!.close,high:Math.max(...chunk.map(b=>b.high)),low:Math.min(...chunk.map(b=>b.low))});}}
   f.note=phase===0?'Individual source candles.':'Three source candles are grouped per teaching candle. Selecting the real timeframe changes the actual series and data requirements.';break;
  }
  case 'ma': {
   const closes=bars.map(b=>b.close),period=clamp(n(value,9),1,200);
   f.traces.push({values:average(closes,phase===0?3:period,/sma/.test(k)),label:phase===0?'Faster average example':`Average example / period ${period}`,tone:'gold'});
   f.traces.push({values:average(closes,20),label:'Reference EMA 20',tone:'blue'});if(phase===2)f.marks=marks([9,22]);f.note='These average traces are calculated from the displayed synthetic closes. This illustrates smoothing, not the complete production signal core.';break;
  }
  case 'oscillator': {
   const kind=/rsi/.test(k)?'RSI':/adx/.test(k)?'ADX':'ATR',period=phase===0?7:clamp(n(value,14),1,50),values=oscillator(bars,period,kind);
   f.indicator={label:`${kind} / teaching period ${period}`,values,threshold:kind==='RSI'?50:kind==='ADX'?22:values.reduce((a,b)=>a+b,0)/values.length};
   f.marks=marks([9,17]);if(phase===2)f.marks=f.marks.map(m=>values[m.bar]<f.indicator!.threshold?{...m,label:'Below teaching threshold',rejected:true,tone:'muted'}:m);
   f.note='Wilder-smoothed values are calculated from synthetic candles, with synthetic warm-up. Periods are bounded to 1-50 for this lesson. A teaching threshold is not the full production signal formula.';break;
  }
  case 'fvg': {
   const lo=bars[12].high,hi=lo+.55;bars[14]={open:hi+.1,close:hi+.35,low:hi,high:hi+.6};band(12,25,'Illustrated FVG zone','mint',lo,hi);f.marks=marks([17]);
   if(phase===2)line((lo+hi)/2,'Inspect touch / gap / displacement rule','gold',17,27);f.note='The zone illustrates the selected gap/touch/strength requirement. It does not assert the full engine setup has triggered.';break;
  }
  case 'sweep': {
   const level=bars[12].high;line(level,'Prior liquidity reference','blue',5,24);bars[17]={open:level-.3,close:level-.15,low:level-.55,high:level+.7};if(phase>0)band(16,18,'Wick sweeps the prior high','coral');if(phase===2)f.marks=marks([18]);f.note='A sweep is context, not an unconditional entry. The configured entry/displacement/confirmation conditions remain necessary.';break;
  }
  case 'volume': {
   f.activity=bars.map((_,i)=>.24+(i%9)/9);f.marks=marks(eventBars);if(phase===2)f.marks=f.marks.map(m=>f.activity[m.bar]<.7?{...m,label:'Below activity threshold',tone:'muted',rejected:true}:m);
   f.note=/orderflow/.test(k)?'Directional tick/activity criteria qualify candidates. The activity pane is a broker-flow proxy illustration, not L2/L3 order-book evidence.':'Activity is compared with the selected reference/threshold. NAS volume filtering remains a separate stream.';break;
  }
  case 'profile': {
   const count=phase===0?6:12;f.activity=Array.from({length:count},(_,i)=>.3+Math.sin(i/count*Math.PI)*.6);band(4,28,phase===0?'Wider price buckets':'Finer profile / selected value area','blue',99.5,101.2);line(100.4,'Illustrated activity region','gold',4,28);f.note='Bin count changes profile resolution; value-area fraction changes the covered activity region. Neither creates missing exchange volume.';break;
  }
  case 'regime': {
   band(1,10,'Illustrated trend region','mint');band(11,21,'Illustrated range region','blue');band(22,30,'Illustrated transition','gold');f.marks=marks(eventBars);
   const blocked=(bar:number)=>/trend/.test(k)?bar<=10:/transition/.test(k)?bar>=22:bar>10&&bar<22;
   if(phase===2&&!/observer/.test(k))f.marks=f.marks.map(m=>blocked(m.bar)?{...m,label:'Selected state blocked',rejected:true,tone:'muted'}:m);
   f.note=/observer/.test(k)?'Observer statistics describe context; toggling observation is not itself a regime-entry block.':'This specific state permission applies after regime classification. The example regions are not new regime-detection mathematics.';break;
  }
  case 'cooldown': {
   line(bars[8].close,'Previous trade closes','gold',8,10);f.marks=marks([9,12,17]);if(phase>0)band(8,14,'Cooldown candles','gold');if(phase===2)f.marks=f.marks.map(m=>m.bar<14?{...m,label:'Cooldown active',tone:'muted',rejected:true}:m);f.note='Cooldown starts after a closure, not just after a new signal. The builder policy must be enabled.';break;
  }
  case 'holding': {
   line(entry,'Entry','blue');line(stop,'Protective stop','coral');line(entry+2,'Original target','mint');band(9,phase===2?18:28,'Open position','blue');if(phase===2)line(bars[18].close,'Illustrated rule/time exit','gold',18,26);f.marks=marks([9]);f.note='A holding rule, trail or custom exit can finish before TP/SL. The selected engine mode and enabled policy determine which rule is active.';break;
  }
  case 'range': {
   line(101,'Range high','blue',2,28);line(99,'Range low','blue',2,28);band(2,8,'Opening range','gold',99,101);if(phase>0)f.marks=marks([17]);if(phase===2)band(17,20,'Check breakout / confirmation','mint');f.note='Build the range first, then test the selected breakout, delay or confirmation rule. A later candidate is not a retroactive fill.';break;
  }
  case 'retest': {
   line(101,'Reference breakout level','blue',2,28);band(17,23,'Return / touch region','gold',100.8,101.2);f.marks=marks(phase===0?[17]:[23]);f.note='Retest-style entry waits for a qualifying return and continuation; immediate-break entry acts at a different point.';break;
  }
  case 'logic': {
   f.traces=[{values:average(bars.map(b=>b.close),9),label:'Teaching EMA 9',tone:'gold'}];f.marks=marks(phase===0?eventBars:eventBars.filter((_,i)=>i%2===phase%2));
   if(phase===2)band(8,14,/edge/.test(k)?'State persists / edge choice':'Selected condition context','blue');f.note=/edge/.test(k)?'A transition-only rule fires on false-to-true changes; a state rule can repeat while true.':'Each signal mode or BUY/SELL rule has its own requirements. These marked events demonstrate selection, not exact production signal locations.';break;
  }
  case 'drawing': {
   line(entry,'Entry','blue',9,phase===0?30:17);line(stop,'Stop','coral',9,phase===0?30:17);line(entry+1.3,'Target','mint',9,phase===0?30:17);f.marks=marks([9]);f.note='Presentation-only example: drawing settings affect the visible chart, not the accepted entry or its mathematical result.';break;
  }
  case 'audit': {
   f.marks=marks(eventBars);band(phase===0?0:phase===1?10:22,phase===0?9:phase===1?21:31,'Historical evidence being inspected','blue');f.note=/atrperiod|slatr|tpatr/.test(k)?'This retained builder field does not change the current pip/R geometry. The lesson intentionally leaves all levels unchanged.':'Audit, connection and diagnostic controls affect evidence processing or availability, not the original entry formula. The picture is not a progress estimate.';break;
  }
 }
 return f;
}
