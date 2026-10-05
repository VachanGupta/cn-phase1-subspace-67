# Task E: TLS with our own CA, validated properly (never -k), and HTTP/1.1 vs HTTP/2

**Trust setup**: mac_aanya's public CA certificate (`certs/ca.crt`) was downloaded from her team bus. Its SHA-256
fingerprint was compared with the one she announced over chat (a second channel) before trusting it (00_ca_certificate_check.txt:
identical, no private key in the file, `CA:TRUE, pathlen:0`, critical Name Constraint `DNS:subspace-67.test`, so it can
only vouch for our domain). It was then added to the **System keychain** as a trusted root by the root batch
`sudo/01_dns_and_ca.sh` (`security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain`).

**What it shows**
| File | Proof |
|---|---|
| 01_curl_v_no_k.txt | `/usr/bin/curl -v https://app.subspace-67.test/` with **no -k and no --cacert**: connects to 10.7.19.193:443 (the name was resolved via our DNS), `SSL connection using TLSv1.3`, `subjectAltName: host "app.subspace-67.test" matched`, `issuer: ... subspace_67 Local Root CA`, **`SSL certificate verify ok.`**, ALPN h2, HTTP/2 200 |
| 02_curl_v_explicit_cafile.txt | the same with `--cacert certs/ca.crt` (explicit CA file): also verify ok |
| 03_homebrew_openssl_curl_without_and_with_ca.txt | Homebrew curl (OpenSSL 3) with no CA: **fails**, exit 60 `self-signed certificate in certificate chain`. With `--cacert certs/ca.crt`: 200, ssl_verify_result=0. This proves validation is real, and shows which client uses which trust store |
| 04_openssl_s_client.txt | `openssl s_client -connect app.subspace-67.test:443 -servername app.subspace-67.test -CAfile ca.crt`: chain depth 1 (our CA) -> depth 0 (app.subspace-67.test), TLSv1.3, `TLS_AES_256_GCM_SHA384`, **`Verify return code: 0 (ok)`** |
| 05/06_openssl_s_client_tls12/13.txt | forced TLS 1.2 -> `ECDHE-RSA-AES256-GCM-SHA384` with X25519 ephemeral key; forced TLS 1.3 -> `TLS_AES_256_GCM_SHA384`, key-exchange group **X25519MLKEM768** (hybrid post-quantum); both `Verification: OK` |
| 07_server_cert_details.txt | server certificate: subject `CN=app.subspace-67.test`, SAN, issuer = our CA, validity dates |
| 08_macos_keychain_trust_check.txt | `security verify-cert -p ssl -s app.subspace-67.test`: macOS's own trust engine (what Safari/Chrome use) accepts the server certificate for that hostname; our CA appears in the admin trust settings |
| 09_http1_vs_http2.txt | `--http1.1`: ALPN offers only http/1.1 -> `GET /api/status HTTP/1.1`, `HTTP/1.1 200 OK`. `--http2`: ALPN offers h2 -> `server accepted h2`, request sent as HTTP/2 pseudo-headers (`:method`, `:scheme`, `:authority`, `:path`) on stream 1 |
| 10_http_redirects_to_https.txt | plain `http://app.subspace-67.test/` -> `301 Moved Permanently`, `Location: https://...` (port 80 only redirects) |

**Why /usr/bin/curl needs no flag but Homebrew curl does (written down as the rules ask)**
- Apple's `/usr/bin/curl` (8.7.1) uses **LibreSSL** by default; `curl -V` lists SecureTransport only as the non-default
  backend (in parentheses). Its verbose output names `CAfile: /etc/ssl/cert.pem`, a static bundle that does **not**
  contain our CA, yet verification succeeds. Apple's build falls back to the **macOS keychain trust settings**, so
  trusting our CA in the System keychain is enough (mac_aanya and mac_vachan observed the same).
- Homebrew curl (OpenSSL 3) only reads its own CA file, never the keychain, so it needs `--cacert certs/ca.crt`
  (full validation against our CA; not a bypass). It is used for the TLS 1.3 / key-log captures in Task G because it
  can force `--tlsv1.3` and write `SSLKEYLOGFILE`. Apple's LibreSSL build rejects `--tlsv1.3` ("option not built-in")
  although it negotiates TLS 1.3 by default.
- `-k/--insecure` was never used anywhere.

**Which layer**: TLS sits between TCP (transport) and HTTP (application): the session/presentation role of encryption,
integrity and server authentication. ALPN (inside the TLS ClientHello) chooses the application protocol, h2 or http/1.1.

**Why it matters**: the Phase 1 gate says "no certificate warning". That is only meaningful if the certificate is
really checked: the name matches the SAN, the chain leads to a trusted root, and the dates are valid. Files 03 and 04
show the check failing without our CA and passing with it.
