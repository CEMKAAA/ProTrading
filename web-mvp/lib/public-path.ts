const basePath = process.env.NEXT_PUBLIC_BASE_PATH || '';

// Next Link prefixes routes automatically; public assets need the same prefix.
export function publicPath(path: string): string {
  if (!path.startsWith('/') || path.startsWith('//')) throw new Error('PUBLIC_PATH_INVALID');
  return basePath + path;
}
