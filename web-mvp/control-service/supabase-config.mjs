import { existsSync,readFileSync } from 'node:fs';
// Public project credentials only. No secret/service_role key belongs in this file.
const networkFile=new URL('./.state/supabase-network.json',import.meta.url);
const network=existsSync(networkFile)?JSON.parse(readFileSync(networkFile,'utf8')):{};
export const supabaseConfig = {
  url: process.env.SUPABASE_URL ?? 'https://uvzhrrqzzdjqtmydpvwo.supabase.co',
  publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY ?? 'sb_publishable_4yCgr706ZuZL8N7_Wci2HA_DoV--QRE',
  studioOrigin: process.env.PUBLIC_STUDIO_ORIGIN ?? 'http://127.0.0.1:4310',
  ipv6Address:process.env.SUPABASE_CONNECT_IPV6??network.ipv6Address,
};
