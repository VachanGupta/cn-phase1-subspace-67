# subspace_67 · Phase 1 demo runbook (brief Section 8, steps 1-8)

Team: mac_vachan (Mac 1: DNS server + Backend B + client), mac_aanya (Mac 2: edge nginx + TLS + load
balancer), mac_abhay (Mac 3: Backend A + main client). Domain: **app.subspace-67.test** (hyphen, `.test`).
IPs below are from the evidence day. If Wi-Fi hands out new IPs, `./start.sh` fixes everything, and the demo
uses names only anyway.

## 0. Before the evaluator arrives (demo-day start order)

1. All three Macs: same Wi-Fi, charger in, lid open. Turn off **iCloud Private Relay** for this network
   (System Settings > Apple Account > iCloud > Private Relay) and Chrome's **Use secure DNS**. Both would
   bypass our DNS server in the browser.
2. Run `./start.sh` in the project folder on **all 3 Macs**, in any order. Each Mac starts its beacon,
   rediscovers the others, regenerates configs if an IP changed, starts its services and verifies. Suggested
   order, to minimise waiting: **mac_vachan** first (DNS + Backend B), then **mac_abhay** (Backend A), then
   **mac_aanya** (edge; it rebuilds its upstream list from the others' IPs).
   ```bash
   cd ~/Desktop/work/CN && ./start.sh
   ```
   mac_vachan's start.sh asks for sudo **only** if its IP changed (it restarts dnsmasq and re-points its
   own DNS). If mac_vachan's IP changed, the other two Macs must re-point their DNS to the new IP: their
   start.sh does this.
3. Quick health check from any Mac, expecting both A and B:
   ```bash
   for i in 1 2 3 4 5 6; do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | grep -i x-backend; done
   ```
4. Open these beforehand: `deliverables/01_architecture/architecture.html` (step 1), Wireshark with
   `04_evidence/task_G_protocol_flow/task_G_tls12.pcapng` (step 6), and a Terminal on each Mac.
5. Make sure `share/control.json` on mac_vachan says `{"A": "up", "B": "up"}` (start.sh resets it).

## Step 1 · Show topology and IP/service inventory

- **Who:** anyone, on mac_vachan's screen.
- **Show:** `01_architecture/architecture.html`: the topology diagram, the IP/service table, the DNS
  record table and the request-flow diagram.
- **Say:** "Mac 1 is our DNS server and Backend B (a team of 3, so roles are combined), Mac 2 is the
  edge: nginx with TLS termination and round-robin load balancing, and Mac 3 is Backend A. Clients know
  only the name; backend IPs live only in nginx's upstream block."
- **Point at:** each Mac's IP, mask /19, gateway 10.7.0.1, MAC; ports 53 (DNS), 443 (edge), 3001/3002 (backends).
- **Live proof, if asked:**
  ```bash
  ipconfig getifaddr en0; ipconfig getoption en0 subnet_mask; route -n get default | grep -E 'gateway|interface'; ifconfig en0 | grep ether
  ```

## Step 2 · Confirm all machines are on the private LAN

- **Who:** each Mac pings the other two (or show `04_evidence/task_A_lan/`).
  ```bash
  ping -c 3 10.7.19.193    # mac_aanya
  ping -c 3 10.7.1.136     # mac_abhay
  ping -c 3 10.7.23.136    # mac_vachan
  arp -an | grep -E '10.7.(19.193|1.136|23.136)'
  ```
- **Expected:** `0.0% packet loss`, `ttl=64` (same subnet, no router hop). `arp` shows each peer's MAC on en0.
- **Say:** "All three are in 10.7.0.0/19, so they reach each other directly. ARP turned the IP into a MAC."

## Step 3 · Resolve the private domain from a client

- **Who:** mac_abhay (client). Repeat on mac_aanya if asked: at least two clients use our DNS.
  ```bash
  networksetup -getdnsservers Wi-Fi          # -> 10.7.23.136 only
  dig app.subspace-67.test                     # plain dig: uses the system resolver
  nslookup app.subspace-67.test
  ```
