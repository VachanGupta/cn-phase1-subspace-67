# F1 · Wrong DNS server configured on a client

**Run:** 2026-09-30 14:07:27-14:07:56 IST on mac_vachan (10.7.23.136), as the client.
**Break:** this Mac's resolver was pointed at `192.0.2.53` (TEST-NET-1, a documentation address where no DNS
server exists): `networksetup -setdnsservers Wi-Fi 192.0.2.53` + cache flush.

## Observation
| Check | Result |
|---|---|
| `scutil --dns` | resolver #1 = 192.0.2.53 |
| `dig app.subspace-67.test +time=2 +tries=2` | `;; connection timed out; no servers could be reached` |
| `curl -v https://app.subspace-67.test/api/status` | `curl: (28) Resolving timed out after 10002 milliseconds`: never got as far as TCP |
| `ping -c 3 10.7.19.193` | 3/3 replies, TTL 64 |
| `nc -vz 10.7.19.193 443` | `Connection to 10.7.19.193 port 443 [tcp/https] succeeded!` |
| same HTTPS request with the edge IP given by hand (`--resolve`, certificate still verified) | `200`, JSON from Backend B |
| capture `F1_queries_to_nowhere.pcapng` | **143 DNS queries to 192.0.2.53, 0 responses**. `app.subspace-67.test` asked at frames 12 and 42 (dig, 2 s apart), then 64, 65, 90, 126 (curl's resolver retrying with backoff). ICMP echo request/reply to the edge (frames 135-140) are answered. |

After restoring the DNS server to 10.7.23.136: `dig` -> 10.7.19.193, HTTPS 200, healthy (B A B A B A).

## Layer and why
**DNS (application-level name lookup) vs IP connectivity (network layer).** Name resolution failed completely,
yet the path to the edge was fine at L3 (ping) and L4 (TCP handshake to 443), and the whole HTTPS exchange
worked once the IP was supplied without DNS. DNS is a separate service that only turns names into addresses. If
the client asks a server that doesn't exist, it can't get an address, even though the network, the edge and
the backends are healthy. **Diagnosis rule:** when `dig` fails but `ping <ip>` works, look at the resolver
configuration (`scutil --dns`), not at the network.

Files: `commands_output.txt` (every command and its full output), `F1_queries_to_nowhere.pcapng` +
`F1_queries_to_nowhere_tshark.txt`.
