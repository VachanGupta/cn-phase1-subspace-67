#!/bin/bash
# Phase 1 gate check from this Mac (step 8): the name resolves to the edge via mac_vachan's DNS server,
# HTTPS works with a verified certificate (no -k, no --cacert), and repeated requests reach BOTH backends.
# Writes share/evidence/mac_vachan/final_gate/final_gate_mac_vachan.txt and prints PASS/FAIL.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR" || exit 1
ME=$(jq -r .ip share/info.json); AANYA=$(jq -r .mac_aanya.ip peers.json)
OUT=share/evidence/mac_vachan/final_gate/final_gate_mac_vachan.txt
mkdir -p "$(dirname "$OUT")"
pass=1
{
echo "# Phase 1 gate check on mac_vachan ($ME) - $(date '+%F %T %Z')"; echo
echo '$ networksetup -getdnsservers Wi-Fi'; networksetup -getdnsservers Wi-Fi; echo
echo '$ dig app.subspace-67.test +noall +answer +stats'; dig app.subspace-67.test +noall +answer +stats | grep -vE '^;; (WHEN|MSG)'; echo
ans=$(dig app.subspace-67.test +short | grep -E '^[0-9.]+$' | head -1); srv=$(dig app.subspace-67.test | awk '/SERVER:/{print $3}')
echo "answer=$ans (edge mac_aanya=$AANYA) server=$srv"
[ "$ans" = "$AANYA" ] && echo "$srv" | grep -q "^$ME#53" && echo "DNS: PASS" || { echo "DNS: FAIL"; pass=0; }; echo
echo '$ curl -sS -v https://app.subspace-67.test/api/status   (no -k, no --cacert)'
curl -sS -v https://app.subspace-67.test/api/status 2>&1 | grep -E 'Connected to|SSL connection|subject:|issuer:|SSL certificate verify|ALPN: server|^< HTTP|^< x-backend|^\{"'
v=$(curl -s -o /dev/null -w '%{http_code} %{ssl_verify_result}' https://app.subspace-67.test/api/status)
[ "$v" = "200 0" ] && echo "HTTPS (verified certificate): PASS" || { echo "HTTPS: FAIL ($v)"; pass=0; }; echo
echo '$ for i in $(seq 1 10); do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | grep -i x-backend; done'
seq=$(for i in $(seq 1 10); do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r'; done | tr '\n' ' ')
echo "X-Backend sequence: $seq"
echo "$seq" | grep -q A && echo "$seq" | grep -q B && echo "Both backends: PASS" || { echo "Both backends: FAIL"; pass=0; }
echo; [ $pass = 1 ] && echo "GATE: PASS" || echo "GATE: FAIL"
} > "$OUT" 2>&1
tail -1 "$OUT"; grep -E 'PASS|FAIL|sequence' "$OUT" | head -6
[ $pass = 1 ]
