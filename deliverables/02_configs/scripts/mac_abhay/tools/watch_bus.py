#!/usr/bin/env python3
"""Watch the team bus and print one line per change (used as a background Monitor).

Every 5 s: re-read each known peer's http://<ip>:8099/info.json and print status-flag
changes, reachability changes, IP changes, and new lines addressed to mac_abhay in the
peers' fallback message board (share/outbox.jsonl). While a team member is still
missing it re-runs discovery (hint IPs from tools/hints.txt + ARP cache every 5 s, the
capped /22 scan every 60 s). Also keeps our own beacon alive and info.json fresh.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import discover  # noqa: E402

PROJECT_DIR = discover.PROJECT_DIR
HINTS = os.path.join(PROJECT_DIR, "tools", "hints.txt")
TEAM = discover.TEAM


def say(msg):
    print(time.strftime("%H:%M:%S ") + msg, flush=True)


def fetch(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read().decode(errors="replace")


def hints():
    try:
        return [l.strip() for l in open(HINTS) if l.strip()]
    except FileNotFoundError:
        return []


def beacon_alive():
    try:
        fetch("http://127.0.0.1:8099/info.json", timeout=2)
        return True
    except Exception:
        return False


def restart_beacon():
    log = open(os.path.join(PROJECT_DIR, "logs", "beacon.log"), "a")
    subprocess.Popen(
        [sys.executable, "-m", "http.server", "8099", "--bind", "0.0.0.0", "--directory",
         os.path.join(PROJECT_DIR, "share")],
        stdout=log, stderr=log, start_new_session=True)


def main():
    prev_status, prev_reach, prev_ip = {}, {}, {}
    state_file = os.path.join(PROJECT_DIR, "logs", "watch_state.json")
    try:
        outbox_seen = json.load(open(state_file)).get("outbox_seen", {})
    except Exception:
        outbox_seen = {}
    last_scan, last_info = 0.0, 0.0
    capture_lock = os.path.join(PROJECT_DIR, "logs", "capture.lock")
    paused = False
    while True:
        now = time.time()
        # Task G packet capture running: send no traffic to peers so the pcap stays clean
        if os.path.exists(capture_lock):
            if not paused:
                say("capture.lock present -> pausing peer polling during the packet capture")
                paused = True
            time.sleep(2)
            continue
        if paused:
            say("capture.lock gone -> resuming peer polling")
            paused = False
        if not beacon_alive():
            say("own beacon :8099 was down -> restarted")
            restart_beacon()
        if now - last_info > 60:
            subprocess.run([sys.executable, os.path.join(PROJECT_DIR, "tools", "info.py")],
                           capture_output=True)
            last_info = now
        try:
            peers = json.load(open(discover.PEERS))
        except Exception:
            peers = {}
        missing = [n for n in TEAM if n not in peers or peers[n].get("_stale")]
        if missing:
            args = [sys.executable, os.path.join(PROJECT_DIR, "tools", "discover.py")] + hints()
            if now - last_scan < 60:
                args.append("--no-scan")
            else:
                last_scan = now
            subprocess.run(args, capture_output=True)
            try:
                peers = json.load(open(discover.PEERS))
            except Exception:
                pass
        for name in TEAM:
            if name == "mac_abhay" or name not in peers:
                continue
            ip = peers[name].get("ip")
            try:
                info = json.loads(fetch(f"http://{ip}:8099/info.json"))
                reach = True
            except Exception:
                info, reach = None, False
            if prev_reach.get(name) != reach:
                say(f"{name} beacon {ip}:8099 {'REACHABLE' if reach else 'UNREACHABLE'}")
                prev_reach[name] = reach
            if not info:
                continue
            if info.get("ip") and info["ip"] != ip:
                say(f"{name} reports a new IP {info['ip']} (was {ip}) -> rediscovering")
                subprocess.run([sys.executable, os.path.join(PROJECT_DIR, "tools", "discover.py"),
                                info["ip"], "--no-scan"], capture_output=True)
            if prev_ip.get(name) != info.get("ip"):
                prev_ip[name] = info.get("ip")
            st = info.get("status", {})
            old = prev_status.get(name)
            if old is None:
                say(f"{name} status now {json.dumps(st, sort_keys=True)}")
            else:
                for k in sorted(set(st) | set(old)):
                    if st.get(k) != old.get(k):
                        say(f"{name} {k}: {old.get(k)} -> {st.get(k)}")
            prev_status[name] = st
            # fallback message board
            try:
                lines = fetch(f"http://{ip}:8099/outbox.jsonl").splitlines()
            except Exception:
                lines = []
            seen = outbox_seen.get(name, 0)
            for line in lines[seen:]:
                try:
                    m = json.loads(line)
                except Exception:
                    continue
                if m.get("to") in ("mac_abhay", "all", "*"):
                    say(f"OUTBOX {m.get('from')}->{m.get('to')}: {m.get('text')}")
            outbox_seen[name] = len(lines)
        try:
            with open(state_file + ".tmp", "w") as f:
                json.dump({"outbox_seen": outbox_seen}, f)
            os.replace(state_file + ".tmp", state_file)
        except Exception:
            pass
        time.sleep(5)


if __name__ == "__main__":
    main()
