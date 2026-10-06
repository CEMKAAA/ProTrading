import assert from 'node:assert/strict';
import { test } from 'node:test';
import { once } from 'node:events';
import { mkdtempSync,writeFileSync,readFileSync,existsSync,rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { ControlPlane } from '../control-service/control-plane.mjs';
import { keyPair,signed,verifySigned,makeProof,id } from '../control-service/crypto.mjs';
import { verifyEaCommand } from '../control-service/ea-authority.mjs';
import { personalPackage,zipFiles } from '../control-service/delivery.mjs';
import { setupConnection } from '../control-service/personal-setup.mjs';
import { controlHttp } from '../control-service/http.mjs';
const DAY=86400000;
const reject=(fn,code)=>assert.throws(fn,e=>e.code===code);
const register=p=>p.register({email:'demo@example.com',password:'a-long-private-password',displayName:'Cem Quant'});
function request(ticket,keys=keyPair()) {
 const payload={enrollmentToken:ticket.enrollmentToken,publicKey:keys.publicKey,label:'Personal MT5'};
 return {...payload,signature:signed(payload,keys.privateKey).signature};
}
export function unzipStored(buffer) {
 const files=new Map();let offset=0;
 while(buffer.readUInt32LE(offset)===0x04034b50){
  assert.equal(buffer.readUInt16LE(offset+8),0);
  const size=buffer.readUInt32LE(offset+18),len=buffer.readUInt16LE(offset+26),extra=buffer.readUInt16LE(offset+28);
  const name=buffer.subarray(offset+30,offset+30+len).toString();const at=offset+30+len+extra;
  files.set(name,buffer.subarray(at,at+size));offset=at+size;
 }
 assert.equal(buffer.readUInt32LE(offset),0x02014b50);return files;
}
test('demo is exactly 30 days; restart, login and redownload never renew it',()=>{
 const dir=mkdtempSync(join(tmpdir(),'stratum-trial-')),database=join(dir,'control.sqlite');let at=Date.UTC(2026,9,6);
 let p=new ControlPlane({database,now:()=>at});let a=register(p),s=p.sessionInfo(a.accessToken);const expiry=at+30*DAY;
 assert.equal(s.trial.expiresAt,expiry);p.issueEnrollment(a.accessToken);p.close();
 at+=10*DAY;p=new ControlPlane({database,now:()=>at});a=p.login({email:'DEMO@example.com',password:'a-long-private-password'});
 assert.equal(p.sessionInfo(a.accessToken).trial.daysRemaining,20);p.issueEnrollment(a.accessToken);
 assert.equal(p.sessionInfo(a.accessToken).trial.expiresAt,expiry);
 reject(()=>register(p),'EMAIL_UNAVAILABLE');at=expiry;
 a=p.login({email:'demo@example.com',password:'a-long-private-password'});s=p.sessionInfo(a.accessToken);
 assert.equal(s.accessMode,'inactive');assert.equal(s.trial.daysRemaining,0);assert.equal(s.subscriptionActive,false);
 reject(()=>p.issueEnrollment(a.accessToken),'ENTITLEMENT_EXPIRED');p.close();rmSync(dir,{recursive:true,force:true});
});
test('paid entitlement does not erase or reset the demo; expiry and disable fail closed',()=>{
 let at=Date.now();const p=new ControlPlane({now:()=>at}),a=register(p),account=p.browser(a.accessToken).accountId;
 p.provisionAccount(account,at+60*DAY);assert.equal(p.sessionInfo(a.accessToken).accessMode,'paid');
 p.provisionAccount(account,0);assert.equal(p.sessionInfo(a.accessToken).accessMode,'demo');
 p.run('UPDATE accounts SET disabled=1 WHERE id=?',account);reject(()=>p.browser(a.accessToken),'UNAUTHORIZED');reject(()=>p.entitlement(account),'ENTITLEMENT_EXPIRED');p.close();
});
test('personal ticket is one-use, expiring and cannot be approved by another account',()=>{
 let at=Date.now();const p=new ControlPlane({now:()=>at}),a=register(p),t=p.issueEnrollment(a.accessToken),r=request(t);
 const pair=p.enrollInstallation(r);assert.equal(pair.accountId,t.accountId);reject(()=>p.enrollInstallation(r),'ENROLLMENT_EXPIRED_OR_USED');
 const b=p.register({email:'other@example.com',password:'another-private-password'});
 reject(()=>p.reviewPairing(b.accessToken,pair.code),'PAIRING_OWNER_MISMATCH');
 reject(()=>p.approvePairing(b.accessToken,pair.code,pair.fingerprint),'PAIRING_OWNER_MISMATCH');
 p.reviewPairing(a.accessToken,pair.code);p.approvePairing(a.accessToken,pair.code,pair.fingerprint);
 const next=p.issueEnrollment(a.accessToken);at+=30*60000;
 reject(()=>p.enrollInstallation(request(next)),'ENROLLMENT_EXPIRED_OR_USED');p.close();
});
test('forged device proof, unsigned registration extras and logout cannot mint trial/installation authority',()=>{
 const p=new ControlPlane(),a=register(p),t=p.issueEnrollment(a.accessToken),r=request(t);
 reject(()=>p.enrollInstallation({...r,label:'tampered'}),'INVALID_SIGNATURE');
 reject(()=>p.register({email:'bad@example.com',password:'a-long-private-password',entitlementUntil:Date.now()+365*DAY}),'INVALID_REQUEST');
 p.logout(a.accessToken);reject(()=>p.enrollInstallation(r),'ENROLLMENT_EXPIRED_OR_USED');reject(()=>p.issueEnrollment(a.accessToken),'UNAUTHORIZED');p.close();
});
test('only newest unused download ticket enrolls; existing approved keys stay approved',()=>{
 const p=new ControlPlane(),a=register(p),first=p.issueEnrollment(a.accessToken),next=p.issueEnrollment(a.accessToken);
 reject(()=>p.enrollInstallation(request(first)),'ENROLLMENT_EXPIRED_OR_USED');const pair=p.enrollInstallation(request(next));
 p.approvePairing(a.accessToken,pair.code,pair.fingerprint);p.issueEnrollment(a.accessToken);
 assert.equal(p.get('SELECT state FROM installations WHERE id=?',pair.installationId).state,'approved');p.close();
});
test('demo identity carries signed mode/expiry; expiry blocks native commands and heartbeat',()=>{
 let at=Date.now();const p=new ControlPlane({now:()=>at}),a=register(p),keys=keyPair(),pair=p.enrollInstallation(request(p.issueEnrollment(a.accessToken),keys));
 p.approvePairing(a.accessToken,pair.code,pair.fingerprint);p.activate(a.accessToken,pair.installationId);
 const body={symbol:'JP225m',brokerServer:'Exness-MT5Trial15',accountLogin:'123'};
 const install=()=>p.authenticateDevice(makeProof(pair.installationId,'POST','/v1/device/identity',body,keys.privateKey,at,id()),'POST','/v1/device/identity',body);
 let cert=p.eaIdentity(install(),body).payload.certificate;assert.ok(verifyEaCommand(cert,p.eaSigningKey.publicKey));
 assert.ok(cert.includes('accessMode=demo'));assert.ok(cert.includes(`trialUntil=${Math.floor((at+30*DAY)/1000)}`));
 at+=30*DAY;cert=p.eaIdentity(install(),body).payload.certificate;
 assert.ok(cert.includes('accessMode=inactive'));assert.ok(cert.includes('subscriptionActive=false'));
 reject(()=>p.heartbeat(install()),'ENTITLEMENT_EXPIRED');reject(()=>p.eaCommand(install(),{jobId:null,attemptId:null}),'ENTITLEMENT_EXPIRED');p.close();
});
test('ZIP is signed and personal; no credentials, compiler, terminal or EA source escapes',async()=>{
 const p=new ControlPlane(),a=register(p),bundle=await personalPackage(p,a.accessToken,'http://127.0.0.1:4321',()=>({binary:Buffer.from('EA'),worker:Buffer.from('OF')}),async()=>Buffer.from('HELPER'));
 const files=unzipStored(bundle.bytes),setup=JSON.parse(files.get('personal-setup.json'));
 assert.ok(verifySigned(setup.envelope,p.signingKey.publicKey));assert.equal(setup.envelope.payload.accountId,p.browser(a.accessToken).accountId);
 assert.equal(setup.envelope.payload.accessMode,'demo');assert.ok(files.has('start_connection.bat'));
 for(const name of files.keys())assert.ok(!/\.mq[5h]$|terminal64|metaeditor|private-key/i.test(name));
 assert.ok(!bundle.bytes.includes(a.accessToken));assert.ok(!bundle.bytes.includes('BEGIN PRIVATE KEY'));
 assert.throws(()=>zipFiles([['../escape','x']]));p.close();
});
test('HTTP signup/login/session work; package is private, unknown fields and invalid origins rejected',async()=>{
 const p=new ControlPlane(),server=controlHttp(p);server.listen(0,'127.0.0.1');await once(server,'listening');const base=`http://127.0.0.1:${server.address().port}`;
 const post=(path,body,token='',origin='http://127.0.0.1:4310')=>fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json',Origin:origin,Authorization:'Bearer '+token},body:JSON.stringify(body)});
 try{
  const response=await post('/v1/auth/register',{email:'http@example.com',password:'a-long-private-password'});assert.equal(response.status,201);const a=await response.json();
  const session=await (await fetch(base+'/v1/session',{headers:{Authorization:'Bearer '+a.accessToken}})).json();assert.equal(session.accessMode,'demo');
  assert.equal((await post('/v1/ea/package',{})).status,401);assert.equal((await post('/v1/ea/package',{accountId:'someone'},a.accessToken)).status,400);
  assert.equal((await post('/v1/ea/package',{},a.accessToken,'https://evil.example')).status,403);
  assert.equal((await post('/v1/auth/login',{email:'http@example.com',password:'wrong'})).status,401);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));p.close();}
});
test('downloaded setup generates local device keys and owner-bound MT5 preset end-to-end',async()=>{
 const p=new ControlPlane(),a=register(p),server=controlHttp(p);server.listen(0,'127.0.0.1');await once(server,'listening');
 const dir=mkdtempSync(join(tmpdir(),'stratum-setup-')),common=join(dir,'common'),api=`http://127.0.0.1:${server.address().port}`;
 try{
  const b=await personalPackage(p,a.accessToken,api,()=>({binary:Buffer.from('EA'),worker:Buffer.from('OF')}),async()=>Buffer.from('HELPER'));
  const files=unzipStored(b.bytes);for(const [name,data] of files){const {mkdirSync}=await import('node:fs');const {dirname}=await import('node:path');mkdirSync(dirname(join(dir,name)),{recursive:true});writeFileSync(join(dir,name),data);}
  const result=await setupConnection(dir,{commonFiles:common});assert.ok(existsSync(join(result.state,'device-key.json')));assert.ok(!existsSync(join(dir,'personal-setup.json')));
  assert.equal(result.config.accountId,p.browser(a.accessToken).accountId);assert.ok(readFileSync(join(result.state,'connection.set')).includes(Buffer.from(result.config.installationId,'utf16le')));
  p.approvePairing(a.accessToken,result.config.pairingCode,result.config.fingerprint);assert.equal(p.get('SELECT state FROM installations WHERE id=?',result.config.installationId).state,'approved');
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));p.close();rmSync(dir,{recursive:true,force:true});}
});
