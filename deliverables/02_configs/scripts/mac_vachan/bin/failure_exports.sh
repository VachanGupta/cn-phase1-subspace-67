#!/bin/bash
# tshark text exports (with packet numbers) for the failure-demo captures. Runs as the normal user;
# called at the end of sudo/02_failure_demos.sh, and safe to re-run by hand.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1
T=/opt/homebrew/bin/tshark
EV=share/evidence/mac_vachan/failures
KEYS=evidence_work/failures/F4_tls_session_keys.log
AANYA=$(jq -r .mac_aanya.ip peers.json); ABHAY=$(jq -r .mac_abhay.ip peers.json)
F="-T fields -E header=y -E separator=/t"
ex() {   # title, command...
  echo "### $1"; echo "\$ ${*:2}"; eval "${@:2}" 2>&1; echo
}

p=$EV/F1_wrong_dns_server/F1_queries_to_nowhere.pcapng
[ -f "$p" ] && { ex "All packets" "$T -r $p -n"
  ex "DNS queries to 192.0.2.53 (dns.flags.response 0 = query; no response ever arrives)" \
     "$T -r $p -n -Y 'dns' $F -e frame.number -e frame.time_relative -e ip.src -e udp.srcport -e ip.dst -e udp.dstport -e dns.flags.response -e dns.qry.name -e dns.qry.type"
  ex "Queries vs responses per server" "$T -r $p -n -q -z dns,tree"
} > "${p%.pcapng}_tshark.txt"

p=$EV/F2_dns_record_wrong_ip/F2_wrong_record.pcapng
[ -f "$p" ] && { ex "All packets" "$T -r $p -n"
  ex "DNS answer for app.subspace-67.test (the A record now points to mac_abhay $ABHAY)" \
     "$T -r $p -n -Y 'dns.qry.name == \"app.subspace-67.test\"' $F -e frame.number -e ip.src -e ip.dst -e dns.flags.response -e dns.flags.rcode -e dns.qry.type -e dns.a -e dns.resp.ttl"
  ex "TCP to $ABHAY:443: SYN answered by RST (nothing listens there)" \
     "$T -r $p -n -Y 'tcp.port == 443' $F -e frame.number -e frame.time_relative -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.seq_raw -e tcp.ack_raw"
} > "${p%.pcapng}_tshark.txt"

p=$EV/F4_both_backends_down/F4_502_after_tls.pcapng
[ -f "$p" ] && { ex "All packets" "$T -r $p -n"
  ex "TCP handshake, TLS handshake, then encrypted application data (per connection = tcp.stream)" \
     "$T -r $p -n -Y 'tcp.flags.syn == 1 or tls.handshake or tls.record.content_type == 23 or tcp.flags.fin == 1 or tcp.flags.reset == 1' $F -e frame.number -e tcp.stream -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tls.handshake.type -e tls.record.content_type -e tls.handshake.extensions_server_name"
  [ -f "$KEYS" ] && ex "Decrypted with the logged session keys: the edge's HTTP/2 response is 502 (sent by nginx itself)" \
     "$T -r $p -n -o tls.keylog_file:$KEYS -Y 'http2.headers.status or http2.headers.path' $F -e frame.number -e tcp.stream -e ip.src -e ip.dst -e http2.headers.method -e http2.headers.authority -e http2.headers.path -e http2.headers.status -e http2.header.value"
  [ -f "$KEYS" ] && ex "Decrypted HTTP/2 response headers in full" \
     "$T -r $p -n -o tls.keylog_file:$KEYS -Y 'http2.headers.status' -O http2 -V | grep -E 'Frame [0-9]+|Header: |:status' | head -30"
} > "${p%.pcapng}_tshark.txt"

p=$EV/F5_wrong_port/F5_syn_rst.pcapng
[ -f "$p" ] && { ex "All packets" "$T -r $p -n"
  ex "Port 8444: SYN -> RST,ACK (the host is up, no process owns that port). Port 443: SYN -> SYN,ACK -> ACK" \
     "$T -r $p -n -Y 'tcp' $F -e frame.number -e frame.time_relative -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.seq_raw -e tcp.ack_raw"
  ex "ICMP echo (ping) to the same host" \
     "$T -r $p -n -Y 'icmp' $F -e frame.number -e ip.src -e ip.dst -e icmp.type -e icmp.seq"
} > "${p%.pcapng}_tshark.txt"

ls -la $EV/*/ 2>/dev/null | grep -E 'tshark|pcapng'
