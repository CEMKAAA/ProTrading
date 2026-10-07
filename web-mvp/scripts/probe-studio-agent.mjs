import {randomUUID,randomBytes} from 'node:crypto';
import {once} from 'node:events';
import https from 'node:https';
import {Readable} from 'node:stream';
import {createStudioAgent} from '../control-service/studio-agent.mjs';
import {studioAgentEnvironment} from '../control-service/studio-agent-config.mjs';
import {controlHttp} from '../control-service/http.mjs';
import {ControlError} from '../control-service/control-plane.mjs';
import {defaultConfiguration} from '../lib/universal-contract.ts';
import {planAgentActions} from '../lib/studio-agent.ts';
import {strategyPreview} from '../lib/studio-agent-preview.ts';
import {setTimeout as delay} from 'node:timers/promises';

if(process.argv[2]!=='--live')throw new Error('Use --live to send real OpenRouter chat requests. No MT5 or user session is used.');
const nativeTransport=process.argv.includes('--transport=https');
const socketAgent=new https.Agent({keepAlive:false,maxCachedSessions:0,...(process.argv.includes('--tls=1.2')?{maxVersion:'TLSv1.2'}:{})});
// Diagnostic alternative: same TLS verification/endpoint/body; no connection/session reuse.
const httpsFetch=(url,init)=>new Promise((resolve,reject)=>{
 try{
 const req=https.request(url,{method:init.method,headers:init.headers,signal:init.signal,agent:socketAgent},res=>resolve(new Response(Readable.toWeb(res),{status:res.statusCode,headers:res.headers})));
 if(process.argv.includes('--fragment=4096'))req.on('socket',socket=>socket.setMaxSendFragment(4096));
 req.on('error',error=>{console.log(JSON.stringify({transport:'https',errorName:error.name,errorCode:error.code??null}));reject(error);});
 if(process.argv.includes('--paced-body')){
  req.on('socket',socket=>socket.once('secureConnect',()=>void(async()=>{
   const bytes=Buffer.from(init.body);
   for(let offset=0;offset<bytes.length;offset+=4096){
    if(!req.write(bytes.subarray(offset,offset+4096)))await once(req,'drain',{signal:init.signal});
    await delay(1,undefined,{signal:init.signal});
   }
   req.end();
  })().catch(error=>{req.destroy(error);reject(error);}))); 
 }else req.end(init.body);
 }catch(error){console.log(JSON.stringify({transport:'https',errorName:error.name,errorCode:error.code??null}));reject(error);}
});
// This isolated fixture exercises the real HTTP/cookie handler, not Supabase identity verification.
const token=randomBytes(32).toString('base64url'),actor={accountId:randomUUID()};
const check=value=>{if(value!==token)throw new ControlError('UNAUTHORIZED',401);return actor;};
const plane={browser:check,entitlement(){},strategies:()=>[],listJobs:()=>[]};
const auth={mode:'isolated-probe',forBrowser:async value=>check(value),strategies:()=>[]};
const events=[],agent=createStudioAgent({env:studioAgentEnvironment(),...(nativeTransport?{fetcher:httpsFetch}:{}),report:e=>events.push(e)});
const server=controlHttp(plane,{agent,auth});server.listen(0,'127.0.0.1');await once(server,'listening');
const base=`http://127.0.0.1:${server.address().port}`,conversation=[];
const orbCase=process.argv.includes('--case=orb');
const orbMessages=[
 'USDJPY i\u00e7in bu platformda ORB stratejisi olu\u015fturup buradan indirdi\u011fim kendime \u00f6zel EA ile MT5 terminalime ba\u011flayabilirim, do\u011fru mu?',
 'Evet kast\u0131m platformun ki\u015fiselle\u015ftirilmi\u015f ba\u011flant\u0131 EA\u0027s\u0131. USDJPY i\u00e7in ORB ara\u015ft\u0131rma tasla\u011f\u0131 haz\u0131rla, hedef 0.10R olsun. Y\u00fcksek WR ar\u0131yorum ama sonucu backtest belirleyecek. Risk ve stop i\u00e7in aile varsay\u0131lanlar\u0131n\u0131 koru ve bunu belirt. Hen\u00fcz test etme veya kaydetme. Ba\u015flayal\u0131m.',
 'Hen\u00fcz Uygula buttonuna basmad\u0131m. Sadece a\u00e7\u0131kla, ayar de\u011fi\u015ftirme: \u00f6nceki cevab\u0131nda 0.10R ORB aral\u0131\u011f\u0131n\u0131n %10\u0027u demistin. Bu do\u011fru mu? Stop mesafem 30 pip olsa 0.10R hedef ka\u00e7 pip olur?',
];
let turn=0,pendingCalls;
try{
 for(const content of orbCase?orbMessages:['merhaba','Sistemde hesap açtım, kendi stratejimi kurmak cazip gelmişti ama dashboard uçak kokpiti gibi yüzlerce ayrı ayar var. Nereden başlamalıyım?','EURUSDm için Fast EMA + RSI hazır motoruyla bir araştırma taslağı öner. M1, 5W audit, 1R geometri, 10 pip stop, Independent ve toplam MAX OPEN 3 olsun. Mevcut %1 risk ve diğer filtreler değişmesin. Strateji adı EURUSD research example olsun. BUY/SELL mantığını ve ayarları göster; henüz backtest çalıştırma veya kaydetme.']){
  turn++;
  conversation.push({role:'user',content});const started=Date.now();
  const response=await fetch(base+'/v1/assistant/chat',{method:'POST',credentials:'include',headers:{Origin:'http://127.0.0.1:4310',Authorization:'Bearer cookie-session',Cookie:`stratum_session=${token}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(90000),body:JSON.stringify({provider:'openrouter',locale:'tr',cloudConsent:true,requestId:randomUUID(),conversation:conversation.map(m=>({...m,content:m.content.slice(0,2000)})),context:{configuration:defaultConfiguration('entrylab'),symbol:orbCase?null:'EURUSDm',auditWeeks:2,jobId:null,...(pendingCalls?{pendingCalls}:{})}})});
  const answer=await response.json();console.log(JSON.stringify({fixture:'HTTP/cookie chat with real OpenRouter; mock account, not a user-auth test',status:response.status,elapsedMs:Date.now()-started,error:answer.error??null,message:answer.message?.slice(0,1200),proposedCalls:answer.calls?.map(c=>c.name)}));
  if(!response.ok){process.exitCode=1;break;}
  const plan=planAgentActions(defaultConfiguration('entrylab'),2,answer.calls);
  if(orbCase&&turn===2){
   const exact=plan.configuration.family==='orb'&&plan.configuration.runtime.targetR===.1&&!plan.runAudit&&!plan.save&&!plan.reviewTrading;
   console.log(JSON.stringify({orbProposalExact:exact,family:plan.configuration.family,targetR:plan.configuration.runtime.targetR,runAudit:plan.runAudit,save:plan.save,preview:strategyPreview(plan.configuration,plan.auditWeeks,null).rows}));if(!exact)process.exitCode=1;
  }
  if(orbCase&&turn===3&&answer.calls.length){console.log(JSON.stringify({explanationOnly:false}));process.exitCode=1;}
  if(answer.calls.length)pendingCalls=answer.calls;
  if(content.startsWith('EURUSDm')){
   const actual={preset:plan.configuration.runtime.entryPreset,tf:plan.configuration.inputs.InpSignalTimeframe,weeks:plan.auditWeeks,targetR:plan.configuration.runtime.targetR,pips:plan.configuration.inputs.InpPipSlPips,independent:plan.configuration.runtime.independent,maxOpen:plan.configuration.runtime.maxOpen,risk:plan.configuration.inputs.InpRiskPerTradePct,runAudit:plan.runAudit,save:plan.save};
   const expected={preset:4,tf:1,weeks:5,targetR:1,pips:10,independent:true,maxOpen:3,risk:1,runAudit:false,save:false};
   const exact=JSON.stringify(actual)===JSON.stringify(expected);console.log(JSON.stringify({proposalExact:exact,actual,preview:strategyPreview(plan.configuration,plan.auditWeeks,'EURUSDm').rows}));if(!exact)process.exitCode=1;
  }
  conversation.push({role:'assistant',content:answer.message||'Öneriyi inceleyin.'});
 }
 console.log(JSON.stringify({diagnostics:events}));
}finally{socketAgent.destroy();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