- **Expected:** `status: NOERROR`, `flags: qr aa rd ra`,
  `app.subspace-67.test. 60 IN A 10.7.19.193`, **`;; SERVER: 10.7.23.136#53`**.
- **Point at:** the SERVER line (our DNS server answered), the answer (the edge's IP, not a backend), the
  TTL 60, and the `aa` flag (authoritative for our zone).
- **Proof from the server side**, on mac_vachan:
  ```bash
  grep 'app.subspace-67.test' ~/Desktop/work/CN/logs/dnsmasq.log | tail -5
  ```
  This shows `query[A] app.subspace-67.test from 10.7.1.136`: the query arrived from mac_abhay's IP.
- **Say:** "DNS only finds the address. The TCP and TLS connection that follows is a separate step to that IP."

## Step 4 · Open the service over HTTPS using the domain name

- **Who:** mac_abhay (or any Mac). Browser: open **https://app.subspace-67.test/** and click the padlock
  to show "Certificate is valid", issued by *subspace_67 Local Root CA*.
  ```bash
  curl -v https://app.subspace-67.test/api/status      # no -k
  ```
- **Expected in curl -v:** `Connected to app.subspace-67.test (10.7.19.193) port 443`,
  `SSL connection using TLSv1.3`, `ALPN: server accepted h2`, `subject: ... CN=app.subspace-67.test`,
  `issuer: ... CN=subspace_67 Local Root CA`, **`SSL certificate verify ok`**, `HTTP/2 200`, `x-backend: A|B`.
- **Say:** "No -k, no IP in the URL. Our CA is trusted in the System keychain on every Mac, so the chain
  app.subspace-67.test -> subspace_67 Local Root CA validates. TLS ends here, at nginx."
- **Optional:** `openssl s_client -connect app.subspace-67.test:443 -servername app.subspace-67.test -CAfile tls/ca.crt </dev/null | grep -E 'subject|issuer|Verify return code'`
  gives `Verify return code: 0 (ok)`.

## Step 5 · Show load balancing across both backends

- **Who:** any client.
  ```bash
  for i in $(seq 1 10); do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | grep -i '^x-backend'; done
  ```
- **Expected:** `x-backend: A` / `x-backend: B` alternating (A B A B ...).
- **Point at:** the same URL each time; only the backend changes. The edge's access log on mac_aanya
  shows `$upstream_addr` alternating between 10.7.1.136:3001 and 10.7.23.136:3002. On mac_vachan,
  `tail -f logs/backend_B.log` shows requests coming from **10.7.19.193** (the edge), never from the client.
- **Say:** "nginx round robin, with the rotation shared by all worker processes via `zone`. The client
  never needs backend IPs: it talks only to the edge, and the edge opens its own connection to a backend."

## Step 6 · Show Wireshark evidence of DNS, TCP and TLS

- **Who:** mac_abhay. Open `04_evidence/task_G_protocol_flow/task_G_tls12.pcapng` in Wireshark (then
  `task_G_tls13.pcapng`), and use these display filters in turn:

| Filter | Point at |
|---|---|
| `dns` | query `A app.subspace-67.test` from the client's **ephemeral port -> 53/UDP** at 10.7.23.136; response with `10.7.19.193` |
| `tcp.flags.syn == 1` | **SYN** (client ephemeral -> 443) and **SYN-ACK**; the next packet is the ACK. Seq/ack numbers: raw ISNs and relative 0 -> 1 |
| `tls.handshake` | **ClientHello** (SNI `app.subspace-67.test`), **ServerHello**, **Certificate** (visible in TLS 1.2), key exchange, **ChangeCipherSpec**, **Finished** |
| `tls.record.content_type == 23` | **Application Data**: the HTTP request and response, encrypted |
| `http` | nothing on the client capture, because HTTP is inside TLS. The edge's capture (mac_aanya's evidence) shows plain HTTP to the backends |

- **Say:** "In TLS 1.3 the Certificate is encrypted right after ServerHello, which is why we also captured
  TLS 1.2. The ports: ephemeral -> 53/UDP for DNS, ephemeral -> 443/TCP for HTTPS."
