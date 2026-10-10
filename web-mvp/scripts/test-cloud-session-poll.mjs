import assert from 'node:assert/strict';
import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {CLOUD_CONTROL,PUBLIC_STUDIO} from '../control-service/api-location.mjs';

const label=process.argv[2]??'after',rounds=Number(process.argv[3]??6);
assert.ok(/^[a-z0-9_-]+$/.test(label)&&Number.isInteger(rounds)&&rounds>0&&rounds<=20);
const qa=JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json',import.meta.url),'utf8'));
const results=[];
async function api(path,token,body){
 const start=performance.now();
 const response=await fetch(CLOUD_CONTROL+path,{method:body===undefined?'GET':'POST',redirect:'error',signal:AbortSignal.timeout(45000),
  headers:{Origin:PUBLIC_STUDIO,...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},
  ...(body===undefined?{}:{body:JSON.stringify(body)})});
 const data=await response.json();
 results.push({path,status:response.status,elapsedMs:Math.round(performance.now()-start),...(data.error?{error:data.error}:{})});
 console.log(JSON.stringify(results.at(-1)));return {response,data};
}
const login=await api('/v1/auth/login',undefined,{email:qa.email,password:qa.password});
assert.equal(login.response.status,200,'QA login failed');const token=login.data.accessToken;
try{
 for(let n=0;n<rounds;n++){
  // Concurrent browser panels, using only the isolated non-trading QA account.
  await Promise.all(['/v1/session','/v1/library/strategies','/v1/jobs'].map(path=>api(path,token)));
  await new Promise(resolve=>setTimeout(resolve,1200));
 }
}finally{
 await api('/v1/auth/logout',token,{});
 const root=resolve(import.meta.dirname,'../../reports/cloud_session_20261010');mkdirSync(root,{recursive:true});
 const reads=results.filter(r=>r.path!=='/v1/auth/login'&&r.path!=='/v1/auth/logout');
 const report={label,rounds,checkedAt:new Date().toISOString(),requests:reads.length,failures:reads.filter(r=>r.status!==200),
  meanMs:Math.round(reads.reduce((n,r)=>n+r.elapsedMs,0)/reads.length),maxMs:Math.max(...reads.map(r=>r.elapsedMs)),results,nativeTradingRequested:false};
 writeFileSync(resolve(root,label+'.json'),JSON.stringify(report,null,2)+'\n');
 if(report.failures.length)process.exitCode=1;
 console.log(JSON.stringify({label,requests:report.requests,failures:report.failures.length,meanMs:report.meanMs,maxMs:report.maxMs}));
}
