import { Hono } from 'hono';
import type { Context } from 'hono';
import { betterAuth } from 'better-auth';
import type { BetterAuthOptions, D1Database } from 'better-auth';
import { bearer } from 'better-auth/plugins';

type Row = Record<string, unknown>;
type D1Meta = Record<string, unknown> & { changes?: number };
type D1Result<T> = { results: T[]; meta?: D1Meta };

/**
 * A small common surface shared by the real Cloudflare D1 binding and the
 * deterministic test adapter. Cloudflare's D1 statement has `all()` only;
 * `first()` and `run()` are convenience methods supplied by the test adapter.
 */
export interface Statement {
  bind(...values: unknown[]): Statement;
  all<T = Row>(): Promise<D1Result<T>>;
  first?<T = Row>(): Promise<T | null>;
  run?(): Promise<unknown>;
}

export interface Database {
  prepare(sql: string): Statement;
  batch?(statements: Statement[]): Promise<D1Result<unknown>[]>;
  exec?(sql: string): Promise<unknown>;
}

export interface Identity {
  accountId: string;
  /// Present for real Better Auth sessions. Tests may supply an id only.
  email?: string | null;
  name?: string | null;
}

/**
 * The verifier is intentionally injectable only for tests. The product path
 * below uses Better Auth's session API and never turns an arbitrary bearer
 * string into an account id.
 */
export type SessionVerifier = (
  request: Request,
  env?: Bindings,
) => Promise<Identity | null>;

export type Bindings = {
  DB: Database;
  BETTER_AUTH_SECRET?: string;
  BETTER_AUTH_URL?: string;
  BETTER_AUTH_TRUSTED_ORIGINS?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
};

type AppEnv = {
  Bindings: Bindings;
  Variables: {
    actor: string;
    actorEmail: string | null;
    actorName: string | null;
  };
};
type AppContext = Context<AppEnv>;
type BetterAuthLike = {
  handler(request: Request): Promise<Response>;
  api: {
    getSession(input: {
      headers: Headers;
    }): Promise<{
      user?: { id?: string; email?: string | null; name?: string | null };
    } | null>;
  };
};
type AppOptions = { sessionVerifier?: SessionVerifier };
type MutationStatement = { sql: string; args: unknown[]; required?: boolean };
type OperationBinding = { method: string; path: string; bodyHash: string };
type StoredMutation = { body: unknown; status: number; replay: boolean };

export const setupNeeded = {
  state: 'setup_needed',
  message:
    'Better Auth is not configured. Set BETTER_AUTH_SECRET and bind a D1 database.',
};

const now = () => new Date().toISOString();
const id = () => crypto.randomUUID();
const jsonString = (body: unknown) => JSON.stringify(body);
const text = (value: unknown) => (typeof value === 'string' ? value.trim() : '');
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

function boundedString(
  value: unknown,
  max: number,
  required = false,
): string | null {
  if (value === undefined || value === null) return required ? null : '';
  if (typeof value !== 'string') return null;
  const result = value.trim();
  if (required && result.length === 0) return null;
  return result.length <= max ? result : null;
}

function calendarDate(value: unknown): string | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

function positiveInteger(value: unknown): number | null {
  return typeof value === 'number' &&
      Number.isSafeInteger(value) &&
      value > 0
    ? value
    : null;
}

function validUrl(value: unknown): boolean {
  if (value === undefined || value === null || value === '') return true;
  if (typeof value !== 'string' || value.length > 2048 || /\s/.test(value)) {
    return false;
  }
  try {
    const parsed = new URL(value);
    return (
      (parsed.protocol === 'http:' || parsed.protocol === 'https:') &&
      parsed.hostname.length > 0 &&
      parsed.username.length === 0 &&
      parsed.password.length === 0
    );
  } catch {
    return false;
  }
}

function validIdempotencyKey(value: string | undefined): value is string {
  return value !== undefined && /^[\x21-\x7e]{1,128}$/.test(value);
}

function validJoinCode(value: unknown): string | null {
  const code = boundedString(value, 32, true);
  return code && /^[A-Za-z0-9_-]{4,32}$/.test(code)
    ? code.toUpperCase()
    : null;
}

function randomJoinCode(): string {
  return crypto.randomUUID().replaceAll('-', '').slice(0, 8).toUpperCase();
}

function stableJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableJson(object[key])}`)
    .join(',')}}`;
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

async function all<T = Row>(
  db: Database,
  sql: string,
  ...args: unknown[]
): Promise<T[]> {
  const result = await db.prepare(sql).bind(...args).all<T>();
  return result.results ?? [];
}

async function first<T = Row>(
  db: Database,
  sql: string,
  ...args: unknown[]
): Promise<T | null> {
  const statement = db.prepare(sql).bind(...args);
  if (statement.first) return statement.first<T>();
  return (await statement.all<T>()).results[0] ?? null;
}

async function run(
  db: Database,
  sql: string,
  ...args: unknown[]
): Promise<unknown> {
  const statement = db.prepare(sql).bind(...args);
  if (statement.run) return statement.run();
  return statement.all();
}

async function atomicBatch(
  db: Database,
  statements: MutationStatement[],
): Promise<D1Result<unknown>[]> {
  if (db.batch) {
    return db.batch(
      statements.map(({ sql, args }) => db.prepare(sql).bind(...args)),
    );
  }
  // Real D1 always supplies batch(). This fallback keeps a small injected
  // adapter usable for read/authorization tests, but is never the Workers
  // production path and is intentionally documented as non-atomic.
  const results: D1Result<unknown>[] = [];
  for (const statement of statements) {
    results.push(await db.prepare(statement.sql).bind(...statement.args).all());
  }
  return results;
}

