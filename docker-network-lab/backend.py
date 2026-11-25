#!/usr/bin/env python3
"""subspace_67 backend: one tiny HTTP service, run identically as Backend A and Backend B.

Python 3 standard library only. Configured by environment variables:
    BACKEND_ID   A or B          (which backend this process is)
    PORT         3001 or 3002    (TCP port, bound on 0.0.0.0 so the edge can reach it over the LAN)

Endpoints (GET and HEAD):
    /                -> service banner JSON
    /api/status      -> status JSON, Cache-Control: no-store (never cached, so every request reaches a backend)
    /api/cache-demo  -> byte-identical body on both backends, Cache-Control: public, max-age=60,
                        ETag = first 16 hex chars of sha256(body), fixed Last-Modified.
                        If-None-Match matching the ETag -> 304 Not Modified with no body.
    anything else    -> 404 JSON
Every response (200, 304, 404, ...) carries "X-Backend: <ID>".
Each request is logged to stdout with the TCP peer IP:port. Behind nginx that peer is the edge
(mac_aanya), which proves clients never talk to a backend directly.
"""
import datetime
import hashlib
import json
import os
import signal
import socket
import sys
import threading
import time
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

BACKEND_ID = os.environ.get("BACKEND_ID", "").strip().upper()
try:
    PORT = int(os.environ.get("PORT", ""))
except ValueError:
    PORT = 0
if BACKEND_ID not in ("A", "B") or not 0 < PORT < 65536:
    sys.exit("usage: BACKEND_ID=A|B PORT=3001|3002 python3 backend.py")

HOSTNAME = socket.gethostname()

# The cache-demo representation: a fixed byte string (no backend id, no timestamp), so Backend A and
# Backend B return identical bytes and therefore the identical ETag. That is what lets a conditional
# request get 304 no matter which backend the load balancer picks.
CACHE_DEMO_BODY = (
    b'{"resource":"cache-demo","team":"subspace_67","version":1,'
    b'"message":"This body is byte-identical on Backend A and Backend B, so both send the same ETag '
    b'and a conditional GET gets 304 Not Modified whichever backend answers."}\n'
)
CACHE_DEMO_ETAG = '"%s"' % hashlib.sha256(CACHE_DEMO_BODY).hexdigest()[:16]
CACHE_DEMO_LAST_MODIFIED = "Tue, 29 Sep 2026 00:00:00 GMT"  # fixed on purpose
CACHE_DEMO_LAST_MODIFIED_DT = parsedate_to_datetime(CACHE_DEMO_LAST_MODIFIED)


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="milliseconds")


def log(line):
    print(f"{now_iso()} backend={BACKEND_ID} {line}", flush=True)


