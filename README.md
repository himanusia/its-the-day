# It's the Day!

An Android-first countdown app for events, H-7/H-3/H-1/H-0 reminders, a home-screen widget, and calendar import.

## Current checkpoint boundaries

**Web + API are live at https://its-the-day.himanusia.com**, on Cloudflare Workers + Hono + Better Auth + D1 with same-origin Workers Static Assets. Email sessions, groups and shared quantity create/read/add are verified against remote D1. Browser secure cookies/CSRF/reload/sign-out, native emulator sign-in/cold restart/sign-out, and the MV3 companion popup are tested. Local goals remain local; signing in does not upload them. Google login remains setup-needed. Alarms, iOS widget, offline reconciliation, realtime, store release and full physical QA are not complete. The physical phone was absent in ADB, so its previous loopback-configured APK has not been replaced with this HTTPS build.

See [deployment evidence](docs/delivery/cloudflare-online-checkpoint.md) and [Cloudflare runbook](server/docs/cloudflare-online-runbook.md). Build Android with `--dart-define=GROUPS_API_URL=https://its-the-day.himanusia.com`; no Mac backend or ADB reverse is needed. Flutter web defaults to same-origin secure cookies. Account login does not request Calendar scopes.

Regenerate launcher assets with `uv run --with Pillow==12.3.0 python tool/generate_icons.py`.

### Online artifacts and commands

```bash
flutter build web --no-pub --release
JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk --debug --no-pub \
  --split-per-abi --target-platform android-arm64 \
  --dart-define=GROUPS_API_URL=https://its-the-day.himanusia.com
flutter test --no-pub --dart-define=ITD_REMOTE_E2E=true \
  test/group_membership_remote_e2e_test.dart
```

The remote test creates synthetic QA accounts/records on the authorized deployment and signs out its sessions; it does not upload local device data. APK: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` (debug-signed ARM64, not a Play Store build). Use serial-scoped `adb install -r` on an authorized connected phone to preserve data. Do not uninstall on a signing mismatch.

Chrome MV3 companion: `cd extension && npm test && python3 scripts/package.py`. Load `extension/` unpacked through `chrome://extensions` in Developer mode. ZIP: `extension/dist/its-the-day-chrome-companion-v1.0.0.zip`. It opens/reuses the hosted web app, not a full Flutter-embedded popup; no account/token state is stored in the extension. Personal Chrome was not touched; no Web Store publication.

Google Web redirect: `https://its-the-day.himanusia.com/api/auth/callback/google`. The Android OAuth client is not a substitute for the Web ID/secret. Worker secret names are `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`; native `GOOGLE_SERVER_CLIENT_ID` receives the Web ID. Never embed the secret/OAuth JSON in the APK or repository.


## Current scope

- Manual countdowns with local persistence.
- All-day events counted by local calendar day; timed events counted to the second.
- Inexact local notifications for H-7, H-3, H-1, and H-0.
- Read-only device calendar import through Android `CalendarContract`.
- Read-only Google Calendar sync through Google OAuth (`calendar.events.readonly`).
- Native Android home-screen widget for the selected countdown.

Google Calendar sync is intentionally read-only in this MVP. It does not create, edit, or delete events in Google Calendar.

## Verify locally

Use JDK 21 for the current Android toolchain:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Enable Google Calendar login

The app does not contain a client secret or a hard-coded OAuth credential. Create the OAuth configuration in the Google Cloud project that owns the app:

1. Enable **Google Calendar API**.
2. Configure the OAuth consent screen and add the testing Google account as a test user while the app is unverified.
3. Create an **Android OAuth client** for package `com.himanusia.itstheday` and the SHA-1 certificate used by the build. `cd android && ./gradlew signingReport` prints the debug certificate.
4. Create or keep a **Web application OAuth client** in the same project.
5. Build with that web client ID supplied out of band:

