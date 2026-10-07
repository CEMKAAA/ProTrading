import ts from 'typescript';
import { readFileSync, writeFileSync } from 'node:fs';
const files=['studio','universal-dashboard','connection-panel','console-window','lever-switch','studio-help','lesson-chart','studio-market-orbit','strategy-demo'];
const keys=new Set();
const decode=s=>s.replace(/&(amp|lt|gt|quot|apos|#39);/g,(_,e)=>({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",'#39':"'"})[e]);
for(const name of files){
 const file=new URL(`../components/${name}.tsx`,import.meta.url),source=readFileSync(file,'utf8');
 if(source.includes('UiText'))continue;
 const ast=ts.createSourceFile(name+'.tsx',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX),edits=[];
 function visit(node){
  if(ts.isJsxText(node)&&node.text.trim()){
   const lines=node.text.split(/\r?\n/),text=decode(lines.map((l,i)=>{let s=l.replace(/\t/g,' ');if(i)s=s.trimStart();if(i<lines.length-1)s=s.trimEnd();return s;}).filter(Boolean).join(' '));
   keys.add(text.trim());edits.push([node.pos,node.end,`<UiText>{${JSON.stringify(text)}}</UiText>`]);return;
  }
  if(ts.isJsxExpression(node)&&node.expression&&(ts.isJsxElement(node.parent)||ts.isJsxFragment(node.parent))){
   const raw=node.expression.getText(ast);
   // Never translate strategy names, user values, credentials, IDs or broker instruments.
   if(!/^(?:String\(.*value.*\)|(?:c|config)\.name|.*\.(?:symbol|email|accountLogin|brokerServer|technical|id)|[nv]|t\.(?:entryPrice|sl|tp|netR).*)$/.test(raw)&&!raw.includes('<')&&!raw.includes('=>')&&!raw.includes('String(topic.currentValue)')){
    edits.push([node.pos,node.end,`<UiText>{${raw}}</UiText>`]);return;
   }
  }
  if(ts.isJsxAttribute(node)&&['placeholder','aria-label','description','title','label'].includes(node.name.getText(ast))&&node.initializer&&ts.isStringLiteral(node.initializer)){
   keys.add(node.initializer.text);edits.push([node.initializer.pos,node.initializer.end,`{t(${JSON.stringify(node.initializer.text)})}`]);
  }
  if(ts.isFunctionDeclaration(node)&&node.name&&/^[A-Z]/.test(node.name.text)&&node.body&&!node.getText(ast).includes('useLanguage('))edits.push([node.body.getStart(ast)+1,node.body.getStart(ast)+1,'\n const {t}=useLanguage();']);
  ts.forEachChild(node,visit);
 }
 visit(ast);
 let result=source;for(const [from,to,text] of edits.sort((a,b)=>b[0]-a[0]))result=result.slice(0,from)+text+result.slice(to);
 result=result.replace(/("use client";|\'use client\';)/,'$1\nimport { UiText'+(source.includes('useLanguage')?'':', useLanguage')+' } from \'./language-provider\';');
 writeFileSync(file,result);
}
writeFileSync(new URL('../docs/ui-language-keys.json',import.meta.url),JSON.stringify([...keys].sort(),null,2));
console.log(`Localized ${files.length} existing component trees explicitly; ${keys.size} static messages extracted.`);
