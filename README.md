# CN Phase 1 - Private Network Service Platform

**Team:** subspace_67 · **Infrastructure:** Type 2 (3 Macs with combined roles) · **Domain:** `app.subspace-67.test`

A private service platform built from scratch on three macOS laptops on one Wi-Fi LAN:
a client resolves a private domain through our own DNS server, connects over HTTPS to our
nginx edge, and is served by one of two backends through a round-robin load balancer.

## Team members

| Enrolment no. | Name | Machine | Project role |
|---|---|---|---|
| TODO | Vachan Gupta | mac_vachan | DNS server (dnsmasq), Backend B, test client |
| TODO | Aanya | mac_aanya | Edge reverse proxy, load balancer, TLS termination, local CA |
| TODO | Abhay Malik | mac_abhay | Backend A, main test client (packet captures) |

## Topology

| Mac | Role | IPv4 | Interface | Services |
|---|---|---|---|---|
| mac_vachan | DNS + Backend B + client | 10.7.23.136/19 | en0 | dnsmasq 53/udp+tcp, Backend B 3002/tcp |
| mac_aanya | Edge / LB / TLS | 10.7.19.193/19 | en0 | nginx 443/tcp (HTTP/2), 80 -> 301 https |
| mac_abhay | Backend A + client | 10.7.1.136/19 | en0 | Backend A 3001/tcp |

Request flow: `client -> dnsmasq (mac_vachan:53) -> nginx (mac_aanya:443) -> Backend A (3001) or B (3002)`

Roles are combined because we are a team of three; the brief permits this. Each role remains a
separate service on its own port, reached over the real LAN.

## How to run the backends

Backends are a single Python file, `deliverables/03_backend_source/backend.py`, started with a
supervisor that restarts them if they exit.

```bash
# Backend A - on mac_abhay
nohup python3 backend/supervisor.py --id A --port 3001 \
      --control-url http://$VACHAN_IP:8099/control.json > logs/backend_A.log 2>&1 < /dev/null &

# Backend B - on mac_vachan
nohup python3 backend/supervisor.py --id B --port 3002 \
      --control-url http://$VACHAN_IP:8099/control.json > logs/backend_B.log 2>&1 < /dev/null &
```

`VACHAN_IP` is mac_vachan's current LAN IP. `supervisor.py` keeps `backend.py` up and applies the
start/stop state in `control.json`, which is how the failure demos stop a backend cleanly.
Both backends run byte-identical code - verify with `shasum -a 256 -c SHA256SUMS`.

Check a backend is listening on the LAN, not just loopback:

```bash
lsof -nP -iTCP:3001 -sTCP:LISTEN        # must show *:3001
curl -si http://<own LAN IP>:3001/api/status
```

Both bind `0.0.0.0`, not `127.0.0.1`, so the edge on another Mac can reach them.

Endpoints: `GET /` (service banner), `GET /api/status` (`{"backend":"A","status":"ok"}`, `no-store`),
`GET /api/cache-demo` (`Cache-Control: max-age=60` + `ETag`, for the 304 demo).
Every response carries `X-Backend: A` or `X-Backend: B`.

Full launch notes: `deliverables/02_configs/backend/backend_launch.md`

## Bringing the whole system up

```bash
./start.sh                 # on all three Macs: rediscovers IPs, regenerates DNS config
./stop.sh                  # stops our processes
sudo ./restore_network.sh  # undoes every system change (DNS, CA, dnsmasq service)
```

## Repository layout

| Path | Contents |
|---|---|
| `deliverables/01_architecture/` | Topology diagram, request-flow diagram, IP/service table |
| `deliverables/02_configs/` | dnsmasq.conf, nginx config, TLS cert setup, per-machine scripts |
| `deliverables/03_backend_source/` | Backend source, supervisor, helpers, SHA256SUMS |
| `deliverables/04_evidence/` | Task A-G evidence and all five failure demonstrations |
| `deliverables/05_demo/` | Demo-day run sheet |
| `deliverables/06_viva/` | Viva preparation notes |
| `bin/` | Helper scripts: discovery, DNS config generation, evidence collection, diagram rendering |

Start at `deliverables/INDEX.md` for a guided index of every piece of evidence.

The live working copies of the dnsmasq, nginx, TLS and backend files are published in their graded
locations under `deliverables/02_configs/` and `deliverables/03_backend_source/`.

## Evidence map (Phase 1 tasks)

| Task | Evidence |
|---|---|
| A - Private LAN | `04_evidence/task_A_lan/` - ifconfig, ping matrix, ARP |
| B - Private DNS | `04_evidence/task_B_dns/` - dig from clients, NXDOMAIN at 8.8.8.8, dnsmasq logs |
| C - Backends | `04_evidence/task_C_backends/` - direct port checks on 3001/3002 |
| D - Reverse proxy + LB | `04_evidence/task_D_load_balancing/` - alternating X-Backend |
| E - HTTPS / TLS | `04_evidence/task_E_tls/` - cert chain, curl -v without -k, handshake |
| F - HTTP caching | `04_evidence/task_F_caching/` - Cache-Control, ETag, 304 via If-None-Match and If-Modified-Since |
| G - Protocol flow | `04_evidence/task_G_protocol_flow/` - tshark DNS, TCP handshake, TLS (1.2 and 1.3) |
| 6.3 - Failures | `04_evidence/failures/` - F1 wrong DNS, F2 wrong IP, F3 one backend, F4 both backends, F5 wrong port |
