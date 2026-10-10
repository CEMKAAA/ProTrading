import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {CLOUD_CONTROL,PUBLIC_STUDIO} from '../control-service/api-location.mjs';
import {signed,keyPair,verifySigned} from '../control-service/crypto.mjs';
import {DeviceClient} from '../control-service/device-client.mjs';
import {UNIVERSAL_RUNTIME} from '../lib/universal-contract.ts';

const qa=JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json',import.meta.url),'utf8'));
const root=resolve(import.meta.dirname,'../../reports/cloud_device_20261010');
mkdirSync(root,{recursive:true});
const report={checkedAt:new Date().toISOString(),nativeTradingRequested:false,realTerminalTest:false,results:[]};
let token,installationId;
async function browser(path,body){
 const start=performance.now(),response=await fetch(CLOUD_CONTROL+path,{method:body===undefined?'GET':'POST',redirect:'error',signal:AbortSignal.timeout(45000),
  headers:{Origin:PUBLIC_STUDIO,...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},
  ...(body===undefined?{}:{body:JSON.stringify(body)})});
 const data=response.headers.get('Content-Type')?.includes('application/zip')?Buffer.from(await response.arrayBuffer()):await response.json();
 const row={path,status:response.status,elapsedMs:Math.round(performance.now()-start)};report.results.push(row);console.log(JSON.stringify(row));
 assert.ok(response.ok,path+': '+data.error);return data;
}
try{
 token=(await browser('/v1/auth/login',{email:qa.email,password:qa.password})).accessToken;
 const bytes=await browser('/v1/ea/package',{});let offset=0,setup;
 while(bytes.readUInt32LE(offset)===0x04034b50){
  const size=bytes.readUInt32LE(offset+18),length=bytes.readUInt16LE(offset+26),extra=bytes.readUInt16LE(offset+28);
  const name=bytes.subarray(offset+30,offset+30+length).toString(),at=offset+30+length+extra;
  if(name==='personal-setup.json')setup=JSON.parse(bytes.subarray(at,at+size));offset=at+size;
 }
 assert.ok(verifySigned(setup.envelope,setup.serverPublicKey));
 const keys=keyPair(),body={enrollmentToken:setup.envelope.payload.enrollmentToken,publicKey:keys.publicKey,label:'Isolated device latency QA'};
 const pair=await browser('/v1/ea/enroll',{...body,signature:signed(body,keys.privateKey).signature});installationId=pair.installationId;
 await browser('/v1/pairings/review',{code:pair.code});await browser('/v1/pairings/approve',{code:pair.code,fingerprint:pair.fingerprint});
 await browser('/v1/installations/'+installationId+'/activate',{});
 const client=new DeviceClient({apiUrl:CLOUD_CONTROL,installationId,privateKey:keys.privateKey,pinnedServerPublicKey:setup.serverPublicKey});
 const original=client.request.bind(client);
 client.request=async(path,body,method)=>{
  const start=performance.now();try{const value=await original(path,body,method);
   const row={path,status:200,elapsedMs:Math.round(performance.now()-start)};report.results.push(row);console.log(JSON.stringify(row));return value;
  }catch(error){const row={path,error:error.message,elapsedMs:Math.round(performance.now()-start)};report.results.push(row);console.log(JSON.stringify(row));throw error;}
 };
 const context={symbol:'USDJPYm',brokerServer:'Exness-MT5Trial15',accountLogin:'123'};
 for(let cycle=0;cycle<6;cycle++){
  const identity=client.verified(await client.request('/v1/device/identity',context),'ea_identity');assert.ok(identity.certificate);
  await client.heartbeat();
  await client.request('/v1/device/status',{...context,runtime:UNIVERSAL_RUNTIME,build:'device-latency-qa',openPositions:0,trading:false,configurationHash:'',error:''});
  assert.equal(await client.claim(),null);
  const command=client.verified(await client.request('/v1/device/command',{jobId:null,attemptId:null}),'ea_command');assert.equal(command.liveTradingAllowed,false);
  await new Promise(resolve=>setTimeout(resolve,2000));
 }
 report.status='PASS';
}catch(error){report.status='FAIL';report.error=error.message;process.exitCode=1;}
finally{
 if(installationId)await browser('/v1/installations/'+installationId+'/revoke',{}).catch(error=>{report.cleanupError=error.message;process.exitCode=1;});
 if(token)await browser('/v1/auth/logout',{}).catch(error=>{report.cleanupError=error.message;process.exitCode=1;});
 const device=report.results.filter(r=>r.path.startsWith('/v1/device/'));
 report.deviceCalls=device.length;report.maxDeviceMs=device.length?Math.max(...device.map(r=>r.elapsedMs)):null;
 writeFileSync(resolve(root,'device-latency.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({status:report.status,deviceCalls:report.deviceCalls,maxDeviceMs:report.maxDeviceMs,error:report.error}));
}
