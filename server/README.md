# Online groups API

This Worker-shaped Hono service is the authoritative boundary for online accounts, groups, and shared goals. Better Auth owns account, session, credential, and verification records in D1. The application owns groups, memberships, goals, progress, checklist state, and idempotency records. There are no demo-user or bearer-string production routes.

## Local deterministic gates

```bash
npm install --include=dev
npm run typecheck
npm test
```

The tests use Node's in-memory SQLite adapter with the Cloudflare D1 `prepare`/`all`/`batch`/`exec` surface. They exercise real Better Auth email/password sign-up, sign-in, bearer-session lookup, sign-out, two-account membership authorization, private access, revocation, revoked-code rejoin blocking, concurrent idempotent progress, request binding conflicts, strict date/URL validation, individual totals, shared totals, and checklist toggling.

## Better Auth runtime

The default `createApp()` path creates Better Auth from the request's Worker bindings. It fails closed with `setup_needed` unless all of the following are present:

- `DB`: a real D1 binding (including `batch()` and `exec()`);
- `BETTER_AUTH_SECRET`: a locally supplied secret of at least 32 characters; never commit or print it;
- optionally `BETTER_AUTH_URL`, which should be the exact API origin in deployed environments;
- optionally `BETTER_AUTH_TRUSTED_ORIGINS`, a comma-separated list for explicitly allowed browser origins.

Auth routes are mounted at `/api/auth/*`. Email/password routes are supplied by Better Auth. Native clients use Better Auth's `bearer()` plugin and the `set-auth-token` response header; browsers use the normal Better Auth cookie. Passwords are sent from the app's sign-up/sign-in form and are never stored by the groups API code.

Google is optional. Set both `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` out of band to enable it. If either value is absent, `/health` reports `google: setup_needed`; no provider secret is fabricated.

The checked-in migrations include the Better Auth core tables and application tables:

```bash
npx wrangler d1 migrations apply its-the-day-groups --local
# Use the same command with the configured remote D1 target only after operator setup.
```

`wrangler.jsonc` enables `nodejs_compat`, which Better Auth requires for Cloudflare Workers. Schema ownership is explicit in `migrations/0001_groups.sql` and the additive hardening changes in `migrations/0002_online_hardening.sql`.

## API and idempotency contract

- `GET /api/session`, `GET /api/groups`, `GET /api/groups/:id/members`, and `GET /api/goals`/`:id` require an active Better Auth session.
- Groups support create, join, leave, member listing, owner revocation, and invite-code rotation at `/api/groups/:id/invite/revoke`.
- Goals support private/shared quantity and checklist creation, update, soft deletion, progress entry add/update/delete, checklist item add/update/delete, and per-member check/uncheck.
- Shared goals require an active membership on every read and mutation. Private goals are owner-only. A revoked member cannot rejoin with the join code that was current at revocation; the owner must rotate the invite first.
- Every state-changing route requires an `Idempotency-Key` of 1–128 visible ASCII characters. The database reservation binds actor, method, path, and canonical request-body hash. D1 `batch()` atomically reserves the key, performs the mutation only while that reservation is pending, and stores the response. Concurrent duplicate requests therefore cannot double count. Reusing a key for a different request returns `409 idempotency_key_conflict`.
- Dates are strict `YYYY-MM-DD` calendar dates, including leap-day validation. Optional URLs require `http`/`https`, a non-empty host, no whitespace, and no userinfo.
- Checklist `total` is the number of unique checked items for `shared_total`, or the current actor's checked items for `individual`; repeated checks do not inflate totals.

## Flutter client configuration

The existing home wiring uses the exact build-time identifier `GROUPS_API_URL`:

```bash
flutter run --dart-define=GROUPS_API_URL=http://127.0.0.1:8787
```

For a same-origin web deployment, the client may use an empty/relative API base and Better Auth cookies. Native builds must use an HTTPS API URL and secure session-token storage. Provider setup and deployment bindings remain operator-owned.

## Remaining operational setup

Configure a real D1 database ID, a secret through the Worker secret store, trusted web origins, optional Google credentials, HTTPS/custom domain, rate limiting/IP forwarding, logging/redaction, migration backup/restore, and deployment/rollback observability before production release. Local D1-shaped tests prove the auth/API contract; they do not prove a deployed Worker or provider configuration.
