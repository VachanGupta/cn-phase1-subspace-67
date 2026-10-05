# Task G explained: one HTTPS request, packet by packet, layer by layer

Captured on **mac_abhay** (the client, 10.7.1.136) on the Wi-Fi interface **en0**. Both the DNS query (to mac_vachan)
and the HTTPS connection (to mac_aanya) really cross the LAN from here.

| Who | IP | MAC seen in the frames | Role in the capture |
|---|---|---|---|
| mac_abhay (me) | 10.7.1.136 | 8e:f6:fb:7b:0a:59 (macOS private Wi-Fi address) | client, and Backend A on :3001 |
| mac_vachan | 10.7.23.136 | 6a:e1:56:86:a2:23 | DNS server (dnsmasq, 53/udp) |
| mac_aanya | 10.7.19.193 | d6:d2:39:70:e5:9a | edge: nginx on 443 (TLS termination + round robin) |

**How each capture was made** (`sudo/02_capture_task_G.sh`, one root password; commands and full output in `*_commands.txt`):
1. flush the DNS cache: `dscacheutil -flushcache; killall -HUP mDNSResponder`
2. `tcpdump -i en0 -P -n -s 0 -U -w <name>.pcapng 'port 53 or host 10.7.19.193'` (-P = pcapng)
3. `dig app.subspace-67.test`
4. `curl https://app.subspace-67.test/api/status`, with `--tls-max 1.2` for **task_G_tls12.pcapng** and `--tlsv1.3` for **task_G_tls13.pcapng**,
   with `SSLKEYLOGFILE` set so the captures can also be decrypted (bonus)
5. stop tcpdump. Text exports with packet numbers are in `task_G_tls12_exports/` and `task_G_tls13_exports/` (tshark 4.6.9).

---

## Part 1: task_G_tls12.pcapng (36 packets), the whole story in order

| # | time (s) | from -> to | what it is | layer that matters |
|---|---|---|---|---|
| 1 | 0.000 | 10.7.1.136:**54633** -> 10.7.23.136:**53** UDP | DNS query id 0x8773 `A? app.subspace-67.test` (from `dig`) | DNS over UDP |
| 2 | 0.256 | 10.7.23.136:53 -> 10.7.1.136:54633 UDP | DNS response 0x8773: **A 10.7.19.193**, TTL 60, flags AA+RA | DNS over UDP |
| 3 | 1.400 | 10.7.1.136:**52172** -> 10.7.23.136:53 UDP | DNS query id 0x0d0e: curl's own lookup (made by the system resolver mDNSResponder) | DNS over UDP |
| 4 | 1.465 | 10.7.23.136:53 -> 10.7.1.136:52172 UDP | answer A 10.7.19.193 | DNS over UDP |
| 5 | 1.466 | 10.7.1.136:**54389** -> 10.7.19.193:**443** | **SYN** seq=0 (raw 2650729791), MSS 1460, WS x64, SACK_PERM | TCP handshake 1/3 |
| 6 | 1.503 | 10.7.19.193:443 -> :54389 | **SYN-ACK** seq=0 (raw 2207460345) **ack=1** (raw 2650729792) | TCP handshake 2/3 |
| 7 | 1.503 | :54389 -> :443 | **ACK** seq=1 ack=1 (raw 2650729792 / 2207460346) | TCP handshake 3/3 |
| 8 | 1.508 | client -> edge | TLS **ClientHello**, 232 bytes, **SNI=app.subspace-67.test**, ALPN h2,http/1.1 | TLS |
| 10 | 1.558 | edge -> client | ACK=233 ("got your 232 bytes, next byte I expect is 233") | TCP |
| 11 | 1.558 | edge -> client | TLS **ServerHello**: TLS 1.2, cipher 0xc030 = ECDHE-RSA-AES256-GCM-SHA384, ALPN **h2** | TLS |
| 12 | 1.558 | edge -> client | **Certificate, ServerKeyExchange, ServerHelloDone** (clear text in 1.2) | TLS |
| 13 | 1.558 | client -> edge | ACK=2769 (1 + 1448 + 1320 bytes received) | TCP |
| 14 | 1.561 | client -> edge | **ClientKeyExchange, ChangeCipherSpec, Finished** ("Encrypted Handshake Message"), 93 bytes | TLS |
| 16 | 1.583 | edge -> client | **ChangeCipherSpec, Finished** (encrypted) | TLS |
| 17 | 1.583 | edge -> client | first **Application Data** (decrypted: HTTP/2 SETTINGS, WINDOW_UPDATE) | TLS / HTTP/2 |
| 19-20 | 1.584 | client -> edge | Application Data (decrypted: HTTP/2 preface, SETTINGS, **HEADERS stream 1: GET /api/status**) | TLS / HTTP/2 |
| 21 | 1.757 | client -> edge | **TCP Retransmission** of bytes 326-509 (no ACK yet after ~173 ms) | TCP reliability |
| 22 | 1.770 | edge -> client | ACK=509 (the original arrived; its ACK was just slow on Wi-Fi) | TCP |
| 25 | 1.789 | edge -> client | Dup ACK with **SACK 326-509**: "I received 326-509 twice" (a D-SACK, so the retransmission was unnecessary) | TCP reliability |
| 26 | 1.876 | edge -> client | Application Data (decrypted: **HEADERS 200 OK, x-backend: B**, DATA = the JSON) | TLS / HTTP/2 |
| 28-29 | 1.878 | client -> edge | GOAWAY, then TLS **close_notify** alert (Encrypted Alert) | TLS |
| 30-36 | 1.878-1.893 | both | **FIN** exchange (both FINs crossed on the air, so Wireshark marks some as retransmission/dup ACK) | TCP teardown |

