import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const stateFile=new URL('../control-service/.state/real-demo-qa.json',import.meta.url);
if(process.argv[2]!=='--live')throw new Error('Use --live for the running authenticated download.');
const account=JSON.parse(readFileSync(stateFile,'utf8')),api='http://127.0.0.1:4321';
const call=async(path,body)=>fetch(api+path,{method:body===undefined?'GET':'POST',headers:{Origin:'http://127.0.0.1:4310',...(account.cookie?{Cookie:account.cookie}:{}),...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(60000),redirect:'error'});
let session=await call('/v1/auth/session');
if(session.status===401){
 const login=await call('/v1/auth/login',{email:account.email,password:account.password});assert.equal(login.status,200);
 account.cookie=login.headers.get('set-cookie').split(';')[0];writeFileSync(stateFile,JSON.stringify(account),{mode:0o600});session=await call('/v1/auth/session');
}
assert.equal(session.status,200);
const response=await call('/v1/ea/package',{});
if(!response.ok){const data=await response.json();console.log(JSON.stringify({result:'FAIL',status:response.status,error:data.error}));process.exitCode=1;}
else{
 const bytes=Buffer.from(await response.arrayBuffer()),files=new Map();let offset=0;
 while(bytes.readUInt32LE(offset)===0x04034b50){
  const size=bytes.readUInt32LE(offset+18),length=bytes.readUInt16LE(offset+26),extra=bytes.readUInt16LE(offset+28),at=offset+30+length+extra;
  files.set(bytes.subarray(offset+30,offset+30+length).toString(),bytes.subarray(at,at+size));offset=at+size;
 }
 assert.equal(bytes.readUInt32LE(offset),0x02014b50);
 assert.equal(response.headers.get('content-type'),'application/zip');assert.ok(response.headers.get('content-disposition').startsWith('attachment;'));
 const ea=files.get('MQL5/Experts/StratumUniversal/UniversalConnectionEA.ex5');assert.ok(ea?.length>1000000);
 const hash=b=>createHash('sha256').update(b).digest('hex');assert.equal(hash(ea),hash(readFileSync(new URL('../../IndicatorCodeExamples/universal/UniversalConnectionEA.ex5',import.meta.url))));
 assert.ok(files.has('connection.mjs'));assert.ok(files.has('personal-setup.json'));assert.ok(files.has('start_connection.bat'));
 console.log(JSON.stringify({result:'PASS',status:response.status,zipBytes:bytes.length,ex5Bytes:ea.length,files:[...files.keys()]}));
}
