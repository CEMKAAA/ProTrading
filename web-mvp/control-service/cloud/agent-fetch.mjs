export async function studioAgentFetch(url,options){return fetch(url,{...options,redirect:'error'});}
