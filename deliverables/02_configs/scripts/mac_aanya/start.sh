#!/bin/bash
# =====================================================================================
# mac_aanya (edge: nginx reverse proxy + load balancer + TLS termination + local CA)
# One command for demo day, even if the Wi-Fi handed out new IPs:
#
#     ./start.sh                  (optionally: ./start.sh <peer_ip> <peer_ip>  as discovery hints)
#
#   1. keeps the Mac awake (caffeinate) and starts the team-bus beacon on :8099
#   2. refreshes share/info.json with this Mac's current IP/mask/gateway/MAC
#   3. rediscovers mac_vachan + mac_abhay (hint IPs, then peers.json, then a /22 scan) -> peers.json
#   4. makes sure the CA + server cert exist (the CA is kept; peers already trust it)
#   5. regenerates the nginx config from the peers' CURRENT IPs; starts or reloads nginx
#   6. checks whether this Mac still uses mac_vachan as DNS and trusts our CA. If not, prints
#      the ONE sudo command to run (the only step that needs a password)
#   7. verifies end to end: dig, HTTPS with full validation (no -k), 10 requests A/B, HTTP/1.1 + HTTP/2
# Stop with ./stop.sh; undo system changes after the project with sudo ./restore_network.sh
# =====================================================================================
set -u
P="$(cd "$(dirname "$0")" && pwd)"
cd "$P" || exit 1
NGINX=/opt/homebrew/bin/nginx
mkdir -p share/evidence/mac_aanya logs run configs tls sudo
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
info() { printf '  ..   %s\n' "$*"; }
FAILS=0

echo "== 1. caffeinate + beacon"
if ! { [ -s run/caffeinate.pid ] && kill -0 "$(cat run/caffeinate.pid)" 2>/dev/null; }; then
  nohup caffeinate -dimsu >/dev/null 2>&1 </dev/null & echo $! > run/caffeinate.pid
fi
ok "caffeinate pid $(cat run/caffeinate.pid) (keep the lid open and the charger in)"
if ! nc -z 127.0.0.1 8099 >/dev/null 2>&1; then
  nohup bash scripts/beacon.sh > logs/beacon_loop.log 2>&1 </dev/null & echo $! > run/beacon.pid
  sleep 2
fi
nc -z 127.0.0.1 8099 >/dev/null 2>&1 && ok "beacon on :8099 (serves share/ only)" || bad "beacon not listening on :8099"

echo "== 2. this Mac"
python3 scripts/info.py >/dev/null
MY_IP=$(plutil -extract ip raw -o - share/info.json)
SERVICE=$(plutil -extract network_service raw -o - share/info.json)
ok "ip=$MY_IP/$(plutil -extract prefix raw -o - share/info.json) gw=$(plutil -extract gateway raw -o - share/info.json) iface=$(plutil -extract interface raw -o - share/info.json) service=$SERVICE"

echo "== 3. peers"
# try the hint IPs + last known IPs first; scan the /22 only once (try 2); then keep retrying the known ones
for try in 1 2 3 4 5 6; do
  SCAN=--no-scan; [ "$try" = 2 ] && SCAN=""
  python3 scripts/discover_peers.py $SCAN "$@" >/dev/null 2>logs/discover.err && break
  info "not all peers found yet (try $try/6). Is start.sh running on the other Macs? Their chat hello has their IP: ./start.sh <ip> <ip>"
  sleep 10
done
VACHAN_IP=$(plutil -extract mac_vachan.ip raw -o - peers.json 2>/dev/null)
ABHAY_IP=$(plutil -extract mac_abhay.ip raw -o - peers.json 2>/dev/null)
[ -n "$VACHAN_IP" ] && ok "mac_vachan = $VACHAN_IP" || bad "mac_vachan not found (pass its IP: ./start.sh <ip>)"
[ -n "$ABHAY_IP" ]  && ok "mac_abhay  = $ABHAY_IP"  || bad "mac_abhay not found (pass its IP: ./start.sh <ip>)"

echo "== 4. certificates"
bash scripts/make_certs.sh >/dev/null 2>&1 && ok "tls/ca.crt + tls/server.crt valid for app/api.subspace-67.test" || bad "make_certs.sh failed"
/opt/homebrew/bin/openssl x509 -checkend $((30*86400)) -noout -in tls/server.crt >/dev/null || { bash scripts/make_certs.sh --force-server >/dev/null 2>&1; info "server cert re-issued (was expiring)"; }
cmp -s tls/ca.crt share/ca.crt || cp tls/ca.crt share/ca.crt
python3 scripts/info.py ca_published=true >/dev/null

echo "== 5. nginx"
GEN=$(python3 scripts/gen_nginx_conf.py)
info "config: $GEN"
if ! $NGINX -t >/dev/null 2>&1; then bad "nginx -t failed:"; $NGINX -t; fi
if [ -s run/nginx.pid ] && kill -0 "$(cat run/nginx.pid)" 2>/dev/null; then
  case "$GEN" in changed*) $NGINX -s reload && ok "nginx reloaded with new upstream IPs";; *) ok "nginx already running, config unchanged";; esac