```bash
flutter run \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

The client ID is passed at build time and is not committed. If it is missing, the Calendar screen shows `Needs setup` rather than presenting a login flow that must fail.

## Calendar modes

- **Device**: requests read-only calendar permission and reads calendars already synced to the Android device. This can include Google Calendar, but it is not an in-app Google login.
- **Google**: signs in explicitly, requests `calendar.events.readonly`, calls the Google Calendar API, and labels imported events as `GOOGLE CALENDAR`.

## Android QA

The normal gate order is:

1. `flutter analyze`
2. `flutter test`
3. Android emulator install/smoke test
4. Physical Android device install/visual and interaction QA

The display name and current package/repository slug are **It's the Day!**.

## Persistence and goals status

### Implemented now

- Android events and goals are stored locally as versioned JSON through `SharedPreferencesEventRepository`; legacy event stores migrate without dropping events.
- Quantity goals support positive targets, explicit units, end-of-local-day deadlines, pace guidance, cumulative entries, notes/URLs, soft deletion, quick +1, and duplicate-entry protection.
- Checklist goals support named items, optional explanations, exactly-once checking, and reversible unchecking.
- Widget state is stored in Android `SharedPreferences`; a selected countdown remains the primary widget card and the first goal is used when no countdown exists.
- `MemoryEventRepository` exists for deterministic tests/previews. Web uses the local repository path and explicitly omits native widgets/calendar/reminder integrations without crashing.
- The Hono/Better Auth API under `server/` is deployed on Cloudflare Workers with real D1. Its test verifier and SQLite adapter are unit-test fixtures, not deployed auth. Business data remains authoritative in D1.
- Group UI supports create/join/list/members and shared-total quantity create/read/add. Native sessions use secure storage; web uses HttpOnly cookies. Provider setup is explicit; Google is still unconfigured. Local goals are not silently synced.

### Remaining online feature/operations gates

- Complete Google Web OAuth configuration and native/browser provider verification. Existing core email auth, D1 migrations/bindings, native bearer and browser-cookie flows have live evidence; provider success is not inferred from those tests.
- Add production notification/realtime/offline queue operations and complete emulator/physical-device/release QA. The web app provides in-app cards and local reload persistence; it does not claim native home-screen widgets.

### Target backend

The deployed core is Workers + Hono + Better Auth + D1 + Workers Static Assets. The wider target stack below includes planned alarm/realtime/photo/delivery components, not deployed proof of them:

- **Cloudflare Workers + Hono**: typed HTTP/API layer.
- **Better Auth**: server-side identity, Google sign-in, account linking, and session lifecycle mounted in Hono. It is not a Flutter package and never runs with mobile client secrets.
- **Cloudflare D1**: authoritative relational database for users, groups, alarms, memberships, response states, challenge metadata, and audit events.
- **Durable Objects**: per-shared-alarm/group coordination and realtime presence/WebSocket fan-out; not a global singleton.
- **R2**: private object storage for optional proof photos, accessed through short-lived authorized upload/download URLs.
- **Queues/Workflows or scheduled Worker jobs**: notification fan-out, retries, recurring alarms, and missed-response transitions.

Hono is the API framework; it is not the database. D1 is the durable database of record. Better Auth owns the authentication/session tables; application tables for groups, alarms, responses, and challenges remain explicitly modeled and authorized by the API. Local preferences remain only a device cache/fallback after sync exists.

### Flutter authentication boundary

Better Auth is a TypeScript server library, so the Flutter app integrates with it over HTTPS rather than importing a Dart SDK. The planned native flow is:

1. Flutter uses the native Google Sign-In plugin to obtain a Google ID token.
2. Flutter sends that ID token to Better Auth's Google sign-in endpoint over HTTPS.
3. Better Auth verifies the token, creates/links the user in D1, and returns a session.
4. The Flutter client stores only the Better Auth session/bearer token in platform secure storage and attaches it to Hono API requests.
5. The Worker uses Better Auth session validation before reading or mutating private/shared alarm data.

The Better Auth bearer plugin is the implemented mobile transport. Same-origin secure browser cookies are implemented and live-tested. Google Calendar authorization stays separate and incremental: account sign-in starts with identity scopes, while `calendar.events.readonly` is requested only when the user connects Calendar.

## TODO / not finished

### Cloudflare backend and identity

- [x] Create a separate `server/` Cloudflare Worker using Hono and Wrangler.
- [x] Add Better Auth to the Hono Worker and mount `/api/auth/*`; email/password is live-tested on Cloudflare. Google provider remains unconfigured.
- [x] Validate Better Auth/D1 migrations and core sessions/groups/quantity against local and deployed Workers; full production maturity is separate.
- [ ] Add Google account authentication/token verification for Flutter without storing the Google client secret in the mobile app.
- [x] Secure native bearer storage and same-origin HttpOnly/Secure browser cookie transport; live core email journeys verified.
- [x] Add D1 migrations for accounts, groups, memberships, private/shared goals, progress, checklist state, and idempotency records.
- [x] Add server-side authorization: private goals are owner-only; shared goals require active group membership and role checks.
- [x] Add idempotency keys on group creation, goal creation, and progress mutations plus retry tests; durable outbox/retry delivery remains pending.
- [ ] Add Durable Object coordination per shared alarm/group for realtime state fan-out and conflict-safe updates.
- [ ] Add offline mobile queue and reconciliation against the server authority.

### Shared alarms and family groups

- [ ] Create/join/invite/leave family or group spaces with owner/admin/member roles.
- [ ] Support private alarms and shared alarms with explicit visibility.
- [ ] Track each member independently: pending, fired, snoozed, snooze count, acknowledged, missed, and timestamps.
- [ ] Keep snooze per member; one member's snooze must not move the shared schedule for everyone else.
- [ ] Add FCM/device-token registration and notification delivery/retry.
- [ ] Define timezone, DST, recurrence, missed-alarm, and membership-removal behavior with tests.

### Optional proof challenge

- [ ] Add an optional `challenge_mode` per alarm: `none` or `push_up_photo` in the first slice.
- [ ] Let an alarm owner choose whether a challenge is optional or required for acknowledgement; do not force challenges by default.
- [ ] When enabled, show a challenge after the alarm fires and allow camera capture/upload.
- [ ] Upload photos to a private R2 bucket; store only proof metadata and object references in D1.
- [ ] Let authorized group members see `submitted`, `acknowledged`, `snoozed`, or `missed` state according to policy.
- [ ] Treat a submitted photo as user-provided evidence, not automatic proof that the person physically woke up or completed push-ups.
- [ ] Add retention, deletion, access logs, signed URLs, and abuse/report handling before storing family photos.
- [ ] Do not add AI/photo verification unless explicitly approved; the first slice can use self-attestation or peer review.

### Release and operations

- [x] Configure Cloudflare D1/ASSETS/rate-limit bindings and private Better Auth secret; values are not in source.
- [x] Run explicit local Worker/D1 and remote HTTPS/D1 integration tests; opt-in skips are not runtime evidence.
- [x] Add migration, Worker-only rollback and observability runbook.
- [ ] Rehearse D1 backup/restore independently of Worker rollback.
- [ ] Run multi-account security tests before calling shared alarms production-ready.
- [ ] Complete physical Android device QA after the backend/auth slice is implemented.
