import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var bar: null
  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool popupOpen: false
  property bool popoutSwitchClosing: false
  property bool secondaryMenuOpen: false

  onPopupOpenChanged: if (!popupOpen) secondaryMenuOpen = false

  readonly property bool opened: popupOpen
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var timerState: service && service.state
    ? service.state : ({ phase: "focus", status: "idle" })
  readonly property var timerConfig: service && service.config
    ? service.config : Model.defaultConfig()

  function open() {
    popupOpen = true
  }

  function close() {
    popupOpen = false
  }

  function togglePanel() {
    if (popupOpen) close()
    else open()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function adjustSetting(name, delta) {
    if (hostWidget && typeof hostWidget.adjustSetting === "function") {
      hostWidget.adjustSetting(name, delta)
      return
    }
    if (!service || typeof service.configure !== "function") return

    var next = {}
    for (var key in timerConfig) next[key] = timerConfig[key]
    next[name] = Number(next[name]) + Number(delta)
    service.configure(next)
  }

  function settingValue(name) {
    return Number(timerConfig[name]) || 0
  }

  function settingText(name) {
    if (name === "longBreakEvery") return settingValue(name) + " focus"
    return settingValue(name) + " min"
  }

  function decrement(name, step) {
    adjustSetting(name, -step)
  }

  function increment(name, step) {
    adjustSetting(name, step)
  }

  readonly property string primaryActionText: timerState.status === "running"
    ? "Pause" : (timerState.status === "paused" ? "Resume" : "Start")
  readonly property string statusText: {
    if (timerState.status === "awaiting") return "Phase complete"
    if (timerState.status === "paused") return "Paused"
    if (timerState.status === "running") return "In progress"
    return "Ready when you are"
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.popupOpen
    contentWidth: fittedContentWidth(Style.space(320))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight)

    Flickable {
      id: popupContent
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: popupContent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(12)

          Column {
            width: parent.width - timeText.implicitWidth - parent.spacing
            spacing: Style.space(2)

            Text {
              text: root.service ? root.service.phaseLabel.toUpperCase() : "FOCUS"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.statusText
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            id: timeText
            text: root.service ? root.service.remainingText : "30:00"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Button {
          width: parent.width
          visible: root.timerState.status !== "awaiting"
          enabled: root.service !== null
          text: root.primaryActionText
          foreground: root.foreground
          fontFamily: root.fontFamily
          selected: root.timerState.status === "running"
          focusable: true
          onClicked: {
            if (!root.service) return
            if (root.timerState.status === "running") root.service.pause()
            else root.service.resume()
          }
        }

        Button {
          width: parent.width
          visible: root.timerState.status === "awaiting"
          enabled: root.service !== null
          text: "Acknowledge & continue"
          foreground: root.foreground
          fontFamily: root.fontFamily
          selected: true
          focusable: true
          onClicked: if (root.service) root.service.acknowledge()
        }

        Button {
          width: parent.width
          text: root.secondaryMenuOpen ? "Hide actions" : "More actions"
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: true
          onClicked: root.secondaryMenuOpen = !root.secondaryMenuOpen
        }

        Row {
          visible: root.secondaryMenuOpen
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Skip"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: root.service !== null
            onClicked: if (root.service) root.service.skip()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Restart"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: root.service !== null
            onClicked: if (root.service) root.service.restart()
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }

        Text {
          text: "DURATIONS"
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(4)
          Text {
            width: parent.width - Style.space(130)
            text: "Focus"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "−"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.decrement("focusMinutes", 5)
          }
          Text {
            width: Style.space(62)
            text: root.settingText("focusMinutes")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "+"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.increment("focusMinutes", 5)
          }
        }

        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(4)
          Text {
            width: parent.width - Style.space(130)
            text: "Short break"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "−"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.decrement("shortBreakMinutes", 1)
          }
          Text {
            width: Style.space(62)
            text: root.settingText("shortBreakMinutes")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "+"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.increment("shortBreakMinutes", 1)
          }
        }

        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(4)
          Text {
            width: parent.width - Style.space(130)
            text: "Long break"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "−"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.decrement("longBreakMinutes", 5)
          }
          Text {
            width: Style.space(62)
            text: root.settingText("longBreakMinutes")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "+"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.increment("longBreakMinutes", 5)
          }
        }

        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(4)
          Text {
            width: parent.width - Style.space(130)
            text: "Long break every"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "−"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.decrement("longBreakEvery", 1)
          }
          Text {
            width: Style.space(62)
            text: root.settingText("longBreakEvery")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            width: Style.space(28)
            height: parent.height
            text: "+"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(2)
            onClicked: root.increment("longBreakEvery", 1)
          }
        }
      }
    }
  }
}
