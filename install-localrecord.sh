#!/bin/bash

# Installs the LocalRecord binary this widget drives.
#
# `omarchy plugin add` deliberately runs no code — no install hooks, no sudo —
# so the app cannot come along with the plugin. This script is what the panel's
# "Install LocalRecord" row runs instead: one click, visible, and undoable by
# deleting one file.
#
# No sudo either. The binary lands in ~/.local/bin, which Omarchy already has on
# PATH, and system libraries are only reported, never installed.

set -euo pipefail

REPO="AntoineArt/localrecord"
PREFIX="${LOCALRECORD_PREFIX:-$HOME/.local/bin}"
TARGET="$PREFIX/localrecord"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

for tool in curl jq; do
  command -v "$tool" >/dev/null || die "$tool is required to install LocalRecord."
done

say "Finding the latest LocalRecord release"
asset=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
  jq -r '.assets[] | select(.name | test("x86_64-linux$")) | .browser_download_url' | head -1)
version=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name')
[[ -n $asset && $asset != null ]] || die "No Linux asset on the latest release."
echo "$version — $(basename "$asset")"

say "Downloading"
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
curl -fL --progress-bar -o "$temporary" "$asset"

# Installed as one atomic rename, so a running LocalRecord keeps its own inode
# and an interrupted download never leaves half a binary on PATH.
mkdir -p "$PREFIX"
chmod +x "$temporary"
mv -f "$temporary" "$TARGET"
trap - EXIT
say "Installed $TARGET"

# The app links against the desktop's audio and tray libraries. Reporting is as
# far as this goes: installing packages is the user's call, with their own sudo.
missing=$(ldd "$TARGET" 2>/dev/null | awk '/not found/ { print $1 }' | sort -u)
if [[ -n $missing ]]; then
  warn "Missing system libraries:"
  printf '  %s\n' $missing
  warn "On Arch: sudo pacman -S --needed libpulse opus gtk3 libappindicator-gtk3 pipewire-pulse zenity xdg-utils"
  exit 1
fi

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) warn "$PREFIX is not on your PATH — add it to use \`localrecord\` from a shell." ;;
esac

if pgrep -x localrecord >/dev/null; then
  say "Already running — restart it to pick up $version"
else
  say "Starting LocalRecord"
  setsid "$TARGET" >/dev/null 2>&1 < /dev/null &
  # The widget reads the app's state file; give it a moment to appear so the
  # panel is already correct when this window closes.
  for _ in {1..20}; do
    [[ -f "$HOME/.local/share/localrecord/state.json" ]] && break
    sleep 0.1
  done
fi

say "Done. The bar widget now drives it."