(Frame 9 is a pure window update. The whole exchange, SYN to last packet, took 0.43 s.)

This request happened to be load-balanced to **Backend B** (mac_vachan), so its edge->backend hop is not visible from
my Mac. In the TLS 1.3 capture the request went to **Backend A** (this Mac) and that hop is captured (Part 4).

---

## Part 2: one packet, layer by layer (reading Wireshark's detail pane top to bottom)

**Frame 1, the DNS query (91 bytes on the wire)**
- **Ethernet II** (14 bytes): src `8e:f6:fb:7b:0a:59` (me) -> dst `6a:e1:56:86:a2:23` (**mac_vachan's own MAC**, because it is
  on my subnet 10.7.0.0/19, so no router is involved; ARP supplied this MAC). EtherType 0x0800 = IPv4.
  (macOS hands Wi-Fi frames to capture tools as Ethernet II; the 802.11 radio header is only visible in monitor mode.)
- **IPv4** (20 bytes): 10.7.1.136 -> 10.7.23.136, TTL 64, **protocol 17 = UDP**.
- **UDP** (8 bytes): src port **54633** (ephemeral, picked by the OS for dig) -> dst port **53** (DNS), length 57.
- **DNS** (49 bytes): transaction id 0x8773, flags RD (recursion desired), 1 question `app.subspace-67.test IN A`,
  1 additional record (EDNS0 OPT: "I can take 1232-byte UDP answers").
- Check: 14 + 20 + 57 = 91 bytes. There's no handshake, no sequence numbers: one datagram out, one back.

**Frame 2, the DNS response**: the same id 0x8773 and the ports swapped (53 -> 54633). That is how the client matches the answer
to its question. Flags **AA** (authoritative: dnsmasq owns subspace-67.test) and **RA** (recursion available). Answer:
`app.subspace-67.test A 10.7.19.193, TTL 60`. That's the edge's IP, **not** a backend's.

