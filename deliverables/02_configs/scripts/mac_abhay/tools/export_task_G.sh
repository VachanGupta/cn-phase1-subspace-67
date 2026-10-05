#!/bin/bash
# Text exports of the Task G captures (run as the normal user after sudo/02_capture_task_G.sh).
# Each export file = exact tshark command + full output (run_ev), with packet numbers.
set -u
PROJECT_DIR="/Users/abhaymalik/Desktop/CN_subspace_67"
cd "$PROJECT_DIR" || exit 1
source tools/evidence_lib.sh
G="$EV/task_G"
TS=$(command -v tshark || echo /Applications/Wireshark.app/Contents/MacOS/tshark)
CI=$(dirname "$TS")/capinfos
A=$(peer_ip mac_aanya); V=$(peer_ip mac_vachan); ME=$(ipconfig getifaddr en0)
HOST="app.subspace-67.test"

ev() { : > "$1"; run_ev "$@"; }
for cap in task_G_tls12 task_G_tls13; do
  f="$G/$cap.pcapng"; [ -f "$f" ] || { echo "missing $f"; continue; }
  X="$G/${cap}_exports"; mkdir -p "$X"
  KL=""; [ -s "$G/${cap}_sslkeylog.txt" ] && KL="$G/${cap}_sslkeylog.txt"
  # the client's TCP connection to the edge (first SYN from me to mac_aanya:443)
  S=$("$TS" -r "$f" -Y "ip.src==$ME && ip.dst==$A && tcp.dstport==443 && tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.stream 2>/dev/null | head -1)
  S=${S:-0}

  ev "$X/00_capinfos.txt" "'$CI' '$f'"
  ev "$X/01_all_packets.txt" "'$TS' -r '$f' -n"

  ev "$X/02_dns_query_response.txt" "'$TS' -r '$f' -n -Y 'dns.qry.name == \"$HOST\"' -T fields -E header=y -E separator='|' -e frame.number -e frame.time_relative -e ip.src -e udp.srcport -e ip.dst -e udp.dstport -e dns.id -e dns.flags.response -e dns.qry.name -e dns.qry.type -e dns.flags.rcode -e dns.a -e dns.resp.ttl | python3 $PROJECT_DIR/tools/fmt_table.py"
  ev "$X/03_dns_detail_dig.txt" "'$TS' -r '$f' -n -Y 'dns.qry.name == \"$HOST\" && dns.qry.type == 1' -O dns -V -c 400 | sed -n '1,400p'"

  ev "$X/04_tcp_handshake.txt" "echo 'Relative seq/ack (Wireshark default):'; '$TS' -r '$f' -n -Y 'tcp.stream == $S' -T fields -E header=y -E separator='|' -e frame.number -e frame.time_relative -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.seq -e tcp.ack -e tcp.len -e tcp.window_size_value -e tcp.options.mss_val -e tcp.options.wscale.shift | head -4 | python3 $PROJECT_DIR/tools/fmt_table.py; echo; echo 'Raw (absolute, as on the wire) seq/ack of the same packets:'; '$TS' -r '$f' -n -Y 'tcp.stream == $S' -T fields -E header=y -E separator='|' -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.seq_raw -e tcp.ack_raw | head -4 | python3 $PROJECT_DIR/tools/fmt_table.py"
  ev "$X/05_tcp_handshake_detail.txt" "'$TS' -r '$f' -n -Y 'tcp.stream == $S && tcp.flags.syn == 1' -O tcp -V"

  TLSK=""; [ -n "$KL" ] && TLSK="-o tls.keylog_file:$KL"
  ev "$X/06_tls_records_encrypted_view.txt" "'$TS' -r '$f' -n -Y 'tcp.stream == $S && tls' -T fields -E header=y -E separator='|' -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tls.record.version -e tls.record.content_type -e tls.handshake.type -e _ws.col.info | python3 $PROJECT_DIR/tools/fmt_table.py"
  ev "$X/07_tls_clienthello_sni.txt" "'$TS' -r '$f' -n -Y 'tcp.stream == $S && tls.handshake.type == 1' -O tls -V"
  ev "$X/08_tls_serverhello_certificate_keyexchange.txt" "'$TS' -r '$f' -n -Y 'tcp.stream == $S && (tls.handshake.type == 2 || tls.handshake.type == 11 || tls.handshake.type == 12 || tls.handshake.type == 14 || tls.handshake.type == 16 || tls.record.content_type == 20)' -O tls -V"

  ev "$X/09_port_table.txt" "echo 'Conversations (who talked to whom, on which ports):'; '$TS' -r '$f' -n -q -z conv,udp -z conv,tcp; echo; echo 'First packet of each flow: client ephemeral port -> server port'; '$TS' -r '$f' -n -Y '(udp && dns.flags.response == 0) || (tcp.flags.syn == 1 && tcp.flags.ack == 0)' -T fields -E header=y -E separator='|' -e frame.number -e _ws.col.protocol -e ip.src -e udp.srcport -e tcp.srcport -e ip.dst -e udp.dstport -e tcp.dstport -e dns.qry.name | python3 $PROJECT_DIR/tools/fmt_table.py"
  ev "$X/10_tcp_stream_seq_ack_all.txt" "'$TS' -r '$f' -n -Y 'tcp.stream == $S' -T fields -E header=y -E separator='|' -e frame.number -e frame.time_relative -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.seq -e tcp.nxtseq -e tcp.ack -e tcp.len -e tcp.analysis.acks_frame -e tcp.analysis.flags -e _ws.col.info | python3 $PROJECT_DIR/tools/fmt_table.py"
  ev "$X/11_edge_to_backendA_hop.txt" "'$TS' -r '$f' -n -Y 'tcp.port == 3001' -T fields -E header=y -E separator='|' -e frame.number -e frame.time_relative -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport -e tcp.flags.str -e tcp.len -e _ws.col.info | python3 $PROJECT_DIR/tools/fmt_table.py"
  if [ -n "$KL" ]; then
    ev "$X/12_decrypted_tls_records.txt" "'$TS' -r '$f' -n $TLSK -Y 'tcp.stream == $S && tls' -T fields -E header=y -E separator='|' -e frame.number -e ip.src -e ip.dst -e tls.record.opaque_type -e tls.record.content_type -e tls.handshake.type -e _ws.col.info | python3 $PROJECT_DIR/tools/fmt_table.py"
    ev "$X/13_decrypted_http.txt" "'$TS' -r '$f' -n $TLSK -Y 'tcp.stream == $S && (http || http2)' -O http,http2 -V"
  fi
done

# Bonus: which process sent each packet (Apple pktap metadata, read with Apple's tcpdump)
for cap in task_G_tls12 task_G_tls13; do
  p="$G/${cap}_pktap_process.pcapng"; [ -f "$p" ] || continue
  ev "$G/${cap}_exports/14_process_per_packet_pktap.txt" "tcpdump -r '$p' -n -k NP 2>/dev/null | head -80"
done
echo "exports written under $G/*_exports/"
