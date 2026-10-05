#!/bin/bash
# mac_aanya evidence collector. Every item = the exact command + its full output (+ exit code).
#   bash scripts/edge_evidence.sh verify    step 5: DNS answer, HTTPS with no -k, A/B alternation, h1.1 + h2
#   bash scripts/edge_evidence.sh static    step 6: openssl s_client TLS1.2/1.3, nginx -T, configs, access log, Task B
#   bash scripts/edge_evidence.sh traffic   the requests sent during the TLS-termination capture window
#   bash scripts/edge_evidence.sh export    tshark / tcpdump text exports of the capture
#   bash scripts/edge_evidence.sh manifest  (re)write MANIFEST.txt
set -u
P="$(cd "$(dirname "$0")/.." && pwd)"; cd "$P" || exit 1
EV="share/evidence/mac_aanya"
PORT=$(cat run/edge_port 2>/dev/null || echo 443)
URL="https://app.subspace-67.test"; [ "$PORT" = 443 ] || URL="$URL:$PORT"
HOSTPORT="app.subspace-67.test:$PORT"
OSSL=/opt/homebrew/bin/openssl
TSHARK=/opt/homebrew/bin/tshark
# Verified on macOS 26: /usr/bin/curl (LibreSSL) also consults the System keychain, where our CA is trusted.
CURL="${CURL:-curl}"   # macOS /usr/bin/curl trusts the System keychain (verified), so no --cacert and never -k
mkdir -p "$EV"/{step5,tls,nginx,configs,task_B,tls_termination}

rec() {  # rec <outfile> <command string>
  local f="$1" c="$2"
  { echo "\$ $c"; bash -c "$c" 2>&1; echo "(exit $?)"; echo; } >> "$f"
}
stamp() { echo "# mac_aanya, $(date '+%F %T %Z'), $1" > "$2"; echo >> "$2"; }

verify() {
  local f="$EV/step5/step5_verification.txt"; stamp "step 5 verification (this Mac as a client, name only, no -k)" "$f"
  rec "$f" "networksetup -getdnsservers Wi-Fi"
  rec "$f" "dig app.subspace-67.test"
  rec "$f" "dig +short api.subspace-67.test"
  rec "$f" "security verify-cert -c tls/server.crt -p ssl -s app.subspace-67.test -L   # system trust store (no -r): our CA is trusted"
  rec "$f" "$CURL -sS -i $URL/api/status"
  rec "$f" "$CURL -sS -v --http1.1 -o /dev/null $URL/api/status 2>&1 | grep -E '^\* (Connected|SSL connection|ALPN|Server certificate|  subject|  issuer|  SSL certificate verify|using HTTP)|^[<>] (GET|HTTP|x-backend|server)'"
  rec "$f" "$CURL -sS -v --http2 -o /dev/null $URL/api/status 2>&1 | grep -E '^\* (Connected|SSL connection|ALPN|Server certificate|  subject|  issuer|  SSL certificate verify|using HTTP)|^[<>] (GET|HTTP|x-backend|server)'"
  rec "$f" "for i in \$(seq 1 10); do $CURL -sS -o /dev/null -D - $URL/api/status | tr -d '\r' | awk -v i=\$i 'tolower(\$1)==\"x-backend:\"{print \"request \" i \": X-Backend \" \$2}'; done"
  rec "$f" "$CURL -sS -o /dev/null -w 'http_version=%{http_version} code=%{http_code} remote=%{remote_ip}:%{remote_port}\n' --http1.1 $URL/api/status"
  rec "$f" "$CURL -sS -o /dev/null -w 'http_version=%{http_version} code=%{http_code} remote=%{remote_ip}:%{remote_port}\n' --http2 $URL/api/status"
  rec "$f" "curl -sS -o /dev/null -w 'code=%{http_code} location=%{redirect_url}\n' http://app.subspace-67.test/api/status"
  rec "$f" "$CURL -sS -i $URL/api/cache-demo   # edge passes Cache-Control / ETag / Last-Modified through untouched (no proxy_cache, no gzip)"
  rec "$f" "ET=\$($CURL -sS -o /dev/null -D - $URL/api/cache-demo | tr -d '\r' | awk 'tolower(\$1)==\"etag:\"{print \$2}'); for i in 1 2; do $CURL -sS -o /dev/null -D - -H \"If-None-Match: \$ET\" $URL/api/cache-demo | tr -d '\r' | grep -iE '^HTTP|^x-backend|^etag' | tr '\n' ' '; echo; done   # 304 from BOTH backends"
  rec "$f" "$CURL -sS -I $URL/   # HEAD"
  rec "$f" "$CURL -sS -o /dev/null -D - $URL/no-such-path | tr -d '\r' | grep -iE '^HTTP|^x-backend'   # 404 still carries X-Backend"
  rec "$f" "curl -sS -I https://app.subspace-67.test/api/status   # plain /usr/bin/curl with NO --cacert (does it use the keychain?)"
  rec "$f" "CURL_SSL_BACKEND=secure-transport curl -sS -I https://app.subspace-67.test/api/status   # Apple's SecureTransport backend = System keychain trust"
  cat "$f"
}