**Frame 5, the TCP SYN (78 bytes)**
- **Ethernet II**: 8e:f6:fb:7b:0a:59 -> `d6:d2:39:70:e5:9a` (**mac_aanya's MAC**), EtherType IPv4.
- **IPv4**: 10.7.1.136 -> **10.7.19.193** (exactly the address DNS returned), TTL 64, **protocol 6 = TCP**.
- **TCP** (44 bytes = 20 header + 24 options): **54389 -> 443**, flags SYN (+ECE/CWR = asking to use ECN),
  seq = ISN 2650729791, window 65535, options **MSS 1460** (1500 MTU - 40), **window scale 6** (x64), **SACK permitted**, timestamps.
- Check: 14 + 20 + 44 = 78 bytes.

**Frames 8 onward**: the same Ethernet/IP/TCP wrapping, now with a **TLS record** in the TCP payload. In frame 12 you can
expand *Transport Layer Security -> Handshake Protocol: Certificate* and read the certificates. Once encryption starts, the
payload is just "Application Data" (the HTTP is inside).

---

## Part 3: TCP in plain language (sequence numbers, ACKs, reliability)

**Three-way handshake** (`task_G_tls12_exports/04_tcp_handshake.txt`, relative and raw numbers side by side):

| # | direction | flags | seq (raw) | ack (raw) | meaning |
|---|---|---|---|---|---|
| 5 | client -> edge | SYN | 2650729791 | 0 | "Let's talk; I'll number my bytes starting after 2650729791" |
| 6 | edge -> client | SYN, ACK | 2207460345 | 2650729792 | "OK, and mine start after 2207460345; I expect your byte 2650729792 next" |
| 7 | client -> edge | ACK | 2650729792 | 2207460346 | "Got it; I expect your byte 2207460346 next" |

- Each side picks a **random initial sequence number (ISN)**. Wireshark shows them as **relative** 0 to make them readable;
  the raw values are what really travel.
- A SYN carries no data but **consumes one sequence number**, so the answer is ISN+1 (2650729791 -> ack 2650729792).
- **ACK = the next byte I expect**, i.e. "I have everything before this". Frame 8 sends 232 bytes starting at seq 1, so
  frame 10 answers `ack=233`. The server's flight of 1448 + 1320 bytes is answered with `ack=2769` (frame 13).

**Reliability, seen live in this capture** (`10_tcp_stream_seq_ack_all.txt`):
- Frames 19+20 carried bytes 326-509. No ACK came back within ~173 ms, so the client **retransmitted** them (frame 21):
  TCP keeps every byte until it is acknowledged.
- The ACK for the original (frame 22, `ack=509`) arrived a moment later; then the server sent a **duplicate ACK with a SACK block
  326-509** (frame 25): "I got 326-509 twice". That is a D-SACK, telling the sender its retransmission was spurious. No data
  was lost or duplicated for the application: TCP's sequence numbers let the receiver drop the extra copy.
- The same happens in the TLS 1.3 capture (frames 15/17, SACK 2542-3990) and on the nginx->Backend A hop (frame 38,
  "spurious retransmission"). That's normal on a busy Wi-Fi with variable delay.
- **Flow control**: every segment carries a window (e.g. `Win=131776` = 2059 x 64 after scaling): how much more the receiver
  can buffer.
- **Teardown** (30-36): the client sends FIN (seq 595) and the server FIN (seq 3188). **A FIN also consumes one sequence number**,
  so the final ACKs are 596 and 3189. The two FINs crossed in flight, so Wireshark labels some copies "retransmission".

**UDP vs TCP here**: the DNS exchange is 2 packets with no setup and no ACKs (if lost, the resolver itself would retry).
The HTTPS exchange needs 3 packets of handshake before any data, and every byte is numbered and acknowledged.

---

## Part 4: TLS 1.2 vs TLS 1.3, and why the certificate disappears in 1.3

**TLS 1.2 (task_G_tls12.pcapng, `06_tls_records_encrypted_view.txt`, `08_tls_serverhello_certificate_keyexchange.txt`)**
1. **ClientHello** (8): record version 0x0301 (compatibility), offers TLS 1.2, cipher list, random, **SNI = app.subspace-67.test**
   (tells nginx which certificate to present; it has to be clear text because no keys exist yet), **ALPN h2, http/1.1**.
2. **ServerHello** (11): picks TLS 1.2, `0xc030 = TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`, ALPN **h2**.
3. **Certificate** (11-12, spans two TCP segments): **readable in 1.2**. Two certificates: the leaf (1110 bytes,
   `CN=app.subspace-67.test`, SAN `app.subspace-67.test, api.subspace-67.test`) and our CA
   (1217 bytes, `CN=subspace_67 Local Root CA`, whose Name Constraints extension permits only `subspace-67.test`).
4. **ServerKeyExchange** (12): the server's ephemeral **x25519** public key (32 bytes), **signed** with the certificate's
   private key (`rsa_pss_rsae_sha256`), proving the server owns the certificate.
5. **ServerHelloDone** (12).
6. **ClientKeyExchange** (14): the client's ephemeral x25519 public key (32 bytes). Now both sides compute the same
   shared secret by Diffie-Hellman; the secret itself never crosses the wire.
7. **ChangeCipherSpec + Finished** from the client (14), then from the server (16). Finished is the first encrypted message:
   a MAC over the whole handshake, so tampering with any earlier message would be detected.
8. **Application Data** (17 onward): the HTTP/2 conversation, encrypted with AES-256-GCM.
That's two round trips (ClientHello -> ServerHelloDone, ClientKeyExchange -> Finished) before the first request.

**TLS 1.3 (task_G_tls13.pcapng, 52 packets)**
| # | encrypted view (what anyone on the Wi-Fi sees) | decrypted with the key log |
|---|---|---|
| 8-9 | ClientHello (SNI=app.subspace-67.test), **1487 bytes, split over 2 TCP segments**: its key_share carries a hybrid post-quantum **X25519MLKEM768** key (1216 bytes) + a plain x25519 key (32 bytes); supported_versions includes 0x0304 = TLS 1.3 | same |
| 12 | Server Hello, Change Cipher Spec, **Application Data** | ServerHello (TLS 1.3, `0x1302 TLS_AES_256_GCM_SHA384`, key_share X25519MLKEM768, 1120 bytes), CCS, **EncryptedExtensions** |
| 14 | **Application Data x3** | **Certificate, CertificateVerify, Finished** |
| 19 | Change Cipher Spec, Application Data | client **Finished** |
| 20 | Application Data | HTTP/2 preface, SETTINGS, **HEADERS[1]: GET /api/status** |
| 22-23 | Application Data | 2 x **NewSessionTicket** (for fast resumption later) |
| 44 | Application Data | **HEADERS[1]: 200 OK, x-backend: A, cache-control: no-store**, DATA (JSON) |
| 46-47 | Application Data | GOAWAY, close_notify alert |

*Why is the Certificate encrypted in TLS 1.3?* The client already sends its key share in the ClientHello and the server
answers with its own in the ServerHello, so **right after ServerHello both sides can derive handshake keys**. TLS 1.3
uses them immediately: everything after ServerHello, including the certificate, is encrypted (record type
"application_data", opaque type 23; the real type hides inside). An eavesdropper can no longer read which certificate
the server presented. They still see the SNI in the ClientHello. The `ChangeCipherSpec` in 1.3 is a dummy kept only so
old middleboxes don't panic. TLS 1.3 also needs only **one round trip** before the request (the client's request
already goes out in frame 20, right after its Finished). That's why we captured TLS 1.2 separately: to *see* the
certificate on the wire.

