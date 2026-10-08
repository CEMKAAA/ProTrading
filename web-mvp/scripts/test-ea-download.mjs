import assert from 'node:assert/strict';
import {test} from 'node:test';
import {requestEaPackage,downloadEaBlob} from '../lib/ea-download.ts';

test('package download uses authenticated POST, validates ZIP bytes and never follows redirects',async()=>{
 let request;const bytes=new Uint8Array([0x50,0x4b,3,4,1,2,3]);
 const blob=await requestEaPackage('cookie-session',async(url,options)=>{request={url,options};return new Response(bytes,{headers:{'Content-Type':'application/zip'}});});
 assert.equal(blob.size,7);assert.equal(request.options.method,'POST');assert.equal(request.options.credentials,'include');assert.equal(request.options.redirect,'error');assert.equal(request.options.headers.Authorization,'Bearer cookie-session');assert.equal(request.options.body,'{}');
});
test('failed verification, HTML/error responses and empty or malformed ZIP do not start a download',async()=>{
 await assert.rejects(()=>requestEaPackage('x',async()=>Response.json({error:'VERIFIED_EA_BUILD_UNAVAILABLE'},{status:503})),/VERIFIED_EA_BUILD_UNAVAILABLE/);
 for(const response of [new Response('<html>sign in</html>',{headers:{'Content-Type':'text/html'}}),new Response('not zip',{headers:{'Content-Type':'application/zip'}}),new Response('',{headers:{'Content-Type':'application/zip'}})])await assert.rejects(()=>requestEaPackage('x',async()=>response),/EA_DOWNLOAD_INVALID/);
});
test('download attaches the link before clicking, does not navigate and retains a fallback URL',()=>{
 const prior=globalThis.document,original=URL.createObjectURL,events=[];let attached=false;
 const anchor={remove(){events.push('remove');attached=false;},click(){assert.ok(attached);assert.equal(this.download,'Stratum-user.zip');assert.equal(this.href,'blob:qa');events.push('click');}};
 globalThis.document={createElement:tag=>{assert.equal(tag,'a');return anchor;},body:{appendChild:node=>{assert.equal(node,anchor);attached=true;events.push('append');}}};URL.createObjectURL=()=>{events.push('url');return 'blob:qa';};
 try{assert.equal(downloadEaBlob(new Blob(['zip']),'Stratum-user.zip'),'blob:qa');assert.deepEqual(events,['url','append','click','remove']);assert.equal(attached,false);}
 finally{if(prior===undefined)delete globalThis.document;else globalThis.document=prior;URL.createObjectURL=original;}
});
