# F3 · One backend is stopped (and the brief's demo step 8: stop Mac 3's Backend A)

**Run:** 2026-09-30 14:08:14-14:09:21 IST, from mac_vachan as the client.
**Break:** `control.json` B -> down. Backend B's supervisor really stopped the process
(`backend B is DOWN: pid 50908 gone, port 3002 closed (connection refused)`), confirmed by
`nc -vz 10.7.23.136 3002` -> refused. Then the same with **A -> down** (mac_abhay's supervisor closed :3001),
which is exactly Section 8 step 8 of the brief.

## Observation
| Phase | Client result (8 requests each, `bin/lb_probe.sh 8`) |
|---|---|
| B down | **8 x HTTP 200, all `X-Backend: A`** |
| B back up, after 11 s | 200s; A A, then B A B A B A (rotation resumes) |
| A down (demo step 8) | **8 x HTTP 200, all `X-Backend: B`** |
| A back up | 8 x `HTTP=000` during a ~14:09:03-14:09:19 **Wi-Fi drop on this Mac** (no TCP at all; the team monitor lost all 3 Macs at the same moment, and mac_abhay saw the same window). This was not nginx. The health check at 14:09:21 passed, and the re-run at 14:11:29 (appended at the end of `commands_output.txt`) shows 8 x 200, B A B A B A B A. |

mac_abhay's supervisor log matches the run: A down at 14:08:41.9, up at 14:08:51.4. During the Wi-Fi drop it
logged "cannot read control.json ... keeping current state" and recovered at 14:09:18: the keep-state rule working.
Backend A's side: `../../task_C_backends/mac_abhay_backend_A/11_supervisor_during_failures.txt` (port 3001 closed
13-23 ms after A=down and listened again 0.11-0.64 s after A=up).

## Layer and why
**Application-layer load balancing with failover.** When nginx's connect to the stopped backend is refused
(TCP RST), `proxy_next_upstream error timeout http_502 http_503` makes it retry the **same client request** on
the other backend, so the client still gets 200. `max_fails=1 fail_timeout=10s` then takes the dead backend out
of rotation for 10 s (shared by all workers via `zone`), which is why the probe right after a restore still
shows only the survivor for a moment. The client never knew: it only ever talks to the edge. That is the
point of a load balancer (like an AWS ALB target group with health checks).

## Edge-side proof (mac_aanya's nginx logs, `../edge_view_mac_aanya/edge_logs_failure_demos.txt`)
```
14:08:17 ... status=200 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 200 x_backend=A request_time=1.072
[error] ... connect() failed (61: Connection refused) while connecting to upstream ... upstream: "http://10.7.23.136:3002/..."
14:08:46 ... status=200 upstream=10.7.1.136:3001, 10.7.23.136:3002 upstream_status=502, 200 x_backend=B request_time=0.549
```
One client request, two upstream attempts: the first to the stopped backend (connection refused, which nginx
logs as upstream status 502), then a retry on the other backend (200). That is failover inside a single
request. The `499` at 14:09:08 is the client giving up during the Wi-Fi drop (nginx's code for "client closed
request"); no backend was marked down for it.

Files: `commands_output.txt` (including the re-run note), `../edge_view_mac_aanya/` (edge logs + annotated notes).