async function readBody(c: AppContext): Promise<Record<string, unknown> | null> {
  try {
    const body: unknown = await c.req.json();
    return isRecord(body) ? body : null;
  } catch {
    return null;
  }
}

function reply(
  c: AppContext,
  body: unknown,
  status = 200,
  replay = false,
): Response {
  return c.json(
    body,
    status as never,
    replay ? { 'Idempotent-Replay': 'true' } : undefined,
  );
}

function betterAuthConfigured(env: Bindings | undefined): boolean {
  if (!env) return false;
  return (
    typeof env.BETTER_AUTH_SECRET === 'string' &&
    env.BETTER_AUTH_SECRET.trim().length >= 32 &&
    typeof env.DB?.prepare === 'function' &&
    typeof env.DB?.batch === 'function' &&
    typeof env.DB?.exec === 'function'
  );
}

function configuredOrigins(env: Bindings | undefined): string[] {
  if (!env) return [];
  const values = [
    env.BETTER_AUTH_URL,
    ...(env.BETTER_AUTH_TRUSTED_ORIGINS ?? '').split(','),
  ];
  return values
    .map((value) => value?.trim() ?? '')
    .filter((value) => value.length > 0);
}

function createBetterAuth(env: Bindings | undefined): BetterAuthLike | null {
  if (!env || !betterAuthConfigured(env)) return null;
  const secret = env.BETTER_AUTH_SECRET!.trim();
  const origins = configuredOrigins(env);
  const googleClientId = text(env.GOOGLE_CLIENT_ID);
  const googleClientSecret = text(env.GOOGLE_CLIENT_SECRET);
  const options: BetterAuthOptions = {
    appName: "It's the Day!",
    database: env.DB as unknown as D1Database,
    secret,
    ...(env.BETTER_AUTH_URL
      ? { baseURL: env.BETTER_AUTH_URL.trim() }
      : {}),
    ...(origins.length > 0 ? { trustedOrigins: origins } : {}),
    emailAndPassword: {
      enabled: true,
      autoSignIn: true,
      minPasswordLength: 8,
      maxPasswordLength: 128,
    },
    // The bearer plugin is Better Auth's supported native/mobile transport.
    // Browser callers continue to use the normal Better Auth cookie.
    plugins: [bearer()],
    advanced: {
      // Core Better Auth tables are managed by the checked-in D1 migrations.
      // D1 schema validation is disabled because Worker startup must not issue
      // an introspection round-trip on every per-request auth instance.
      database: { validateSchema: false },
      useSecureCookies: env.BETTER_AUTH_URL?.startsWith('https://') ?? false,
    },
  };
  if (googleClientId && googleClientSecret) {
    options.socialProviders = {
      google: {
        clientId: googleClientId,
        clientSecret: googleClientSecret,
      },
    };
  }
  return betterAuth(options) as unknown as BetterAuthLike;
}

async function verifyBetterAuthSession(
  request: Request,
  env: Bindings,
): Promise<Identity | null> {
  const auth = createBetterAuth(env);
  if (!auth) throw new Error('better_auth_setup_needed');
  const session = await auth.api.getSession({ headers: request.headers });
  const accountId = session?.user?.id;
  if (!accountId) return null;
  return {
    accountId,
    email: typeof session?.user?.email === 'string' ? session.user.email : null,
    name: typeof session?.user?.name === 'string' ? session.user.name : null,
  };
}

function reservationPredicate(binding: OperationBinding): string {
  return `EXISTS (
    SELECT 1 FROM idempotency
    WHERE actor_id=? AND key=? AND method=? AND path=? AND body_hash=? AND completed=0
  )`;
}

function reservationArgs(
  actorId: string,
  key: string,
  binding: OperationBinding,
): unknown[] {
  return [actorId, key, binding.method, binding.path, binding.bodyHash];
}

function membershipPredicate(groupIdColumn: string, actorIdColumn = '?') {
  return `EXISTS (
    SELECT 1 FROM memberships m
    WHERE m.group_id=${groupIdColumn} AND m.account_id=${actorIdColumn} AND m.active=1
  )`;
}

