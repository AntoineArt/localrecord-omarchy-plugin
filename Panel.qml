import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// LocalRecord in the bar: a waveform that turns into a live REC pill, and a
// panel holding everything the app can be told to do — recording, every
// setting, and the last file it saved. The tray menu is not needed to drive it.
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
  readonly property bool showElapsed: setting("showElapsed", true) === true
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property bool timerVisible: showElapsed && service.isRecording && !vertical

  // A waveform rather than a microphone: next to the bar's headphones, screen
  // and shield, a mic glyph names a device and reads as its settings, when what
  // this widget does is capture a signal. Recording swaps it for the record dot,
  // so the state changes shape and not only colour. "Not running" is the
  // button's own `dimmed`, which is why there is no third glyph here.
  readonly property string glyph: service.isRecording ? "󰻂" : "󱑽"
  readonly property string elapsedText: Model.elapsedText(service.elapsed)
  readonly property string stateText: service.isRecording
    ? "Recording " + elapsedText
    : (service.running ? "Idle" : "Not running")

  readonly property string tooltip: {
    if (!service.running) return "LocalRecord is not running"
    if (service.isRecording) return "Recording " + elapsedText
    var shortcut = Model.shortcutText(service.hotkey)
    return shortcut === "" ? "LocalRecord" : "LocalRecord · " + shortcut
  }

  readonly property string lastFileName: Model.fileName(service.lastFile)
  readonly property string lastSavedText: Model.savedAgoText(service.lastSavedAt, service.nowSeconds)
  readonly property bool hasLastFile: service.lastFile !== ""
  readonly property bool lossy: String(service.format).toLowerCase() === "opus"

  // ---- Panel cursor. Built from what is actually on screen, so keyboard
  //      navigation never lands on a row the state hid.
  readonly property var rows: {
    var list = []
    if (!service.running) {
      list.push(service.installed ? "launch" : "install")
    } else {
      list.push("record", "agc", "startup", "tray", "format")
      if (lossy) list.push("bitrate")
      list.push("shortcut", "folder")
    }
    // The last recording is a fact about the folder rather than about the
    // process, so its rows stay on screen while the app is stopped — and the
    // cursor has to reach them there too.
    if (hasLastFile) list.push("last")
    list.push("openFolder")
    if (service.running) list.push("quit")
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
    // Left/right adjusts the row that has a range; everywhere else it is inert.
    if (dx !== 0) {
      if (cursorRow === "bitrate") service.setBitrate(clampBitrate(service.bitrate + dx * 16))
      else if (cursorRow === "format") toggleFormat()
      return
    }
    if (dy === 0) return
    rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + dy))
  }

  function setCursor(name) {
    cursorActive = true
    var at = rows.indexOf(name)
    if (at !== -1) rowIndex = at
  }

  function activateCursor() {
    if (cursorRow === "install") service.installApp()
    else if (cursorRow === "launch") service.launchApp()
    else if (cursorRow === "record") service.toggleRecording()
    else if (cursorRow === "agc") service.toggleAgc()
    else if (cursorRow === "startup") service.toggleStartup()
    else if (cursorRow === "tray") service.toggleTray()
    else if (cursorRow === "format") toggleFormat()
    else if (cursorRow === "shortcut") service.changeShortcut()
    else if (cursorRow === "folder") service.changeFolder()
    else if (cursorRow === "last") service.openLastFile()
    else if (cursorRow === "openFolder") service.openRecordingsFolder()
    else if (cursorRow === "quit") service.quitApp()
  }

  function toggleFormat() { service.setFormat(root.lossy ? "wav" : "opus") }

  function clampBitrate(value) { return Math.max(32, Math.min(128, Math.round(value))) }

  // A picker opens a dialog on top of everything; leaving the panel up behind
  // it would just be in the way.
  function closeAfterPicker() { root.close() }

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

    // Left opens the panel, which is where everything lives. Middle is the
    // one shortcut kept for muscle memory; right is deliberately unbound.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) service.toggleRecording()
      else if (buttonCode !== Qt.RightButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

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
        else if (key === "f") root.toggleFormat()
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
        ScrollBar.vertical: ShellScrollBar {
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: column
          width: panelFlick.width - Style.space(10)
          spacing: Style.space(12)

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
          }

          ActionRow {
            rowName: "install"
            visible: !service.running && !service.installed
            glyph: "󰇚"
            label: "Install LocalRecord"
            detail: "Downloads the latest release into ~/.local/bin"
            onActivated: { service.installApp(); root.close() }
          }

          ActionRow {
            rowName: "launch"
            visible: !service.running && service.installed
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

          PanelSeparator { visible: service.running; foreground: root.foreground }

          Column {
            visible: service.running
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleRow {
              rowName: "agc"
              glyph: "󰕾"
              label: "Auto-level mic and desktop"
              detail: "Applies to the next recording"
              checked: service.agc
              onActivated: service.toggleAgc()
            }

            ToggleRow {
              rowName: "startup"
              glyph: "󰐥"
              label: "Launch at login"
              detail: service.startup ? "Starts with your session" : "Started by hand"
              checked: service.startup
              onActivated: service.toggleStartup()
            }

            ToggleRow {
              rowName: "tray"
              glyph: "󰏘"
              label: "Tray icon"
              detail: service.tray ? "Shown in the system tray" : "Hidden — this panel drives the app"
              checked: service.tray
              onActivated: service.toggleTray()
            }

            ActionRow {
              rowName: "format"
              glyph: "󰈣"
              label: "Format"
              detail: root.lossy ? "Compact, ~30 MB per hour" : "Uncompressed"
              onActivated: root.toggleFormat()

              trailing: Component {
                ButtonGroup {
                  options: [{ value: "opus", label: "Opus" }, { value: "wav", label: "WAV" }]
                  value: root.lossy ? "opus" : "wav"
                  foreground: root.foreground
                  background: root.bar ? root.bar.background : Color.background
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  cursorIndex: root.hasCursorOn("format") ? (root.lossy ? 0 : 1) : -1
                  onChanged: function(value) { service.setFormat(value) }
                  onHovered: function(index, isHovered) { if (isHovered) root.setCursor("format") }
                }
              }
            }

            // Only Opus has a bitrate to spend; WAV is what it is.
            Column {
              visible: root.lossy
              width: parent.width
              spacing: Style.space(2)

              ActionRow {
                rowName: "bitrate"
                glyph: "󰓅"
                label: "Bitrate"
                detail: service.bitrate + " kbps"
                activatable: false
              }

              PanelSlider {
                x: Style.space(10)
                width: parent.width - Style.space(20)
                bar: root.bar
                minimum: 32
                maximum: 128
                step: 16
                integer: true
                value: service.bitrate
                onReleased: function(value) { service.setBitrate(value) }
              }
            }

            ActionRow {
              rowName: "shortcut"
              glyph: "󰌌"
              label: "Shortcut"
              detail: Model.shortcutText(service.hotkey) || "None"
              onActivated: { service.changeShortcut(); root.closeAfterPicker() }
            }

            ActionRow {
              rowName: "folder"
              glyph: "󰝰"
              label: "Recordings folder"
              detail: Model.shortPath(service.recordingsDir, service.home)
              onActivated: { service.changeFolder(); root.closeAfterPicker() }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

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
                }
              }
            }

            ActionRow {
              rowName: "openFolder"
              glyph: "󰉋"
              label: "Open recordings folder"
              onActivated: service.openRecordingsFolder()
            }
          }

          PanelSeparator { visible: service.running; foreground: root.foreground }

          ActionRow {
            rowName: "quit"
            visible: service.running
            glyph: "󰗼"
            label: "Quit LocalRecord"
            detail: "Stops recording and closes the app"
            onActivated: { service.quitApp(); root.close() }
          }
        }
      }
    }
  }

  // One row shape for every line in the panel: glyph, label, sub-label, an
  // optional trailing control, and a cursor ring shared with the keyboard.
  component ActionRow: CursorSurface {
    id: actionRow

    property string rowName: ""
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool accent: false
    property bool activatable: true
    property Component trailing: null

    signal activated()

    hasCursor: root.hasCursorOn(rowName)
    foreground: root.foreground
    width: parent ? parent.width : 0
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: actionRow.activatable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.setCursor(actionRow.rowName)
      onClicked: if (actionRow.activatable) actionRow.activated()
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
          elide: Text.ElideMiddle
        }
      }

      Loader {
        active: actionRow.trailing !== null
        sourceComponent: actionRow.trailing
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A row whose trailing control is a switch. The three settings that use one
  // differ only in the state they mirror, so `checked` is the whole difference
  // and flipping the switch is the same thing as activating the row.
  component ToggleRow: ActionRow {
    id: toggleRow

    property bool checked: false

    trailing: Component {
      ToggleSwitch {
        checked: toggleRow.checked
        hasCursor: root.hasCursorOn(toggleRow.rowName)
        foreground: root.foreground
        onHovered: function(on) { if (on) root.setCursor(toggleRow.rowName) }
        onToggled: toggleRow.activated()
      }
    }
  }
}
