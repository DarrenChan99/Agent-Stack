#!/bin/bash
# One-shot setup on a fresh Mac: build + install Perch.app, wire Claude Code hooks, install auto-rebuild git hooks.
# Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

say "Checking prerequisites"
[ "$(uname)" = Darwin ] || die "Perch is a macOS app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || die "macOS 15 or newer required (you have $(sw_vers -productVersion))."
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null; then
  xcode-select --install 2>/dev/null || true
  die "Command Line Tools missing. Finish the installer that just opened, then re-run: ./Scripts/setup.sh"
fi
swift --version 2>&1 | head -1
command -v claude >/dev/null || echo "note: 'claude' not on PATH. Install Claude Code and log in so Perch has sessions to show."

say "Building and installing ~/Applications/Perch.app (first build takes a few minutes)"
Scripts/build-app.sh
[ -x "$HOME/Applications/Perch.app/Contents/MacOS/Perch" ] ||
  die "No Perch.app. If a build was killed earlier, run: rm -rf ~/Applications/.perch-build.lock — then re-run."

say "Installing Claude Code hooks into ~/.claude/settings.json (backup at settings.json.perch-bak)"
mkdir -p "$HOME/.claude"
"$HOME/Applications/Perch.app/Contents/MacOS/Perch" --install-hooks

say "Installing git hooks (rebuild Perch.app after every commit/pull)"
Scripts/install-git-hook.sh

say "Done"
cat <<'EOF'
Perch is running in your menu bar.
  • Restart any open Claude Code sessions so they pick up the hooks.
  • Optional: Perch → Settings → "Launch at login".
EOF
