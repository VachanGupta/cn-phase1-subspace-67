# LEARN_mac_aanya: the edge Mac, explained for the viva

This Mac (Aanya, "Mac 2") is the **front door** of the subspace_67 service. Every client that
opens `https://app.subspace-67.test` talks to *this* Mac and only this Mac. nginx here:

1. accepts the HTTPS connection and does the TLS handshake with our own certificate (**TLS termination**),
2. picks a backend in turn, Backend A (mac_abhay) or Backend B (mac_vachan) (**load balancing**),
3. forwards the request to that backend as plain HTTP over the LAN (**reverse proxy**),
4. sends the backend's answer back to the client inside the encrypted connection.

It also runs the team's **Certificate Authority** (the thing that makes browsers and curl trust our
certificate with no warning).

```
client ──DNS query──▶ mac_vachan:53 (dnsmasq)  "app.subspace-67.test = 10.7.19.193"
client ══HTTPS/TLS══▶ mac_aanya:443 (nginx) ──HTTP──▶ Backend A  mac_abhay:3001
        (encrypted)     TLS ends here        └─HTTP──▶ Backend B  mac_vachan:3002
```

Addresses on project day (they come from DHCP and can change; nothing is hard-coded):

| Mac | IP | role |
|---|---|---|
| mac_aanya (this) | 10.7.19.193 /19, gw 10.7.0.1, en0 Wi-Fi | edge: nginx 443 (+80 redirect), load balancer, TLS, CA |
| mac_vachan | 10.7.23.136 | DNS server (dnsmasq), Backend B :3002, integrator |
| mac_abhay | 10.7.1.136 | Backend A :3001, main test client (packet captures) |

---------------------------------------------------------------------------------------------

## 1. Reverse proxy vs load balancer

- A **forward proxy** works for *clients* (e.g., a school proxy that you send all your web traffic
  through). The server sees the proxy, not you.
- A **reverse proxy** works for *servers*. Clients think they are talking to the real server, but it
  is a middleman in front of the real servers. The client never sees the servers behind it.
  nginx here is a reverse proxy: the client connects to 10.7.19.193:443 and has no idea that
  10.7.1.136:3001 or 10.7.23.136:3002 exist.
- A **load balancer** is a reverse proxy with *more than one* server behind it and a rule for
  choosing which one gets each request. Our `upstream team_backends { A; B; }` block is what
  turns nginx from "just a reverse proxy" into a load balancer.

So: every load balancer (of this kind) is a reverse proxy, but a reverse proxy with one backend
is not load balancing anything.

Things our reverse proxy does besides forwarding:
- **hides the backends**: clients only ever use the name; backend IPs never appear in responses.
  nginx even replaces the backend's `Server:` header with its own and we set `server_tokens off`.
- **adds headers** so the backend still knows who the real client is:
  `X-Real-IP` / `X-Forwarded-For` (client IP), `X-Forwarded-Proto: https` (the client used TLS),
  `Host` (which name the client asked for). The backends log the *edge's* IP as the TCP peer,
  which is the proof that traffic comes through the edge.
- **one place for TLS, logging and failover** instead of in every backend.

## 2. Round robin vs least_conn

- **Round robin** (nginx's default, what we use): request 1 → A, 2 → B, 3 → A, 4 → B, ...
  Simple and fair when every request costs about the same, as ours do.
  Our proof: 10 requests through the edge gave `A B A B A B A B A B`.
- **least_conn**: send the new request to the backend with the *fewest active connections*.
  Better when requests have very different durations (e.g., one slow report + many quick pages),
  because round robin would keep sending new work to a backend that is still busy.
- Others: `ip_hash` / `hash` (same client always goes to the same backend: "sticky sessions"),
  weighted round robin (`weight=3` = gets 3x the traffic, for a bigger machine).

**The zone lesson (something we hit for real):** nginx starts one worker process per CPU core
(10 here). Each worker had its *own* round-robin counter, so at first the order looked random
(`A B A A B A A B B A`). Adding `zone team_backends 1m;` puts the upstream's state (the
round-robin position and the failure counters) in shared memory, so all workers take turns
together and the order became strictly `A B A B ...`. It also means that when a backend dies,
*all* workers learn it at once.

## 3. The TLS handshake (what happens before any HTTP is sent)

TLS runs on top of TCP. First the normal TCP 3-way handshake (SYN, SYN-ACK, ACK) to port 443,
then:

