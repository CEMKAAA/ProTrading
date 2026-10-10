import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { Buffer } from 'node:buffer';
import * as crypto from 'node:crypto';
import {signed,keyPair} from '../control-service/crypto.mjs';

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

function releaseFixture({conflict=false}={}){
 const keys=keyPair(),serviceKey='release-test',encryption=crypto.createHash('sha256').update('stratum-cloud-config-v1\0'+serviceKey).digest();
 const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
 const priorBytes=Buffer.from('old artifact'),names=['connection.mjs','UniversalConnectionEA.ex5','MaCrossOrderFlowWorker.ex5'];
 const original={artifacts:Object.fromEntries(names.map(name=>[name,digest(priorBytes)])),encryptionKey:'retain-me',signingKey:keys,eaSigningKey:{privateKey:'retain-native-key'}};
 const seal=c=>{const iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',encryption,iv);cipher.setAAD(Buffer.from(api));const data=Buffer.concat([cipher.update(JSON.stringify(c)),cipher.final()]);return Buffer.concat([iv,cipher.getAuthTag(),data]).toString('base64');};
 const open=s=>{const b=Buffer.from(s,'base64'),cipher=crypto.createDecipheriv('aes-256-gcm',encryption,b.subarray(0,12));cipher.setAAD(Buffer.from(api));cipher.setAuthTag(b.subarray(12,28));return JSON.parse(Buffer.concat([cipher.update(b.subarray(28)),cipher.final()]));};
 let sealed=seal(original),handler;
 const files=new Map(names.map(name=>[name,priorBytes]));
 const database=async(strings,...values)=>{const sql=strings.join('');if(sql.includes('SELECT sealed'))return [{sealed}];
  if(sql.includes('UPDATE stratum_runtime.deployment_configuration')){if(conflict||values[1]!==sealed)return [];sealed=values[0];return [{id:1}];}return [{count:1}];};
 database.begin=work=>work(async()=>[]);
 runInNewContext(source,{Buffer,process:{env:{}},...crypto,URL,Request,Response,AbortSignal,console:{error(){}},postgres:()=>database,operatorKey:keys.publicKey,
  Deno:{env:{get:n=>({SUPABASE_URL:project,SUPABASE_SERVICE_ROLE_KEY:serviceKey,SUPABASE_DB_URL:'test'})[n]},serve:fn=>handler=fn},cloudRequest:async()=>new Response('{}'),
  fetch:async(url,options={})=>{const path=String(url).split('stratum-private-builds/')[1];
   if(options.method==='DELETE'){for(const name of JSON.parse(options.body).prefixes)files.delete(name);return new Response('{}');}
   if(options.method==='POST'){files.set(path,Buffer.from(options.body));return new Response('{}');}
   return files.has(path)?new Response(files.get(path)):new Response('{}',{status:404});},
 });
 const send=(kind,bytes,sha256=digest(bytes),signatureKey=keys.privateKey)=>{
  const payload={apiUrl:api,issuedAt:Date.now(),expiresAt:Date.now()+60000,kind,name:names[1],sha256,index:0,count:1,chunkHash:digest(bytes)};
  return handler(new Request(api+'/operator/artifact/'+names[1],{method:'POST',headers:{'X-Stratum-Proof':Buffer.from(JSON.stringify(signed(payload,signatureKey))).toString('base64url')},body:bytes}));
 };
 return {original,config:()=>open(sealed),files,digest,send,health:()=>handler(new Request(api+'/health'))};
}

test('owner-signed replacement publishes immutable bytes and preserves all license/encryption keys',async()=>{
 const f=releaseFixture(),bytes=Buffer.from('new verified artifact'),sha=f.digest(bytes);
 assert.equal((await f.send('artifact_chunk',bytes)).status,200);
 assert.equal((await f.send('artifact_complete',Buffer.alloc(0),sha)).status,200);
 const c=f.config();assert.equal(c.encryptionKey,f.original.encryptionKey);assert.deepEqual(c.signingKey,f.original.signingKey);assert.deepEqual(c.eaSigningKey,f.original.eaSigningKey);
 assert.equal(c.artifacts['UniversalConnectionEA.ex5'],sha);assert.equal(c.artifactPaths['UniversalConnectionEA.ex5'],'UniversalConnectionEA.ex5.'+sha);
 assert.equal(f.files.get('UniversalConnectionEA.ex5').toString(),'old artifact');assert.equal(f.files.get(c.artifactPaths['UniversalConnectionEA.ex5']).toString(),bytes.toString());
 assert.equal((await f.health()).status,200);
});

test('forged owner signatures and mismatched assembled hashes cannot change the pinned release',async()=>{
 const f=releaseFixture(),bytes=Buffer.from('replacement');
 assert.equal((await f.send('artifact',bytes,f.digest(bytes),keyPair().privateKey)).status,503);
 assert.deepEqual(f.config(),f.original);
 assert.equal((await f.send('artifact',bytes,'a'.repeat(64))).status,503);assert.deepEqual(f.config(),f.original);
});

test('concurrent release conflict leaves old configuration and downloads intact',async()=>{
 const f=releaseFixture({conflict:true}),bytes=Buffer.from('new candidate');
 assert.equal((await f.send('artifact',bytes)).status,503);assert.deepEqual(f.config(),f.original);
 assert.equal((await f.health()).status,200);assert.equal(f.files.get('UniversalConnectionEA.ex5').toString(),'old artifact');
});