else
  $NGINX && sleep 1 && ok "nginx started (as $(whoami), no sudo: macOS lets users bind 80/443 on the wildcard address)"
fi
EDGE_PORT=$(cat run/edge_port)
nc -z 127.0.0.1 "$EDGE_PORT" >/dev/null 2>&1 && ok "nginx listening on :$EDGE_PORT and :80" || bad "nginx not listening on :$EDGE_PORT"
python3 scripts/info.py edge_port="$EDGE_PORT" >/dev/null
for b in "$ABHAY_IP:3001" "$VACHAN_IP:3002"; do
  code=$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "http://$b/api/status")
  [ "$code" = 200 ] && ok "backend $b answers directly (200)" || info "backend $b not answering yet (HTTP $code)"
done

echo "== 6. system settings (the only sudo step)"
NEED_SUDO=0
CUR_DNS=$(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ' | sed 's/ $//')
[ "$CUR_DNS" = "$VACHAN_IP" ] && ok "DNS on $SERVICE = $VACHAN_IP (mac_vachan only)" || { info "DNS on $SERVICE is '$CUR_DNS', should be $VACHAN_IP"; NEED_SUDO=1; }
security verify-cert -c tls/server.crt -p ssl -s app.subspace-67.test -L -q >/dev/null 2>&1 && ok "our CA is trusted in the System keychain" || { info "our CA is not trusted yet"; NEED_SUDO=1; }
if [ "$NEED_SUDO" = 1 ]; then
  echo
  echo "  >>> Run this ONE command yourself in Terminal (it asks for your Mac password):"
  echo "      sudo bash $P/sudo/01_dns_trust_capture.sh --no-capture"
  echo "  >>> then run ./start.sh again."
  python3 scripts/info.py edge_ready=false >/dev/null
  exit 1
fi

echo "== 7. end-to-end verification (edge = this Mac, clients use only the name)"
dscacheutil -flushcache 2>/dev/null
ANS=$(dig +short app.subspace-67.test A | tail -1); SRV=$(dig app.subspace-67.test | awk '/SERVER:/{print $3}')
[ "$ANS" = "$MY_IP" ] && ok "dig app.subspace-67.test -> $ANS (server $SRV)" || bad "dig app.subspace-67.test -> '$ANS' via $SRV (want $MY_IP)"
# Plain /usr/bin/curl: on macOS 26 it also trusts the System keychain, where our CA is installed
# (checked: the CA is not in /etc/ssl/cert.pem, yet verification succeeds). Never -k.
PORTSUF=""; [ "$EDGE_PORT" = 443 ] || PORTSUF=":$EDGE_PORT"
CURL="curl -sS --max-time 5"
if ! $CURL -o /dev/null "https://app.subspace-67.test$PORTSUF/api/status" 2>/dev/null; then
  if curl -sS --max-time 5 --cacert "$P/tls/ca.crt" -o /dev/null "https://app.subspace-67.test$PORTSUF/api/status" 2>/dev/null; then
    info "plain curl does not trust the keychain here -> validating with --cacert tls/ca.crt instead (still full validation)"
    CURL="curl -sS --max-time 5 --cacert $P/tls/ca.crt"
  fi
fi
SEQ=""
for i in $(seq 1 10); do
  SEQ="$SEQ$($CURL -o /dev/null -D - "https://app.subspace-67.test$PORTSUF/api/status" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="x-backend:"{printf "%s", $2}')"
done
echo "$SEQ" | grep -q A && echo "$SEQ" | grep -q B && ok "10 requests via https://app.subspace-67.test -> X-Backend: $(echo "$SEQ" | sed 's/./& /g')" || bad "load balancing: got '$SEQ'"
H1=$($CURL --http1.1 -o /dev/null -w '%{http_version} %{http_code}' "https://app.subspace-67.test$PORTSUF/api/status" 2>&1)
H2=$($CURL --http2   -o /dev/null -w '%{http_version} %{http_code}' "https://app.subspace-67.test$PORTSUF/api/status" 2>&1)
[ "$H1" = "1.1 200" ] && ok "HTTP/1.1 over TLS: $H1" || bad "HTTP/1.1: $H1"
[ "$H2" = "2 200" ]   && ok "HTTP/2 over TLS:   $H2" || bad "HTTP/2: $H2"
R=$(curl -s --max-time 3 -o /dev/null -w '%{http_code} %{redirect_url}' "http://app.subspace-67.test/")
[ "${R%% *}" = 301 ] && ok "http:// -> $R" || bad "port 80 redirect: $R"

if [ "$FAILS" = 0 ]; then
  python3 scripts/info.py edge_ready=true edge_port="$EDGE_PORT" >/dev/null
  echo; echo "EDGE READY: https://app.subspace-67.test$PORTSUF (edge_ready=true on the bus)"
else
  python3 scripts/info.py edge_ready=false >/dev/null
  echo; echo "$FAILS check(s) failed; see above. edge_ready=false"
  exit 1
fi
