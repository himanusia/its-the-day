(() => {
  'use strict';

  const APP_ORIGIN = 'https://its-the-day.himanusia.com';
  const APP_URL = `${APP_ORIGIN}/`;
  const APP_URL_PATTERN = `${APP_ORIGIN}/*`;

  function isHostedAppUrl(value) {
    if (typeof value !== 'string' || value.length === 0) {
      return false;
    }

    try {
      const parsed = new URL(value);
      return (
        parsed.protocol === 'https:' &&
        parsed.hostname === 'its-the-day.himanusia.com' &&
        parsed.origin === APP_ORIGIN &&
        parsed.username === '' &&
        parsed.password === ''
      );
    } catch {
      return false;
    }
  }

  function chooseExistingTab(tabs) {
    return tabs
      .filter((tab) => tab && Number.isInteger(tab.id) && isHostedAppUrl(tab.url))
      .sort((left, right) => {
        const activeDifference = Number(Boolean(right.active)) - Number(Boolean(left.active));
        return activeDifference || left.id - right.id;
      })[0] || null;
  }

  async function openOrReuseAppTab(tabsApi) {
    if (!tabsApi || typeof tabsApi.query !== 'function' || typeof tabsApi.create !== 'function') {
      throw new TypeError('A Chrome tabs API with query and create is required.');
    }

    const queriedTabs = await tabsApi.query({ url: APP_URL_PATTERN });
    if (!Array.isArray(queriedTabs)) {
      throw new TypeError('Chrome tabs query did not return a tab list.');
    }

    const existingTab = chooseExistingTab(queriedTabs);
    if (existingTab) {
      if (typeof tabsApi.update !== 'function') {
        throw new TypeError('A Chrome tabs API with update is required to reuse a tab.');
      }
      await tabsApi.update(existingTab.id, { active: true });
      return {
        action: 'reused',
        tabId: existingTab.id,
        url: existingTab.url,
      };
    }

    const createdTab = await tabsApi.create({ url: APP_URL });
    return {
      action: 'created',
      tabId: createdTab && Number.isInteger(createdTab.id) ? createdTab.id : null,
      url: APP_URL,
    };
  }

  const api = {
    APP_ORIGIN,
    APP_URL,
    APP_URL_PATTERN,
    isHostedAppUrl,
    chooseExistingTab,
    openOrReuseAppTab,
  };

  globalThis.ItsTheDayNavigation = api;
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
})();