**Decrypting (bonus)**: curl wrote its session secrets to `task_G_tls12_sslkeylog.txt` (TLS 1.2: one `CLIENT_RANDOM`
line) and `task_G_tls13_sslkeylog.txt` (TLS 1.3: handshake + traffic secrets). In Wireshark: *Settings -> Protocols -> TLS
-> (Pre)-Master-Secret log filename* -> choose the file, and the encrypted records turn into the HTTP/2 frames listed
above (`12_decrypted_tls_records.txt`, `13_decrypted_http.txt`). These files unlock only these captured sessions;
they contain no private key and can't be used to impersonate the server.

---

## Part 5: the reverse-proxy hop (TLS 1.3 capture, request answered by Backend A = this Mac)

`task_G_tls13_exports/11_edge_to_backendA_hop.txt`:

| # | from -> to | what |
|---|---|---|
| 25 | **10.7.19.193:52365 -> 10.7.1.136:3001** | nginx opens its **own** TCP connection to Backend A (SYN), ~16 ms after my encrypted request (frame 20) left my Mac |
| 29, 33 | 3001 -> 52365, 52365 -> 3001 | SYN-ACK, ACK (a second 3-way handshake) |
| 34 | 52365 -> 3001 | `GET /api/status HTTP/1.1` in **plain text** (172 bytes; inside the LAN the edge talks plain HTTP/1.1) |
| 37, 41 | 3001 -> 52365 | `HTTP/1.1 200 OK` + the JSON body (`"backend": "A"`) |
| 44 | edge -> client | nginx re-encrypts the answer into my TLS/HTTP/2 connection |