def etag_matches(header_value, etag):
    """If-None-Match uses the weak comparison: W/"x" matches "x"; "*" matches any current representation."""
    for candidate in header_value.split(","):
        candidate = candidate.strip()
        if candidate == "*":
            return True
        if candidate.startswith("W/"):
            candidate = candidate[2:]
        if candidate == etag:
            return True
    return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"          # keep-alive capable; every response has Content-Length
    server_version = "subspace67-backend/1.0"

    def version_string(self):
        return self.server_version

    # ---- routing -------------------------------------------------------------------------------
    def do_GET(self):
        self.route(send_body=True)

    def do_HEAD(self):                      # curl -I sends HEAD: same headers as GET, no body
        self.route(send_body=False)

    def route(self, send_body):
        path = urlsplit(self.path).path
        if path == "/":
            self.send_json(200, {"service": "subspace_67 backend", "backend": BACKEND_ID,
                                 "status": "running", "host": HOSTNAME, "time": now_iso()}, send_body)
        elif path == "/api/status":
            self.send_json(200, {"backend": BACKEND_ID, "status": "ok", "port": PORT,
                                 "host": HOSTNAME, "time": now_iso()}, send_body,
                           extra={"Cache-Control": "no-store"})
        elif path == "/api/cache-demo":
            self.cache_demo(send_body)
        else:
            self.send_json(404, {"error": "not found", "path": path, "backend": BACKEND_ID}, send_body)

    def cache_demo(self, send_body):
        validators = {"Cache-Control": "public, max-age=60", "ETag": CACHE_DEMO_ETAG,
                      "Last-Modified": CACHE_DEMO_LAST_MODIFIED}
        inm = self.headers.get("If-None-Match")
        ims = self.headers.get("If-Modified-Since")
        not_modified = False
        if inm is not None:                 # If-None-Match wins over If-Modified-Since (RFC 9110 13.2.2)
            not_modified = etag_matches(inm, CACHE_DEMO_ETAG)
        elif ims is not None:
            try:
                not_modified = parsedate_to_datetime(ims) >= CACHE_DEMO_LAST_MODIFIED_DT
            except (TypeError, ValueError):
                not_modified = False
        if not_modified:
            self.send_response(304)          # 304: validators repeated, no body, no Content-Length
            self.send_header("X-Backend", BACKEND_ID)
            for k, v in validators.items():
                self.send_header(k, v)
            self.end_headers()
            return
        self.send_bytes(200, CACHE_DEMO_BODY, "application/json; charset=utf-8", send_body, validators)

    # ---- response helpers ----------------------------------------------------------------------
    def send_json(self, code, obj, send_body, extra=None):
        body = (json.dumps(obj) + "\n").encode()
        self.send_bytes(code, body, "application/json; charset=utf-8", send_body, extra)

    def send_bytes(self, code, body, ctype, send_body, extra=None):
        self.send_response(code)
        self.send_header("X-Backend", BACKEND_ID)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def send_error(self, code, message=None, explain=None):
        # Replaces the stock HTML error page so even 400/405/501 carry X-Backend and JSON.
        self.close_connection = True
        body = (json.dumps({"error": message or self.responses.get(code, ("error",))[0],
                            "code": code, "backend": BACKEND_ID}) + "\n").encode()
        self.send_response(code)
        self.send_header("X-Backend", BACKEND_ID)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        if code == 405:
            self.send_header("Allow", "GET, HEAD")
        self.end_headers()
        if self.command != "HEAD" and code >= 200 and code not in (204, 304):
            self.wfile.write(body)

    def do_POST(self):
        self.send_error(405, "method not allowed")

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_POST

    # ---- logging: one stdout line per request, with the TCP peer (IP:port) ----------------------
    def log_request(self, code="-", size="-"):
        peer = "%s:%s" % self.client_address[:2]
        h = getattr(self, "headers", None)   # absent if the request line itself was malformed
        extras = ""
        if h is not None:
            extras = " host=%s xff=%s proto=%s ua=%s" % (
                h.get("Host", "-"), h.get("X-Forwarded-For", "-"),
                h.get("X-Forwarded-Proto", "-"), (h.get("User-Agent", "-") or "-").replace(" ", "_"))
        log('client=%s "%s" %s%s' % (peer, self.requestline, getattr(code, "value", code), extras))

    def log_message(self, fmt, *args):
        log("client=%s:%s %s" % (self.client_address[0], self.client_address[1], fmt % args))


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def watch_supervisor(ppid):
    """When started by supervisor.py: exit as soon as the supervisor dies (even if it was kill -9'd)."""
    while True:
        time.sleep(1)
        if os.getppid() != ppid:
            log("supervisor is gone -> exiting")
            os._exit(0)


def main():
    def on_term(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, on_term)

    sup = os.environ.get("SUPERVISOR_PID")
    if sup and sup.isdigit():
        threading.Thread(target=watch_supervisor, args=(int(sup),), daemon=True).start()

    httpd = Server(("0.0.0.0", PORT), Handler)
    log(f"listening on 0.0.0.0:{PORT} (host {HOSTNAME}, pid {os.getpid()}, cache-demo ETag {CACHE_DEMO_ETAG})")
    try:
        httpd.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        httpd.server_close()
        log(f"stopped; port {PORT} closed")


if __name__ == "__main__":
    main()
