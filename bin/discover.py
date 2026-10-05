#!/usr/bin/env python3
"""Find the team's Macs by their team-bus beacon (http://<ip>:8099/info.json); save PROJECT_DIR/peers.json.

  discover.py                 one pass: known IPs + ARP neighbours + sweep of own subnet (capped at /22)
  discover.py --loop [SECS]   repeat every 10 s until all 3 names are found (default timeout 1800 s)
  discover.py 10.7.1.2 ...    extra candidate IPs (e.g. from a peer's chat hello) are probed first

Peer IPs always come from the peer's own info.json, never hard-coded.
"""
import concurrent.futures, datetime, ipaddress, json, os, re, subprocess, sys, time, urllib.request

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEERS = os.path.join(PROJECT_DIR, "peers.json")
NAMES = ("mac_vachan", "mac_aanya", "mac_abhay")


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return ""


def own_net():
    iface = (re.search(r"interface:\s*(\S+)", sh("route", "-n", "get", "default")) or [None, "en0"])[1]
    ip = sh("ipconfig", "getifaddr", iface).strip()
    mask = sh("ipconfig", "getoption", iface, "subnet_mask").strip() or "255.255.255.0"
    return ip, ipaddress.ip_interface(f"{ip}/{mask}").network


def probe(ip):
    try:
        with urllib.request.urlopen(f"http://{ip}:8099/info.json", timeout=1) as r:
            d = json.loads(r.read().decode())
        if d.get("name") in NAMES:
            return str(ip), d
    except Exception:
        pass
    return None


def load():
    try:
        with open(PEERS) as f:
            return json.load(f)
    except Exception:
        return {}


def save(peers):
    tmp = PEERS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(peers, f, indent=2)
        f.write("\n")
    os.replace(tmp, PEERS)


def one_pass(extra):
    my_ip, net = own_net()
    scan = net if net.prefixlen >= 22 else ipaddress.ip_network(f"{my_ip}/22", strict=False)
    old = load()
    hints = []                             # run/hint_ips.txt: IPs a peer mentioned (hello, evidence)
    try:
        hints = [l.strip() for l in open(os.path.join(PROJECT_DIR, "run", "hint_ips.txt")) if l.strip()]
    except OSError:
        pass
    first = [my_ip] + list(extra) + hints + [p.get("ip") for p in old.values() if p.get("ip")]
    arp = re.findall(r"\((\d+\.\d+\.\d+\.\d+)\) at [0-9a-f:]{11,17} on", sh("arp", "-an"))
    first += [a for a in arp if ipaddress.ip_address(a) in net]
    found = {}

    def run(ips):
        with concurrent.futures.ThreadPoolExecutor(max_workers=128) as ex:
            for res in ex.map(probe, dict.fromkeys(ips)):
                if res:
                    ip, d = res
                    found[d["name"]] = {**d, "beacon": f"http://{ip}:8099/", "seen": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}

    run(first)
    if len(found) < len(NAMES):
        run(str(h) for h in scan.hosts())
    peers = {**old, **found}              # keep last-known entries for names not seen this pass
    for name in peers:
        peers[name]["reachable_now"] = name in found
    save(peers)
    return found, scan


def main():
    args = sys.argv[1:]
    loop = "--loop" in args
    timeout = 1800
    if loop:
        i = args.index("--loop")
        if i + 1 < len(args) and args[i + 1].isdigit():
            timeout = int(args.pop(i + 1))
        args.remove("--loop")
    deadline = time.time() + timeout
    while True:
        found, scan = one_pass(args)
        line = ", ".join(f"{n}={found[n]['ip']}" for n in NAMES if n in found)
        missing = [n for n in NAMES if n not in found]
        print(f"{datetime.datetime.now():%H:%M:%S} scanned {scan} (+known/ARP): {line or 'none'}"
              + (f"; missing {missing}" if missing else "; all 3 found"), flush=True)
        if not loop or not missing or time.time() > deadline:
            sys.exit(0 if not missing else 1)
        time.sleep(10)


if __name__ == "__main__":
    main()
