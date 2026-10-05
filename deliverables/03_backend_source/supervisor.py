#!/usr/bin/env python3
"""subspace_67 backend supervisor: keeps backend.py up or down to match the team's control.json.

    python3 supervisor.py --id A --port 3001 --control-url http://<mac_vachan IP>:8099/control.json
    (or env BACKEND_ID / PORT / CONTROL_URL)

- Runs backend.py (same folder) as a child process with BACKEND_ID and PORT.
- Every 2 s fetches control.json, e.g. {"A":"up","B":"up"}, and starts/stops the child to match.
  "down" means the child process is really gone and the port is closed, so nginx gets
  "connection refused" (a real failure, not a fake error page).
- If control.json can't be fetched, the current state is kept.
- If the child dies on its own while it should be up, it is restarted.
- Killing the supervisor (SIGTERM/SIGINT/SIGHUP) stops the child too; the child also exits by
  itself if the supervisor disappears (even after kill -9), because it watches its parent pid.
Standard library only. Supervisor lines and the backend's request lines share one stdout log.
"""
import argparse
import datetime
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="milliseconds")


def log(msg):
    print(f"{now_iso()} [supervisor] {msg}", flush=True)


def port_open(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


class Supervisor:
    def __init__(self, backend_id, port, control_url, interval, backend_path):
        self.id, self.port, self.url = backend_id, port, control_url
        self.interval, self.backend_path = interval, backend_path
        self.child = None
        self.desired = None          # last state read from control.json ("up"/"down")
        self.fetch_ok = None

    def fetch(self):
        """Return 'up'/'down' from control.json, or None if it can't be fetched/parsed."""
        try:
            req = urllib.request.Request(self.url, headers={"Cache-Control": "no-cache"})
            with urllib.request.urlopen(req, timeout=1.5) as r:
                data = json.loads(r.read().decode())
            state = str(data.get(self.id, "up")).strip().lower()
            if state not in ("up", "down"):
                raise ValueError(f"unknown state {state!r} for {self.id}")
            if self.fetch_ok is False:
                log(f"control.json reachable again ({self.url})")
            self.fetch_ok = True
            return state
        except Exception as e:
            if self.fetch_ok is not False:
                log(f"cannot read control.json ({e.__class__.__name__}: {e}); keeping current state")
            self.fetch_ok = False
            return None

    def running(self):
        return self.child is not None and self.child.poll() is None

    def start_child(self):
        env = dict(os.environ, BACKEND_ID=self.id, PORT=str(self.port),
                   PYTHONUNBUFFERED="1", SUPERVISOR_PID=str(os.getpid()))
        self.child = subprocess.Popen([sys.executable, self.backend_path], env=env,
                                      stdin=subprocess.DEVNULL)
        log(f"started backend {self.id} (pid {self.child.pid}) on port {self.port}")
        for _ in range(20):                      # wait up to 2 s for the listener
            if port_open(self.port) or self.child.poll() is not None:
                break
            time.sleep(0.1)
        if port_open(self.port):
            log(f"backend {self.id} is UP: port {self.port} accepting connections")

    def stop_child(self, reason):
        if not self.running():
            self.child = None
            return
        pid = self.child.pid
        log(f"stopping backend {self.id} (pid {pid}): {reason}")
        self.child.terminate()
        try:
            self.child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()
        self.child = None
        closed = not port_open(self.port)
        log(f"backend {self.id} is DOWN: pid {pid} gone, port {self.port} "
            f"{'closed (connection refused)' if closed else 'STILL OPEN - another process holds it'}")

    def run(self):
        log(f"supervising backend {self.id} on port {self.port}; control {self.url} every {self.interval}s")
        while True:
            state = self.fetch()
            if state is not None:
                if state != self.desired:
                    log(f"control.json says {self.id}={state}")
                self.desired = state
            elif self.desired is None:
                self.desired = "up"              # no control file yet: run the backend
            if self.child is not None and self.child.poll() is not None:
                log(f"backend {self.id} exited on its own (code {self.child.returncode})")
                self.child = None
            if self.desired == "up" and not self.running():
                self.start_child()
            elif self.desired == "down" and self.running():
                self.stop_child("control.json says down")
            time.sleep(self.interval)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", default=os.environ.get("BACKEND_ID"), help="A or B")
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "0") or 0))
    ap.add_argument("--control-url", default=os.environ.get("CONTROL_URL"),
                    help="http://<mac_vachan IP>:8099/control.json")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--backend", default=os.path.join(HERE, "backend.py"))
    a = ap.parse_args()
    if not a.id or a.id.upper() not in ("A", "B") or not 0 < a.port < 65536 or not a.control_url:
        ap.error("need --id A|B, --port N and --control-url URL (or BACKEND_ID/PORT/CONTROL_URL)")

    sup = Supervisor(a.id.upper(), a.port, a.control_url, a.interval, a.backend)

    def on_signal(signum, frame):
        raise SystemExit(128 + signum)
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        if signal.getsignal(s) is not signal.SIG_IGN:   # respect nohup (SIGHUP ignored)
            signal.signal(s, on_signal)
    try:
        sup.run()
    except SystemExit:
        pass
    finally:
        sup.stop_child("supervisor exiting")
        log("supervisor exited")


if __name__ == "__main__":
    main()
