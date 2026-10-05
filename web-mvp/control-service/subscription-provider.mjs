import { createHmac, timingSafeEqual } from "node:crypto";
import { ControlError } from "./control-plane.mjs";

export const billingConfigured=()=>!!(process.env.STRIPE_SECRET_KEY&&process.env.STRIPE_PRICE_ID&&process.env.STRIPE_WEBHOOK_SECRET&&process.env.PUBLIC_STUDIO_ORIGIN);
async function stripe(path,body){
  const response=await fetch("https://api.stripe.com/v1/"+path,{method:body?"POST":"GET",headers:{Authorization:"Bearer "+process.env.STRIPE_SECRET_KEY,...(body?{"Content-Type":"application/x-www-form-urlencoded"}:{})},
    ...(body?{body:new URLSearchParams(body)}:{}),signal:AbortSignal.timeout(10000),redirect:"error"});
  if(!response.ok)throw new ControlError("BILLING_PROVIDER_ERROR",502);return response.json();
}
export async function billingCheckout(plane,accessToken){
  const actor=plane.browser(accessToken);
  if(!billingConfigured())throw new ControlError("BILLING_NOT_CONFIGURED",503);
  const origin=new URL(process.env.PUBLIC_STUDIO_ORIGIN);
  if(origin.protocol!=="https:")throw new ControlError("BILLING_HTTPS_REQUIRED",503);
  const session=await stripe("checkout/sessions",{mode:"subscription","line_items[0][price]":process.env.STRIPE_PRICE_ID,"line_items[0][quantity]":"1",
    "client_reference_id":actor.accountId,"subscription_data[metadata][accountId]":actor.accountId,
    success_url:origin.origin+"/studio",cancel_url:origin.origin+"/studio"});
  if(!/^https:\/\/checkout\.stripe\.com\//.test(session.url))throw new ControlError("INVALID_CHECKOUT_URL",502);
  return {url:session.url};
}
export function verifyWebhook(raw,header,secret,now=Date.now()){
  if(typeof header!=="string"||header.length>2048)throw new ControlError("INVALID_WEBHOOK",401);
  const parts=header.split(","),at=parts.find(p=>p.startsWith("t="))?.slice(2),signatures=parts.filter(p=>p.startsWith("v1=")).map(p=>p.slice(3));
  if(!at||!/^\d+$/.test(at)||Math.abs(now/1000-Number(at))>300)throw new ControlError("WEBHOOK_EXPIRED",401);
  const expected=createHmac("sha256",secret).update(at+".").update(raw).digest();
  if(!signatures.some(s=>/^[a-f0-9]{64}$/.test(s)&&timingSafeEqual(expected,Buffer.from(s,"hex"))))throw new ControlError("INVALID_WEBHOOK",401);
  return JSON.parse(raw.toString("utf8"));
}
export async function billingWebhook(plane,raw,header){
  if(!billingConfigured())throw new ControlError("BILLING_NOT_CONFIGURED",503);
  const event=verifyWebhook(raw,header,process.env.STRIPE_WEBHOOK_SECRET,plane.now());
  if(typeof event.id!=="string"||!/^evt_[A-Za-z0-9]+$/.test(event.id))throw new ControlError("INVALID_WEBHOOK",400);
  if(plane.get("SELECT id FROM billing_events WHERE id=?",event.id))return {received:true};
  if(["customer.subscription.created","customer.subscription.updated","customer.subscription.deleted"].includes(event.type)){
    const subId=event.data?.object?.id;if(!/^sub_[A-Za-z0-9]+$/.test(subId))throw new ControlError("INVALID_SUBSCRIPTION",400);
    // Re-fetch authoritative state; a delayed webhook must not resurrect expired authority.
    const sub=await stripe("subscriptions/"+subId),accountId=sub.metadata?.accountId;
    if(plane.get("SELECT id FROM accounts WHERE id=?",accountId??"")){
      const paidItems=sub.items?.data?.filter(i=>i.price?.id===process.env.STRIPE_PRICE_ID)??[];
      const ends=paidItems.map(i=>Number(i.current_period_end??sub.current_period_end)).filter(n=>Number.isFinite(n)&&n>0);
      const until=["active","trialing"].includes(sub.status)&&ends.length?Math.max(...ends)*1000:plane.now();
      plane.provisionAccount(accountId,until);
      if(until<=plane.now())plane.run("UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?",accountId);
      plane.event(accountId,"billing_reconciled",{eventId:event.id,status:sub.status,until});
    }
  }
  plane.run("INSERT OR IGNORE INTO billing_events VALUES(?,?)",event.id,plane.now());return {received:true};
}
