import { Buffer } from 'node:buffer';
import process from 'node:process';
import { createHash,createCipheriv,createDecipheriv,randomBytes,verify,createPublicKey } from 'node:crypto';
import postgres from 'npm:postgres@3.4.8';
import { cloudRequest } from './control-bundle.mjs';
import operatorKey from './operator-public-key.mjs';

globalThis.Buffer=Buffer;
const url=Deno.env.get('SUPABASE_URL'),serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const apiUrl=url+'/functions/v1/stratum-control',studio='https://cemkaaa.github.io';
// Keep the account-locked SQL transaction beside this project's Singapore database.
const databaseRegion='ap-southeast-1';
const database=postgres(Deno.env.get('SUPABASE_DB_URL'),{prepare:false,max:2,idle_timeout:20,connect_timeout:10,
 types:{safeInteger:{to:20,from:[20],serialize:String,parse:value=>{const n=Number(value);if(!Number.isSafeInteger(n))throw new Error('DATABASE_INTEGER_UNSAFE');return n;}}}});
const encryption=createHash('sha256').update('stratum-cloud-config-v1\0'+serviceKey).digest();
let cached;
const digest=v=>createHash('sha256').update(v).digest('hex');
const canonical=v=>v===null||typeof v!=='object'?JSON.stringify(v):Array.isArray(v)?'['+v.map(canonical).join(',')+']':'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';
function encrypt(value){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',encryption,iv);cipher.setAAD(Buffer.from(apiUrl));
 const bytes=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);return Buffer.concat([iv,cipher.getAuthTag(),bytes]).toString('base64');}
function decrypt(value){const b=Buffer.from(value,'base64'),cipher=createDecipheriv('aes-256-gcm',encryption,b.subarray(0,12));cipher.setAAD(Buffer.from(apiUrl));cipher.setAuthTag(b.subarray(12,28));
 return JSON.parse(Buffer.concat([cipher.update(b.subarray(28)),cipher.final()]).toString());}
