# Cloudflare online runbook

This runbook is for the owner/ops lane. The server implementation does not provision Cloudflare resources, create DNS, upload credentials, apply remote migrations, or deploy. Do not paste secret values into chat, logs, shell history, this repository, or test fixtures.

## Target and bounded behavior

- Worker name: `its-the-day-groups`.
- Custom Domain: `its-the-day.himanusia.com`.
- Static Assets directory: `../build/web`, built by the parent Flutter lane.
- D1 binding: `DB`, database name `its-the-day-groups`; its verified new remote ID is checked into `wrangler.jsonc`. No local QA data is uploaded.
- Rate-limit binding: `AUTH_RATE_LIMITER`, configured for 10 calls per 60 seconds; namespace `20491002` was verified unused across all 19 existing Worker bindings in the target account.
- Production nonsecret variables are checked in as `BETTER_AUTH_URL=https://its-the-day.himanusia.com` and `BETTER_AUTH_TRUSTED_ORIGINS=https://its-the-day.himanusia.com`.
- Static routing is intentionally strict: `/api` and unknown `/api/*` remain Worker 404s; a non-API 404 is delegated to `ASSETS`; `not_found_handling=404-page` prevents missing files from becoming `index.html`.
- The Worker keeps the existing Better Auth routes, native bearer transport, browser cookie transport, groups, and shared-goal API contracts. Alarms, notifications, realtime, offline outbox, and Google provider setup are outside this slice.

## Local gates and dry run

Run from `server/` after the parent has produced `../build/web`:

```bash
npm ci --include=dev
npm run typecheck
npm test
npm exec -- wrangler deploy --dry-run
```

The dry run must report Wrangler `4.146.0`, read the Flutter asset directory, and show `DB`, `AUTH_RATE_LIMITER`, `ASSETS`, `BETTER_AUTH_URL`, and `BETTER_AUTH_TRUSTED_ORIGINS` bindings/variables. A dry run is not a deployment or proof that D1, the custom domain, DNS, secrets, or the rate-limit namespace exist remotely.

## Migration sequence

1. Owner verifies the target account from the owned zone and resolves the actual remote D1 ID. Do not use the stale account ID or upload the local `.wrangler` database.
2. Apply checked-in migrations to local D1 when exercising the Worker locally:

   ```bash
   npm exec -- wrangler d1 migrations apply its-the-day-groups --local
   ```

3. Before the first remote apply, take the owner-approved D1 backup/export and confirm the migration list against the new empty database. Apply only the checked-in migrations:

   ```bash
   npm exec -- wrangler d1 migrations apply its-the-day-groups --remote
   ```

4. Read back migration status and binding names. Never destructively roll back D1 to undo a Worker release; use a forward migration if a schema repair is required.

## Named secrets and optional Google setup

Only these names are expected; values are entered through Wrangler's interactive secret prompt or the approved secure operator path:

- `BETTER_AUTH_SECRET` — required, at least 32 characters, generated privately.
- `GOOGLE_CLIENT_ID` — optional web OAuth client ID.
- `GOOGLE_CLIENT_SECRET` — optional web OAuth client secret.

For optional Google login, configure both Google names or neither. The supplied Android OAuth client JSON is not a Web OAuth credential and must not be copied into this Worker or repository. If either Google name is absent, `/health` must continue to report `google: setup_needed`; email auth remains independent.

Owner-only secret commands (do not include values in command arguments or output):

```bash
npm exec -- wrangler secret put BETTER_AUTH_SECRET
# Optional, only after the Web OAuth client is separately verified:
npm exec -- wrangler secret put GOOGLE_CLIENT_ID
npm exec -- wrangler secret put GOOGLE_CLIENT_SECRET
npm exec -- wrangler secret list
```

The final command is a names/status check only. Never print, diff, export, or echo secret values. Cloudflare credentials such as `CLOUDFLARE_API_TOKEN` are operator-injected and are not Worker secrets or repository files.

## Pre-deploy checks

Before a first deployment, the owner must:

- verify the checked-in remote D1 ID still belongs to this new project database;
- verify the checked-in rate-limit namespace remains account-unique;
- confirm the custom domain is not already serving another resource and fail closed on a collision;
- confirm the intended account/token lane and binding names without printing credential values;
- confirm the migration apply and D1 readback;
- rerun `npm run typecheck`, `npm test`, and the dry run;
- confirm `../build/web` is the exact Flutter artifact intended for this Worker.

`CF-Connecting-IP` is the only client-IP input accepted for public auth. It is trustworthy when the request is received by the Cloudflare Worker edge. The Worker rejects missing/malformed values when `AUTH_RATE_LIMITER` is bound and never uses `X-Forwarded-For` or an isolate-local `Map`. Cloudflare rate-limit counters are bounded and location-local/eventually consistent; they are not an exact global abuse ledger.

## Owner deployment and readback

After the pre-deploy checks pass, the owner may run:

```bash
npm exec -- wrangler deploy
npm exec -- wrangler versions list
curl -fsS https://its-the-day.himanusia.com/health
curl -i https://its-the-day.himanusia.com/api/does-not-exist
curl -i https://its-the-day.himanusia.com/missing-asset.js
```

Expected readback:

- HTTPS serves the configured Worker/custom domain, not a provider default page.
- `/health` is healthy and reports Google `configured` only when both optional names are present; otherwise it reports `setup_needed`.
- `/api/does-not-exist` is a Worker 404 and does not contain Flutter HTML.
- A missing non-API asset is a 404 and does not silently return `index.html`.
- Browser auth uses the same-origin secure cookie; native clients use Better Auth's bearer token header. Do not put bearer tokens or passwords in curl history or logs.

Live auth/group/goal checks, DNS/custom-domain verification, D1 readback, and deployment version confirmation belong to the owner ops lane and are not claimed by local tests or this server-only change.

## Worker-only rollback

If the deployed Worker is unhealthy, record the current Worker version and use the owner-approved prior Worker version:

```bash
npm exec -- wrangler versions list
npm exec -- wrangler rollback <VERIFIED_PRIOR_VERSION_ID>
curl -fsS https://its-the-day.himanusia.com/health
```

Rollback only this Worker. Do not delete or roll back the D1 database, unrelated Workers, DNS, secrets, or the custom domain as part of a Worker rollback. For the first deployment, stopping public routing is an explicit owner decision when a blocker cannot be resolved; it is not an automatic cleanup step. After rollback, preserve the failing version/readback for review and use a forward source/config fix before the next deploy.
