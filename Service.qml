import QtQuick
import Quickshell
import Quickshell.Io

// Everything the widget knows about LocalRecord, and every way it talks back.
//
// Reading: the app publishes ~/.local/share/localrecord/state.json on each
// change. Watched for instant updates, and re-read on a slow timer as well —
// the app renames the file into place (so a reader never sees a half-written
// one), and a rename swaps the inode out from under a file watcher.
//
// Writing: signals, the same channel the compositor binding uses. SIGUSR1
// toggles recording, SIGUSR2 toggles auto-levelling. That keeps the app the
// single owner of its settings file, so its tray menu never goes stale.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/share/localrecord/state.json"

  // Parsed straight out of the state file.
  property bool parsed: false
  property int pid: 0
  property string exe: ""
  property bool recording: false
  property double startedAt: 0
  property string lastFile: ""
  property double lastSavedAt: 0
  property bool agc: true
  property string hotkey: ""
  property string format: ""
  property string recordingsDir: ""

  // `comm` for our pid, so a crashed app is not read as an idle one. Empty
  // until the first read lands, which is why `running` waits for `parsed`.
  property string processName: ""

  readonly property bool running: parsed && pid > 0 && processName === "localrecord"
  readonly property bool isRecording: running && recording

  // Ticks only while recording, so an idle bar costs nothing.
  property double nowSeconds: 0
  readonly property int elapsed: isRecording && startedAt > 0
    ? Math.max(0, Math.floor(nowSeconds - startedAt))
    : 0

  signal actionFailed(string message)

  function reload() {
    stateFile.reload()
    if (pid > 0) processFile.reload()
  }

  function toggleRecording() { signalApp("USR1") }

  function toggleAgc() { signalApp("USR2") }

  function openRecordingsFolder() {
    if (recordingsDir !== "") Quickshell.execDetached(["xdg-open", recordingsDir])
  }

  function openLastFile() {
    if (lastFile !== "") Quickshell.execDetached(["xdg-open", lastFile])
  }

  function copyLastPath() {
    if (lastFile !== "") Quickshell.execDetached(["wl-copy", "--", lastFile])
  }

  function launchApp() {
    // The app records its own path, so the launch works wherever it was
    // installed from; PATH is the fallback for a state file that predates it.
    Quickshell.execDetached(exe !== "" ? [exe] : ["localrecord"])
  }

  // argv, never a shell string: `kill` takes the pid we parsed and nothing has
  // to be quoted.
  function signalApp(name) {
    if (!running) {
      root.actionFailed("LocalRecord is not running")
      return
    }
    Quickshell.execDetached(["kill", "-" + name, String(pid)])
  }

  function applyState(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      reset()
      return
    }

    var data = null
    try {
      data = JSON.parse(text)
    } catch (error) {
      // A truncated read is transient; keep the last good values rather than
      // flashing the widget back to "not running".
      return
    }

    if (!data || typeof data !== "object") {
      reset()
      return
    }

    pid = Number(data.pid) || 0
    exe = String(data.exe || "")
    recording = data.recording === true
    startedAt = Number(data.started_at) || 0
    lastFile = String(data.last_file || "")
    lastSavedAt = Number(data.last_saved_at) || 0
    agc = data.agc !== false
    hotkey = String(data.hotkey || "")
    format = String(data.format || "")
    recordingsDir = String(data.recordings_dir || "")
    parsed = true
    if (pid > 0) processFile.reload()
  }

  function reset() {
    parsed = false
    pid = 0
    recording = false
    startedAt = 0
    processName = ""
  }

  Component.onCompleted: nowSeconds = Date.now() / 1000

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyState(text())
    onFileChanged: root.applyState(text())
    onLoadFailed: root.reset()
  }

  FileView {
    id: processFile
    path: root.pid > 0 ? "/proc/" + root.pid + "/comm" : ""
    printErrors: false
    onLoaded: root.processName = String(text() || "").trim()
    onLoadFailed: root.processName = ""
  }

  // Slow safety net for the watcher, and what notices the app going away.
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.reload()
  }

  // The elapsed clock. Separate from the reload timer so the label steps every
  // second while recording without re-reading anything.
  Timer {
    interval: 1000
    running: root.isRecording
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowSeconds = Date.now() / 1000
  }
}
