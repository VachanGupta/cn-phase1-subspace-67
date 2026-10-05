#!/bin/bash
# subspace_67 / mac_vachan - undo every system change made for the project (run after the project):
#     sudo bash /Users/vachanP/Desktop/work/CN/restore_network.sh
#   1. stops our services (Backend B supervisor, team-bus beacon, caffeinate we started)
#   2. stops the root dnsmasq service and gives the Homebrew paths back to the owner
#   3. restores the original DNS servers / search domains saved in state/original_network.txt
#   4. removes the subspace_67 Local Root CA from the System keychain
#   5. flushes the DNS cache
# Project files are left in place.
set -u
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BREW=/opt/homebrew/bin/brew
OWNER="${SUDO_USER:-$(stat -f %Su "$PROJECT_DIR")}"
[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo:  sudo bash $0"; exit 1; }
# shellcheck disable=SC1091
. "$PROJECT_DIR/state/original_network.txt"      # SERVICE, DNS_SERVERS, SEARCH_DOMAINS
echo "=== restoring network settings of $SERVICE"

echo "--- 1. project processes"
sudo -u "$OWNER" bash "$PROJECT_DIR/stop.sh" --all 2>/dev/null

echo "--- 2. dnsmasq service"
"$BREW" services stop dnsmasq 2>&1 | tail -1
rm -f /Library/LaunchDaemons/homebrew.mxcl.dnsmasq.plist
# `sudo brew services` took root ownership of a few Homebrew paths; give them back
for p in /opt/homebrew/Cellar/dnsmasq /opt/homebrew/opt/dnsmasq /opt/homebrew/var/homebrew/linked/dnsmasq \
         /opt/homebrew/etc/dnsmasq.conf /opt/homebrew/etc/dnsmasq.d /opt/homebrew/var/log/dnsmasq_subspace_67.log; do
  [ -e "$p" ] && chown -R "$OWNER":admin "$p"
done
# put Homebrew's stock config back (saved before the project)
[ -f "$PROJECT_DIR/state/dnsmasq.conf.homebrew-default" ] && \
  cp "$PROJECT_DIR/state/dnsmasq.conf.homebrew-default" /opt/homebrew/etc/dnsmasq.conf && \
  chown "$OWNER":admin /opt/homebrew/etc/dnsmasq.conf

echo "--- 3. DNS servers"
if [ -z "${DNS_SERVERS// /}" ] || echo "$DNS_SERVERS" | grep -q "There aren't any"; then
  networksetup -setdnsservers "$SERVICE" empty
else
  # shellcheck disable=SC2086
  networksetup -setdnsservers "$SERVICE" $DNS_SERVERS
fi
if [ -z "${SEARCH_DOMAINS// /}" ] || echo "$SEARCH_DOMAINS" | grep -q "There aren't any"; then
  networksetup -setsearchdomains "$SERVICE" empty
else
  # shellcheck disable=SC2086
  networksetup -setsearchdomains "$SERVICE" $SEARCH_DOMAINS
fi
echo "DNS now: $(networksetup -getdnsservers "$SERVICE" | tr '\n' ' ')"

echo "--- 4. team CA"
while security find-certificate -c "subspace_67 Local Root CA" /Library/Keychains/System.keychain >/dev/null 2>&1; do
  security delete-certificate -c "subspace_67 Local Root CA" -t /Library/Keychains/System.keychain || break
done
security find-certificate -c "subspace_67 Local Root CA" /Library/Keychains/System.keychain >/dev/null 2>&1 \
  && echo "CA still present (remove it in Keychain Access > System)" || echo "CA removed"

echo "--- 5. flush DNS cache"
dscacheutil -flushcache; killall -HUP mDNSResponder
echo "=== restored. (Homebrew packages dnsmasq etc. are still installed: brew uninstall dnsmasq if unwanted)"
