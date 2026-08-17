# doublea.localrecord

An Omarchy 4 bar widget (Quickshell/QML) for
[LocalRecord](https://github.com/AntoineArt/localrecord). See `README.md` for what
it does; this file is what an agent needs to change it safely.

## This checkout is the installed plugin

`~/.config/omarchy/plugins/doublea.localrecord` is both the git repo and what the
running shell loads. Editing here changes the live bar. There is no separate
build.

## It follows the app

The widget imports no app code. It reads and writes two files, and the app owns
both formats:

- reads `~/.local/share/localrecord/state.json` (written by the app's
  `src/state.rs`)
- appends to `~/.local/share/localrecord/command` (read by the app's
  `src/command.rs`)

So a change here often belongs upstream first. **The panel is meant to hold every
setting the app has** — if the app grows one, add a row rather than leaving it
reachable only from the tray menu. When you start relying on a new field or verb,
raise the version floor in `README.md` and say so in the app's release notes.

The app's `.cursor/rules/release-pipeline.mdc` carries the propagation rules for
all three repos. Read it before releasing either side.

## Testing

Hot reload is unreliable for structural edits: the shell logs `Local plugin
changed, reloading` and keeps running the old component. Verify against the line
numbers in the log, and when in doubt restart:

```bash
omarchy plugin validate .            # after any manifest.json change
omarchy-restart-shell                # the reliable reload
quickshell list --all                # instance id
quickshell log -i <id> -t 200        # errors; also confirms which file version loaded
omarchy-shell doublea.localrecord status   # "Idle" / "Recording 0:07" / "Not running"
omarchy-shell doublea.localrecord open     # drive the panel without clicking
```

One warning is expected and harmless: `IpcHandler ... will not be used because
another handler is registered` — one instance per monitor, only the first
registers. Every first-party panel logs it too.

Never run `omarchy-refresh-shell`: it resets `shell.json` to defaults and would
wipe the user's bar layout.

To see the result, screenshot the monitor that actually holds the popup — find it
by namespace, because the panel opens on one monitor and dismiss scrims cover the
others:

```bash
hyprctl layers -j | grep -B5 omarchy-keyboard-panel
grim -o <output> /tmp/panel.png
```

## Two constraints that are easy to break

**Portability.** The committed `Panel.qml` must use `KeyboardPanel` from `qs.Ui`
and import nothing outside this directory. The user's working tree deliberately
carries an uncommitted edit swapping in their own `ShadowKeyboardPanel` from
`~/.config/omarchy/qml` — their house style. Keep it out of commits: stash the
local file, commit the portable version, restore it. `git status` showing a
modified `Panel.qml` is the expected state here, not something to clean up.

**Theming.** Take every colour, font and metric from the bar and the theme
singletons (`bar.foreground`, `bar.urgent`, `Color.*`, `Style.*`). No literal
colours or sizes: an Omarchy theme switch has to carry the widget with it.
Recording state uses `urgent`. Text is dropped in vertical bars, where there is no
room for it.

## Installing the app

`omarchy plugin add` runs no plugin code by design — no install hooks, no sudo —
so the app can never be installed as a side effect of installing this. The panel
offers `install-localrecord.sh` instead, which pulls the latest release binary
into `~/.local/bin` and reports missing system libraries without touching them.
