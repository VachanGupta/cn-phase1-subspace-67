#!/bin/bash
# mac_abhay client evidence, Tasks B-F.  Usage: bash tools/client_evidence.sh B|C|D|E|F|all
# Every item = exact command + full output + exit code (run_ev). Clients use only the NAME
# app.subspace-67.test; peer IPs below are only used to *label/check* results, read from peers.json.
set -u
PROJECT_DIR="/Users/abhaymalik/Desktop/CN_subspace_67"
cd "$PROJECT_DIR" || exit 1
source tools/evidence_lib.sh
V=$(peer_ip mac_vachan); A=$(peer_ip mac_aanya); ME=$(ipconfig getifaddr en0)
EDGE_PORT=$(peer_status mac_aanya edge_port); [ "$EDGE_PORT" = "None" ] || [ -z "$EDGE_PORT" ] && EDGE_PORT=443
HOST="app.subspace-67.test"
BASE="https://$HOST"; [ "$EDGE_PORT" != "443" ] && BASE="https://$HOST:$EDGE_PORT"
CA="$PROJECT_DIR/certs/ca.crt"
CURL=/usr/bin/curl
BREW_CURL=/opt/homebrew/opt/curl/bin/curl
# macOS /usr/bin/curl (Apple's LibreSSL build) falls back to the macOS keychain trust settings, so once
# our CA is trusted in the System keychain it validates the edge with NO extra flags (verified: verify=0).
# Homebrew curl (OpenSSL 3) only reads its own CA file, so it needs --cacert certs/ca.crt. Never -k.
TRUST=""

task_B() {
  local D="$EV/task_B"; mkdir -p "$D"
  run_ev "$D/01_dns_servers.txt" "networksetup -getdnsservers Wi-Fi"
  run_ev "$D/02_scutil_dns_excerpt.txt" "scutil --dns | sed -n '1,/^\$/p'; scutil --dns | sed -n '/DNS configuration (for scoped queries)/,/^\$/p' | head -12"
  run_ev "$D/03_resolv_conf.txt" "cat /etc/resolv.conf"
  run_ev "$D/04_dig_app.txt" "dig $HOST"
  run_ev "$D/05_dig_api.txt" "dig api.subspace-67.test"
  run_ev "$D/06_nslookup_app.txt" "nslookup $HOST"
  run_ev "$D/07_dig_tcp53.txt" "dig +tcp $HOST"
  run_ev "$D/08_system_resolver.txt" "dscacheutil -q host -a name $HOST"
  run_ev "$D/09_outside_name_forwarded.txt" "dig +noall +answer +stats example.com"
  {
    echo "CHECK (who answered / what):"
    echo "  dig SERVER line : $(awk '/;; SERVER:/{print $3}' "$D/04_dig_app.txt" | tail -1)  (expected $V#53 = mac_vachan)"
    echo "  dig answer      : $(awk -v h="$HOST." '$1==h && $4=="A"{print $5}' "$D/04_dig_app.txt" | tail -1)  (expected $A = mac_aanya, the edge)"
  } > "$D/00_check.txt"
  cat "$D/00_check.txt"
}

task_C() {
  local D="$EV/task_C"; mkdir -p "$D"
  local mark; mark=$(date '+%Y-%m-%dT%H:%M:%S')
  run_ev "$D/08_via_edge_requests.txt" "for p in / /api/status /api/cache-demo /api/status /no-such-path /api/status; do echo \"--- GET $BASE\$p\"; $CURL -sS $TRUST -D - -o /dev/null $BASE\$p | tr -d '\r' | grep -iE '^HTTP/|^x-backend|^cache-control|^etag'; done"
  sleep 1
  run_ev "$D/09_backend_A_log_edge_requests.txt" "awk -v m='$mark' '\$1 >= m' $PROJECT_DIR/logs/backend_A.log | grep -E 'client=' ; echo; echo 'TCP peers seen by Backend A since $mark (IP only):'; awk -v m='$mark' '\$1 >= m' $PROJECT_DIR/logs/backend_A.log | grep -oE 'client=[0-9.]+' | sort | uniq -c"
  run_ev "$D/10_established_connections_3001.txt" "netstat -an -p tcp | grep -E 'Proto|\\.3001 '"
}

task_D() {
  local D="$EV/task_D"; mkdir -p "$D"
  run_ev "$D/01_ten_requests_round_robin.txt" "for i in \$(seq 1 10); do printf 'request %2d -> ' \$i; $CURL -sS $TRUST -o /dev/null -D - $BASE/api/status | tr -d '\r' | awk 'tolower(\$1)==\"x-backend:\"{print \"X-Backend: \" \$2}'; done"
  run_ev "$D/02_ten_requests_bodies.txt" "for i in \$(seq 1 10); do $CURL -sS $TRUST $BASE/api/status; done"
  run_ev "$D/03_dns_only_knows_the_edge.txt" "dig +noall +answer $HOST api.subspace-67.test"
}

