import { Agent,request } from 'node:https';
import { isIP } from 'node:net';

// Optional operator-only route override for networks with a broken IPv4 route.
// URL, Host, SNI and TLS certificate validation still use the Supabase hostname.
export function supabaseTransport({url,ipv6Address}) {
  if(!ipv6Address)return fetch;
  if(isIP(ipv6Address)!==6)throw new Error('SUPABASE_IPV6_ADDRESS_INVALID');
  const origin=new URL(url),agent=new Agent({keepAlive:true,lookup:(hostname,options,callback)=>{
    if(hostname!==origin.hostname)return callback(new Error('AUTH_HOST_MISMATCH'));
    if(options.all)callback(null,[{address:ipv6Address,family:6}]);else callback(null,ipv6Address,6);
  }});
  const send=(target,options={})=>new Promise((resolve,reject)=>{
    const dest=new URL(target);
    if(dest.origin!==origin.origin)return reject(new Error('AUTH_HOST_MISMATCH'));
    const req=request(dest,{agent,method:options.method??'GET',headers:options.headers,signal:options.signal,
      servername:origin.hostname,rejectUnauthorized:true},res=>{
      const chunks=[];let size=0;
      res.on('data',chunk=>{size+=chunk.length;if(size>8*1024*1024)res.destroy(new Error('AUTH_RESPONSE_TOO_LARGE'));else chunks.push(chunk);});
      res.on('error',reject);
      res.on('end',()=>{
        const headers=new Headers();for(const [key,value] of Object.entries(res.headers))if(value!==undefined)
          headers.set(key,Array.isArray(value)?value.join(','):value);
        const status=res.statusCode??502;
        if(status>=300&&status<400)return reject(new Error('AUTH_REDIRECT_DENIED'));
        resolve(new Response(status===204?null:Buffer.concat(chunks),{status,headers}));
      });
    });
    req.on('error',reject);if(options.body!==undefined)req.write(options.body);req.end();
  });
  send.close=()=>agent.destroy();return send;
}
