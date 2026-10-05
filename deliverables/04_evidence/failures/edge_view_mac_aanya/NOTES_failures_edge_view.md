# Failure demos seen from the edge (mac_aanya nginx logs)

Source: `edge_logs_failure_demos.txt` (exact commands + full log lines). Demos were run by mac_vachan
on 2026-09-30 between 14:08 and 14:10 IST; all probe traffic came from mac_vachan (client=10.7.23.136).
Relevant nginx settings: `max_fails=1 fail_timeout=10s`, `proxy_connect_timeout 2s`,
`proxy_next_upstream error timeout http_502 http_503`, upstream `zone` shared by all workers.

## F3a: Backend B down (≈14:08:14.9 → ≈14:08:30): failover, client never notices
- `14:08:17 ... status=200 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 200 x_backend=A`
  → nginx picked B (its turn in the round robin), the TCP connect was **refused** (error log:
  `connect() failed (61: Connection refused) while connecting to upstream ... 10.7.23.136:3002`), so
  `proxy_next_upstream error` **retried the same request on A**, and the client got **200** from A.
  The "502" in `upstream_status` is nginx's internal verdict for the failed try; the client never saw it.
- error log: `upstream server temporarily disabled`: with `max_fails=1`, one failure takes B out of
  the pool for `fail_timeout=10s`.
- 14:08:17 → 14:08:20: every request goes **straight to A** (no more retries, since B is known to be down).
- 14:08:33 onward (B restored): the round robin is back to `A B A B`. That's nginx's *passive*
  health check (after 10 s it simply tries B again with real traffic).

## F3b: Backend A down (≈14:08:41.9 → 14:08:51.4): the mirror image
- `14:08:46 ... upstream=10.7.1.136:3001, 10.7.23.136:3002 upstream_status=502, 200 x_backend=B` + error
  log `Connection refused ... 10.7.1.136:3001` + `temporarily disabled`; then only B until A returns.

## The Wi-Fi blip (≈14:09:03 → 14:09:19)
- `14:09:08 ... status=499 upstream=10.7.23.136:3002 upstream_status=-`: **499 = the client closed the
  connection before nginx could answer** (nginx-specific code). The probe gave up while the backend
  exchange was stalled by the Wi-Fi outage. It's not a backend failure, and nginx did not mark B down.

## F4: both backends down (≈14:09:22 → 14:09:30.7): 502 Bad Gateway
- `14:09:28 ... status=502 upstream=10.7.23.136:3002, 10.7.1.136:3001 upstream_status=502, 502
  request_time=2.028 upstream_connect=1.013, 1.015` → nginx tried B, then A; both refused, so nothing
  was left to retry and nginx itself answered **502 Bad Gateway** (the gateway is fine, what's behind it isn't).
- `14:09:29 ... status=502 upstream=team_backends request_time=0.000` + error log
  `no live upstreams while connecting to upstream` → both servers are marked down (fail_timeout), so
  nginx answers 502 **instantly** without even trying a connection.
- 14:09:44 onward: both restored → `A B A B` again, with no nginx restart or reload.

## F1, F2, F5 leave NO trace on the edge, and that is the evidence
- **F1** (client's DNS server → 192.0.2.53, unreachable): the name never resolves, so no packet ever
  reaches the edge (layer: DNS, before TCP).
- **F2** (DNS record → 10.7.1.136, the wrong host): clients connect to mac_abhay instead of the edge.
  mac_abhay has nothing on 443, so they get connection refused there (or, if something answered, the
  certificate would still fail). Again nothing hits our nginx.
- **F5** (port 8444): nothing listens on :8444 on the edge (`lsof` in the extract), so the kernel answers
  the SYN with a RST ("connection refused"). nginx is never involved.
  So the edge's logs tell you *where* a failure happened: no entry means it failed before the edge
  (DNS/TCP), `502, 200` means a backend failed and nginx hid it, and `502` means all backends failed.

## Timing notes
- A refused connect is normally near-instant; here `upstream_connect` for the refused tries was
  0.46–1.04 s because mac_vachan's Wi-Fi link was congested (its Content Caching service was serving
  campus clients, adding queueing delay). Everything stayed under `proxy_connect_timeout 2s`, so every
  failure was a clean "connection refused" (error), never a timeout.
