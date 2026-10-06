import { existsSync,readFileSync,writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
const file=new URL('../control-service/.state/real-demo-qa.json',import.meta.url);
const mode=process.argv[2];
const origin='http://127.0.0.1:4310',api='http://127.0.0.1:4321';
let account=existsSync(file)?JSON.parse(readFileSync(file,'utf8')):null;
async function request(path,body,cookie){
 const response=await fetch(api+path,{method:body===undefined?'GET':'POST',headers:{Origin:origin,...(cookie?{Cookie:cookie}:{}),
  ...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(30000)});
 const data=await response.json();return {response,data};
}
if(mode==='register'){
 if(account?.registered)throw new Error('QA registration succeeded already; use login, never reset the demo.');
 const email=process.argv[3];assert.ok(email?.includes('@'));
 if(account)assert.equal(account.email,email);
 else{account={email,password:randomBytes(30).toString('base64url')};writeFileSync(file,JSON.stringify(account),{mode:0o600,flag:'wx'});}
 const {response,data}=await request('/v1/auth/register',{email,password:account.password,displayName:'Cem'});
 console.log(JSON.stringify({operation:'real_signup',status:response.status,confirmationRequired:data.confirmationRequired??false,error:data.error??null}));
 if(response.ok){account.registered=true;writeFileSync(file,JSON.stringify(account),{mode:0o600});}
 if(!response.ok)process.exitCode=1;
}else if(mode==='login'){
 assert.ok(account);const {response,data}=await request('/v1/auth/login',{email:account.email,password:account.password});
 if(!response.ok){console.log(JSON.stringify({operation:'real_login',status:response.status,error:data.error}));process.exitCode=1;}
 else{
  assert.equal(data.accessToken,'cookie-session');account.cookie=response.headers.get('set-cookie').split(';')[0];
  writeFileSync(file,JSON.stringify(account),{mode:0o600});
  const result=await request('/v1/session',undefined,account.cookie);assert.equal(result.response.status,200);
  assert.equal(result.data.accessMode,'demo');assert.equal(result.data.displayName,'Cem');
  console.log(JSON.stringify({operation:'real_login',status:'PASS',accountId:result.data.accountId,accessMode:result.data.accessMode,daysRemaining:result.data.trial.daysRemaining,subscriptionActive:result.data.subscriptionActive}));
 }
}else throw new Error('Use register <email> or login. Passwords and cookies are only in ignored private QA state, never printed.');
