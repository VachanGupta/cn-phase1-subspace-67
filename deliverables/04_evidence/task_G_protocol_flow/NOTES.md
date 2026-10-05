# Task G: the main packet capture (DNS + TCP + TLS + HTTP on the wire)

**Full packet-by-packet walkthrough: `task_G_explained.md`.**

| File | What it is |
|---|---|
| task_G_tls12.pcapng | flush DNS cache -> `dig app.subspace-67.test` -> `curl --tls-max 1.2 https://app.subspace-67.test/api/status` (36 packets). The Certificate message is visible |
| task_G_tls13.pcapng | the same with `--tlsv1.3` (52 packets): Certificate encrypted after ServerHello; this request went to Backend A, so the nginx -> :3001 hop is included |
| task_G_tls1{2,3}_commands.txt | exact commands and full output of each capture run (tcpdump, dig, curl -v) |
| task_G_tls1{2,3}_sslkeylog.txt | TLS session secrets written by curl (SSLKEYLOGFILE), for decrypting in Wireshark (bonus). Not a private key |
| task_G_tls1{2,3}_pktap_process.pcapng | parallel capture on Apple's pktap interface: per-packet process name/PID (bonus) |
| task_G_tls1{2,3}_exports/ | tshark text exports with packet numbers: 00 capinfos, 01 all packets, 02-03 DNS, 04-05 TCP handshake (relative and raw seq/ack), 06-08 TLS handshake (ClientHello/SNI, ServerHello, Certificate, key exchange, CCS, Finished), 09 port table, 10 full seq/ack table, 11 edge -> Backend A hop, 12-13 decrypted TLS records / HTTP/2, 14 process per packet |
| attempt1_blocked_* | first TLS 1.2 attempt: DNS OK, but macOS Local Network privacy blocked /usr/bin/curl (no SYN sent). Kept as evidence of that gotcha |

**Which layers**: link (Ethernet II framing of Wi-Fi, MAC addresses), network (IPv4, TTL, protocol 6/17), transport
(UDP 53; TCP 443 and 3001: handshake, seq/ack, retransmission, SACK, FIN), and TLS + application (DNS, TLS 1.2/1.3, HTTP/2 and HTTP/1.1).

**Why here**: on mac_abhay both the DNS query (to mac_vachan) and the HTTPS connection (to mac_aanya) really cross the
Wi-Fi. The captures show the order of events: name lookup first (UDP, 2 packets), then a TCP connection to the
**answered IP**, then TLS authenticates the server and encrypts, and only then HTTP flows.

**Wireshark screenshots**: skipped. `CGPreflightScreenCaptureAccess()` reports that this Mac has not granted Screen Recording
to the capture tool, and granting it needs an app restart mid-run. The text exports above carry the same information.
On demo day: `open -a Wireshark share/evidence/mac_abhay/task_G/task_G_tls12.pcapng`, then type a display filter
(`dns`, `tcp.flags.syn == 1`, `tls.handshake`, `tcp.port == 3001`) and take screenshots with Cmd-Shift-4.
