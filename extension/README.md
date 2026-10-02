# It's the Day! — hosted Chrome companion

This directory contains a small, installable Chrome Manifest V3 companion for the hosted app at:

`https://its-the-day.himanusia.com/`

The companion is intentionally a doorway, not a second client. Its popup contains one primary action: **Open It's the Day!**. It reuses an existing tab on the exact hosted HTTPS origin when possible, or opens the exact app URL in a new tab. Account, group, and progress controls stay in the hosted web app.

It is **not** a full Flutter-embedded popup, does not display fake synced totals, and does not maintain a local-versus-server copy of app state.

## Version boundary

- Extension version: `1.0.0` (independent starting version; not published to the Chrome Web Store).
- Current app baseline: `1.1.0+2` from the root Flutter package. This companion version does not claim to release or synchronize the app version.

## Permissions and security boundary

- Manifest V3 with an extension-local popup and local scripts/styles/assets only.
- `permissions` is intentionally empty; there is no `tabs` permission.
- The only host permission is the exact app origin pattern `https://its-the-day.himanusia.com/*`, used so the popup can identify a hosted-app tab to focus.
- No content scripts, background service worker, browser history, global URL access, remote executable JavaScript, network fetches, cookies, tokens, account state, or group state.
- The popup's Content Security Policy is `script-src 'self'; object-src 'self';` with no inline JavaScript or inline styles.
- Branding is copied from the existing local mark and web icons; the source assets remain untouched.

## Deterministic checks and package

No package installation is required. From this directory:

```sh
npm test
npm run package
```

`npm test` runs the Node built-in unit/schema/security suite. It covers:

- exact HTTPS-origin allowlisting and rejection of lookalike origins;
- reuse of a matching hosted-app tab without touching unrelated tabs;
- exact URL creation when no matching tab exists;
- MV3 manifest shape, empty sensitive permissions, and narrow host permission;
- local-only popup resources, CSP-safe source, and absence of token/storage/scraping/remote-execution paths;
- deterministic packaging behavior.

`npm run package` is equivalent to:

```sh
python3 scripts/package.py
```

It writes the reproducible runtime-only archive:

`dist/its-the-day-chrome-companion-v1.0.0.zip`

The archive has a fixed file order and timestamp, contains exactly the runtime manifest/popup/navigation/assets, and excludes tests, scripts, and documentation. The archive is a handoff artifact, not evidence of Web Store publication.

## Disposable-profile unpacked install

For parent-owned disposable Chromium QA only:

1. Run `npm test`.
2. Run `npm run package` if a ZIP artifact is needed.
3. Open `chrome://extensions` in the disposable Chromium profile.
4. Enable **Developer mode**.
5. Choose **Load unpacked** and select this `extension/` directory (not the ZIP).
6. Click the extension action and activate **Open It's the Day!**.
7. Verify that the exact hosted app opens or that an existing hosted-app tab is focused. Use the hosted web app for account and group flows.

Do not install this in a personal Chrome profile and do not publish it to the Chrome Web Store as part of this lane.
