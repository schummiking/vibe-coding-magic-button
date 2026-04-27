#!/bin/bash

set -u

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.vibecoding.vibe-coding-magic-button"
TEMPLATE_FILE="$PROJECT_DIR/launchd/$LABEL.plist.template"
SERVER_FILE="$PROJECT_DIR/server.js"
PORT=2000
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
LOCAL_URL="https://127.0.0.1:$PORT"
PHONE_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"
PHONE_URL="https://$PHONE_IP:$PORT"
LOG_FILE="$PROJECT_DIR/vibe-button.log"
RENDERED_PLIST="$PROJECT_DIR/$LABEL.plist"
DEST_PLIST="/Library/LaunchDaemons/$LABEL.plist"

is_running() {
  curl -ks --max-time 2 "$LOCAL_URL/ping" 2>/dev/null | grep -qx 'pong'
}

echo "Starting Vibe Coding Magic Button..."
echo

if is_running; then
  echo "Service is already running."
  echo "Phone: $PHONE_URL"
  echo "Local: $LOCAL_URL"
  echo "Log:   $LOG_FILE"
  echo
  read -n 1 -s -r -p "Press any key to close..."
  echo
  exit 0
fi

if [ ! -f "$SERVER_FILE" ]; then
  echo "server.js not found:"
  echo "$SERVER_FILE"
  echo
  read -n 1 -s -r -p "Press any key to close..."
  echo
  exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "launchd template not found:"
  echo "$TEMPLATE_FILE"
  echo
  read -n 1 -s -r -p "Press any key to close..."
  echo
  exit 1
fi

if [ -z "${NODE_BIN:-}" ] || [ ! -x "$NODE_BIN" ]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    if [ -x "$candidate" ]; then
      NODE_BIN="$candidate"
      break
    fi
  done
fi

if [ -z "${NODE_BIN:-}" ]; then
  echo "Node.js not found."
  echo
  read -n 1 -s -r -p "Press any key to close..."
  echo
  exit 1
fi

cd "$PROJECT_DIR" || exit 1
: > "$LOG_FILE"

sed \
  -e "s|__NODE_BIN__|$NODE_BIN|g" \
  -e "s|__SERVER_FILE__|$SERVER_FILE|g" \
  -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
  -e "s|__LOG_FILE__|$LOG_FILE|g" \
  "$TEMPLATE_FILE" > "$RENDERED_PLIST"

ADMIN_COMMAND="install -m 644 '$RENDERED_PLIST' '$DEST_PLIST'; launchctl bootout system '$DEST_PLIST' >/dev/null 2>&1 || true; launchctl bootstrap system '$DEST_PLIST'; launchctl kickstart -k system/$LABEL"
APPLE_COMMAND=$(printf '%s' "$ADMIN_COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g')

echo "Project: $PROJECT_DIR"
echo "Node: $NODE_BIN"
echo "Phone: $PHONE_URL"
echo "Log:   $LOG_FILE"
echo "Installing launchd service..."
echo

/usr/bin/osascript <<OSA
try
  do shell script "$APPLE_COMMAND" with administrator privileges
on error errMsg number errNum
  error errMsg number errNum
end try
OSA

for i in {1..30}; do
  if is_running; then
    echo "Service is running."
    echo "Phone: $PHONE_URL"
    echo "Local: $LOCAL_URL"
    echo "launchd: system/$LABEL"
    echo
    read -n 1 -s -r -p "Press any key to close..."
    echo
    exit 0
  fi
  sleep 1
done

echo "Service did not become ready within 30 seconds."
echo "Check log: $LOG_FILE"
echo "launchd plist: $DEST_PLIST"
echo
sed -n '1,120p' "$LOG_FILE"
echo
read -n 1 -s -r -p "Press any key to close..."
echo
exit 1
