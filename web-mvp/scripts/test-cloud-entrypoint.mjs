import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { Buffer } from 'node:buffer';
import * as crypto from 'node:crypto';

const source=readFileSync(new URL('../supabase/functions/stratum-control/index.mjs',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'');
const origin='https://cemkaaa.github.io',project='https://testproject.supabase.co',api=project+'/functions/v1/stratum-control';
function fixture({corrupt=false,missing=false,region,forwardStatus=200,forwardError=false}={}){
 const serviceKey='test-server-only',key=crypto.createHash('sha256').update('stratum-cloud-config-v1\0'+serviceKey).digest();
 const bytes=Buffer.from('verified private bytes'),sha=crypto.createHash('sha256').update(bytes).digest('hex');
 const config={artifacts:Object.fromEntries(['connection.mjs','UniversalConnectionEA.ex5','MaCrossOrderFlowWorker.ex5'].map(n=>[n,sha]))};
 const iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(Buffer.from(api));
 const encrypted=Buffer.concat([cipher.update(JSON.stringify(config)),cipher.final()]);
 const sealed=Buffer.concat([iv,cipher.getAuthTag(),encrypted]).toString('base64');
 let handler,downloads=0,requests=0;const forwarded=[];
 const database=async strings=>strings.join('').includes('SELECT sealed')?(missing?[]:[{sealed}]):[{count:1}];
 database.begin=work=>work(async()=>[]);
 runInNewContext(source,{
  Buffer,process:{env:{}},...crypto,URL,Request,Response,AbortSignal,
  console:{error(){}},postgres:()=>database,operatorKey:'unused test public key',
  Deno:{env:{get:n=>({SUPABASE_URL:project,SUPABASE_SERVICE_ROLE_KEY:serviceKey,SUPABASE_DB_URL:'test-db',SB_REGION:region})[n]},serve:fn=>handler=fn},
  fetch:async(request,options)=>{
   if(request instanceof Request){forwarded.push({url:request.url,method:request.method,headers:Object.fromEntries(request.headers),body:await request.text(),redirect:options.redirect,hasSignal:!!options.signal});
    if(forwardError)throw new Error('network unavailable');
    return new Response(JSON.stringify({error:'REMOTE_STATUS_PRESERVED'}),{status:forwardStatus,headers:{'Access-Control-Allow-Origin':origin,'X-Proof':'preserved'}});
   }
   downloads++;return new Response(corrupt?'tampered':bytes);
  },
  cloudRequest:async(tx,request,path,c,artifacts)=>{requests++;if(path==='/v1/ea/package')assert.ok(artifacts.binary&&artifacts.worker&&artifacts.helper);return new Response('{}');},
 });
 return {call:(path,method='GET',from=origin)=>handler(new Request(api+path,{method,headers:from?{Origin:from}:{}})),handle:handler,forwarded,downloads:()=>downloads,requests:()=>requests};
}

test('distant regions route unchanged signed requests beside the database without consuming the body twice',async()=>{
 const f=fixture({region:'eu-central-1',forwardStatus:403});
 const body=JSON.stringify({symbol:'USDJPYm'}),r=await f.handle(new Request(api+'/v1/device/identity',{method:'POST',headers:{Origin:origin,Authorization:'Bearer opaque-test','X-Stratum-Proof':'signed-device-proof','Content-Type':'application/json','x-region':'eu-central-1'},body}));
 assert.equal(r.status,403);assert.equal(r.headers.get('X-Proof'),'preserved');assert.equal(r.headers.get('Access-Control-Allow-Origin'),origin);
 assert.deepEqual(f.forwarded,[{url:api+'/v1/device/identity',method:'POST',headers:{authorization:'Bearer opaque-test','content-type':'application/json',origin,'x-region':'ap-southeast-1','x-stratum-proof':'signed-device-proof'},body,redirect:'error',hasSignal:true}]);
 assert.equal(f.downloads(),0);assert.equal(f.requests(),0);
});

test('database-region invocation never forwards again; validation and CORS remain local',async()=>{
 const near=fixture({region:'ap-southeast-1'});assert.equal((await near.call('/v1/session')).status,200);assert.equal(near.forwarded.length,0);
 const far=fixture({region:'eu-central-1'});
 assert.equal((await far.call('/v1/session','OPTIONS')).status,204);
 assert.equal((await far.call('/v1/session','GET','https://evil.example')).status,403);
 assert.equal((await far.call('/v1/session?unsafe=1')).status,400);
 assert.equal(far.forwarded.length,0);
});

test('regional network failure remains an explicit failure and cannot mint authority',async()=>{
 const f=fixture({region:'eu-central-1',forwardError:true}),r=await f.call('/v1/session');
 assert.equal(r.status,500);assert.equal((await r.json()).error,'CLOUD_SERVICE_UNAVAILABLE');assert.equal(f.requests(),0);
});
test('auth and session requests never load private artifacts; package/health verify and reuse them',async()=>{
 const f=fixture();assert.equal((await f.call('/v1/auth/login','POST')).status,200);
 assert.equal((await f.call('/v1/session')).status,200);assert.equal(f.downloads(),0);
 assert.equal((await f.call('/v1/ea/package','POST')).status,200);assert.equal(f.downloads(),3);
 assert.equal((await f.call('/health')).status,200);assert.equal(f.downloads(),3);
});
test('trusted origin has consistent CORS on preflight, health and errors; unknown origin is refused',async()=>{
 const f=fixture();
 for(const [path,method]of [['/v1/auth/login','OPTIONS'],['/health','GET'],['/health?redirect=evil','GET']]){
  const r=await f.call(path,method);assert.equal(r.headers.get('Access-Control-Allow-Origin'),origin);
  assert.equal(r.headers.get('Access-Control-Allow-Credentials'),'true');assert.equal(r.headers.get('Vary'),'Origin');
 }
 const denied=await f.call('/v1/auth/login','OPTIONS','https://evil.example');
 assert.equal(denied.status,403);assert.equal(denied.headers.get('Access-Control-Allow-Origin'),null);
});
test('corrupt or absent configuration cannot silently authorize or supply an EA package',async()=>{
 const f=fixture({corrupt:true});
 assert.equal((await f.call('/v1/session')).status,200);assert.equal(f.downloads(),0);
 const r=await f.call('/v1/ea/package','POST');assert.equal(r.status,503);
 assert.equal((await r.json()).error,'VERIFIED_EA_BUILD_UNAVAILABLE');assert.equal(f.requests(),1);
 assert.equal((await f.call('/v1/ea/package','POST')).status,503);assert.equal(f.requests(),1);
 const missing=fixture({missing:true});assert.equal((await missing.call('/v1/auth/login','POST')).status,503);
 assert.equal(missing.requests(),0);
});
