import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createApp } from '../src/index.ts';

const migrations = [
  readFileSync(new URL('../migrations/0001_groups.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../migrations/0002_online_hardening.sql', import.meta.url), 'utf8'),
].join('\n');

function d1Sqlite() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(migrations);
  const returnsRows = (sql) =>
    /^(SELECT|PRAGMA)/i.test(sql.trim()) || /\bRETURNING\b/i.test(sql);
  const DB = {
    prepare(sql) {
      let values = [];
      const statement = {
        bind(...next) {
          values = next;
          return statement;
        },
        async all() {
          const prepared = sqlite.prepare(sql);
          if (returnsRows(sql)) {
            return {
              results: prepared.all(...values),
              meta: { changes: 0, last_row_id: 0 },
            };
          }
          const result = prepared.run(...values);
          return {
            results: [],
            meta: {
              changes: Number(result.changes ?? 0),
              last_row_id: Number(result.lastInsertRowid ?? 0),
            },
          };
        },
      };
      return statement;
    },
    async batch(statements) {
      sqlite.exec('BEGIN IMMEDIATE');
      try {
        const results = [];
        for (const statement of statements) results.push(await statement.all());
        sqlite.exec('COMMIT');
        return results;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
    async exec(sql) {
      sqlite.exec(sql);
    },
  };
  return DB;
}

test('Better Auth email/password bearer session works on a D1-shaped runtime', async () => {
  const app = createApp();
  const env = {
    DB: d1Sqlite(),
    BETTER_AUTH_SECRET: 'local-test-secret-please-change-32-chars',
    BETTER_AUTH_URL: 'https://local',
    AUTH_RATE_LIMITER: { async limit() { return { success: true }; } },
  };
  const signUp = await app.request(
    'https://local/api/auth/sign-up/email',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        origin: 'https://local',
        'cf-connecting-ip': '198.51.100.20',
      },
      body: JSON.stringify({
        name: 'Local Tester',
        email: 'auth@example.test',
        password: 'local-password-123',
      }),
    },
    env,
  );
  assert.equal(signUp.status, 200);
  const signUpToken = signUp.headers.get('set-auth-token');
  assert.ok(signUpToken);
  const signUpCookie = signUp.headers.get('set-cookie') ?? '';
  assert.match(signUpCookie, /Secure/i);
  assert.match(signUpCookie, /SameSite=Lax/i);

  const session = await app.request(
    'https://local/api/session',
    { headers: { authorization: `Bearer ${signUpToken}` } },
    env,
  );
  assert.equal(session.status, 200);
  const sessionBody = await session.json();
  assert.equal(sessionBody.state, 'online');
  assert.ok(sessionBody.accountId);
  // The app names the signed-in person with the email, never the raw id.
  assert.equal(sessionBody.email, 'auth@example.test');
  assert.equal(sessionBody.name, 'Local Tester');

  const signIn = await app.request(
    'https://local/api/auth/sign-in/email',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        origin: 'https://local',
        'cf-connecting-ip': '198.51.100.20',
      },
      body: JSON.stringify({
        email: 'auth@example.test',
        password: 'local-password-123',
      }),
    },
    env,
  );
  assert.equal(signIn.status, 200);
  const signInToken = signIn.headers.get('set-auth-token');
  assert.ok(signInToken);

  const signOut = await app.request(
    'https://local/api/auth/sign-out',
    { method: 'POST', headers: { authorization: `Bearer ${signInToken}` } },
    env,
  );
  assert.equal(signOut.status, 200);
  const afterSignOut = await app.request(
    'https://local/api/session',
    { headers: { authorization: `Bearer ${signInToken}` } },
    env,
  );
  assert.equal(afterSignOut.status, 401);
});

test('cookie-backed application mutations require an exact Origin while native bearer mutations do not', async () => {
  const app = createApp();
  const env = {
    DB: d1Sqlite(),
    BETTER_AUTH_SECRET: 'local-test-secret-please-change-32-chars',
    BETTER_AUTH_URL: 'https://local',
    BETTER_AUTH_TRUSTED_ORIGINS: 'https://local',
    AUTH_RATE_LIMITER: { async limit() { return { success: true }; } },
  };
  const signUp = await app.request(
    'https://local/api/auth/sign-up/email',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        origin: 'https://local',
        'cf-connecting-ip': '198.51.100.21',
      },
      body: JSON.stringify({
        name: 'Origin Tester',
        email: 'origin@example.test',
        password: 'local-password-123',
      }),
    },
    env,
  );
  assert.equal(signUp.status, 200);
  const cookie = (signUp.headers.get('set-cookie') ?? '').split(';', 1)[0];
  const bearerToken = signUp.headers.get('set-auth-token');
  assert.ok(cookie);
  assert.ok(bearerToken);

  async function mutate(headers, key, name) {
    return app.request(
      'https://local/api/groups',
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'idempotency-key': key,
          ...headers,
        },
        body: JSON.stringify({ name }),
      },
      env,
    );
  }

  assert.equal((await mutate({ cookie }, 'missing-origin', 'Missing Origin')).status, 403);
  assert.equal(
    (await mutate({ cookie, referer: 'https://local/app' }, 'referer-only', 'Referer Only')).status,
    403,
  );
  assert.equal(
    (await mutate({ cookie, origin: 'https://evil.example' }, 'wrong-origin', 'Wrong Origin')).status,
    403,
  );
  assert.equal(
    (await mutate({ cookie, origin: 'https://local' }, 'same-origin', 'Same Origin')).status,
    201,
  );
  const goalResponse = await app.request(
    'https://local/api/goals',
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        cookie,
        origin: 'https://local',
        'idempotency-key': 'origin-goal',
      },
      body: JSON.stringify({
        title: 'Origin Goal',
        kind: 'quantity',
        visibility: 'private',
        targetMode: 'individual',
        target: 1,
        unit: 'item',
        deadline: '2026-12-31',
      }),
    },
    env,
  );
  assert.equal(goalResponse.status, 201);
  const goal = await goalResponse.json();
  const patchWithoutOrigin = await app.request(
    `https://local/api/goals/${goal.id}`,
    {
      method: 'PATCH',
      headers: {
        'content-type': 'application/json',
        cookie,
        'idempotency-key': 'origin-goal-patch',
      },
      body: JSON.stringify({ title: 'Blocked Patch' }),
    },
    env,
  );
  assert.equal(patchWithoutOrigin.status, 403);
  const deleteWithUntrustedOrigin = await app.request(
    `https://local/api/goals/${goal.id}`,
    {
      method: 'DELETE',
      headers: {
        'content-type': 'application/json',
        cookie,
        origin: 'https://evil.example',
        'idempotency-key': 'origin-goal-delete',
      },
      body: '{}',
    },
    env,
  );
  assert.equal(deleteWithUntrustedOrigin.status, 403);
  const authSignOutWithRefererOnly = await app.request(
    'https://local/api/auth/sign-out',
    {
      method: 'POST',
      headers: { cookie, referer: 'https://local/app' },
    },
    env,
  );
  assert.equal(authSignOutWithRefererOnly.status, 403);
  assert.equal(
    (
      await mutate(
        { authorization: `Bearer ${bearerToken}` },
        'native-bearer',
        'Native Bearer',
      )
    ).status,
    201,
  );
  assert.equal(
    (
      await mutate(
        { cookie, authorization: `Bearer ${bearerToken}` },
        'ambiguous-auth',
        'Ambiguous Auth',
      )
    ).status,
    403,
  );

  const read = await app.request(
    'https://local/api/groups',
    { headers: { cookie } },
    env,
  );
  assert.equal(read.status, 200);
});
