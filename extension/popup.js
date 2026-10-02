(() => {
  'use strict';

  const openButton = document.getElementById('open-app');
  const status = document.getElementById('status');

  function setStatus(message) {
    status.textContent = message;
  }

  async function openHostedApp() {
    openButton.disabled = true;
    openButton.setAttribute('aria-busy', 'true');
    setStatus('Opening the hosted web app…');

    try {
      const navigation = globalThis.ItsTheDayNavigation;
      if (!navigation || !globalThis.chrome || !globalThis.chrome.tabs) {
        throw new Error('The Chrome tabs API is unavailable.');
      }

      const result = await navigation.openOrReuseAppTab(globalThis.chrome.tabs);
      setStatus(
        result.action === 'reused'
          ? "Existing It's the Day! tab focused."
          : "It's the Day! opened in a new tab.",
      );
    } catch {
      setStatus('Could not open the hosted app. Try again.');
    } finally {
      openButton.disabled = false;
      openButton.removeAttribute('aria-busy');
    }
  }

  if (openButton && status) {
    openButton.addEventListener('click', openHostedApp);
  }
})();
