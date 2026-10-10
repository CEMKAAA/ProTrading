import assert from 'node:assert/strict';
import {test} from 'node:test';
import {rankCampaignStrategies,cycleCampaignSort} from '../lib/strategy-campaign.ts';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {loadUi} from './ui-ssr-loader.mjs';

const metrics=(wins,losses)=>({total:wins+losses,wins,losses,open:0,flat:0,winRate:wins/(wins+losses)*100,netR:wins-losses,minCumR:-losses});
const item=(id,wins,losses)=>({id,name:id,campaign:{windows:[{weeks:2,available:true,metrics:metrics(wins,losses)},{weeks:260,available:true,metrics:metrics(losses,wins)}]}});
const sorts=[{key:'winRate',direction:'desc'},{key:'total',direction:'desc'}];
const ids=items=>items.map(i=>i.id);
test('equal 99% WR prefers 10,000 trades over 100 trades; priorities are lexicographic',()=>{
 const rows=[item('small',99,1),item('large',9900,100),item('low-wr',50000,50000)];
 assert.deepEqual(ids(rankCampaignStrategies(rows,2,sorts)),['large','small','low-wr']);
 assert.deepEqual(ids(rankCampaignStrategies(rows,2,[...sorts].reverse())),['low-wr','large','small']);
 assert.deepEqual(ids(rows),['small','large','low-wr']);
});
test('selected window controls ranking, not the largest available window',()=>{
 const rows=[item('first',9,1),item('second',2,8)];
 assert.deepEqual(ids(rankCampaignStrategies(rows,2,sorts)),['first','second']);
 assert.deepEqual(ids(rankCampaignStrategies(rows,260,sorts)),['second','first']);
});
test('each metric reverses and missing windows / null WR remain last in both directions',()=>{
 const rows=[item('high',9,1),item('low',2,8),{id:'missing',name:'missing',campaign:{windows:[]}}];
 for(const direction of ['asc','desc']){
  const ranked=rankCampaignStrategies(rows,2,[{key:'winRate',direction}]);
  assert.equal(ranked[2].id,'missing');assert.equal(ranked[0].id,direction==='asc'?'low':'high');
 }
 for(const key of ['total','wins','losses','netR','minCumR'])assert.equal(rankCampaignStrategies(rows,2,[{key,direction:'asc'}]).at(-1).id,'missing');
 const openOnly=item('open-only',1,1);openOnly.campaign.windows[0].metrics.winRate=null;
 assert.equal(rankCampaignStrategies([...rows,openOnly],2,sorts).at(-2).id,'open-only');
});
test('toggle cycles descending, ascending, off without disturbing other priority slots',()=>{
 const start=[{key:'wins',direction:'desc'}];
 const descending=cycleCampaignSort(start,'total');assert.deepEqual(descending,[...start,{key:'total',direction:'desc'}]);
 const ascending=cycleCampaignSort(descending,'total');assert.deepEqual(ascending,[...start,{key:'total',direction:'asc'}]);
 assert.deepEqual(cycleCampaignSort(ascending,'total'),start);
});
const {LanguageProvider}=loadUi('components/language-provider.tsx'),Library=loadUi('components/shared-strategy-library.tsx').default;
const {translate}=loadUi('lib/messages.ts');
for(const locale of ['en','tr','de'])test(`ranking controls are accessible and translated in ${locale}`,()=>{
 const html=renderToStaticMarkup(React.createElement(LanguageProvider,{locale},React.createElement(Library,{credential:'',onLoad:()=>{}})));
 for(const text of ['Sort this audit window','Clear sorting','Highest first','Trade count','Win rate'])assert.ok(html.includes(translate(text,locale)));
 assert.equal((html.match(/campaign-sort-priority/g)??[]).length,2);
 assert.ok(html.includes('aria-pressed="true"'));
});
