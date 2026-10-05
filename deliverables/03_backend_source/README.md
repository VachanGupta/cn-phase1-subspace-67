# subspace_67 backend (identical code for Backend A and Backend B)

Files: backend.py (the HTTP service), supervisor.py (keeps it up/down per control.json), SHA256SUMS.
Python 3 standard library only. Do not edit: both backends must run byte-identical code
(`shasum -a 256 -c SHA256SUMS` must say OK on both Macs).

## Run (from your PROJECT_DIR; VACHAN_IP = mac_vachan's current LAN IP from its info.json)
    mkdir -p backend logs
    curl -fsS http://$VACHAN_IP:8099/backend/backend.py    -o backend/backend.py
    curl -fsS http://$VACHAN_IP:8099/backend/supervisor.py -o backend/supervisor.py
    curl -fsS http://$VACHAN_IP:8099/backend/SHA256SUMS    -o backend/SHA256SUMS
    (cd backend && shasum -a 256 -c SHA256SUMS)
    # Backend A (mac_abhay):
    nohup python3 backend/supervisor.py --id A --port 3001 \
          --control-url http://$VACHAN_IP:8099/control.json > logs/backend_A.log 2>&1 < /dev/null &
    # Backend B (mac_vachan) is the same with --id B --port 3002 > logs/backend_B.log

## Check
    lsof -nP -iTCP:3001 -sTCP:LISTEN          # must show *:3001 (bound on all interfaces)
    curl -si http://<own LAN IP>:3001/api/status   # 200 + X-Backend: A

## Endpoints (GET and HEAD)
- /                -> {"service":"subspace_67 backend","backend":ID,"status":"running","host":...,"time":...}
- /api/status      -> {"backend":ID,"status":"ok","port":PORT,"host":...,"time":...}  Cache-Control: no-store
- /api/cache-demo  -> identical bytes on A and B; Cache-Control: public, max-age=60;
                      ETag "6adb0ec0cb57508d" (= first 16 hex of sha256(body)); Last-Modified fixed.
                      If-None-Match: "6adb0ec0cb57508d" -> 304 Not Modified, no body.
- anything else    -> 404 JSON.   Every response carries X-Backend: A|B.

## control.json (served by mac_vachan at http://$VACHAN_IP:8099/control.json)
{"A":"up","B":"up"}. The supervisor polls it every 2 s. "down" = the backend process is really
stopped and its port closed (nginx then gets "connection refused"). If control.json can't be
fetched the supervisor keeps the current state. Killing the supervisor stops the backend too.

## Logs
One line per request with the TCP peer IP:port, e.g.
    ... backend=A client=<mac_aanya IP>:54012 "GET /api/status HTTP/1.0" 200 host=app.subspace-67.test xff=<real client IP> proto=https ...
Behind nginx the peer is always the edge (mac_aanya); the original client is only in X-Forwarded-For.
