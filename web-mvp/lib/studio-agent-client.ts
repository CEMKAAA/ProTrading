type Readiness={credential:string;active:boolean;loading:boolean;available:boolean;configured:boolean;cloud:boolean;consent:boolean;pending:boolean};

export function assistantBlocker(state:Readiness):string|null{
 if(!state.credential||!state.active)return 'AI_ACCESS_REQUIRED';
 if(state.pending)return 'AI_DESK_BUSY';
 if(state.loading)return 'AI_STATUS_LOADING';
 if(!state.available)return 'AI_STATUS_UNAVAILABLE';
 if(!state.configured)return 'AI_NOT_CONFIGURED';
 if(state.cloud&&!state.consent)return 'AI_CLOUD_CONSENT_REQUIRED';
 return null;
}

export function assistantFailure(error:unknown):string{
 if(error instanceof Error){
  if(error.name==='TimeoutError')return 'AI_TIMEOUT';
  if(/^[A-Z][A-Z0-9_]{2,80}$/.test(error.message))return error.message;
 }
 return 'AI_CONTROL_UNREACHABLE';
}

export async function assistantJson<T>(response:Response):Promise<T>{
 let value:unknown;
 try{value=await response.json();}catch{throw new Error('AI_INVALID_RESPONSE');}
 if(!response.ok){
  const code=value&&typeof value==='object'&&'error' in value?value.error:null;
  throw new Error(typeof code==='string'&&/^[A-Z][A-Z0-9_]{2,80}$/.test(code)?code:response.status===401?'UNAUTHORIZED':'AI_CONTROL_UNREACHABLE');
 }
 return value as T;
}
