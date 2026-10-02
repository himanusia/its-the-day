import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createApp, worker } from '../src/index.ts';

const configText = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8');
const packageText = readFileSync(new URL('../package.json', import.meta.url), 'utf8');

function fakeDb() {
  return { prepare() { throw new Error('database should not be touched'); } };
}

function executionContext() {
  return {
    waitUntil() {},
    passThroughOnException() {},
  };
}

function assetsFixture() {
  const calls = [];
  return {
    calls,
    async fetch(request) {
      const pathname = new URL(request.url).pathname;
      calls.push(pathname);
      if (pathname === '/index.html') {
        return new Response('<!doctype html><html><body>Flutter</body></html>', {
          headers: { 'content-type': 'text/html; charset=UTF-8' },
        });
      }
      return new Response('Not Found', {
        status: 404,
        headers: { 'content-type': 'text/plain; charset=UTF-8' },
      });
    },
  };
}

test('Worker gives API and auth paths priority over static assets', async () => {
  const assets = assetsFixture();
  const env = { DB: fakeDb(), ASSETS: assets };

  const index = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/index.html'),
    env,
    executionContext(),
  );
  assert.equal(index.status, 200);
  assert.match(await index.text(), /Flutter/);

  const missingApi = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api/does-not-exist'),
    env,
    executionContext(),
  );
  assert.equal(missingApi.status, 404);
  assert.equal(await missingApi.text(), '404 Not Found');
  assert.equal(assets.calls.includes('/api/does-not-exist'), false);

  const missingRootApi = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api'),
    env,
    executionContext(),
  );
  assert.equal(missingRootApi.status, 404);
  assert.equal(assets.calls.includes('/api'), false);
});

test('missing document assets remain 404 instead of becoming the Flutter HTML shell', async () => {
  const assets = assetsFixture();
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/missing.js'),
    { DB: fakeDb(), ASSETS: assets },
    executionContext(),
  );

  assert.equal(response.status, 404);
  assert.equal(response.headers.get('content-type')?.startsWith('text/html'), false);
  assert.equal(await response.text(), 'Not Found');
  assert.deepEqual(assets.calls, ['/missing.js']);
});

test('Wrangler config pins static hosting, same-origin auth, custom domain, D1 and CF rate limiting', () => {
  assert.match(packageText, /"wrangler"\s*:\s*"4\.146\.0"/);
  assert.match(configText, /"name"\s*:\s*"its-the-day-groups"/);
  assert.match(configText, /"directory"\s*:\s*"\.\.\/build\/web"/);
  assert.match(configText, /"binding"\s*:\s*"ASSETS"/);
  assert.match(configText, /"not_found_handling"\s*:\s*"404-page"/);
  assert.match(configText, /"run_worker_first"\s*:\s*\[\s*"\/api"\s*,\s*"\/api\/\*"\s*\]/);
  assert.match(configText, /"pattern"\s*:\s*"its-the-day\.himanusia\.com"/);
  assert.match(configText, /"custom_domain"\s*:\s*true/);
  assert.match(configText, /"BETTER_AUTH_URL"\s*:\s*"https:\/\/its-the-day\.himanusia\.com"/);
  assert.match(configText, /"BETTER_AUTH_TRUSTED_ORIGINS"\s*:\s*"https:\/\/its-the-day\.himanusia\.com"/);
  assert.match(configText, /"database_id"\s*:\s*"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"/);
  assert.match(configText, /"name"\s*:\s*"AUTH_RATE_LIMITER"/);
  assert.match(configText, /"namespace_id"\s*:\s*"[1-9]\d*"/);
});

test('health keeps Google explicitly setup-needed without Web OAuth credentials', async () => {
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/health'),
    { DB: fakeDb() },
    executionContext(),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true,
    auth: 'setup_needed',
    google: 'setup_needed',
  });
});

test('public auth rate limiting uses the Cloudflare client IP and never an isolate-local map', async () => {
  const calls = [];
  const appEnv = {
    DB: fakeDb(),
    AUTH_RATE_LIMITER: {
      async limit(input) {
        calls.push(input);
        return { success: true };
      },
    },
  };
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api/auth/sign-in/email', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': '198.51.100.7',
        'x-forwarded-for': '203.0.113.99',
      },
      body: JSON.stringify({ email: 'auth@example.test', password: 'not-a-secret' }),
    }),
    appEnv,
    executionContext(),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    state: 'setup_needed',
    message: 'Better Auth is not configured. Set BETTER_AUTH_SECRET and bind a D1 database.',
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0].key, /^auth:POST:\/api\/auth\/sign-in\/email:198\.51\.100\.7$/);
  assert.equal(calls[0].key.includes('203.0.113.99'), false);
});

test('public auth rate limiting fails closed without a trustworthy Cloudflare IP', async () => {
  let calls = 0;
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api/auth/sign-up/email', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-forwarded-for': '198.51.100.8',
      },
      body: JSON.stringify({ email: 'auth@example.test', password: 'not-a-secret' }),
    }),
    {
      DB: fakeDb(),
      AUTH_RATE_LIMITER: {
        async limit() {
          calls += 1;
          return { success: true };
        },
      },
    },
    executionContext(),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'auth_unavailable' });
  assert.equal(calls, 0);
});

test('public auth rate limiting returns a bounded generic 429 response', async () => {
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api/auth/sign-in/email', {
      method: 'POST',
      headers: { 'cf-connecting-ip': '198.51.100.9' },
    }),
    {
      DB: fakeDb(),
      AUTH_RATE_LIMITER: {
        async limit() {
          return { success: false };
        },
      },
    },
    executionContext(),
  );

  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '60');
  assert.deepEqual(await response.json(), { error: 'rate_limited' });
});

test('unexpected server errors are generic and do not expose thrown details', async () => {
  const app = createApp(async () => ({ accountId: 'alice' }));
  const secretLikeDetail = 'internal-token-that-must-not-escape';
  const response = await app.request(
    'http://local/api/groups',
    { headers: { authorization: 'Bearer alice' } },
    {
      DB: {
        prepare() {
          throw new Error(secretLikeDetail);
        },
      },
    },
  );
  const raw = await response.text();

  assert.equal(response.status, 500);
  assert.deepEqual(JSON.parse(raw), { error: 'internal_error' });
  assert.equal(raw.includes(secretLikeDetail), false);
});

test('HTTPS Better Auth setup requires the CF limiter instead of falling back to isolate state', async () => {
  const response = await worker.fetch(
    new Request('https://its-the-day.himanusia.com/api/auth/sign-in/email', {
      method: 'POST',
      headers: { 'cf-connecting-ip': '198.51.100.10' },
    }),
    {
      DB: fakeDb(),
      BETTER_AUTH_SECRET: 'local-test-secret-please-change-32-chars',
      BETTER_AUTH_URL: 'https://its-the-day.himanusia.com',
    },
    executionContext(),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    state: 'setup_needed',
    message: 'Better Auth is not configured. Set BETTER_AUTH_SECRET and bind a D1 database.',
  });
});
