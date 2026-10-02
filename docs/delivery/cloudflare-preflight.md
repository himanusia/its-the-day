# Cloudflare online + extension preflight

Status: PASS for bounded implementation, deployment gated by reviewed source and readback.
Decided by: repository owner, latest instruction authorizes himanusia.com subdomain and continuing all work. Supersedes prior no-deploy policy for this product, not unrelated resources.

Parent #6; deployment #11; extension #12. Branch feat/cloudflare-online-extension from merged main ae49f5e. Preserve atomic commits and merge commit after independent review/local gates; existing repository has no remote CI. Same-account delivery exception follows the established owner-authorized workflow. Do not invent CI proof.

## Outcome and ownership

1. Serve existing Flutter web and Worker API under its-the-day.himanusia.com (after collision checks), authoritative remote D1, HTTPS same-origin cookies, native HTTPS bearer flow. No localhost dependency for core account/group/quantity flows.
2. Installable MV3 companion with original local branding and explicit opening of the hosted app. Not an embedded full Flutter popup, not fake synced totals, not Web Store publication. Parent disposable-profile QA only; personal Chrome remains off-limits.
3. Rebuild/verify on emulator, then install configured HTTPS Android APK on connected authorized physical device. Preserve app data.
4. Supplied Android OAuth client is not substituted for Web OAuth credentials. Google stays honest setup-needed until secure Web credentials are supplied; email auth can ship independently.

Engineer lane writes only server/ (including pinned Wrangler/config/security/runtime tests/runbook). Extension lane writes only extension/. Parent owns docs, Flutter builds, Git, operational credentials/provision/deploy, cross-lane review and verification. No workers access private files or mutate remote resources.

## Target and credential discovery

Owned zone himanusia.com confirmed active via token-authenticated API. Environment account ID was a mismatched target; resolve deployment account from the owned zone's account in memory and pass explicitly to isolated ops commands. Same token successfully lists Workers scripts, D1 and Worker custom domains on resolved account. No existing its-the-day Worker/database/custom-domain detected. DNS-record list is denied by token; use public DNS checks and fail closed on custom-domain collision, never override an existing record. No legacy global-key fallback.

## Guards, acceptance and rollback

- New isolated D1 only; apply checked-in migrations, no QA/local DB upload.
- Better Auth secret generated privately and stored in Worker secrets; never print/persist credentials in repo or artifacts.
- Same-origin web/API, strict unknown /api and unknown document routes, static assets served through ASSETS; do not respond with HTML for missing API routes.
- Production CF trusted client-IP/rate control, no insecure fake provider success, auth errors/logs redacted. Cookie/bearer authorization tested with two accounts and revocation/idempotency.
- Pin Wrangler and deploy configuration; observability and rollback documented; avoid log retention of sensitive request bodies/tokens.
- Local Flutter/server gates, dry-run build and independent exact-source review before publishing; after deployment read version/bindings names, DNS/HTTPS, health, auth/group/quantity and browser-cookie flows. Build success alone is not live readiness.
- APK tested in emulator before physical install. Extension validated and exercised in disposable headless Chromium; unpacked ZIP/path is not Web Store publication or personal-profile installation.
- Release is a bounded early-access core checkpoint, not full product readiness. Existing version remains checkpoint-unreleased unless owner release policy is applied through changelog/tag step. No store publication.
- Roll back only this new Worker to its verified prior version; DB never destructively rolled back. For first deployment, stop public routing only with explicit owner trigger if a blocker cannot be resolved. No unrelated resource changes.

Remaining #6 alarm/notification/realtime/offline outbox/checklist/edit-delete/provider/physical-matrix gates remain visible; this preflight does not declare them completed.
