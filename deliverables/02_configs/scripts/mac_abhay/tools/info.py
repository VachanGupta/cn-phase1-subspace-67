#!/usr/bin/env python3
"""Keep share/info.json current for mac_abhay (the team bus beacon file).

Usage:
  python3 tools/info.py                      # refresh network facts, keep status flags
  python3 tools/info.py backend_A_ready=true # also set/replace status flags
  python3 tools/info.py note="some text"     # string values are kept as strings

Always writes a temp file and then renames it over info.json, so a peer polling
http://<ip>:8099/info.json never reads a half-written file.
"""
import datetime
import ipaddress
import json
import os
import subprocess
import sys

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARE = os.path.join(PROJECT_DIR, "share")
INFO = os.path.join(SHARE, "info.json")
NAME = "mac_abhay"
ROLES = ["backend_A", "client"]
DEFAULT_STATUS = {"backend_A_ready": False, "client_evidence_done": False}


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def network_facts():
    route = sh("route -n get default")
    iface, gateway = "en0", ""
    for line in route.splitlines():
        line = line.strip()
        if line.startswith("interface:"):
            iface = line.split(":", 1)[1].strip()
        elif line.startswith("gateway:"):
            gateway = line.split(":", 1)[1].strip()
    ip = sh(f"ipconfig getifaddr {iface}")
    netmask, prefix = "", None
    for line in sh(f"ifconfig {iface}").splitlines():
        parts = line.split()
        if parts and parts[0] == "inet" and len(parts) >= 4:
            ip = ip or parts[1]
            netmask = str(ipaddress.IPv4Address(int(parts[3], 16)))
            prefix = ipaddress.IPv4Network(f"0.0.0.0/{netmask}").prefixlen
        if parts and parts[0] == "ether":
            mac = parts[1]
    # Map the BSD interface (en0) to its network service name (Wi-Fi) and hardware MAC
    service, hw_mac, current = "", "", None
    for line in sh("networksetup -listallhardwareports").splitlines():
        if line.startswith("Hardware Port:"):
            current = {"port": line.split(":", 1)[1].strip()}
        elif line.startswith("Device:") and current is not None:
            current["dev"] = line.split(":", 1)[1].strip()
        elif line.startswith("Ethernet Address:") and current is not None:
            current["hw"] = line.split(":", 1)[1].strip()
            if current.get("dev") == iface:
                service, hw_mac = current["port"], current["hw"]
    return {
        "ip": ip,
        "netmask": netmask,
        "prefix": prefix,
        "gateway": gateway,
        "interface": iface,
        "network_service": service or "Wi-Fi",
        # the address actually used on the wire (macOS private Wi-Fi address) - this is what pcaps show
        "mac_address": locals().get("mac", ""),
        "hardware_mac_address": hw_mac,
        "hostname": sh("scutil --get LocalHostName") or sh("hostname"),
    }


def parse_value(v):
    low = v.lower()
    if low in ("true", "false"):
        return low == "true"
    try:
        return int(v)
    except ValueError:
        return v


def main():
    os.makedirs(SHARE, exist_ok=True)
    info = {}
    if os.path.exists(INFO):
        try:
            with open(INFO) as f:
                info = json.load(f)
        except Exception:
            info = {}
    status = dict(DEFAULT_STATUS)
    status.update(info.get("status", {}))
    for arg in sys.argv[1:]:
        if "=" in arg:
            k, v = arg.split("=", 1)
            status[k] = parse_value(v)
    new = {"name": NAME}
    new.update(network_facts())
    new["roles"] = ROLES
    new["status"] = status
    new["updated"] = datetime.datetime.now(datetime.timezone.utc).astimezone().isoformat(timespec="seconds")
    tmp = INFO + ".tmp"
    with open(tmp, "w") as f:
        json.dump(new, f, indent=2)
        f.write("\n")
    os.replace(tmp, INFO)
    print(json.dumps(new, indent=2))


if __name__ == "__main__":
    main()