task_E() {
  local D="$EV/task_E"; mkdir -p "$D"
  run_ev "$D/01_curl_v_no_k.txt" "$CURL -v $BASE/"
  run_ev "$D/02_curl_v_explicit_cafile.txt" "$CURL -v --cacert $CA $BASE/ -o /dev/null"
  run_ev "$D/03_homebrew_openssl_curl_without_and_with_ca.txt" "echo '--- Homebrew curl (OpenSSL 3, does NOT read the macOS keychain), no CA given: must FAIL ---'; $BREW_CURL -sS -o /dev/null $BASE/api/status; echo \"exit code \$?\"; echo; echo '--- same curl with --cacert certs/ca.crt: validates ---'; $BREW_CURL -sS -o /dev/null -w 'HTTP %{http_code} over HTTP/%{http_version}, ssl_verify_result=%{ssl_verify_result}\n' --cacert $CA $BASE/api/status"
  run_ev "$D/04_openssl_s_client.txt" "openssl version; echo | openssl s_client -connect $HOST:$EDGE_PORT -servername $HOST -CAfile $CA -showcerts 2>&1"
  run_ev "$D/05_openssl_s_client_tls12.txt" "echo | openssl s_client -connect $HOST:$EDGE_PORT -servername $HOST -CAfile $CA -tls1_2 -brief 2>&1"
  run_ev "$D/06_openssl_s_client_tls13.txt" "echo | openssl s_client -connect $HOST:$EDGE_PORT -servername $HOST -CAfile $CA -tls1_3 -brief 2>&1"
  echo | openssl s_client -connect "$HOST:$EDGE_PORT" -servername "$HOST" -CAfile "$CA" 2>/dev/null | openssl x509 > "$PROJECT_DIR/certs/server_seen_by_client.pem" 2>/dev/null
  run_ev "$D/07_server_cert_details.txt" "openssl x509 -in $PROJECT_DIR/certs/server_seen_by_client.pem -noout -subject -issuer -dates -ext subjectAltName,basicConstraints,extendedKeyUsage -fingerprint -sha256"
  run_ev "$D/08_macos_keychain_trust_check.txt" "security verify-cert -c $PROJECT_DIR/certs/server_seen_by_client.pem -p ssl -s $HOST; echo; security dump-trust-settings -d 2>/dev/null | grep -A2 subspace_67"
  run_ev "$D/09_http1_vs_http2.txt" "echo '=== --http1.1 ==='; $CURL -sv --http1.1 $TRUST $BASE/api/status 2>&1 | grep -iE 'ALPN|^> GET|^< HTTP|using HTTP|x-backend'; echo; echo '=== --http2 ==='; $CURL -sv --http2 $TRUST $BASE/api/status 2>&1 | grep -iE 'ALPN|^> GET|^< HTTP|using HTTP|x-backend|\\[HTTP/2\\]'"
  run_ev "$D/10_http_redirects_to_https.txt" "$CURL -sS -I http://$HOST/"
}

task_F() {
  local D="$EV/task_F"; mkdir -p "$D"
  local U="$BASE/api/cache-demo"
  run_ev "$D/01_head_cache_headers.txt" "$CURL -sS $TRUST -I $U"
  ET=$($CURL -sS $TRUST -I "$U" | tr -d '\r' | awk 'tolower($1)=="etag:"{print $2}')
  run_ev "$D/02_conditional_get_304.txt" "$CURL -sS $TRUST -i -H 'If-None-Match: $ET' $U"
  run_ev "$D/03_normal_get_200.txt" "$CURL -sS $TRUST -i $U"
  run_ev "$D/04_304_from_both_backends.txt" "for i in 1 2 3 4; do $CURL -sS $TRUST -o /dev/null -D - -H 'If-None-Match: $ET' $U | tr -d '\r' | grep -iE '^HTTP/|^x-backend|^etag' | tr '\n' ' '; echo; done"
  run_ev "$D/05_wrong_etag_full_200.txt" "$CURL -sS $TRUST -i -H 'If-None-Match: \"0000000000000000\"' $U"
  run_ev "$D/06_if_modified_since_304.txt" "$CURL -sS $TRUST -i -H 'If-Modified-Since: Tue, 29 Sep 2026 00:00:00 GMT' $U"
  run_ev "$D/07_curl_etag_save_compare.txt" "rm -f $PROJECT_DIR/logs/etag_demo.txt; $CURL -sS $TRUST --etag-save $PROJECT_DIR/logs/etag_demo.txt -o /dev/null -w 'first request : %{http_code} (%{size_download} body bytes)\n' $U; echo \"saved ETag: \$(cat $PROJECT_DIR/logs/etag_demo.txt)\"; $CURL -sS $TRUST --etag-compare $PROJECT_DIR/logs/etag_demo.txt -o /dev/null -w 'second request: %{http_code} (%{size_download} body bytes)\n' $U"
  run_ev "$D/08_status_is_no_store.txt" "$CURL -sS $TRUST -I $BASE/api/status"
}

case "${1:-all}" in
  B) task_B ;; C) task_C ;; D) task_D ;; E) task_E ;; F) task_F ;;
  all) task_B; task_C; task_D; task_E; task_F ;;
  *) echo "usage: $0 B|C|D|E|F|all"; exit 1 ;;
esac
