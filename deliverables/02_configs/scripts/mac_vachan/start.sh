#!/bin/bash
# subspace_67 / mac_vachan (Mac 1: DNS server + Backend B + client + integrator)
# Demo-day start - safe to re-run:   cd ~/Desktop/work/CN && ./start.sh
#   1. team-bus beacon (:8099) + caffeinate, refresh share/info.json (new IP/mask/gateway/MAC)
#   2. rediscover peers (IPs always from their own info.json) -> peers.json
#   3. Backend B via the supervisor (ID=B, PORT=3002); restarted if this Mac's IP changed
#   4. regenerate configs/dnsmasq.conf (app/api -> mac_aanya's current IP, listen on our current IP);
#      sudo ONLY if something changed: restart the root dnsmasq service / repoint this Mac's DNS
#   5. verify DNS, HTTPS (no -k) and A/B round robin, and publish the status flags
# Start order on demo day: run ./start.sh on all 3 Macs (any order; each waits for the others).
set -u
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR" || exit 1
step() { printf '\n== %s\n' "$*"; }
ok=1

step "1. team bus + keep awake"
bash bin/beacon.sh
python3 bin/info.py init > /dev/null
python3 bin/info.py set failures_in_progress=false > /dev/null
IP=$(jq -r .ip share/info.json)
[ -f share/control.json ] && grep -q '"down"' share/control.json && echo "control.json had a backend down -> resetting"
python3 -c 'import json,os; p="share/control.json"; json.dump({"A":"up","B":"up"}, open(p+".tmp","w")); os.replace(p+".tmp",p)'
echo "this Mac: $IP ($(jq -r .interface share/info.json), gateway $(jq -r .gateway share/info.json)); bus http://$IP:8099/"

step "2. peers (waits up to 5 min for all three beacons)"
python3 bin/discover.py --loop 300 || echo "WARNING: not all peers found yet; continuing with last known IPs"
jq -r 'to_entries[] | "  \(.key) = \(.value.ip)  reachable_now=\(.value.reachable_now)"' peers.json
AANYA=$(jq -r .mac_aanya.ip peers.json)

step "3. Backend B"
bash bin/start_backend_B.sh
curl -s --max-time 3 "http://$IP:3002/api/status" | grep -q '"backend": "B"' && echo "Backend B answers on $IP:3002" || { echo "Backend B NOT answering"; ok=0; }

step "4. DNS server (dnsmasq)"
GEN=$(python3 bin/gen_dnsmasq.py) || { echo "$GEN"; ok=0; }
echo "$GEN"
need_root=0
echo "$GEN" | grep -q '^CHANGED' && need_root=1
[ "$(dig @"$IP" app.subspace-67.test +short +time=1 +tries=1)" = "$AANYA" ] || need_root=1
[ "$(networksetup -getdnsservers Wi-Fi | tr -d '\n')" = "$IP" ] || need_root=1
if [ $need_root = 1 ]; then
  echo "DNS server/config or this Mac's DNS setting must be (re)applied -> sudo needed once:"
  sudo bash "$PROJECT_DIR/sudo/10_apply_dns.sh" || ok=0
else
  echo "dnsmasq already serving the current config; this Mac already uses $IP as DNS (no sudo needed)"
fi

step "5. verify"
. bin/tls_env.sh
A=$(dig app.subspace-67.test +short); S=$(dig app.subspace-67.test | awk '/SERVER:/{print $3}')
echo "dig app.subspace-67.test -> $A (server $S)"
[ "$A" = "$AANYA" ] || ok=0
if curl -s --max-time 5 -o /dev/null https://app.subspace-67.test/api/status; then
  seq_ab=$(for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | awk -F': ' 'tolower($1)=="x-backend"{printf "%s ", $2}' | tr -d '\r'; done)
  echo "HTTPS OK (certificate verified, no -k); X-Backend sequence: $seq_ab"
  echo "$seq_ab" | grep -q A && echo "$seq_ab" | grep -q B || echo "note: only one backend seen (is the other Mac's start.sh done?)"
else
  echo "HTTPS to https://app.subspace-67.test failed:"; curl -sS --max-time 5 -o /dev/null https://app.subspace-67.test/api/status; ok=0
fi
python3 bin/info.py set backend_B_ready=true > /dev/null
[ $ok = 1 ] && python3 bin/info.py set dns_ready=true > /dev/null
echo; [ $ok = 1 ] && echo "mac_vachan READY" || echo "mac_vachan has problems - see above"
