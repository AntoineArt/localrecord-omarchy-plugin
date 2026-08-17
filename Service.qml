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
// Writing: a line appended to the app's command file. Every action the panel
// offers routes through it, including the ones that carry a value, and the app
// applies each one through the same code path its tray menu uses — so the menu,
// the panel and the state file cannot disagree. Nothing here writes the app's
// settings file directly.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/share/localrecord/state.json"
  readonly property string commandPath: home + "/.local/share/localrecord/command"

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
  property int bitrate: 0
  property bool startup: false
  property bool tray: true
  property string recordingsDir: ""

  // `comm` for our pid, so a crashed app is not read as an idle one. Empty
  // until the first read lands, which is why `running` waits for `parsed`.
  property string processName: ""

  // Whether the binary exists at all. A missing app and a stopped one need
  // different offers — install versus start — and neither can be told from the
  // state file, which a never-installed app has never written.
  property bool installed: false
  readonly property string installerPath: String(Qt.resolvedUrl("install-localrecord.sh")).replace("file://", "")

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

  // Costs a shell and a jq, and only ever changes the panel while the app is
  // missing — so it is asked on its own slow timer rather than riding the
  // three-second state reload, and not at all once the app is running.
  function probeInstalled() {
    if (!installedProc.running) installedProc.running = true
  }

  // Runs the installer in a floating terminal rather than silently: it
  // downloads a binary and may have system libraries to report, and both are
  // things the user should see.
  function installApp() {
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation", installerPath
    ])
  }

  function toggleRecording() { send("record") }
  function toggleAgc() { send("agc") }
  function toggleStartup() { send("startup") }
  function toggleTray() { send("tray") }
  function changeShortcut() { send("shortcut") }
  function changeFolder() { send("folder") }
  function setFormat(value) { send("format " + value) }
  function setBitrate(kbps) { send("bitrate " + Math.round(kbps)) }
  function quitApp() { send("quit") }

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

  // Appended rather than written, so a second click lands behind the first
  // instead of overwriting it. The shell is only here for the `>>`; every
  // value is quoted, and each one comes from a fixed vocabulary anyway.
  function send(line) {
    if (!running) {
      root.actionFailed("LocalRecord is not running")
      return
    }
    Quickshell.execDetached([
      "bash", "-c",
      "printf '%s\\n' " + JSON.stringify(String(line)) + " >> " + JSON.stringify(commandPath)
    ])
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
    bitrate = Number(data.bitrate) || 0
    startup = data.startup === true
    tray = data.tray !== false
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

  Process {
    id: installedProc
    // PATH, the usual prefix, or wherever the state file says the app last ran
    // from — a build run out of its source tree counts as installed too.
    command: ["bash", "-lc",
      "command -v localrecord >/dev/null"
      + " || test -x \"$HOME/.local/bin/localrecord\""
      + " || test -x \"$(jq -r '.exe // empty' \"$HOME/.local/share/localrecord/state.json\" 2>/dev/null)\""]
    onExited: function(exitCode) { root.installed = exitCode === 0 }
  }

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

  // Only runs while the app is missing, which is the only time the answer can
  // still change what the panel offers.
  Timer {
    interval: 15000
    running: !root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeInstalled()
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
