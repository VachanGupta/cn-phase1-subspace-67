#!/bin/bash
# Build the subspace_67 local CA and the edge's server certificate in PROJECT_DIR/tls/.
# Idempotent: an existing CA is kept (peers already trust it); pass --force-server to re-issue
# the server cert, or --force-all to start over (then every Mac must re-trust the new ca.crt).
# Private keys (ca.key, server.key) are chmod 600 and NEVER copied to share/.
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
T="$P/tls"
OSSL=/opt/homebrew/bin/openssl
[ -x "$OSSL" ] || OSSL=openssl
cd "$T"
umask 077

if [ "${1:-}" = "--force-all" ]; then rm -f ca.key ca.crt server.key server.csr server.crt fullchain.crt; fi
if [ "${1:-}" = "--force-server" ]; then rm -f server.key server.csr server.crt fullchain.crt; fi

if [ ! -s ca.key ] || [ ! -s ca.crt ]; then
  echo "== creating CA (RSA 3072, 10 years)"
  "$OSSL" genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ca.key
  chmod 600 ca.key
  "$OSSL" req -x509 -new -key ca.key -sha256 -days 3650 -config ca.cnf -extensions v3_ca \
    -set_serial "0x$("$OSSL" rand -hex 16)" -out ca.crt
fi

if [ ! -s server.key ] || [ ! -s server.crt ]; then
  echo "== creating server key + CSR + certificate (RSA 2048, 397 days)"
  "$OSSL" genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out server.key
  chmod 600 server.key
  "$OSSL" req -new -key server.key -config server.cnf -out server.csr
  "$OSSL" x509 -req -in server.csr -CA ca.crt -CAkey ca.key -set_serial "0x$("$OSSL" rand -hex 16)" \
    -days 397 -sha256 -extfile server.cnf -extensions v3_server -out server.crt
fi

# nginx serves the leaf + the CA so clients see the whole chain (-showcerts prints both).
cat server.crt ca.crt > fullchain.crt
chmod 644 ca.crt server.crt fullchain.crt
chmod 600 ca.key server.key

echo "== verify chain with OpenSSL"
"$OSSL" verify -CAfile ca.crt -purpose sslserver -verify_hostname app.subspace-67.test server.crt
"$OSSL" verify -CAfile ca.crt -purpose sslserver -verify_hostname api.subspace-67.test server.crt
