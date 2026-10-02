# Cloudflare online checkpoint

## Delivered scope

- Public same-origin web/API: **https://its-the-day.himanusia.com**.
- Worker: `its-the-day-groups`; Cloudflare production Custom Domain readback matches the hostname and service.
- Deployed source reviewed at `ceeec890d23b10ce968363891a6b9cfb985bfc3a`.
- Worker version: `1bb6fe88-d66e-4801-9cfe-a620f780c2d3`, created `2026-10-02T06:42:59.782Z`.
- Real D1 binding `DB`, database `its-the-day-groups`, migrations `0001_groups.sql` and `0002_online_hardening.sql` applied remotely; subsequent migration list reports none pending. Schema readback verified auth/business tables, region APAC.
- Bindings read back: `DB`, `ASSETS`, `AUTH_RATE_LIMITER` namespace `20491002`, private `BETTER_AUTH_SECRET` name, and exact same-origin URL/trusted-origin variables. Secret values were generated/transmitted privately and never logged or committed.

Cloudflare deployment account was resolved from the owned zone. The stale environment account ID was not used; ops passed an isolated explicit account. Exact DNS collision check found no existing record for the selected hostname; public A answers were inherited from the zone wildcard before deployment. No unrelated resource was overwritten.

## Parent verification

| Evidence | Actual result | Bounds |
|---|---|---|
| Flutter analyze/default tests | Clean; 69 passed before deployment, opt-in runtime tests skipped | Default tests do not establish live readiness |
| Server tests/typecheck | 21 passed; typecheck clean | Real Better Auth on D1-shaped SQLite, not a remote runtime |
| Extension tests | 12 passed | Includes deterministic runtime-only packaging |
| Wrangler dry run | Passed; 56 Flutter assets read | Build proof only |
| Source re-review | PASS exact `ceeec89` | Independent, read-only; previous security FAIL was corrected |
| HTTPS root/health | Root 200; `auth: better_auth`, `google: setup_needed` | Google is not enabled |
| Missing asset | 404 | No Flutter HTML fallback |
| Real Flutter HTTPS integrations | 2 passed | Two-account quantity/membership/privacy/revocation/idempotent replay against remote D1; not two GUI devices |
| Browser cookie integration | PASS in Chrome 154 disposable profile | Synthetic sign-up via actual same-origin fetch, not login-form UI |
| Cookie attributes | HttpOnly, Secure, SameSite=Lax | Actual browser cookie readback; values not exported |
| Browser mutation protection | Same-origin 201; evil/missing Origin 403 | Rejected mutations did not create groups; list readback checked |
| Browser session | Persisted across fresh reload; sign-out then session 401 | Actual cookie/server flow |
| Native Android | HTTPS ARM64 debug APK installed on emulator without ADB reverse | Physical phone absent; not physical verification |
| Native account UI | Sign-in succeeded; cold-restart restored session; sign-out returned form | Existing local `QA 50 Shorts` retained. Initial probe wrongly expected name, but UI displays email; readback recovered genuine successful sign-in |
| Extension runtime | Popup rendered, opened exact HTTPS URL and reused same tab; no runtime exceptions/overflow | Installed only in a disposable headless profile, not personal Chrome/Web Store |
| Deployed observability | Query redaction true; invocation logs false; traces false | Provider email reset/verification callbacks remain unconfigured |

Browser/runtime fixture credentials remained ephemeral. Dedicated QA accounts/records are synthetic; they are not the user's data and do not establish offline sync. No existing local goals were uploaded.

## Artifact integrity

- Android debug ARM64 APK built with `GROUPS_API_URL=https://its-the-day.himanusia.com`.
- APK bytes: `116731630`.
- APK SHA-256: `af1228323c1b350d2696fba08bbaed4e04c3700bcc4b0caf8e20bd3bd553b9c3`.
- Extension companion version `1.0.0`; 12 runtime files, deterministic ZIP.
- Extension ZIP SHA-256: `57b33196c59b54f14780f477f24f2c6ec679c19649cf9bed75b152f5a2e7be10`.
- Extension opens/reuses the hosted app. It is not a full Flutter popup and does not copy or sync account/device data.

Screenshots: `evidence/cloudflare-web-home.png`, `evidence/chrome-companion-popup.png`, `evidence/android-https-account.png`, `evidence/android-https-cold-session.png`. Reviewed visually: deployed narrow web home rendered original clock/spark branding without visible overflow; native Account showed the successful synthetic session and sign-out, not a loading/error state; companion popup was legible and explicit about hosted-app boundaries.

## Reproduce

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --dart-define=ITD_REMOTE_E2E=true \
  test/group_membership_remote_e2e_test.dart
(cd server && npm test && npm run typecheck)
(cd extension && npm test && python3 scripts/package.py)
curl -fsS https://its-the-day.himanusia.com/health
```

Runtime test is explicitly opt-in because it creates synthetic QA records on this authorized deployment. Operator setup, migration, deployment/readback and Worker-only rollback are in `server/docs/cloudflare-online-runbook.md`.

## Not completed by this checkpoint

- Google live native/browser OAuth or Calendar; correct Web client ID/secret and callback configuration are still required. Supplied Android client is not substituted.
- Physical phone HTTPS APK replacement and physical interaction/notification/foldable matrix. Its previously installed loopback-configured build does not become remote-configured automatically.
- Shared checklist/individual/edit-delete/admin UI, durable offline outbox/reconciliation, automatic realtime, shared alarm scheduling/member responses/delivery/photo proof, iOS widget, store signing/publication and full production operational maturity.
- Personal Chrome installation: prohibited by standing preference. The extension is available unpacked/ZIP and tested only in a disposable profile.

Issues #11 and #12 are bounded deployment/companion checkpoints under #6, not a declaration that the whole product is finished. Do not infer completion percentages from test counts.