static() {
  local f
  f="$EV/tls/s_client_tls12.txt"; stamp "openssl s_client, TLS 1.2 forced" "$f"
  rec "$f" "echo | $OSSL s_client -connect $HOSTPORT -servername app.subspace-67.test -CAfile tls/ca.crt -showcerts -tls1_2"
  f="$EV/tls/s_client_tls13.txt"; stamp "openssl s_client, TLS 1.3 forced" "$f"
  rec "$f" "echo | $OSSL s_client -connect $HOSTPORT -servername app.subspace-67.test -CAfile tls/ca.crt -showcerts -tls1_3"
  f="$EV/tls/s_client_wrong_name.txt"; stamp "negative test: SNI/hostname not in the certificate" "$f"
  rec "$f" "echo | $OSSL s_client -connect $HOSTPORT -servername wrong.subspace-67.test -verify_hostname wrong.subspace-67.test -CAfile tls/ca.crt -brief"
  f="$EV/nginx/nginx_T.txt"; stamp "full effective nginx configuration" "$f"
  rec "$f" "/opt/homebrew/bin/nginx -T"
  cp configs/nginx_subspace_67.conf "$EV/configs/nginx_subspace_67.conf"
  cp /opt/homebrew/etc/nginx/nginx.conf "$EV/configs/homebrew_nginx.conf"
  f="$EV/nginx/access_log_excerpt.txt"; stamp "edge access log: last 40 proxied requests (upstream alternates A/B)" "$f"
  rec "$f" "grep 'upstream=10' logs/nginx_access.log | tail -40"
  rec "$f" "grep 'upstream=10' logs/nginx_access.log | awk '{for(i=1;i<=NF;i++) if(\$i ~ /^upstream=/) print \$i}' | sort | uniq -c"
  f="$EV/task_B/dns_settings.txt"; stamp "Task B: this Mac uses mac_vachan as its only DNS server" "$f"
  rec "$f" "networksetup -getdnsservers Wi-Fi"
  rec "$f" "scutil --dns | sed -n '1,14p'"
  rec "$f" "cat /etc/resolv.conf | grep -v '^#'"
  rec "$f" "cat original_network/wifi_dns_servers.orig   # before the project"
  ls -la "$EV"/tls "$EV"/nginx "$EV"/task_B
}

traffic() {
  local f="$EV/tls_termination/capture_traffic_commands.txt"; stamp "requests sent from this Mac while the capture ran" "$f"
  rec "$f" "dig app.subspace-67.test +noall +answer +stats | grep -E 'IN|SERVER'"
  rec "$f" "$CURL -sS --tlsv1.2 --tls-max 1.2 --http1.1 -i $URL/api/status"
  rec "$f" "$CURL -sS --http2 -i $URL/api/status   # default = TLS 1.3 (Apple curl has no --tlsv1.3 switch)"
  rec "$f" "$CURL -sS --http2 -i $URL/api/cache-demo"
  rec "$f" "$CURL -sS --http1.1 -o /dev/null -D - $URL/"
  cat "$f"
}

