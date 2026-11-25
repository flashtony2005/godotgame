const AUDIO_STATE = (function () {
  const BASE_MASTER_GAIN = 0.5;
  const DEFAULT_VOLUME = 1.0;
  const UNMUTE_FALLBACK_VOLUME = 0.5;

  function clampVolume(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return DEFAULT_VOLUME;
    if (n <= 0) return 0;
    if (n >= 1) return 1;
    return Math.round(n * 100) / 100;
  }

  function volumeToPercent(v) {
    return Math.round(clampVolume(v) * 100);
  }

  function percentToVolume(pct) {
    const n = Number(pct);
    if (!Number.isFinite(n)) return DEFAULT_VOLUME;
    return clampVolume(n / 100);
  }

  function computeMasterGain(volume, muted) {
    if (muted) return 0;
    return BASE_MASTER_GAIN * clampVolume(volume);
  }

  function applyVolumeChange(state, nextVolume) {
    const volume = clampVolume(nextVolume);
    const muted = volume > 0 ? false : !!state.muted;
    return { volume, muted };
  }

  function applyMuteToggle(state, nextMuted) {
    const muted = nextMuted === undefined ? !state.muted : !!nextMuted;
    let volume = clampVolume(state.volume);
    if (!muted && volume <= 0) volume = UNMUTE_FALLBACK_VOLUME;
    return { volume, muted };
  }

  function parseStoredState(rawVolume, rawMuted) {
    const hasVol = rawVolume !== null && rawVolume !== undefined && rawVolume !== '';
    const volume = hasVol ? clampVolume(rawVolume) : DEFAULT_VOLUME;
    const muted = rawMuted === '1' || rawMuted === 'true' || rawMuted === true;
    return { volume, muted };
  }

  function formatStatusText(volume, muted) {
    if (muted) return 'Muted';
    return volumeToPercent(volume) + '%';
  }

  return {
    BASE_MASTER_GAIN,
    DEFAULT_VOLUME,
    UNMUTE_FALLBACK_VOLUME,
    clampVolume,
    volumeToPercent,
    percentToVolume,
    computeMasterGain,
    applyVolumeChange,
    applyMuteToggle,
    parseStoredState,
    formatStatusText,
  };
})();
