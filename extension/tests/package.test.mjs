import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

const EXTENSION_DIR = fileURLToPath(new URL('..', import.meta.url));
const OUTPUT = join(EXTENSION_DIR, 'dist', 'its-the-day-chrome-companion-v1.0.0.zip');
const PACKAGE_FILES = [
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

function packageExtension() {
  return execFileSync('python3', ['scripts/package.py'], {
    cwd: EXTENSION_DIR,
    encoding: 'utf8',
  });
}

test('package command emits a deterministic runtime-only archive', () => {
  packageExtension();
  assert.equal(existsSync(OUTPUT), true);
  const first = readFileSync(OUTPUT);
  const firstHash = createHash('sha256').update(first).digest('hex');

  packageExtension();
  const second = readFileSync(OUTPUT);
  const secondHash = createHash('sha256').update(second).digest('hex');

  assert.equal(secondHash, firstHash);
  assert.match(firstHash, /^[0-9a-f]{64}$/);
});

test('package command reports the independent extension version', () => {
  const output = packageExtension();
  assert.match(output, /its-the-day-chrome-companion-v1\.0\.0\.zip/);
  assert.match(output, /12 files/);

  const names = JSON.parse(execFileSync('python3', [
    '-c',
    'import json, sys; from zipfile import ZipFile; print(json.dumps(ZipFile(sys.argv[1]).namelist()))',
    OUTPUT,
  ], { encoding: 'utf8' }));
  assert.deepEqual(names, PACKAGE_FILES);
});
