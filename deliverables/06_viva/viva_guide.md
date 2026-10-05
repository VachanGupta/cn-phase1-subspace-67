# subspace_67 · viva guide (Phase 1, whole system)

Every member must be able to explain **any** part, not just their own. Read the overview, then all three machine sections, then test yourself with the questions at the end. Answers must come from understanding, not notes.

## The whole system in 60 seconds

1. **DNS** (UDP 53): the client asks mac_vachan's dnsmasq (10.7.23.136) for `app.subspace-67.test` and gets the edge IP 10.7.19.193 (TTL 60).
2. **TCP** (443): SYN, SYN-ACK, ACK to the edge.
3. **TLS**: nginx presents a certificate for app.subspace-67.test signed by our own CA ("subspace_67 Local Root CA", trusted in every Mac's System keychain), so there is no warning.
4. **HTTP/2** inside TLS: `GET /api/status`.
5. **Load balancer**: nginx round-robins to Backend A (mac_abhay :3001) or B (mac_vachan :3002) over plain HTTP on the LAN, adding X-Forwarded-For.
6. The backend answers with `X-Backend: A|B`; nginx relays it back through TLS.

Where things break (failure demos): wrong DNS server -> no name (F1); wrong record -> wrong host (F2); one backend down -> failover (F3); both down -> TLS ok then 502 (F4); wrong port -> RST (F5).

## Mac 1 · DNS server + Backend B + client + integrator (mac_vachan)


> mac_vachan = **Mac 1**: our private **DNS server** (dnsmasq), **Backend B** (Python on port 3002),
> a **test client**, and the **integrator** who runs the failure demos and builds the deliverables.
> We are a team of 3, so Mac 4's "client" role is merged into this Mac (the brief allows combining roles).

### 0. The whole system in one breath

A client types `https://app.subspace-67.test`.
1. **DNS** (UDP port 53): the client's resolver asks *our* DNS server on mac_vachan (10.7.23.136), "what is
   the IPv4 address of app.subspace-67.test?" dnsmasq answers from its own records: **10.7.19.193**
   (mac_aanya, the edge).
2. **TCP** (port 443): the client opens a TCP connection to 10.7.19.193:443 (SYN, SYN-ACK, ACK).
3. **TLS**: nginx on mac_aanya presents a certificate for app.subspace-67.test signed by our own CA.
   Every Mac trusts that CA, so there is no warning.
4. **HTTP**: inside the encrypted tunnel the client sends `GET /api/status`.
5. **Load balancer**: nginx picks a backend in round-robin order, A (mac_abhay 10.7.1.136:3001) or
   B (mac_vachan 10.7.23.136:3002), and forwards the request as **plain HTTP** over the LAN.
6. The backend answers with the header `X-Backend: A` or `B`, and nginx relays it back through TLS.

The client only ever knows the **name**. It never needs a backend IP, and it never talks to a backend directly.

### 1. This Mac's network identity (Task A)

| | |
|---|---|
| Interface | en0 (network service "Wi-Fi") |
| IPv4 / mask | 10.7.23.136 / 255.255.224.0 = **/19** |
| Network / broadcast | 10.7.0.0 - 10.7.31.255 (8,190 usable hosts) |
| Gateway | 10.7.0.1 |
| MAC on the air | 6a:e1:56:86:a2:23 (macOS *Private Wi-Fi Address*, randomised per network) |
| Hardware MAC | 10:9f:41:ba:e3:83 |

- **Mask /19**: the first 19 bits are the network part. All three Macs (10.7.23.136, 10.7.19.193,
  10.7.1.136) fall inside 10.7.0.0/19, so they reach each other **directly on the LAN**. A Mac finds a
  peer's MAC address with ARP and sends the frame straight to it, with no router hop (ping shows TTL 64,
  so nothing decremented it). Anything outside the /19 (such as 1.1.1.1) goes to the gateway.
- **Two MACs**: macOS uses a random "private" MAC per Wi-Fi network for privacy. `ifconfig` shows the
  one really in use, and `networksetup -getmacaddress` shows the burned-in one.

### 2. The DNS server (dnsmasq)

#### What DNS does here
DNS is a **directory**: it turns a name into an IP address. It does **not** carry our traffic. After the
answer arrives, the client connects to the IP by itself (failure demo F2 proves this: a wrong answer
means the connection goes to the wrong machine).

#### Why our own DNS server?
`subspace-67.test` exists only inside our LAN. Public resolvers (8.8.8.8) would answer NXDOMAIN
("no such name"). So every Mac uses **only** mac_vachan (10.7.23.136) as its DNS server. dnsmasq
answers our names itself and forwards all other names (google.com, api.anthropic.com) to real
resolvers, so the internet keeps working.

- **Why `.test`?** It is reserved for testing (RFC 2606/6761), so it can never clash with a real
  domain. We avoid `.local` because macOS uses it for multicast DNS (Bonjour/mDNS on 224.0.0.251:5353),
  so `.local` names would bypass our server.
- **Why a hyphen?** `subspace-67`: underscores are not allowed in hostnames, and certificate validation
  rejects them.

#### The config, line by line (configs/dnsmasq.conf)
| line | meaning / why |
|---|---|
| `local=/subspace-67.test/` | We are the final word for this zone. Never ask upstream about it, and answer NXDOMAIN for names we don't have. |
| `host-record=app.subspace-67.test,10.7.19.193` | The A record (and matching PTR) for the service, pointing at the **edge**, not a backend |
| `host-record=api.subspace-67.test,10.7.19.193` | Second name on the same edge (the certificate covers both) |
| `local-ttl=60` | Clients may cache our answer for 60 s. Short, so an IP change on demo day spreads quickly. |
| `no-resolv` | Don't read /etc/resolv.conf. This Mac's resolver points at itself, so reading it would create a **forwarding loop**. |
| `server=8.8.8.8`, `server=1.1.1.1` | Upstream resolvers for every other name. (The spec suggested the gateway, but 10.7.0.1 does not answer DNS on this Wi-Fi: `dig @10.7.0.1` times out. So we use the DHCP-provided resolver 8.8.8.8 plus 1.1.1.1.) |
| `domain-needed`, `bogus-priv` | Never leak single-label names or private-range reverse lookups to the internet |
| `listen-address=10.7.23.136`, `listen-address=127.0.0.1` | Serve the LAN (other Macs) and this Mac itself, nothing else |
| `bind-interfaces`, `user=nobody` | macOS dnsmasq binds each address separately. Binding port 53 (below 1024) on a specific address requires root, so launchd starts it as root and it drops to `nobody` right after binding. |
| `log-queries=extra` + `log-facility=logs/dnsmasq.log` | One log line per query, with the **client's IP**. This proves mac_aanya and mac_abhay really asked us. |

#### Non-root vs root: what we tried
macOS lets a normal user bind low ports only on the **wildcard** address (0.0.0.0). Our test showed
`bind 0.0.0.0:53 OK` but `bind 127.0.0.1:53: Permission denied`. dnsmasq on macOS forces
`bind-interfaces` (it logs "setting --bind-interfaces option because of OS limitations"), so
non-root it fails with "failed to create listening socket for 10.7.23.136: Permission denied".
The fix is a **root Homebrew service** (`sudo brew services start dnsmasq`). It is also started at
boot and is exempt from macOS's Local Network privacy prompts.