1. **ClientHello** (client → server, in the clear): TLS versions it supports, cipher suites,
   a random number, **SNI = "app.subspace-67.test"** (which site it wants; that's how nginx picks
   the right server block and certificate), **ALPN** = "h2, http/1.1" (which HTTP version it would
   like), and in TLS 1.3 already a **key share** (its half of the Diffie-Hellman exchange).
2. **ServerHello** (server → client): the chosen version and cipher suite, a random number, and
   the server's key share. Both sides can now compute the same secret keys (ECDHE: Elliptic
   Curve Diffie-Hellman *Ephemeral*). The key is never sent over the wire.
3. **Certificate**: the server's certificate chain (our `fullchain.crt`: leaf + CA).
4. **CertificateVerify** (TLS 1.3) / signed **ServerKeyExchange** (TLS 1.2): the server signs the
   handshake with its **private key** (`server.key`). This proves it *owns* the certificate; anyone
   could copy a certificate, but not the key.
5. **Finished** (both directions): a MAC over the whole handshake, so any tampering is detected.
6. Application data (the HTTP request/response), encrypted with AES-GCM or ChaCha20-Poly1305.

**TLS 1.2 vs TLS 1.3**
| | TLS 1.2 | TLS 1.3 |
|---|---|---|
| round trips before data | 2 RTT | 1 RTT (0-RTT possible on resumption) |
| Certificate message | **sent in the clear** (visible in Wireshark) | **encrypted** (everything after ServerHello is encrypted) |
| key exchange | ServerKeyExchange + ClientKeyExchange messages; old RSA key transport still allowed | always (EC)DHE, key share inside the Hello messages |
| forward secrecy | only with ECDHE suites | always |
| cipher suites | many, some weak | 5 modern AEAD suites only |

That's why our nginx allows **both** 1.2 and 1.3 (`ssl_protocols TLSv1.2 TLSv1.3`): a 1.2 capture
lets us *see* the Certificate message in Wireshark, while modern clients negotiate 1.3.

What we actually measured (`openssl s_client`):
- TLS 1.2 → cipher `ECDHE-RSA-AES256-GCM-SHA384`: **ECDHE** = key exchange, **RSA** = the server
  signs with its RSA key (authentication), **AES256-GCM** = bulk encryption + integrity, **SHA384** = PRF hash.
- TLS 1.3 → `TLS_AES_256_GCM_SHA384` with key-exchange group **X25519MLKEM768**: a *hybrid*
  post-quantum exchange (classic X25519 elliptic-curve DH + ML-KEM-768, a lattice-based KEM). The session
  key stays safe even against a future quantum computer, as long as either half holds. New OpenSSL
  (3.5+) on both ends picks it automatically. In TLS 1.3 the suite name no longer says how keys are exchanged
  or authenticated; that's negotiated separately (key_share + signature_algorithms extensions).
- curl on macOS negotiated TLS 1.3 with `TLS_CHACHA20_POLY1305_SHA256` (ChaCha20 is fast on CPUs
  without AES hardware; the client listed it first).

**Forward secrecy**: because the key exchange uses fresh (ephemeral) DH keys per connection, even
if `server.key` leaks later, old recorded traffic cannot be decrypted.

## 4. The certificate chain and why clients trust our CA

- A **certificate** binds a public key to names, signed by an issuer. Ours:
  - **Root CA**: "subspace_67 Local Root CA": self-signed, `CA:TRUE`, `keyUsage keyCertSign,cRLSign`,
    RSA 3072, 10 years, **name-constrained** to `subspace-67.test`.
  - **Leaf / server cert**: `CN=app.subspace-67.test`, **SAN** = `app.subspace-67.test`,
    `api.subspace-67.test`, `extendedKeyUsage serverAuth`, RSA 2048, 397 days, signed by the CA.
- The client **validates**:
  1. the leaf's signature checks out with the CA's public key,
  2. dates are valid, `serverAuth` is present, `CA:FALSE` on the leaf,
  3. the hostname it typed is in the **SAN** list (the CN is ignored by modern clients),
  4. the chain ends at a root that is in its **trust store**.
