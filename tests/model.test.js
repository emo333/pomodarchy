const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'Model.js'), 'utf8');
const Model = vm.createContext({});
vm.runInContext(source, Model, { filename: 'Model.js' });

const config = {
  focusMinutes: 25,
  shortBreakMinutes: 6,
  longBreakMinutes: 31,
  longBreakEvery: 4,
};
const minute = 60 * 1000;

function finishPhase(state, now, phaseDurationMs) {
  const running = Model.start(state, now);
  return Model.tick(running, now + phaseDurationMs);
}

test('createState uses configured focus duration and normalized bounds', () => {
  const state = Model.createState(config);
  assert.equal(state.phase, 'focus');
  assert.equal(state.status, 'idle');
  assert.equal(state.remainingMs, 25 * minute);
  assert.equal(state.deadlineMs, null);
  assert.equal(state.completedFocusSessions, 0);

  assert.equal(Model.createState({ focusMinutes: -10 }).remainingMs, minute);
  assert.equal(Model.createState({ focusMinutes: 99999 }).remainingMs, 1440 * minute);
  assert.equal(Model.createState({ focusMinutes: 'not a number' }).remainingMs, 30 * minute);
  assert.equal(Model.createState({ focusMinutes: 2.6 }).remainingMs, 3 * minute);
});

test('start, countdown, pause, and resume preserve elapsed-time semantics', () => {
  const initial = Model.createState(config);
  const running = Model.start(initial, 1000);
  assert.equal(running.status, 'running');
  assert.equal(running.deadlineMs, 1000 + 25 * minute);
  assert.equal(Model.currentRemainingMs(running, 4000), 25 * minute - 3000);
  assert.equal(initial.status, 'idle', 'transitions do not mutate the input state');

  const paused = Model.pause(running, 4000);
  assert.equal(paused.status, 'paused');
  assert.equal(paused.remainingMs, 25 * minute - 3000);
  assert.equal(paused.deadlineMs, null);
  assert.equal(Model.currentRemainingMs(paused, 100000), paused.remainingMs);

  const resumed = Model.start(paused, 9000);
  assert.equal(resumed.status, 'running');
  assert.equal(resumed.deadlineMs, 9000 + paused.remainingMs);

  const expiry = 1000 + 25 * minute;
  const atExpiry = Model.pause(running, expiry);
  assert.equal(atExpiry.status, 'awaiting');
  assert.equal(atExpiry.remainingMs, 0);
  assert.equal(Model.acknowledge(atExpiry, expiry, config).phase, 'shortBreak');
  assert.equal(Model.pause(running, expiry + 100).status, 'awaiting');
});

test('tick enters awaiting at expiry and acknowledge starts the next phase', () => {
  const initial = Model.createState(config);
  const running = Model.start(initial, 0);
  const beforeExpiry = Model.tick(running, 25 * minute - 1);
  assert.equal(beforeExpiry, running);
  assert.equal(Model.tick(running, 25 * minute - 1).status, 'running');

  const awaiting = Model.tick(running, 25 * minute);
  assert.equal(awaiting.status, 'awaiting');
  assert.equal(awaiting.remainingMs, 0);
  assert.equal(awaiting.deadlineMs, null);
  assert.equal(Model.acknowledge(running, 25 * minute, config), running, 'acknowledgment is ignored before expiry');

  const next = Model.acknowledge(awaiting, 25 * minute, config);
  assert.equal(next.phase, 'shortBreak');
  assert.equal(next.status, 'running');
  assert.equal(next.remainingMs, 6 * minute);
  assert.equal(next.deadlineMs, 31 * minute);
  assert.equal(next.completedFocusSessions, 1);
});

test('long break follows every fourth acknowledged focus session', () => {
  let state = Model.createState(config);
  let now = 0;

  for (let session = 1; session <= 8; session += 1) {
    const focusDuration = state.remainingMs;
    state = finishPhase(state, now, focusDuration);
    now += focusDuration;
    const expectedBreak = session % 4 === 0 ? 'longBreak' : 'shortBreak';
    state = Model.acknowledge(state, now, config);
    assert.equal(state.phase, expectedBreak, `break after focus session ${session}`);
    assert.equal(state.remainingMs, (expectedBreak === 'longBreak' ? 31 : 6) * minute);
    assert.equal(state.completedFocusSessions, session);

    const breakDuration = state.remainingMs;
    state = finishPhase(state, now, breakDuration);
    now += breakDuration;
    state = Model.acknowledge(state, now, config);
    assert.equal(state.phase, 'focus');
  }
});

