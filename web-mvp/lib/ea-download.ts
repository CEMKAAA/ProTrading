import {CONTROL_API} from './control-endpoint.ts';

export async function requestEaPackage(credential:string,fetcher:typeof fetch=fetch){
 const response=await fetcher(CONTROL_API+'/v1/ea/package',{method:'POST',headers:{Authorization:`Bearer ${credential}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(60000),cache:'no-store',redirect:'error',credentials:'include'});
 if(!response.ok){
  let data:unknown;try{data=await response.json();}catch{throw new Error('EA_DOWNLOAD_FAILED');}
  const code=data&&typeof data==='object'&&'error' in data?data.error:null;
  throw new Error(typeof code==='string'&&/^[A-Z][A-Z0-9_]{2,80}$/.test(code)?code:'EA_DOWNLOAD_FAILED');
 }
 if(response.headers.get('content-type')?.split(';')[0]!=='application/zip')throw new Error('EA_DOWNLOAD_INVALID');
 const blob=await response.blob();if(blob.size<4)throw new Error('EA_DOWNLOAD_INVALID');
 const signature=new Uint8Array(await blob.slice(0,4).arrayBuffer());
 if(signature[0]!==0x50||signature[1]!==0x4b||signature[2]!==3||signature[3]!==4)throw new Error('EA_DOWNLOAD_INVALID');
 return blob;
}

export function downloadEaBlob(blob:Blob,filename:string){
 const url=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=url;a.download=filename;a.hidden=true;document.body.appendChild(a);
 try{a.click();}finally{a.remove();}
 // Retain a visible, real user-click fallback until replaced or the component unmounts.
 return url;
}
