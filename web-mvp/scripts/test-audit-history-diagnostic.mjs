import assert from 'node:assert/strict';
import {test} from 'node:test';
import {auditHistoryFailureCode, maxBarsMessage} from '../lib/audit-history-diagnostic.ts';
import {friendlyError} from '../lib/studio-help.ts';
import {connectionMessages} from '../lib/connection-messages.ts';

const detail = 'MA HISTORY BLOCKED / signal CopyRates copied=100000 error=0 seed=2025.10.28 14:45 first=2025.10.28 15:25 bars=100009 max=100000';
test('actual BTCUSD 2W and 5W failures identify the terminal capacity limit', () => {
  for (const d of [detail, detail.replace('15:25', '15:20').replace('100009', '100008')]) {
    assert.equal(auditHistoryFailureCode('AUDIT_HISTORY_BLOCKED', d), 'AUDIT_MAX_BARS_LIMIT');
    assert.equal(friendlyError('AUDIT_HISTORY_BLOCKED', d), maxBarsMessage);
  }
});
test('downloads, broker gaps and malformed diagnostics are not relabeled as terminal limits', () => {
  for (const d of [undefined, '', detail.replace('copied=100000', 'copied=5000'),
    detail.replace('bars=100009', 'bars=99999'), detail.replace('max=100000', 'max=0'),
    detail.replace('error=0', 'error=4401'), detail.replace('15:25', '14:45'),
    detail.replace('15:25', '14:40'), detail.replace('2025.10.28 15:25', '2025.13.28 15:25'),
    detail.replace('2025.10.28 15:25', '2025.02.30 15:25'), 'NAS_CACHE_PARTIAL first=2026.10.01 required=2026.09.10',
    'copied=100000 max=100000', detail + 'x'.repeat(1024)]) {
    assert.equal(auditHistoryFailureCode('AUDIT_HISTORY_BLOCKED', d), 'AUDIT_HISTORY_BLOCKED');
  }
});
test('unrelated failures retain their original code; explicit native capacity diagnostics work', () => {
  for (const code of ['AUDIT_AUTHORITY_EXPIRED', 'AUDIT_HISTORY_STALLED', 'TICK_DATA_MISSING']) {
    assert.equal(auditHistoryFailureCode(code, detail), code);
  }
  assert.equal(auditHistoryFailureCode('AUDIT_HISTORY_BLOCKED', 'signal origin exceeds Max bars in chart tf=5 origin=2020.01.01 00:00 loaded=2025.01.01 00:00'), 'AUDIT_MAX_BARS_LIMIT');
  assert.equal(friendlyError('AUDIT_MAX_BARS_LIMIT'), maxBarsMessage);
});
test('capacity instructions ship in English, Turkish and German without guessing results', () => {
  for (const message of connectionMessages[maxBarsMessage]) {
    assert.notEqual(message, maxBarsMessage);
    assert.ok(!message.includes('?'), 'Built-in translations must retain their Unicode characters');
    assert.match(message, /1\.000\.000/);
    assert.match(message, /\.state/);
  }
  assert.match(connectionMessages[maxBarsMessage][0], /sınırına/);
  assert.match(connectionMessages[maxBarsMessage][1], /Lücke/);
});
