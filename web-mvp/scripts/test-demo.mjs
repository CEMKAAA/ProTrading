import assert from "node:assert/strict";
import { makeFixture, createReplay, initialRules, evaluate, featureValue } from "../lib/demo-engine.ts";
const candles=makeFixture("BTCUSD",4032);
assert.deepEqual(candles,makeFixture("BTCUSD",4032),"Fixture must be deterministic");
assert.ok(candles.every(c=>c.low<=Math.min(c.open,c.close)&&c.high>=Math.max(c.open,c.close)),"OHLC geometry");
assert.ok(candles.every((c,i)=>i===0||c.time-candles[i-1].time===300000),"5 minute UTC chronology");
assert.ok(candles.every((c,i)=>i<5||c.hh===Math.max(...candles.slice(i-5,i).map(b=>b.high))),"Breakout excludes current bar");
function replay(rules,mode="Single",max=1,spread=.015){const r=createReplay(candles,rules,1.5,spread,mode,max);let p=0,previous=0;while(p<100){p=r.step(128);assert.ok(p>=previous);previous=p;}const result=r.result();assert.equal(result.examined,candles.length);assert.equal(result.trades.length,result.wins+result.losses+result.data+result.open);assert.equal(result.net,result.wins*1.5-result.losses);return result;}
const single=replay(initialRules);
assert.ok(single.trades.length>0);
assert.ok(single.open<=1);
assert.ok(single.trades.every((t,i)=>i===0||t.entry>=single.trades[i-1].exit),"No concurrent Single trades");
const independent=replay(initialRules,"Independent",3);
assert.ok(independent.open<=3);
for(let i=40;i<candles.length;i++){const open=independent.trades.filter(t=>t.entry<=i&&(t.outcome==="OPEN"||t.exit>i));assert.ok(open.length<=3,"Independent simultaneous cap");}
assert.equal(replay([{...initialRules[0],feature:"ADX",threshold:101}]).trades.length,0,"Rejecting condition must prevent entries");
assert.notDeepEqual(single.trades,replay(initialRules,"Single",1,.04).trades,"Spread edits affect replay fills");
const c=candles[120];const trueRule={...initialRules[0],feature:"ADX",operator:">",threshold:-1};const falseRule={...trueRule,id:2,threshold:101};
assert.equal(evaluate(c,[trueRule,falseRule]),false);
assert.equal(evaluate(c,[trueRule,{...falseRule,join:"OR"}]),true);
assert.equal(evaluate(c,[trueRule,{...trueRule,id:2,join:"XOR"}]),false);
assert.equal(evaluate(c,[{...trueRule,negate:true}]),false);
assert.throws(()=>createReplay(candles,initialRules,NaN,.01));
const ambiguous=[{...c,close:100,open:100,high:100,low:100,atr:1,adx:100},{...c,close:100,open:100,high:200,low:1,atr:1,adx:100}];
const pad=Array.from({length:40},()=>({...c,adx:0}));const ambiguityReplay=createReplay([...pad,...ambiguous],[trueRule],1,.0);while(ambiguityReplay.step()<100){}assert.ok(ambiguityReplay.result().data>0,"Ambiguous intrabar exits must be DATA, never fake W/L");
console.log("PASS: deterministic fixtures, chronology, causality, completion, counts, R accounting, Single/Independent caps, gates, spreads, AND/OR/XOR/NOT, input validation, OHLC ambiguity.");
