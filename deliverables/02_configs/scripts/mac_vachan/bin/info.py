#!/usr/bin/env python3
"""Maintain share/info.json for mac_vachan (the team-bus beacon file).

  info.py init                 refresh network facts, keep existing status flags
  info.py set k=v [k=v ...]    set status flags (true/false/ints parsed)
  info.py get [k]              print the whole file or one status flag

Writes are atomic (temp file + os.replace) so peers never read half a file.
"""
import datetime, json, os, re, socket, subprocess, sys

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO = os.path.join(PROJECT_DIR, "share", "info.json")
NAME = "mac_vachan"
ROLES = ["dns_server", "backend_B", "client", "integrator"]
FLAGS = ["backend_code_published", "backend_B_ready", "dns_ready",
         "failures_in_progress", "failures_done", "deliverables_done", "team_done"]


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return ""


def network_facts():
    route = sh("route", "-n", "get", "default")
    iface = re.search(r"interface:\s*(\S+)", route)
    gw = re.search(r"gateway:\s*(\S+)", route)
    iface = iface.group(1) if iface else "en0"
    ip = sh("ipconfig", "getifaddr", iface).strip()
    mask = sh("ipconfig", "getoption", iface, "subnet_mask").strip()
    prefix = sum(bin(int(o)).count("1") for o in mask.split(".")) if mask else None
    ether = re.search(r"ether\s+([0-9a-f:]{17})", sh("ifconfig", iface))
    service, hw_mac = None, None
    order = sh("networksetup", "-listnetworkserviceorder")
    m = re.search(r"\(\d+\)\s+([^\n]+)\n\(Hardware Port: [^,]+, Device: %s\)" % re.escape(iface), order)
    if m:
        service = m.group(1).strip()
    ports = sh("networksetup", "-listallhardwareports")
    m = re.search(r"Device: %s\nEthernet Address: (\S+)" % re.escape(iface), ports)
    if m:
        hw_mac = m.group(1)
    return {
        "ip": ip, "netmask": mask, "prefix": prefix,
        "gateway": gw.group(1) if gw else None,
        "interface": iface, "network_service": service or "Wi-Fi",
        # ifconfig "ether" is what is really on the air (macOS Private Wi-Fi Address);
        # hardware_mac is the burned-in address shown as "Wi-Fi ID".
        "mac_address": ether.group(1) if ether else None,
        "hardware_mac": hw_mac,
        "hostname": socket.gethostname(),
    }


def load():
    try:
        with open(INFO) as f:
            return json.load(f)
    except Exception:
        return {}


def save(d):
    d["updated"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    tmp = INFO + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, INFO)


def parse(v):
    low = v.lower()
    if low in ("true", "false"):
        return low == "true"
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    return v


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "get"
    d = load()
    if cmd == "init":
        status = d.get("status", {})
        for flag in FLAGS:
            status.setdefault(flag, False)
        d = {"name": NAME, **network_facts(), "roles": ROLES,
             "services": {"dns": "dnsmasq 53/udp+tcp", "backend_B": "3002/tcp", "team_bus": "8099/tcp"},
             "status": status}
        save(d)
        print(json.dumps(d, indent=2))
    elif cmd == "set":
        d.setdefault("status", {})
        for kv in sys.argv[2:]:
            k, _, v = kv.partition("=")
            d["status"][k] = parse(v)
        save(d)
        print(json.dumps(d["status"]))
    elif cmd == "get":
        if len(sys.argv) > 2:
            print(json.dumps(d.get("status", {}).get(sys.argv[2])))
        else:
            print(json.dumps(d, indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
