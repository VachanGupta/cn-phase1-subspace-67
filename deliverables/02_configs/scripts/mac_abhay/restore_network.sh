#!/bin/bash
# mac_abhay: undo every system change made for the subspace_67 project (run after the project).
#   1. stop project processes (stop.sh)
#   2. Wi-Fi DNS back to the original setting saved in original_network_settings.txt
#      (it was "no manual DNS servers" = use the DHCP-provided ones -> networksetup ... Empty)
#   3. flush the DNS cache
#   4. remove the subspace_67 Local Root CA (trust settings + certificate) from the System keychain
# Asks for your Mac password once (sudo). Wireshark was installed before the project, so it stays.
set -u
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE="Wi-Fi"
CA="$PROJECT_DIR/certs/ca.crt"
CA_NAME="subspace_67 Local Root CA"

if [ "$(id -u)" -ne 0 ]; then
  bash "$PROJECT_DIR/stop.sh"
  echo "Now undoing system settings (sudo):"
  exec sudo bash "$0" "$@"
fi

ORIG=$(grep '^dns_servers=' "$PROJECT_DIR/original_network_settings.txt" | cut -d= -f2-)
if [ -z "$ORIG" ] || echo "$ORIG" | grep -q "aren't any"; then
  networksetup -setdnsservers "$SERVICE" Empty
else
  # shellcheck disable=SC2086
  networksetup -setdnsservers "$SERVICE" $ORIG
fi
echo "DNS for $SERVICE now: $(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ')"
dscacheutil -flushcache; killall -HUP mDNSResponder
echo "DNS cache flushed"

if [ -f "$CA" ]; then
  security remove-trusted-cert -d "$CA" 2>/dev/null && echo "CA trust settings removed"
  SHA1=$(/usr/bin/openssl x509 -in "$CA" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
  while security find-certificate -a -Z -c "$CA_NAME" /Library/Keychains/System.keychain 2>/dev/null | grep -qi "$SHA1"; do
    security delete-certificate -Z "$SHA1" /Library/Keychains/System.keychain && echo "CA certificate deleted from System keychain"
  done
fi
echo "Restore complete. (Project files remain in $PROJECT_DIR)"
