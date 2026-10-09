// Pure Pomodoro state transitions. This file is intentionally plain JavaScript so it
// can be imported by QML with: import "Model.js" as Model

function defaultConfig() {
    return {
        focusMinutes: 30,
        shortBreakMinutes: 5,
        longBreakMinutes: 30,
        longBreakEvery: 4
    };
}

function normalizeConfig(config) {
    var defaults = defaultConfig();
    var source = config || {};

    return {
        focusMinutes: boundedInteger(source.focusMinutes, defaults.focusMinutes, 1, 1440),
        shortBreakMinutes: boundedInteger(source.shortBreakMinutes, defaults.shortBreakMinutes, 1, 1440),
        longBreakMinutes: boundedInteger(source.longBreakMinutes, defaults.longBreakMinutes, 1, 1440),
        longBreakEvery: boundedInteger(source.longBreakEvery, defaults.longBreakEvery, 1, 100)
    };
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
