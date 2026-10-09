import {cpSync,existsSync,mkdirSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,relative} from 'node:path';
import './check-pages-export.mjs';

const web=resolve(import.meta.dirname,'..');
const release=resolve(web,'../reports/web_publish_20261009');
const repository=resolve(release,'CemkaCapital');
const prefix='/CemkaCapital';
if(process.env.NEXT_PUBLIC_BASE_PATH!==prefix)throw new Error('RELEASE_BASE_PATH_MISMATCH');
if(existsSync(repository))throw new Error('RELEASE_DIRECTORY_ALREADY_EXISTS');
mkdirSync(repository,{recursive:true});
cpSync(resolve(web,'out'),repository,{recursive:true});
writeFileSync(resolve(repository,'README.md'),`# Cemka Capital / Stratum\n\nVerified production frontend.\n\n- Website: https://cemkaaa.github.io/CemkaCapital/\n- Studio: https://cemkaaa.github.io/CemkaCapital/studio/\n- Frontend: Next.js static export, including index.html and bundled application JS/CSS.\n- Backend: existing Supabase Auth and stratum-control Edge Function.\n\nThis repository contains only public build artifacts. Proprietary EA sources, private strategies, credentials, signing keys and databases are not included. Backtests run on the authorized user's MT5; GitHub Pages does not execute broker audits. Live trading remains OFF until separately authorized.\n\nSource of truth: the operator's web-mvp workspace, not this generated directory.\n`);
const files=[];
function collect(dir){for(const entry of readdirSync(dir,{withFileTypes:true})){
 const path=resolve(dir,entry.name);if(entry.isDirectory())collect(path);
 else{const bytes=readFileSync(path);files.push({file:relative(repository,path).replaceAll('\\','/'),size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});}
}}
collect(repository);
writeFileSync(resolve(release,'release.json'),JSON.stringify({preparedAt:new Date().toISOString(),repository:'https://github.com/CEMKAAA/CemkaCapital.git',basePath:prefix,site:'https://cemkaaa.github.io/CemkaCapital/',controlApi:'https://uvzhrrqzzdjqtmydpvwo.supabase.co/functions/v1/stratum-control',files},null,2)+'\n');
console.log(`Release prepared: ${files.length} public files, ${files.reduce((sum,f)=>sum+f.size,0)} bytes.\n${repository}`);
