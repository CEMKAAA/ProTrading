import {z} from 'zod';

export const conversationMessageSchema=z.object({role:z.enum(['user','assistant']),content:z.string().min(1).max(6000).regex(/^[^\x00]*$/)}).strict();
export type ConversationMessage=z.infer<typeof conversationMessageSchema>;
const fields={id:z.string().uuid(),title:z.string().trim().min(1).max(80).regex(/^[^\r\n\x00-\x1f\x7f]+$/),provider:z.enum(['local','openrouter']),locale:z.enum(['en','tr','de'])};
export const saveConversationSchema=z.object({...fields,messages:z.array(conversationMessageSchema).min(1).max(512)}).strict()
 .refine(value=>new TextEncoder().encode(JSON.stringify(value)).byteLength<=1024*1024,'Conversation is too large');
export const conversationSummarySchema=z.object({...fields,messageCount:z.number().int().min(1).max(512),createdAt:z.string().datetime({offset:true}),updatedAt:z.string().datetime({offset:true})}).strict();
export const savedConversationSchema=conversationSummarySchema.extend({messages:z.array(conversationMessageSchema).min(1).max(512)});
export const conversationListRequestSchema=z.object({offset:z.number().int().min(0).max(100000)}).strict();
export const conversationListSchema=z.object({items:z.array(conversationSummarySchema).max(25),hasMore:z.boolean()}).strict();
export type ConversationSummary=z.infer<typeof conversationSummarySchema>;
export type SavedConversation=z.infer<typeof savedConversationSchema>;
export const conversationTitle=(messages:ConversationMessage[])=>messages.find(m=>m.role==='user')?.content.replace(/[\r\n\x00-\x1f\x7f]+/g,' ').trim().slice(0,80)||'Conversation';
