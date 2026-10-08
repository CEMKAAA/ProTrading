import { Buffer } from 'node:buffer';

export function createServer(handler) {
  return {
    address:()=>({port:443}),
    async fetch(request, path, remoteAddress) {
      const headers=Object.fromEntries(request.headers), responseHeaders=new Headers();
      const chunks=request.body?request.body:null;
      const req={headers,url:path,method:request.method,socket:{remoteAddress},
        async *[Symbol.asyncIterator](){if(chunks)for await(const chunk of chunks)yield Buffer.from(chunk);}};
      let status=200,value=null;
      const res={writableEnded:false,
        setHeader:(key,value)=>responseHeaders.set(key,value),
        writeHead:(code,extra={})=>{status=code;for(const [key,value]of Object.entries(extra))responseHeaders.set(key,value);},
        end:body=>{value=body??null;res.writableEnded=true;}};
      await handler(req,res);
      if(!res.writableEnded)throw new Error('HTTP_RESPONSE_NOT_ENDED');
      return new Response(value,{status,headers:responseHeaders});
    }
  };
}