async function idempotentMutation(
  c: AppContext,
  key: string,
  body: Record<string, unknown>,
  responseBody: unknown,
  responseStatus: number,
  mutationStatements: MutationStatement[],
): Promise<StoredMutation | Response> {
  const actorId = c.get('actor');
  const binding: OperationBinding = {
    method: c.req.method.toUpperCase(),
    path: new URL(c.req.url).pathname,
    bodyHash: await sha256(stableJson(body)),
  };
  const db = c.env.DB;
  const existing = await first<Row>(
    db,
    'SELECT method,path,body_hash AS bodyHash,response,response_status AS responseStatus,completed FROM idempotency WHERE actor_id=? AND key=?',
    actorId,
    key,
  );
  if (existing) {
    const matches =
      existing.method === binding.method &&
      existing.path === binding.path &&
      existing.bodyHash === binding.bodyHash;
    if (!matches) {
      return reply(c, { error: 'idempotency_key_conflict' }, 409);
    }
    if (Number(existing.completed) !== 1 || existing.response === '__pending__') {
      return reply(c, { error: 'idempotency_in_progress' }, 409);
    }
    return {
      body: JSON.parse(String(existing.response)),
      status: Number(existing.responseStatus ?? 200),
      replay: true,
    };
  }

  const response = jsonString(responseBody);
  const conflictResponse = jsonString({ error: 'mutation_conflict' });
  const reservation: MutationStatement = {
    sql: `INSERT OR IGNORE INTO idempotency
      (actor_id,key,method,path,body_hash,response,response_status,completed,created_at)
      VALUES (?,?,?,?,?,'__pending__',?,0,?)`,
    args: [
      actorId,
      key,
      binding.method,
      binding.path,
      binding.bodyHash,
      responseStatus,
      now(),
    ],
  };
  const batch: MutationStatement[] = [reservation];
  const requiredPositions: number[] = [];
  for (const mutation of mutationStatements) {
    const required = mutation.required !== false;
    const mutationPosition = batch.length;
    batch.push(mutation);
    if (!required) continue;
    requiredPositions.push(mutationPosition);
    // D1 batch() is atomic, so a zero-row required mutation must select the
    // conflict completion below before the idempotency row can be completed.
    batch.push({
      sql: `UPDATE idempotency SET response=CASE
          WHEN response='__mutation_failed__' THEN '__mutation_failed__'
          WHEN changes() > 0 THEN '__mutation_succeeded__'
          ELSE '__mutation_failed__'
        END
        WHERE actor_id=? AND key=? AND method=? AND path=? AND body_hash=? AND completed=0`,
      args: reservationArgs(actorId, key, binding),
    });
  }
  const completionState = requiredPositions.length > 0
    ? '__mutation_succeeded__'
    : '__pending__';
  batch.push({
    sql: `UPDATE idempotency
      SET response=?,response_status=?,completed=1
      WHERE actor_id=? AND key=? AND method=? AND path=? AND body_hash=?
        AND completed=0 AND response=?`,
    args: [
      response,
      responseStatus,
      actorId,
      key,
      binding.method,
      binding.path,
      binding.bodyHash,
      completionState,
    ],
  });
  batch.push({
    sql: `UPDATE idempotency
      SET response=?,response_status=409,completed=1
      WHERE actor_id=? AND key=? AND method=? AND path=? AND body_hash=?
        AND completed=0 AND response='__mutation_failed__'`,
    args: [
      conflictResponse,
      actorId,
      key,
      binding.method,
      binding.path,
      binding.bodyHash,
    ],
  });
  const batchResults = await atomicBatch(db, batch);
  const changed = (result: D1Result<unknown> | undefined) =>
    Number(result?.meta?.changes ?? 0);
  const reserved = changed(batchResults[0]) === 1;
  const requiredSucceeded = requiredPositions.every(
    (position) => changed(batchResults[position]) > 0,
  );

  const stored = await first<Row>(
    db,
    'SELECT method,path,body_hash AS bodyHash,response,response_status AS responseStatus,completed FROM idempotency WHERE actor_id=? AND key=?',
    actorId,
    key,
  );
  if (!stored || Number(stored.completed) !== 1 || !stored.response) {
    return reply(c, { error: 'idempotency_unavailable' }, 503);
  }
  if (
    stored.method !== binding.method ||
    stored.path !== binding.path ||
    stored.bodyHash !== binding.bodyHash
  ) {
    return reply(c, { error: 'idempotency_key_conflict' }, 409);
  }
  const storedResponse = String(stored.response);
  if (reserved && !requiredSucceeded && storedResponse === response) {
    return reply(c, { error: 'mutation_conflict' }, 409);
  }
  return {
    body: JSON.parse(storedResponse),
    status: Number(stored.responseStatus ?? 200),
    replay: !reserved && storedResponse !== response,
  };
}

function sendMutationResult(c: AppContext, result: StoredMutation | Response) {
  if (result instanceof Response) return result;
  return reply(c, result.body, result.status, result.replay);
}

async function member(
  db: Database,
  groupId: string,
  accountId: string,
): Promise<Row | null> {
  return first<Row>(
    db,
    `SELECT role,active,joined_at AS joinedAt,revoked_at AS revokedAt,
      revoked_join_code AS revokedJoinCode
     FROM memberships WHERE group_id=? AND account_id=?`,
    groupId,
    accountId,
  );
}

async function activeMember(
  db: Database,
  groupId: string,
  accountId: string,
): Promise<Row | null> {
  return first<Row>(
    db,
    'SELECT role,joined_at AS joinedAt FROM memberships WHERE group_id=? AND account_id=? AND active=1',
    groupId,
    accountId,
  );
}

async function accessibleGoal(
  db: Database,
  goalId: string,
  accountId: string,
): Promise<Row | null> {
  return first<Row>(
    db,
    `SELECT g.id,g.owner_id AS ownerId,g.group_id AS groupId,g.visibility,
      g.kind,g.target_mode AS targetMode,g.title,g.unit,g.target,g.deadline,
      g.created_at AS createdAt
     FROM goals g
     WHERE g.id=? AND g.deleted_at IS NULL AND
       ((g.visibility='private' AND g.owner_id=?) OR
        (g.visibility='shared' AND EXISTS (
          SELECT 1 FROM memberships m
          WHERE m.group_id=g.group_id AND m.account_id=? AND m.active=1
        )))`,
    goalId,
    accountId,
    accountId,
  );
}

