#!/bin/sh
# ./install.sh = build FastShot.app into ~/Applications and launch it; ./install.sh --uninstall = remove
set -e
APP="$HOME/Applications/FastShot.app"
OLD_PLIST="$HOME/Library/LaunchAgents/com.fastshot.plist"
launchctl unload "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST" "$HOME/.local/bin/fastshot"
pkill -x FastShot 2>/dev/null || true
[ "$1" = "--uninstall" ] && { rm -rf "$APP"; echo removed; exit 0; }
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" "$(dirname "$0")"/Sources/*.swift -o "$APP/Contents/MacOS/FastShot"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.fastshot.app</string>
<key>CFBundleName</key><string>FastShot</string>
<key>CFBundleExecutable</key><string>FastShot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Record your voice with screen recordings.</string>
</dict></plist>
EOF
# a real identity keeps the Screen Recording grant across rebuilds; ad-hoc resets it each time
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
codesign -f -s "${ID:--}" "$APP"
open "$APP"
echo "installed: $APP — grant Screen Recording when asked (Settings window shows status)."
