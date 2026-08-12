#!/bin/bash
# Builds KeyLaunch.app into /Applications.
#
# The app must run as a signed bundle: macOS attaches the Accessibility (TCC)
# grant to the bundle's code signature, and a bare binary run from the shell
# gets denied when it tries to create the event tap.
set -euo pipefail

cd "$(dirname "$0")"
APP="/Applications/KeyLaunch.app"

swift build -c release

# Quit any running copy so the bundle can be replaced.
pkill -x KeyLaunch 2>/dev/null || true
sleep 0.3

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/KeyLaunch "$APP/Contents/MacOS/KeyLaunch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable ad-hoc identity keeps the Accessibility grant across rebuilds;
# without --identifier the hash changes and macOS treats it as a new app.
codesign --force --sign - --identifier com.alfonsokim.keylaunch "$APP"

echo "Built $APP"