test('skip advances immediately without crediting running or paused focus', () => {
  let state = Model.start(Model.createState(config), 0);
  state = Model.skip(state, 10, config);
  assert.equal(state.phase, 'shortBreak');
  assert.equal(state.status, 'running');
  assert.equal(state.completedFocusSessions, 0);

  state = Model.pause(Model.start(Model.createState(config), 100), 500);
  state = Model.skip(state, 600, config);
  assert.equal(state.phase, 'shortBreak');
  assert.equal(state.completedFocusSessions, 0);
});

test('skipping an awaiting completed focus counts it, while skipping a break returns to focus', () => {
  let state = Model.tick(Model.start(Model.createState(config), 0), 25 * minute);
  state = Model.skip(state, 25 * minute, config);
  assert.equal(state.phase, 'shortBreak');
  assert.equal(state.completedFocusSessions, 1);

  state = Model.skip(state, 25 * minute + 1, config);
  assert.equal(state.phase, 'focus');
  assert.equal(state.completedFocusSessions, 1);
});

test('restart resets the current phase duration and starts immediately', () => {
  let state = Model.start(Model.createState(config), 0);
  state = Model.pause(state, 12 * minute);
  state = Model.restart(state, 50 * minute, config);
  assert.equal(state.phase, 'focus');
  assert.equal(state.status, 'running');
  assert.equal(state.remainingMs, 25 * minute);
  assert.equal(state.deadlineMs, 75 * minute);
  assert.equal(state.completedFocusSessions, 0);

  const breakState = Model.skip(state, 50 * minute, config);
  const restartedBreak = Model.restart(breakState, 60 * minute, config);
  assert.equal(restartedBreak.phase, 'shortBreak');
  assert.equal(restartedBreak.remainingMs, 6 * minute);
});

test('suspend resume starts a fresh running focus without crediting a session', () => {
  const state = Model.suspendResume(1234, config);
  assert.equal(state.phase, 'focus');
  assert.equal(state.status, 'running');
  assert.equal(state.remainingMs, 25 * minute);
  assert.equal(state.deadlineMs, 1234 + 25 * minute);
  assert.equal(state.completedFocusSessions, 0);

  const prior = { ...state, completedFocusSessions: 3, remainingMs: 1 };
  const resumed = Model.suspendResume(5000, config, prior);
  assert.equal(resumed.phase, 'focus');
  assert.equal(resumed.status, 'running');
  assert.equal(resumed.remainingMs, 25 * minute);
  assert.equal(resumed.deadlineMs, 5000 + 25 * minute);
  assert.equal(resumed.completedFocusSessions, 3);
  assert.equal(prior.remainingMs, 1, 'suspend resume does not mutate the prior state');
});

test('defaultConfig ships the completion sound settings', () => {
  const defaults = Model.defaultConfig();
  assert.equal(defaults.soundEnabled, true);
  assert.equal(defaults.focusEndSound, 'assets/focus-complete.wav');
  assert.equal(defaults.breakEndSound, 'assets/break-complete.wav');
  assert.equal(defaults.soundVolume, 50);

  const normalized = Model.normalizeConfig({});
  assert.equal(normalized.soundEnabled, true);
  assert.equal(normalized.focusEndSound, defaults.focusEndSound);
  assert.equal(normalized.breakEndSound, defaults.breakEndSound);
  assert.equal(normalized.soundVolume, 50);
  assert.deepEqual(Object.keys(normalized), Object.keys(defaults), 'config key set stays stable');
});

