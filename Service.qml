import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

QtObject {
  id: root

  // Injected by Omarchy's third-party plugin service loader.
  property var shell: null

  property var config: Model.defaultConfig()
  property var state: Model.createState(config)
  property double now: Date.now()
  property bool suspended: false
  property bool awaitingSleepValue: false
  property int sleepSignalRevision: 0
  property int sleepProbeRevision: 0
  property bool sleepMonitorInterrupted: true
  property double sleepProbeAt: 0
  property double monitorRestartAt: 0

  readonly property real remainingMs: Model.currentRemainingMs(state, now)
  readonly property int remainingSeconds: Math.max(0, Math.ceil(remainingMs / 1000))
  readonly property string remainingText: formatTime(remainingSeconds)
  readonly property string phaseLabel: labelForPhase(state ? state.phase : "focus")
  readonly property string statusLabel: labelForStatus(state ? state.status : "idle")

  // ------------------------------------------------ do not disturb (read-only)
  //
  // DND is read from the state file the daemon persists rather than by
  // querying it over IPC. In-process cross-plugin IPC is scoped to a plugin's
  // own id, and the daemon's id is not fixed anyway: the stock build is
  // `omarchy.notifications`, but a user clone (for example
  // `mitch.notifications`) answers to its own id instead. The state file path
  // is the same either way. See applyDndState() for the unknown-value policy.
  //
  // Omarchy's own notification daemon writes this file. A different daemon
  // (mako, dunst, ...) keeps its DND somewhere else, so nothing is written
  // here and this stays false - such setups are simply not detected.
  //
  // XDG_STATE_HOME is the primary candidate, but the notifications service
  // actually writes $HOME/.local/state/omarchy/notifications.json
  // unconditionally, so with a relocated XDG_STATE_HOME the primary path does
  // not exist and the HOME path is used instead. On the usual setup the two
  // are the same file.
  readonly property string dndPrimaryPath: {
    var stateHome = Quickshell.env("XDG_STATE_HOME")
    if (!stateHome) return ""
    return String(stateHome) + "/omarchy/notifications.json"
  }
  readonly property string dndFallbackPath: String(Quickshell.env("HOME"))
    + "/.local/state/omarchy/notifications.json"
  // dndFile reads this; it starts on the primary candidate and falls back to
  // HOME once, if the primary turns out to be unreadable.
  property string dndActivePath: root.dndPrimaryPath || root.dndFallbackPath
  property bool dndFallbackScheduled: false
  // Backing store for doNotDisturb. Private: only applyDndState() writes it.
  property bool muted: false
  readonly property alias doNotDisturb: root.muted

  // paplay availability is probed once, lazily, on the first play request.
  property bool paplayChecked: false
  property bool paplayAvailable: false
  property string pendingSoundPath: ""
  property int pendingSoundVolume: 0

  function labelForPhase(phase) {
    if (phase === "shortBreak") return "Short break"
    if (phase === "longBreak") return "Long break"
    return "Focus"
  }

  function labelForStatus(status) {
    if (status === "running") return "Running"
    if (status === "paused") return "Paused"
    if (status === "awaiting") return "Complete"
    return "Ready"
  }

  function formatTime(totalSeconds) {
    var minutes = Math.floor(totalSeconds / 60)
    var seconds = totalSeconds % 60
    return (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
  }

  function commitState(nextState, timestamp) {
    var previousState = root.state
    root.state = nextState
    root.now = timestamp

    if (previousState && previousState.status === "running" &&
        nextState && nextState.status === "awaiting") {
      root.notifyExpiry(previousState.phase)
      // Independent of the notification above: a sound that cannot play is
      // not an error, and must not disturb either the toast or the timer.
      root.playPhaseSound(previousState.phase)
    }
  }

  function tick() {
    var timestamp = Date.now()

    // Check the gap before restarting the monitor, while its uncovered period
    // is still observable.
    if (!root.suspended && root.recoverMissedSleep(timestamp)) return

    if (root.monitorRestartAt > 0 && timestamp >= root.monitorRestartAt) {
      root.monitorRestartAt = 0
      if (!sleepMonitor.running) sleepMonitor.running = true
      root.sleepProbeAt = timestamp + 500
    }
    if (root.sleepProbeAt > 0 && timestamp >= root.sleepProbeAt) {
      root.sleepProbeAt = 0
      root.requestSleepProbe()
    }

    if (root.suspended) {
      // A property check is a fallback in case the monitor lost the resume
      // signal while restarting.
      root.requestSleepProbe()
      return
    }

    if (!root.state || root.state.status !== "running") {
      root.now = timestamp
      return
    }
    root.commitState(Model.tick(root.state, timestamp), timestamp)
  }

  function start() {
    var timestamp = Date.now()
    root.commitState(Model.start(root.state, timestamp), timestamp)
  }

  function pause() {
    var timestamp = Date.now()
    root.commitState(Model.pause(root.state, timestamp), timestamp)
  }

  function resume() {
    root.start()
  }

  function acknowledge() {
    var timestamp = Date.now()
    root.commitState(Model.acknowledge(root.state, timestamp, root.config), timestamp)
  }

  function skip() {
    var timestamp = Date.now()
    root.commitState(Model.skip(root.state, timestamp, root.config), timestamp)
  }

  function restart() {
    var timestamp = Date.now()
    root.commitState(Model.restart(root.state, timestamp, root.config), timestamp)
  }

  // Config changes apply to the next phase. An idle or paused timer adopts the
  // selected duration immediately; an active deadline is left untouched.
  function configure(values) {
    var nextConfig = Model.normalizeConfig(values)
    if (JSON.stringify(nextConfig) === JSON.stringify(root.config)) return

    root.config = nextConfig
    var timestamp = Date.now()
    if (root.state.status === "idle") {
      root.state = Model.createState(nextConfig)
    } else if (root.state.status === "paused") {
      root.state = {
        phase: root.state.phase,
        status: "paused",
        remainingMs: Model.durationMs(root.state.phase, nextConfig),
        deadlineMs: null,
        completedFocusSessions: root.state.completedFocusSessions
      }
    }
    root.now = timestamp
  }

  // ------------------------------------------------------------ sound playback
  //
  // paplay, the PulseAudio client from libpulse, plays one clip; it talks to
  // the pipewire-pulse server when that is what is running. Every path here is
  // best effort:
  // a disabled toggle, DND, a missing file, a dead audio server or a missing
  // binary all mean the same thing - no sound, no output, no state change.

  function playPhaseSound(phase) {
    root.playSound(Model.soundPathForPhase(phase, root.config))
  }

  // Model defaults are relative to the plugin. Resolve them against this QML
  // file, while keeping user-selected absolute paths intact. Convert the
  // resolved QML URL (including file URLs from path choosers) to a local path.
  function resolveSoundPath(path) {
    var value = String(path || "").trim()
    if (value === "") return ""
    if (value.charAt(0) === "/") return value

    var resolved
    try {
      resolved = new URL(String(Qt.resolvedUrl(value)))
    } catch (error) {
      return ""
    }
    if (resolved.protocol !== "file:" ||
        (resolved.hostname !== "" && resolved.hostname !== "localhost")) return ""

    try {
      return decodeURIComponent(resolved.pathname)
    } catch (error) {
      return ""
    }
  }

  // Manual "Test sound": the same gates as a real completion, so a custom
  // path is verified exactly as it will behave in production.
  function previewSound() {
    root.playPhaseSound("focus")
  }

  function playSound(path) {
    var target = root.resolveSoundPath(path)
    if (target === "") return

    var config = Model.normalizeConfig(root.config)
    if (!config.soundEnabled || root.doNotDisturb) return

    if (root.paplayChecked) {
      if (root.paplayAvailable) root.startPaplay(target, config.soundVolume)
      return
    }

    // First request of the session: resolve the binary once, then play.
    root.pendingSoundPath = target
    root.pendingSoundVolume = config.soundVolume
    if (!paplayProbe.running) paplayProbe.running = true
  }

  function startPaplay(path, volumePercent) {
    // exec() instead of `running = true`: it stops any clip still playing
    // first, so a second "Test sound" click restarts the sound rather than
    // being ignored. Two calls in the same millisecond still collapse into
    // one spawn (QProcess refuses to start over itself); clicks are never
    // that close, and a phase cannot end twice that fast.
    soundProcess.exec([
      "paplay",
      "--volume=" + Model.paplayVolumeArg(volumePercent),
      path
    ])
  }

  // --------------------------------------------------------- do not disturb
  //
  // Unknown-value policy, deliberately: only a parseable `true` mutes. A
  // missing file (fresh install), an unreadable one, malformed JSON, or a
  // `dnd` value that is neither true nor false all resolve to "not muted".
  // The failure mode of guessing wrong the other way is a timer that never
  // makes a sound again with no visible explanation.
  function applyDndState(raw) {
    var muted = false
    var text = String(raw || "").trim()
    if (text !== "") {
      var parsed = null
      try {
        parsed = JSON.parse(text)
      } catch (error) {
        parsed = null
      }
      // The daemon writes a JSON boolean; the string spellings are tolerated
      // because they are the only other thing a hand-edited file can hold.
      if (parsed && typeof parsed === "object" &&
          (parsed.dnd === true || parsed.dnd === "true")) {
        muted = true
      }
    }
    if (root.muted !== muted) root.muted = muted
  }

  // Read failure is its own case: the file that answered the question is gone
  // or unreadable, and the HOME path is still worth one look because that is
  // where the daemon really writes.
  function applyDndFailure() {
    // "Unknown" resolves to not muted, and is applied before the fallback
    // lookup so a stale true cannot be masked by the file that just vanished.
    root.applyDndState("")
    if (root.dndActivePath === root.dndPrimaryPath &&
        root.dndPrimaryPath !== root.dndFallbackPath &&
        !root.dndFallbackScheduled) {
      root.dndFallbackScheduled = true
      // Deferred: a path change made from inside the load-failed handler is
      // not picked up until the next poll.
      Qt.callLater(function() {
        root.dndActivePath = root.dndFallbackPath
        dndFile.reload()
      })
    }
  }

  function notifyExpiry(phase) {
    var phaseName = labelForPhase(phase)
    notificationProcess.command = [
      "notify-send",
      "--app-name=Pomodarchy",
      phaseName + " complete",
      "Acknowledge to start the next phase."
    ]
    notificationProcess.running = true
  }

  function setSuspended(value) {
    if (value) {
      if (root.suspended) return
      root.suspended = true
      root.now = Date.now()
      return
    }

    // PrepareForSleep(false) deliberately ends whatever was active and starts
    // a fresh focus phase immediately, as specified by the timer model.
    root.suspended = false
    var timestamp = Date.now()
    root.state = Model.suspendResume(timestamp, root.config, root.state)
    root.now = timestamp
  }

  function handleSleepLine(line) {
    var text = String(line || "").trim()
    if (text.indexOf("member=PrepareForSleep") !== -1) {
      root.awaitingSleepValue = true
      root.sleepSignalRevision += 1
    }

    if (!root.awaitingSleepValue) return
    var match = text.match(/\bboolean\s+(true|false)\b/i)
    if (!match) return

    root.awaitingSleepValue = false
    var preparingForSleep = match[1].toLowerCase() === "true"
    root.setSuspended(preparingForSleep)
    if (!preparingForSleep) root.sleepMonitorInterrupted = false
  }

  // A monitor restart can miss a PrepareForSleep edge. Query logind's current
  // property, but discard a response if a newer signal arrived while it ran.
  function requestSleepProbe() {
    if (sleepStateProbe.running) return
    root.sleepProbeRevision = root.sleepSignalRevision
    sleepStateProbe.running = true
  }

  function recoverMissedSleep(timestamp) {
    if (!root.sleepMonitorInterrupted || sleepMonitor.running ||
        timestamp - root.now <= 2500) return false
    root.state = Model.suspendResume(timestamp, root.config, root.state)
    root.now = timestamp
    root.sleepMonitorInterrupted = false
    return true
  }

  function reconcileSleepState(output) {
    if (root.sleepProbeRevision !== root.sleepSignalRevision) return
    var match = String(output || "").trim().match(/^b\s+(true|false)$/i)
    if (!match) {
      if (!root.suspended && sleepMonitor.running)
        root.sleepMonitorInterrupted = false
      return
    }

    var preparingForSleep = match[1].toLowerCase() === "true"
    if (preparingForSleep) {
      root.setSuspended(true)
    } else {
      if (root.suspended) root.setSuspended(false)
      else root.recoverMissedSleep(Date.now())
      if (sleepMonitor.running) root.sleepMonitorInterrupted = false
    }
  }

  property Timer tickTimer: Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: true
    onTriggered: root.tick()
  }

  property Process notificationProcess: Process {}

  // Probed once per session instead of being spawned blindly: without this a
  // missing paplay prints "Process failed to start" from Quickshell on every
  // phase completion.
  property Process paplayProbe: Process {
    command: ["sh", "-c", "command -v paplay >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.paplayChecked = true
      root.paplayAvailable = exitCode === 0
      var pending = root.pendingSoundPath
      root.pendingSoundPath = ""
      if (root.paplayAvailable && pending !== "")
        root.startPaplay(pending, root.pendingSoundVolume)
    }
  }

  // Playback only. Both channels get a no-op parser so paplay's own output
  // ("No such file or directory", "Connection failure") is read and dropped
  // rather than reaching the shell log.
  property Process soundProcess: Process {
    stdout: SplitParser { onRead: function(line) {} }
    stderr: SplitParser { onRead: function(line) {} }
  }

  // Omarchy's notifications.json. Read-only: nothing here writes a file, so
  // a machine that never toggles DND does not get one created for it.
  // (Declared as a property, not a bare child: this root is a QtObject and so
  // has no default property to hold a FileView.)
  property FileView dndFile: FileView {
    id: dndFileView
    path: root.dndActivePath
    watchChanges: true
    // A fresh install has no file yet; without this every poll would log a
    // load failure.
    printErrors: false
    onLoaded: root.applyDndState(dndFileView.text())
    onLoadFailed: root.applyDndFailure()
    onFileChanged: dndFileView.reload()
  }

  // The daemon writes notifications.json atomically (write + rename), which
  // can leave the file watch pointing at the replaced inode forever. The poll
  // is the backstop: it re-reads the value and re-arms the watch, and it also
  // picks up a file that did not exist when the shell started.
  property Timer dndPollTimer: Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: dndFile.reload()
  }

  property Process sleepStateProbe: Process {
    command: [
      "busctl", "--system", "get-property",
      "org.freedesktop.login1",
      "/org/freedesktop/login1",
      "org.freedesktop.login1.Manager",
      "PreparingForSleep"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reconcileSleepState(text)
    }
  }

  property Process sleepMonitor: Process {
    command: [
      "dbus-monitor",
      "--system",
      "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
    ]
    stdout: SplitParser {
      onRead: function(line) { root.handleSleepLine(line) }
    }
    onExited: {
      root.awaitingSleepValue = false
      root.sleepMonitorInterrupted = true
      root.monitorRestartAt = Date.now() + 5000
    }
  }

  Component.onCompleted: {
    root.now = Date.now()
    sleepMonitor.running = true
    root.sleepProbeAt = root.now + 500
  }
}
