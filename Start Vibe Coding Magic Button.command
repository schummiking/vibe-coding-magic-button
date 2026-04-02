#!/bin/bash

set -u

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_FILE="$PROJECT_DIR/server.js"
PORT=2000
NODE_BIN="/Users/schummiking/.nvm/versions/node/v22.22.0/bin/node"
LOCAL_URL="https://127.0.0.1:$PORT"
PHONE_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"
PHONE_URL="https://$PHONE_IP:$PORT"
LOG_FILE="$PROJECT_DIR/vibe-button.log"

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

if [ ! -x "$NODE_BIN" ]; then
  NODE_BIN="$(command -v node || true)"
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

COMMAND="cd '$PROJECT_DIR' && '$NODE_BIN' '$SERVER_FILE' >> '$LOG_FILE' 2>&1 &"
APPLE_COMMAND=$(printf '%s' "$COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g')

echo "Project: $PROJECT_DIR"
echo "Node: $NODE_BIN"
echo "Phone: $PHONE_URL"
echo "Log:   $LOG_FILE"
echo "Requesting administrator permission..."
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
    echo
    read -n 1 -s -r -p "Press any key to close..."
    echo
    exit 0
  fi
  sleep 1
done

echo "Service did not become ready within 30 seconds."
echo "Check log: $LOG_FILE"
echo
sed -n '1,120p' "$LOG_FILE"
echo
read -n 1 -s -r -p "Press any key to close..."
echo
exit 1
