# Pomodarchy

Pomodarchy is a configurable Pomodoro timer for the Omarchy bar. `BarWidget.qml` displays the current phase and remaining time, `PomodoroPanel.qml` provides controls, and the shared `Service.qml` owns timer state.

## Install

The GitHub repository `emo333/pomodarchy` has not been created yet. These install commands will work once the plugin has been published there.

On Omarchy, add the Git repository and enable the plugin:

```bash
omarchy plugin add https://github.com/emo333/pomodarchy --enable
```

The `.git` URL form works too:

```bash
omarchy plugin add https://github.com/emo333/pomodarchy.git --enable
```

Omarchy asks you to confirm before cloning a third-party plugin. Read the security note below and review the source on GitHub first, or use the manual review path below. To add it without enabling, omit `--enable` and decline Omarchy's follow-up enable prompt. Enable it later with:

```bash
omarchy plugin enable emo333.pomodarchy
```

To specify the right section explicitly, use `omarchy plugin enable emo333.pomodarchy --section right`.

## Manual review and installation

Clone the repository somewhere outside the Omarchy plugin directory and inspect the manifest and all plugin source files before installing:

```bash
git clone https://github.com/emo333/pomodarchy.git
cd pomodarchy
less manifest.json
# Review BarWidget.qml, PomodoroPanel.qml, Service.qml, Model.js, and all other shipped code.
omarchy plugin validate .
```

After validation and review, install the folder and enable it:

```bash
mkdir -p ~/.config/omarchy/plugins
install -d ~/.config/omarchy/plugins/emo333.pomodarchy
install -m644 manifest.json BarWidget.qml PomodoroPanel.qml Service.qml Model.js LICENSE.md README.md \
  ~/.config/omarchy/plugins/emo333.pomodarchy/
omarchy-shell shell rescanPlugins
# Wait until `omarchy plugin list` shows emo333.pomodarchy, then enable it.
omarchy plugin enable emo333.pomodarchy --section right
```

`omarchy plugin enable` adds the bar widget in the right section by default; the explicit section above makes that placement clear. The manifest also declares `right` as its default section.

## Timer behavior

The default configuration is:

| Setting | Default |
| --- | ---: |
| Focus | 30 minutes |
| Short break | 5 minutes |
| Long break | 30 minutes |
| Focus sessions before a long break | 4 |
| Completion sound | on |
| Focus end sound | `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga` |
| Break end sound | `/usr/share/sounds/freedesktop/stereo/bell.oga` |
| Completion sound volume | 50% |

The repeating cycle is focus → short break → focus, with a long break after every fourth completed focus session. A phase that reaches zero waits for acknowledgment; acknowledging it starts the next phase. A configured long break replaces the short break after the fourth, eighth, and subsequent fourth completed focus sessions. Skipping a running or paused focus phase does not count it as completed; skipping a focus phase that has already reached zero does count it.

The widget displays a phase indicator and remaining time in `MM:SS` format (the minute field can exceed two digits for long durations). Click the bar widget to open its panel. The panel controls are:

