(function () {
  let audioContext;
  let wakeLock;

  function context() {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return null;
    audioContext ||= new AudioContext();
    return audioContext;
  }

  window.fcTeugnPrepareTickerSignal = function () {
    const current = context();
    if (current && current.state === 'suspended') {
      current.resume().catch(() => {});
    }
  };

  window.fcTeugnPlayTickerEndSignal = function () {
    const current = context();
    if (!current) return;
    current.resume().then(() => {
      const start = current.currentTime;
      [
        { frequency: 659.25, offset: 0 },
        { frequency: 783.99, offset: 0.34 },
      ].forEach(({ frequency, offset }) => {
        const oscillator = current.createOscillator();
        const gain = current.createGain();
        oscillator.type = 'sine';
        oscillator.frequency.value = frequency;
        gain.gain.setValueAtTime(0.0001, start + offset);
        gain.gain.exponentialRampToValueAtTime(0.12, start + offset + 0.04);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.48);
        oscillator.connect(gain);
        gain.connect(current.destination);
        oscillator.start(start + offset);
        oscillator.stop(start + offset + 0.5);
      });
    }).catch(() => {});
  };

  window.fcTeugnActivateTickerFocusMode = function () {
    if (!('wakeLock' in navigator)) return;
    navigator.wakeLock.request('screen')
      .then((lock) => { wakeLock = lock; })
      .catch(() => {});
  };

  window.fcTeugnDeactivateTickerFocusMode = function () {
    if (!wakeLock) return;
    wakeLock.release().catch(() => {});
    wakeLock = null;
  };
})();
