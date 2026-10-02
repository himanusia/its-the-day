import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const EXTENSION_DIR = fileURLToPath(new URL('..', import.meta.url));
const manifest = JSON.parse(readFileSync(join(EXTENSION_DIR, 'manifest.json'), 'utf8'));
const packageJson = JSON.parse(readFileSync(join(EXTENSION_DIR, 'package.json'), 'utf8'));

function readExtensionFile(relativePath) {
  return readFileSync(join(EXTENSION_DIR, relativePath), 'utf8');
}

test('manifest is a bounded MV3 popup companion', () => {
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.version, '1.0.0');
  assert.equal(manifest.name, "It's the Day! — hosted companion");
  assert.equal(manifest.action.default_popup, 'popup.html');
  assert.equal(manifest.action.default_title, "Open It's the Day!");
  assert.deepEqual(manifest.permissions, []);
  assert.deepEqual(manifest.host_permissions, ['https://its-the-day.himanusia.com/*']);
  assert.equal('content_scripts' in manifest, false);
  assert.equal('background' in manifest, false);
});

test('package metadata keeps the companion private and versioned independently', () => {
  assert.equal(packageJson.private, true);
  assert.equal(packageJson.version, '1.0.0');
  assert.equal(packageJson.scripts.test, 'node --test tests/*.test.mjs');
  assert.equal(packageJson.scripts.package, 'python3 scripts/package.py');

  const readme = readExtensionFile('README.md');
  assert.match(readme, /full Flutter-embedded popup/i);
  assert.match(readme, /not published to the Chrome Web Store/i);
  assert.match(readme, /personal Chrome profile/i);
});

test('manifest has no broad or sensitive permissions', () => {
  const permissions = [...(manifest.permissions || []), ...(manifest.host_permissions || [])];
  const forbiddenPermissions = new Set([
    '<all_urls>',
    '*://*/*',
    'activeTab',
    'bookmarks',
    'browsingData',
    'cookies',
    'history',
    'sessions',
    'scripting',
    'storage',
    'tabs',
    'webNavigation',
    'webRequest',
  ]);

  assert.deepEqual(permissions.filter((permission) => forbiddenPermissions.has(permission)), []);
  assert.equal(permissions.some((permission) => permission.startsWith('http://')), false);
  assert.equal(permissions.some((permission) => permission.includes('*://')), false);
  assert.equal(permissions.some((permission) => permission.includes('/*/*')), false);
});

test('declared runtime files and local visual assets exist', () => {
  const runtimeFiles = [
    'manifest.json',
    'popup.html',
    'popup.css',
    'popup.js',
    'navigation.js',
    'assets/its_the_day_mark.svg',
    'icons/icon-16.png',
    'icons/icon-32.png',
    'icons/icon-48.png',
    'icons/icon-128.png',
    'icons/icon-192.png',
    'icons/icon-512.png',
  ];

  for (const file of runtimeFiles) {
    assert.equal(existsSync(join(EXTENSION_DIR, file)), true, `${file} should exist`);
  }

  for (const icon of Object.values(manifest.icons)) {
    assert.equal(existsSync(join(EXTENSION_DIR, icon)), true, `${icon} should exist`);
  }
  for (const icon of Object.values(manifest.action.default_icon)) {
    assert.equal(existsSync(join(EXTENSION_DIR, icon)), true, `${icon} should exist`);
  }
});

test('popup uses only local executable resources and names the hosted boundary', () => {
  const html = readExtensionFile('popup.html');
  assert.match(html, /<script\s+src="navigation\.js"\s+defer><\/script>/);
  assert.match(html, /<script\s+src="popup\.js"\s+defer><\/script>/);
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)[^>]*>/i);
  assert.doesNotMatch(html, /<style\b/i);
  assert.doesNotMatch(html, /\sstyle\s*=/i);
  assert.doesNotMatch(html, /(?:https?:|javascript:|data:)/i);
  assert.match(html, /Accounts, groups, and progress live in the hosted app/i);
  assert.match(html, /does not copy or sync your data/i);
  assert.match(html, /Open It's the Day!/i);
});

test('runtime JavaScript has no remote execution, persistence, scraping, or token path', () => {
  const source = `${readExtensionFile('navigation.js')}\n${readExtensionFile('popup.js')}`;
  const forbiddenPatterns = [
    /\beval\s*\(/,
    /\bnew\s+Function\s*\(/,
    /\bimport\s*\(/,
    /\bfetch\s*\(/,
    /XMLHttpRequest/,
    /document\.cookie/,
    /localStorage|sessionStorage/,
    /chrome\.(?:history|scripting|webNavigation|webRequest)/,
    /\b(?:access|read|capture|sync)\b[^\n]*(?:token|cookie)/i,
  ];

  for (const pattern of forbiddenPatterns) {
    assert.doesNotMatch(source, pattern, `runtime must not contain ${pattern}`);
  }
  assert.match(source, /chrome\.tabs/);
  assert.doesNotMatch(source, /chrome\.tabs\.query\(\{\s*\}/);
});
