# mac_aanya evidence: the edge (nginx reverse proxy + load balancer + TLS termination + local CA)

Captured 2026-09-30 on mac_aanya (10.7.19.193/19, en0 Wi-Fi). Peers: mac_vachan 10.7.23.136
(DNS + Backend B :3002), mac_abhay 10.7.1.136 (Backend A :3001). Every text file holds the exact command
(`$ ...`), its full output and the exit code. No private keys are in this folder.

| folder / file | what it shows | layer | why it matters |
|---|---|---|---|
| `task_A/task_A_commands.txt`, `task_A_summary.txt` | `ifconfig en0`, `route -n get default`, `networksetup -getinfo Wi-Fi`: IP 10.7.19.193, mask 255.255.224.0 (/19), gateway 10.7.0.1, interface en0, MAC d6:d2:39:70:e5:9a (private Wi-Fi address; hardware 10:9f:41:be:0f:1e) | L2/L3 | identity of the edge; all 3 Macs are in 10.7.0.0/19, so they reach each other directly (ARP), not via the router |
| `task_A/ping_mac_*.txt` | 4/4 ICMP replies from both peers + their ARP entries | L2/L3 | basic reachability before any service is built |
| `backends/backends_direct_check.txt` | `curl http://<peer>:300x/api/status` straight to each backend → `X-Backend: A` / `B` | L7 (HTTP) | proves both backends work *before* nginx is involved (divide and conquer) |
| `tls/ca_cert_details.txt`, `server_cert_details.txt`, `ca.cnf`, `server.cnf`, `README_tls.md` | the CA (CA:TRUE, pathlen:0, keyCertSign/cRLSign, nameConstraints subspace-67.test) and the leaf (SAN app+api, EKU serverAuth, 397 days) + how they were made | TLS / PKI | the fields clients check; why each one is there |
| `tls/chain_verification.txt` | `openssl verify` OK; Apple's `security verify-cert` OK for app/api, "Host name mismatch" for a wrong name; a cert for evil.example.com signed by our CA is rejected (name constraint) | TLS / PKI | the chain validates with both OpenSSL and macOS; our CA can't be abused for other domains |
| `step5/root_batch_log.txt` | the one sudo batch: safety check of mac_vachan's DNS, DNS → 10.7.23.136 only, cache flush, CA trusted in the System keychain | OS config | the only root-only changes on this Mac (undo: `restore_network.sh`) |
| `step5/step5_verification.txt` | `dig app.subspace-67.test` → 10.7.19.193 from SERVER 10.7.23.136; plain `curl https://app.subspace-67.test/api/status` (no `-k`, no `--cacert`) → 200; 10 requests → `B A B A B A B A B A`; `--http1.1` and `--http2` → 200; `http://` → 301 to https; cache-demo: `Cache-Control`/`ETag`/`Last-Modified` untouched and `If-None-Match` → **304 from both A and B**; HEAD; 404 with X-Backend | L3 DNS → L4 TCP → TLS → L7 HTTP | the Phase-1 gate from this Mac: name → edge → TLS with no warning → both backends |
| `tls/s_client_tls12.txt`, `s_client_tls13.txt` | `openssl s_client ... -CAfile tls/ca.crt -showcerts`: chain depth 0 = app.subspace-67.test, depth 1 = subspace_67 Local Root CA; **Verify return code: 0 (ok)**; TLS 1.2 = ECDHE-RSA-AES256-GCM-SHA384; TLS 1.3 = TLS_AES_256_GCM_SHA384 with group X25519MLKEM768 (hybrid post-quantum key exchange) | TLS | both protocol versions work and the chain is complete and trusted |
| `tls/s_client_wrong_name.txt` | SNI/verify name `wrong.subspace-67.test` → "Verification error: hostname mismatch" | TLS | the SAN check really happens |
| `tls_termination/edge_tls_termination.pcapng` + `tshark_*.txt` + `tcpdump_pktap_metadata.txt` | **TLS termination** (see below) | L3–L7 | the core proof for this Mac |
| `nginx/nginx_T.txt`, `configs/nginx_subspace_67.conf`, `configs/homebrew_nginx.conf` | the full effective nginx config (`nginx -T`) and the files it's built from | config | upstream (round robin, shared zone, max_fails/fail_timeout), TLS 1.2+1.3, http2, proxy headers, failover, no cache/gzip, redirects, default_server, log format |
| `nginx/access_log_excerpt.txt` | edge access log: `upstream=` alternates 10.7.1.136:3001 / 10.7.23.136:3002, `tls=TLSv1.3`, `x_backend=A/B`, 304s; a count of requests per upstream | L7 (edge view) | edge-side proof of load balancing (and later of failover) |
| `failures/edge_logs_failure_demos.txt`, `failures/NOTES_failures_edge_view.md` | nginx access + error log lines during mac_vachan's failure demos (14:08–14:10): B down → `upstream_status=502, 200` (retry on A, client gets 200) + "temporarily disabled"; A down → mirror; both down → `502, 502` then instant 502 "no live upstreams"; recovery → A/B again; a 499 during a Wi-Fi blip; F1/F2/F5 leave no edge trace | L4 (connect refused) + L7 (502/499) | edge-side proof of failover vs 502, and of *where* each failure happened |
| `task_B/dns_settings.txt` | `networksetup -getdnsservers Wi-Fi` = 10.7.23.136; `scutil --dns` resolver #1 = 10.7.23.136; `/etc/resolv.conf`; original value | DNS config | this Mac uses mac_vachan as its only DNS server |
| `scripts/` | start.sh, stop.sh, restore_network.sh, the sudo batch, cert/config generators, this evidence collector | reproducibility | demo day: `./start.sh` rebuilds everything even if IPs change |