- The text exports with packet numbers are next to each pcap (`*_tshark*.txt`), with a walkthrough in
  `task_G_explained.md`.

## Step 7 · Show HTTP headers and caching behaviour

- **Who:** any client.
  ```bash
  curl -sI https://app.subspace-67.test/api/cache-demo
  curl -sI -H 'If-None-Match: "6adb0ec0cb57508d"' https://app.subspace-67.test/api/cache-demo
  curl -sI https://app.subspace-67.test/api/status
  ```
- **Expected:** (1) `HTTP/2 200`, `cache-control: public, max-age=60`, `etag: "6adb0ec0cb57508d"`,
  `last-modified: Tue, 29 Sep 2026 00:00:00 GMT`; (2) **`HTTP/2 304`** (no body), with the same ETag, from
  A or B; (3) `cache-control: no-store`.
- **Browser:** DevTools > Network > reload `https://app.subspace-67.test/api/cache-demo`. The first load is
  200. Re-open it within 60 s: the Size column shows *(disk cache)* or *(memory cache)* (a **fresh cache hit**,
  no request sent). After 60 s, or with Cmd+R, the browser revalidates and gets **304**.
- **Say:** "A fresh hit uses no network at all. A conditional request asks 'has it changed?' and gets a
  small 304. A full request downloads the body again (200). Both backends return byte-identical bodies,
  so they compute the same ETag and the 304 works whichever backend answers."

## Step 8 · Fail one backend and prove the service continues

- **Who:** mac_vachan controls both backends through `share/control.json`. The supervisor on each backend Mac
  polls it every 2 s and really stops or starts the process.
  ```bash
  cd ~/Desktop/work/CN
  echo '{"A":"down","B":"up"}' > share/control.json      # stop Mac 3's Backend A
  sleep 4; nc -vz 10.7.1.136 3001                          # -> Connection refused (really down)
  for i in $(seq 1 8); do curl -s -D - -o /dev/null -w '%{http_code} ' https://app.subspace-67.test/api/status | grep -i x-backend; done
  echo '{"A":"up","B":"up"}' > share/control.json        # restore
  sleep 12; for i in $(seq 1 6); do curl -s -D - -o /dev/null https://app.subspace-67.test/api/status | grep -i x-backend; done
  ```
- **Expected:** every request is `200` with `x-backend: B` while A is down. After the restore (and nginx's
  10 s `fail_timeout`), A and B alternate again.
- **Say:** "nginx got *connection refused* from 10.7.1.136:3001, retried the same request on Backend B
  (`proxy_next_upstream error`) and marked A as failed for 10 s (`max_fails=1 fail_timeout=10s`). The client
  never noticed." The recorded run is in `04_evidence/failures/F3_one_backend_down/` (B stopped, then A stopped).

## Backup: the other failure demos (evidence in 04_evidence/failures)

| Demo | Break | Observation | Layer |
|---|---|---|---|
| F1 | mac_vachan's DNS -> 192.0.2.53 | dig times out, curl can't resolve, **ping and nc to 10.7.19.193:443 work** | DNS vs IP connectivity |
| F2 | app record -> 10.7.1.136 | dig "succeeds" with the wrong IP; curl: *connection refused* at 10.7.1.136:443 | DNS is a directory, not a connection |
| F3 | Backend B stopped (and A) | 200s continue from the other backend | LB failover (application) |
| F4 | both backends stopped | TLS handshake still completes at the edge, then **502 Bad Gateway** | where the edge ends and the backends begin |
| F5 | `https://app.subspace-67.test:8444` | *connection refused* (SYN -> RST) while ping and port 443 work | ports vs IP addresses |

Troubleshooting order for a faculty-injected fault (Phase 2 preview): **DNS** (`dig`) -> **IP** (`ping`) ->
**TCP port** (`nc -vz host 443`) -> **TLS** (`curl -v` / `openssl s_client`) -> **HTTP** (status, headers, logs).
