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

The repeating cycle is focus → short break → focus, with a long break after every fourth completed focus session. A phase that reaches zero waits for acknowledgment; acknowledging it starts the next phase. A configured long break replaces the short break after the fourth, eighth, and subsequent fourth completed focus sessions. Skipping a running or paused focus phase does not count it as completed; skipping a focus phase that has already reached zero does count it.

The widget displays a phase indicator and remaining time in `MM:SS` format (the minute field can exceed two digits for long durations). Click the bar widget to open its panel. The panel controls are:

- **Start / Pause / Resume** — start an idle timer, pause a running timer, or resume a paused timer.
- **Acknowledge & continue** — after a phase ends, acknowledge it and start the next phase.
- **Skip** — advance to the next phase immediately.
- **Restart** — restart the current phase at its full configured duration.

The four integer settings are declared in the manifest and can be changed in the popup or through Omarchy's bar settings, for example:

```bash
omarchy bar set emo333.pomodarchy focusMinutes 45 --json
omarchy bar set emo333.pomodarchy shortBreakMinutes 8 --json
```

Durations accept integer minutes from 1 to 1440; `longBreakEvery` accepts an integer from 1 to 100.

## Restart, suspend, and assumptions

Timer state is held in memory, not saved to disk. Restarting the Omarchy shell or rebooting resets the timer to a fresh idle focus phase; there is no session history. On system suspend, the current phase is abandoned. When the system resumes, a fresh focus phase starts immediately, without crediting the interrupted phase as completed.

The behavior and scope are explicitly:

- **Notifications only:** phase completion sends one desktop notification; the plugin does not play or request sound and does not repeat notifications. Notifications go through the desktop service, which applies its normal Do Not Disturb and sound behavior.
- **Idle and activity are independent:** idle time, lock state, active application, and workspace do not automatically pause or resume the timer.
- **No history:** session progress is runtime state only; no persistent history, reports, or streaks are kept.
- **Compact display:** show the phase indicator and `MM:SS` countdown.

## Dependencies and security

The service depends on `dbus-monitor` to detect suspend/resume, `busctl` to recover the current sleep state if the monitor restarts, and `notify-send` to send phase-completion notifications. These commands must be available in `PATH`; notifications also depend on a working desktop notification service. The shared timer service requires the built-in Omarchy bar's own-plugin service API; third-party replacement bars that expose a service-less API are not supported.

**Omarchy plugins are unsandboxed.** Plugin QML and JavaScript run inside the long-lived `omarchy-shell` process and can run with your user permissions; installing a plugin is not an isolation boundary. Review all shipped code—including process invocation and file access—before installing or enabling it. Omarchy validation checks manifest requirements, safe relative entrypoints, and file presence, and rejects symlinks in the plugin source tree (excluding `.git`). It is not a code or runtime security audit and does not validate QML syntax.

## Development and validation

From the repository root:

```bash
# Check basic manifest requirements and that declared entrypoint files exist.
omarchy plugin validate .

# Run the pure timer-model test suite with Node.js.
node --test
```

The Node tests cover configuration normalization and timer phase transitions. Omarchy validation checks the manifest and declared entrypoint paths/files; it does not load the QML or verify the plugin at runtime.

## License

MIT. See [LICENSE.md](LICENSE.md).