test('default sound paths are plugin-relative bundled assets', () => {
  const defaults = Model.defaultConfig();
  const bundled = {
    focusEndSound: 'assets/focus-complete.wav',
    breakEndSound: 'assets/break-complete.wav',
  };
  assert.equal(defaults.focusEndSound, bundled.focusEndSound);
  assert.equal(defaults.breakEndSound, bundled.breakEndSound);

  for (const key of Object.keys(bundled)) {
    assert.ok(!path.isAbsolute(defaults[key]), `${key} is relative, not absolute`);
    assert.ok(!defaults[key].startsWith('/'), `${key} does not start with a slash`);
    assert.ok(!defaults[key].split('/').includes('..'), `${key} does not escape the plugin directory`);
    assert.ok(defaults[key].startsWith('assets/'), `${key} lives in the assets directory`);
    assert.ok(
      fs.existsSync(path.join(__dirname, '..', defaults[key])),
      `${key} default ${defaults[key]} exists in the repository`
    );
  }

  const normalized = Model.normalizeConfig({});
  assert.equal(normalized.focusEndSound, bundled.focusEndSound);
  assert.equal(normalized.breakEndSound, bundled.breakEndSound);
  assert.equal(Model.soundPathForPhase('focus'), bundled.focusEndSound);
  assert.equal(Model.soundPathForPhase('longBreak'), bundled.breakEndSound);
});

test('soundEnabled accepts booleans and true/false strings only', () => {
  assert.equal(Model.normalizeConfig({ soundEnabled: false }).soundEnabled, false);
  assert.equal(Model.normalizeConfig({ soundEnabled: true }).soundEnabled, true);
  assert.equal(Model.normalizeConfig({ soundEnabled: 'false' }).soundEnabled, false);
  assert.equal(Model.normalizeConfig({ soundEnabled: 'FALSE' }).soundEnabled, false);
  assert.equal(Model.normalizeConfig({ soundEnabled: ' True ' }).soundEnabled, true);

  for (const junk of ['yes', 'no', '1', '0', '', '   ', 1, 0, null, undefined, {}, []]) {
    assert.equal(
      Model.normalizeConfig({ soundEnabled: junk }).soundEnabled,
      true,
      `garbage soundEnabled ${JSON.stringify(junk)} falls back to the default`
    );
  }
  assert.equal(Model.normalizeConfig().soundEnabled, true, 'missing config still normalizes');
});

test('sound paths are trimmed and fall back to the defaults', () => {
  assert.equal(
    Model.normalizeConfig({ focusEndSound: '  /tmp/focus.oga  ' }).focusEndSound,
    '/tmp/focus.oga'
  );
  assert.equal(Model.normalizeConfig({ breakEndSound: '\t/tmp/break.wav\n' }).breakEndSound, '/tmp/break.wav');

  const fallbackFocus = 'assets/focus-complete.wav';
  const fallbackBreak = 'assets/break-complete.wav';
  for (const junk of ['', '   ', '\t\n', 42, true, false, null, undefined, {}, []]) {
    const normalized = Model.normalizeConfig({ focusEndSound: junk, breakEndSound: junk });
    assert.equal(normalized.focusEndSound, fallbackFocus);
    assert.equal(normalized.breakEndSound, fallbackBreak);
  }
});

test('soundVolume is rounded and clamped to 0..100', () => {
  assert.equal(Model.normalizeConfig({ soundVolume: 0 }).soundVolume, 0);
  assert.equal(Model.normalizeConfig({ soundVolume: 50 }).soundVolume, 50);
  assert.equal(Model.normalizeConfig({ soundVolume: 100 }).soundVolume, 100);
  assert.equal(Model.normalizeConfig({ soundVolume: -25 }).soundVolume, 0);
  assert.equal(Model.normalizeConfig({ soundVolume: 250 }).soundVolume, 100);
  assert.equal(Model.normalizeConfig({ soundVolume: '75' }).soundVolume, 75);
  assert.equal(Model.normalizeConfig({ soundVolume: 'loud' }).soundVolume, 50);
  assert.equal(Model.normalizeConfig({ soundVolume: 49.4 }).soundVolume, 49, 'fractions round, not truncate');
  assert.equal(Model.normalizeConfig({ soundVolume: 49.5 }).soundVolume, 50);
});

