import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { constants, createHash, privateEncrypt, sign } from "node:crypto";
import { eaKeyPair, eaModulus } from "../control-service/ea-authority.mjs";

const key=JSON.parse(readFileSync(new URL('../control-service/.state/ea-signing-key.json',import.meta.url),'utf8'));
const body='command=audit\nname=Proof / Turkish Unicode: \u00e7\u015f\u0131\nissued=1\nexpires=16';
const sig=sign('sha256',Buffer.from(body),{key:key.privateKey,padding:constants.RSA_PKCS1_PADDING}).toString('hex');
const cases=[['valid',body,sig,true],['tampered',body+'x',sig,false],['wrong-key',body,sign('sha256',Buffer.from(body),eaKeyPair().privateKey).toString('hex'),false],
  ['zero',body,'0'.repeat(512),false],['equal-modulus',body,eaModulus(key.publicKey),false],['short',body,sig.slice(2),false],['bad-hex',body,'z'+sig.slice(1),false]];
const raw=Buffer.concat([Buffer.from('0001','hex'),Buffer.alloc(202,255),Buffer.from('003031300d060960864801650304020105000420','hex'),createHash('sha256').update(body).digest()]);
for(const index of [0,1,2,203,204,205,222,223,255]){
  const bad=Buffer.from(raw);bad[index]^=1;
  cases.push(['padding-'+index,body,privateEncrypt({key:key.privateKey,padding:constants.RSA_NO_PADDING},bad).toString('hex'),false]);
}
const quote=s=>'"'+s.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('\n','\\n')+'"';
let code='#property strict\n#include "../../IndicatorCodeExamples/universal/UniversalAuthority.mqh"\n#include "../../IndicatorCodeExamples/universal/UniversalAuthorityKey.mqh"\nvoid OnStart(){int passed=0,failed=0;ulong started=GetTickCount64();\n';
for(const [name,text,signature,expected] of cases)code+=`if(UcRsaVerify(${quote(text)},${quote(signature)},UC_AUTHORITY_MODULUS)==${expected})passed++;else{failed++;Print("FAIL ${name}");}\n`;
code+='string b="command=audit\\nissued=1000\\nexpires=1015\\ninstallationId=device\\naccountLogin=123\\nsymbol=JP225m\\nbrokerServer=Exness\\nsequence=2\\naccountId=11111111-1111-1111-1111-111111111111\\ngeneration=22222222-2222-2222-2222-222222222222";\n';
const scopes=[['device','123','JP225m','Exness',1001,1,true],['other','123','JP225m','Exness',1001,1,false],['device','456','JP225m','Exness',1001,1,false],['device','123','XAUUSDm','Exness',1001,1,false],['device','123','JP225m','Other',1001,1,false],['device','123','JP225m','Exness',1015,1,false],['device','123','JP225m','Exness',994,1,false],['device','123','JP225m','Exness',1001,2,false]];
for(const [d,l,s,b,n,f,ok] of scopes)code+=`if(UcAuthorityScope(b,${quote(d)},${quote(l)},${quote(s)},${quote(b)},${n},${f})==${ok})passed++;else failed++;\n`;
const identity='command=identity\nissued=1000\nexpires=1015\ninstallationId=device\naccountLogin=123\nsymbol=JP225m\nbrokerServer=Exness\nsequence=2\naccountId=11111111-1111-1111-1111-111111111111\nsubscriberName=Cem Quant\nsubscriptionActive=true\nsubscriptionUntil=2000\ncontrollerActive=false';
code+=`string identity=${quote(identity)};\n`;
for(const [d,l,s,b,n,f,ok] of scopes)code+=`if(UcIdentityScope(identity,${quote(d)},${quote(l)},${quote(s)},${quote(b)},${n},${f})==${ok})passed++;else failed++;\n`;
code+='if(!UcAuthorityScope(identity,"device","123","JP225m","Exness",1001,1))passed++;else failed++;\n';
code+='if(!UcIdentityScope(b,"device","123","JP225m","Exness",1001,1))passed++;else failed++;\n';
code+='int f=FileOpen("Stratum/security-probe.json",FILE_WRITE|FILE_TXT|FILE_COMMON);FileWriteString(f,"{\\"passed\\":"+(string)passed+",\\"failed\\":"+(string)failed+",\\"elapsedMs\\":"+(string)(GetTickCount64()-started)+"}");FileClose(f);Print("UC PROOF passed=",passed," failed=",failed);}\n';
const folder=new URL('../../tests/mql5/',import.meta.url);mkdirSync(folder,{recursive:true});
writeFileSync(new URL('UniversalAuthorityProbe.mq5',folder),code,'utf8');
console.log('Generated native authority probe:',cases.length+scopes.length*2+2,'cases; no private material embedded.');
