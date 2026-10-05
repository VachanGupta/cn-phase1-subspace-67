#!/bin/bash
# mac_abhay (Mac 3: Backend A + main test client) - one-shot start for demo day.
#   ./start.sh [peer_ip ...]      (optional peer IPs as hints if a peer is outside our /22)
# Steps: keep awake -> team-bus beacon :8099 -> rediscover peers -> fix configs whose IPs changed
#        (DNS server = mac_vachan, supervisor control URL, CA check) -> Backend A -> verify.
# sudo is used ONLY if this Mac's DNS must be re-pointed or the CA re-trusted (IP/CA changed).
set -u
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR" || exit 1
export PROJECT_DIR
source tools/evidence_lib.sh
mkdir -p logs share certs
SERVICE="Wi-Fi"
HOST="app.subspace-67.test"
step() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }
ok()   { printf "  \033[32mOK\033[0m   %s\n" "$*"; }
bad()  { printf "  \033[31mFAIL\033[0m %s\n" "$*"; }

step "1. Keep this Mac awake (lid open, charger in)"
pgrep -qf "caffeinate -dimsu" || { nohup caffeinate -dimsu >/dev/null 2>&1 & disown; }
ok "caffeinate running (pid $(pgrep -f 'caffeinate -dimsu' | head -1))"

step "2. Team-bus beacon on :8099 + info.json"
python3 tools/info.py >/dev/null   # refresh IP/MAC facts; flags are set from the checks in step 6
if ! lsof -nP -iTCP:8099 -sTCP:LISTEN >/dev/null 2>&1; then
  nohup python3 -m http.server 8099 --bind 0.0.0.0 --directory "$PROJECT_DIR/share" >> logs/beacon.log 2>&1 &
  echo $! > logs/beacon.pid; disown; sleep 1
fi
ME=$(ipconfig getifaddr "$(route -n get default | awk '/interface:/{print $2}')")
curl -s --max-time 2 "http://$ME:8099/info.json" >/dev/null && ok "beacon http://$ME:8099/info.json" || bad "beacon not answering"

step "3. Rediscover peers (hints: args, old peers.json, peers' peers.json, ARP cache, /22 scan)"
for i in $(seq 1 60); do
  if python3 tools/discover.py "$@" $(cat tools/hints.txt 2>/dev/null); then break; fi
  echo "  ...not all 3 found yet (try $i/60); retrying in 5 s"; sleep 5
done
V=$(peer_ip mac_vachan); A=$(peer_ip mac_aanya)
[ -n "$V" ] && ok "mac_vachan = $V" || bad "mac_vachan not found (pass its IP: ./start.sh <ip>)"
[ -n "$A" ] && ok "mac_aanya  = $A" || bad "mac_aanya not found (pass its IP: ./start.sh <ip>)"

step "4. Configs that depend on peer IPs"
NEED_ROOT=0
CUR_DNS=$(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ' | sed 's/ $//')
if [ -n "$V" ] && [ "$CUR_DNS" != "$V" ]; then
  echo "  DNS for $SERVICE is '$CUR_DNS' but mac_vachan is $V -> needs re-pointing (sudo)"; NEED_ROOT=1
else ok "DNS server = $CUR_DNS (mac_vachan)"; fi
if [ -n "$A" ] && curl -s --max-time 3 -o certs/ca.crt.new "http://$A:8099/ca.crt"; then
  NEW_FP=$(openssl x509 -in certs/ca.crt.new -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  OLD_FP=$(openssl x509 -in certs/ca.crt -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  if [ -n "$NEW_FP" ] && [ "$NEW_FP" != "$OLD_FP" ]; then
    echo "  mac_aanya's CA changed ($OLD_FP -> $NEW_FP)."
    echo "  Check the new fingerprint with mac_aanya, then set EXPECTED_FP in sudo/01_dns_and_ca.sh and re-run it."
    mv certs/ca.crt.new certs/ca.crt.candidate
  else rm -f certs/ca.crt.new; ok "CA unchanged ($OLD_FP)"; fi
fi
if [ "$NEED_ROOT" = 1 ]; then
  echo "  Running the root batch (your Mac password is asked once):"
  sudo bash "$PROJECT_DIR/sudo/01_dns_and_ca.sh"
fi

step "5. Backend A (supervisor follows http://$V:8099/control.json)"
WANT_URL="http://$V:8099/control.json"
RUNNING=$(pgrep -f "backend/supervisor.py --id A" | head -1)
if [ -n "$RUNNING" ] && ! ps -o command= -p "$RUNNING" | grep -q -- "--control-url $WANT_URL"; then
  echo "  supervisor points at an old control URL -> restarting it"
  kill "$RUNNING"; sleep 3; RUNNING=""
fi
if [ -z "$RUNNING" ]; then
  nohup python3 backend/supervisor.py --id A --port 3001 --control-url "$WANT_URL" >> logs/backend_A.log 2>&1 &
  echo $! > logs/backend_A_supervisor.pid; disown
  for i in $(seq 1 20); do lsof -nP -iTCP:3001 -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 0.5; done
fi

step "6. Verify"
lsof -nP -iTCP:3001 -sTCP:LISTEN | grep -q '\*:3001' && ok "Backend A listening on *:3001" || bad "nothing on *:3001"
if curl -s --max-time 3 "http://$ME:3001/api/status" | grep -q '"backend": "A"'; then
  ok "http://$ME:3001/api/status answers (X-Backend: A)"; python3 tools/info.py backend_A_ready=true >/dev/null
else bad "Backend A does not answer on $ME:3001"; python3 tools/info.py backend_A_ready=false >/dev/null; fi
DIG=$(dig +time=2 +tries=1 "$HOST")
DIG_SERVER=$(echo "$DIG" | awk '/;; SERVER:/{print $3}' | cut -d'#' -f1)
DIG_ANS=$(echo "$DIG" | awk -v h="$HOST." '$1==h && $4=="A"{print $5}' | head -1)
[ "$DIG_SERVER" = "$V" ] && ok "dig SERVER = $DIG_SERVER (mac_vachan)" || bad "dig SERVER = '$DIG_SERVER' (expected $V)"
[ "$DIG_ANS" = "$A" ] && ok "$HOST -> $DIG_ANS (mac_aanya, the edge)" || bad "$HOST -> '$DIG_ANS' (expected $A)"
EDGE_PORT=$(curl -s --max-time 3 "http://$A:8099/info.json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',{}).get('edge_port') or 443)" 2>/dev/null || echo 443)
URL="https://$HOST/api/status"; [ "$EDGE_PORT" != "443" ] && URL="https://$HOST:$EDGE_PORT/api/status"
echo "  4 requests through the edge ($URL), certificate verified against our CA, no -k:"
for i in 1 2 3 4; do
  printf "    %s  " "$i"
  /usr/bin/curl -s --cacert certs/ca.crt -o /dev/null -D - --max-time 5 "$URL" | awk 'tolower($1)=="x-backend:"{printf "X-Backend: %s", $2} /^HTTP/{printf "%s ", $0}' | tr -d '\r'; echo
done
echo
echo "Done. Logs: logs/backend_A.log (Backend A requests), logs/beacon.log. Stop with ./stop.sh"
