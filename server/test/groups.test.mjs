import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createApp } from '../src/index.ts';

const migration = [
  readFileSync(new URL('../migrations/0001_groups.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('../migrations/0002_online_hardening.sql', import.meta.url), 'utf8'),
].join('\n');

function isRead(sql) {
  const normalized = sql.trim().toUpperCase();
  return normalized.startsWith('SELECT') || normalized.startsWith('PRAGMA');
}

function setup(verifier = async (request) => ({
  // This is a test-only identity fixture. Production createApp() uses Better Auth.
  accountId: request.headers.get('authorization')?.replace(/^Bearer /, '') ?? '',
})) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(migration);
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
          if (isRead(sql)) return { results: prepared.all(...values) };
          const result = prepared.run(...values);
          return { results: [], meta: { changes: Number(result.changes ?? 0) } };
        },
        async first() {
          return sqlite.prepare(sql).get(...values) ?? null;
        },
        async run() {
          return sqlite.prepare(sql).run(...values);
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
  const app = createApp(verifier);
  async function call(user, method, path, body, key) {
    const headers = {
      authorization: `Bearer ${user}`,
      'content-type': 'application/json',
    };
    if (key !== undefined) headers['Idempotency-Key'] = key;
    const response = await app.request(
      `http://local${path}`,
      {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      },
      { DB },
    );
    const raw = await response.text();
    return {
      status: response.status,
      body: raw ? JSON.parse(raw) : null,
    };
  }
  return { call, DB };
}

const quantityGoal = (
  groupId,
  visibility = 'shared',
  targetMode = 'shared_total',
) => ({
  title: 'Read',
  kind: 'quantity',
  visibility,
  groupId,
  targetMode,
  target: 10,
  unit: 'pages',
  deadline: '2026-12-31',
});

async function createGroup(call, user = 'alice', key = `g-${user}`) {
  return (await call(user, 'POST', '/api/groups', { name: 'Friends' }, key)).body;
}

test('membership, privacy, revocation and concurrent idempotent progress', async () => {
  const { call } = setup();
  const group = await createGroup(call);
  assert.deepEqual(
    (await call('alice', 'POST', '/api/groups', { name: 'Friends' }, 'g-alice')).body,
    group,
  );
  const privateGoal = (
    await call(
      'alice',
      'POST',
      '/api/goals',
      quantityGoal(null, 'private', 'individual'),
      'private',
    )
  ).body;
  assert.equal((await call('bob', 'GET', `/api/goals/${privateGoal.id}`)).status, 404);
  const shared = (
    await call('alice', 'POST', '/api/goals', quantityGoal(group.id), 'shared')
  ).body;
  assert.equal((await call('bob', 'GET', `/api/goals/${shared.id}`)).status, 404);
  await call('bob', 'POST', '/api/groups/join', { code: group.joinCode }, 'join-bob');
  const requests = Array.from({ length: 8 }, () =>
    call('bob', 'POST', `/api/goals/${shared.id}/progress`, { amount: 3 }, 'p'),
  );
  const results = await Promise.all(requests);
  assert.equal(new Set(results.map((result) => result.body.id)).size, 1);
  assert.equal((await call('alice', 'GET', `/api/goals/${shared.id}`)).body.total, 3);
  assert.equal(
    (await call('bob', 'POST', `/api/goals/${shared.id}/progress`, { amount: 99 }, 'p')).status,
    409,
  );
  assert.equal((await call('eve', 'POST', `/api/groups/${group.id}/revoke/bob`, {}, 'bad-revoke')).status, 403);
  await call('alice', 'POST', `/api/groups/${group.id}/revoke/bob`, {}, 'revoke-bob');
  assert.equal((await call('bob', 'GET', `/api/goals/${shared.id}`)).status, 404);
  assert.equal(
    (await call('bob', 'POST', '/api/groups/join', { code: group.joinCode }, 'join-again')).status,
    403,
  );
});

test('individual quantity and checklist totals are actor-scoped', async () => {
  const { call } = setup();
  const group = await createGroup(call);
  await call('bob', 'POST', '/api/groups/join', { code: group.joinCode }, 'join-bob');
  const individual = (
    await call(
      'alice',
      'POST',
      '/api/goals',
      quantityGoal(group.id, 'shared', 'individual'),
      'individual',
    )
  ).body;
  await call('bob', 'POST', `/api/goals/${individual.id}/progress`, { amount: 2 }, 'bob-progress');
  assert.equal((await call('bob', 'GET', `/api/goals/${individual.id}`)).body.total, 2);
  assert.equal((await call('alice', 'GET', `/api/goals/${individual.id}`)).body.total, 0);

  const checklist = (
    await call(
      'alice',
      'POST',
      '/api/goals',
      { ...quantityGoal(group.id), kind: 'checklist', unit: '', target: 2 },
      'checklist',
    )
  ).body;
  const item = (
    await call('alice', 'POST', `/api/goals/${checklist.id}/items`, { title: 'First' }, 'item')
  ).body;
  assert.equal(
    (await call('bob', 'POST', `/api/goals/${checklist.id}/items`, { title: 'No' }, 'bad-item')).status,
    403,
  );
  await call('bob', 'PUT', `/api/goals/${checklist.id}/items/${item.id}/check`, { checked: true }, 'bob-check');
  assert.equal((await call('alice', 'GET', `/api/goals/${checklist.id}`)).body.total, 1);
  assert.equal((await call('bob', 'GET', `/api/goals/${checklist.id}`)).body.total, 1);
  await call('bob', 'PUT', `/api/goals/${checklist.id}/items/${item.id}/check`, { checked: false }, 'bob-uncheck');
  assert.equal((await call('bob', 'GET', `/api/goals/${checklist.id}`)).body.total, 0);
});

test('strict input validation and idempotency binding', async () => {
  const { call } = setup();
  assert.equal((await call('alice', 'POST', '/api/groups', { name: 'x' }, 'x'.repeat(129))).status, 400);
  assert.equal(
    (
      await call(
        'alice',
        'POST',
        '/api/goals',
        { ...quantityGoal(null, 'private', 'individual'), deadline: '2026-02-30' },
        'bad-date',
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await call(
        'alice',
        'POST',
        '/api/goals',
        { ...quantityGoal(null, 'private', 'individual'), deadline: '2026-12-31' },
        'bad-date',
      )
    ).status,
    201,
  );
  const group = await createGroup(call, 'alice', 'another-group');
  const goal = (
    await call('alice', 'POST', '/api/goals', quantityGoal(group.id), 'binding-goal')
  ).body;
  await call('bob', 'POST', '/api/groups/join', { code: group.joinCode }, 'binding-join');
  assert.equal(
    (await call('bob', 'POST', `/api/goals/${goal.id}/progress`, { amount: 1, url: 'https://ok.example/a' }, 'binding-progress')).status,
    201,
  );
  assert.equal(
    (await call('bob', 'POST', `/api/goals/${goal.id}/progress`, { amount: 2, url: 'https://ok.example/a' }, 'binding-progress')).status,
    409,
  );
});

test('missing Better Auth configuration fails closed', async () => {
  const app = createApp();
  const response = await app.request('http://local/api/session');
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    state: 'setup_needed',
    message: 'Better Auth is not configured. Set BETTER_AUTH_SECRET and bind a D1 database.',
  });
});
