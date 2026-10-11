import assert from 'node:assert/strict';
import {test} from 'node:test';
import {storedSession,storeSession,CLOUD_SESSION} from '../lib/control-endpoint.ts';

const key='stratum.cloud-session.v1';
const storage=()=>{const values=new Map();return {
  getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)
};};
function browser(work){
  const names=['window','localStorage','sessionStorage'];
  const before=names.map(k=>Object.getOwnPropertyDescriptor(globalThis,k));
  globalThis.window={};globalThis.localStorage=storage();globalThis.sessionStorage=storage();
  try{assert.equal(CLOUD_SESSION,true);work();}
  finally{names.forEach((k,n)=>{if(before[n])Object.defineProperty(globalThis,k,before[n]);else delete globalThis[k];});}
}
test('cloud login survives replacing the tab storage and logout removes both copies',()=>browser(()=>{
  storeSession('opaque-bff-handle');globalThis.sessionStorage=storage();
  assert.equal(storedSession(),'opaque-bff-handle');
  storeSession('');assert.equal(storedSession(),'');
  assert.equal(localStorage.getItem(key),null);assert.equal(sessionStorage.getItem(key),null);
}));
test('existing tab-only credentials migrate without extending server expiry',()=>browser(()=>{
  sessionStorage.setItem(key,'old-bff-handle');assert.equal(storedSession(),'old-bff-handle');
  assert.equal(localStorage.getItem(key),'old-bff-handle');
}));
test('the current persistent login takes precedence over a stale tab',()=>browser(()=>{
  localStorage.setItem(key,'new-bff-handle');sessionStorage.setItem(key,'old-bff-handle');
  assert.equal(storedSession(),'new-bff-handle');
}));
test('blocked persistent storage falls back to the current tab',()=>browser(()=>{
  globalThis.localStorage={getItem(){throw Error('blocked');},setItem(){throw Error('blocked');},removeItem(){throw Error('blocked');}};
  storeSession('tab-only');assert.equal(storedSession(),'tab-only');
  storeSession('');assert.equal(storedSession(),'');
}));
test('server rendering never reads browser credentials',()=>{
  assert.equal(typeof window,'undefined');assert.equal(storedSession(),'');assert.doesNotThrow(()=>storeSession(''));
});
