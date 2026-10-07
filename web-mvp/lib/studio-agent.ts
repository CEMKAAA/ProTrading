import { z } from 'zod';
import { defaultConfiguration, universalConfigurationSchema, builderSchema, eaCatalog, type UniversalConfiguration } from './universal-contract.ts';

export const auditWindow = z.union([z.literal(2),z.literal(5),z.literal(10),z.literal(20),z.literal(52),z.literal(104),z.literal(156),z.literal(208),z.literal(260)]);
const scalar = z.union([z.string().max(200),z.number().finite(),z.boolean()]);
const reason = z.string().trim().min(1).max(600);
export const agentTools = {
  edit_settings: z.object({reason,name:z.string().trim().min(1).max(70).optional(),inputs:z.record(scalar).optional(),runtime:z.record(scalar).optional(),dayHourMasks:z.array(z.number().int().min(0).max(0xffffff)).length(7).optional(),builder:builderSchema.nullable().optional(),auditWeeks:auditWindow.optional()}).strict(),
  select_engine: z.object({reason,family:z.enum(['orb','macross','sol','entrylab'])}).strict(),
  load_strategy: z.object({reason,name:z.string().min(1).max(70)}).strict(),
  save_strategy: z.object({reason}).strict(),
  run_audit: z.object({reason}).strict(),
  show_controls: z.object({reason,group:z.enum(['Entry / Execution','Geometry','Positions','NAS','Order Flow','Regimes','Filters','Risk','Audit','Session / Timezone','Time Matrix','builder','library'])}).strict(),
  review_trading: z.object({reason}).strict(),
};
export type AgentToolName = keyof typeof agentTools;
export type AgentCall = {name:AgentToolName;arguments:Record<string,unknown>};
export const agentCallSchema=z.object({name:z.enum(Object.keys(agentTools) as [AgentToolName,...AgentToolName[]]),arguments:z.record(z.unknown())}).strict();
export const agentRequestSchema=z.object({
  provider:z.enum(['local','openrouter']),locale:z.enum(['en','tr','de']),cloudConsent:z.boolean(),requestId:z.string().uuid(),
  conversation:z.array(z.object({role:z.enum(['user','assistant']),content:z.string().trim().min(1).max(2000)}).strict()).min(1).max(12),
  context:z.object({configuration:universalConfigurationSchema,auditWeeks:auditWindow,jobId:z.string().uuid().nullable(),symbol:z.string().regex(/^[A-Za-z0-9._#-]{1,64}$/).nullable(),pendingCalls:z.array(agentCallSchema).max(8).optional()}).strict(),
}).strict().refine(v=>v.conversation.at(-1)?.role==='user','Last message must be from the user');
export type AgentRequest=z.infer<typeof agentRequestSchema>;
export type AgentAnswer={requestId:string;message:string;calls:AgentCall[];provider:'local'|'openrouter';model:string};
export type AgentPlan={configuration:UniversalConfiguration;auditWeeks:number;calls:AgentCall[];runAudit:boolean;save:boolean;reviewTrading:boolean;show:string|null;changes:{field:string;before:unknown;after:unknown}[]};

// The model proposes data. It never receives an execution callback or account authority.
export function planAgentActions(configuration:UniversalConfiguration,weeks:number,rawCalls:unknown,strategies:UniversalConfiguration[]=[]):AgentPlan {
  const calls=z.array(agentCallSchema).max(8).parse(rawCalls);
  let next=structuredClone(universalConfigurationSchema.parse(configuration)),window=auditWindow.parse(weeks),runAudit=false,save=false,reviewTrading=false,show:string|null=null;
  let replacement=false,edited=false;
  for(const call of calls){
    const args=agentTools[call.name].parse(call.arguments);
    switch(call.name){
      case 'select_engine': {
        if(replacement||edited)throw new Error('ENGINE_REPLACEMENT_MUST_BE_FIRST');
        next=defaultConfiguration((args as z.infer<typeof agentTools.select_engine>).family);replacement=true;break;
      }
      case 'load_strategy': {
        if(replacement||edited)throw new Error('ENGINE_REPLACEMENT_MUST_BE_FIRST');
        const found=strategies.find(s=>s.name===agentTools.load_strategy.parse(call.arguments).name);
        if(!found)throw new Error('STRATEGY_NOT_FOUND');
        next=structuredClone(universalConfigurationSchema.parse(found));replacement=true;break;
      }
      case 'edit_settings': {
        const patch=args as z.infer<typeof agentTools.edit_settings>;
        for(const kind of ['inputs','runtime'] as const)for(const key of Object.keys(patch[kind]??{})){
          if(!eaCatalog[next.family][kind].some(s=>s.key===key))throw new Error('UNKNOWN_CONTROL');
        }
        next=universalConfigurationSchema.parse({...next,...(patch.name===undefined?{}:{name:patch.name}),inputs:{...next.inputs,...patch.inputs},runtime:{...next.runtime,...patch.runtime},...(patch.dayHourMasks===undefined?{}:{dayHourMasks:patch.dayHourMasks}),...(patch.builder===undefined?{}:{builder:patch.builder})});
        if(patch.auditWeeks!==undefined)window=patch.auditWeeks;edited=true;break;
      }
      case 'run_audit':if(runAudit)throw new Error('DUPLICATE_ACTION');runAudit=true;break;
      case 'save_strategy':if(save)throw new Error('DUPLICATE_ACTION');save=true;break;
      case 'review_trading':if(reviewTrading)throw new Error('DUPLICATE_ACTION');reviewTrading=true;break;
      case 'show_controls':show=agentTools.show_controls.parse(call.arguments).group;break;
    }
  }
  const changes:AgentPlan['changes']=[];
  for(const field of ['family','name','inputs','runtime','builder','dayHourMasks'] as const){
    if(field==='inputs'||field==='runtime')for(const key of new Set([...Object.keys(configuration[field]),...Object.keys(next[field])])){
      if(JSON.stringify(configuration[field][key])!==JSON.stringify(next[field][key]))changes.push({field:`${field}.${key}`,before:configuration[field][key],after:next[field][key]});
    }else if(JSON.stringify(configuration[field])!==JSON.stringify(next[field]))changes.push({field,before:configuration[field],after:next[field]});
  }
  if(weeks!==window)changes.push({field:'auditWeeks',before:weeks,after:window});
  return {configuration:next,auditWeeks:window,calls,changes,runAudit,save,show,reviewTrading};
}

const string={type:'string'},why={type:'string',description:'Explain why this serves the user request, in their language.'};
const settingMap={type:'object',additionalProperties:{anyOf:[{type:'number'},{type:'boolean'},{type:'string'}]}};
const rule={type:'object',additionalProperties:false,required:['feature','comparator','threshold','gate','negate','period','rhsFeature','rhsPeriod'],properties:{feature:{type:'integer',minimum:0,maximum:43},comparator:{type:'integer',minimum:0,maximum:7},threshold:{type:'number'},gate:{type:'integer',minimum:0,maximum:2},negate:{type:'boolean'},period:{type:'integer',minimum:1,maximum:5000},rhsFeature:{type:'integer',minimum:-1,maximum:43},rhsPeriod:{type:'integer',minimum:1,maximum:5000}}};
const builder={type:'object',additionalProperties:false,required:['edge','buy','sell','exitBuy','exitSell','exitsEnabled','policy','atrPeriod','slAtr','tpAtr','cooldown','maxBars','maxMinutes'],properties:{edge:{type:'boolean'},buy:{type:'array',minItems:1,maxItems:256,items:rule},sell:{type:'array',minItems:1,maxItems:256,items:rule},exitBuy:{type:'array',maxItems:256,items:rule},exitSell:{type:'array',maxItems:256,items:rule},exitsEnabled:{type:'boolean'},policy:{type:'boolean'},atrPeriod:{type:'integer',minimum:1,maximum:5000},slAtr:{type:'number'},tpAtr:{type:'number'},cooldown:{type:'integer'},maxBars:{type:'integer'},maxMinutes:{type:'integer'}}};
const definitions={
  edit_settings:{description:'Prepare a reviewable proposal NOW when the user requests settings. This does not apply anything and needs no extra chat permission. Compose after select_engine in the same response when changing family. runtime.targetR is reward / initial stop distance, NOT ORB range. All keys and units must come from the catalog. HH:MM waits are integer minutes here. Builder replacement needs complete BUY and SELL lists. Day masks are Sunday-first, bit 0 = 00:00-01:00 broker time.',properties:{reason:why,name:string,inputs:settingMap,runtime:settingMap,builder:{anyOf:[builder,{type:'null'}]},dayHourMasks:{type:'array',minItems:7,maxItems:7,items:{type:'integer',minimum:0,maximum:16777215}},auditWeeks:{type:'integer',enum:[2,5,10,20,52,104,156,208,260]}}},
  select_engine:{description:'Propose replacing the draft with family defaults; saved strategies stay intact. Must be the first call. Include edit_settings in this SAME response for any requested target or other overrides. Warn about replacement; actual application waits for the UI button.',properties:{reason:why,family:{type:'string',enum:['orb','macross','sol','entrylab']}}},
  load_strategy:{description:'Propose loading a saved strategy by its exact name. Must be the first call. Only use names in the supplied private library.',properties:{reason:why,name:string}},
  save_strategy:{description:'Ask the user to confirm saving/updating the final draft to their private library.',properties:{reason:why}},
  run_audit:{description:'Ask to apply and test the final draft on real MT5 history. Only propose if the user explicitly requests a backtest. This does not enable trading.',properties:{reason:why}},
  show_controls:{description:'Navigate to a settings group or the builder/library.',properties:{reason:why,group:{type:'string',enum:['Entry / Execution','Geometry','Positions','NAS','Order Flow','Regimes','Filters','Risk','Audit','Session / Timezone','Time Matrix','builder','library']}}},
  review_trading:{description:'Open the existing live-trading review. Never enables trading or acknowledges risk. User must separately inspect and confirm the real UI.',properties:{reason:why}},
};
export const modelTools=Object.entries(definitions).map(([name,d])=>({type:'function',function:{name,description:d.description,parameters:{type:'object',properties:d.properties,required:['reason',...(name==='select_engine'?['family']:name==='load_strategy'?['name']:name==='show_controls'?['group']:[])],additionalProperties:false}}}));