export_capture() {
  local d="$EV/tls_termination" pc="$EV/tls_termination/edge_tls_termination.pcapng" f
  [ -s "$pc" ] || { echo "no capture file $pc"; return 1; }
  f="$d/tshark_all_packets.txt"; stamp "every captured packet, one line each (interface + process from Apple pktap metadata)" "$f"
  rec "$f" "$TSHARK -r $pc -T fields -E header=y -E separator=' | ' -e frame.number -e frame.time_relative -e frame.interface_name -e frame.darwin.process_info.pname -e ip.src -e tcp.srcport -e udp.srcport -e ip.dst -e tcp.dstport -e udp.dstport -e _ws.col.Protocol -e _ws.col.Info"
  f="$d/tshark_client_leg_tls.txt"; stamp "LEG 1 client->edge (lo0, port $PORT): TLS only, application data unreadable" "$f"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==$PORT && tls'"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==$PORT && tls.handshake.type' -T fields -e frame.number -e tls.record.version -e tls.handshake.type -e tls.handshake.extensions_server_name -e tls.handshake.extensions_alpn_str -e tls.handshake.ciphersuite -e x509sat.uTF8String -e x509ce.dNSName"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==$PORT && tls.handshake.type==11' -O tls -V | grep -E 'Handshake Type|Certificates Length|Certificate:|subject|issuer|rdnSequence|dNSName|validity|notBefore|notAfter' | head -40   # TLS 1.2 Certificate message, readable because 1.2 sends it in the clear"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==$PORT && tls.app_data' -T fields -e frame.number -e tls.record.version -e tls.app_data | head -8   # encrypted HTTP: random-looking bytes"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==$PORT' -T fields -e frame.number -e tcp.payload | grep -ci 'x-backend' || true   # 0 = the text 'X-Backend' never appears in the clear on this leg"
  f="$d/tshark_backend_leg_http.txt"; stamp "LEG 2 edge->backends (en0, ports 3001/3002): plain HTTP, X-Backend visible" "$f"
  rec "$f" "$TSHARK -r $pc -Y 'tcp.port==3001 || tcp.port==3002' -T fields -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e _ws.col.Info"
  rec "$f" "$TSHARK -r $pc -Y 'http && (tcp.port==3001 || tcp.port==3002)' -O http -V | grep -E '^Frame|Hypertext|GET |HTTP/1|Host:|X-Real-IP|X-Forwarded|X-Backend|Cache-Control|ETag|Content-Type'"
  f="$d/tshark_dns.txt"; stamp "DNS query/answer to mac_vachan" "$f"
  rec "$f" "$TSHARK -r $pc -Y dns -T fields -e frame.number -e ip.src -e ip.dst -e dns.qry.name -e dns.a -e dns.flags.response"
  f="$d/tcpdump_pktap_metadata.txt"; stamp "same capture read by macOS tcpdump with pktap metadata (interface, process)" "$f"
  rec "$f" "tcpdump -r $pc -k NP -nn 2>/dev/null | head -80"
}

manifest() {
  (cd "$EV" && find . -type f ! -name MANIFEST.txt ! -name '.*' | sed 's|^\./||' | sort > MANIFEST.txt)
  echo "MANIFEST: $(wc -l < "$EV/MANIFEST.txt") files"; cat "$EV/MANIFEST.txt"
}

case "${1:-}" in
  verify) verify ;; static) static ;; traffic) traffic ;; export) export_capture ;; manifest) manifest ;;
  *) echo "usage: $0 verify|static|traffic|export|manifest"; exit 1 ;;
esac
