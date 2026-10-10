import type {Family,UniversalConfiguration} from './universal-contract';
import type {StrategyCampaign} from './strategy-campaign';
export type AdminUser={id:string;email:string;displayName:string;createdAt:string;confirmed:boolean;disabled:boolean;accessMode:string;trialUntil:string|null;grantedCount:number};
export type CatalogStrategy={id:string;name:string;family:Family;symbol:string;ready:boolean;importNote:string;enabled:boolean;revision:number;campaign?:StrategyCampaign|null};
export type CatalogPage={items:CatalogStrategy[];total:number;counts:Partial<Record<Family,number>>;hasMore:boolean};
export type SharedStrategy={id:string;name:string;family:Family;symbol:string;sourceHash:string;campaign?:StrategyCampaign|null};
export type SharedLoad={id:string;symbol:string;sourceHash:string;configuration:UniversalConfiguration};
