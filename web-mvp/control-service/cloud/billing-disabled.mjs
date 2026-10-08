import { ControlError } from './generated/control-plane.mjs';
// A cloud trial is real. Paid checkout is not enabled until payment/webhook configuration exists.
export const billingConfigured=()=>false;
export async function billingCheckout(){throw new ControlError('BILLING_NOT_CONFIGURED',503);}
export async function billingWebhook(){throw new ControlError('BILLING_NOT_CONFIGURED',503);}
