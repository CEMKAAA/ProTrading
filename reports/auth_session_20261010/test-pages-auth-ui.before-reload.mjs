import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { CLOUD_CONTROL } from '../control-service/api-location.mjs';

const qa = JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json', import.meta.url), 'utf8'));
const site = process.env.STRATUM_PAGES_URL ?? 'https://cemkaaa.github.io/CemkaCapital/studio/';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const failures = [], calls = [], responses = [];
let token;
page.on('request', request => {
  if (request.url().includes('/v1/auth/')) calls.push({ url: request.url(), method: request.method() });
});
page.on('console', message => {
  if (message.type() === 'error' && /CORS|Access-Control/.test(message.text())) failures.push(message.text());
});
page.on('response', response => {
  if (response.url().startsWith(CLOUD_CONTROL)) responses.push({ path: response.url().slice(CLOUD_CONTROL.length), status: response.status() });
});
try {
  await page.goto(site, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // The form replaces the restoring state only after React hydration completes.
  const form = page.locator('form.uc-login');
  await form.waitFor({state:'visible',timeout:60000});
  await form.locator('input[type=email]').fill(qa.email);
  await form.locator('input[type=password]').fill(qa.password);
  const sessionPromise = page.waitForResponse(response => response.url() === CLOUD_CONTROL + '/v1/session' && response.status() === 200, { timeout: 90000 });
  const responsePromise = page.waitForResponse(response => response.url() === CLOUD_CONTROL + '/v1/auth/login', { timeout: 60000 });
  // Keep both listeners handled if a gateway failure prevents either response.
  void sessionPromise.catch(()=>{});void responsePromise.catch(()=>{});
  await form.locator('button[type=submit],button.primary-btn').click();
  const response = await responsePromise;
  const result = await response.json();
  token = result.accessToken;
  assert.equal(response.status(), 200, result.error);
  assert.ok(token);
  await sessionPromise;
  await form.waitFor({ state: 'detached', timeout: 45000 });
  // Observe several automatic refreshes, not just the first successful login response.
  await page.waitForTimeout(15000);
  assert.equal(failures.length, 0);
  assert.ok(calls.length > 0);
  assert.ok(calls.every(call => call.url.startsWith(CLOUD_CONTROL)));
  assert.doesNotMatch(await page.locator('body').innerText(), /Yerel kontrol servisine|Cannot reach the local control service/);
  assert.deepEqual(responses.filter(response=>response.status>=500),[]);
} catch (error) {
  console.log(JSON.stringify({ failures, calls, responses, alerts: await page.locator('[role=alert],.uc-error').allTextContents() }));
  throw error;
} finally {
  try {
    if (token) {
      const cleanup = await page.evaluate(async ({ api, token }) => {
        const response = await fetch(api + '/v1/auth/logout', { method: 'POST', credentials: 'omit', redirect: 'error', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: '{}', signal: AbortSignal.timeout(45000) });
        const value = await response.json();
        return { status: response.status, error: value.error };
      }, { api: CLOUD_CONTROL, token });
      assert.ok([200, 401].includes(cleanup.status), 'QA logout: ' + JSON.stringify(cleanup));
      assert.deepEqual(responses.filter(response=>response.status>=500),[]);
    }
  } finally { await browser.close(); }
}
console.log(JSON.stringify({ status: 'PASS', site, responses, checks: ['published login form', 'real Supabase QA login', 'authenticated session', 'no localhost auth calls', 'no CORS errors', 'no server 5xx responses', 'test-session cleanup'], nativeTradingRequested: false }));
