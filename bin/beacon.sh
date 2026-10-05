#!/bin/bash
# Start (or restart) the team-bus beacon: a plain HTTP file server on :8099 serving share/.
# Idempotent: does nothing if the beacon already answers. Also keeps the Mac awake (caffeinate).
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/logs" "$PROJECT_DIR/run"

if ! curl -s --max-time 2 -o /dev/null "http://127.0.0.1:8099/info.json"; then
  [ -f "$PROJECT_DIR/run/beacon.pid" ] && kill "$(cat "$PROJECT_DIR/run/beacon.pid")" 2>/dev/null
  nohup python3 -m http.server 8099 --bind 0.0.0.0 --directory "$PROJECT_DIR/share" \
    >> "$PROJECT_DIR/logs/beacon.log" 2>&1 < /dev/null &
  echo $! > "$PROJECT_DIR/run/beacon.pid"
  disown 2>/dev/null
  echo "beacon started (pid $(cat "$PROJECT_DIR/run/beacon.pid"))"
else
  echo "beacon already up"
fi

if ! pgrep -qf "caffeinate -dimsu"; then
  nohup caffeinate -dimsu > /dev/null 2>&1 < /dev/null &
  echo $! > "$PROJECT_DIR/run/caffeinate.pid"
  disown 2>/dev/null
  echo "caffeinate started (pid $(cat "$PROJECT_DIR/run/caffeinate.pid"))"
fi
