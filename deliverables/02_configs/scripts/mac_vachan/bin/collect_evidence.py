#!/usr/bin/env python3
"""Download every file a peer lists in share/evidence/<name>/MANIFEST.txt into collected/<name>/.
   collect_evidence.py mac_aanya [mac_abhay ...]      (default: both peers)
Safety: refuses anything that looks like a private key or secret (never stored, reported instead).
Writes collected/<name>/COLLECTED.txt (path, bytes, sha256) as a receipt."""
import hashlib, json, os, re, sys, urllib.parse, urllib.request

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
peers = json.load(open(os.path.join(PROJECT_DIR, "peers.json")))
SECRET_MARKERS = (b"PRIVATE KEY-----", b"BEGIN OPENSSH PRIVATE")   # long-term private keys: never collected
KEYLOG_LINE = re.compile(rb"^(CLIENT_RANDOM|CLIENT_HANDSHAKE_TRAFFIC_SECRET|SERVER_HANDSHAKE_TRAFFIC_SECRET|"
                         rb"CLIENT_TRAFFIC_SECRET_0|SERVER_TRAFFIC_SECRET_0|EXPORTER_SECRET) [0-9a-f]+ [0-9a-f]+$", re.M)


def fetch(url, timeout=20):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


def collect(name):
    ip = peers[name]["ip"]
    base = f"http://{ip}:8099/evidence/{name}/"
    manifest = fetch(base + "MANIFEST.txt").decode().splitlines()
    dest = os.path.join(PROJECT_DIR, "collected", name)
    os.makedirs(dest, exist_ok=True)
    receipt, problems = [], []
    for rel in [l.strip() for l in manifest if l.strip() and not l.startswith("#")]:
        rel = rel.lstrip("./")
        if ".." in rel.split("/"):
            problems.append(f"skipped unsafe path {rel}"); continue
        try:
            data = fetch(base + urllib.parse.quote(rel))
        except Exception as e:
            problems.append(f"MISSING {rel}: {e}"); continue
        low = rel.lower()
        if low.endswith((".key", ".p12", ".pfx")) or any(m in data for m in SECRET_MARKERS):
            problems.append(f"REFUSED {rel}: looks like a private key")
            continue
        if KEYLOG_LINE.search(data):   # SSLKEYLOGFILE: per-session secrets of our own test requests only
            problems.append(f"note {rel}: TLS session keylog (decrypts only the captured test sessions; kept for Wireshark)")
        path = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        receipt.append(f"{rel}\t{len(data)}\t{hashlib.sha256(data).hexdigest()}")
    with open(os.path.join(dest, "MANIFEST.txt"), "w") as f:
        f.write("\n".join(manifest) + "\n")
    with open(os.path.join(dest, "COLLECTED.txt"), "w") as f:
        f.write(f"# collected from {base} by mac_vachan\n# path\tbytes\tsha256\n" + "\n".join(receipt) + "\n")
        if problems:
            f.write("# problems:\n" + "\n".join("# " + p for p in problems) + "\n")
    print(f"{name}: {len(receipt)} files collected from {base}" + (f"; {len(problems)} problems:" if problems else ""))
    for p in problems:
        print("   ", p)


if __name__ == "__main__":
    for n in sys.argv[1:] or ["mac_aanya", "mac_abhay"]:
        try:
            collect(n)
        except Exception as e:
            print(f"{n}: FAILED ({e})")