#### How one lookup travels
1. An app calls `getaddrinfo("app.subspace-67.test")`. macOS's resolver daemon **mDNSResponder** checks
   its cache, then sends a DNS query in a **UDP** datagram from a random *ephemeral* port to
   10.7.23.136:**53**.
2. dnsmasq matches the `local=` zone, builds the answer from `host-record`, and replies (flag `aa`
   authoritative, TTL 60).
3. For google.com, dnsmasq forwards the query to 8.8.8.8, caches the answer and relays it.
- **UDP vs TCP 53**: normal queries use UDP (one small request, one small reply, no handshake). DNS
  falls back to TCP when a reply is too big (the TC bit is set) and for zone transfers. dnsmasq listens on both.

#### Commands to know
`dig app.subspace-67.test` (the SERVER line shows who answered), `dig @10.7.23.136 ...` (ask a specific
server), `nslookup`, `scutil --dns` (the resolvers macOS really uses), `networksetup -getdnsservers Wi-Fi`,
`dscacheutil -flushcache; killall -HUP mDNSResponder` (flush the cache).

**Cloud equivalent:** dnsmasq plays the role of a *Route 53 private hosted zone* (or Cloud DNS), which
answers names inside a VPC.

### 3. Backend B (backend/backend.py, port 3002)

- Python standard library only: a `ThreadingHTTPServer` (one thread per connection), started with
  `BACKEND_ID=B PORT=3002`. mac_abhay runs the **byte-identical** file as Backend A (`shasum` proves it).
- It binds **0.0.0.0**, not 127.0.0.1. 127.0.0.1 would accept only connections from this same Mac,
  and the edge on 10.7.19.193 must reach it over Wi-Fi.
- Every response carries `X-Backend: B`, even 304 and 404. That header is how a client can *see*
  which backend served it (round robin shows A, B, A, B).
- Endpoints: `/` banner, `/api/status` (`Cache-Control: no-store`, so it is never cached and every
  request really reaches a backend), `/api/cache-demo` (see below), and 404 JSON for anything else.
  `HEAD` returns the same headers with no body (`curl -I`).
- **Logs** show the TCP peer, for example
  `client=10.7.19.193:50864 ... xff=10.7.1.136`. The connection comes from the **edge**. The real client
  appears only in the `X-Forwarded-For` header that nginx adds. The same port 50864 on several lines
  means nginx **reuses** one keep-alive TCP connection for many requests.

#### /api/cache-demo, ETag and 304
- The body is **identical bytes** on A and B (no backend id, no timestamp). So both compute the same
  `ETag: "6adb0ec0cb57508d"` (the first 16 hex characters of the SHA-256 of the body), and both send a
  fixed `Last-Modified` plus `Cache-Control: public, max-age=60`.
- **Fresh cache hit**: for 60 s a browser reuses its copy without asking at all (zero network).
- **Conditional request**: after that it asks `If-None-Match: "6adb0ec0cb57508d"`. If the ETag
  still matches, the server answers **304 Not Modified** with no body, and the client reuses its copy.
  Because both backends agree on the ETag, the 304 works whichever backend the load balancer picks.
- **Full request**: no validator, or the content changed, gives a 200 with the full body.

### 4. The supervisor and control.json (how failures are made real)
`supervisor.py` starts backend.py as a child process and reads `http://10.7.23.136:8099/control.json`
(`{"A":"up","B":"up"}`) every 2 s.
- `"down"`: it terminates the backend, so the process is gone and the port is **closed**. nginx then
  gets *connection refused* (a TCP RST), a genuine network-level failure rather than a fake error page.
- `"up"`: it starts the backend again. It also restarts a backend that crashed.
- If control.json can't be fetched, it keeps the current state (it never flaps because of a network blip).
- If the supervisor is killed (even with `kill -9`), the backend notices its parent is gone and exits.
One file on mac_vachan's bus therefore controls both backends on two different Macs.

### 5. TLS as a client on this Mac
- mac_aanya created **our own CA** ("subspace_67 Local Root CA", name-constrained to
  `subspace-67.test`) and signed the edge's server certificate with it. We trust that CA in the macOS
  **System keychain**. Browsers and the OS then accept `https://app.subspace-67.test` with no
  warning, and we never use `curl -k`.
- *Name constraints*: this CA can only vouch for names under subspace-67.test. Even if its key leaked,
  it could not impersonate google.com. That makes trusting it low-risk.
- `/usr/bin/curl` on macOS defaults to LibreSSL with the static bundle `/etc/ssl/cert.pem`, which does
  **not** include certificates added to the keychain. (See bin/tls_env.sh for how we make curl validate
  our certificate properly.)

### 6. The team bus (how the three Macs coordinate)
Each Mac serves its `share/` folder over HTTP on port 8099 (`python3 -m http.server`). `info.json`
holds its IP and status flags (for example `dns_ready`). Peers are found by fetching
`http://<ip>:8099/info.json` across the subnet. Peer IPs always come from the peer's own info.json,
never typed in by hand, so the setup survives IP changes on demo day.

### 7. What went wrong on build day (and how we diagnosed it, layer by layer)

These are real problems, which makes them good viva answers because they show method, not memorised facts.

1. **"Permission denied" binding port 53.** A normal user may bind low ports only on the wildcard address, and
   macOS dnsmasq binds each address separately. **Fix:** root Homebrew service.
2. **The root service crash-looped (exit code 3).** `launchctl print system/homebrew.mxcl.dnsmasq` showed
   `runs = 17, last exit code = 3` (a filesystem problem): macOS privacy protection (TCC) stops a root launchd
   daemon from reading `~/Desktop`, where the config and log were. **Fix:** a byte-identical config copy in
   `/opt/homebrew/etc`, with the log in `/opt/homebrew/var/log`. launchd's KeepAlive restarted it by itself.
3. **A health check that lied.** `[ -n "$(dig +short ...)" ]` counted dig's
   ";; connection timed out" text as an answer, so the script switched this Mac's DNS to a server that
   wasn't running. This Mac briefly had no DNS. A stopgap relay (wildcard :53, only this Mac's own queries,
   forwarded to 1.1.1.1) kept it online until dnsmasq was fixed. **Lesson:** test the protocol and parse
   the answer; don't trust "non-empty output".
4. **Slow replies from this Mac only** (ping 0.5-0.9 s even to the gateway, while the radio was excellent at
   -36 dBm on 802.11ax). The cause was **macOS Content Caching** serving Apple downloads to 17 campus devices
   at several MB/s. The Wi-Fi transmit queue filled up (*bufferbloat*), so every packet waited behind the
   bulk transfer. There was no loss, just queueing delay. It matters because nginx treats a backend connect
   over 2 s as a failure. **Lesson:** latency to *every* destination with a good signal points to this host's
   queue, not to DNS, TCP or TLS.
5. **Apple's curl and the keychain.** `curl -v` prints `CAfile: /etc/ssl/cert.pem`, which suggests the
   keychain is ignored. We tested instead of guessing: before trusting our CA, `SSL certificate problem:
   self signed certificate in certificate chain`; after trusting it in the System keychain,
   `ssl_verify_result=0` with no `-k` and no `--cacert`. Apple's build honours keychain trust settings.

