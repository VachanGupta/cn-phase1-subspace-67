#!/bin/bash
# Shared helpers for mac_abhay evidence collection.
# Every evidence item = the exact command + its full output + exit code, as plain text.

# Resolve the project folder from this file's location when sourced by bash; under zsh
# BASH_SOURCE is empty, so fall back to the current directory (callers cd to PROJECT_DIR first).
if [ -z "$PROJECT_DIR" ]; then
  if [ -n "${BASH_SOURCE[0]}" ]; then
    PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  else
    PROJECT_DIR="$PWD"
  fi
fi
[ -f "$PROJECT_DIR/mac_abhay.md" ] || { echo "evidence_lib: PROJECT_DIR=$PROJECT_DIR is not the project folder" >&2; return 1 2>/dev/null || exit 1; }
EV="$PROJECT_DIR/share/evidence/mac_abhay"
PEERS="$PROJECT_DIR/peers.json"

# run_ev <outfile> <command string>  -> appends "$ command", output and exit code to outfile
run_ev() {
  local out="$1"; shift
  local cmd="$*"
  mkdir -p "$(dirname "$out")"
  {
    echo "### $(date '+%Y-%m-%d %H:%M:%S %Z') on mac_abhay ($(ipconfig getifaddr en0 2>/dev/null))"
    echo "\$ $cmd"
    bash -c "$cmd" 2>&1
    echo "[exit code: $?]"
    echo
  } >> "$out"
}

# peer_ip <name> -> IP of a peer, always read from peers.json (which is built from each peer's own info.json)
peer_ip() {
  python3 -c "import json,sys; print(json.load(open('$PEERS'))['$1']['ip'])" 2>/dev/null
}

# peer_status <name> <flag> -> prints the flag's current value from the peer's live info.json (or 'unreachable')
peer_status() {
  local ip; ip="$(peer_ip "$1")"
  [ -z "$ip" ] && { echo unreachable; return; }
  curl -s --max-time 2 "http://$ip:8099/info.json" |
    python3 -c "import json,sys; print(json.load(sys.stdin).get('status',{}).get('$2'))" 2>/dev/null || echo unreachable
}
