// A late cookie probe must never overwrite a newer login or sign-out.
export async function restoreStudioSession({ cloud, saved, probe, isCurrent, accept }: {
  cloud: boolean;
  saved: string;
  probe: () => Promise<Response>;
  isCurrent: () => boolean;
  accept: (credential: string) => void;
}): Promise<void> {
  if (cloud) {
    // The dashboard verifies this opaque handle; no anonymous auth probe is needed.
    if (saved && isCurrent()) accept(saved);
    return;
  }
  const response = await probe();
  if (!isCurrent()) return;
  if (response.status === 401) { accept(''); return; }
  if (!response.ok) return;
  const data = await response.json() as { accessToken?: unknown };
  if (typeof data.accessToken !== 'string' || !data.accessToken) throw new Error('AUTH_SESSION_INVALID');
  if (isCurrent()) accept(data.accessToken);
}