### 8. The failure demos (run from this Mac; evidence in 04_evidence/failures)

| Demo | What we break | What we observe | Which layer / why |
|---|---|---|---|
| F1 wrong DNS server | this Mac's resolver -> 192.0.2.53 | `dig` times out, curl can't resolve the name, yet `ping 10.7.19.193` and `nc -vz 10.7.19.193 443` succeed | DNS (application-level lookup) is separate from IP reachability. A name failure isn't a network failure. |
| F2 wrong record | app.subspace-67.test -> 10.7.1.136 | dig returns an answer (NOERROR) but the wrong IP; curl gets **connection refused** from 10.7.1.136:443 | DNS is a directory: it answers whatever it's told and never checks that the service is there |
| F3 one backend down | control.json B -> down (and later A -> down) | every request still 200, all from the surviving backend | nginx got a TCP RST from the dead port, retried the other upstream within the same request and skipped the dead one for 10 s |
| F4 both down | A and B -> down | TCP + TLS handshake complete (certificate verified), then nginx itself returns **502 Bad Gateway** | the edge is healthy; the failure is behind it. TLS ends at the edge; the 502 is generated there. |
| F5 wrong port | `https://app.subspace-67.test:8444` | **connection refused** (SYN -> RST,ACK) while ping and port 443 work | an IP identifies the host; a port identifies the service on it |

Systematic diagnosis for any fault: `dig` (name) -> `ping` (IP) -> `nc -vz host 443` (TCP port) ->
`curl -v` / `openssl s_client` (TLS) -> HTTP status, headers and logs (application).

### 9. Integrator: how the team was coordinated and the deliverables built
- The **team bus**: every Mac serves `share/` over HTTP :8099 with `info.json` (IP + status flags).
  `bin/discover.py` finds peers; `bin/watch_bus.py` watches their flags and messages. Messaging between the
  three operator sessions sped things up, but the flags were the source of truth.
- `bin/collect_evidence.py` downloads exactly the files each peer lists in its MANIFEST.txt, records a
  sha256 receipt and refuses anything that looks like a private key.
- `bin/build_deliverables.py` sorts everything into the brief's task folders, writes `INDEX.md`, renders
  HTML and zips `deliverables_subspace_67_phase1.zip`.
- **Demo day:** `./start.sh` on all three Macs. It rediscovers IPs, regenerates the DNS config and uses sudo
  only if this Mac's IP changed. `./stop.sh` stops our processes; `sudo ./restore_network.sh` undoes every
  system change (DNS back to 8.8.8.8/1.1.1.1, CA removed, dnsmasq service removed).

### 10. Where my evidence is
- Task A: `04_evidence/task_A_lan/mac_vachan/` (ifconfig, route, networksetup, pings).
- Task B: `04_evidence/task_B_dns/mac_vachan_dns_server/` (dig/nslookup, `scutil --dns`, **dnsmasq log lines
  from 10.7.19.193 and 10.7.1.136**, service + config, troubleshooting).
- Task C: `04_evidence/task_C_backends/mac_vachan_backend_B/` (endpoints + headers, `lsof *:3002`, backend
  log showing requests only from the edge, unit tests).
- Failures: `04_evidence/failures/F1..F5/` (commands + outputs, pcaps + tshark exports, README with
  observation, layer and why).


## Mac 2 · edge: nginx reverse proxy, load balancer, TLS termination, local CA (mac_aanya)


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

### 1. Reverse proxy vs load balancer

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

### 2. Round robin vs least_conn

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

### 3. The TLS handshake (what happens before any HTTP is sent)

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

### 4. The certificate chain and why clients trust our CA

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

### 5. TLS termination

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

### 6. Why clients never need the backend IPs

- Clients only know the **name** `app.subspace-67.test`. DNS (mac_vachan) maps the name to the
  **edge** (10.7.19.193), never to a backend.
- Only the edge knows the pool (`upstream team_backends`). We can add, remove, move or restart
  backends and **no client changes anything**: that's how you do maintenance and scaling.
- It's also security: backends aren't directly reachable by the name, and the certificate is only
  valid for the name, so a client that tries the IP gets a certificate name mismatch. Our
  `default_server` blocks answer "please use the domain name" to requests by bare IP / unknown Host.
- Our backend IPs themselves are **discovered** (each Mac publishes its own `info.json` on the
  team bus), and `start.sh` regenerates the nginx upstream if the Wi-Fi gives new addresses.

### 7. What nginx does when a backend dies (failover vs 502)

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

### 8. nginx ≈ AWS ALB / GCP HTTP(S) Load Balancer

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

### 9. Why the edge is a single point of failure (SPOF)

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

### 10. Everything this Mac actually does, step by step (and why)

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

### 11. Things that went wrong on the day, and what they teach

| symptom | cause | lesson |
|---|---|---|
| first HTTPS requests to the new nginx hung, then worked | the macOS **application firewall** held incoming connections until someone clicked *Allow* for nginx (Homebrew's nginx is only ad-hoc signed, so it isn't auto-allowed like Developer-ID-signed Python) | a host firewall sits in front of every listening app; "port open" ≠ "reachable" |
| round robin looked random: `A B A A B A A B B A` | 10 nginx worker processes, each with its own round-robin pointer | shared state needs shared memory: `zone team_backends 1m;` → strict `A B A B` |
| `nginx -s reload` refused the new config: "zone is too small" | nginx 1.31 needs more than 64k for an upstream zone | reload is safe: a bad config is rejected and the old one keeps running |
| a peer's first ping/curl said "No route to host" | ARP for that peer hadn't resolved yet (the kernel briefly rejects a destination after an ARP failure); a moment later it worked | "No route to host" on a LAN is usually layer 2 (ARP), or macOS *Local Network* privacy |
| `curl --tlsv1.3` → exit 4 | Apple's LibreSSL build of curl has no such switch | TLS 1.3 is the default anyway; check with `-v` or `-w %{ssl_version}` |
| discovery sometimes missed mac_vachan; ping to it 450–1270 ms while the gateway was 20 ms | **macOS Content Caching** on mac_vachan was serving 17 campus devices at ~2.5 MB/s each way; the Wi-Fi radio was fine (-36 dBm, 344 Mbps) but its queue was full | **latency ≠ bandwidth**: a saturated upload queue adds delay to every packet ("bufferbloat"). Our timeouts (1 s probe, nginx `proxy_connect_timeout 2s`) must fit the real RTT, or healthy servers look dead and get failed over |
| the peers could not be found by scanning | the Wi-Fi is a **/19** (8190 hosts) and the Macs sat in different /22 blocks, so a /22 scan misses them | use discovery that doesn't depend on guessing the subnet (chat hello with the IP), then confirm from the peer's own info.json |

### 12. Likely viva questions, short answers
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


## Mac 3 · Backend A + main test client + packet captures (mac_abhay)


Read this once or twice and you should be able to explain every part without notes.
Team **subspace_67**, domain **subspace-67.test** (hyphen: `_` is not allowed in hostnames or TLS certificates).

---

### 1. The big picture in one breath

