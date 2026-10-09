import { existsSync,writeFileSync,readdirSync,readFileSync } from 'node:fs';
import { resolve, relative } from 'node:path';
const root=resolve(import.meta.dirname,'../out');
for(const path of ['index.html','studio/index.html'])if(!existsSync(resolve(root,path)))throw new Error('STATIC_PAGE_MISSING: '+path);
function check(dir){for(const item of readdirSync(dir,{withFileTypes:true})){
 const path=resolve(dir,item.name);if(item.isDirectory()){if(/\.state|control-service|IndicatorCodeExamples/.test(item.name))throw new Error('PRIVATE_DIRECTORY_IN_EXPORT');check(path);}
 else if(/\.(ex5|mq5|mqh|pem|sqlite|env)$/.test(item.name)||item.name==='personal-setup.json')throw new Error('PRIVATE_ARTIFACT_IN_EXPORT');
 else if(/\.(html|js|json)$/.test(item.name)&&/BEGIN (?:RSA |EC |)PRIVATE KEY|sb_secret_|service_role/.test(readFileSync(path,'utf8')))throw new Error('SECRET_MARKER_IN_EXPORT');
}}
check(root);
const base=process.env.NEXT_PUBLIC_BASE_PATH || '';
for(const page of ['index.html','studio/index.html']){
 const html=readFileSync(resolve(root,page),'utf8');
 if(!html.includes(`href="${base}/favicon.svg"`))throw new Error('FAVICON_BASE_PATH_MISSING');
 if(!html.includes(`href="${base}/studio/"`)&&page==='index.html')throw new Error('STUDIO_BASE_PATH_MISSING');
 for(const tag of html.matchAll(/<(?:script|link|a|img|source)\b[^>]*>/g)){
  if(/rel="(?:preconnect|dns-prefetch)"/.test(tag[0]))continue;
  const match=/(?:src|href)="(\/[^"?#]*)(?:[?#][^"]*)?"/.exec(tag[0]);
  if(!match)continue;
  const path=match[1];
  if(!path.startsWith(base+'/'))throw new Error('UNPREFIXED_EXPORT_ASSET: '+path);
  let local=resolve(root,decodeURIComponent(path.slice(base.length+1)));
  if(path.endsWith('/'))local=resolve(local,'index.html');
  if(relative(root,local).startsWith('..')||!existsSync(local))throw new Error('EXPORT_ASSET_MISSING: '+path);
 }
}
writeFileSync(resolve(root,'.nojekyll'),'');console.log('Static export checked: homepage, Studio, base-path assets and no private EA/server artifacts.');
