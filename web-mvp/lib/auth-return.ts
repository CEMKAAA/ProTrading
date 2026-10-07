// The email-verification redirect is not a BFF login. Never retain its tokens.
export function authReturn(hash: string): 'confirmed' | 'failed' | null {
  const params=new URLSearchParams(hash.replace(/^#/,''));
  if(params.has('error')||params.has('error_code'))return 'failed';
  if(params.has('access_token')||params.has('refresh_token'))return 'confirmed';
  return null;
}
