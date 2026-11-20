#!/bin/bash
# Build, ad-hoc sign and (re)install ~/Applications/Perch.app, then relaunch it.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/lock.sh
mkdir -p "$HOME/Applications"
acquire_lock "$HOME/Applications/.perch-build.lock" # overlapping runs (rebase/cherry-pick commits) exit quietly
swift build -c release --product Perch
swift build -c release --product perch-hook
BIN=$(swift build -c release --show-bin-path)

DEST="$HOME/Applications/Perch.app"
mkdir -p "$HOME/Applications"
TMP=$(mktemp -d "$HOME/Applications/.perch-build.XXXXXX")
QUIT=0
cleanup() { # failure after the old app was quit: put it back and relaunch
  local rc=$?
  rm -rf "$TMP"
  if [ $rc -ne 0 ] && [ $QUIT = 1 ]; then
    [ -e "$DEST.old" ] && [ ! -e "$DEST" ] && mv "$DEST.old" "$DEST"
    [ -e "$DEST" ] && open "$DEST"
  fi
  rm -rf "$LOCKDIR"
}
trap cleanup EXIT
APP="$TMP/Perch.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Perch" "$BIN/perch-hook" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.perch.Perch</string>
<key>CFBundleExecutable</key><string>Perch</string>
<key>CFBundleName</key><string>Perch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>$(git rev-list --count HEAD)</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Perch brings the Terminal tab running your agent to the front.</string>
</dict></plist>
PL
codesign --force --deep -s - "$APP"

QUIT=1
osascript -e 'quit app "Perch"' >/dev/null 2>&1 || pkill -x Perch || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Perch >/dev/null || break; sleep 0.3; done
pkill -x Perch || true
rm -rf "$DEST.old"
[ -e "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$APP" "$DEST"
rm -rf "$DEST.old"
open "$DEST"