async function goalPayload(
  db: Database,
  goal: Row,
  accountId: string,
): Promise<Record<string, unknown>> {
  const progress = await all<Row>(
    db,
    `SELECT id,goal_id AS goalId,actor_id AS actorId,amount,title,note,url,
      occurred_at AS occurredAt,created_at AS createdAt
     FROM progress WHERE goal_id=? AND deleted_at IS NULL ORDER BY occurred_at ASC`,
    goal.id,
  );
  const items = await all<Row>(
    db,
    `SELECT id,goal_id AS goalId,title,explanation,created_at AS createdAt
     FROM checklist_items WHERE goal_id=? AND deleted_at IS NULL ORDER BY created_at ASC`,
    goal.id,
  );
  const checks = await all<Row>(
    db,
    `SELECT cc.item_id AS itemId,cc.actor_id AS actorId,cc.checked,
      cc.changed_at AS changedAt
     FROM checklist_checks cc
     JOIN checklist_items i ON i.id=cc.item_id AND i.deleted_at IS NULL
     WHERE i.goal_id=?`,
    goal.id,
  );

  let total = 0;
  const individualTotals: Record<string, number> = {};
  if (goal.kind === 'quantity') {
    for (const entry of progress) {
      const actor = String(entry.actorId);
      const amount = Number(entry.amount);
      individualTotals[actor] = (individualTotals[actor] ?? 0) + amount;
      if (goal.targetMode === 'shared_total' || actor === accountId) {
        total += amount;
      }
    }
  } else {
    const checkedItems = new Set<string>();
    const mine = new Set<string>();
    for (const check of checks) {
      if (Number(check.checked) !== 1) continue;
      const itemId = String(check.itemId);
      checkedItems.add(itemId);
      if (String(check.actorId) === accountId) mine.add(itemId);
    }
    total = (goal.targetMode === 'shared_total' ? checkedItems : mine).size;
    for (const check of checks) {
      if (Number(check.checked) !== 1) continue;
      const actor = String(check.actorId);
      const itemId = String(check.itemId);
      // Individual checklist totals count each item once per actor, even if
      // the client repeats the check request.
      individualTotals[actor] =
        (individualTotals[actor] ?? 0) +
        (checks.some(
          (candidate) =>
            String(candidate.actorId) === actor &&
            String(candidate.itemId) === itemId &&
            Number(candidate.checked) === 1,
        )
          ? 0
          : 0);
    }
    for (const actor of new Set(checks.map((check) => String(check.actorId)))) {
      individualTotals[actor] = new Set(
        checks
          .filter(
            (check) =>
              String(check.actorId) === actor && Number(check.checked) === 1,
          )
          .map((check) => String(check.itemId)),
      ).size;
    }
  }

  return {
    goal,
    progress,
    items,
    checks,
    total,
    individualTotals,
    checklistTotals:
      goal.kind === 'checklist'
        ? { total, itemCount: items.length }
        : null,
    state: 'online',
    serverTime: now(),
  };
}

function groupSelect() {
  return `SELECT g.id,g.name,g.join_code AS joinCode,g.owner_id AS ownerId,
    g.created_at AS createdAt,m.role,m.joined_at AS joinedAt,
    (SELECT COUNT(*) FROM memberships activeMembers
      WHERE activeMembers.group_id=g.id AND activeMembers.active=1) AS memberCount
    FROM groups g JOIN memberships m ON m.group_id=g.id
    WHERE m.account_id=? AND m.active=1 ORDER BY g.created_at DESC`;
}

/**
 * Create the Worker-shaped app. Calling this with no test verifier activates
 * the Better Auth/D1 path. The optional verifier exists solely to keep domain
 * integration tests independent from password fixtures and provider setup.
 */
