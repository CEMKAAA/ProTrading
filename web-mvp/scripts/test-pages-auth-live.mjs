import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { CLOUD_CONTROL } from '../control-service/api-location.mjs';

const site = process.env.STRATUM_PAGES_URL ?? 'https://cemkaaa.github.io/CemkaCapital/studio/';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const failures = [];
const networkFailures = [];
page.on('requestfailed', request => {
  if (request.url().startsWith(CLOUD_CONTROL)) networkFailures.push({ path: request.url().slice(CLOUD_CONTROL.length), error: request.failure()?.errorText });
});
page.on('console', message => {
  if (message.type() === 'error' && /CORS|Access-Control|Failed to fetch/.test(message.text())) failures.push(message.text());
});
try {
  await page.goto(site, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const credentials = process.env.STRATUM_TEST_CREDENTIALS ?? 'omit';
  const result = await page.evaluate(async ({ api, credentials }) => {
    const cases = [];
    for (const path of ['/health', '/v1/auth/session', '/v1/auth/register']) {
      try {
        const signup = path.endsWith('register');
        const response = await fetch(api + path, {
          method: signup ? 'POST' : 'GET', credentials, redirect: 'error',
          headers: signup ? { 'Content-Type': 'application/json', Authorization: 'Bearer ' } : {},
          ...(signup ? { body: '{}' } : {}), signal: AbortSignal.timeout(30000),
        });
        cases.push({ path, status: response.status, data: await response.json() });
      } catch (error) { cases.push({ path, error: error.message }); }
    }
    return cases;
  }, { api: CLOUD_CONTROL, credentials });
  console.log(JSON.stringify({ site, credentials, result, corsErrors: failures }, null, 2));
  if (process.env.STRATUM_EXPECT_CORS_FAILURE === '1') {
    assert.ok(result.some(item => item.error === 'Failed to fetch'));
    assert.ok(failures.length);
  } else {
    assert.deepEqual(result.map(item => item.status), [200, 401, 400]);
    assert.equal(result[0].data.ready, true);
    assert.equal(result[2].data.error, 'INVALID_REQUEST');
    if (process.env.STRATUM_AUTH_LIVE_QA === '1') {
      const qa = JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json', import.meta.url), 'utf8'));
      let verified;
      try { verified = await page.evaluate(async ({ api, qa, credentials }) => {
        let token;
        const request = async (path, body) => {
          const response = await fetch(api + path, {
            method: body === undefined ? 'GET' : 'POST', credentials, redirect: 'error',
            headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
            ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30000),
          });
          return { status: response.status, data: await response.json() };
        };
        const signup = await request('/v1/auth/register', { email: qa.email, password: qa.password });
        if(signup.status!==201||!signup.data.confirmationRequired)return {signup:signup.status,error:signup.data.error};
        const login = await request('/v1/auth/login', { email: qa.email, password: qa.password });
        token = login.data.accessToken;
        if (login.status !== 200 || !token) return { login: login.status, error: login.data.error };
        try {
          const session = await request('/v1/session');
          return { signup:signup.status,confirmationRequired:signup.data.confirmationRequired,login: login.status, session: session.status, mode: session.data.accessMode };
        } finally { await request('/v1/auth/logout', {}); }
      }, { api: CLOUD_CONTROL, qa, credentials });
      } catch (error) {
        console.log(JSON.stringify({ corsErrors: failures, networkFailures }));
        throw error;
      }
      console.log(JSON.stringify({ verifiedLogin: verified }));
      assert.equal(verified.login, 200);
      assert.equal(verified.session, 200);
      assert.equal(verified.signup,201);
    }
  }
} finally { await browser.close(); }
