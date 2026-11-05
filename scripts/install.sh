#!/bin/bash
# 装到 ~/Applications/Naiwa.app，命令行 naiwa 链接到 ~/.local/bin，并设成登录时自动出现
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/Naiwa.app ] || scripts/build_app.sh

DEST=~/Applications/Naiwa.app
BIN=~/.local/bin
AGENT=~/Library/LaunchAgents/com.nwverse.naiwa.plist

[ -x "$DEST/Contents/MacOS/naiwa" ] && "$DEST/Contents/MacOS/naiwa" quit 2>/dev/null || true
mkdir -p ~/Applications "$BIN" ~/Library/LaunchAgents
rm -rf "$DEST"
cp -R build/Naiwa.app "$DEST"
ln -sf "$DEST/Contents/MacOS/naiwa" "$BIN/naiwa"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nwverse.naiwa</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>-a</string><string>${DEST}</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST

open -g -a "$DEST"
echo "装好了：${DEST}，命令行 $BIN/naiwa"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "注意：$BIN 不在 PATH 里，加一行 export PATH=\"$BIN:\$PATH\"";; esac
echo "接入 Claude Code：naiwa hooks install"
