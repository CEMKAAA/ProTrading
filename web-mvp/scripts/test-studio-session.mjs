import assert from 'node:assert/strict';
import {test} from 'node:test';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {restoreStudioSession} from '../lib/studio-session.ts';
import {loadUi} from './ui-ssr-loader.mjs';

const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};};
function fixture(cloud,saved=''){
 let revision=0,credential=saved,probes=0;
 const response=deferred(),json=deferred();
 const accept=value=>{revision++;credential=value;};
 const start=()=>{const owner=revision;return restoreStudioSession({cloud,saved,
  probe:()=>{probes++;return response.promise;},isCurrent:()=>owner===revision,accept});};
 return {start,response,json,accept,credential:()=>credential,probes:()=>probes};
}
test('anonymous cloud startup never sends the 401 probe that could erase a new login',async()=>{
 const f=fixture(true),restore=f.start();f.accept('new-login');await restore;
 assert.equal(f.probes(),0);assert.equal(f.credential(),'new-login');
});
test('saved cloud handles are restored for dashboard validation without another auth request',async()=>{
 const f=fixture(true,'opaque-handle');await f.start();assert.equal(f.probes(),0);assert.equal(f.credential(),'opaque-handle');
});
test('late cookie 401 does not erase a successful login',async()=>{
 const f=fixture(false),restore=f.start();f.accept('new-login');f.response.resolve(new Response(null,{status:401}));
 await restore;assert.equal(f.credential(),'new-login');
});
test('late cookie success cannot undo a later login or sign-out, including during JSON parsing',async()=>{
 for(const newer of ['new-login','']){
  const f=fixture(false,'old-handle'),restore=f.start();
  f.response.resolve({ok:true,status:200,json:()=>f.json.promise});await Promise.resolve();
  f.accept(newer);f.json.resolve({accessToken:'cookie-session'});await restore;
  assert.equal(f.credential(),newer);
 }
});
test('unmounted cookie probes cannot write credentials',async()=>{
 let accepted=false;await restoreStudioSession({cloud:false,saved:'',probe:async()=>new Response(null,{status:401}),
  isCurrent:()=>false,accept:()=>{accepted=true;}});assert.equal(accepted,false);
});
test('current local cookie probe succeeds; transient failure does not clear credentials',async()=>{
 const f=fixture(false),restore=f.start();f.response.resolve(Response.json({accessToken:'cookie-session'}));await restore;
 assert.equal(f.credential(),'cookie-session');
 const g=fixture(false,'still-valid'),retry=g.start();g.response.resolve(new Response(null,{status:503}));await retry;
 assert.equal(g.credential(),'still-valid');
});
test('loading and retry views are localized and accessible without suggesting a confirmed login',()=>{
 const {default:Progress}=loadUi('components/auth-progress.tsx'),{LanguageProvider}=loadUi('components/language-provider.tsx');
 const {translate}=loadUi('lib/messages.ts');
 for(const locale of ['en','tr','de']){
  for(const restoring of [true,false]){
   const html=renderToStaticMarkup(React.createElement(LanguageProvider,{locale},React.createElement(Progress,{restoring,retrying:false,onRetry:()=>{}})));
   assert.ok(html.includes('role="status"'));assert.ok(html.includes('aria-busy="true"'));assert.ok(html.includes('uc-auth-spinner'));
   assert.ok(html.includes(translate(restoring?'Restoring your session...':'Opening your workspace...',locale)));
  }
  const retry=renderToStaticMarkup(React.createElement(LanguageProvider,{locale},React.createElement(Progress,{restoring:false,retrying:true,onRetry:()=>{}})));
  assert.ok(retry.includes(translate('Your session is saved',locale)));assert.ok(retry.includes(translate('Retry now',locale)));
  assert.ok(!retry.includes('uc-auth-spinner'));
 }
});
