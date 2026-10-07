import assert from 'node:assert/strict';
import {test} from 'node:test';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {loadUi} from './ui-ssr-loader.mjs';

// Real React SSR, without a web server, browser, microphone or model connection.
const {LanguageProvider}=loadUi('components/language-provider.tsx');
const {translate}=loadUi('lib/messages.ts');
const Home=loadUi('components/launch-page.tsx').default;
const Agent=loadUi('components/studio-agent.tsx').default;
const {defaultConfiguration}=loadUi('lib/universal-contract.ts');
const render=(component,locale)=>renderToStaticMarkup(React.createElement(LanguageProvider,{locale},component));

for(const locale of ['en','tr','de']){
 test(`homepage and assistant render in ${locale} without browser services`,()=>{
  const html=render(React.createElement(Home),locale);
  assert.ok(html.includes(translate('Build your own.',locale)));
  assert.ok(html.includes(translate('Create trading rules without writing code. Test them on your broker’s history. Send the settings to your own MT5, and decide when trading begins.',locale)));
  assert.ok(html.includes('href="/studio"'));
  for(const id of ['overview','platform','workflow','markets','research','faq'])assert.ok(html.includes(`id="${id}"`));
  const agent=render(React.createElement(Agent,{credential:'',active:false,configuration:defaultConfiguration('entrylab'),auditWeeks:2,symbol:null,jobId:null,summary:null,resultIsCurrent:false,strategies:[],connectionKey:'',pending:false,onMoodChange:()=>{},onConfirm:async()=>{},onRestore:()=>{}}),locale);
  assert.ok(agent.includes(translate('Talk to your guide',locale)));
  assert.ok(agent.includes('data-speaking="false"'));
  assert.ok(!agent.includes('<canvas'),'Server rendering never creates a WebGL context');
 });
}

test('bundled voice/help text is translated without modifying names or numeric identifiers',()=>{
 for(const locale of ['tr','de']){
  for(const label of ['Speak to your guide','Read replies aloud','Send when dictation ends','Check recognized numbers before applying a proposal. By default, dictation fills the message box for review.','Microphone could not start. Try again or use text.'])assert.notEqual(translate(label,locale),label);
  for(const literal of ['FastEmaRsi0.01RIndependent','EURUSDm','InpSLPips','0.00001R'])assert.equal(translate(literal,locale),literal);
 }
});
