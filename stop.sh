#!/bin/bash
# subspace_67 / mac_vachan - stop this Mac's project processes:  ./stop.sh
#   Backend B (supervisor + backend.py), the team-bus beacon (:8099) and the caffeinate we started.
#   dnsmasq is left running on purpose: the other two Macs use it as their ONLY DNS server, so
#   stopping it would cut their internet name resolution. Stop it with
#   `sudo brew services stop dnsmasq` only after they have restored their DNS (or run
#   `sudo ./restore_network.sh`, which does everything).
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR" || exit 1

stop_pidfile() {  # name pidfile pattern
  local pid; pid=$(cat "$2" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -o command= -p "$pid" | grep -q "$3"; then
    kill "$pid"; echo "stopped $1 (pid $pid)"
  fi
  rm -f "$2"
}
stop_pidfile "Backend B supervisor" run/supervisor_B.pid "supervisor.py --id B"
pkill -f "supervisor.py --id B" 2>/dev/null
sleep 1
pkill -f "backend/backend.py" 2>/dev/null     # the supervisor stops its child; this is a safety net
nc -z 127.0.0.1 3002 2>/dev/null && echo "WARNING: something still listens on 3002" || echo "Backend B down (3002 closed)"
stop_pidfile "team-bus beacon" run/beacon.pid "http.server 8099"
stop_pidfile "caffeinate" run/caffeinate.pid "caffeinate"
echo "dnsmasq left running (other Macs depend on it); see the header of this file."
