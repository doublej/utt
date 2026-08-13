#!/usr/bin/env zsh
# Build + sign the Phase 0 spike as dev.jurrejan.utt so its TCC grants carry
# over to the real app (same bundle id + same cert root => same designated requirement).
set -euo pipefail
cd "${0:h}"

IDENTITY="A4F985E255EAA49E09BCA155A81331F318CA59CB"
KEYCHAIN="$HOME/Library/Keychains/utt-dev.keychain-db"
APP="Spike.app"

security unlock-keychain -p uttdev "$KEYCHAIN"

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" build

swiftc -O -swift-version 6 -target arm64-apple-macos26.0 \
    -o "$APP/Contents/MacOS/utt" main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>utt</string>
  <key>CFBundleIdentifier</key><string>dev.jurrejan.utt</string>
  <key>CFBundleName</key><string>utt</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>utt records your voice so it can transcribe it on-device.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>utt watches for your push-to-talk hotkey.</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --timestamp=none \
    --entitlements utt.entitlements \
    --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP"

codesign -d -r- "$APP" 2>&1 | tail -1
echo "built: $PWD/$APP"