- **Why does anyone trust our home-made CA?** Because each Mac *installed it* as a trusted root:
  `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt`
  (that's the sudo step). Apps that use the macOS trust store (Safari, Chrome, and on macOS 26 even
  `/usr/bin/curl`) now accept it; we checked that our CA is *not* in curl's file bundle
  `/etc/ssl/cert.pem`, yet plain `curl https://app.subspace-67.test` verifies, so Apple's curl consults the
  keychain. Tools with their own trust store (`openssl s_client`, Homebrew curl, Python) are given the CA
  explicitly with `-CAfile` / `--cacert tls/ca.crt`, which is still full validation, never `-k`.
  Public websites get certificates from CAs like Let's Encrypt, whose
  roots ship pre-installed with macOS. We can't get a public certificate for a `.test` name (it
  isn't a real registered domain), so we became our own CA and distributed its root ourselves.
- Rules we had to respect: SAN must contain the name (hence a **hyphen**, not an underscore:
  `_` is illegal in hostnames and fails validation); macOS rejects server certs valid for more than
  **825 days** (we use 397); SHA-256 signature; RSA ≥ 2048; `serverAuth` EKU.
- **Name constraint** (our extra hardening): the CA itself says "I may only vouch for names under
  subspace-67.test". We tested it: a cert for `evil.example.com` signed by our CA is rejected by both
  OpenSSL ("permitted subtree violation") and macOS. So trusting our CA system-wide cannot be abused
  to fake google.com even if `ca.key` leaked.
- **What nginx actually sends** in the Certificate message: `fullchain.crt` = leaf (1110 bytes DER) + root
  CA (1217 bytes DER). Strictly, the root is optional (a client must already have it in its trust store,
  and one sent over the wire is never trusted just because it was sent). Real sites send leaf +
  intermediates only and save ~1.2 KB per handshake. We include it so `openssl s_client -showcerts` and
  Wireshark show the whole chain (depth 0 leaf → depth 1 root).
- The **private keys** (`ca.key`, `server.key`) are `chmod 600` and never leave `tls/`; only the
  public `ca.crt` is shared (on the bus as `share/ca.crt`, with its SHA-256 fingerprint sent by chat
  so the others could check they got the right file).

## 5. TLS termination

"Terminating TLS" = the TLS connection **ends** at nginx. nginx decrypts the request, reads the
HTTP (so it can route, add headers, log), and then opens a **new, separate TCP connection** to a
backend and sends the request as **plain HTTP**. The response comes back in clear to nginx, which
encrypts it into the client's TLS session.

Why do it:
- the backends stay trivial (no certificates, no crypto CPU cost, one place to renew certs),
- the proxy must *read* HTTP to do HTTP-level load balancing, add `X-Forwarded-For`, retry on 502,
- one certificate for many backends.

Trade-off: the edge→backend hop is **unencrypted on the LAN**. That's OK inside a trusted private
network (like a cloud VPC), and our capture shows it on purpose. In production you would either keep
the backend network private or re-encrypt ("TLS bridging" / mTLS to the backends).

**Our proof (packet capture on this Mac, `lo0` + `en0` at the same time, `tcpdump -i pktap,lo0,en0`):**
The client (curl) ran on the edge itself, so leg 1 goes over the **loopback** interface `lo0` (traffic to
your own IP never touches the Wi-Fi), and leg 2 leaves on **en0**. Apple's *pktap* adds the process name
to each packet, so you can literally see `curl` on one side and `nginx` on the other.
- frame 11 (lo0, curl): TLS 1.2 **ClientHello**, SNI `app.subspace-67.test`;
- frame 15 (lo0, nginx): **ServerHello + Certificate + ServerKeyExchange**. In 1.2 we can read the
  certificate: CN app.subspace-67.test, SAN app/api, issuer subspace_67 Local Root CA;
- frame 27 (lo0): the HTTP request as encrypted **Application Data**. The text "X-Backend" occurs
  **0 times** in any port-443 payload;
- frame 31 (en0, nginx → 10.7.23.136:3002): **`GET /api/status HTTP/1.1` in plain text** with
  `X-Forwarded-For: 10.7.19.193`, `X-Forwarded-Proto: https`;
- frame 35 (en0): **`HTTP/1.1 200 OK`, `X-Backend: B`** in plain text;
- frame 37 (lo0): the same response re-encrypted for curl.
Same request, two legs, encrypted on one side, plaintext on the other → nginx terminated TLS.
In the TLS 1.3 handshakes of the same capture (frames 77/81) no Certificate message is visible at all:
1.3 encrypts it. (On lo0 every packet shows up twice, once leaving curl's socket and once arriving at
nginx's, so Wireshark calls the copies "Retransmission"/"Dup ACK". That's a loopback-capture artefact.)
(Files: `share/evidence/mac_aanya/tls_termination/`, explained in `share/evidence/mac_aanya/README.md`.)