test('soundPathForPhase maps focus and both break phases', () => {
  const config = {
    focusEndSound: '/tmp/focus.oga',
    breakEndSound: '/tmp/break.oga',
  };
  assert.equal(Model.soundPathForPhase('focus', config), '/tmp/focus.oga');
  assert.equal(Model.soundPathForPhase('shortBreak', config), '/tmp/break.oga');
  assert.equal(Model.soundPathForPhase('longBreak', config), '/tmp/break.oga');

  const defaults = Model.defaultConfig();
  assert.equal(Model.soundPathForPhase('focus'), defaults.focusEndSound);
  assert.equal(Model.soundPathForPhase('shortBreak'), defaults.breakEndSound);
  assert.equal(Model.soundPathForPhase('longBreak'), defaults.breakEndSound);
});

test('paplayVolumeArg converts percent to pulse units', () => {
  assert.equal(Model.paplayVolumeArg(0), 0);
  assert.equal(Model.paplayVolumeArg(50), 32768);
  assert.equal(Model.paplayVolumeArg(100), 65536);
  assert.equal(Model.paplayVolumeArg(200), 65536, 'above range clamps to unity gain');
  assert.equal(Model.paplayVolumeArg(-10), 0, 'below range clamps to silence');
  assert.equal(Model.paplayVolumeArg('50'), 32768);
  assert.equal(Model.paplayVolumeArg(25), 16384);
  assert.equal(Model.paplayVolumeArg(33), Math.round(0.33 * 65536));
  assert.equal(Model.paplayVolumeArg(49.4), Math.round(0.494 * 65536), 'fractional percent scales continuously');
  assert.equal(Model.paplayVolumeArg(49.5), Math.round(0.495 * 65536));
  assert.equal(Model.paplayVolumeArg('loud'), 32768, 'garbage falls back to the default volume');
  assert.equal(Model.paplayVolumeArg(null), 32768);
  assert.equal(Model.paplayVolumeArg(undefined), 32768);
  assert.equal(Model.paplayVolumeArg(Number.NaN), 32768);
});

test('sound settings do not disturb phase transitions', () => {
  const noisy = { ...config, soundEnabled: false, focusEndSound: '/tmp/f.oga', soundVolume: 0 };
  const initial = Model.createState(noisy);
  assert.equal(initial.remainingMs, 25 * minute);

  const awaiting = Model.tick(Model.start(initial, 0), 25 * minute);
  assert.equal(awaiting.status, 'awaiting');
  const next = Model.acknowledge(awaiting, 25 * minute, noisy);
  assert.equal(next.phase, 'shortBreak');
  assert.equal(next.remainingMs, 6 * minute);
  assert.equal(Model.durationMs('focus', noisy), 25 * minute);
  assert.equal(Model.durationMs('longBreak', noisy), 31 * minute);
  assert.equal(
    Model.soundPathForPhase(next.phase, noisy),
    'assets/break-complete.wav',
    'breakEndSound was not overridden, so breaks use the default file'
  );
  assert.equal(Model.soundPathForPhase('focus', noisy), '/tmp/f.oga');
  assert.equal(Model.paplayVolumeArg(Model.normalizeConfig(noisy).soundVolume), 0);
});

test('longBreakEvery is rounded and bounded', () => {
  const startState = Model.createState({ ...config, longBreakEvery: 0 });
  assert.equal(startState.completedFocusSessions, 0);
  assert.equal(Model.normalizeConfig({ longBreakEvery: 0 }).longBreakEvery, 1);
  assert.equal(Model.normalizeConfig({ longBreakEvery: 1000 }).longBreakEvery, 100);
  assert.equal(Model.normalizeConfig({ longBreakEvery: 2.6 }).longBreakEvery, 3);
  assert.equal(Model.normalizeConfig({ longBreakEvery: null }).longBreakEvery, 4);
  assert.equal(Model.normalizeConfig({ longBreakEvery: '   ' }).longBreakEvery, 4);

  const normalized = Model.normalizeConfig({
    focusMinutes: null,
    shortBreakMinutes: -1,
    longBreakMinutes: 2000,
  });
  assert.equal(normalized.focusMinutes, 30);
  assert.equal(normalized.shortBreakMinutes, 1);
  assert.equal(normalized.longBreakMinutes, 1440);
});
