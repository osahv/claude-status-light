#!/bin/bash
# Builds ClaudeStatus.app (menu bar light) into build/, universal (Apple Silicon + Intel), plus a zip to share.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HERE/build/ClaudeStatus.app"
VERSION="${VERSION:-1.0}"
MIN_OS=13.0
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_OS" "$HERE"/app/*.swift -o "$TMP/ClaudeStatus-$arch"
done
lipo -create "$TMP"/ClaudeStatus-* -output "$APP/Contents/MacOS/ClaudeStatus"
cp "$HERE/bin/report.sh" "$APP/Contents/Resources/report.sh"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ClaudeStatus</string>
<key>CFBundleIdentifier</key><string>local.claude-status-light</string>
<key>CFBundleExecutable</key><string>ClaudeStatus</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign -s - --force "$APP" >/dev/null 2>&1 || true
rm -f "$HERE/build/ClaudeStatus.zip"
ditto -c -k --keepParent "$APP" "$HERE/build/ClaudeStatus.zip"
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeStatus")) and build/ClaudeStatus.zip"
