import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcPath = path.join(__dirname, '..', 'cinderwatch', 'src', '79-audio-state.js');
const code = fs.readFileSync(srcPath, 'utf8');
const AUDIO_STATE = new Function(`${code}\nreturn AUDIO_STATE;`)();

test('clampVolume bounds values and handles invalid inputs', () => {
  assert.equal(AUDIO_STATE.clampVolume(-0.4), 0);
  assert.equal(AUDIO_STATE.clampVolume(0), 0);
  assert.equal(AUDIO_STATE.clampVolume(0.456), 0.46);
  assert.equal(AUDIO_STATE.clampVolume(1), 1);
  assert.equal(AUDIO_STATE.clampVolume(2.5), 1);
  assert.equal(AUDIO_STATE.clampVolume('not-a-number'), 1);
  assert.equal(AUDIO_STATE.clampVolume(NaN), 1);
});

test('percent/volume conversions round-trip accurately', () => {
  assert.equal(AUDIO_STATE.volumeToPercent(0), 0);
  assert.equal(AUDIO_STATE.volumeToPercent(0.45), 45);
  assert.equal(AUDIO_STATE.volumeToPercent(1), 100);
  assert.equal(AUDIO_STATE.percentToVolume(0), 0);
  assert.equal(AUDIO_STATE.percentToVolume(45), 0.45);
  assert.equal(AUDIO_STATE.percentToVolume(125), 1);
  assert.equal(AUDIO_STATE.percentToVolume(-10), 0);
});

test('computeMasterGain scales base master gain and silences when muted', () => {
  assert.equal(AUDIO_STATE.computeMasterGain(1, false), 0.5);
  assert.equal(AUDIO_STATE.computeMasterGain(0.5, false), 0.25);
  assert.equal(AUDIO_STATE.computeMasterGain(0, false), 0);
  assert.equal(AUDIO_STATE.computeMasterGain(0.8, true), 0);
});

test('applyVolumeChange unmutes automatically when raising volume above zero', () => {
  assert.deepEqual(
    AUDIO_STATE.applyVolumeChange({ volume: 0.7, muted: true }, 0.45),
    { volume: 0.45, muted: false }
  );
  assert.deepEqual(
    AUDIO_STATE.applyVolumeChange({ volume: 0.7, muted: true }, 0),
    { volume: 0, muted: true }
  );
  assert.deepEqual(
    AUDIO_STATE.applyVolumeChange({ volume: 0.7, muted: false }, 0),
    { volume: 0, muted: false }
  );
});

test('applyMuteToggle preserves volume and restores audible level when unmuting from 0%', () => {
  assert.deepEqual(
    AUDIO_STATE.applyMuteToggle({ volume: 0.65, muted: false }),
    { volume: 0.65, muted: true }
  );
  assert.deepEqual(
    AUDIO_STATE.applyMuteToggle({ volume: 0.65, muted: true }),
    { volume: 0.65, muted: false }
  );
  assert.deepEqual(
    AUDIO_STATE.applyMuteToggle({ volume: 0, muted: true }),
    { volume: AUDIO_STATE.UNMUTE_FALLBACK_VOLUME, muted: false }
  );
});

test('parseStoredState handles empty, valid, and corrupted localStorage values', () => {
  assert.deepEqual(AUDIO_STATE.parseStoredState(null, null), { volume: 1, muted: false });
  assert.deepEqual(AUDIO_STATE.parseStoredState('0.35', '1'), { volume: 0.35, muted: true });
  assert.deepEqual(AUDIO_STATE.parseStoredState('0', '0'), { volume: 0, muted: false });
  assert.deepEqual(AUDIO_STATE.parseStoredState('bad', 'true'), { volume: 1, muted: true });
});

test('formatStatusText displays Muted or rounded percentage', () => {
  assert.equal(AUDIO_STATE.formatStatusText(0.8, false), '80%');
  assert.equal(AUDIO_STATE.formatStatusText(0.8, true), 'Muted');
  assert.equal(AUDIO_STATE.formatStatusText(0, false), '0%');
});
