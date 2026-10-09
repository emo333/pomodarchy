# Pomodoro Omarchy Quickshell Widget: Initial Plan

**Status:** Initial implementation is in place. QML runtime testing and publication remain.  
**Repository role:** This repository is the plugin source intended for `https://github.com/emo333/pomodarchy`.

## Goal

Provide a configurable Pomodoro timer in the Omarchy bar with a popup for controls and duration settings. All bar instances share one timer. The plugin follows Omarchy's third-party plugin API and can be installed from this GitHub repository after it is published.

## Product specification

### Surface and controls

- Show a compact phase indicator and remaining time in `MM:SS` in the bar.
- Clicking the bar widget opens the popup.
- The popup provides Start, Pause, Resume, and Acknowledge & continue.
- Acknowledge & continue advances to and starts the next phase.
- Skip and Restart are secondary actions under More actions.
- No scroll controls, global shortcuts, or desktop-pinned widget in the first version.

### Session sequence and configuration

- Defaults: 30-minute focus, 5-minute short break, and 30-minute long break.
- After every four completed focus sessions, use a long break instead of a short break.
- The cycle repeats. A phase that reaches zero waits for acknowledgment before advancing.
- Durations and long-break cadence are configurable in the popup and Omarchy's inline bar settings. Values are integer minutes, bounded to 1–1440; cadence is 1–100 focus sessions.
- No task labels, persistent history, reports, or streaks in the first version.

### Lifecycle and attention behavior

- Timer state is in memory. Shell restart or reboot resets to a fresh idle focus phase.
- On suspend, end the current phase. On resume, immediately start a fresh focus phase. The interrupted phase does not count as completed; the completed-focus count is retained.
- Idle time, lock state, active application, and workspace do not pause or resume the timer.

### Phase-end feedback

Send one desktop notification when a phase reaches zero. Do not play sound or repeat alerts in the plugin. Notifications go through the desktop notification service, which applies its normal Do Not Disturb and sound behavior. The user must acknowledge the phase in the popup to continue.

## Technical design

- `manifest.json`: plugin metadata, settings defaults/schema, and `bar-widget` plus `service` entry points.
- `Service.qml`: one shared in-memory timer service with a single ticking timer, lifecycle handling, notification, and IPC controls. `keepLoaded` keeps it alive across plugin hot reloads while the shell remains running.
- `Model.js`: pure state-transition functions, tested independently with Node.js.
- `BarWidget.qml`: bar label and popup host. It reads the service through its scoped plugin API; it does not own timer state.
- `PomodoroPanel.qml`: timer controls and duration settings.
- Suspend detection uses logind's `PrepareForSleep` signal via `dbus-monitor`, with `busctl` to reconcile sleep state if the monitor restarts. `notify-send` sends notifications.
- The plugin depends on Omarchy/Quickshell, `dbus-monitor`, `busctl`, `notify-send`, and a working desktop notification service. The installed Omarchy bar must expose the plugin's own service API; service-less third-party replacement bars may not support this widget.

Do not edit `/usr/share/omarchy/`. Omarchy plugins are unsandboxed code, so review all plugin source before installing or enabling it.

## Packaging and publication

- Plugin ID: `emo333.pomodarchy`.
- Repository: `https://github.com/emo333/pomodarchy` (not created yet).
- License: MIT (`LICENSE.md`).
- Install after publication with `omarchy plugin add https://github.com/emo333/pomodarchy --enable`.
- The manifest validates locally with `omarchy plugin validate .`.

## Decisions

- **D1:** Bar and popup, no persistent desktop widget.
- **D2:** The plugin owns timer state.
- **D3:** Reset after shell restart/reboot. Suspend ends the current phase; resume starts a fresh focus phase immediately.
- **D4:** Configurable 30/5-minute focus and short-break defaults; 30-minute long break after four completed focus sessions; acknowledgment starts the next phase; repeat the cycle.
- **D5:** Bar click opens popup; primary controls in popup; Skip and Restart under More actions; no scroll or global shortcuts.
- **D6:** Activity and idle state do not affect the timer.
- **D7:** One notification per completed phase; no plugin sound or repeat.
- **D8:** Phase indicator and `MM:SS` countdown; popup includes status and settings.
- **D9:** No persistent history; settings in popup and Omarchy's inline widget settings.
- **D10:** This repository is the plugin for GitHub project `emo333/pomodarchy`; the public install URL will work after the repository is created.

## Implementation and validation status

- **Complete:** manifest, README, license metadata, pure timer model, Node tests, shared QML service, bar widget, popup, settings, IPC, notifications, and suspend monitoring.
- **Validated:** `omarchy plugin validate .`; all 9 Node model tests pass; `qmllint` passes `Service.qml` and `PomodoroPanel.qml`. The local `qmllint` exits 255 on `BarWidget.qml`, which uses typed `IpcHandler` signatures found in installed Omarchy examples. LSP reports no diagnostics for the QML files.
- **Remaining:** Test runtime behavior in Omarchy, especially multi-monitor synchronization, suspend/resume, settings persistence, and service access through the built-in bar. Create the GitHub repository and push this source before treating installation as live.

## Acceptance criteria

- Timer transitions follow the configured focus/short-break/long-break sequence and wait for acknowledgment at phase end.
- All widget instances display the same service state while the shell runs.
- Shell restart/reboot resets the timer; suspend ends the current phase and resume starts a fresh focus phase immediately.
- Completion sends one notification. Activity and lock state do not otherwise change timer behavior.
- Manifest validation and model tests pass, and the plugin does not modify Omarchy's packaged files.
- Installation from GitHub succeeds after the repository is published.
