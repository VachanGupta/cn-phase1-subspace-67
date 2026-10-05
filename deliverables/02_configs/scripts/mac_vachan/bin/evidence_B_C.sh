#!/bin/bash
# Collect Task B (DNS) and Task C (Backend B) evidence on mac_vachan into share/evidence/mac_vachan/.
# Every file = the exact command + its full output. Peer IPs come from peers.json (their info.json).
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1
. bin/tls_env.sh 2>/dev/null        # sets the curl trust-store env if /usr/bin/curl needs it
ME=$(jq -r .ip share/info.json); AANYA=$(jq -r .mac_aanya.ip peers.json); ABHAY=$(jq -r .mac_abhay.ip peers.json)
B=share/evidence/mac_vachan/task_B_dns; C=share/evidence/mac_vachan/task_C_backend_B
mkdir -p "$B" "$C"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
hdr() { echo "# $1 - captured on mac_vachan ($ME) $(date '+%F %T %Z')"; echo "# mac_aanya (edge) = $AANYA, mac_abhay = $ABHAY, mac_vachan (DNS server + Backend B) = $ME"; echo; }

# ---------------- Task B: DNS ----------------
{ hdr "Task B - DNS resolution through our own server"
  run "networksetup -getdnsservers Wi-Fi"
  run "dig app.subspace-67.test"
  run "dig api.subspace-67.test +noall +answer +stats"
  run "dig @$ME app.subspace-67.test"
  run "dig @127.0.0.1 app.subspace-67.test +noall +answer"
  run "dig app.subspace-67.test AAAA +noall +comments +answer | grep -E 'status|ANSWER|app'"
  run "dig nosuchhost.subspace-67.test | grep -E 'status|SERVER|AUTHORITY'"
  run "dig google.com +noall +answer +stats"
  run "dig api.anthropic.com +short"
  run "dig -x $AANYA +short"
  run "nslookup app.subspace-67.test"
  run "nslookup api.subspace-67.test $ME"
  run "dscacheutil -q host -a name app.subspace-67.test"
} > "$B/dig_nslookup.txt"
{ hdr "Task B - macOS resolver configuration (scutil --dns, first resolvers)"
  run "scutil --dns | sed -n '1,25p'"
  run "scutil --dns | grep -A6 'for scoped queries' | head -12"
} > "$B/scutil_dns.txt"
{ hdr "Task B - dnsmasq is the DNS server: sockets, service, config"
  run "lsof -nP -i :53 2>/dev/null | head; echo '(root-owned sockets are hidden from a normal user; the dig answers above prove the listener)'"
  run "brew services info dnsmasq"
  run "cat /opt/homebrew/etc/dnsmasq.conf"
  run "cat configs/dnsmasq.conf"
} > "$B/dnsmasq_service_and_config.txt"
{ hdr "Task B - dnsmasq query log: which clients asked (lines from $AANYA = mac_aanya, $ABHAY = mac_abhay)"
  echo "\$ grep -E 'from ($AANYA|$ABHAY)' logs/dnsmasq.log | grep -E 'subspace-67' | head -40"
  grep -E "from ($AANYA|$ABHAY)" logs/dnsmasq.log | grep -E 'subspace-67' | head -40; echo
  echo "\$ grep -E 'from ($AANYA|$ABHAY)' logs/dnsmasq.log | grep -vE 'subspace-67' | head -15   # forwarded internet names"
  grep -E "from ($AANYA|$ABHAY)" logs/dnsmasq.log | grep -vE 'subspace-67' | head -15; echo
  echo "\$ grep -cE 'from $AANYA' logs/dnsmasq.log; grep -cE 'from $ABHAY' logs/dnsmasq.log; grep -cE 'from ($ME|127.0.0.1)' logs/dnsmasq.log"
  echo "queries from mac_aanya: $(grep -cE "from $AANYA" logs/dnsmasq.log)"
  echo "queries from mac_abhay: $(grep -cE "from $ABHAY" logs/dnsmasq.log)"
  echo "queries from mac_vachan itself: $(grep -cE "from ($ME|127.0.0.1)" logs/dnsmasq.log)"; echo
  echo "\$ grep -E 'config app.subspace-67.test|query\\[A\\] app.subspace-67.test' logs/dnsmasq.log | tail -6"
  grep -E 'config app.subspace-67.test|query\[A\] app.subspace-67.test' logs/dnsmasq.log | tail -6
} > "$B/dnsmasq_log_clients.txt"

# ---------------- Task C: Backend B ----------------
{ hdr "Task C - Backend B endpoints and headers (direct, bypassing the edge)"
  run "curl -si http://$ME:3002/"
  run "curl -sI http://$ME:3002/"
  run "curl -si http://$ME:3002/api/status"
  run "curl -si http://$ME:3002/api/cache-demo"
  ET=$(curl -sI "http://$ME:3002/api/cache-demo" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
  run "curl -si -H 'If-None-Match: $ET' http://$ME:3002/api/cache-demo"
  run "curl -si http://$ME:3002/nope"
} > "$C/endpoints_headers.txt"
{ hdr "Task C - Backend B process and socket"
  run "lsof -nP -iTCP:3002 -sTCP:LISTEN"
  run "ps -o pid,ppid,etime,command -p \$(pgrep -f 'supervisor.py --id B' | head -1),\$(pgrep -f 'backend/backend.py' | head -1)"
  run "cat run/supervisor_B.url"
} > "$C/lsof_process.txt"
{ hdr "Task C - Backend B log: requests arrive from the EDGE ($AANYA), the real client only appears in X-Forwarded-For"
  echo "\$ grep 'client=$AANYA' logs/backend_B.log | tail -25"
  grep "client=$AANYA" logs/backend_B.log | tail -25; echo
  echo "\$ grep -c 'client=$AANYA' logs/backend_B.log   # requests from the edge"
  grep -c "client=$AANYA" logs/backend_B.log; echo
  echo "\$ grep -vE 'client=($AANYA|$ME|127.0.0.1)' logs/backend_B.log | grep -c 'client='   # requests from anyone else (clients never connect directly)"
  grep -vE "client=($AANYA|$ME|127.0.0.1)" logs/backend_B.log | grep -c 'client='
  echo
  echo "\$ grep '\\[supervisor\\]' logs/backend_B.log | tail -8"
  grep '\[supervisor\]' logs/backend_B.log | tail -8
} > "$C/backend_B_log_from_edge.txt"
ls -la "$B" "$C"
