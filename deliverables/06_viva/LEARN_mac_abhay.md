# LEARN_mac_abhay: what this Mac does and why (viva notes)

Read this once or twice and you should be able to explain every part without notes.
Team **subspace_67**, domain **subspace-67.test** (hyphen: `_` is not allowed in hostnames or TLS certificates).

---

## 1. The big picture in one breath

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

## 2. This Mac's network identity (Task A)

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

## 3. The team bus (how the three Macs coordinate)

Each Mac runs a tiny web server, `python3 -m http.server 8099`, serving its `share/` folder.
- `share/info.json` holds my name, IP, mask, gateway, MAC, roles and **status flags** (`backend_A_ready`, `client_evidence_done`). Peers poll it every few seconds, so a flag is the reliable way to say "done".
- **Discovery**: `tools/discover.py` finds peers by fetching `http://<ip>:8099/info.json`. It tries IPs from chat hellos, the ARP cache, peers' `peers.json`, then a parallel scan of my own subnet capped at a /22. IPs are **never hard-coded**; they are always read from each peer's own info.json into `peers.json`.
- Files shared: mac_vachan -> backend code + `control.json`; mac_aanya -> `ca.crt` (public CA certificate only); everyone -> `evidence/<name>/`.
- **Never** in share/: private keys, passwords, tokens.

---

## 4. Backend A (this Mac, port 3001)

- `backend/backend.py` (written once by mac_vachan; **both backends run the identical file**; I verified it with `shasum -a 256 -c SHA256SUMS`). Python standard library only (`ThreadingHTTPServer`).
- Started as `BACKEND_ID=A PORT=3001` by `backend/supervisor.py`, which every 2 s reads `http://<mac_vachan>:8099/control.json` (`{"A":"up","B":"up"}`) and starts/stops the backend process to match. "down" really kills the process, so the port is **closed** and nginx gets *connection refused*. That makes the failure demos real.
- **Binds 0.0.0.0** (all interfaces), not 127.0.0.1. On 127.0.0.1 only processes on this Mac could connect, and nginx on mac_aanya could not reach it. `lsof -nP -iTCP:3001 -sTCP:LISTEN` shows `*:3001`.
- Every response carries **`X-Backend: A`**. That is how a client can see which backend answered, even though it only talks to the edge.
- Every request is logged with the **TCP peer IP:port**. In `logs/backend_A.log` the peer is always **10.7.19.193 (mac_aanya)**, never the real client. This proves clients never talk to a backend directly: nginx opens its own TCP connection to me. The original client IP appears only in the `X-Forwarded-For` header that nginx adds.

Endpoints: `/` (banner), `/api/status` (`Cache-Control: no-store`), `/api/cache-demo` (cacheable, ETag), anything else -> 404 JSON. HEAD works too (`curl -I`).

---

## 5. DNS resolution vs. the connection that follows

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

## 6. UDP vs. TCP

| UDP (DNS) | TCP (HTTPS) |
|---|---|
| connectionless: just send a datagram | connection-oriented: 3-way handshake first |
| no delivery guarantee, no ordering, no retransmission by UDP itself | reliable, ordered byte stream: sequence numbers, ACKs, retransmission |
| 8-byte header (ports, length, checksum) | 20+ byte header (ports, seq, ack, flags, window, options) |
| DNS query = 1 packet, answer = 1 packet: fast; if lost, the *application* (resolver) retries | perfect for web pages: every byte must arrive, in order |

