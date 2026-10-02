import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import vm from 'node:vm';

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const EXTENSION_DIR = join(TEST_DIR, '..');

function loadNavigation() {
  const source = readFileSync(join(EXTENSION_DIR, 'navigation.js'), 'utf8');
  const module = { exports: {} };
  const context = { URL, module, console };
  context.globalThis = context;
  vm.runInNewContext(source, context, { filename: 'navigation.js' });
  return module.exports;
}

test('allows only the hosted HTTPS app origin', () => {
  const { isHostedAppUrl } = loadNavigation();

  assert.equal(isHostedAppUrl('https://its-the-day.himanusia.com/'), true);
  assert.equal(isHostedAppUrl('https://its-the-day.himanusia.com/groups?group=7#today'), true);
  assert.equal(isHostedAppUrl('http://its-the-day.himanusia.com/'), false);
  assert.equal(isHostedAppUrl('https://www.its-the-day.himanusia.com/'), false);
  assert.equal(isHostedAppUrl('https://its-the-day.himanusia.com.evil.example/'), false);
  assert.equal(isHostedAppUrl('https://evil.example/?next=https://its-the-day.himanusia.com/'), false);
  assert.equal(isHostedAppUrl('javascript:alert(1)'), false);
  assert.equal(isHostedAppUrl('not a URL'), false);
});

test('reuses the active hosted-app tab and never touches an unrelated tab', async () => {
  const { APP_URL_PATTERN, openOrReuseAppTab } = loadNavigation();
  const calls = [];
  const tabsApi = {
    async query(queryInfo) {
      calls.push(['query', queryInfo]);
      return [
        { id: 88, active: true, url: 'https://its-the-day.himanusia.com/groups' },
        { id: 12, active: false, url: 'https://example.com/private' },
      ];
    },
    async update(tabId, updateInfo) {
      calls.push(['update', tabId, updateInfo]);
      return { id: tabId, url: 'https://its-the-day.himanusia.com/groups' };
    },
    async create(createInfo) {
      calls.push(['create', createInfo]);
      return { id: 99, ...createInfo };
    },
  };

  const result = await openOrReuseAppTab(tabsApi);

  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [
    ['query', { url: APP_URL_PATTERN }],
    ['update', 88, { active: true }],
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), {
    action: 'reused',
    tabId: 88,
    url: 'https://its-the-day.himanusia.com/groups',
  });
});

test('opens the exact hosted app when no hosted-app tab exists', async () => {
  const { APP_URL_PATTERN, APP_URL, openOrReuseAppTab } = loadNavigation();
  const calls = [];
  const tabsApi = {
    async query(queryInfo) {
      calls.push(['query', queryInfo]);
      return [{ id: 12, active: true, url: 'https://example.com/private' }];
    },
    async update(tabId, updateInfo) {
      calls.push(['update', tabId, updateInfo]);
      return { id: tabId, ...updateInfo };
    },
    async create(createInfo) {
      calls.push(['create', createInfo]);
      return { id: 44, ...createInfo };
    },
  };

  const result = await openOrReuseAppTab(tabsApi);

  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [
    ['query', { url: APP_URL_PATTERN }],
    ['create', { url: APP_URL }],
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { action: 'created', tabId: 44, url: APP_URL });
});

test('does not update a tab whose returned URL is outside the allowlist', async () => {
  const { APP_URL, openOrReuseAppTab } = loadNavigation();
  const calls = [];
  const tabsApi = {
    async query() {
      return [{ id: 23, active: true, url: 'https://evil.example/' }];
    },
    async update(...args) {
      calls.push(['update', ...args]);
    },
    async create(info) {
      calls.push(['create', info]);
      return { id: 24, ...info };
    },
  };

  const result = await openOrReuseAppTab(tabsApi);

  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [['create', { url: APP_URL }]]);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { action: 'created', tabId: 24, url: APP_URL });
});
