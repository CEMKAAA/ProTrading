import { readFileSync,existsSync,mkdirSync,writeFileSync,renameSync,unlinkSync } from 'node:fs';
import { resolve,dirname,join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes,createHash } from 'node:crypto';
import { keyPair,signed,verifySigned } from './crypto.mjs';
import { runAgent } from './mt5-agent.mjs';

export async function setupConnection(packageRoot=dirname(fileURLToPath(import.meta.url)),{commonFiles=join(process.env.APPDATA??'','MetaQuotes/Terminal/Common/Files')}={}) {
  const [major,minor]=process.versions.node.split('.').map(Number);
  if(major<22||(major===22&&minor<13))throw new Error('NODE_22_13_OR_NEWER_REQUIRED');
  const {envelope,serverPublicKey}=JSON.parse(readFileSync(join(packageRoot,'personal-setup.json'),'utf8'));
  if(!verifySigned(envelope,serverPublicKey))throw new Error('PACKAGE_SIGNATURE_INVALID');
  const p=envelope.payload,url=new URL(p.apiUrl);
  if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['127.0.0.1','localhost'].includes(url.hostname)))throw new Error('HTTPS_REQUIRED');
  if(url.origin!==p.apiUrl)throw new Error('API_ORIGIN_REQUIRED');
  for(const artifact of p.artifacts){
    if(!/^[A-Za-z0-9_./-]+$/.test(artifact.name)||artifact.name.includes('..')||artifact.name.startsWith('/'))throw new Error('PACKAGE_PATH_INVALID');
    if(createHash('sha256').update(readFileSync(join(packageRoot,artifact.name))).digest('hex')!==artifact.sha256)throw new Error('PACKAGE_ARTIFACT_CHANGED');
  }
  const state=join(packageRoot,'.state');mkdirSync(state,{recursive:true});
  const configFile=join(state,'installation.json'),keyFile=join(state,'device-key.json');
  if(!existsSync(configFile)){
    if(p.expiresAt<=Date.now())throw new Error('SETUP_TICKET_EXPIRED_DOWNLOAD_AGAIN');
    const keys=existsSync(keyFile)?JSON.parse(readFileSync(keyFile,'utf8')):keyPair();
    if(!existsSync(keyFile))writeFileSync(keyFile,JSON.stringify(keys),{mode:0o600});
    const body={enrollmentToken:p.enrollmentToken,publicKey:keys.publicKey,label:`MT5 / ${p.subscriberName}`.slice(0,80)};
    const res=await fetch(url.origin+'/v1/ea/enroll',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({...body,signature:signed(body,keys.privateKey).signature}),redirect:'error',signal:AbortSignal.timeout(10000)});
    const pair=await res.json();if(!res.ok)throw new Error(pair.error);
    if(pair.accountId!==p.accountId)throw new Error('PACKAGE_OWNER_MISMATCH');
    const folder=join(commonFiles,'Stratum',pair.installationId);mkdirSync(folder,{recursive:true});
    writeFileSync(join(folder,'local.key'),randomBytes(16).toString('hex'),{mode:0o600});
    const config={apiUrl:url.origin,installationId:pair.installationId,pinnedServerPublicKey:serverPublicKey,folder,
      accountId:p.accountId,pairingCode:pair.code,fingerprint:pair.fingerprint};
    writeFileSync(configFile+'.pending',JSON.stringify(config),{mode:0o600});renameSync(configFile+'.pending',configFile);
    writeFileSync(join(state,'connection.set'),Buffer.concat([Buffer.from([0xff,0xfe]),Buffer.from(`InpInstallationId=${pair.installationId}\r\n`,'utf16le')]),{mode:0o600});
    // The used enrollment secret is no longer needed on disk.
    unlinkSync(join(packageRoot,'personal-setup.json'));writeFileSync(join(state,'owner.json'),JSON.stringify({accountId:p.accountId,subscriberName:p.subscriberName}));
    return {state,config};
  }
  return {state,config:JSON.parse(readFileSync(configFile,'utf8'))};
}
async function main(){
  const root=dirname(fileURLToPath(import.meta.url));
  // After first activation, resume using the local device key, never the ticket.
  let value;
  if(existsSync(join(root,'.state/installation.json'))&&!existsSync(join(root,'personal-setup.json'))){
    value={state:join(root,'.state'),config:JSON.parse(readFileSync(join(root,'.state/installation.json'),'utf8'))};
  }else value=await setupConnection(root);
  console.log(`\nSTRATUM / PERSONAL MT5 CONNECTION\nStudio: http://127.0.0.1:4310/studio\nPairing code: ${value.config.pairingCode}\nFingerprint: ${value.config.fingerprint}\nInpInstallationId: ${value.config.installationId}\nInputs preset: ${join(value.state,'connection.set')}\nApprove in your own Studio account. Keep this window open. Ctrl+C stops the helper, not protective SL/TP.\n`);
  await runAgent(['watch','--state',value.state]);
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
