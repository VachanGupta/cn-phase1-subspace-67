#!/bin/bash
# Send N requests to https://app.subspace-67.test<PATH> (certificate verified, never -k) and print one
# line per request: HTTP status, X-Backend, and the edge IP:port curl connected to.
#   bin/lb_probe.sh [N=10] [PATH=/api/status]
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$PROJECT_DIR/bin/tls_env.sh" 2>/dev/null
N=${1:-10}; P=${2:-/api/status}
for i in $(seq 1 "$N"); do
  out=$(curl -s -D - -o /dev/null --max-time 5 \
        -w 'HTTP=%{http_code} edge=%{remote_ip}:%{remote_port} verify=%{ssl_verify_result}\n' \
        "https://app.subspace-67.test$P" 2>&1)
  be=$(printf '%s\n' "$out" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')
  printf 'request %2d: %s X-Backend: %s\n' "$i" "$(printf '%s\n' "$out" | grep '^HTTP=')" "${be:--}"
done