A user types `https://app.subspace-67.test`.
1. **DNS**: the client asks *our own* DNS server (dnsmasq on **mac_vachan**) "what is the IP of app.subspace-67.test?" and gets back **mac_aanya's** IP (the edge).
2. **TCP**: the client opens a TCP connection to mac_aanya port 443 (three-way handshake).
3. **TLS**: inside that TCP connection, TLS proves the server really is app.subspace-67.test (a certificate signed by our team CA) and agrees on encryption keys.
4. **HTTP**: the encrypted HTTP request reaches **nginx** on mac_aanya, which picks a backend by **round robin**: **Backend A (this Mac, port 3001)** or **Backend B (mac_vachan, port 3002)**, and forwards the request there over plain HTTP.
5. The backend answers; nginx relays the answer back through the TLS connection to the client.

The client only ever knows the **name** app.subspace-67.test. It never learns or needs the backend IPs.

**My Mac (mac_abhay) plays two parts:**
- **Backend A**: one of the two servers behind the load balancer.
- **Main test client**: I run the dig/curl/openssl tests and the key **packet captures**. This Mac is the right place for them because both the DNS query (to mac_vachan) and the HTTPS connection (to mac_aanya) really cross the Wi-Fi from here.

| Mac | Role | Services |
|---|---|---|
| mac_vachan | DNS server + Backend B + integrator | dnsmasq 53/udp+tcp, Backend B 3002/tcp |
| mac_aanya | edge: nginx reverse proxy, load balancer, TLS termination, team CA | nginx 443/tcp (80 redirects to https) |
| **mac_abhay** (this Mac) | **Backend A + main test client + packet captures** | **Backend A 3001/tcp** |

---

### 2. This Mac's network identity (Task A)

| Item | Value | Command |
|---|---|---|
| Interface | `en0` (Wi-Fi) | `route -n get default` |
| IP address | 10.7.1.136 (via DHCP) | `ipconfig getifaddr en0` |
| Subnet mask | 255.255.224.0 = **/19** (8190 usable hosts: 10.7.0.1 - 10.7.31.254) | `ifconfig en0` shows `0xffffe000` |
| Default gateway | 10.7.0.1 | `route -n get default` |
| MAC on the wire | `8e:f6:fb:7b:0a:59` (macOS *private Wi-Fi address*) | `ifconfig en0` -> `ether` |
| Hardware MAC | `10:9f:41:b9:7b:b6` | `networksetup -listallhardwareports` |

*Why two MACs?* macOS uses a randomised "private Wi-Fi address" per network for privacy. The frames in our captures carry the private one (`8e:f6:...`), not the burned-in hardware address.

