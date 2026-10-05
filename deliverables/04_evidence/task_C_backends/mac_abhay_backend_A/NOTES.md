# Task C: Backend A (mac_abhay, port 3001)

**What it shows**
| File | Proof |
|---|---|
| 00_backend_code_identical.txt | `shasum -a 256 -c SHA256SUMS`: backend.py and supervisor.py are byte-identical to mac_vachan's published copies (both backends run the same code) |
| 01_lsof_listen_3001.txt | `lsof ... -sTCP:LISTEN` -> `TCP *:3001 (LISTEN)`: bound on **all interfaces** (0.0.0.0), so other Macs can connect; netstat shows `*.3001 LISTEN` |
| 02-06_direct_*.txt | direct requests to 10.7.1.136:3001: `/` banner, `/api/status` (`Cache-Control: no-store`), HEAD (`curl -I`), `/api/cache-demo` (ETag + 304 on If-None-Match), unknown path -> 404; **every** response has `X-Backend: A` (also the 304 and the 404) |
| 07_supervisor_and_processes.txt | supervisor.py (PPID 1, started with nohup) is the parent of backend.py; it follows mac_vachan's control.json |
| 08_via_edge_requests.txt | the same endpoints through the edge `https://app.subspace-67.test/...`: `x-backend` is A or B depending on nginx's round robin |
| 09_backend_A_log_edge_requests.txt | Backend A's own log for those requests: **every** TCP peer is `client=10.7.19.193:<port>` = **mac_aanya (the edge)**; the real client appears only in `xff=` (X-Forwarded-For, added by nginx): `xff=10.7.1.136` = me, `xff=10.7.23.136` = mac_vachan testing at the same time |
| 10_established_connections_3001.txt | `netstat`: ESTABLISHED TCP connections `10.7.1.136.3001 <-> 10.7.19.193.<ephemeral>`: nginx keeps reusable (keep-alive) upstream connections to Backend A |
| 11_supervisor_during_failures.txt | Backend A's supervisor during mac_vachan's failure demos (14:08:40-14:09:31): each `control.json says A=down` -> backend process stopped and **port 3001 really closed** (`connection refused` for nginx) within 13-23 ms; each `A=up` -> restarted and listening within 0.11-0.64 s. Also a live example of the **keep-state rule**: during a 14 s Wi-Fi blip (14:09:05-14:09:19) control.json could not be fetched, the supervisor logged `cannot read control.json ... keeping current state`, left Backend A running, and resumed when the bus was reachable again |

**Which layer**: transport (TCP socket 3001, listening vs established, peer IP:port) and application (HTTP headers
`X-Backend`, `X-Forwarded-For`, `Cache-Control`, `ETag`).

**Why**: this proves the reverse proxy really sits in the middle. The client's TCP connection ends at nginx on mac_aanya;
nginx opens its **own** TCP connection to the backend. So the backend's TCP peer is always the edge's IP, never the
client's. That's why nginx adds `X-Forwarded-For`, so the backend can still learn who the original client was.
The six requests in file 08 are not strictly A/B alternating because mac_vachan's test requests (xff=10.7.23.136)
went through the same round robin at the same moment. Round robin is global over all clients (strict alternation
from a single client is shown in task_D).