DNS uses UDP because a question and answer each fit in one packet and a retry is cheap. (DNS switches to TCP port 53 for big answers or zone transfers. That's why dnsmasq listens on 53/udp **and** 53/tcp.)

---

## 7. The TCP three-way handshake, sequence/ack numbers, reliability

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

## 8. Ports, ephemeral ports, socket pairs

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

## 9. TLS: what the handshake does, and 1.2 vs 1.3

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

## 10. HTTP/1.1 vs HTTP/2

| HTTP/1.1 | HTTP/2 |
|---|---|
| text protocol (`GET /api/status HTTP/1.1` + header lines) | binary **frames** (HEADERS, DATA, SETTINGS, ...) |
| one request at a time per connection (browsers open ~6 connections) | many **streams** multiplexed on one connection |
| headers repeated as text every time | **HPACK** header compression |
| `curl --http1.1` | negotiated with TLS **ALPN** "h2"; `curl --http2` |

curl `-v` shows `ALPN: server accepted h2` and `using HTTP/2`, versus `http/1.1`. Between nginx and the backends it is HTTP/1.1 in plain text; only the client side is h2 over TLS. That's normal for a reverse proxy.

---

## 11. Caching: Cache-Control, ETag, 304

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

## 12. Load balancing: why the client never needs backend IPs

- DNS maps the name to **one** IP: the edge. nginx holds the **upstream pool** (`10.7.1.136:3001`, `10.7.23.136:3002`) and picks one per request, round robin, so we see A, B, A, B...
- The client sees one stable name/IP. Backends can be added, removed, restarted or moved to new IPs, and **only nginx's config changes**. That's the whole point of a reverse proxy: decoupling, plus a single place for TLS, logging and health handling.
- If Backend A is down, nginx gets *connection refused* from my port 3001, marks it failed, and sends the request to B. The client just sees B answering.

---

## 12a. What my Mac does during the failure demos (run by mac_vachan)

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

## 12b. What our real captures show (numbers to quote in the viva)

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

## 13. How to read our captures in Wireshark

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

## 14. What I changed on this Mac, and how to undo it

- Wi-Fi DNS -> mac_vachan's IP only (`networksetup -setdnsservers Wi-Fi <ip>`). The original setting (none set manually = use DHCP's) is saved in `original_network_settings.txt`.
- Our CA trusted in the System keychain.
- These need **root**, so they are batched in `sudo/01_dns_and_ca.sh` (one password). Captures are in `sudo/02_capture_task_G.sh`: root is needed only to flush mDNSResponder's cache and for the pktap interface. Plain tcpdump works as my user because Wireshark's ChmodBPF gives the `access_bpf` group access to `/dev/bpf*`.
- **Gotcha we hit (macOS Local Network privacy)**: in the first capture, Apple's `/usr/bin/curl` launched from the root script failed instantly with "No route to host", and the pcap shows **no SYN at all**, while DNS and other traffic to the same Mac were fine. macOS blocked the app from reaching the local network *before* any packet left. Homebrew curl was allowed, so the capture was retaken with it. The failed pcap is kept as `attempt1_blocked_task_G_tls12.pcapng`: a nice example of "the network is fine, the host policy is not".
- `./start.sh` rediscovers peers and fixes anything whose IP changed; `./stop.sh` stops my processes; **`./restore_network.sh` undoes all system changes** (DNS back to DHCP, flush, remove the CA).

---

## 15. Quick viva answers

- *Why does Backend A's log show mac_aanya's IP, not yours?* Because nginx terminates the client's connection and opens a **new** TCP connection to the backend; the backend's TCP peer is the proxy. The client IP is only in `X-Forwarded-For`.
- *What if DNS is down?* The name can't be turned into an IP, so curl fails with "Could not resolve host" **before any TCP packet is sent**. The edge and backends are fine but unreachable by name.
- *What if one backend is down?* nginx gets RST (connection refused), retries the other backend; users still get answers (only from the other one).
- *Why TLS 1.2 for the certificate screenshot?* In 1.3 the Certificate message is encrypted.
- *Why is the ACK number x+1 after a SYN?* The SYN flag counts as one byte of sequence space.
- *What is SNI for?* One IP:443 can host many names; SNI tells the server which certificate to send, **before** encryption starts, so it is visible in the ClientHello.
- *304 vs fresh hit?* Fresh hit = no request at all (within max-age). 304 = a request was made, but the body was not resent because the ETag matched.
