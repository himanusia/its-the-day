# Shared quantity create/read/add checkpoint

Parent tracker: #6. Checkpoint: #9. PR: #10.

## Implemented slice

The group members screen links to a server-filtered quantity/shared-total goal list. Members can create a goal with title, integer target, unit and calendar-date deadline, open authoritative detail, and log a positive integer result with an optional note. Mutation keys survive unchanged retries and auth recovery; forms preserve drafts. Local goals are not uploaded. Refresh is explicit, not realtime or an offline queue.

Contribution timestamps are assigned by the server and displayed in local time. The add dialog explicitly says "Recorded by the server when you submit." This is not a user-selectable historical contribution date. Goal deadlines are date-only values.

## Parent verification

- Flutter analyze: clean.
- Default Flutter suite: 62 passing tests, two opt-in integration tests skipped.
- Server typecheck: clean; nine server tests pass.
- Opt-in actual client/loopback Worker+D1 integration: two tests pass. The added quantity journey creates and lists a group goal, logs results from two ephemeral accounts, checks authoritative total/results/notes, repeats an unchanged mutation key without adding a result, checks unrelated-group filtering, and rejects a revoked member's read.
- ARM64 debug APK built with `GROUPS_API_URL=http://10.0.2.2:8787`, installed successfully on the API36 ARM64 emulator.
- Actual emulator journey: existing signed-in owner opened a group, created a goal with target10/unit times/date-only deadline, opened detail, and submitted +1 with `App note`. A second authenticated HTTP account added +3 with `Second account note`; replay reused the same result ID. The app refreshed to4/10,6 remaining, two results and both notes. After force-stop/cold launch and navigating back, the same authoritative values remained.
- Screenshots inspected: no visible overflow in this emulator layout. They do not prove motion quality or the full accessibility matrix.
- The initial software-rendered emulator became unresponsive with a system ANR during input. It was restarted without snapshots using the host GPU, then the journey above was repeated successfully. The input harness also dropped a leading title character; the observed fixture title is `print`, not product UI copy.

Evidence: `evidence/shared-quantity-two-results.png` and `evidence/shared-quantity-cold-reload.png`. The cross-account GUI journey used one app GUI plus a second authenticated HTTP client, not two GUI devices.

## Reproduce local gates

Start the configured loopback Wrangler/D1 server using the existing private local environment, then run:

```sh
flutter analyze
flutter test
flutter test test/group_membership_local_e2e_test.dart --dart-define=ITD_LOCAL_E2E=true
(cd server && npm run typecheck && npm test)
JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk --debug --split-per-abi --target-platform android-arm64 --dart-define=GROUPS_API_URL=http://10.0.2.2:8787
```

The opt-in tests deliberately create ephemeral local QA data. Credentials remain in memory; they are not printed or persisted in the repository.

## Cloudflare boundary and remaining gates

The exercised backend is a local Cloudflare Worker/Hono/Better Auth+D1 runtime. No remote resources have been provisioned or deployed by this checkpoint. Workers/D1 remains the authoritative backend target, with Durable Objects, Queues and scheduled processing planned for coordination/delivery, optional private R2 for photos, and Workers Static Assets for same-origin web hosting. Those planned services are not claimed implemented here.

Independent exact-source review is pending. This document does not establish merge state. Shared checklist/individual mode/edit-delete/admin UI, offline outbox/reconciliation/realtime, shared alarms/notification delivery, live Google OAuth, browser-cookie E2E and physical-device QA remain outside this slice. The broader shared-goal gate in #6 stays open.
