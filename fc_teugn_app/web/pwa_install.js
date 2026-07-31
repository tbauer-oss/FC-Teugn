(function () {
  let deferredInstallPrompt = null;

  function isIos() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function isIosSafari() {
    if (!isIos()) return false;
    return /safari/i.test(navigator.userAgent) &&
      !/crios|fxios|edgios|opios/i.test(navigator.userAgent);
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredInstallPrompt = event;
  });

  window.addEventListener('appinstalled', function () {
    deferredInstallPrompt = null;
  });

  window.fcTeugnPwaState = function () {
    return JSON.stringify({
      ios: isIos(),
      iosSafari: isIosSafari(),
      standalone: isStandalone(),
      canPrompt: deferredInstallPrompt !== null,
    });
  };

  window.fcTeugnInstallPwa = async function () {
    if (!deferredInstallPrompt) return false;
    const prompt = deferredInstallPrompt;
    deferredInstallPrompt = null;
    await prompt.prompt();
    const choice = await prompt.userChoice;
    return choice.outcome === 'accepted';
  };
})();
