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

On phase completion, play a completion clip and send one desktop notification. The clip is chosen by phase type: a focus phase plays `focusEndSound`, and both short and long breaks play `breakEndSound`, with defaults pointing at two different freedesktop sound theme clips. Sound is suppressed when Do Not Disturb is detected (best effort, read from Omarchy's notifications state file). Neither the sound nor the notification repeats. The user must acknowledge the phase in the popup to continue.

### Sound settings

- `soundEnabled` (boolean, default on) toggles end-of-phase sound in the popup and is the master gate for playback.
- `focusEndSound` and `breakEndSound` are absolute file paths, defaulting to `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga` and `/usr/share/sounds/freedesktop/stereo/bell.oga`.
- `soundVolume` (integer 0–100, step 5, default 50) is converted to PulseAudio volume units for `paplay`.
- Popup controls: a sound toggle, a 5% volume stepper, and a **Test sound** button that previews the focus clip through the same gates as a real completion. The two clip paths have no popup control and are set through the bar settings or `omarchy bar set`.
- Only non-default values are persisted, so absolute default paths are never written into `shell.json`.

## Technical design

- `manifest.json`: plugin metadata, settings defaults/schema (durations plus the four sound settings), and `bar-widget` plus `service` entry points.
- `Service.qml`: one shared in-memory timer service with a single ticking timer, lifecycle handling, notification, and completion-sound playback. `keepLoaded` keeps it alive across plugin hot reloads while the shell remains running.
- `Model.js`: pure state-transition functions plus the pure sound helpers (defaults, normalization, phase-to-clip mapping, percent-to-PulseAudio conversion), tested independently with Node.js.
- `BarWidget.qml`: bar label and popup host. It reads the service through its scoped plugin API; it does not own timer state. It also hosts the `emo333.pomodarchy` IPC target, including `previewSound` and `dndState`, because a second `IpcHandler` for the same target is rejected by Quickshell.
- `PomodoroPanel.qml`: timer controls, duration settings, and the sound toggle, volume stepper, and Test sound button.
- Suspend detection uses logind's `PrepareForSleep` signal via `dbus-monitor`, with `busctl` to reconcile sleep state if the monitor restarts. `notify-send` sends notifications; `paplay` (the PulseAudio client from `libpulse`, talking to `pipewire-pulse`) plays the completion clip, with availability probed once per shell session. Every playback path is best effort: a disabled toggle, Do Not Disturb, a missing file, a dead audio server, or a missing binary all mean no sound and no state change.
- Do Not Disturb is read from the `dnd` key of the notifications state file that Omarchy's notification daemon persists (`$HOME/.local/state/omarchy/notifications.json`, with `$XDG_STATE_HOME/omarchy/notifications.json` tried first and the `$HOME` path as fallback), watched and polled every 5 seconds. Only a parseable `true` suppresses sound; a missing, unreadable, or malformed file resolves to "not muted". A non-Omarchy notification daemon stores DND elsewhere and is not detected.
- The plugin depends on Omarchy/Quickshell, `dbus-monitor`, `busctl`, `notify-send`, `paplay`, and a working desktop notification service. The default clips come from the freedesktop sound theme. The installed Omarchy bar must expose the plugin's own service API; service-less third-party replacement bars may not support this widget.

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
- **D7:** Sound policy: one distinct clip per phase type (focus versus break), configurable paths with freedesktop sound theme defaults, `paplay` playback at a configurable volume, suppressed when Do Not Disturb is detected, one shot per phase, never repeating.
- **D8:** Phase indicator and `MM:SS` countdown; popup includes status and settings.
- **D9:** No persistent history; settings in popup and Omarchy's inline widget settings.
- **D10:** This repository is the plugin for GitHub project `emo333/pomodarchy`; the public install URL will work after the repository is created.

## Implementation and validation status

- **Complete:** manifest, README, license metadata, pure timer model, Node tests, shared QML service, bar widget, popup, duration and sound settings, IPC (including `previewSound` and `dndState`), notifications, completion sound with Do Not Disturb suppression, and suspend monitoring.
- **Validated:** `omarchy plugin validate .`; all 16 Node model tests pass; `qmllint` passes `Service.qml` and `PomodoroPanel.qml`. The local `qmllint` exits 255 on `BarWidget.qml`, which uses typed `IpcHandler` signatures found in installed Omarchy examples. LSP reports no diagnostics for the QML files.
- **Remaining:** Test runtime behavior in Omarchy, especially multi-monitor synchronization, suspend/resume, settings persistence, service access through the built-in bar, and that the phase-end clip is audible at the configured volume and silent under Do Not Disturb. Create the GitHub repository and push this source before treating installation as live.

## Acceptance criteria

- Timer transitions follow the configured focus/short-break/long-break sequence and wait for acknowledgment at phase end.
- All widget instances display the same service state while the shell runs.
- Shell restart/reboot resets the timer; suspend ends the current phase and resume starts a fresh focus phase immediately.
- Completion plays one clip (distinct per phase type) and sends one notification; neither repeats.
- The sound is suppressed while Do Not Disturb is detected, and an unreadable DND state leaves sound enabled rather than muting silently.
- `soundEnabled`, `focusEndSound`, `breakEndSound`, and `soundVolume` are declared in the manifest with matching defaults, settable through `omarchy bar set` and, for the toggle and volume, in the popup; only non-default values reach `shell.json`.
- Activity and lock state do not otherwise change timer behavior.
- Manifest validation and model tests pass, and the plugin does not modify Omarchy's packaged files.
- Installation from GitHub succeeds after the repository is published.
