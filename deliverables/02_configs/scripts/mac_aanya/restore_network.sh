#!/bin/bash
# =====================================================================================
# mac_aanya: undo EVERY system change made for subspace_67. Run it once, after the project:
#
#     sudo bash ~/Desktop/CN_subspace_67/restore_network.sh
#
#   1. stops nginx, the :8099 beacon and caffeinate (stop.sh, as the normal user)
#   2. puts the Wi-Fi DNS servers back to what they were before the project
#      (saved in original_network/wifi_dns_servers.orig; it was "1.0.01", a malformed manual
#       entry that macOS ignores, so the Mac really used the DHCP servers 8.8.8.8 / 10.5.7.1.
#       If networksetup refuses the old value we fall back to "Empty" = DHCP, which behaves the same)
#   3. removes the "subspace_67 Local Root CA" trust setting and certificate from the System keychain
#   4. puts Homebrew's original nginx.conf back
#   5. removes the macOS firewall "allow incoming" entry that was added for nginx
# Homebrew packages (nginx, wireshark) are left installed; remove them with
#     brew uninstall nginx wireshark     if you no longer want them.
# =====================================================================================
set -u
if [ "$(id -u)" != 0 ]; then echo "Please run with sudo:  sudo bash $0"; exit 1; fi
P="$(cd "$(dirname "$0")" && pwd)"
OWNER=$(stat -f %Su "$P")
SERVICE=$(plutil -extract network_service raw -o - "$P/share/info.json" 2>/dev/null); SERVICE=${SERVICE:-Wi-Fi}
echo "== 1. stopping services"
sudo -u "$OWNER" bash "$P/stop.sh"

echo "== 2. DNS on $SERVICE"
ORIG=$(cat "$P/original_network/wifi_dns_servers.orig" 2>/dev/null)
if [ -z "$ORIG" ] || echo "$ORIG" | grep -q "aren't any DNS Servers"; then
  networksetup -setdnsservers "$SERVICE" Empty
else
  # shellcheck disable=SC2086  (several servers are space separated on purpose)
  networksetup -setdnsservers "$SERVICE" $ORIG
  NOW=$(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ' | sed 's/ $//')
  [ "$NOW" = "$(echo $ORIG)" ] || { echo "   original value refused, using Empty (DHCP)"; networksetup -setdnsservers "$SERVICE" Empty; }
fi
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
echo "   DNS now: $(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ')"

echo "== 3. removing our CA from the System keychain"
security remove-trusted-cert -d "$P/tls/ca.crt" 2>/dev/null && echo "   trust setting removed"
while security find-certificate -c "subspace_67 Local Root CA" /Library/Keychains/System.keychain >/dev/null 2>&1; do
  security delete-certificate -c "subspace_67 Local Root CA" /Library/Keychains/System.keychain >/dev/null || break
  echo "   certificate deleted"
done
security find-certificate -c "subspace_67 Local Root CA" /Library/Keychains/System.keychain >/dev/null 2>&1 \
  && echo "   WARNING: CA still present, remove it in Keychain Access > System" || echo "   CA no longer in the System keychain"

echo "== 4. Homebrew nginx.conf"
if [ -f /opt/homebrew/etc/nginx/nginx.conf.orig_subspace67 ]; then
  cp /opt/homebrew/etc/nginx/nginx.conf.orig_subspace67 /opt/homebrew/etc/nginx/nginx.conf
  chown "$OWNER" /opt/homebrew/etc/nginx/nginx.conf
  echo "   original nginx.conf restored"
fi

echo "== 5. firewall entry for nginx"
for bin in /opt/homebrew/Cellar/nginx/*/bin/nginx; do
  [ -e "$bin" ] && /usr/libexec/ApplicationFirewall/socketfilterfw --remove "$bin" 2>/dev/null | sed 's/^/   /'
done
echo "done: this Mac's network settings are back to how they were before subspace_67."
