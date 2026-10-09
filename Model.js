// Pure Pomodoro state transitions. This file is intentionally plain JavaScript so it
// can be imported by QML with: import "Model.js" as Model

// Volume ceiling used by the sound backend. 100% maps to 65536 because
// paplay treats that value as unity gain rather than a distinct step.
var MAX_VOLUME_ARG = 65536;

function defaultConfig() {
    return {
        focusMinutes: 30,
        shortBreakMinutes: 5,
        longBreakMinutes: 30,
        longBreakEvery: 4,
        soundEnabled: true,
        focusEndSound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
        breakEndSound: "/usr/share/sounds/freedesktop/stereo/bell.oga",
        soundVolume: 50
    };
}

function normalizeConfig(config) {
    var defaults = defaultConfig();
    var source = config || {};

    // The key set and its order stay fixed so Service.qml can compare configs
    // with a plain JSON.stringify.
    return {
        focusMinutes: boundedInteger(source.focusMinutes, defaults.focusMinutes, 1, 1440),
        shortBreakMinutes: boundedInteger(source.shortBreakMinutes, defaults.shortBreakMinutes, 1, 1440),
        longBreakMinutes: boundedInteger(source.longBreakMinutes, defaults.longBreakMinutes, 1, 1440),
        longBreakEvery: boundedInteger(source.longBreakEvery, defaults.longBreakEvery, 1, 100),
        soundEnabled: booleanFlag(source.soundEnabled, defaults.soundEnabled),
        focusEndSound: soundPath(source.focusEndSound, defaults.focusEndSound),
        breakEndSound: soundPath(source.breakEndSound, defaults.breakEndSound),
        soundVolume: boundedInteger(source.soundVolume, defaults.soundVolume, 0, 100)
    };
}

// Only real booleans and the strings "true"/"false" are honoured; every other
// value (numbers, junk strings, missing keys) falls back to the default.
function booleanFlag(value, fallback) {
    if (typeof value === "boolean") {
        return value;
    }
    if (typeof value === "string") {
        var text = value.trim().toLowerCase();
        if (text === "true") {
            return true;
        }
        if (text === "false") {
            return false;
        }
    }
    return fallback;
}

// Sound paths are stored verbatim (after trimming); nothing here touches the
// filesystem, so a missing file is resolved by the player at play time.
function soundPath(value, fallback) {
    if (typeof value !== "string") {
        return fallback;
    }
    var text = value.trim();
    return text === "" ? fallback : text;
}

// Completion sound for a phase: focus has its own file, both breaks share one.
function soundPathForPhase(phase, config) {
    var normalized = normalizeConfig(config);
    if (phase === "focus") {
        return normalized.focusEndSound;
    }
    return normalized.breakEndSound;
}

// paplay expects raw PulseAudio volume units, where 65536 is unity gain.
function paplayVolumeArg(volumePercent) {
    var defaults = defaultConfig();
    var numeric = Number(volumePercent);
    if (volumePercent === null || volumePercent === undefined || volumePercent === "" ||
            (typeof volumePercent === "string" && volumePercent.replace(/\s/g, "") === "") ||
            !isFinite(numeric)) {
        numeric = defaults.soundVolume;
    }
    return Math.max(0, Math.min(MAX_VOLUME_ARG, Math.round(numeric / 100 * MAX_VOLUME_ARG)));
}

function boundedInteger(value, fallback, minimum, maximum) {
    var numeric = Number(value);
    if (value === null || value === undefined || value === "" ||
            (typeof value === "string" && value.replace(/\s/g, "") === "") || !isFinite(numeric)) {
        return fallback;
    }
    numeric = Math.round(numeric);
    return Math.max(minimum, Math.min(maximum, numeric));
}

function durationMs(phase, config) {
    var normalized = normalizeConfig(config);
    var minutes;
    if (phase === "shortBreak") {
        minutes = normalized.shortBreakMinutes;
    } else if (phase === "longBreak") {
        minutes = normalized.longBreakMinutes;
    } else {
        minutes = normalized.focusMinutes;
    }
    return minutes * 60 * 1000;
}

