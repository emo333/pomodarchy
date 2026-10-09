import QtQuick
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
