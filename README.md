# It's the Day!

An Android-first countdown app for events, H-7/H-3/H-1/H-0 reminders, a home-screen widget, and calendar import.

## Current checkpoint boundaries

Quantity/checklist goals, Android widget goal focus, original Android/iOS/macOS/web icons, and the account client are implemented. Better Auth email/password is locally tested; Google account login integration is setup-gated and not live-verified. The group client remains explicitly unavailable, and signing in does not synchronize local goals. No production deployment, iOS widget, offline reconciliation, or realtime delivery is claimed.

See `server/README.md` for local migrations/auth/provider setup. For local account testing, build Android with `--dart-define=GROUPS_API_URL=http://10.0.2.2:8787` or iOS simulator with `--dart-define=GROUPS_API_URL=http://127.0.0.1:8787`. Web auth requires same-origin cookies. Account login does not request Calendar scopes.

Regenerate launcher assets with `uv run --with Pillow==12.3.0 python tool/generate_icons.py`.

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
- A local-testable Hono/D1-shaped groups API lives under `server/`; it covers private/shared goals, membership authorization, actor attribution, and idempotency. Its test verifier and SQLite adapter are not production auth.
- The UI includes setup-needed/offline/permission-denied states for groups and stores mobile session tokens only behind secure storage. Better Auth/provider/deployment setup remains explicit and unconfigured.

### Still required before online release

- Configure and independently verify Better Auth, its D1 adapter/schema, Google identity provider, bearer sessions, origins, rate limits, observability, migrations, and deployment bindings out of band.
- Add production notification/realtime/offline queue operations and complete emulator/physical-device/release QA. The web app provides in-app cards and local reload persistence; it does not claim native home-screen widgets.

### Target backend

The planned server stack is:

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

The Better Auth bearer plugin is the intended mobile transport. Browser cookies remain appropriate for a future web client. Google Calendar authorization stays separate and incremental: account sign-in starts with identity scopes, while `calendar.events.readonly` is requested only when the user connects Calendar.

## TODO / not finished

### Cloudflare backend and identity

- [x] Create a separate `server/` Cloudflare Worker using Hono and Wrangler.
- [x] Add Better Auth to the Hono Worker and mount `/api/auth/*`; local email/password sessions are tested. Production/provider setup remains unconfigured.
- [ ] Validate a D1-compatible Better Auth adapter (including schema generation/migrations) against local and deployed Workers before production use.
- [ ] Add Google account authentication/token verification for Flutter without storing the Google client secret in the mobile app.
- [x] Add a secure Flutter session-token client boundary; web cookie transport and Better Auth sign-in remain setup-needed.
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

- [ ] Add Cloudflare environment bindings/secrets without committing credentials.
- [ ] Add server integration tests against local D1/Workers test runtime.
- [ ] Add migration/backup/restore and observability runbooks.
- [ ] Run multi-account security tests before calling shared alarms production-ready.
- [ ] Complete physical Android device QA after the backend/auth slice is implemented.
