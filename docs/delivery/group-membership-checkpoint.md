# Group membership client checkpoint

Refs #7; parent tracker #6. Cloudflare Workers/Hono/Better Auth + D1 remain the backend target. No deployment or provider configuration changes.

## Implemented

Authenticated group list, create/join dialogs, member list, role/activity labels, owner invite code and refresh. Native secure bearer and same-origin web cookies reuse the existing transport. Unchanged form payload retries retain the operation key; submission guards prevent duplicate taps. Local tracker data remains device-local. Member profile names are not available from the current member route: this slice displays role/activity, not raw account IDs.

## Parent verification

- `flutter analyze`: clean.
- Full `flutter test`: 55 passed before adding the opt-in live test.
- Server `npm run typecheck` and `npm test`: clean, 9 passed.
- Android debug APK built with `GROUPS_API_URL=http://10.0.2.2:8787`.
- Local health readback: Better Auth enabled, Google setup needed.
- `flutter test test/group_membership_local_e2e_test.dart --dart-define=ITD_LOCAL_E2E=true`: passed against real local Wrangler/D1. It creates ephemeral synthetic accounts, invokes the real Flutter HTTP client, creates and replays one group mutation, joins a second account, reads membership from both, denies an outsider, revokes the member and verifies group visibility/sign-out. Tokens exist only in test-process memory and are not logged. Synthetic account/group records remain in the local QA database; sign-out is attempted during cleanup.
- The live test first failed because the backend intentionally returns `404 not_found` for inaccessible groups rather than `403`; the membership client now maps this privacy-preserving response to its access-denied state. No server contract was changed.

## Not yet verified

Two-account emulator UI interaction, fresh installed screen captures and independent review. Android install timed out twice on the existing emulator (streaming and no-streaming), so build success is NOT treated as successful installation. The real-client test above is not a widget or emulator E2E.

Shared goal CRUD, individual target/member management, offline outbox, live Google OAuth, shared alarm scheduling/delivery, iOS widgets and production Cloudflare provisioning are not part of this checkpoint. Do not close #7 until its remaining UI QA gate is satisfied.