*Why /19 matters:* all three Macs (10.7.1.136, 10.7.19.193, 10.7.23.136) are inside 10.7.0.0/19, so they reach each other **directly** on the LAN (ARP gives the peer's MAC, frames go straight to it). The router 10.7.0.1 is only needed for traffic that leaves the subnet (for example DNS forwarding to 8.8.8.8).

---

### 3. The team bus (how the three Macs coordinate)

Each Mac runs a tiny web server, `python3 -m http.server 8099`, serving its `share/` folder.
- `share/info.json` holds my name, IP, mask, gateway, MAC, roles and **status flags** (`backend_A_ready`, `client_evidence_done`). Peers poll it every few seconds, so a flag is the reliable way to say "done".
- **Discovery**: `tools/discover.py` finds peers by fetching `http://<ip>:8099/info.json`. It tries IPs from chat hellos, the ARP cache, peers' `peers.json`, then a parallel scan of my own subnet capped at a /22. IPs are **never hard-coded**; they are always read from each peer's own info.json into `peers.json`.
- Files shared: mac_vachan -> backend code + `control.json`; mac_aanya -> `ca.crt` (public CA certificate only); everyone -> `evidence/<name>/`.
- **Never** in share/: private keys, passwords, tokens.

---

### 4. Backend A (this Mac, port 3001)

- `backend/backend.py` (written once by mac_vachan; **both backends run the identical file**; I verified it with `shasum -a 256 -c SHA256SUMS`). Python standard library only (`ThreadingHTTPServer`).
- Started as `BACKEND_ID=A PORT=3001` by `backend/supervisor.py`, which every 2 s reads `http://<mac_vachan>:8099/control.json` (`{"A":"up","B":"up"}`) and starts/stops the backend process to match. "down" really kills the process, so the port is **closed** and nginx gets *connection refused*. That makes the failure demos real.
- **Binds 0.0.0.0** (all interfaces), not 127.0.0.1. On 127.0.0.1 only processes on this Mac could connect, and nginx on mac_aanya could not reach it. `lsof -nP -iTCP:3001 -sTCP:LISTEN` shows `*:3001`.
- Every response carries **`X-Backend: A`**. That is how a client can see which backend answered, even though it only talks to the edge.
- Every request is logged with the **TCP peer IP:port**. In `logs/backend_A.log` the peer is always **10.7.19.193 (mac_aanya)**, never the real client. This proves clients never talk to a backend directly: nginx opens its own TCP connection to me. The original client IP appears only in the `X-Forwarded-For` header that nginx adds.

Endpoints: `/` (banner), `/api/status` (`Cache-Control: no-store`), `/api/cache-demo` (cacheable, ETag), anything else -> 404 JSON. HEAD works too (`curl -I`).

---

### 5. DNS resolution vs. the connection that follows

These are **two separate conversations with two different machines**:

| | DNS lookup | The real connection |
|---|---|---|
| With whom | mac_vachan (our DNS server) | mac_aanya (the edge) |
| Transport | **UDP** port 53 (one question packet, one answer packet) | **TCP** port 443 |
| Purpose | turn the *name* into an *IP* | carry TLS + HTTP |
| Tool | `dig app.subspace-67.test` / `nslookup` | `curl https://app.subspace-67.test/...` |

DNS only hands out an address; it carries none of the web traffic. After the answer arrives, the client never contacts the DNS server again for this connection. In the capture you see a DNS query/response pair **first**, then a TCP SYN to the address the DNS answer contained.

- `dig` shows `;; SERVER: 10.7.23.136#53` (who answered: mac_vachan) and `app.subspace-67.test. <TTL> IN A 10.7.19.193` (the answer: mac_aanya).
- `dig` talks to the DNS server itself. `curl` asks the macOS resolver (mDNSResponder), which has a **cache**. That's why we flush it (`dscacheutil -flushcache; killall -HUP mDNSResponder`) before a capture, so a fresh query really goes on the wire.
- The `.test` top-level domain is reserved for testing (RFC 2606), so it can never clash with a real site. `.local` is avoided because macOS uses it for mDNS/Bonjour.
- mac_vachan's dnsmasq answers `*.subspace-67.test` itself and forwards every other name to 8.8.8.8 / 1.1.1.1, so the Mac keeps working normally.

---

### 6. UDP vs. TCP

| UDP (DNS) | TCP (HTTPS) |
|---|---|
| connectionless: just send a datagram | connection-oriented: 3-way handshake first |
| no delivery guarantee, no ordering, no retransmission by UDP itself | reliable, ordered byte stream: sequence numbers, ACKs, retransmission |
| 8-byte header (ports, length, checksum) | 20+ byte header (ports, seq, ack, flags, window, options) |
| DNS query = 1 packet, answer = 1 packet: fast; if lost, the *application* (resolver) retries | perfect for web pages: every byte must arrive, in order |

DNS uses UDP because a question and answer each fit in one packet and a retry is cheap. (DNS switches to TCP port 53 for big answers or zone transfers. That's why dnsmasq listens on 53/udp **and** 53/tcp.)

---

### 7. The TCP three-way handshake, sequence/ack numbers, reliability

```
client (10.7.1.136:ephemeral)                   edge (10.7.19.193:443)
   SYN        seq=x                    ->
                                       <-   SYN-ACK  seq=y, ack=x+1
   ACK        seq=x+1, ack=y+1         ->
   (now data flows: TLS ClientHello ...)
```
- Each side picks a random **Initial Sequence Number** (ISN; the "raw" seq in Wireshark, e.g. **2650729791** for my SYN in task_G_tls12). Wireshark shows **relative** numbers (starting at 0) to make them readable. Both are in our exports.
- The SYN and the FIN each "use up" one sequence number. That is why the reply is `ack = x + 1` even though the SYN carries no data.
- **ACK number = "the next byte I expect from you"**, i.e. everything before it arrived. In our capture the ClientHello is 232 bytes starting at seq=1, so the server replies `ack=233` (frames 8 and 10).
- **Reliability**: the sender keeps data until it is ACKed. If no ACK arrives in time (the retransmission timeout), it **retransmits**. Duplicate ACKs trigger a *fast retransmit*. The receiver uses seq numbers to put segments **in order** and drop duplicates. The **window** field says how much more the receiver can accept (flow control).
- SYN options negotiate **MSS** (max segment size, 1460 on Ethernet/Wi-Fi with MTU 1500), **window scale**, **SACK permitted**, timestamps.
- Closing: FIN -> ACK in each direction (or RST to abort). **RST** is also what you get when nobody listens on a port: that is "connection refused", which is exactly what nginx sees when Backend A is "down".

---

### 8. Ports, ephemeral ports, socket pairs

- A **port** identifies a program on a host: 53 = DNS, 443 = HTTPS, 80 = HTTP, 3001 = Backend A, 3002 = Backend B, 8099 = our team bus.
- Servers listen on **well-known/fixed** ports. Clients use a random **ephemeral** port chosen by the OS (macOS range 49152-65535) for each new connection.
- A connection is identified by the **socket pair** (the 4-tuple, plus protocol):
  `(client IP, client ephemeral port, server IP, server port)`, e.g. `(10.7.1.136, 5xxxx) <-> (10.7.19.193, 443)`.
  That's how one server can hold thousands of connections on port 443 at once: each has a different client IP:port.
- There are **two TCP connections** for every request through the proxy:
  1. client 10.7.1.136:ephemeral -> edge 10.7.19.193:443 (TLS)
  2. edge 10.7.19.193:ephemeral -> Backend A 10.7.1.136:3001 (plain HTTP inside our LAN)
  Backend A's log line `client=10.7.19.193:5xxxx` is the **edge's** ephemeral port of connection 2.

---

### 9. TLS: what the handshake does, and 1.2 vs 1.3

TLS gives three things: **confidentiality** (encryption), **integrity** (tampering is detected), **authentication** (the server proves its identity with a certificate).

**Certificates and our CA**
- mac_aanya created a team **root CA** ("subspace_67 Local Root CA") and used it to sign the server certificate for `app.subspace-67.test` / `api.subspace-67.test`.
- A client trusts a certificate if it chains up to a root in its **trust store**. So each Mac adds our CA to the **macOS System keychain** as a trusted root (`security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt`, done with sudo).
- I verified the CA's SHA-256 fingerprint against the one mac_aanya announced over a separate channel (chat) before trusting it. That stops someone substituting a fake CA file.
- Our CA has a critical **Name Constraint: DNS:subspace-67.test**, so even if its key leaked, it could not issue a certificate for any other site (e.g. a bank).
- **Never `curl -k`**: `-k` turns off certificate checking, which defeats authentication. We always validate.
- **curl note (tested, see task_E)**: macOS `/usr/bin/curl` uses LibreSSL. Its verbose output names `CAfile: /etc/ssl/cert.pem`, a file that doesn't contain our CA, **but Apple's build falls back to the macOS keychain trust settings**. So once our CA was trusted in the System keychain, plain `curl https://app.subspace-67.test/` said `SSL certificate verify ok.` with no extra flags. **Homebrew curl** (OpenSSL 3) never reads the keychain: without our CA it fails (`exit 60, self-signed certificate in certificate chain`); with `--cacert certs/ca.crt` it validates. That's full validation against our CA, not a bypass. Safari/Chrome use the keychain directly.

**TLS 1.2 handshake (task_G_tls12.pcapng)**
1. **ClientHello**: TLS versions, cipher suites, random, **SNI = app.subspace-67.test** (tells nginx which certificate to present), **ALPN** = h2, http/1.1.
2. **ServerHello**: chosen version and cipher (ours: **ECDHE-RSA-AES256-GCM-SHA384**, i.e. ECDHE key exchange, RSA certificate, AES-256-GCM encryption, SHA-384), server random, chosen ALPN (h2).
3. **Certificate**: server certificate + chain. **Visible in clear text in TLS 1.2**: Wireshark shows subject, issuer, SAN.
4. **ServerKeyExchange**: the server's ephemeral ECDHE public key, **signed** with the certificate's private key (proves possession of the key).
5. **ServerHelloDone**.
6. **ClientKeyExchange**: the client's ECDHE public key. Both sides now compute the same shared secret (Diffie-Hellman); it never crosses the wire.
7. **ChangeCipherSpec** (each side): "from now on I encrypt".
8. **Finished** (each side, encrypted): a hash over the whole handshake, so any tampering with earlier messages is detected.
9. **Application Data**: the encrypted HTTP request/response.
That's 2 round trips (2-RTT) before data.

**TLS 1.3 handshake (task_G_tls13.pcapng)**
1. **ClientHello** already includes a **key_share** (the client's ECDHE public key) and `supported_versions` = TLS 1.3.
2. **ServerHello** with the server's key_share. Both sides derive the handshake keys **immediately**.
3. **Everything after ServerHello is encrypted**: EncryptedExtensions, **Certificate**, CertificateVerify, Finished. In Wireshark (without keys) these appear only as "Application Data" records. **So in TLS 1.3 you cannot see the certificate on the wire.** That is why the TLS 1.2 capture is used to show it.
4. A dummy **ChangeCipherSpec** appears only for middlebox compatibility; it has no meaning in 1.3.
5. 1-RTT handshake (faster), only forward-secret (ephemeral) key exchange, legacy ciphers removed.

**Bonus, decryption**: Homebrew curl wrote its session secrets to `SSLKEYLOGFILE` (`task_G_tls12_sslkeylog.txt`, `task_G_tls13_sslkeylog.txt`). Wireshark -> Settings -> Protocols -> TLS -> "(Pre)-Master-Secret log filename" -> that file, and the encrypted records turn into readable HTTP/2 frames (`:method GET`, `:path /api/status`, `x-backend`). The key log unlocks **only these captured sessions**; it contains no private key and can't be used to impersonate the server.

---

### 10. HTTP/1.1 vs HTTP/2

| HTTP/1.1 | HTTP/2 |
|---|---|
| text protocol (`GET /api/status HTTP/1.1` + header lines) | binary **frames** (HEADERS, DATA, SETTINGS, ...) |
| one request at a time per connection (browsers open ~6 connections) | many **streams** multiplexed on one connection |
| headers repeated as text every time | **HPACK** header compression |
| `curl --http1.1` | negotiated with TLS **ALPN** "h2"; `curl --http2` |

curl `-v` shows `ALPN: server accepted h2` and `using HTTP/2`, versus `http/1.1`. Between nginx and the backends it is HTTP/1.1 in plain text; only the client side is h2 over TLS. That's normal for a reverse proxy.

---

### 11. Caching: Cache-Control, ETag, 304

`/api/cache-demo` returns: `Cache-Control: public, max-age=60`, `ETag: "6adb0ec0cb57508d"` (first 16 hex chars of sha256(body)), fixed `Last-Modified`.
The body is **byte-identical on A and B**, so both send the **same ETag**, and a conditional request gets 304 no matter which backend the load balancer picks.

Three different situations:
1. **Fresh cache hit** (within max-age=60 s): the browser uses its stored copy and **sends nothing on the network**. DevTools -> Network shows *"(disk cache)"* / *"(memory cache)"*, status 200, size 0 transferred.
2. **Conditional request / revalidation** (copy is stale, or you force it): the client sends `If-None-Match: "6adb0ec0cb57508d"`. If it still matches, the server answers **`304 Not Modified` with no body** (a few hundred bytes instead of the full resource), and the client reuses its copy.
3. **Full new request** (no copy, or the ETag doesn't match): normal **200** with the full body.

Our evidence (task_F): `curl --etag-save` got **200 with 225 body bytes**, and `--etag-compare` got **304 with 0 body bytes**. Four conditional requests gave 304 from A, B, A, B.

`/api/status` has `Cache-Control: no-store`: never cached, so every request really goes through the load balancer (that's why we use it for round robin).

**Demo-day DevTools**: open https://app.subspace-67.test/api/cache-demo in Chrome, DevTools -> Network (leave "Disable cache" **unchecked**). First load: 200 (full). Press Enter in the address bar within 60 s: 200 *(from disk cache)* = fresh hit. After 60 s, or with a normal reload (Cmd-R): request with `If-None-Match` -> **304**. Shift-Cmd-R (hard reload) skips the cache -> full 200.

---

### 12. Load balancing: why the client never needs backend IPs

- DNS maps the name to **one** IP: the edge. nginx holds the **upstream pool** (`10.7.1.136:3001`, `10.7.23.136:3002`) and picks one per request, round robin, so we see A, B, A, B...
- The client sees one stable name/IP. Backends can be added, removed, restarted or moved to new IPs, and **only nginx's config changes**. That's the whole point of a reverse proxy: decoupling, plus a single place for TLS, logging and health handling.
- If Backend A is down, nginx gets *connection refused* from my port 3001, marks it failed, and sends the request to B. The client just sees B answering.

---

### 12a. What my Mac does during the failure demos (run by mac_vachan)

- mac_vachan edits `control.json` (e.g. `{"A":"down","B":"up"}`). Within 2 s my `supervisor.py` reads it, logs
  `control.json says A=down`, sends SIGTERM to `backend.py`, and logs `backend A is DOWN: ... port 3001 closed (connection refused)`.
- Now a TCP SYN from nginx to 10.7.1.136:3001 gets an immediate **RST** from my kernel (nobody is listening): *connection refused*.
  nginx marks A as failed and retries the request on B, so clients still get 200s, all with `X-Backend: B`.
- When control.json says `"A":"up"` again, the supervisor restarts the backend (`backend A is UP: port 3001 accepting connections`)
  and round robin returns to A, B, A, B.
- If mac_vachan's control.json itself can't be fetched, the supervisor **keeps the current state**, so a bus hiccup never
  kills Backend A by accident. Everything is logged in `logs/backend_A.log`.
- During the demos I send no test traffic (flag `failures_in_progress`), so the evidence shows only the demo's traffic.
- **What really happened in our run** (`task_C/11_supervisor_during_failures.txt`): A=down at 14:08:41.907 -> port 3001 closed
  13 ms later; A=up at 14:08:50.712 -> listening at 14:08:51.355. A 14 s Wi-Fi blip then hit (14:09:05-14:09:19): the supervisor
  logged `cannot read control.json ... keeping current state` and left Backend A running, which is the keep-state rule working live.
  A=down again at 14:09:22.318 (closed 23 ms later), and A=up at 14:09:30.622 (listening 0.11 s later).

### 12b. What our real captures show (numbers to quote in the viva)

From `share/evidence/mac_abhay/task_G/` (full walkthrough in `task_G_explained.md`):
- **DNS**: frame 1 `10.7.1.136:54633 -> 10.7.23.136:53` UDP, query id 0x8773 `A? app.subspace-67.test`. Frame 2 answer
  `A 10.7.19.193, TTL 60` (flag AA = authoritative), 0.26 s later. Then curl's own lookup from port 52172 (done by
  mDNSResponder on curl's behalf, which the pktap capture proves).
- **TCP handshake** (frames 5-7): `54389 -> 443`. SYN seq 2650729791 (raw) -> SYN-ACK seq 2207460345, ack **2650729792** ->
  ACK 2650729792 / **2207460346**. Relative numbers: 0/0 -> 0/1 -> 1/1. MSS 1460, window scale x64, SACK permitted.
- **Reliability live**: frame 21 is a real **retransmission** (no ACK for ~173 ms on Wi-Fi), and frame 25 a duplicate ACK with a
  **SACK block 326-509** saying the copy arrived twice.
- **TLS 1.2**: ClientHello with **SNI app.subspace-67.test** and ALPN h2 -> ServerHello (ECDHE-RSA-AES256-GCM-SHA384, h2) ->
  **Certificate** (leaf + our CA, readable) + ServerKeyExchange (x25519 key signed with RSA-PSS) + ServerHelloDone ->
  ClientKeyExchange + ChangeCipherSpec + Finished -> the server's ChangeCipherSpec + Finished -> Application Data.
- **TLS 1.3**: the ClientHello is 1487 bytes (split over 2 TCP segments) because it carries a **post-quantum hybrid key share
  X25519MLKEM768**. After ServerHello everything is "Application Data". Decrypted with the key log, frame 14 turns out to be
  **Certificate + CertificateVerify + Finished**, and frame 20 is `HEADERS: GET /api/status` (HTTP/2).
- **Proxy hop**: in the TLS 1.3 run the request went to Backend A. Frame 25 shows **nginx 10.7.19.193:52365 -> 10.7.1.136:3001**
  SYN, then `GET /api/status HTTP/1.1` in **plain text**, then `HTTP/1.1 200 OK`. That's one user request = two TCP connections.

### 13. How to read our captures in Wireshark

Open `share/evidence/mac_abhay/task_G/task_G_tls12.pcapng` (double-click, or `open -a Wireshark file.pcapng`). Useful display filters:

| Filter | Shows |
|---|---|
| `dns` | the query (client ephemeral port -> 53/UDP) and the response (answer = edge IP) |
| `dns.qry.name == "app.subspace-67.test"` | only our name's queries/answers |
| `tcp.flags.syn == 1` | the SYN and SYN-ACK (start of each TCP connection) |
| `tcp.stream == 0` | one whole TCP connection (right-click a packet -> Follow -> TCP Stream) |
| `tls.handshake` | ClientHello, ServerHello, Certificate, ... |
| `tls.handshake.type == 1` | ClientHello: expand TLS -> Extension: server_name -> **SNI** |
| `tls.handshake.type == 11` | Certificate (visible in 1.2 only) |
| `tls.record.content_type == 23` | encrypted Application Data |
| `tcp.port == 3001` | nginx -> Backend A hop (if the request went to A) |

How to read one packet (the detail pane, top to bottom = bottom layer to top layer):
- **Frame**: arrival time, length.
- **Ethernet II**: source/destination MAC (Wi-Fi frames are shown as Ethernet by macOS).
- **Internet Protocol Version 4**: source/destination IP, TTL, protocol (17 = UDP, 6 = TCP).
- **UDP / TCP**: source/destination port; for TCP also seq/ack/flags/window.
- **DNS / TLS / HTTP**: the application data.

Tip: *Statistics -> Conversations* gives the port table; *Statistics -> Flow Graph* draws the handshake as arrows.

---

### 14. What I changed on this Mac, and how to undo it

- Wi-Fi DNS -> mac_vachan's IP only (`networksetup -setdnsservers Wi-Fi <ip>`). The original setting (none set manually = use DHCP's) is saved in `original_network_settings.txt`.
- Our CA trusted in the System keychain.
- These need **root**, so they are batched in `sudo/01_dns_and_ca.sh` (one password). Captures are in `sudo/02_capture_task_G.sh`: root is needed only to flush mDNSResponder's cache and for the pktap interface. Plain tcpdump works as my user because Wireshark's ChmodBPF gives the `access_bpf` group access to `/dev/bpf*`.
- **Gotcha we hit (macOS Local Network privacy)**: in the first capture, Apple's `/usr/bin/curl` launched from the root script failed instantly with "No route to host", and the pcap shows **no SYN at all**, while DNS and other traffic to the same Mac were fine. macOS blocked the app from reaching the local network *before* any packet left. Homebrew curl was allowed, so the capture was retaken with it. The failed pcap is kept as `attempt1_blocked_task_G_tls12.pcapng`: a nice example of "the network is fine, the host policy is not".
- `./start.sh` rediscovers peers and fixes anything whose IP changed; `./stop.sh` stops my processes; **`./restore_network.sh` undoes all system changes** (DNS back to DHCP, flush, remove the CA).

---

### 15. Quick viva answers

- *Why does Backend A's log show mac_aanya's IP, not yours?* Because nginx terminates the client's connection and opens a **new** TCP connection to the backend; the backend's TCP peer is the proxy. The client IP is only in `X-Forwarded-For`.
- *What if DNS is down?* The name can't be turned into an IP, so curl fails with "Could not resolve host" **before any TCP packet is sent**. The edge and backends are fine but unreachable by name.
- *What if one backend is down?* nginx gets RST (connection refused), retries the other backend; users still get answers (only from the other one).
- *Why TLS 1.2 for the certificate screenshot?* In 1.3 the Certificate message is encrypted.
- *Why is the ACK number x+1 after a SYN?* The SYN flag counts as one byte of sequence space.
- *What is SNI for?* One IP:443 can host many names; SNI tells the server which certificate to send, **before** encryption starts, so it is visible in the ClientHello.
- *304 vs fresh hit?* Fresh hit = no request at all (within max-age). 304 = a request was made, but the body was not resent because the ETag matched.


## Likely viva questions, with short answers

### LAN and addressing (Task A)
1. **What is your IP, mask and gateway, and what does /19 mean?** For example mac_vachan is 10.7.23.136/19,
   mask 255.255.224.0, gateway 10.7.0.1. /19 means the first 19 bits identify the network, so 10.7.0.0 to
   10.7.31.255 is one subnet with 8,190 usable host addresses.
2. **Why can the Macs talk directly, without the router?** All three IPs are inside 10.7.0.0/19. For an
   on-link destination a Mac ARPs for the peer's MAC and sends the frame straight to it; only off-subnet
   traffic goes to the gateway. Ping shows TTL 64, meaning no router decremented it.
3. **Why do `ifconfig` and `networksetup -getmacaddress` show different MACs?** macOS uses a *Private
   Wi-Fi Address* (a random MAC per network) for privacy. The burned-in hardware MAC isn't used on this network.
4. **What does ARP do?** It maps an IPv4 address to a MAC address on the local link (a broadcast "who has
   10.7.19.193?" and a unicast reply). `arp -an` shows the cache.

### DNS (Task B)
5. **What happens when you type app.subspace-67.test?** The OS resolver (mDNSResponder) sends a DNS query
   over UDP from an ephemeral port to 10.7.23.136:53. dnsmasq answers 10.7.19.193 (TTL 60) from its
   `host-record`. Only then does the client open TCP to 10.7.19.193:443.
6. **DNS resolution vs the connection: what's the difference?** DNS only turns a name into an IP. It
   carries no application data. The TCP/TLS/HTTP connection is a separate step, to the IP DNS returned.
   F2 proves it: a wrong record sends the client to the wrong host.
7. **Why UDP for DNS?** One small question and one small answer. There's no handshake, so it's fast and
   has less overhead. TCP 53 is used when a reply is too big (the TC bit) or for zone transfers; dnsmasq
   listens on both.
8. **Why `.test`, why not `.local`, why a hyphen?** `.test` is reserved (RFC 2606/6761) and never exists
   publicly. `.local` belongs to multicast DNS (Bonjour) on macOS and would bypass our server. Underscores
   are illegal in hostnames and break certificate checks.
9. **Why must clients use only our DNS server?** Public resolvers don't know our private zone (NXDOMAIN),
   and macOS may query any configured server. dnsmasq forwards all other names upstream, so the
   internet still works.
10. **What do `local=`, `no-resolv` and `server=` do?** `local=/subspace-67.test/` makes us authoritative:
    we never forward our zone and answer NXDOMAIN for unknown names. `no-resolv` ignores resolv.conf,
    which would point back at ourselves (a loop). `server=` sets the upstream resolvers (8.8.8.8, 1.1.1.1).
11. **What is TTL and why 60 s?** It is how long clients may cache the answer. Short, so a change (a new IP
    on demo day, or a migration) takes effect within a minute. The trade-off is more queries.
12. **How do you prove other Macs use your DNS server?** Their `dig` shows `SERVER: 10.7.23.136#53`, their
    `scutil --dns` lists resolver #1 = 10.7.23.136, and our dnsmasq log shows
    `query[A] app.subspace-67.test from 10.7.1.136` / `from 10.7.19.193`.
13. **Why does dnsmasq need root on macOS?** macOS dnsmasq binds each listen address separately, and
    binding a port below 1024 on a *specific* address needs root. A normal user may only bind the
    wildcard 0.0.0.0. It drops to `nobody` right after binding.

### Transport (TCP/UDP, ports)
14. **Describe the TCP three-way handshake.** The client sends SYN (seq = x). The server replies SYN-ACK
    (seq = y, ack = x+1). The client sends ACK (ack = y+1). Both sides have now agreed on initial sequence
    numbers, and data can flow.
15. **What are sequence and acknowledgement numbers for?** Every byte is numbered. The receiver ACKs the
    next byte it expects. Missing ACKs trigger retransmission, and the numbers put segments back in
    order: this is TCP's reliability. Wireshark shows *relative* numbers starting at 0; the raw ISNs are random.
16. **What is an ephemeral port? What is a socket pair?** The client's temporary source port (e.g. 53700),
    picked by the OS. A connection is identified by the 4-tuple (src IP, src port, dst IP, dst port),
    e.g. 10.7.1.136:62812 -> 10.7.19.193:443.
17. **Which well-known ports do you use?** 53/UDP+TCP for DNS, 443/TCP for HTTPS, 80/TCP (redirect),
    3001 and 3002/TCP for the backends, 8099/TCP for our team bus.
18. **What does "connection refused" mean at packet level?** The host is up but no process listens on that
    port, so its kernel answers the SYN with an **RST**. That is F5 (port 8444), and nginx's view of a
    stopped backend in F3/F4. A timeout instead means packets are dropped (a firewall or dead host).

### TLS (Task E)
19. **Walk through the TLS handshake.** ClientHello (versions, ciphers, SNI = app.subspace-67.test, ALPN
    h2, key share) -> ServerHello (chosen version, cipher, key share) -> Certificate (+ CertificateVerify)
    -> Finished from both sides. Key exchange (ECDHE) derives the session keys. After that everything is
    Application Data (encrypted).
20. **TLS 1.2 vs 1.3?** 1.3 needs one round trip instead of two and removes old ciphers. It encrypts
    everything after ServerHello, *including the certificate*, which is why we also captured TLS 1.2 to
    show the Certificate in clear. In 1.2 you see ChangeCipherSpec and a separate ServerKeyExchange.
21. **Why does the browser trust your certificate?** The leaf (CN/SAN app.subspace-67.test) is signed by
    "subspace_67 Local Root CA", and every Mac has that CA in its System keychain as trusted. Validation
    also checks the SAN matches the name, the dates, and the EKU serverAuth.
22. **What is SNI?** Server Name Indication: the hostname in the ClientHello, in clear text, so the server
    can choose the right certificate or virtual host. Our edge refuses unknown names or bare IPs with 400.
23. **What does TLS termination mean? Where does it happen?** The edge (nginx) decrypts TLS and talks
    plain HTTP to the backends. Only the edge holds the private key. mac_aanya's capture shows the same
    request encrypted on the client leg and in clear on the backend leg.
24. **Why never `curl -k`?** `-k` disables certificate validation, which is exactly what TLS is supposed
    to prove. We fixed trust properly: the CA is in the keychain. (`/usr/bin/curl` on macOS honours it.)
25. **What is the name constraint on your CA?** The CA may only sign names under subspace-67.test. Even if
    its key leaked, it couldn't impersonate google.com, so trusting it is low-risk.

### HTTP, caching (Tasks C, F)
26. **HTTP/1.1 vs HTTP/2?** HTTP/1.1 is text-based, one request at a time per connection. HTTP/2 is binary
    framing with many parallel *streams* over one connection and header compression (HPACK). It is chosen
    in the TLS handshake via ALPN (`h2`). Our edge speaks HTTP/2 to clients and HTTP/1.1 to backends.
27. **What does `X-Backend` prove?** Which backend produced the response, so round robin is visible
    from the client side without backend IPs.
28. **Explain Cache-Control, ETag and 304.** `Cache-Control: public, max-age=60` means any cache may reuse
    the response for 60 s. `ETag` is a fingerprint of the body. A later `If-None-Match: "<etag>"` asks "has
    it changed?", and if not the server answers **304 Not Modified** with no body.
29. **Fresh cache hit vs conditional request vs full request?** A fresh hit is served from the local cache
    with no network at all (DevTools shows "disk/memory cache"). A conditional request is a small round trip
    that ends in 304. A full request downloads the whole 200 response.
30. **Why does 304 work no matter which backend answers?** Both backends run byte-identical code and
    return a byte-identical cache-demo body, so both compute the same ETag
    (the first 16 hex characters of SHA-256 of the body).
31. **Why must backends bind 0.0.0.0?** 127.0.0.1 only accepts connections from the same machine. The edge
    connects over Wi-Fi to the LAN IP.

### Load balancing (Task D)
32. **Reverse proxy vs load balancer?** A reverse proxy is a server that accepts client connections on
    behalf of backends (it can terminate TLS, add headers, route). A load balancer is a reverse proxy that
    spreads requests over several backends. nginx does both here.
33. **Round robin vs least_conn?** Round robin takes turns: A, B, A, B. least_conn picks the backend with
    the fewest active connections, which is better when requests vary in length. Ours are tiny, so round
    robin is fine.
34. **Why doesn't the client need backend IPs?** It only talks to the edge. The edge's `upstream` block is
    the only place backend IPs exist. This also lets us replace or hide backends freely.
35. **Why do the backend logs show the edge's IP?** nginx opens its own TCP connection to the backend, so
    the TCP peer is 10.7.19.193. The real client is only in `X-Forwarded-For` / `X-Real-IP`.
36. **What is the `zone` directive for?** It lets nginx's worker processes share one round-robin pointer and
    one set of failure counters. Without it, each of the 10 workers rotates on its own, and a client saw
    A A B B.

### Failures (F1-F5)
37. **F1: wrong DNS server. What fails and what doesn't?** Name resolution fails: dig times out, curl
    "Could not resolve host" or a resolving timeout. Ping and `nc -vz 10.7.19.193 443` to the IP still
    work. DNS and IP connectivity are separate layers.
38. **F2: wrong A record.** dig "succeeds" but returns mac_abhay's IP. curl connects there and gets
    *connection refused* (no 443 on that host). DNS is a directory, not a connection. It doesn't check
    whether the service exists.
39. **F3: one backend down.** Every request still returns 200, all from the other backend. nginx got
    connection refused, retried the other backend within the same request (`proxy_next_upstream error`)
    and skips the dead one for `fail_timeout=10s`.
40. **F4: both backends down.** DNS, TCP and the TLS handshake still succeed (the edge is fine), then nginx
    itself answers **502 Bad Gateway**. That shows exactly where the edge ends and the backends begin.
41. **F5: wrong port.** `https://app.subspace-67.test:8444` gets connection refused (SYN -> RST), while ping
    and port 443 work. The IP address identifies the host; the port identifies the service on it.
42. **How would you diagnose an unknown fault?** Layer by layer: `dig` (DNS) -> `ping` (IP) -> `nc -vz host
    443` (TCP port) -> `curl -v` / `openssl s_client` (TLS) -> HTTP status, headers and logs (application).

### Cloud and design
43. **Map your components to the cloud.** dnsmasq ~ Route 53 private hosted zone. nginx edge ~ AWS ALB /
    GCP HTTPS LB / a CDN edge. The CA ~ ACM (Private CA). The backends ~ EC2 instances in a target group.
    The Wi-Fi LAN ~ a VPC subnet.
44. **What are the single points of failure?** The one edge (nginx on mac_aanya) and the one DNS server. The
    fixes: a second edge plus DNS failover or a floating IP, and a secondary DNS server (Phase 2
    Extensions A/E).
45. **Why a team bus and supervisor?** The three Macs coordinate status and files over plain HTTP (:8099).
    `control.json` lets one Mac stop or start both backends for real (the process dies and the port
    closes), so the failure demos show genuine network behaviour.

