import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

const root=import.meta.dirname,manifest=JSON.parse(readFileSync(resolve(root,'publication.json'),'utf8'));
const base='https://cemkaaa.github.io/CemkaCapital/';
const result={commit:manifest.commit,site:manifest.site,checkedAt:new Date().toISOString(),files:[],failures:[]};
for(const file of manifest.files){
 try{
  const url=new URL(file.file,base);url.searchParams.set('verify',manifest.commit);
  const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000)});
  const bytes=Buffer.from(await response.arrayBuffer());
  const sha256=createHash('sha256').update(bytes).digest('hex');
  const check={file:file.file,status:response.status,matches:response.ok&&sha256===file.sha256};
  result.files.push(check);if(!check.matches)result.failures.push(check);
  console.log(`${result.files.length}/${manifest.files.length} ${check.matches?'PASS':'FAIL'} ${file.file}`);
 }catch(error){const check={file:file.file,error:error.message};result.files.push(check);result.failures.push(check);console.log('FAIL '+file.file+': '+error.message);}
}
writeFileSync(resolve(root,'live-deployment-check.json'),JSON.stringify(result,null,2)+'\n');
if(result.failures.length)process.exitCode=1;
else{
 manifest.state='pages_built_and_live_hash_verified';manifest.liveVerifiedAt=result.checkedAt;
 writeFileSync(resolve(root,'publication.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log(`Verified ${result.files.length} public files at commit ${result.commit}`);
}