## 6. Why clients never need the backend IPs

- Clients only know the **name** `app.subspace-67.test`. DNS (mac_vachan) maps the name to the
  **edge** (10.7.19.193), never to a backend.
- Only the edge knows the pool (`upstream team_backends`). We can add, remove, move or restart
  backends and **no client changes anything**: that's how you do maintenance and scaling.
- It's also security: backends aren't directly reachable by the name, and the certificate is only
  valid for the name, so a client that tries the IP gets a certificate name mismatch. Our
  `default_server` blocks answer "please use the domain name" to requests by bare IP / unknown Host.
- Our backend IPs themselves are **discovered** (each Mac publishes its own `info.json` on the
  team bus), and `start.sh` regenerates the nginx upstream if the Wi-Fi gives new addresses.

## 7. What nginx does when a backend dies (failover vs 502)

Settings: `max_fails=1 fail_timeout=10s`, `proxy_connect_timeout 2s`,
`proxy_next_upstream error timeout http_502 http_503`.

- **One backend down** (e.g., A's process is stopped, so its port is closed and the TCP SYN gets a
  RST, "connection refused"): nginx's attempt to A fails *immediately*, `proxy_next_upstream error`
  makes nginx **retry the same request on B**, and the client still gets `200` from B. It never
  sees the failure (**failover**). Because `max_fails=1`, A is then marked unavailable for
  `fail_timeout=10s` and skipped; after 10 s nginx tries A again (passive health check). The access
  log shows it: `upstream=10.7.1.136:3001, 10.7.23.136:3002 upstream_status=502, 200`.
  If a backend *hangs* instead of refusing, `proxy_connect_timeout 2s` limits the wait before failover.
