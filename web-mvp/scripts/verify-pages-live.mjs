import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

const report=resolve(import.meta.dirname,'../../reports/web_publish_20261009');
const manifest=JSON.parse(readFileSync(resolve(report,'release.json'),'utf8'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const checks=[];
const stamp=Date.now();
async function request(url,options={}){
 const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000),...options});
 const bytes=Buffer.from(await response.arrayBuffer());
 return {response,bytes};
}
// Four bounded HTTP lanes verify all public assets, not just an HTTP 200 homepage.
const files=manifest.files.filter(f=>f.file!=='.nojekyll');
let next=0;
async function lane(){
 while(next<files.length){
  const file=files[next++],url=manifest.site+file.file+'?release='+stamp;
  const {response,bytes}=await request(url);
  assert.equal(response.status,200,file.file);
  assert.equal(sha(bytes),file.sha256,'LIVE_BUILD_MISMATCH: '+file.file);
  checks.push({file:file.file,status:response.status,sha256:sha(bytes)});
 }
}
await Promise.all(Array.from({length:4},lane));
const old=await request('https://cemkaaa.github.io/studio/?release='+stamp);
assert.equal(old.response.status,200);
assert.equal(sha(old.bytes),sha(readFileSync(new URL('./legacy-studio-redirect.html',import.meta.url))));
const origin=new URL(manifest.site).origin,api=manifest.controlApi;
const health=await request(api+'/health',{headers:{Origin:origin}});
assert.equal(health.response.status,200);
assert.equal(health.response.headers.get('access-control-allow-origin'),origin);
const ready=JSON.parse(health.bytes);
assert.equal(ready.ready,true);assert.equal(ready.authMode,'supabase');
assert.equal(ready.liveTradingDefault,false);
const preflight=await request(api+'/v1/auth/login',{method:'OPTIONS',headers:{Origin:origin,
 'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'content-type,authorization'}});
assert.equal(preflight.response.status,204);
assert.equal(preflight.response.headers.get('access-control-allow-origin'),origin);
const anonymous=await request(api+'/v1/session',{headers:{Origin:origin}});
assert.equal(anonymous.response.status,401,'ANONYMOUS_AUTHORITY_NOT_DENIED');
const alien=await request(api+'/health',{headers:{Origin:'https://evil.example'}});
assert.equal(alien.response.status,403,'FOREIGN_ORIGIN_NOT_DENIED');

const result={verifiedAt:new Date().toISOString(),status:'PASS',site:manifest.site,filesVerified:checks.length,
 legacyStudioRedirect:true,supabase:{health:health.response.status,corsPreflight:preflight.response.status,
 anonymousSession:anonymous.response.status,foreignOrigin:alien.response.status,liveTradingDefault:ready.liveTradingDefault,
 billingConfigured:ready.billingConfigured},browserVisualCheck:'unavailable_no_browser_provider',checks};
writeFileSync(resolve(report,'live-verification.json'),JSON.stringify(result,null,2)+'\n');
const deployment=JSON.parse(readFileSync(resolve(report,'deployment.json'),'utf8'));
writeFileSync(resolve(report,'deployment.json'),JSON.stringify({...deployment,state:'live_verified',verifiedAt:result.verifiedAt},null,2)+'\n');
console.log(JSON.stringify({...result,checks:undefined},null,2));
