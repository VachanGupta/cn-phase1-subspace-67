# F5 · Wrong destination port on the client

**Run:** 2026-09-30 14:09:46-14:09:55 IST, from mac_vachan. Nothing was changed on any server.
**Break:** the client asked for `https://app.subspace-67.test:8444`, a port where nothing listens on the edge.

## Observation
| Check | Result |
|---|---|
| `curl -v https://app.subspace-67.test:8444/api/status` | the name resolves to `10.7.19.193`, then `connect to 10.7.19.193 port 8444 ... failed: Connection refused` |
| `ping -c 3 10.7.19.193` | 3/3 replies: the host is up |
| `nc -vz 10.7.19.193 443` | `succeeded!`: the right port works |
| `nc -vz 10.7.19.193 8444` | `Connection refused` |
| capture `F5_syn_rst.pcapng` | port 8444: frame 1 **SYN** 10.7.23.136:49761 -> 10.7.19.193:8444 (seq 1861762739); frame 2 **RST,ACK** (ack 1861762740), repeated at frames 3/4 by curl's retry. Port 443: frames 11-13 **SYN -> SYN,ACK -> ACK** (a complete handshake), then FIN (nc closes). |

## Layer and why
**Transport layer: IP addresses and ports are separate identifiers.** The IP address (network layer) got the
packets to the right machine: it answered ping and completed a handshake on 443. The port (transport layer)
names the *service* on that machine. On 8444 no socket is listening, so the edge's TCP stack answers the SYN
with a **RST**, which the client reports as "connection refused". A refusal (RST) proves the host is reachable
and the service is missing; a *timeout* would instead suggest a firewall silently dropping packets or a
dead host.

Files: `commands_output.txt`, `F5_syn_rst.pcapng` + `F5_syn_rst_tshark.txt`.