- **Both backends down**: every attempt fails, nothing is left to retry → nginx itself answers
  **`502 Bad Gateway`** (the gateway, nginx, is fine; what's behind it is bad). While both are marked
  down, nginx answers 502 at once ("no live upstreams").
- **Backend comes back**: after `fail_timeout` it gets traffic again, and round robin resumes, with no
  restart of nginx needed.
- 502 = the gateway got no/invalid response from upstream; 503 = service unavailable (e.g.,
  overloaded); 504 = the gateway timed out waiting for upstream; 499 (nginx-only) = the *client* gave up
  before nginx could answer.

**What our edge logged during mac_vachan's failure demos (30 Sep, 14:08–14:10):**
```
14:08:17 status=200 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 200 x_backend=A   <- B down: retried on A
error:   connect() failed (61: Connection refused) ... upstream: "http://10.7.23.136:3002/..."
warn:    upstream server temporarily disabled                                                   <- max_fails=1
14:08:17-20  every request -> 10.7.1.136:3001 (A) only                                          <- B skipped for 10 s
14:08:33     B back in rotation: B A B A ...                                                    <- passive health check
14:09:28 status=502 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 502          <- both down
14:09:29 status=502 upstream=team_backends request_time=0.000   error: no live upstreams         <- instant 502
14:09:44     A B A B ...                                                                        <- recovered, no reload
```
DNS failures (wrong server, wrong record) and a wrong port leave **no** line in the edge's logs: the
client fails *before* reaching nginx. That itself tells you which layer broke.

## 8. nginx ≈ AWS ALB / GCP HTTP(S) Load Balancer

What we built by hand is exactly what cloud "Layer-7 load balancers" sell as a managed service:

| our setup | AWS Application Load Balancer | GCP HTTP(S) Load Balancer |
|---|---|---|
| nginx on mac_aanya:443 | the ALB (listener on 443) | the global forwarding rule + URL map |
| `upstream team_backends` | **target group** | **backend service** |
| backends A/B | EC2 instances / containers (targets) | instance groups / NEGs |
| `max_fails` / `fail_timeout` (passive) | active **health checks** (+ passive) | health checks |
| our local CA + `server.crt` | certificate from **ACM** | Google-managed certificate |
| TLS termination at nginx | "HTTPS listener" terminates TLS | terminates TLS at Google's edge |
| `X-Forwarded-For/Proto` | same headers added by ALB | same headers |
| dnsmasq A record → edge IP | Route 53 alias → ALB DNS name | Cloud DNS → the LB's anycast IP |

Differences: cloud LBs are themselves **many machines** behind one name/IP (so they are not a
single point of failure), they autoscale, and they use *active* health checks (they poll
`/health` even when there is no traffic). nginx open-source only does passive checks.

## 9. Why the edge is a single point of failure (SPOF)

Everything goes through this one Mac. If it sleeps, loses Wi-Fi, or nginx stops, **the whole
service is down**, even though both backends are healthy, because DNS points only at 10.7.19.193.
(We keep it awake with `caffeinate -dimsu`, lid open, charger in.) Likewise the DNS server
(mac_vachan) is a SPOF for name resolution.

How real systems remove it:
- **two or more edges** sharing a **virtual IP** that moves on failure (keepalived / VRRP), or
- DNS with **several A records** / health-checked DNS failover (Route 53), or
- **anycast** (one IP announced from many places; GCP does this), or
- a managed load balancer, which is internally redundant.
Load balancing gives redundancy for the *backends*; the balancer needs its own redundancy.

---------------------------------------------------------------------------------------------

## 10. Everything this Mac actually does, step by step (and why)

**Step 1: identity + team bus.**
- Found its own facts: `route -n get default` (gateway 10.7.0.1 on en0), `ipconfig getifaddr en0`
  (10.7.19.193), mask 255.255.224.0 = **/19** (network 10.7.0.0 to 10.7.31.255, so all 3 Macs are on
  the same link: they talk directly, and ARP resolves each other's MAC), MAC in use `d6:d2:39:70:e5:9a`
  (a macOS **private Wi-Fi address**; the hardware MAC is 10:9f:41:be:0f:1e). Evidence: `task_A/`.
- **Team bus**: `python3 -m http.server 8099 --bind 0.0.0.0` serving `share/`, a tiny web server so
  the other Macs can read `info.json` (our IP + status flags such as `ca_published`, `edge_ready`)
  and download `ca.crt`. `info.json` is written to a temp file then `mv`'d (atomic rename), so a peer
  never reads a half-written file. `bind 0.0.0.0` = listen on all interfaces (127.0.0.1 would be
  reachable only from this Mac).
- Peer discovery: the peers' IPs came from their chat hellos (a /22 scan around our IP would not have
  found them, because the Wi-Fi subnet is a /19 and they are in other /22s); every IP is then
  confirmed from the peer's *own* `info.json`. `ping` both peers (evidence: `task_A/ping_*.txt`).
- `caffeinate -dimsu` keeps the Mac awake (display, idle, disk, system, user-active).

**Step 2: CA + server certificate** (see §4 and `tls/README.md`).

**Step 3: backends checked directly** before involving nginx:
`curl http://10.7.1.136:3001/api/status` → `X-Backend: A`, `curl http://10.7.23.136:3002/api/status`
→ `X-Backend: B`. If nginx later fails, we already know the backends themselves are fine
(divide and conquer when debugging).

**Step 4: nginx config** (`configs/nginx_subspace_67.conf`, included from Homebrew's `nginx.conf`):
- `upstream team_backends` (round robin, shared `zone`, `max_fails=1 fail_timeout=10s`),
- `listen 443 ssl; http2 on;` for our two names; TLS 1.2 + 1.3,
- `proxy_pass http://team_backends` + the forwarding headers + `proxy_next_upstream` failover,
- **no** `proxy_cache` and **no** gzip, so every request really reaches a backend (X-Backend
  alternates) and `Cache-Control` / `ETag` / 304 reach the client exactly as the backend sent them,
- port 80 → `301` redirect to https; `default_server` blocks tell bare-IP/unknown-Host users to use
  the name,
- custom `log_format` → `logs/nginx_access.log` with `$remote_addr`, `$upstream_addr`,
  `$upstream_status`, `$ssl_protocol`, `$request_time`: the edge-side proof of load balancing and
  failover.
- nginx runs **without root**: macOS lets normal users bind ports < 1024 on the wildcard address.
  The macOS application firewall asked once to "accept incoming connections" for nginx (Homebrew's
  nginx is only ad-hoc signed, so it isn't auto-allowed); we clicked Allow.

**Step 5: one sudo batch** (`sudo/01_dns_trust_capture.sh`): first checks that mac_vachan's DNS
answers both our name *and* public names (so we can't lose the internet), then sets this Mac's DNS
to mac_vachan only, flushes the DNS cache, and trusts `ca.crt` in the System keychain. Then:
`dig app.subspace-67.test` answers 10.7.19.193 from `SERVER: 10.7.23.136#53`;
`curl https://app.subspace-67.test/api/status` works **without `-k` and without `--cacert`** (keychain);
10 requests gave `B A B A B A B A B A`; HTTP/1.1 and HTTP/2 both 200; `http://` → 301 to https;
`/api/cache-demo` keeps `Cache-Control: public, max-age=60` and its `ETag`, and a conditional request
(`If-None-Match`) gets **304 from both A and B**, which works only because both backends serve a
byte-identical body with the same ETag and the edge doesn't cache or re-compress.
Why only mac_vachan as DNS? Our names exist only in its dnsmasq. It answers
`app/api.subspace-67.test` itself (authoritative for our zone) and forwards everything else to
8.8.8.8 / 1.1.1.1, so the internet still works. Before switching, the script checks exactly that.

**Step 6: evidence** (`share/evidence/mac_aanya/`): TLS-termination capture, `openssl s_client`
for TLS 1.2 and 1.3 (chain + "Verify return code: 0 (ok)"), `nginx -T`, access-log excerpts,
DNS settings (Task B).

**Reproducibility**: `start.sh` (rediscovers peers, regenerates the upstream if IPs changed, starts
beacon + nginx, tells you the one sudo command if DNS/trust are missing, verifies end-to-end),
`stop.sh`, and `restore_network.sh` (puts DNS back, removes the CA from the keychain, restores
Homebrew's nginx.conf, removes the firewall entry).

## 11. Things that went wrong on the day, and what they teach

| symptom | cause | lesson |
|---|---|---|
| first HTTPS requests to the new nginx hung, then worked | the macOS **application firewall** held incoming connections until someone clicked *Allow* for nginx (Homebrew's nginx is only ad-hoc signed, so it isn't auto-allowed like Developer-ID-signed Python) | a host firewall sits in front of every listening app; "port open" ≠ "reachable" |
| round robin looked random: `A B A A B A A B B A` | 10 nginx worker processes, each with its own round-robin pointer | shared state needs shared memory: `zone team_backends 1m;` → strict `A B A B` |
| `nginx -s reload` refused the new config: "zone is too small" | nginx 1.31 needs more than 64k for an upstream zone | reload is safe: a bad config is rejected and the old one keeps running |
| a peer's first ping/curl said "No route to host" | ARP for that peer hadn't resolved yet (the kernel briefly rejects a destination after an ARP failure); a moment later it worked | "No route to host" on a LAN is usually layer 2 (ARP), or macOS *Local Network* privacy |
| `curl --tlsv1.3` → exit 4 | Apple's LibreSSL build of curl has no such switch | TLS 1.3 is the default anyway; check with `-v` or `-w %{ssl_version}` |
| discovery sometimes missed mac_vachan; ping to it 450–1270 ms while the gateway was 20 ms | **macOS Content Caching** on mac_vachan was serving 17 campus devices at ~2.5 MB/s each way; the Wi-Fi radio was fine (-36 dBm, 344 Mbps) but its queue was full | **latency ≠ bandwidth**: a saturated upload queue adds delay to every packet ("bufferbloat"). Our timeouts (1 s probe, nginx `proxy_connect_timeout 2s`) must fit the real RTT, or healthy servers look dead and get failed over |
| the peers could not be found by scanning | the Wi-Fi is a **/19** (8190 hosts) and the Macs sat in different /22 blocks, so a /22 scan misses them | use discovery that doesn't depend on guessing the subnet (chat hello with the IP), then confirm from the peer's own info.json |

## 12. Likely viva questions, short answers
- *Why does the client see no certificate warning?* The chain ends at our root, which is installed as
  trusted, and the hostname is in the SAN.
- *Where is the private key?* `tls/server.key` on the edge only (600). The CA key never left `tls/`.
- *What does SNI do?* Tells the server which hostname the client wants *during* the handshake, so
  it can pick the right certificate (many sites on one IP).
- *What is ALPN?* The client and server agree on `h2` vs `http/1.1` inside the TLS handshake.
- *Why HTTP/2?* One TCP+TLS connection carries many parallel requests (multiplexing), with
  compressed headers.
- *Can the backends see the client's IP?* Not at the TCP level (they see the edge's IP) but yes via
  `X-Real-IP` / `X-Forwarded-For`.
- *What if you curl the edge's IP directly?* Certificate name mismatch (the cert is for the names, not
  the IP), and our default server answers "use the domain name".
- *Why not `.local`?* It's reserved for mDNS/Bonjour on macOS; `.test` is reserved for testing (RFC 2606).
