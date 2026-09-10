# LocalRecord for Omarchy

A bar widget for [LocalRecord](https://github.com/AntoineArt/localrecord), the
tray app that records your microphone and desktop audio into one file.

A waveform glyph while idle, a red REC dot and a running clock while
recording, and a panel holding everything the app can be told to do — recording,
every setting, and the last file it saved, one click from being opened or copied.

It exists because the Linux tray backend has no click action: right-clicking for
a menu is the only thing an Omarchy user can do with the tray icon. This gives
the app a real click target, somewhere to show that a recording is running, and
enough control that the tray icon becomes optional — the panel can hide it.

## Requirements

- Omarchy 4 (`omarchy-shell`), which is what loads the plugin.
- LocalRecord **0.1.16 or newer** — older versions publish neither the state
  file this reads nor the command file it writes. The app renumbered from
  0.1.17 straight to 1.3.0 so that it and this widget share a version from
  here on; the floor is still the old 0.1.16, which remains supported.
- The panel heading and **App version** row need LocalRecord **1.3.2 or newer**, which is
  the first release to publish `app_version` in its state file. Below that the
  app version hides itself; nothing else changes, so the floor stays where it is.
- Use plugin **1.3.3 or newer** with LocalRecord **1.3.3 or newer**: it recognizes
  the versioned Linux process name (`localrec-1.3.3`). Older app versions remain
  supported. The **Plugin version** row is always available, even with the app stopped.

## Install

```bash
omarchy plugin add https://github.com/AntoineArt/localrecord-omarchy-plugin.git --enable
```

It lands in the right section of the bar. Move it with `omarchy bar move`, and
remove it with `omarchy plugin remove doublea.localrecord`.

### Installing the app

`omarchy plugin add` runs no code — no install hooks, no sudo — so the app
cannot ride along with the plugin. Instead the widget notices when it is
missing and offers **Install LocalRecord** in its panel: that downloads the
latest release binary into `~/.local/bin` and starts it, in a terminal window so
you can see what it does. No sudo, and missing system libraries are reported
rather than installed.

The same thing from a shell, if you prefer:

```bash
~/.config/omarchy/plugins/doublea.localrecord/install-localrecord.sh
```

## Interactions

| Input | Action |
|---|---|
| Left click | Open the panel |
| Middle click | Start/stop recording |
| Right click | Nothing, deliberately |

With LocalRecord 1.3.3+, auto-levelling applies only to desktop audio: the microphone
keeps a fixed gain so its hiss does not rise during pauses. With older apps, the
panel keeps the original mic-and-desktop label.

The panel holds start/stop, auto-levelling, launch at login, the tray icon,
format, bitrate, the shortcut picker, the recordings folder, the last recording,
and quit.

Arrows move the cursor and Enter activates; left/right adjust the bitrate and
flip the format. `r` records, `a` toggles auto-levelling, `f` flips the format,
`o` opens the folder, `c` copies the last file's path.

## Settings

Per widget, in Setup > Plugins, or under this widget's entry in
`~/.config/omarchy/shell.json`:

| Key | Default | What it does |
|---|---|---|
| `showElapsed` | `true` | Show the running length next to the icon. Vertical bars never do, for lack of room |
| `hideWhenIdle` | `false` | Keep the widget out of the bar until a recording starts |

## How it talks to the app

Reading is a file, writing is a file.

LocalRecord publishes `~/.local/share/localrecord/state.json` whenever something
changes — whether it is recording, since when, the last file it saved, and the
settings worth mirroring. The widget watches that file, and re-reads it on a slow
timer as well: the app renames the file into place so a reader never catches a
half-written one, and a rename swaps the inode out from under a file watcher.
`pid` is checked against `/proc` so a crashed app does not read as an idle one.

Acting goes back as a line appended to `~/.local/share/localrecord/command`,
which the app polls and applies through the same code paths its tray menu uses —
so the menu, the panel and the state file cannot disagree. Nothing here writes
the app's settings file directly. Signals remain the channel for a compositor
binding: `SIGUSR1` records, `SIGUSR2` toggles auto-levelling.

## Theming

Every colour, font and metric comes from the bar and the shell's theme
singletons, so switching Omarchy themes carries the widget with it. The recording
state uses the theme's `urgent` colour — the same one the bar uses to say
"something needs your attention".

## Licence

MIT, same as LocalRecord.
