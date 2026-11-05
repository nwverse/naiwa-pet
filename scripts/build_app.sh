#!/bin/bash
# 编译并打包成 build/Naiwa.app（只需要 Command Line Tools，不需要 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-0.1.0}
APP=build/Naiwa.app

# 两种芯片都编一份再合并；Intel 那份编不出来就只发本机架构
swift build -c release --triple arm64-apple-macosx13.0
bins=(.build/arm64-apple-macosx/release/naiwa)
if swift build -c release --triple x86_64-apple-macosx13.0 2>/dev/null; then
    bins+=(.build/x86_64-apple-macosx/release/naiwa)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/naiwa"
cp -R assets "$APP/Contents/Resources/assets"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.nwverse.naiwa</string>
  <key>CFBundleName</key><string>Naiwa</string>
  <key>CFBundleDisplayName</key><string>奶蛙</string>
  <key>CFBundleExecutable</key><string>naiwa</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 没有开发者账号，先做 ad-hoc 签名，本机和同事机器都能跑
codesign --force --sign - "$APP" >/dev/null
echo "${APP}（$(du -sh "$APP" | cut -f1)，$(lipo -archs "$APP/Contents/MacOS/naiwa")）"
