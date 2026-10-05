#!/usr/bin/env python3
"""Find the other subspace_67 Macs by their team-bus beacon (http://<ip>:8099/info.json).

Order: hint IPs given on the command line (from a peer's chat hello) -> IPs already in
peers.json -> the ARP cache -> a parallel scan of this Mac's own subnet, capped at /22.
Results go to PROJECT_DIR/peers.json keyed by the name each peer reports in its own
info.json (peer IPs are never hard-coded). Exit code 0 only when all 3 names are known.

Usage: python3 tools/discover.py [hint_ip ...] [--no-scan]
"""
import concurrent.futures
import datetime
import ipaddress
import json
import os
import re
import subprocess
import sys
import urllib.request

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEERS = os.path.join(PROJECT_DIR, "peers.json")
INFO = os.path.join(PROJECT_DIR, "share", "info.json")
TEAM = ["mac_vachan", "mac_aanya", "mac_abhay"]
MAX_SCAN_PREFIX = 22  # never scan anything bigger than a /22


def probe(ip):
    try:
        with urllib.request.urlopen(f"http://{ip}:8099/info.json", timeout=1) as r:
            data = json.loads(r.read().decode())
        if data.get("name") in TEAM:
            data["_seen_at"] = str(ip)
            return data
    except Exception:
        pass
    return None


def own_network():
    with open(INFO) as f:
        me = json.load(f)
    net = ipaddress.IPv4Interface(f"{me['ip']}/{me['prefix']}").network
    if net.prefixlen < MAX_SCAN_PREFIX:
        net = ipaddress.IPv4Interface(f"{me['ip']}/{MAX_SCAN_PREFIX}").network
    return me, net


def arp_ips():
    try:
        out = subprocess.run(["arp", "-an"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    return re.findall(r"\((\d+\.\d+\.\d+\.\d+)\) at [0-9a-f]", out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    no_scan = "--no-scan" in sys.argv
    me, net = own_network()
    found = {"mac_abhay": me}
    old = {}
    if os.path.exists(PEERS):
        try:
            old = json.load(open(PEERS))
        except Exception:
            old = {}

    def run(ips):
        ips = list(dict.fromkeys(str(i) for i in ips if str(i) != me["ip"]))
        with concurrent.futures.ThreadPoolExecutor(max_workers=256) as ex:
            for res in ex.map(probe, ips):
                if res and res["name"] != "mac_abhay":
                    found[res["name"]] = res

    run(args + [v.get("ip") for k, v in old.items() if isinstance(v, dict) and v.get("ip")])
    if not all(n in found for n in TEAM):
        # gossip: a peer we found may already know the others (share/peers.json on its bus)
        gossip = []
        for k, v in list(found.items()):
            if k == "mac_abhay":
                continue
            try:
                with urllib.request.urlopen(f"http://{v['ip']}:8099/peers.json", timeout=1) as r:
                    theirs = json.loads(r.read().decode())
                gossip += [e.get("ip") for e in theirs.values() if isinstance(e, dict) and e.get("ip")]
            except Exception:
                pass
        run(gossip)
    if not all(n in found for n in TEAM) and not no_scan:
        # ARP cache first: it can hold peers outside our /22 (the LAN here is a /19)
        run(arp_ips())
    if not all(n in found for n in TEAM) and not no_scan:
        run(net.hosts())

    # keep entries we could not reach this time, but mark them stale
    for k, v in old.items():
        if k in TEAM and k not in found and isinstance(v, dict):
            v["_stale"] = True
            found[k] = v
    found["_updated"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    found["_scanned"] = str(net)
    tmp = PEERS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(found, f, indent=2)
    os.replace(tmp, PEERS)
    pub = os.path.join(PROJECT_DIR, "share", "peers.json")
    view = {k: {"ip": v.get("ip"), "roles": v.get("roles"), "stale": bool(v.get("_stale"))}
            for k, v in found.items() if k in TEAM}
    with open(pub + ".tmp", "w") as f:
        json.dump(view, f, indent=2)
    os.replace(pub + ".tmp", pub)
    for n in TEAM:
        v = found.get(n)
        if v:
            print(f"{n:11s} {v.get('ip'):15s} stale={bool(v.get('_stale'))} status={json.dumps(v.get('status', {}))}")
        else:
            print(f"{n:11s} NOT FOUND")
    sys.exit(0 if all(n in found and not found[n].get("_stale") for n in TEAM) else 1)


if __name__ == "__main__":
    main()
