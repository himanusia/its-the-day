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

## Emulator QA and review follow-up

The install timeout was recovered by restarting the owned AVD without snapshots and installing the ABI-matched ARM64 debug APK. An initial x86_64 split build was rejected with `INSTALL_FAILED_NO_MATCHING_ABIS`; it was not treated as installed.

On `h-countdown-api36`, API at emulator `10.0.2.2:8787`, parent exercised:
- Signed-in app account creates a real group through the dialog; owner code appears.
- A separate ephemeral HTTP account joins it; app refresh shows two members and member screen shows Owner/Member active, without raw account IDs. The second account's raw list response has null invite code.
- The second HTTP account creates another group; the app account joins it through the actual Join dialog and refresh displays Member, with no invite code.
- Force-stop/cold-launch returns to home; opening Groups reloads both memberships from the server.
- Screenshots inspected: `evidence/groups-two-members.png` and `evidence/groups-cold-reload.png`. One app GUI plus a second real HTTP client were used, not two GUI devices.

ADB IME input initially truncated the join code; the dialog correctly stayed open with an error. Replacing it with character-by-character input and verifying the fresh UI tree made the request succeed. UI dump collection was hardened to remove previous XML before each capture to avoid stale readback during launch.

Review fixes: account recovery now opens the account page above the still-live mutation dialog, preserving draft and operation key; a widget regression exercises return/retry. Server group lists return invite codes only to owners, verified by server tests. Stale Account unavailable copy had already been replaced. Final gates after these fixes: analyze/typecheck clean, 56 Flutter tests pass (1 opt-in skipped), 9 server tests pass, separate opt-in local HTTP test passes, ABI-matched APK builds and installs. Independent final source review is pending; no production deployment is claimed.

Shared goal CRUD, individual target/member management, offline outbox, live Google OAuth, shared alarm scheduling/delivery, iOS widgets and production Cloudflare provisioning are not part of this checkpoint. Do not close #7 until its remaining UI QA gate is satisfied.
