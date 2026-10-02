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
        for (const statement of statements) await statement.all();
        sqlite.exec('COMMIT');
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