## The TLS-termination capture, explained

**How:** during one sudo run, `tcpdump -i pktap,lo0,en0` captured both interfaces into one pcapng with Apple's
per-packet metadata (interface + process name). Filter: only this Mac's HTTPS-to-itself, edge↔backend HTTP,
and DNS to mac_vachan (no unrelated traffic). Traffic (see `capture_traffic_commands.txt`): `dig`, one request
forced to TLS 1.2 + HTTP/1.1, then requests with curl's default TLS 1.3 (HTTP/2 and HTTP/1.1).

The client is on the edge itself, so leg 1 (curl → nginx, to our own IP) travels over the **loopback
interface lo0**, while leg 2 (nginx → backend) leaves on **en0 (Wi-Fi)**. Same request, two TCP connections:

| frames | interface / process | what you see |
|---|---|---|
| 1–2 | en0 / dig | DNS: `A app.subspace-67.test?` to 10.7.23.136:53 → `A 10.7.19.193` |
| 3–10 | lo0 / curl ↔ nginx | TCP 3-way handshake to :443 |
| 11 | lo0 / curl | **TLS 1.2 ClientHello**, SNI = `app.subspace-67.test`, ALPN http/1.1 |
| 15 | lo0 / nginx | **ServerHello, Certificate, ServerKeyExchange, ServerHelloDone**: in TLS 1.2 the Certificate is readable: subject CN=app.subspace-67.test, SAN app+api, issuer "subspace_67 Local Root CA", followed by the CA cert (`tshark_client_leg_tls.txt`) |
| 19, 23 | lo0 | ClientKeyExchange + ChangeCipherSpec + Finished (encrypted), server ChangeCipherSpec + Finished |
| 27 | lo0 / curl → nginx | **Application Data**: the HTTP request, *encrypted* |
| 31 | **en0 / nginx → 10.7.23.136:3002** | **`GET /api/status HTTP/1.1` in plain text** with `Host`, `X-Real-IP`, `X-Forwarded-For: 10.7.19.193`, `X-Forwarded-Proto: https` |
| 33–35 | en0 / backend B → nginx | **`HTTP/1.1 200 OK`, `X-Backend: B`**, JSON body, in plain text |
| 37 | lo0 / nginx → curl | Application Data: the same response, re-encrypted for the client |
| 77, 81 | lo0 | **TLS 1.3** ClientHello (offers h2) / ServerHello (TLS_CHACHA20_POLY1305_SHA256): after the ServerHello everything, *including the certificate*, is encrypted, so no Certificate message is visible |
| 109–121, 175–179 | en0 / nginx ↔ A:3001, B:3002 | the next requests went to **A** then **B** (round robin), again readable HTTP (`ETag`, `Cache-Control` visible) |

Checks in the exports: the string `X-Backend` appears **0 times** in the TCP payloads on port 443 (it's only
inside encrypted records), and appears in clear on ports 3001/3002. **Encrypted on the client side, plaintext
on the backend side, for the same request = nginx terminates TLS.**

Reading notes:
- On lo0 each packet is captured twice (leaving the sender's socket and arriving at the receiver's socket;
  pktap shows `curl` for one copy and `nginx` for the other), so Wireshark labels the second copy
  "TCP Retransmission" / "Dup ACK". These are capture artefacts, not real retransmissions.
- Leg 2 is plain HTTP on the Wi-Fi LAN on purpose (the lab's "private network"); in production you'd keep
  that network private or re-encrypt to the backends.
- The edge→backend hop shows the edge's IP (10.7.19.193) as the source: the backends never see the client's
  TCP connection, only `X-Forwarded-For`.

Open the pcapng in Wireshark; useful display filters: `tls.handshake`, `tcp.port==443 && tls.app_data`,
`http && (tcp.port==3001 || tcp.port==3002)`, `dns`. Add the columns *Interface name* and *Darwin → Process
Information → Name* to see lo0/en0 and curl/nginx per packet.

## Notes
- `/usr/bin/curl` on macOS 26 (LibreSSL 3.3.6 build) **does** use the System keychain: our CA is not in
  `/etc/ssl/cert.pem`, yet plain `curl https://app.subspace-67.test` verifies (ssl_verify_result=0); with an
  empty `--cacert` file the same request fails. So no `-k` and no `--cacert` were needed. `openssl s_client`
  does not read the keychain, so it gets `-CAfile tls/ca.crt` (still full validation).
- Apple's curl has no `--tlsv1.3` switch (exit 4, nothing sent); TLS 1.3 is its default anyway.
- nginx runs as the normal user (no sudo): macOS allows binding ports < 1024 on the wildcard address. The macOS
  application firewall asked once to allow incoming connections for nginx (ad-hoc signed Homebrew build).
- `zone team_backends 1m;` makes all 10 nginx workers share one round-robin pointer and one set of failure
  counters (before it, one client saw `A B A A B A A B B A`).
