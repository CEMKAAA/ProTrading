export const maxBarsMessage = 'MT5 reached its Max bars in chart limit, not a confirmed broker-history gap. In MT5, open Tools > Options > Charts, increase Max bars in chart (for example to 1,000,000), restart MT5, then retry the audit. Keep the same helper and .state folder. Short audits can also need earlier candles to initialize the signal engine.';

function nativeTime(value: string): number | null {
  const iso = value.replaceAll('.', '-').replace(' ', 'T');
  const ms = Date.parse(iso + ':00Z');
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 16) === iso ? ms : null;
}

// Interpret only the engine's explicit capacity diagnostic. A short copy alone
// is not evidence of a terminal limit: it can also be a download or broker gap.
export function auditHistoryFailureCode(code: string, detail?: string): string {
  if (code !== 'AUDIT_HISTORY_BLOCKED' || !detail || detail.length > 1024) return code;
  if (/(?:^|[ /|])signal origin exceeds Max bars in chart(?:$| )/.test(detail)) return 'AUDIT_MAX_BARS_LIMIT';
  const m = /(?:^|[ /|])signal CopyRates copied=(\d+) error=(\d+) seed=(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) first=(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) bars=(\d+) max=(\d+)(?:$|[ |])/.exec(detail);
  if (!m) return code;
  const [, copied, error, seed, first, bars, max] = m;
  const start = nativeTime(seed), loaded = nativeTime(first), limit = Number(max);
  return limit > 0 && Number.isSafeInteger(limit) && Number(copied) === limit
    && Number(error) === 0 && Number(bars) >= limit && start !== null && loaded !== null && loaded > start
    ? 'AUDIT_MAX_BARS_LIMIT' : code;
}