export function createApp(
  options: AppOptions | SessionVerifier = {},
) {
  const app = new Hono<AppEnv>();
  const testVerifier =
    typeof options === 'function' ? options : options.sessionVerifier;

  app.get('/health', (c) => {
    const googleConfigured =
      text(c.env?.GOOGLE_CLIENT_ID) !== '' &&
      text(c.env?.GOOGLE_CLIENT_SECRET) !== '';
    return c.json({
      ok: true,
      auth: testVerifier
        ? 'test_adapter'
        : betterAuthConfigured(c.env)
          ? 'better_auth'
          : 'setup_needed',
      google: googleConfigured ? 'configured' : 'setup_needed',
    });
  });

  const authHandler = async (c: AppContext) => {
    const auth = createBetterAuth(c.env);
    if (!auth) return c.json(setupNeeded, 503);
    try {
      return await auth.handler(c.req.raw);
    } catch {
      return c.json({ error: 'auth_unavailable' }, 503);
    }
  };
  app.all('/api/auth', authHandler);
  app.all('/api/auth/*', authHandler);

  app.use('/api/*', async (c, next) => {
    // Better Auth routes above own their session/cookie lifecycle.
    if (c.req.path === '/api/auth' || c.req.path.startsWith('/api/auth/')) {
      await next();
      return;
    }
    if (!testVerifier && !betterAuthConfigured(c.env)) {
      return c.json(setupNeeded, 503);
    }
    let identity: Identity | null;
    try {
      identity = testVerifier
        ? await testVerifier(c.req.raw, c.env)
        : await verifyBetterAuthSession(c.req.raw, c.env);
    } catch {
      return c.json({ error: 'auth_unavailable' }, 503);
    }
    if (!identity?.accountId) return c.json({ error: 'unauthorized' }, 401);
    c.set('actor', identity.accountId);
    c.set('actorEmail', identity.email ?? null);
    c.set('actorName', identity.name ?? null);
    await run(
      c.env.DB,
      'INSERT OR IGNORE INTO accounts(id,created_at) VALUES(?,?)',
      identity.accountId,
      now(),
    );
    await next();
  });

  app.get('/api/session', (c) =>
    c.json({
      accountId: c.get('actor'),
      email: c.get('actorEmail'),
      name: c.get('actorName'),
      state: 'online',
    }),
  );

  app.get('/api/groups', async (c) =>
    c.json({ groups: await all(c.env.DB, groupSelect(), c.get('actor')) }),
  );

  app.post('/api/groups', async (c) => {
    const body = await readBody(c);
    const name = boundedString(body?.name, 100, true);
    if (!body || name === null) return c.json({ error: 'invalid_name' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const groupId = id();
    const joinCode = randomJoinCode();
    const createdAt = now();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: groupId,
      name,
      joinCode,
      role: 'owner',
      memberCount: 1,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      201,
      [
        {
          sql: `INSERT INTO groups(id,name,join_code,owner_id,created_at)
            SELECT ?,?,?,?,? WHERE ${reserve}`,
          args: [groupId, name, joinCode, actorId, createdAt, ...args],
        },
        {
          sql: `INSERT INTO memberships(group_id,account_id,role,joined_at)
            SELECT ?,?,?,? WHERE ${reserve}`,
          args: [groupId, actorId, 'owner', createdAt, ...args],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.get('/api/groups/:id/members', async (c) => {
    const groupId = c.req.param('id');
    if (!(await activeMember(c.env.DB, groupId, c.get('actor')))) {
      return c.json({ error: 'not_found' }, 404);
    }
    return c.json({
      members: await all(
        c.env.DB,
        `SELECT account_id AS accountId,role,active,joined_at AS joinedAt,
          revoked_at AS revokedAt
         FROM memberships WHERE group_id=? ORDER BY joined_at ASC`,
        groupId,
      ),
      state: 'online',
    });
  });

  app.post('/api/groups/join', async (c) => {
    const body = await readBody(c);
    const code = validJoinCode(body?.code);
    if (!body || !code) return c.json({ error: 'invalid_code' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const group = await first<Row>(
      c.env.DB,
      'SELECT id,name,join_code AS joinCode FROM groups WHERE join_code=?',
      code,
    );
    if (!group) return c.json({ error: 'invalid_code' }, 404);
    const actorId = c.get('actor');
    const previous = await member(c.env.DB, String(group.id), actorId);
    if (
      previous &&
      Number(previous.active) !== 1 &&
      previous.revokedAt &&
      previous.revokedJoinCode === group.joinCode
    ) {
      return c.json({ error: 'membership_revoked' }, 403);
    }
    const joinedAt = now();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: group.id,
      name: group.name,
      role: previous?.role === 'owner' ? 'owner' : 'member',
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      200,
      [
        {
          sql: `INSERT INTO memberships
              (group_id,account_id,role,active,joined_at)
            SELECT ?,?,'member',1,?
            WHERE ${reserve}
              AND EXISTS (
                SELECT 1 FROM groups currentGroup
                WHERE currentGroup.id=? AND currentGroup.join_code=?
              )
            ON CONFLICT(group_id,account_id) DO UPDATE SET
              active=1,joined_at=?,revoked_at=NULL,revoked_join_code=NULL
            WHERE ${reserve}
              AND memberships.role='member'
              AND (memberships.revoked_at IS NULL OR memberships.revoked_join_code<>?)
              AND EXISTS (
                SELECT 1 FROM groups currentGroup
                WHERE currentGroup.id=? AND currentGroup.join_code=?
              )`,
          args: [
            group.id,
            actorId,
            joinedAt,
            ...args,
            group.id,
            group.joinCode,
            joinedAt,
            ...args,
            group.joinCode,
            group.id,
            group.joinCode,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.post('/api/groups/:id/leave', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const groupId = c.req.param('id');
    const actorId = c.get('actor');
    const current = await activeMember(c.env.DB, groupId, actorId);
    if (!current) return c.json({ error: 'forbidden' }, 403);
    if (current.role === 'owner') {
      return c.json({ error: 'owner_cannot_leave' }, 409);
    }
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { state: 'left' },
      200,
      [
        {
          sql: `UPDATE memberships SET active=0,revoked_at=NULL,revoked_join_code=NULL
            WHERE group_id=? AND account_id=? AND role='member' AND active=1 AND ${reserve}`,
          args: [groupId, actorId, ...args],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.post('/api/groups/:id/revoke/:account', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const groupId = c.req.param('id');
    const target = boundedString(c.req.param('account'), 128, true);
    if (!target) return c.json({ error: 'invalid_account' }, 400);
    const actorId = c.get('actor');
    const owner = await activeMember(c.env.DB, groupId, actorId);
    if (!owner || owner.role !== 'owner') {
      return c.json({ error: 'forbidden' }, 403);
    }
    if (target === actorId) {
      return c.json({ error: 'owner_cannot_revoke_self' }, 409);
    }
    const group = await first<Row>(
      c.env.DB,
      'SELECT join_code AS joinCode FROM groups WHERE id=?',
      groupId,
    );
    if (!group) return c.json({ error: 'not_found' }, 404);
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { state: 'revoked', accountId: target },
      200,
      [
        {
          sql: `UPDATE memberships SET active=0,revoked_at=?,revoked_join_code=?
            WHERE group_id=? AND account_id=? AND role='member' AND ${reserve}
              AND EXISTS (
                SELECT 1 FROM memberships ownerMembership
                WHERE ownerMembership.group_id=? AND ownerMembership.account_id=?
                  AND ownerMembership.role='owner' AND ownerMembership.active=1
              )`,
          args: [now(), group.joinCode, groupId, target, ...args, groupId, actorId],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.post('/api/groups/:id/invite/revoke', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const groupId = c.req.param('id');
    const actorId = c.get('actor');
    const owner = await activeMember(c.env.DB, groupId, actorId);
    if (!owner || owner.role !== 'owner') {
      return c.json({ error: 'forbidden' }, 403);
    }
    const newCode = randomJoinCode();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { state: 'invite_revoked', joinCode: newCode },
      200,
      [
        {
          sql: `UPDATE groups SET join_code=? WHERE id=? AND ${reserve}
            AND EXISTS (
              SELECT 1 FROM memberships m
              WHERE m.group_id=groups.id AND m.account_id=?
                AND m.role='owner' AND m.active=1
            )`,
          args: [newCode, groupId, ...args, actorId],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.get('/api/goals', async (c) => {
    const actorId = c.get('actor');
    const goals = await all<Row>(
      c.env.DB,
      `SELECT g.id,g.owner_id AS ownerId,g.group_id AS groupId,g.visibility,
        g.kind,g.target_mode AS targetMode,g.title,g.unit,g.target,g.deadline,
        g.created_at AS createdAt
       FROM goals g WHERE g.deleted_at IS NULL AND
       ((g.visibility='private' AND g.owner_id=?) OR
        (g.visibility='shared' AND EXISTS (
          SELECT 1 FROM memberships m
          WHERE m.group_id=g.group_id AND m.account_id=? AND m.active=1
        ))) ORDER BY g.deadline ASC,g.created_at DESC`,
      actorId,
      actorId,
    );
    return c.json({ goals, state: 'online' });
  });

  app.post('/api/goals', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_goal' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const title = boundedString(body.title, 160, true);
    const unit = boundedString(body.unit, 40, false);
    const deadline = calendarDate(body.deadline);
    const target = positiveInteger(body.target);
    const visibility = body.visibility === 'private' || body.visibility === 'shared'
      ? body.visibility
      : null;
    const kind = body.kind === 'quantity' || body.kind === 'checklist'
      ? body.kind
      : null;
    const targetMode = body.targetMode === 'shared_total' || body.targetMode === 'individual'
      ? body.targetMode
      : null;
    const groupId = visibility === 'shared'
      ? boundedString(body.groupId, 128, true)
      : '';
    if (
      title === null ||
      unit === null ||
      !deadline ||
      !target ||
      !visibility ||
      !kind ||
      !targetMode ||
      (kind === 'quantity' && unit.length === 0) ||
      (kind === 'checklist' && unit.length > 0) ||
      (visibility === 'private' && targetMode !== 'individual') ||
      (visibility === 'shared' && !groupId)
    ) {
      return c.json({ error: 'invalid_goal' }, 400);
    }
    const actorId = c.get('actor');
    if (
      visibility === 'shared' &&
      !(await activeMember(c.env.DB, groupId!, actorId))
    ) {
      return c.json({ error: 'forbidden' }, 403);
    }
    const goalId = id();
    const createdAt = now();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: goalId,
      ownerId: actorId,
      groupId: visibility === 'shared' ? groupId : null,
      visibility,
      kind,
      targetMode,
      title,
      unit: kind === 'quantity' ? unit : '',
      target,
      deadline,
      state: 'online',
    };
    const access = visibility === 'private'
      ? '1=1'
      : `EXISTS (SELECT 1 FROM memberships m WHERE m.group_id=? AND m.account_id=? AND m.active=1)`;
    const accessArgs = visibility === 'private' ? [] : [groupId, actorId];
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      201,
      [
        {
          sql: `INSERT INTO goals
            (id,owner_id,group_id,visibility,kind,target_mode,title,unit,target,deadline,created_at)
            SELECT ?,?,?,?,?,?,?,?,?,?,? WHERE ${reserve} AND ${access}`,
          args: [
            goalId,
            actorId,
            visibility === 'shared' ? groupId : null,
            visibility,
            kind,
            targetMode,
            title,
            kind === 'quantity' ? unit : '',
            target,
            deadline,
            createdAt,
            ...args,
            ...accessArgs,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.get('/api/goals/:id', async (c) => {
    const goal = await accessibleGoal(
      c.env.DB,
      c.req.param('id'),
      c.get('actor'),
    );
    if (!goal) return c.json({ error: 'not_found' }, 404);
    return c.json(await goalPayload(c.env.DB, goal, c.get('actor')));
  });

  app.patch('/api/goals/:id', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_goal_update' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const current = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!current || current.ownerId !== actorId) {
      return c.json({ error: current ? 'forbidden' : 'not_found' }, current ? 403 : 404);
    }
    const title = body.title === undefined
      ? String(current.title)
      : boundedString(body.title, 160, true);
    const unit = body.unit === undefined
      ? String(current.unit)
      : boundedString(body.unit, 40, false);
    const deadline = body.deadline === undefined
      ? String(current.deadline)
      : calendarDate(body.deadline);
    const target = body.target === undefined
      ? Number(current.target)
      : positiveInteger(body.target);
    if (
      title === null ||
      unit === null ||
      !deadline ||
      !target ||
      (current.kind === 'quantity' && unit.length === 0) ||
      (current.kind === 'checklist' && unit.length > 0)
    ) {
      return c.json({ error: 'invalid_goal_update' }, 400);
    }
    const binding = {
      method: 'PATCH',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      ...current,
      title,
      unit,
      target,
      deadline,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      200,
      [
        {
          sql: `UPDATE goals SET title=?,unit=?,target=?,deadline=?
            WHERE id=? AND deleted_at IS NULL AND owner_id=? AND ${reserve}
              AND (visibility='private' OR EXISTS (
                SELECT 1 FROM memberships m WHERE m.group_id=goals.group_id
                  AND m.account_id=? AND m.active=1
              ))`,
          args: [
            title,
            unit,
            target,
            deadline,
            current.id,
            actorId,
            ...args,
            actorId,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.delete('/api/goals/:id', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const current = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!current || current.ownerId !== actorId) {
      return c.json({ error: current ? 'forbidden' : 'not_found' }, current ? 403 : 404);
    }
    const binding = {
      method: 'DELETE',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { id: current.id, state: 'deleted' },
      200,
      [
        {
          sql: `UPDATE goals SET deleted_at=? WHERE id=? AND owner_id=? AND ${reserve}`,
          args: [now(), current.id, actorId, ...args],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.post('/api/goals/:id/progress', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_progress' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    if (goal.kind !== 'quantity') return c.json({ error: 'wrong_kind' }, 409);
    const amount = positiveInteger(body.amount);
    const title = boundedString(body.title, 160, false);
    const note = boundedString(body.note, 2000, false);
    const url = boundedString(body.url, 2048, false);
    if (!amount || title === null || note === null || url === null || !validUrl(url)) {
      return c.json({ error: 'invalid_progress' }, 400);
    }
    const entryId = id();
    const at = now();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: entryId,
      goalId: goal.id,
      actorId,
      amount,
      title: title || null,
      note: note || null,
      url: url || null,
      occurredAt: at,
      createdAt: at,
      state: 'online',
    };
    const access = `(g.visibility='private' AND g.owner_id=?) OR
      (g.visibility='shared' AND EXISTS (
        SELECT 1 FROM memberships m WHERE m.group_id=g.group_id
          AND m.account_id=? AND m.active=1
      ))`;
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      201,
      [
        {
          sql: `INSERT INTO progress
            (id,goal_id,actor_id,amount,title,note,url,occurred_at,created_at)
            SELECT ?,?,?,?,?,?,?,?,? WHERE ${reserve}
              AND EXISTS (
                SELECT 1 FROM goals g WHERE g.id=? AND g.deleted_at IS NULL
                  AND g.kind='quantity' AND (${access})
              )`,
          args: [
            entryId,
            goal.id,
            actorId,
            amount,
            title || null,
            note || null,
            url || null,
            at,
            at,
            ...args,
            goal.id,
            actorId,
            actorId,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.patch('/api/goals/:id/progress/:entry', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_progress' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    const current = await first<Row>(
      c.env.DB,
      `SELECT id,amount,title,note,url,occurred_at AS occurredAt,created_at AS createdAt
       FROM progress WHERE id=? AND goal_id=? AND actor_id=? AND deleted_at IS NULL`,
      c.req.param('entry'),
      goal.id,
      actorId,
    );
    if (!current) return c.json({ error: 'forbidden' }, 403);
    const amount = positiveInteger(body.amount);
    const title = boundedString(body.title, 160, false);
    const note = boundedString(body.note, 2000, false);
    const url = boundedString(body.url, 2048, false);
    if (!amount || title === null || note === null || url === null || !validUrl(url)) {
      return c.json({ error: 'invalid_progress' }, 400);
    }
    const binding = {
      method: 'PATCH',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: current.id,
      goalId: goal.id,
      actorId,
      amount,
      title: title || null,
      note: note || null,
      url: url || null,
      occurredAt: current.occurredAt,
      createdAt: current.createdAt,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      200,
      [
        {
          sql: `UPDATE progress SET amount=?,title=?,note=?,url=?
            WHERE id=? AND goal_id=? AND actor_id=? AND deleted_at IS NULL AND ${reserve}
              AND EXISTS (
                SELECT 1 FROM goals g WHERE g.id=progress.goal_id AND
                  (g.visibility='private' AND g.owner_id=? OR
                   g.visibility='shared' AND EXISTS (
                     SELECT 1 FROM memberships m WHERE m.group_id=g.group_id
                       AND m.account_id=? AND m.active=1
                   ))
              )`,
          args: [
            amount,
            title || null,
            note || null,
            url || null,
            current.id,
            goal.id,
            actorId,
            ...args,
            actorId,
            actorId,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.delete('/api/goals/:id/progress/:entry', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    const current = await first<Row>(
      c.env.DB,
      'SELECT id FROM progress WHERE id=? AND goal_id=? AND actor_id=? AND deleted_at IS NULL',
      c.req.param('entry'),
      goal.id,
      actorId,
    );
    if (!current) return c.json({ error: 'forbidden' }, 403);
    const binding = {
      method: 'DELETE',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { id: current.id, state: 'deleted' },
      200,
      [
        {
          sql: `UPDATE progress SET deleted_at=?
            WHERE id=? AND goal_id=? AND actor_id=? AND deleted_at IS NULL AND ${reserve}
              AND EXISTS (
                SELECT 1 FROM goals g WHERE g.id=progress.goal_id AND g.deleted_at IS NULL
                  AND (g.visibility='private' AND g.owner_id=? OR
                    g.visibility='shared' AND EXISTS (
                      SELECT 1 FROM memberships m WHERE m.group_id=g.group_id
                        AND m.account_id=? AND m.active=1
                    ))
              )`,
          args: [now(), current.id, goal.id, actorId, ...args, actorId, actorId],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.post('/api/goals/:id/items', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_item' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    if (goal.kind !== 'checklist' || goal.ownerId !== actorId) {
      return c.json({ error: 'forbidden' }, 403);
    }
    const title = boundedString(body.title, 160, true);
    const explanation = boundedString(body.explanation, 1000, false);
    if (title === null || explanation === null) {
      return c.json({ error: 'invalid_item' }, 400);
    }
    const itemId = id();
    const createdAt = now();
    const binding = {
      method: 'POST',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: itemId,
      goalId: goal.id,
      title,
      explanation: explanation || null,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      201,
      [
        {
          sql: `INSERT INTO checklist_items(id,goal_id,title,explanation,created_at)
            SELECT ?,?,?,?,? WHERE ${reserve}
              AND EXISTS (SELECT 1 FROM goals WHERE id=? AND owner_id=? AND deleted_at IS NULL)`,
          args: [
            itemId,
            goal.id,
            title,
            explanation || null,
            createdAt,
            ...args,
            goal.id,
            actorId,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.patch('/api/goals/:id/items/:item', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body) return c.json({ error: 'invalid_item' }, 400);
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    if (goal.kind !== 'checklist' || goal.ownerId !== actorId) {
      return c.json({ error: 'forbidden' }, 403);
    }
    const current = await first<Row>(
      c.env.DB,
      `SELECT id,title,explanation FROM checklist_items
       WHERE id=? AND goal_id=? AND deleted_at IS NULL`,
      c.req.param('item'),
      goal.id,
    );
    if (!current) return c.json({ error: 'not_found' }, 404);
    const title = body.title === undefined
      ? String(current.title)
      : boundedString(body.title, 160, true);
    const explanation = body.explanation === undefined
      ? String(current.explanation ?? '')
      : boundedString(body.explanation, 1000, false);
    if (title === null || explanation === null) {
      return c.json({ error: 'invalid_item' }, 400);
    }
    const binding = {
      method: 'PATCH',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      id: current.id,
      goalId: goal.id,
      title,
      explanation: explanation || null,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      200,
      [
        {
          sql: `UPDATE checklist_items SET title=?,explanation=?
            WHERE id=? AND goal_id=? AND deleted_at IS NULL AND ${reserve}`,
          args: [title, explanation || null, current.id, goal.id, ...args],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.delete('/api/goals/:id/items/:item', async (c) => {
    const body = (await readBody(c)) ?? {};
    if (!isRecord(body)) return c.json({ error: 'invalid_body' }, 400);
    const key = c.req.header('Idempotency-Key');
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    if (goal.kind !== 'checklist' || goal.ownerId !== actorId) {
      return c.json({ error: 'forbidden' }, 403);
    }
    const current = await first<Row>(
      c.env.DB,
      'SELECT id FROM checklist_items WHERE id=? AND goal_id=? AND deleted_at IS NULL',
      c.req.param('item'),
      goal.id,
    );
    if (!current) return c.json({ error: 'not_found' }, 404);
    const binding = {
      method: 'DELETE',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const result = await idempotentMutation(
      c,
      key,
      body,
      { id: current.id, state: 'deleted' },
      200,
      [
        {
          sql: `UPDATE checklist_items SET deleted_at=?
            WHERE id=? AND goal_id=? AND deleted_at IS NULL AND ${reserve}`,
          args: [now(), current.id, goal.id, ...args],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  app.put('/api/goals/:id/items/:item/check', async (c) => {
    const body = await readBody(c);
    const key = c.req.header('Idempotency-Key');
    if (!body || typeof body.checked !== 'boolean') {
      return c.json({ error: 'invalid_check' }, 400);
    }
    if (!validIdempotencyKey(key)) {
      return c.json(
        { error: key === undefined ? 'idempotency_key_required' : 'idempotency_key_invalid' },
        400,
      );
    }
    const actorId = c.get('actor');
    const goal = await accessibleGoal(c.env.DB, c.req.param('id'), actorId);
    if (!goal) return c.json({ error: 'not_found' }, 404);
    if (goal.kind !== 'checklist') return c.json({ error: 'wrong_kind' }, 409);
    const item = await first<Row>(
      c.env.DB,
      `SELECT i.id FROM checklist_items i
       WHERE i.id=? AND i.goal_id=? AND i.deleted_at IS NULL`,
      c.req.param('item'),
      goal.id,
    );
    if (!item) return c.json({ error: 'not_found' }, 404);
    const at = now();
    const binding = {
      method: 'PUT',
      path: new URL(c.req.url).pathname,
      bodyHash: await sha256(stableJson(body)),
    };
    const reserve = reservationPredicate(binding);
    const args = reservationArgs(actorId, key, binding);
    const response = {
      itemId: item.id,
      actorId,
      checked: body.checked,
      changedAt: at,
      state: 'online',
    };
    const result = await idempotentMutation(
      c,
      key,
      body,
      response,
      200,
      [
        {
          sql: `INSERT INTO checklist_checks(item_id,actor_id,checked,changed_at)
            SELECT ?,?,?,? WHERE ${reserve}
              AND EXISTS (
                SELECT 1 FROM checklist_items i
                JOIN goals g ON g.id=i.goal_id
                WHERE i.id=? AND i.goal_id=? AND i.deleted_at IS NULL
                  AND g.deleted_at IS NULL AND g.kind='checklist'
                  AND (g.visibility='private' AND g.owner_id=? OR
                    g.visibility='shared' AND EXISTS (
                      SELECT 1 FROM memberships m WHERE m.group_id=g.group_id
                        AND m.account_id=? AND m.active=1
                    ))
              )
            ON CONFLICT(item_id,actor_id) DO UPDATE SET
              checked=excluded.checked,changed_at=excluded.changed_at
            WHERE ${reserve}
              AND EXISTS (
                SELECT 1 FROM checklist_items i
                JOIN goals g ON g.id=i.goal_id
                WHERE i.id=? AND i.goal_id=? AND i.deleted_at IS NULL
                  AND g.deleted_at IS NULL AND g.kind='checklist'
                  AND (g.visibility='private' AND g.owner_id=? OR
                    g.visibility='shared' AND EXISTS (
                      SELECT 1 FROM memberships m WHERE m.group_id=g.group_id
                        AND m.account_id=? AND m.active=1
                    ))
              )`,
          args: [
            item.id,
            actorId,
            body.checked ? 1 : 0,
            at,
            ...args,
            item.id,
            goal.id,
            actorId,
            actorId,
            ...args,
            item.id,
            goal.id,
            actorId,
            actorId,
          ],
        },
      ],
    );
    return sendMutationResult(c, result);
  });

  return app;
}

export default createApp();
