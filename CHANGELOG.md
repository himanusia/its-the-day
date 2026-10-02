# Changelog

## 1.1.0-cloudflare.1 — Early access

- Deploy the existing account/group/shared-quantity core and Flutter web on Cloudflare Workers + D1 at https://its-the-day.himanusia.com.
- Same-origin HTTPS cookies, native bearer transport, exact-Origin mutation protection, Cloudflare auth rate limits and redacted edge observability.
- Add original-branded Chrome MV3 hosted-app companion; deterministic unpacked ZIP, no account/token storage or personal-profile modification.
- Add opt-in real HTTPS/D1 integration tests and browser/native/extension runtime evidence.
- Provide an ARM64 debug APK configured for the public HTTPS API, not a loopback/Mac backend.

Application package version remains `1.1.0+2`; this tag identifies the Cloudflare delivery checkpoint. Extension version is independently `1.0.0`. APK is debug-signed; no store publication. Google remains setup-needed without Web OAuth credentials. Physical phone HTTPS replacement is pending device availability. Shared checklist/individual/admin/edit-delete UI, offline outbox, realtime, shared alarms/photo proof and iOS widget remain tracked, not completed by this release.

## 1.1.0 — goals and shared spaces

- Added locally persistent quantity and checklist goals with deadlines, pace guidance, progress entries, explanations, and safe retry semantics.
- Added a local-testable Cloudflare Workers/Hono/D1-shaped groups API with membership authorization, private/shared goals, actor attribution, and idempotency keys.
- Added setup-needed groups UX and secure mobile session-token boundary; Better Auth/provider deployment remains explicitly unconfigured until operator setup.
- Added original clock-and-spark product artwork, Android adaptive icon/splash resources, web PWA branding, reduced-motion progress transitions, and tactile goal cards.
- Preserved countdown events, reminders, calendar import, Google Calendar setup state, and the Android widget.