function validNow(now) {
    var numeric = Number(now);
    return isFinite(numeric) ? numeric : 0;
}

function remainingValue(state) {
    var numeric = Number(state.remainingMs);
    return isFinite(numeric) ? Math.max(0, numeric) : 0;
}

function createState(config) {
    return {
        phase: "focus",
        status: "idle",
        remainingMs: durationMs("focus", config),
        deadlineMs: null,
        completedFocusSessions: 0
    };
}

function currentRemainingMs(state, now) {
    if (!state) {
        return 0;
    }
    if (state.status === "running") {
        var deadline = Number(state.deadlineMs);
        if (!isFinite(deadline)) {
            return 0;
        }
        return Math.max(0, deadline - validNow(now));
    }
    return remainingValue(state);
}

function copyState(state, changes) {
    var next = {
        phase: state.phase,
        status: state.status,
        remainingMs: state.remainingMs,
        deadlineMs: state.deadlineMs,
        completedFocusSessions: state.completedFocusSessions
    };
    var key;
    for (key in changes) {
        if (Object.prototype.hasOwnProperty.call(changes, key)) {
            next[key] = changes[key];
        }
    }
    return next;
}

function start(state, now) {
    if (!state || state.status === "running" || state.status === "awaiting") {
        return state;
    }
    var remaining = remainingValue(state);
    return copyState(state, {
        status: "running",
        remainingMs: remaining,
        deadlineMs: validNow(now) + remaining
    });
}

function pause(state, now) {
    if (!state || state.status !== "running") {
        return state;
    }
    var remaining = currentRemainingMs(state, now);
    return copyState(state, {
        status: remaining <= 0 ? "awaiting" : "paused",
        remainingMs: remaining,
        deadlineMs: null
    });
}

function tick(state, now) {
    if (!state || state.status !== "running") {
        return state;
    }
    var remaining = currentRemainingMs(state, now);
    if (remaining <= 0) {
        return copyState(state, {
            status: "awaiting",
            remainingMs: 0,
            deadlineMs: null
        });
    }
    return state;
}

function nextPhase(state, now, config, completedFocusSessions) {
    var phase;
    if (state.phase === "focus") {
        phase = completedFocusSessions > 0 &&
            completedFocusSessions % normalizeConfig(config).longBreakEvery === 0
            ? "longBreak"
            : "shortBreak";
    } else {
        phase = "focus";
    }
    var remaining = durationMs(phase, config);
    return {
        phase: phase,
        status: "running",
        remainingMs: remaining,
        deadlineMs: validNow(now) + remaining,
        completedFocusSessions: completedFocusSessions
    };
}

function acknowledge(state, now, config) {
    if (!state || state.status !== "awaiting") {
        return state;
    }
    var completed = Number(state.completedFocusSessions) || 0;
    if (state.phase === "focus") {
        completed += 1;
    }
    return nextPhase(state, now, config, completed);
}

function skip(state, now, config) {
    if (!state) {
        return state;
    }
    var completed = Number(state.completedFocusSessions) || 0;
    if (state.status === "awaiting" && state.phase === "focus") {
        completed += 1;
    }
    return nextPhase(state, now, config, completed);
}

function restart(state, now, config) {
    if (!state) {
        return state;
    }
    var remaining = durationMs(state.phase, config);
    return copyState(state, {
        status: "running",
        remainingMs: remaining,
        deadlineMs: validNow(now) + remaining
    });
}

function suspendResume(now, config, previousState) {
    var remaining = durationMs("focus", config);
    return {
        phase: "focus",
        status: "running",
        remainingMs: remaining,
        deadlineMs: validNow(now) + remaining,
        completedFocusSessions: previousState
            ? Math.max(0, Math.floor(Number(previousState.completedFocusSessions) || 0))
            : 0
    };
}
