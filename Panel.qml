import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// LocalRecord in the bar: a mic glyph that turns into a live REC pill, and a
// popup with the controls the tray menu has plus the last recording.
//
// Everything visual comes off the bar and the theme singletons — foreground,
// urgent, font family, spacing — so a theme switch carries the widget with it
// and no colour is hardcoded. Text is dropped in vertical bars, where there is
// no room for it, the same way the media widget does.
Panel {
  id: root
  moduleName: "doublea.localrecord"
  ipcTarget: "doublea.localrecord"
  manageIpc: false

  // ---- Theme. Same derivation as the first-party panels.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- User settings, from this widget's shell.json entry.
  readonly property bool panelOnLeftClick: String(setting("primaryAction", "Toggle recording")) === "Open panel"
  readonly property bool showElapsed: setting("showElapsed", true) === true
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true

  readonly property bool timerVisible: showElapsed && service.isRecording && !vertical
  readonly property bool vertical: bar ? bar.vertical : false

  readonly property string glyph: service.isRecording ? "󰻂" : (service.running ? "󰍬" : "󰍭")
  readonly property string elapsedText: Model.elapsedText(service.elapsed)
  readonly property string stateText: service.isRecording
    ? "Recording " + elapsedText
    : (service.running ? "Idle" : "Not running")

  readonly property string tooltip: {
    if (!service.running) return "LocalRecord is not running"
    if (service.isRecording) return "Recording " + elapsedText + " — click to stop"
    var shortcut = Model.shortcutText(service.hotkey)
    return shortcut === "" ? "LocalRecord" : "LocalRecord · " + shortcut
  }

  readonly property string lastFileName: Model.fileName(service.lastFile)
  readonly property string lastSavedText: Model.savedAgoText(service.lastSavedAt, service.nowSeconds)
  readonly property bool hasLastFile: service.lastFile !== ""

  // ---- Popup cursor, for keyboard navigation.
  readonly property var rows: {
    var list = []
    if (!service.running) list.push("launch")
    else list.push("record")
    if (service.running) list.push("agc")
    if (hasLastFile) list.push("last")
    list.push("folder")
    return list
  }
  property int rowIndex: 0
  property bool cursorActive: false

  readonly property string cursorRow: rows.length === 0
    ? ""
    : rows[Math.max(0, Math.min(rowIndex, rows.length - 1))]

  function hasCursorOn(name) { return cursorActive && cursorRow === name }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + dy))
  }

  function setCursor(name) {
    cursorActive = true
    var at = rows.indexOf(name)
    if (at !== -1) rowIndex = at
  }

  function activateCursor() {
    if (cursorRow === "launch") service.launchApp()
    else if (cursorRow === "record") service.toggleRecording()
    else if (cursorRow === "agc") service.toggleAgc()
    else if (cursorRow === "last") service.openLastFile()
    else if (cursorRow === "folder") service.openRecordingsFolder()
  }

  // Hidden while idle only when asked; a recording always shows, otherwise the
  // setting would hide the one state worth seeing.
  visible: !hideWhenIdle || service.isRecording
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    rowIndex = 0
    service.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    onActionFailed: function(message) {
      if (root.bar) root.bar.run("omarchy-notification-send " + JSON.stringify(message))
    }
  }

  // Measured off-screen: the button has to reserve room for the timer, which
  // lives inside its icon slot and so cannot be asked for its width.
  TextMetrics {
    id: timerMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: root.elapsedText
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function record(): string { service.toggleRecording(); return "ok" }
    function agc(): string { service.toggleAgc(); return "ok" }
    function status(): string { return root.stateText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: service.isRecording
    dimmed: !service.running
    tooltipText: root.tooltip
    slotSize: Style.bar.statusSlot + (root.timerVisible ? timerMetrics.width + Style.space(5) : 0)

    // A Row rather than the plain glyph, so the timer rides along inside the
    // one click target instead of becoming a second, unclickable item.
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: service.isRecording ? root.urgent : (root.bar ? root.bar.barForeground : root.foreground)
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.timerVisible
            text: root.elapsedText
            color: root.bar ? root.bar.barForeground : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) service.openRecordingsFolder()
      else if (buttonCode === Qt.RightButton) root.panelOnLeftClick ? service.toggleRecording() : root.toggle()
      else root.panelOnLeftClick ? root.toggle() : service.toggleRecording()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "r") service.toggleRecording()
        else if (key === "a") service.toggleAgc()
        else if (key === "o") service.openRecordingsFolder()
        else if (key === "c") service.copyLastPath()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.hasCursorOn("agc")
            function focusHero() { root.setCursor("agc") }

            PanelHero {
              id: hero
              width: parent.width
              title: "LocalRecord"
              meta: root.stateText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: service.isRecording ? 1.0 : 0.55
              iconComponent: Component {
                Text {
                  text: root.glyph
                  color: service.isRecording ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              // Auto-levelling on the hero's trailing edge: the one setting
              // worth a switch, and the app owns the write (SIGUSR2) so its
              // tray checkmark stays in step.
              trailingControl: Component {
                ToggleSwitch {
                  id: agcSwitch
                  visible: service.running
                  checked: service.agc
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: service.toggleAgc()

                  PanelToolTip {
                    visible: agcSwitch.containsMouse
                    text: service.agc ? "Turn auto-levelling off" : "Turn auto-levelling on"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          ActionRow {
            rowName: "launch"
            visible: !service.running
            glyph: "󰐊"
            label: "Start LocalRecord"
            detail: "The app is not running"
            onActivated: service.launchApp()
          }

          ActionRow {
            rowName: "record"
            visible: service.running
            glyph: service.isRecording ? "󰓛" : "󰑊"
            label: service.isRecording ? "Stop recording" : "Start recording"
            detail: service.isRecording
              ? "Saves and copies the file to the clipboard"
              : Model.shortcutText(service.hotkey)
            accent: service.isRecording
            onActivated: service.toggleRecording()
          }

          Column {
            visible: service.running
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Auto-levelling"; value: service.agc ? "On" : "Off" }
            InfoPair { label: "Format"; value: String(service.format).toUpperCase() }
            InfoPair { label: "Folder"; value: Model.shortPath(service.recordingsDir, service.home) }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LAST RECORDING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !root.hasLastFile
              width: parent.width
              text: "Nothing recorded yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            ActionRow {
              rowName: "last"
              visible: root.hasLastFile
              glyph: "󰎈"
              label: root.lastFileName
              detail: root.lastSavedText
              onActivated: service.openLastFile()

              trailing: Component {
                PanelActionButton {
                  iconText: "󰆏"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: service.copyLastPath()

                  PanelToolTip {
                    visible: parent.containsMouse === true
                    text: "Copy path"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }

            ActionRow {
              rowName: "folder"
              glyph: "󰉋"
              label: "Open recordings folder"
              detail: Model.shortPath(service.recordingsDir, service.home)
              onActivated: service.openRecordingsFolder()
            }
          }
        }
      }
    }
  }

  // One row shape for every action in the panel: glyph, label, sub-label, an
  // optional trailing control, and a cursor ring shared with the keyboard.
  component ActionRow: CursorSurface {
    id: actionRow

    property string rowName: ""
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool accent: false
    property Component trailing: null

    signal activated()

    hasCursor: root.hasCursorOn(rowName)
    foreground: root.foreground
    width: parent ? parent.width : 0
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(actionRow.rowName)
      onClicked: actionRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: actionRow.glyph
        color: actionRow.accent ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          Layout.fillWidth: true
          visible: actionRow.detail !== ""
          text: actionRow.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Loader {
        active: actionRow.trailing !== null
        sourceComponent: actionRow.trailing
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideMiddle
  }
}
