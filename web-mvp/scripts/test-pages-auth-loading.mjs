import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync,existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,sep,extname} from 'node:path';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {CLOUD_CONTROL} from '../control-service/api-location.mjs';

// Real production UI; deliberately delayed/mock responses isolate loading and session races.
const root=resolve(import.meta.dirname,'../out'),report=resolve(import.meta.dirname,'../../reports/auth_session_20261010');
mkdirSync(report,{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.woff2':'font/woff2'};
const server=createServer((request,response)=>{
 const path=decodeURIComponent(new URL(request.url,'http://localhost').pathname).replace(/^\/CemkaCapital(?=\/|$)/,'');
 const file=resolve(root,'.'+path+(path.endsWith('/')?'index.html':''));
 if(!file.startsWith(root+sep)||!existsSync(file)){response.writeHead(404);response.end();return;}
 response.writeHead(200,{'Content-Type':mime[extname(file)]??'application/octet-stream'});response.end(readFileSync(file));
});
server.listen(0,'127.0.0.1');await once(server,'listening');
const site=`http://127.0.0.1:${server.address().port}/CemkaCapital/studio/`,browser=await chromium.launch({headless:true});
const checks=[],errors=[],key='stratum.cloud-session.v1',token='qa-opaque-session-handle';
const gate=()=>{let release;const promise=new Promise(r=>release=r);return {promise,release};};
const session={accountId:'qa-account',displayName:'QA Session',email:'qa@example.test',subscriptionActive:false,entitlementUntil:0,
 accessMode:'inactive',trial:null,installations:[],lease:null,trading:{enabled:false,jobId:null},terminalStatuses:[]};
async function waitFor(check){const end=Date.now()+15000;while(!await check()){if(Date.now()>end)throw new Error('UI_CONDITION_TIMEOUT');await new Promise(r=>setTimeout(r,75));}}
async function context({locale='en',saved='',mobile=false,reduced=false}={}){
 const c=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1440,height:1000},reducedMotion:reduced?'reduce':'no-preference'});
 await c.addInitScript(({locale,saved,key})=>{localStorage.setItem('stratum.language',locale);if(saved&&!sessionStorage.getItem(key))sessionStorage.setItem(key,saved);},{locale,saved,key});
 const page=await c.newPage();page.on('pageerror',e=>errors.push(e.message));return {c,page};
}
async function mock(page,handler){
 await page.route(CLOUD_CONTROL+'/**',async route=>{
  const path=new URL(route.request().url()).pathname.split('/stratum-control')[1];
  const special=await handler(path,route);if(special)return;
  const data=path==='/v1/session'?session:path==='/v1/strategies'?{strategies:[]}:path==='/v1/jobs'?{jobs:[]}:path.includes('/admin/')?{isAdmin:false}:{items:[]};
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
}
try{
 const {c,page}=await context({locale:'tr'}),login=gate(),workspace=gate();let authCalls=0,probes=0,offline=false,revoked=false;
 await mock(page,async(path,route)=>{
  if(path==='/v1/auth/session'){probes++;await route.fulfill({status:401,json:{error:'UNAUTHORIZED'}});return true;}
  if(path==='/v1/auth/login'){authCalls++;await login.promise;await route.fulfill({status:200,json:{accessToken:token}});return true;}
  if(path==='/v1/session'){
   await workspace.promise;
   await route.fulfill({status:revoked?401:offline?503:200,json:revoked?{error:'SESSION_REVOKED'}:offline?{error:'CLOUD_SERVICE_UNAVAILABLE'}:session});return true;
  }
 });
 await page.goto(site);const form=page.locator('form.uc-login');await form.waitFor({state:'visible'});
 await form.locator('input[type=email]').fill('qa@example.test');await form.locator('input[type=password]').fill('a-long-private-password');
 await form.locator('button[type=submit]').click();
 assert.equal(await form.getAttribute('aria-busy'),'true');assert.equal(await form.locator('button[type=submit]').isDisabled(),true);
 assert.equal(await form.locator('button.text-btn').isDisabled(),true);assert.equal(await form.locator('input[type=email]').isDisabled(),true);
 assert.ok((await form.innerText()).includes('Giriş yapılıyor...'));
 assert.equal(await form.locator('.uc-auth-spinner').evaluate(el=>getComputedStyle(el).animationName),'uc-auth-spin');
 await form.evaluate(el=>{for(let n=0;n<4;n++)el.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));});
 assert.equal(authCalls,1);await page.locator('#studio-account').screenshot({path:resolve(report,'login-pending-tr.png')});
 login.release();await page.locator('.uc-auth-progress').waitFor({state:'visible'});
 assert.ok((await page.locator('.uc-auth-progress').innerText()).includes('Çalışma alanınız açılıyor...'));
 assert.equal(await form.count(),0);assert.equal(await page.evaluate(k=>sessionStorage.getItem(k),key),token);
 await page.locator('#studio-account').screenshot({path:resolve(report,'workspace-pending-tr.png')});
 workspace.release();await page.locator('.uc-status-grid').waitFor({state:'visible'});assert.equal(probes,0);
 checks.push('TR login spinner; inputs/mode locked; repeated submissions fenced; verified workspace loading');
 await page.reload();await page.locator('.uc-status-grid').waitFor({state:'visible'});assert.equal(authCalls,1);assert.equal(probes,0);
 checks.push('reload restores the saved handle without an anonymous auth probe or another login');
 const reopened=await c.newPage();let reopenedLogin=0;
 await mock(reopened,async(path,route)=>{
  if(path==='/v1/auth/login'||path==='/v1/auth/session'){reopenedLogin++;await route.fulfill({status:401,json:{error:'UNAUTHORIZED'}});return true;}
 });
 await reopened.goto(site);await reopened.locator('.uc-status-grid').waitFor({state:'visible'});
 assert.equal(reopenedLogin,0);assert.equal(await reopened.evaluate(k=>localStorage.getItem(k),key),token);
 await reopened.close();checks.push('new tab restores persisted login without tab storage, a probe or another login');
 offline=true;await waitFor(async()=>!!(await page.locator('.uc-error').count()));
 assert.equal(await form.count(),0);assert.equal(await page.evaluate(k=>sessionStorage.getItem(k),key),token);
 offline=false;await waitFor(async()=>!(await page.locator('.uc-error').count()));assert.equal(authCalls,1);
 checks.push('temporary 503 preserves session and recovers through automatic polling');
 revoked=true;await form.waitFor({state:'visible',timeout:15000});assert.equal(await page.evaluate(k=>sessionStorage.getItem(k),key),null);
 checks.push('actual revocation still clears the credential and requires login');await c.close();

 const signupContext=await context({locale:'de',mobile:true,reduced:true}),signupPage=signupContext.page,registration=gate(),failedLogin=gate();let registrations=0;
 await mock(signupPage,async(path,route)=>{
  if(path==='/v1/auth/register'){registrations++;await registration.promise;await route.fulfill({status:201,json:{confirmationRequired:true,message:'Confirm your email, then sign in.'}});return true;}
  if(path==='/v1/auth/login'){await failedLogin.promise;await route.fulfill({status:401,json:{error:'INVALID_CREDENTIALS'}});return true;}
 });
 await signupPage.goto(site);const signupForm=signupPage.locator('form.uc-login');await signupForm.waitFor({state:'visible'});
 await signupForm.locator('button.text-btn').click();await signupForm.locator('[autocomplete=name]').fill('QA Subscriber');
 await signupForm.locator('input[type=email]').fill('qa@example.test');await signupForm.locator('input[type=password]').fill('a-long-private-password');
 await signupForm.locator('button[type=submit]').click();assert.ok((await signupForm.innerText()).includes('Ihr Konto wird erstellt...'));
 assert.equal(await signupForm.locator('.uc-auth-spinner').evaluate(el=>getComputedStyle(el).animationName),'none');
 await signupPage.locator('#studio-account').screenshot({path:resolve(report,'signup-pending-de-mobile.png')});
 registration.release();await waitFor(async()=>!(await signupForm.locator('button[type=submit]').isDisabled()));
 assert.equal(registrations,1);assert.equal(await signupPage.locator('.uc-status-grid').count(),0);
 assert.ok((await signupPage.locator('#studio-account').innerText()).includes('Confirm your email, then sign in.')||
  (await signupPage.locator('#studio-account').innerText()).includes('Bestätig'));
 checks.push('DE signup loading and confirmation without fake login; mobile layout; reduced motion');
 await signupForm.locator('input[type=password]').fill('a-long-private-password');await signupForm.locator('button[type=submit]').click();
 failedLogin.release();await signupPage.locator('#studio-account .uc-error').waitFor({state:'visible'});
 assert.equal(await signupForm.locator('button[type=submit]').isDisabled(),false);assert.equal(await signupForm.locator('.uc-auth-spinner').count(),0);
 assert.equal(await signupPage.locator('.uc-status-grid').count(),0);
 checks.push('failed login stops loading, enables retry, and displays the error beside the form');await signupContext.c.close();

 const retryContext=await context({saved:token}),retryPage=retryContext.page;let available=false;
 await mock(retryPage,async(path,route)=>{
  if(path==='/v1/session'&&!available){await route.fulfill({status:503,json:{error:'CLOUD_SERVICE_UNAVAILABLE'}});return true;}
 });
 await retryPage.goto(site);await waitFor(async()=> (await retryPage.locator('.uc-auth-progress').innerText()).includes('Your session is saved'));
 assert.equal(await retryPage.locator('form.uc-login').count(),0);available=true;
 await retryPage.locator('.uc-auth-progress button').click();await retryPage.locator('.uc-status-grid').waitFor({state:'visible'});
 assert.equal(await retryPage.evaluate(k=>sessionStorage.getItem(k),key),token);
 checks.push('EN restoration failure offers retry, keeps handle, and opens workspace only after verification');await retryContext.c.close();
 assert.deepEqual(errors,[]);console.log(JSON.stringify({status:'PASS',checks,pageErrors:errors,mocked:true,nativeTradingRequested:false},null,2));
 writeFileSync(resolve(report,'browser-loading.json'),JSON.stringify({status:'PASS',checks,pageErrors:errors,mocked:true,nativeTradingRequested:false},null,2)+'\n');
}finally{await browser.close();await new Promise(r=>server.close(r));}
