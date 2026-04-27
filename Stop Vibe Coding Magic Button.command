#!/bin/bash

set -u

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.vibecoding.vibe-coding-magic-button"
DEST_PLIST="/Library/LaunchDaemons/$LABEL.plist"
SERVER_FILE="$PROJECT_DIR/server.js"
PORT=2000

echo "Stopping Vibe Coding Magic Button..."
echo

/usr/bin/osascript <<OSA
try
  do shell script "launchctl bootout system '$DEST_PLIST' >/dev/null 2>&1 || launchctl bootout system/$LABEL >/dev/null 2>&1 || true; for plist in /Library/LaunchDaemons/*.plist; do if /usr/bin/grep -q '$SERVER_FILE' \"$plist\" 2>/dev/null; then launchctl bootout system \"$plist\" >/dev/null 2>&1 || true; fi; done" with administrator privileges
on error errMsg number errNum
  error errMsg number errNum
end try
OSA

sleep 1

if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Service still appears to be listening on port $PORT."
  echo "You may need to inspect launchd status manually."
  echo
  exit 1
fi

echo "Service stopped."
echo
read -n 1 -s -r -p "Press any key to close..."
echo
