# LocalRecord for Omarchy

A bar widget for [LocalRecord](https://github.com/AntoineArt/localrecord), the
tray app that records your microphone and desktop audio into one file.

A microphone glyph while idle, a red REC dot and a running clock while
recording, and a popup with the controls the tray menu has — plus the last
recording, one click from being opened or copied.

It exists because the Linux tray backend has no click action: right-clicking for
a menu is the only thing an Omarchy user can do with the tray icon. This gives
the app a real click target, and somewhere to show that a recording is running.

## Requirements

- Omarchy 4 (`omarchy-shell`), which is what loads the plugin.
- LocalRecord **0.1.15 or newer** — older versions publish neither the state
  file this reads nor the signal the auto-levelling switch sends.

## Install

```bash
omarchy plugin add https://github.com/AntoineArt/localrecord-omarchy-plugin.git --enable
```

It lands in the right section of the bar. Move it with `omarchy bar move`, and
remove it with `omarchy plugin remove doublea.localrecord`.

## Interactions

| Input | Action |
|---|---|
| Left click | Start/stop recording (swap with the panel in settings) |
| Right click | Open the panel |
| Middle click | Open the recordings folder |

In the panel, arrows move the cursor and Enter activates. `r` records, `a`
toggles auto-levelling, `o` opens the folder, `c` copies the last file's path.

## Settings

Per widget, in Setup > Plugins, or under this widget's entry in
`~/.config/omarchy/shell.json`:

| Key | Default | What it does |
|---|---|---|
| `primaryAction` | `Toggle recording` | Which action the left button takes; the other moves to the right button |
| `showElapsed` | `true` | Show the running length next to the icon. Vertical bars never do, for lack of room |
| `hideWhenIdle` | `false` | Keep the widget out of the bar until a recording starts |

## How it talks to the app

Reading is a file, writing is a signal.

LocalRecord publishes `~/.local/share/localrecord/state.json` whenever something
changes — whether it is recording, since when, the last file it saved, and the
settings worth mirroring. The widget watches that file, and re-reads it on a slow
timer as well: the app renames the file into place so a reader never catches a
half-written one, and a rename swaps the inode out from under a file watcher.
`pid` is checked against `/proc` so a crashed app does not read as an idle one.

Acting goes back through signals, the same channel the compositor shortcut uses:
`SIGUSR1` toggles recording, `SIGUSR2` toggles auto-levelling. Nothing here
writes the app's settings file, so its tray menu never goes stale.

## Theming

Every colour, font and metric comes from the bar and the shell's theme
singletons, so switching Omarchy themes carries the widget with it. The recording
state uses the theme's `urgent` colour — the same one the bar uses to say
"something needs your attention".

## Licence

MIT, same as LocalRecord.
