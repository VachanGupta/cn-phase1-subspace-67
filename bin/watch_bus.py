#!/usr/bin/env python3
"""Background watcher for the team bus (run under Monitor). Prints one line per *change*:
  PEER_FOUND / PEER_LOST, STATUS <peer> <flag>=<value>, MSG <from> -> <to>: <text>, BEACON restarted.
Every ~5 s: polls each peer's info.json + outbox.jsonl; every 60 s re-runs discovery while a peer is
missing; keeps our own beacon alive. State persists in run/watch_state.json so a re-armed watcher
only reports what is new.
"""
import hashlib, json, os, subprocess, sys, time, urllib.request

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(PROJECT_DIR, "run", "watch_state.json")
ME = "mac_vachan"
PEERS = ("mac_aanya", "mac_abhay")


def get(url, timeout=1.5):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read().decode()


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def save_state(st):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE)


def emit(line):
    print(line, flush=True)


def main():
    st = load(STATE, {"status": {}, "up": {}})
    last_disc = 0
    while True:
        # keep our own beacon alive
        try:
            get("http://127.0.0.1:8099/info.json", 1)
        except Exception:
            subprocess.run(["bash", os.path.join(PROJECT_DIR, "bin", "beacon.sh")], capture_output=True)
            emit("BEACON was down -> restarted")
        peers = load(os.path.join(PROJECT_DIR, "peers.json"), {})
        missing = [p for p in PEERS if p not in peers]
        if missing and time.time() - last_disc > 60:
            last_disc = time.time()
            subprocess.run([sys.executable, os.path.join(PROJECT_DIR, "bin", "discover.py")], capture_output=True)
            peers = load(os.path.join(PROJECT_DIR, "peers.json"), {})
            for p in missing:
                if p in peers:
                    emit(f"PEER_FOUND {p} {peers[p].get('ip')}")
        for p in PEERS:
            if p not in peers:
                continue
            ip = peers[p].get("ip")
            try:
                info = json.loads(get(f"http://{ip}:8099/info.json"))
                if not st["up"].get(p, False):
                    emit(f"PEER_UP {p} {ip}")
                st["up"][p] = True
                st.setdefault("fails", {})[p] = 0
                if info.get("ip") and info["ip"] != ip:
                    emit(f"PEER_IP_CHANGED {p} {ip} -> {info['ip']}")
                    peers[p]["ip"] = info["ip"]
                old = st["status"].get(p, {})
                for k, v in (info.get("status") or {}).items():
                    if old.get(k) != v:
                        emit(f"STATUS {p} {k}={json.dumps(v)}")
                st["status"][p] = info.get("status") or {}
            except Exception as e:
                st.setdefault("fails", {})[p] = st.get("fails", {}).get(p, 0) + 1
                if st["up"].get(p, False) and st["fails"][p] >= 3:
                    emit(f"PEER_UNREACHABLE {p} {ip} ({e.__class__.__name__})")
                    st["up"][p] = False
                    last_disc = 0      # rediscover soon (IP may have changed)
                continue
            try:
                lines = get(f"http://{ip}:8099/outbox.jsonl").splitlines()
            except Exception:
                continue                      # transient failure: keep what we have seen so far
            seen = st.setdefault("seen", {})
            first_time = p not in seen        # first look (e.g. after a re-arm): record silently
            known = set(seen.get(p, []))
            for raw in lines:
                h = hashlib.sha1(raw.encode()).hexdigest()[:16]
                if h in known:
                    continue
                known.add(h)
                seen.setdefault(p, []).append(h)
                if first_time:
                    continue
                try:
                    m = json.loads(raw)
                except Exception:
                    continue
                if m.get("to") in (ME, "all", "*", None) or ME in str(m.get("to")):
                    emit(f"MSG {m.get('from', p)} -> {m.get('to')}: {m.get('text')}")
            seen[p] = seen.get(p, [])[-2000:]
        save_state(st)
        time.sleep(5)


if __name__ == "__main__":
    main()
