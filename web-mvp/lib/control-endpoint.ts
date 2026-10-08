import { CLOUD_CONTROL, controlLocation } from '../control-service/api-location.mjs';

export function controlEndpoint(hostname: string, configured = ''): string {
  if (configured) return controlLocation(configured);
  if (hostname === 'localhost') return 'http://localhost:4321';
  if (hostname === '127.0.0.1' || hostname === '[::1]') return 'http://127.0.0.1:4321';
  return CLOUD_CONTROL;
}

export const CONTROL_API = controlEndpoint(typeof window === 'undefined' ? '' : window.location.hostname,
  process.env.NEXT_PUBLIC_CONTROL_API ?? '');
export const CLOUD_SESSION = new URL(CONTROL_API).protocol === 'https:';
const sessionKey = 'stratum.cloud-session.v1';
export function storedSession(): string {
  if (!CLOUD_SESSION || typeof window === 'undefined') return '';
  try { return sessionStorage.getItem(sessionKey) ?? ''; } catch { return ''; }
}
export function storeSession(value: string): void {
  if (!CLOUD_SESSION || typeof window === 'undefined') return;
  try { if (value) sessionStorage.setItem(sessionKey, value); else sessionStorage.removeItem(sessionKey); } catch { /* Private browsing can disable storage. */ }
}
