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
