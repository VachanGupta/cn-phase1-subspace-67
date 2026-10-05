#!/bin/bash
# mac_aanya: stop this Mac's subspace_67 services (nginx edge, team-bus beacon, caffeinate).
# No sudo needed: everything was started as the normal user. System settings (DNS, CA trust)
# are NOT touched here; restore_network.sh undoes those after the project.
P="$(cd "$(dirname "$0")" && pwd)"
NGINX=/opt/homebrew/bin/nginx

# mark the edge as not ready while the beacon can still publish it
python3 "$P/scripts/info.py" edge_ready=false >/dev/null 2>&1

if [ -s "$P/run/nginx.pid" ] && kill -0 "$(cat "$P/run/nginx.pid")" 2>/dev/null; then
  "$NGINX" -s quit && echo "nginx: graceful stop sent (pid $(cat "$P/run/nginx.pid"))"
else
  echo "nginx: not running"
fi

if [ -s "$P/run/beacon.pid" ] && kill -0 "$(cat "$P/run/beacon.pid")" 2>/dev/null; then
  kill "$(cat "$P/run/beacon.pid")" && echo "beacon: stopped (loop pid $(cat "$P/run/beacon.pid"))"
fi
pkill -f "http.server 8099 --bind 0.0.0.0 --directory $P/share" 2>/dev/null && echo "beacon: http.server stopped"

if [ -s "$P/run/caffeinate.pid" ] && kill -0 "$(cat "$P/run/caffeinate.pid")" 2>/dev/null; then
  kill "$(cat "$P/run/caffeinate.pid")" && echo "caffeinate: stopped"
fi
rm -f "$P/run/beacon.pid" "$P/run/caffeinate.pid"
echo "stopped. (start again with ./start.sh)"
