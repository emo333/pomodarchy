import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "emo333.pomodarchy"

  readonly property var timerService: {
    var pluginShell = root.bar ? root.bar.shell : null
    if (!pluginShell || typeof pluginShell.serviceFor !== "function") return null
    return pluginShell.serviceFor(root.moduleName)
  }
  readonly property string phaseAbbreviation: {
    if (!timerService || !timerService.state) return "F"
    if (timerService.state.phase === "shortBreak") return "SB"
    if (timerService.state.phase === "longBreak") return "LB"
    return "F"
  }
  readonly property string barText: {
    var time = timerService ? timerService.remainingText : "30:00"
    if (vertical) return phaseAbbreviation + " " + time
    var phase = timerService ? timerService.phaseLabel.toUpperCase() : "FOCUS"
    return phase + " " + time
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.anchorItem = button
    panel.hostWidget = root
    panel.service = root.timerService
  }

  function syncConfig() {
    if (!timerService || typeof timerService.configure !== "function") return
    timerService.configure(Model.normalizeConfig(root.settings))
  }

  function persistConfig(values) {
    var next = Model.normalizeConfig(values)
    var defaults = Model.defaultConfig()
    var entry = { id: root.moduleName }
    // Keys the model does not own are preserved verbatim (bar-widget state
    // written by the host, etc.).
    if (root.settings) {
      for (var key in root.settings) {
        if (key !== "id" && !Object.prototype.hasOwnProperty.call(defaults, key))
          entry[key] = root.settings[key]
      }
    }
    // Only non-default values are written. The defaults include long absolute
    // sound file paths, and persisting those would bake this machine's file
    // layout into shell.json - every duration tweak would do it. A key that
    // returns to its default therefore disappears from the entry again.
    for (var configKey in next) {
      if (next[configKey] !== defaults[configKey]) entry[configKey] = next[configKey]
    }

    root.settings = entry
    if (root.timerService && typeof root.timerService.configure === "function")
      root.timerService.configure(next)

    var pluginShell = root.bar ? root.bar.shell : null
    if (pluginShell && typeof pluginShell.updateEntryInline === "function")
      pluginShell.updateEntryInline(root.moduleName, entry)
  }

  function setSetting(name, value) {
    var current = timerService ? timerService.config : Model.normalizeConfig(root.settings)
    var next = {}
    for (var key in current) next[key] = current[key]
    next[name] = value
    root.persistConfig(next)
  }

  function adjustSetting(name, delta) {
    var current = timerService ? timerService.config : Model.normalizeConfig(root.settings)
    root.setSetting(name, Number(current[name]) + Number(delta))
  }

  function previewSound() {
    if (root.timerService && typeof root.timerService.previewSound === "function")
      root.timerService.previewSound()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.togglePanel()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    injectPanel()
    syncConfig()
  }
  onSettingsChanged: {
    injectPanel()
    syncConfig()
  }
  onTimerServiceChanged: {
    injectPanel()
    syncConfig()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("PomodoroPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "emo333.pomodarchy"

    // The service holds the sound state, but it cannot register this target
    // itself: a second IpcHandler for the same target is rejected by
    // Quickshell, so the handlers stay here and delegate.

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function start(): void { if (root.timerService) root.timerService.start() }
    function pause(): void { if (root.timerService) root.timerService.pause() }
    function resume(): void { if (root.timerService) root.timerService.resume() }
    function acknowledge(): void { if (root.timerService) root.timerService.acknowledge() }
    function skip(): void { if (root.timerService) root.timerService.skip() }
    function restart(): void { if (root.timerService) root.timerService.restart() }
    function previewSound(): void { root.previewSound() }
    function dndState(): string {
      if (!root.timerService) return "unavailable"
      return root.timerService.doNotDisturb ? "on" : "off"
    }
    function status(): string {
      if (!root.timerService) return "unavailable"
      return JSON.stringify({
        phase: root.timerService.state.phase,
        status: root.timerService.state.status,
        remainingMs: root.timerService.remainingMs,
        config: root.timerService.config
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    tooltipText: root.timerService
      ? "Pomodoro " + root.timerService.phaseLabel + " · " + root.timerService.statusLabel
      : "Pomodoro timer"
    active: root.timerService && root.timerService.state
      ? root.timerService.state.status === "running" || root.timerService.state.status === "awaiting"
      : false
    horizontalMargin: 7
    verticalPadding: 6
    textRotation: root.vertical ? -90 : 0
    fixedHeight: root.vertical ? Math.max(Style.bar.iconSlot, labelWidth + Style.space(12)) : -1

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