- **Start / Pause / Resume** — start an idle timer, pause a running timer, or resume a paused timer.
- **Acknowledge & continue** — after a phase ends, acknowledge it and start the next phase.
- **Skip** — advance to the next phase immediately.
- **Restart** — restart the current phase at its full configured duration.
- **Completion sound** — toggle the end-of-phase clip, set its volume in 5% steps, and preview the focus clip with **Test sound**. See [Completion sound](#completion-sound).
- **More actions** — reveals Skip and Restart.

All eight settings are declared in the manifest schema that Omarchy's bar settings read, so any of them can be set from a terminal with `omarchy bar set`. The durations, the sound toggle, and the volume also have controls in the popup; the two clip paths have no popup control:

```bash
omarchy bar set emo333.pomodarchy focusMinutes 45 --json
omarchy bar set emo333.pomodarchy shortBreakMinutes 8 --json
```

Durations accept integer minutes from 1 to 1440; `longBreakEvery` accepts an integer from 1 to 100.

## Completion sound

When a phase reaches zero the plugin plays a completion clip and sends one desktop notification. The clip depends on the phase type: a focus phase uses `focusEndSound`, and both short and long breaks use `breakEndSound`. By default those are two different files from the freedesktop sound theme (`alarm-clock-elapsed.oga` for focus, `bell.oga` for breaks).

The sound plays exactly once per completed phase and never repeats, matching the single notification. A sound that fails to play is ignored: a missing file, an unreachable audio server, or a missing `paplay` binary produces no output and no error, and never affects the timer, the notification, or the popup.

Four settings control it:

| Setting | Type | Default |
| --- | --- | --- |
| `soundEnabled` | boolean | `true` |
| `focusEndSound` | path | `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga` |
| `breakEndSound` | path | `/usr/share/sounds/freedesktop/stereo/bell.oga` |
| `soundVolume` | integer 0–100, step 5 | `50` |

In the popup, a **Completion sound** toggle switches sound on and off, and a **Volume** row moves in 5% steps. **Test sound** plays the focus-end clip through exactly the same gates as a real completion, so the button is disabled while sound is off or Do Not Disturb is on; it always previews the focus clip, not the break clip. The popup has no control for the two clip paths, so set them through the bar settings or from a terminal:

```bash
omarchy bar set emo333.pomodarchy soundEnabled false
omarchy bar set emo333.pomodarchy soundVolume 80 --json
omarchy bar set emo333.pomodarchy focusEndSound /home/you/Sounds/chime.oga
omarchy bar set emo333.pomodarchy breakEndSound /home/you/Sounds/done.oga
```

Only non-default values are written into `shell.json`. The defaults include absolute paths to system sound files, so persisting them would bake this machine's file layout into your config and a single duration tweak would rewrite them. A value that returns to its default disappears from the config entry again.

### Do Not Disturb

A third-party plugin does not call Omarchy's notifications service. Instead the timer reads the state that service persists: the `dnd` key of the notifications state file. Omarchy's own notification daemon writes `$HOME/.local/state/omarchy/notifications.json` unconditionally; the plugin prefers `$XDG_STATE_HOME/omarchy/notifications.json` when `XDG_STATE_HOME` is set and falls back to the `$HOME` path when that one cannot be read. On the usual setup the two are the same file. The file is watched and re-read every 5 seconds.

This is a **best-effort check, not an integration with the notifications service**:

- Only a parseable `dnd: true` (or the string `"true"`) suppresses the sound.
- A missing file (a fresh install), an unreadable one, malformed JSON, or any other `dnd` value resolves to "not muted", so the sound plays. The plugin never blocks its own sound on a value it could not read.
- The sound does not bypass Do Not Disturb: when `dnd` is true the clip is suppressed, exactly like the notification.
- A notification daemon other than Omarchy's keeps its Do Not Disturb state somewhere else — mako, dunst, and friends write no `notifications.json` — so such setups are simply not detected and the sound still plays.
- The plugin only ever reads this file; it never writes to it.

### Playback backend

Playback uses `paplay`, the PulseAudio client (`libpulse` on Arch, which talks to `pipewire-pulse`), with `soundVolume` converted from a percentage to PulseAudio volume units (100% is 65536, the unity gain value). Whether `paplay` exists is probed **once per shell session**, lazily, on the first sound request; the result is then cached for the rest of that session. Installing `paplay` while the shell is running therefore needs an `omarchy-restart-shell` to be picked up.

The default clips ship with the freedesktop sound theme (`sound-theme-freedesktop`). On a system without that package the default paths do not exist, nothing plays, and no error is shown — point `focusEndSound` and `breakEndSound` at your own files, or install the theme.

## IPC

The bar widget registers a Quickshell IPC target named `emo333.pomodarchy`. Call it through the running shell instance with `quickshell ipc` (the `quickshell` package also installs `qs` as a shorter alias):

```bash
quickshell ipc -p /usr/share/omarchy/shell call emo333.pomodarchy toggle
quickshell ipc -p /usr/share/omarchy/shell call emo333.pomodarchy previewSound
quickshell ipc -p /usr/share/omarchy/shell call emo333.pomodarchy dndState
```

The `-p` path is the running shell's config directory, which is how `qs ipc` finds the instance to ask; without it the call does not reach the plugin.

| Handler | Effect |
| --- | --- |
| `open`, `show` | open the popup |
| `close`, `hide` | close the popup |
| `toggle` | open the popup if closed, close it if open |
| `start`, `pause`, `resume` | timer control |
| `acknowledge`, `skip`, `restart` | phase control |
| `previewSound` | play the focus-end clip now, through the same gates as a completion |
| `dndState` | returns `on`, `off`, or `unavailable` when the service is not reachable |
| `status` | returns JSON with the phase, status, remaining milliseconds, and current config |

The handlers live in `BarWidget.qml` because a second `IpcHandler` for the same target is rejected by Quickshell, so they delegate to the shared service. That means IPC needs the bar widget loaded (the plugin enabled and on the bar); `dndState` answers `unavailable` and `status` returns `unavailable` when the service itself is not reachable.

## Restart, suspend, and assumptions

Timer state is held in memory, not saved to disk. Restarting the Omarchy shell or rebooting resets the timer to a fresh idle focus phase; there is no session history. On system suspend, the current phase is abandoned. When the system resumes, a fresh focus phase starts immediately, without crediting the interrupted phase as completed.

The behavior and scope are explicitly:

- **One alert per phase:** phase completion plays a single completion clip (a distinct file for focus versus breaks) and sends one desktop notification. Neither repeats. The sound is suppressed while Do Not Disturb is detected, using the best-effort check described above; the notification still goes through the desktop service, which applies its own Do Not Disturb behavior.
- **Idle and activity are independent:** idle time, lock state, active application, and workspace do not automatically pause or resume the timer.
- **No history:** session progress is runtime state only; no persistent history, reports, or streaks are kept.
- **Compact display:** show the phase indicator and `MM:SS` countdown.

## Dependencies and security

The service depends on `dbus-monitor` to detect suspend/resume, `busctl` to recover the current sleep state if the monitor restarts, `notify-send` to send phase-completion notifications, and `paplay` (the PulseAudio client from `libpulse`, talking to `pipewire-pulse`) to play completion sounds. These commands must be available in `PATH`; notifications also depend on a working desktop notification service, and sound additionally needs a reachable audio server. The default clips come with the freedesktop sound theme (`sound-theme-freedesktop`), so a system without it needs custom `focusEndSound`/`breakEndSound` paths. The shared timer service requires the built-in Omarchy bar's own-plugin service API; third-party replacement bars that expose a service-less API are not supported.

**Omarchy plugins are unsandboxed.** Plugin QML and JavaScript run inside the long-lived `omarchy-shell` process and can run with your user permissions; installing a plugin is not an isolation boundary. Review all shipped code—including process invocation and file access—before installing or enabling it. Omarchy validation checks manifest requirements, safe relative entrypoints, and file presence, and rejects symlinks in the plugin source tree (excluding `.git`). It is not a code or runtime security audit and does not validate QML syntax.

## Development and validation

From the repository root:

```bash
# Check basic manifest requirements and that declared entrypoint files exist.
omarchy plugin validate .

# Run the pure timer-model test suite with Node.js.
node --test
```

The Node tests cover configuration normalization, timer phase transitions, and the sound settings helpers (default clips, path fallback, volume clamping, percent-to-PulseAudio conversion, and phase-to-clip mapping). Omarchy validation checks the manifest and declared entrypoint paths/files; it does not load the QML or verify the plugin at runtime.

## License

MIT. See [LICENSE.md](LICENSE.md).
