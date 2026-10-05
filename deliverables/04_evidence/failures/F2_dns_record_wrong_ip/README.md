# F2 · The DNS record points to the wrong IP address

**Run:** 2026-09-30 14:07:56-14:08:14 IST on mac_vachan (DNS server + client).
**Break:** `app.subspace-67.test` was pointed at **10.7.1.136** (mac_abhay: a live host, but nothing listens on
443 there): `bin/gen_dnsmasq.py --app-ip 10.7.1.136`, then a dnsmasq restart and a cache flush.

## Observation
| Check | Result |
|---|---|
| `dig app.subspace-67.test` | `status: NOERROR`, flags `qr aa rd ra`, `app.subspace-67.test. 60 IN A 10.7.1.136`, `SERVER: 10.7.23.136#53`: a perfectly "successful" lookup |
| `curl -v https://app.subspace-67.test/api/status` | `Trying 10.7.1.136:443...` -> `connect to 10.7.1.136 port 443 ... failed: Connection refused` |
| `ping -c 2 10.7.1.136` | 2/2 replies: the wrong host is alive |
| `nc -vz 10.7.1.136 443` | `Connection refused` |
| capture `F2_wrong_record.pcapng` | frame 20: SYN 10.7.23.136:49346 -> 10.7.1.136:443; frame 26: **RST,ACK** from 10.7.1.136 (retry at frames 27/28). The DNS answer itself is not on en0, because this Mac is its own DNS server and that query goes over loopback; the `dig` output shows it. |

After restoring the record: `dig` -> 10.7.19.193, HTTPS 200, healthy.

## Layer and why
**DNS is a directory, not a connection.** The DNS server answered exactly what it was configured to say, with
authority and a 60 s TTL. It has no idea whether that IP runs our service. The client then did what DNS told
it: opened TCP to 10.7.1.136:443. That host's kernel refused the connection (RST) because no process listens on
443. The failure shows up at the transport layer, but its cause is a wrong DNS record. **Diagnosis rule:**
compare the IP `dig` returns with the IP you expect before debugging TCP or TLS. The 60 s TTL also means any
client that looked up the name during the fault keeps the wrong answer for up to a minute (or until its cache
is flushed).

Files: `commands_output.txt`, `F2_wrong_record.pcapng` + `F2_wrong_record_tshark.txt`.
