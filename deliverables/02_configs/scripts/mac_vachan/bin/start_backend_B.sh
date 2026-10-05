#!/bin/bash
# Start Backend B (supervisor + backend.py, ID=B, PORT=3002) if it isn't already running with the
# right control URL. The control URL uses this Mac's *current* LAN IP, so a restart after an IP
# change picks up the new address.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1
IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}'); IF=${IF:-en0}
IP=$(ipconfig getifaddr "$IF")
URL="http://$IP:8099/control.json"
PIDF=run/supervisor_B.pid

running_pid=""
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && ps -o command= -p "$(cat "$PIDF")" | grep -q "supervisor.py --id B"; then
  running_pid=$(cat "$PIDF")
fi
if [ -n "$running_pid" ] && [ "$(cat run/supervisor_B.url 2>/dev/null)" = "$URL" ]; then
  echo "Backend B supervisor already running (pid $running_pid, control $URL)"
  exit 0
fi
if [ -n "$running_pid" ]; then
  echo "control URL changed -> restarting Backend B supervisor"
  kill "$running_pid"; sleep 2
fi
pkill -f "supervisor.py --id B" 2>/dev/null; sleep 0.5
nohup python3 "$PROJECT_DIR/backend/supervisor.py" --id B --port 3002 --control-url "$URL" \
  >> "$PROJECT_DIR/logs/backend_B.log" 2>&1 < /dev/null &
echo $! > "$PIDF"
echo "$URL" > run/supervisor_B.url
disown 2>/dev/null
for i in $(seq 1 30); do nc -z 127.0.0.1 3002 2>/dev/null && break; sleep 0.2; done
echo "Backend B supervisor started (pid $(cat "$PIDF"), control $URL)"
