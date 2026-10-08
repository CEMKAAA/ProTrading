export const CLOUD_CONTROL = 'https://uvzhrrqzzdjqtmydpvwo.supabase.co/functions/v1/stratum-control';
export const PUBLIC_STUDIO = 'https://cemkaaa.github.io';

export function controlLocation(value) {
  const url = new URL(value);
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  const path = url.pathname.replace(/\/$/, '');
  if (!(url.protocol === 'https:' || (local && url.protocol === 'http:'))) throw new Error('HTTPS required');
  if (url.username || url.password || url.search || url.hash
    || !(url.protocol === 'https:' || (local && url.protocol === 'http:'))
    || (path !== '' && !/^\/functions\/v1\/[a-z][a-z0-9-]{0,62}$/.test(path))) {
    throw new Error('API_LOCATION_INVALID');
  }
  return url.origin + path;
}

export function studioLocation(value) {
  const url = new URL(value);
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/'
    || !(url.protocol === 'https:' || (url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) {
    throw new Error('STUDIO_ORIGIN_INVALID');
  }
  return url.origin;
}
