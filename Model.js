.pragma library

// Pure formatting for the widget and its panel. Kept out of QML so the shapes
// below can be reasoned about (and fixed) without touching layout code.

// "0:07", "12:34", "1:02:03" — a recorder's clock, so seconds always show and
// the hour only appears once it exists.
function elapsedText(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var s = total % 60
  var m = Math.floor(total / 60) % 60
  var h = Math.floor(total / 3600)
  var pad = function(value) { return value < 10 ? "0" + value : String(value) }
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

function fileName(path) {
  var text = String(path || "")
  if (text === "") return ""
  var cut = text.lastIndexOf("/")
  return cut === -1 ? text : text.slice(cut + 1)
}

// Relative time for the last saved recording. Coarse on purpose: the exact
// second stops mattering within a minute, and "just now" reads better.
function savedAgoText(savedAt, nowSeconds) {
  var saved = Math.floor(Number(savedAt) || 0)
  if (saved <= 0) return ""

  var delta = Math.max(0, Math.floor(nowSeconds) - saved)
  if (delta < 45) return "just now"
  if (delta < 90) return "a minute ago"

  var minutes = Math.round(delta / 60)
  if (minutes < 60) return minutes + " min ago"

  var hours = Math.round(delta / 3600)
  if (hours < 24) return hours === 1 ? "an hour ago" : hours + " hours ago"

  var days = Math.round(delta / 86400)
  return days === 1 ? "yesterday" : days + " days ago"
}

// Home-relative folders, since that is how the user thinks of them and the
// panel is narrow.
function shortPath(path, home) {
  var text = String(path || "")
  var prefix = String(home || "")
  if (prefix !== "" && text.indexOf(prefix + "/") === 0) return "~" + text.slice(prefix.length)
  return text
}

// LocalRecord stores "Ctrl+Shift+R"; the bar spells modifiers out with spaces
// around a separator, matching how Omarchy shows shortcuts elsewhere.
function shortcutText(binding) {
  var text = String(binding || "").trim()
  if (text === "") return ""
  return text.split("+").map(function(part) { return part.trim() }).join(" + ")
}

// /proc/<pid>/comm is capped at 15 bytes. Accept old app names as well as the
// name derived from the version in state.json; unrelated reused PIDs stay dead.
function isLocalRecordProcess(name, version) {
  return name === "localrecord"
    || (version !== "" && name === ("localrec-" + version).slice(0, 15))
}

function desktopOnlyAgc(version) {
  var parts = String(version).split(".").map(Number)
  return parts.length === 3 && parts.every(function(part) { return Number.isFinite(part) })
    && (parts[0] > 1 || (parts[0] === 1 && (parts[1] > 3 || (parts[1] === 3 && parts[2] >= 3))))
}