So one user request = **two TCP connections**: client:54103 -> edge:443 (TLS, HTTP/2) and edge:52365 -> backend:3001 (plain
HTTP/1.1). Backend A's log shows the TCP peer `10.7.19.193:52365`, never the client's address (see task_C). The client
never knew 3001 or my role as a backend existed.

---

## Part 6: ports and socket pairs (`09_port_table.txt`)

| Flow | client side (ephemeral) | server side (well-known/fixed) | protocol | who opened it |
|---|---|---|---|---|
| dig's DNS lookup (tls12 / tls13) | 10.7.1.136:54633 / :61173 | 10.7.23.136:**53** | UDP | dig |
| curl's DNS lookup (tls12 / tls13) | 10.7.1.136:52172 / :53824 | 10.7.23.136:**53** | UDP | mDNSResponder (for curl) |
| HTTPS (tls12 / tls13) | 10.7.1.136:54389 / :54103 | 10.7.19.193:**443** | TCP | curl |
| proxy hop (tls13) | 10.7.19.193:52365 | 10.7.1.136:**3001** | TCP | nginx |

Every connection is identified by its **socket pair** (src IP, src port, dst IP, dst port) plus the protocol. The server
ports are fixed (53, 443, 3001); the client ports are random **ephemeral** ports (49152-65535 on macOS), new for each
socket. That's how many conversations can run at once without mixing.

**Which process sent what** (bonus, `14_process_per_packet_pktap.txt`, Apple's pktap interface): the DNS answer for
dig's query was delivered to **`dig:21076`**. The answer for curl's lookup went to **`mDNSResponder:417`** with
*effective process* **`curl:21082`**. curl doesn't do DNS itself: it asks the system resolver daemon, which has a
cache (that's why we flush it first). dig bypasses that cache and asks the server directly.

---

## Part 7: other packets you may notice, and a failed first attempt

- `attempt1_blocked_task_G_tls12.pcapng`: our first TLS 1.2 capture. DNS worked (packets 29-32), but **no SYN** ever went
  to 443: macOS **Local Network privacy** blocked Apple's `/usr/bin/curl` when it was launched from the root capture script
  (curl: "Immediate connect fail ... No route to host"). Packets 33-36 show my Mac was talking to 10.7.19.193 at that
  very moment, so the network was fine. The block was inside macOS, before any packet was sent. Retaken with Homebrew curl.
  (Packets 1-28 there are mac_aanya's team-bus poller fetching my info.json on port 8099, before she paused it.)
- `task_G_tls13.pcapng` frame 52: an ARP broadcast from another host (10.7.19.97) asking "who has 10.7.19.193?". It
  matched the filter `host 10.7.19.193`.
- Frame 51 (TLS 1.3): nginx ends the connection with a RST after both FINs. That is a normal abortive close by the server
  and happens after all data was delivered.

## How to look at this yourself in Wireshark
Open a `.pcapng`, then try these display filters: `dns` · `tcp.flags.syn == 1` · `tcp.stream == 0` · `tls.handshake` ·
`tls.handshake.type == 11` (Certificate, 1.2 only) · `tcp.port == 3001` · `tcp.analysis.flags` (retransmissions, dup ACKs).
*Statistics -> Conversations* gives the port table; *Statistics -> Flow Graph* draws the handshakes as arrows;
*right-click -> Follow -> TCP Stream* shows one connection. With the key log loaded, try `http2`.