const response=(status,error,origin)=>new Response(JSON.stringify(error),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store',...(origin===studio?{'Access-Control-Allow-Origin':studio,'Access-Control-Allow-Credentials':'true','Vary':'Origin'}:{})}});
function operatorProof(payload,signature){
 if(payload.apiUrl!==apiUrl||payload.expiresAt<=Date.now()||payload.expiresAt>Date.now()+300000||payload.issuedAt>Date.now()+30000
   ||!verify(null,Buffer.from(canonical(payload)),operatorKey,Buffer.from(signature??'','base64url')))throw new Error('OPERATOR_PROOF_INVALID');
}
async function storage(path,options={}){const r=await fetch(url+'/storage/v1/'+path,{...options,headers:{Authorization:'Bearer '+serviceKey,apikey:serviceKey,...options.headers},redirect:'error',signal:AbortSignal.timeout(20000)});
 if(!r.ok)throw new Error('PRIVATE_ARTIFACT_STORAGE_UNAVAILABLE');return r;}
async function configuration(requireArtifacts=false){
 if(!cached||cached.until<=Date.now()){
 const rows=await database`SELECT sealed FROM stratum_runtime.deployment_configuration WHERE id=1`;
 if(!rows.length)throw new Error('CLOUD_SETUP_REQUIRED');
 cached={config:decrypt(rows[0].sealed),artifacts:null,until:Date.now()+60000};
 }
 const state=cached;
 // Authentication must not download megabytes of unrelated private EA binaries.
 if(requireArtifacts&&!state.artifacts){
 const artifacts={};
 for(const [name,expected]of Object.entries(state.config.artifacts)){
  const artifactPath=state.config.artifactPaths?.[name]??name;
  if(artifactPath!==name&&artifactPath!==name+'.'+expected)throw new Error('VERIFIED_EA_BUILD_UNAVAILABLE');
  const bytes=Buffer.from(await (await storage('object/authenticated/stratum-private-builds/'+artifactPath)).arrayBuffer());
  if(digest(bytes)!==expected)throw new Error('VERIFIED_EA_BUILD_UNAVAILABLE');
  artifacts[name==='connection.mjs'?'helper':name==='UniversalConnectionEA.ex5'?'binary':'worker']=bytes;
 }
 state.artifacts=artifacts;
 }
 return state;
}

async function installArtifact(config,sealed,name,bytes,sha256){
 const artifactPath=name+'.'+sha256;
 // Publish immutable bytes first, then swap only the pinned artifact metadata.
 // Existing enrollment, device and encryption keys remain unchanged.
 await storage('object/stratum-private-builds/'+artifactPath,{method:'POST',headers:{'Content-Type':'application/octet-stream','x-upsert':'true'},body:bytes});
 const next={...config,artifacts:{...config.artifacts,[name]:sha256},artifactPaths:{...config.artifactPaths,[name]:artifactPath}};
 const updated=await database`UPDATE stratum_runtime.deployment_configuration SET sealed=${encrypt(next)} WHERE id=1 AND sealed=${sealed} RETURNING id`;
 if(updated.length!==1)throw new Error('ARTIFACT_SCOPE_INVALID');
 cached=null;
}

Deno.serve(async request=>{
 const uri=new URL(request.url),origin=request.headers.get('origin'),prefix='/stratum-control';
 // The hosted gateway strips /functions/v1 before calling the function.
 const base=uri.pathname.startsWith('/functions/v1'+prefix)?'/functions/v1'+prefix:prefix;
 if(!uri.pathname.startsWith(base+'/')||uri.search||uri.hash||uri.pathname.includes('%'))return response(400,{error:'INVALID_PATH'},origin);
 const path=uri.pathname.slice(base.length);
 if(origin&&origin!==studio)return response(403,{error:'ORIGIN_DENIED'},origin);
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:{'Access-Control-Allow-Origin':studio,'Access-Control-Allow-Credentials':'true','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Access-Control-Allow-Headers':'Content-Type, Authorization, X-Stratum-Proof','Access-Control-Max-Age':'600','Vary':'Origin'}});
 const ip=request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()??'unknown';
 try{
  if(Deno.env.get('SB_REGION')&&Deno.env.get('SB_REGION')!==databaseRegion){
   const forwarded=new Request(apiUrl+path,request);forwarded.headers.set('x-region',databaseRegion);
   return await fetch(forwarded,{redirect:'error',signal:AbortSignal.timeout(30000)});
  }
  // Rate limits are persisted, not per-isolate maps; no credentials are retained in the key.
  const sensitive=/\/auth\/|\/pairings|\/ea\//.test(path),limit=sensitive?12:600,at=Date.now();
  const key=digest(ip+'|'+(sensitive?'identity':'all'));
  const rate=await database`INSERT INTO stratum_runtime.rate_limits VALUES(${key},${at+60000},1)
   ON CONFLICT(key) DO UPDATE SET count=CASE WHEN rate_limits.until_at<${at} THEN 1 ELSE rate_limits.count+1 END,
   until_at=CASE WHEN rate_limits.until_at<${at} THEN ${at+60000} ELSE rate_limits.until_at END RETURNING count`;
  if(rate[0].count>limit)return response(429,{error:'RATE_LIMITED'},origin);
  if(path==='/operator/bootstrap'&&request.method==='POST'){
   if(Number(request.headers.get('content-length')??0)>65536)return response(413,{error:'BODY_TOO_LARGE'},origin);
   const {payload,signature}=await request.json();operatorProof(payload,signature);
   const c=payload.configuration;
   if(c.studioUrl!==studio||c.apiUrl!==apiUrl||c.supabaseUrl!==url||c.signingKey.publicKey!==operatorKey
    ||createPublicKey(c.signingKey.privateKey).export({type:'spki',format:'pem'})!==operatorKey
    ||Buffer.from(c.encryptionKey,'base64').length!==32||!c.publishableKey.startsWith('sb_publishable_'))throw new Error('BOOTSTRAP_CONFIG_INVALID');
   const names=Object.keys(c.artifacts).sort();
   if(names.join('|')!==['MaCrossOrderFlowWorker.ex5','UniversalConnectionEA.ex5','connection.mjs'].join('|')||Object.values(c.artifacts).some(x=>!/^[a-f0-9]{64}$/.test(x)))throw new Error('BOOTSTRAP_CONFIG_INVALID');
   await database`INSERT INTO stratum_runtime.deployment_configuration VALUES(1,${encrypt(c)})`;
   const bucket=await fetch(url+'/storage/v1/bucket',{method:'POST',headers:{Authorization:'Bearer '+serviceKey,apikey:serviceKey,'Content-Type':'application/json'},body:JSON.stringify({id:'stratum-private-builds',name:'stratum-private-builds',public:false}),redirect:'error'});
   if(!bucket.ok&&bucket.status!==409)throw new Error('PRIVATE_ARTIFACT_STORAGE_UNAVAILABLE');
   return response(201,{configured:true,artifactsRequired:true},origin);
  }
  if(path.startsWith('/operator/artifact/')&&request.method==='POST'){
   const name=path.slice('/operator/artifact/'.length),proof=JSON.parse(Buffer.from(request.headers.get('x-stratum-proof')??'','base64url').toString());
   operatorProof(proof.payload,proof.signature);
   if(!['artifact','artifact_chunk','artifact_complete'].includes(proof.payload.kind)||proof.payload.name!==name)throw new Error('OPERATOR_PROOF_INVALID');
   const row=await database`SELECT sealed FROM stratum_runtime.deployment_configuration WHERE id=1`,c=decrypt(row[0].sealed);
   const sha256=proof.payload.sha256,stage=name+'.'+sha256;
   if(!c.artifacts[name]||!/^[a-f0-9]{64}$/.test(sha256))throw new Error('ARTIFACT_SCOPE_INVALID');
   if(proof.payload.kind==='artifact_chunk'){
    const {index,count,chunkHash}=proof.payload;
    if(!Number.isInteger(index)||!Number.isInteger(count)||index<0||index>=count||count>256)throw new Error('ARTIFACT_SCOPE_INVALID');
    const chunk=Buffer.from(await request.arrayBuffer());
    if(chunk.length>65536||digest(chunk)!==chunkHash)throw new Error('ARTIFACT_HASH_INVALID');
    await storage('object/stratum-private-builds/'+stage+'.part-'+index,{method:'POST',headers:{'Content-Type':'application/octet-stream','x-upsert':'true'},body:chunk});
    return response(200,{uploaded:true,index},origin);
   }
   if(proof.payload.kind==='artifact_complete'){
    const {count}=proof.payload;
    if(!Number.isInteger(count)||count<1||count>256)throw new Error('ARTIFACT_SCOPE_INVALID');
    const chunks=[];
    for(let i=0;i<count;i+=8)chunks.push(...await Promise.all(Array.from({length:Math.min(8,count-i)},async(_,j)=>Buffer.from(await(await storage('object/authenticated/stratum-private-builds/'+stage+'.part-'+(i+j))).arrayBuffer()))));
    const bytes=Buffer.concat(chunks);
    if(bytes.length>10*1024*1024||digest(bytes)!==sha256)throw new Error('ARTIFACT_HASH_INVALID');
    await installArtifact(c,row[0].sealed,name,bytes,sha256);
    await storage('object/stratum-private-builds',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:Array.from({length:count},(_,i)=>stage+'.part-'+i)})});
    return response(200,{uploaded:true,name,sha256},origin);
   }
   const bytes=Buffer.from(await request.arrayBuffer());
   if(bytes.length>10*1024*1024||digest(bytes)!==sha256)throw new Error('ARTIFACT_HASH_INVALID');
   await installArtifact(c,row[0].sealed,name,bytes,sha256);
   return response(200,{uploaded:true,name,sha256},origin);
  }
  const state=await configuration(['/health','/v1/ea/package','/v1/ea/download'].includes(path));
  if(path==='/health')return response(200,{service:'stratum-control',authMode:'supabase',protocolVersion:2,ready:true,liveTradingDefault:false,billingConfigured:false},origin);
  for(const k of ['STRATUM_AI_OPENROUTER_KEY','STRATUM_AI_OPENROUTER_MODEL'])if(Deno.env.get(k))process.env[k]=Deno.env.get(k);
  return await database.begin(async tx=>{
   await tx`SET LOCAL search_path TO stratum_runtime`;
   await tx`SET LOCAL statement_timeout TO '12s'`;
   await tx`SET LOCAL lock_timeout TO '10s'`;
   return cloudRequest(tx,request,path,state.config,state.artifacts,ip);
  });
 }catch(error){
  console.error('stratum-request-failed',JSON.stringify({path,code:/^[A-Z0-9_]{1,64}$/.test(error.code??'')?error.code:'INTERNAL_ERROR'}));
  const allowed=['CLOUD_SETUP_REQUIRED','PRIVATE_ARTIFACT_STORAGE_UNAVAILABLE','VERIFIED_EA_BUILD_UNAVAILABLE','OPERATOR_PROOF_INVALID','BOOTSTRAP_CONFIG_INVALID','ARTIFACT_SCOPE_INVALID','ARTIFACT_HASH_INVALID'];
  return response(allowed.includes(error.message)?503:500,{error:allowed.includes(error.message)?error.message:'CLOUD_SERVICE_UNAVAILABLE'},origin);
 }
});
