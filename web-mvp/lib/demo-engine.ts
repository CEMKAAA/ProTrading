export type Feature = "EMA trend" | "RSI" | "ADX" | "Candle body / ATR" | "Price / EMA" | "5-bar breakout";
export type Rule = { id: number; feature: Feature; operator: ">" | "<"; threshold: number; join: "AND" | "OR" | "XOR"; negate: boolean };
export type Candle = { time: number; open: number; high: number; low: number; close: number; volume: number; ema12: number; ema26: number; rsi: number; adx: number; atr: number; hh: number; ll: number };
export type Trade = { id: number; entry: number; exit: number; direction: "BUY" | "SELL"; entryPrice: number; exitPrice: number; sl: number; tp: number; r: number; outcome: "WIN" | "LOSS" | "OPEN" | "DATA"; duration: number };
export type Result = { trades: Trade[]; equity: number[]; wins: number; losses: number; data: number; open: number; net: number; dd: number; examined: number };
export const initialRules: Rule[] = [
 { id:1, feature:"EMA trend", operator:">", threshold:0, join:"AND", negate:false },
 { id:2, feature:"RSI", operator:">", threshold:55, join:"AND", negate:false },
 { id:3, feature:"ADX", operator:">", threshold:22, join:"AND", negate:false },
];

