#!/bin/bash
# =====================================================================================
# mac_aanya: the ONE root batch (step 5 + the packet capture of step 6).
# Run it yourself in Terminal (it asks for your Mac password once; macOS may also pop up
# a dialog to approve the certificate-trust change: approve it):
#
#     sudo bash ~/Desktop/CN_subspace_67/sudo/01_dns_trust_capture.sh
#
# What it does, and nothing else:
#   0. SAFETY CHECK (no changes yet): mac_vachan's DNS server must answer both
#      app.subspace-67.test (-> this Mac) AND a public name. Otherwise it stops, so switching
#      DNS can never cut this Mac off the internet.
#   1. sets the Wi-Fi DNS server to mac_vachan's IP only (original saved in original_network/)
#   2. flushes the macOS DNS cache
#   3. trusts tls/ca.crt ("subspace_67 Local Root CA", name-constrained to subspace-67.test)
#      in the System keychain
#   4. packet capture for the TLS-termination evidence: waits until the operator creates
#      run/capture.start, runs tcpdump on lo0+en0 (pktap) with a narrow filter (only
#      this Mac's own HTTPS-to-itself, edge->backend HTTP and DNS to mac_vachan), and stops
#      at run/capture.stop (or after 5 min). Skip it with --no-capture.
# Undo everything after the project with:  sudo bash ~/Desktop/CN_subspace_67/restore_network.sh
# =====================================================================================
set -u
if [ "$(id -u)" != 0 ]; then echo "Please run with sudo:  sudo bash $0"; exit 1; fi
P="$(cd "$(dirname "$0")/.." && pwd)"
OWNER=$(stat -f %Su "$P")
LOG="$P/logs/root_changes.log"
CAPTURE=1; [ "${1:-}" = "--no-capture" ] && CAPTURE=0
say() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

VACHAN_IP=$(plutil -extract mac_vachan.ip raw -o - "$P/peers.json" 2>/dev/null)
ABHAY_IP=$(plutil -extract mac_abhay.ip raw -o - "$P/peers.json" 2>/dev/null)
MY_IP=$(plutil -extract ip raw -o - "$P/share/info.json" 2>/dev/null)
SERVICE=$(plutil -extract network_service raw -o - "$P/share/info.json" 2>/dev/null); SERVICE=${SERVICE:-Wi-Fi}
IFACE=$(plutil -extract interface raw -o - "$P/share/info.json" 2>/dev/null); IFACE=${IFACE:-en0}
EDGE_PORT=$(cat "$P/run/edge_port" 2>/dev/null || echo 443)
say "=== mac_aanya root batch start: service=$SERVICE iface=$IFACE me=$MY_IP vachan(DNS)=$VACHAN_IP abhay=$ABHAY_IP edge_port=$EDGE_PORT"
[ -n "$VACHAN_IP" ] && [ -n "$MY_IP" ] || { say "ERROR: peers.json/info.json incomplete - ask the operator to rerun discovery"; exit 1; }

# ---- 0. safety check (read-only) --------------------------------------------------
A=$(dig +short +time=2 +tries=2 @"$VACHAN_IP" app.subspace-67.test A | tail -1)
PUB=$(dig +short +time=2 +tries=2 @"$VACHAN_IP" api.anthropic.com A | tail -1)
say "check: @$VACHAN_IP app.subspace-67.test -> '${A}' (want $MY_IP); api.anthropic.com -> '${PUB}'"
if [ "$A" != "$MY_IP" ] || [ -z "$PUB" ]; then
  say "STOP: mac_vachan's DNS is not ready (or does not forward public names). NOTHING was changed."
  say "      Tell the operator; they will coordinate with mac_vachan, then you can run this again."
  exit 2
fi

# ---- 1+2. DNS -> mac_vachan only, flush caches ------------------------------------
[ -s "$P/original_network/wifi_dns_servers.orig" ] || networksetup -getdnsservers "$SERVICE" > "$P/original_network/wifi_dns_servers.orig"
say "original DNS on $SERVICE: $(tr '\n' ' ' < "$P/original_network/wifi_dns_servers.orig")"
networksetup -setdnsservers "$SERVICE" "$VACHAN_IP" && say "set DNS on $SERVICE -> $VACHAN_IP"
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null; say "flushed DNS cache (dscacheutil + mDNSResponder HUP)"
sleep 2
say "now: $(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ')"
scutil --dns | sed -n '1,12p' | tee -a "$LOG"

# ---- 3. trust our CA in the System keychain ----------------------------------------
security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$P/tls/ca.crt" \
  && say "trusted tls/ca.crt (subspace_67 Local Root CA) in the System keychain" \
  || say "WARNING: add-trusted-cert failed (was the dialog cancelled?) - tell the operator"
security verify-cert -c "$P/tls/server.crt" -p ssl -s app.subspace-67.test -L -q \
  && say "check: macOS now trusts the edge certificate for app.subspace-67.test (system trust, no -r)" \
  || say "WARNING: macOS does not trust the edge certificate yet - tell the operator"
chown "$OWNER" "$LOG"

# ---- 4. capture window for the TLS-termination evidence ----------------------------
[ "$CAPTURE" = 1 ] || { say "=== done (no capture). You can close this window."; exit 0; }
CAP="$P/share/evidence/mac_aanya/tls_termination"; mkdir -p "$CAP"; chown "$OWNER" "$CAP"
rm -f "$P/run/capture.start" "$P/run/capture.stop" "$P/run/capture.running"
FILTER="(src host $MY_IP and dst host $MY_IP and tcp port $EDGE_PORT)"
[ -n "$ABHAY_IP" ] && FILTER="$FILTER or (host $ABHAY_IP and tcp port 3001)"
FILTER="$FILTER or (host $VACHAN_IP and tcp port 3002) or (host $VACHAN_IP and port 53)"
say "capture: waiting (max 20 min) for the operator to create run/capture.start ... (leave this window open)"
for i in $(seq 1 1200); do [ -e "$P/run/capture.start" ] && break; sleep 1; done
[ -e "$P/run/capture.start" ] || { say "no capture.start after 20 min - skipping capture. Everything else is done."; exit 0; }
say "capture: tcpdump -i pktap,lo0,$IFACE filter: $FILTER"
tcpdump -i "pktap,lo0,$IFACE" -w "$CAP/edge_tls_termination.pcapng" "$FILTER" 2>>"$LOG" &
TPID=$!
sleep 1; echo "$TPID" > "$P/run/capture.running"; chown "$OWNER" "$P/run/capture.running"
for i in $(seq 1 300); do [ -e "$P/run/capture.stop" ] && break; sleep 1; done
sleep 1; kill -INT "$TPID" 2>/dev/null; wait "$TPID" 2>/dev/null
chown -R "$OWNER" "$CAP"; rm -f "$P/run/capture.running"
say "capture: saved $CAP/edge_tls_termination.pcapng ($(stat -f %z "$CAP/edge_tls_termination.pcapng" 2>/dev/null) bytes)"
say "=== all done. You can close this window."
