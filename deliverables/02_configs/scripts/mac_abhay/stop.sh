#!/bin/bash
# mac_abhay: stop this Mac's project processes (Backend A + its supervisor, beacon, caffeinate).
# System settings (DNS server, trusted CA) are left alone: undo those with ./restore_network.sh
set -u
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR" || exit 1
python3 tools/info.py backend_A_ready=false >/dev/null 2>&1   # tell peers before the beacon goes away
if pgrep -f "backend/supervisor.py --id A" >/dev/null; then
  pkill -TERM -f "backend/supervisor.py --id A"      # the supervisor stops its backend.py child
  sleep 3
fi
pkill -TERM -f "$PROJECT_DIR/backend/backend.py" 2>/dev/null   # leftover child, if any
pkill -TERM -f "http.server 8099 --bind 0.0.0.0 --directory $PROJECT_DIR/share" 2>/dev/null
pkill -TERM -f "caffeinate -dimsu" 2>/dev/null
sleep 1
echo "port 3001: $(lsof -nP -iTCP:3001 -sTCP:LISTEN >/dev/null 2>&1 && echo STILL OPEN || echo closed)"
echo "port 8099: $(lsof -nP -iTCP:8099 -sTCP:LISTEN >/dev/null 2>&1 && echo STILL OPEN || echo closed)"
echo "caffeinate: $(pgrep -f 'caffeinate -dimsu' >/dev/null && echo running || echo stopped)"