// Reproducible synthetic OHLC data, never represented as a real market feed.
export function makeFixture(symbol = "BTCUSD", count = 4032): Candle[] {
 let seed = 7421;
 const random = () => { seed = (Math.imul(seed,1664525) + 1013904223) >>> 0; return seed / 4294967296; };
 const base = symbol === "EURUSD" ? 1.105 : symbol === "XAUUSD" ? 2640 : symbol === "JP225" ? 38700 : 64300;
 let price = base, fast = base, slow = base, gain = 0, loss = 0, atr = base * .0012, tr14 = 0, plus14 = 0, minus14 = 0, adx = 20;
 const candles: Candle[] = [];
 for (let i=0;i<count;i++) {
   const open=price;
   const drift = Math.sin(i / 41) * .00048 + Math.sin(i / 137) * .00018;
   price = open * (1 + drift + (random()-.5) * .0016);
   const high=Math.max(open,price)+base*random()*.00065, low=Math.min(open,price)-base*random()*.00065;
   fast += (price-fast)*2/13; slow += (price-slow)*2/27;
   gain = (gain*13 + Math.max(0,price-open))/14; loss = (loss*13 + Math.max(0,open-price))/14;
   const tr = Math.max(high-low, Math.abs(high-open), Math.abs(low-open)); atr = (atr*13+tr)/14;
   const prev = candles.at(-1), up = prev ? high-prev.high : 0, down=prev ? prev.low-low : 0;
   tr14=(tr14*13+tr)/14; plus14=(plus14*13+(up>down&&up>0?up:0))/14; minus14=(minus14*13+(down>up&&down>0?down:0))/14;
   const pdi=tr14?100*plus14/tr14:0, mdi=tr14?100*minus14/tr14:0; const dx=pdi+mdi?100*Math.abs(pdi-mdi)/(pdi+mdi):0; adx=(adx*13+dx)/14;
   const previous=candles.slice(-5);
   candles.push({time:Date.UTC(2026,8,1)+i*300000,open,close:price,high,low,volume:Math.floor(150+random()*850),ema12:fast,ema26:slow,rsi:loss===0?100:100-100/(1+gain/loss),adx,atr,hh:previous.length?Math.max(...previous.map(c=>c.high)):high,ll:previous.length?Math.min(...previous.map(c=>c.low)):low});
 }
 return candles;
}
export function featureValue(c: Candle, feature: Feature): number {
 switch(feature) {
  case "EMA trend":return (c.ema12-c.ema26)/c.atr;
  case "RSI":return c.rsi;
  case "ADX":return c.adx;
  case "Candle body / ATR":return (c.close-c.open)/c.atr;
  case "Price / EMA":return (c.close-c.ema26)/c.atr;
  case "5-bar breakout":return c.close>c.hh?1:c.close<c.ll?-1:0;
 }
}
export function evaluate(c: Candle, rules: Rule[], short = false): boolean {
 if(!rules.length)return false;
 const values=rules.map(rule=>{
   const raw=featureValue(c,rule.feature);
   // This demo mirrors directional conditions for SELL; ADX remains nondirectional.
   const v=short&&rule.feature!=="ADX"?(rule.feature==="RSI"?100-raw:-raw):raw;
   const result=rule.operator===">"?v>rule.threshold:v<rule.threshold;
   return rule.negate?!result:result;
 });
 return values.slice(1).reduce((acc, value, i)=>rules[i+1].join==="AND"?acc&&value:rules[i+1].join==="OR"?acc||value:acc!==value,values[0]);
}
export function createReplay(candles: Candle[], rules: Rule[], targetR: number, spreadPct: number, mode: "Single" | "Independent" = "Single", maxOpen = 3) {
 if(!Number.isFinite(targetR)||targetR<=0||!Number.isFinite(spreadPct)||spreadPct<0)throw new Error("Invalid risk settings");
 const trades: Trade[]=[]; const active: Trade[]=[]; const equity=[0]; let cursor=40,net=0,peak=0,dd=0;
 return {
  step(size=256) {
   const end=Math.min(candles.length,cursor+size);
   for(;cursor<end;cursor++) {
    const candle=candles[cursor];
    for(let n=active.length-1;n>=0;n--) {
     const trade=active[n]; const halfSpread=candle.close*spreadPct/200;
     const low=candle.low+(trade.direction==="SELL"?halfSpread:-halfSpread),high=candle.high+(trade.direction==="SELL"?halfSpread:-halfSpread);
     const hitSL=trade.direction==="BUY"?low<=trade.sl:high>=trade.sl;
     const hitTP=trade.direction==="BUY"?high>=trade.tp:low<=trade.tp;
     if(!hitSL&&!hitTP)continue;
     trade.exit=cursor;trade.duration=cursor-trade.entry;
     // Intra-bar ordering cannot be known from OHLC. Exclude ambiguity, do not invent winners.
     if(hitSL&&hitTP){trade.outcome="DATA";trade.r=0;trade.exitPrice=NaN;}
     else {trade.outcome=hitTP?"WIN":"LOSS";trade.r=hitTP?targetR:-1;trade.exitPrice=hitTP?trade.tp:trade.sl;net+=trade.r;}
     active.splice(n,1);peak=Math.max(peak,net);dd=Math.max(dd,peak-net);equity.push(net);
    }
    const direction=evaluate(candle,rules)?"BUY":evaluate(candle,rules,true)?"SELL":null;
    if(!direction||active.length>=(mode==="Single"?1:Math.max(1,maxOpen)))continue;
    const distance=candle.atr*.9,spread=candle.close*spreadPct/200;
    if(distance<=spread*2)continue;
    const entryPrice=candle.close+(direction==="BUY"?spread:-spread);
    const trade:Trade={id:trades.length+1,entry:cursor,exit:cursor,direction,entryPrice,exitPrice:entryPrice,sl:entryPrice+(direction==="BUY"?-distance:distance),tp:entryPrice+(direction==="BUY"?distance*targetR:-distance*targetR),r:0,outcome:"OPEN",duration:0};
    trades.push(trade);active.push(trade);
   }
   return Math.min(100,Math.floor(cursor/candles.length*100));
  },
  result():Result {return {trades,equity,wins:trades.filter(t=>t.outcome==="WIN").length,losses:trades.filter(t=>t.outcome==="LOSS").length,data:trades.filter(t=>t.outcome==="DATA").length,open:active.length,net,dd,examined:cursor};},
 };
}
