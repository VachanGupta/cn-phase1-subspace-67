#!/usr/bin/env python3
"""EMERGENCY stopgap only: relay DNS queries from THIS Mac (127.0.0.1 / own LAN IP) to 1.1.1.1/8.8.8.8.
Binds the wildcard 0.0.0.0:53 (allowed for a normal user on macOS). Other sources are ignored, so it
is not an open resolver. Stopped as soon as the real dnsmasq service is fixed."""
import socket, subprocess, threading
me = subprocess.run(["ipconfig", "getifaddr", "en0"], capture_output=True, text=True).stdout.strip()
ALLOWED = {"127.0.0.1", me}
srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
srv.bind(("0.0.0.0", 53))
def handle(data, addr):
    for up in (("1.1.1.1", 53), ("8.8.8.8", 53)):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2.5)
        try:
            s.sendto(data, up); r, _ = s.recvfrom(65535); srv.sendto(r, addr); return
        except OSError:
            continue
        finally:
            s.close()
while True:
    data, addr = srv.recvfrom(65535)
    if addr[0] in ALLOWED:
        threading.Thread(target=handle, args=(data, addr), daemon=True).start()
