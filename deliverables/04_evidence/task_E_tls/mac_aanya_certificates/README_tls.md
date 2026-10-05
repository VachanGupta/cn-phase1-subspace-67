# subspace_67 TLS: local CA + edge server certificate (mac_aanya)

Everything here is produced by `scripts/make_certs.sh` (OpenSSL 3.6, `/opt/homebrew/bin/openssl`).
Only `ca.crt` (the **public** CA certificate) is ever copied to `share/`. `ca.key` and `server.key`
are `chmod 600` and never leave this folder.

| file | what it is | secret? |
|---|---|---|
| `ca.key` | CA private key (RSA 3072). Whoever holds it can issue certs our Macs trust. | **YES** (600) |
| `ca.crt` | CA certificate, "subspace_67 Local Root CA", self-signed, 10 years. Installed as a trusted root on every Mac. | no, it's public |
| `server.key` | edge's private key (RSA 2048). nginx uses it to prove it owns the cert. | **YES** (600) |
| `server.csr` | certificate signing request (public key + requested name), input to the CA | no |
| `server.crt` | leaf cert for `app.subspace-67.test` + `api.subspace-67.test`, signed by the CA, 397 days | no |
| `fullchain.crt` | `server.crt` followed by `ca.crt`; what nginx sends in the TLS Certificate message | no |
| `ca.cnf`, `server.cnf` | OpenSSL configs holding the subject names and X.509v3 extensions below | no |

## The exact commands (what `scripts/make_certs.sh` runs)

```bash
cd tls
# 1. CA key + self-signed CA certificate
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ca.key && chmod 600 ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 -config ca.cnf -extensions v3_ca \
        -set_serial 0x$(openssl rand -hex 16) -out ca.crt

# 2. server key + CSR, then the CA signs it
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out server.key && chmod 600 server.key
openssl req -new -key server.key -config server.cnf -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -set_serial 0x$(openssl rand -hex 16) \
        -days 397 -sha256 -extfile server.cnf -extensions v3_server -out server.crt

# 3. chain file for nginx
cat server.crt ca.crt > fullchain.crt

# 4. checks
openssl verify -CAfile ca.crt -purpose sslserver -verify_hostname app.subspace-67.test server.crt   # -> OK
security verify-cert -c server.crt -r ca.crt -p ssl -s app.subspace-67.test -L -n                   # Apple's engine -> successful
```

## Why each field matters

**CA certificate (`ca.cnf`, section `v3_ca`)**
- `basicConstraints = critical, CA:TRUE, pathlen:0`: marks it as a CA. Clients refuse to accept a
  certificate as an issuer unless the issuer says CA:TRUE. `critical` means a client that does not
  understand the extension must reject the cert. `pathlen:0` means it can sign leaf certs but not sub-CAs.
- `keyUsage = critical, keyCertSign, cRLSign`: the CA key may only sign certificates and revocation lists.
- `CN = subspace_67 Local Root CA`: just a label for humans and for Keychain Access. A CA name is
  not a hostname, so the underscore is fine here.
- `nameConstraints = critical, permitted;DNS:subspace-67.test` (extra hardening): this CA can only
  vouch for `subspace-67.test` and names under it. We trust it in the *System* keychain, so if `ca.key`
  leaked, an attacker still could not impersonate any other site. Tested: a cert for `evil.example.com`
  signed by our CA is rejected by OpenSSL ("permitted subtree violation") and by macOS
  (`CSSMERR_TP_INVALID_CERTIFICATE`).
- Self-signed + 10 years: a root is trusted because we *installed* it, not because anyone signed it.

**Server certificate (`server.cnf`, section `v3_server`)**
- `subjectAltName = DNS:app.subspace-67.test, DNS:api.subspace-67.test`: **the** field clients check.
  Modern clients (macOS, Chrome, curl) ignore the CN and match the URL's hostname against the SAN list.
  That is also why the domain has a hyphen: `_` is not legal in a DNS hostname, so a SAN containing
  `subspace_67` would fail validation.
- `CN = app.subspace-67.test`: kept for humans and old tools only.
- `extendedKeyUsage = serverAuth`: the cert may only be used by a TLS server. macOS requires this EKU.
- `keyUsage = critical, digitalSignature, keyEncipherment`: with ECDHE (TLS 1.3 and our TLS 1.2 suites)
  the server key *signs* the handshake (digitalSignature). keyEncipherment covers legacy RSA key exchange.
- `basicConstraints = critical, CA:FALSE`: this leaf can never act as a CA.
- `-days 397`: macOS rejects TLS server certs valid for more than 825 days (for user-installed roots),
  and browsers cap public certs at 398 days. 397 satisfies both, so nothing can reject it for its lifetime.
- `-sha256`: SHA-1 signatures are rejected by all modern clients.
- RSA 2048: Apple requires RSA keys of at least 2048 bits for TLS.
- random 128-bit serial: every certificate from one CA must have a unique serial.

## How a client ends up trusting https://app.subspace-67.test
1. nginx sends `fullchain.crt` (leaf + CA) in the TLS Certificate message.
2. The client checks the leaf's signature with the CA's public key, checks the dates, EKU=serverAuth,
   and that the hostname it typed is in the SAN list (and inside the CA's name constraint).
3. It finds the CA in its trust store. On macOS that's the System keychain, where each Mac's sudo step
   runs `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt`.
   The chain ends at a trusted anchor, so there's no warning. No `-k`/`--insecure` anywhere.
4. The server then proves it owns `server.key` by signing the handshake (CertificateVerify in TLS 1.3,
   ServerKeyExchange signature in TLS 1.2). A copied certificate is useless without the key.

CA SHA-256 fingerprint (compare after downloading `ca.crt`):
`E7:6D:FE:6B:4E:06:F4:B6:07:9D:68:5B:1B:E0:E5:D8:62:50:EC:D2:85:80:B5:C3:95:35:78:F8:95:B0:AE:F6`
