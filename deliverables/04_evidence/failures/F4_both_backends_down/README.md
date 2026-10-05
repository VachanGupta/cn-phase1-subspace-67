# F4 · Both backends stopped

**Run:** 2026-09-30 14:09:21-14:09:46 IST, from mac_vachan as the client.
**Break:** `control.json` A -> down and B -> down. Both ports were really closed: `nc -vz 10.7.1.136 3001` and
`nc -vz 10.7.23.136 3002` -> `Connection refused`.

## Observation
| Check | Result |
|---|---|
| `curl -v https://app.subspace-67.test/api/status` | `Connected to app.subspace-67.test (10.7.19.193) port 443`, full **TLS 1.3 handshake**, `ALPN: server accepted h2`, `subject: CN=app.subspace-67.test`, `issuer: CN=subspace_67 Local Root CA`, **`SSL certificate verify ok`**, then **`HTTP/2 502`** with `server: nginx` and the body `<h1>502 Bad Gateway</h1>` |
| same request with Homebrew curl + `SSLKEYLOGFILE` | `http_version=2 status=502 ssl_verify_result=0 tcp_connect=0.14s tls_done=0.17s total=0.19s` |
| capture `F4_502_after_tls.pcapng` (en0, host 10.7.19.193, port 443) | stream 0 and stream 1: SYN, SYN-ACK (frames 1-2, 35-36), ClientHello with SNI `app.subspace-67.test` (4, 40), ServerHello (7, 42), encrypted records, FIN. Decrypted with `F4_tls_session_keys.log`: **frame 48 `GET /api/status`**, **frame 54 `:status 502`, `server: nginx`** |

**Edge-side proof** (mac_aanya, `../edge_view_mac_aanya/edge_logs_failure_demos.txt`):
```
[error] ... connect() failed (61: Connection refused) ... upstream: "http://10.7.23.136:3002/api/status"
[error] ... connect() failed (61: Connection refused) ... upstream: "http://10.7.1.136:3001/api/status"
14:09:28 ... status=502 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 502 request_time=2.028
[error] ... no live upstreams while connecting to upstream ...        (14:09:29: both now marked down -> instant 502)
```
The first request tried both backends (about 1 s per refused connect, because of Wi-Fi queueing on the path to
mac_vachan, still under the 2 s `proxy_connect_timeout`). The next request got an immediate 502 because both
upstreams were inside their 10 s `fail_timeout`.

After restoring both: ports open again, and after nginx's 10 s fail_timeout the rotation is back (healthy at 14:09:46).

## Layer and why
**This shows where the edge ends and the backends begin.** DNS worked (the name resolved to the edge), TCP
worked (handshake with the edge), and TLS worked (the edge holds the certificate and key and terminates TLS),
so the client's secure channel to the edge was fine. Only **behind** the edge did everything fail: nginx's
connects to both upstreams were refused, so nginx generated the error response itself, **502 Bad Gateway**
("I am a gateway, and the servers behind me gave me no valid response"). A 502 from `server: nginx` after a
successful handshake points the diagnosis at the upstreams, not at DNS, TCP or TLS.

Files: `commands_output.txt`, `F4_502_after_tls.pcapng`, `F4_502_after_tls_tshark.txt` (including the
decrypted HTTP/2 frames), `F4_tls_session_keys.log` (in the deliverables copy: the per-session secrets of those
test connections only, not a private key; load it in Wireshark via Preferences > Protocols > TLS >
(Pre)-Master-Secret log filename).
