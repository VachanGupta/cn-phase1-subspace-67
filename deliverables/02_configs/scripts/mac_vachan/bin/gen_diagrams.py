#!/usr/bin/env python3
"""Generate the architecture SVGs from live data (peers.json = each Mac's own info.json):
     deliverables/01_architecture/topology.svg      3 Macs, roles, real IPs, MACs and ports on the LAN
     deliverables/01_architecture/request_flow.svg  one request, step by step, each step mapped to its layer
Both SVGs carry their own light/dark colours (prefers-color-scheme), so they read well anywhere."""
import html, json, os

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT_DIR, "deliverables", "01_architecture")
peers = json.load(open(os.path.join(PROJECT_DIR, "peers.json")))
V, A, B = peers["mac_vachan"], peers["mac_aanya"], peers["mac_abhay"]
NET = "10.7.0.0/%s" % V.get("prefix", 19)

STYLE = """<style>
  .bg{fill:#ffffff} .ink{fill:#1d2330} .muted{fill:#5b6475} .line{stroke:#8a93a6}
  .box{fill:#f6f8fb;stroke:#c9d1de} .bus{fill:#e8eef8;stroke:#9fb3d6}
  .dns{fill:#7a4bd1} .edge{fill:#0f7b6c} .be{fill:#c25e00} .cli{fill:#2f6fd6} .net{fill:#6b7385}
  .s-dns{stroke:#7a4bd1} .s-edge{stroke:#0f7b6c} .s-be{stroke:#c25e00} .s-cli{stroke:#2f6fd6}
  .chip{fill:#eef1f6} .lbl{fill:#ffffff}
  text{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
  @media (prefers-color-scheme: dark){
    .bg{fill:#14171d} .ink{fill:#e6e9ef} .muted{fill:#9aa3b5} .line{stroke:#5d6679}
    .box{fill:#1c2029;stroke:#343b4a} .bus{fill:#1b2536;stroke:#34507e}
    .dns{fill:#a57cf0} .edge{fill:#3fbfa8} .be{fill:#f0913a} .cli{fill:#6aa0f5} .net{fill:#8d95a8}
    .s-dns{stroke:#a57cf0} .s-edge{stroke:#3fbfa8} .s-be{stroke:#f0913a} .s-cli{stroke:#6aa0f5}
    .chip{fill:#252b37} .lbl{fill:#14171d}
  }
</style>"""


def t(x, y, s, cls="ink", size=13, anchor="start", weight="normal", mono=False):
    c = cls + (" mono" if mono else "")
    return (f'<text x="{x}" y="{y}" class="{c}" font-size="{size}" text-anchor="{anchor}" '
            f'font-weight="{weight}">{html.escape(s)}</text>')


def topology():
    W, H = 1100, 640
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" role="img" '
         f'aria-label="subspace_67 phase 1 topology">', STYLE, f'<rect class="bg" width="{W}" height="{H}"/>']
    o.append(t(40, 40, "subspace_67 · Phase 1 topology", size=22, weight="700"))
    o.append(t(40, 64, f"Three Macs on one Wi-Fi LAN ({NET}). Real IPs as captured on the evidence day.", "muted", 13))
    # internet + gateway
    o.append('<rect class="box" x="430" y="84" width="240" height="46" rx="10"/>')
    o.append(t(550, 104, "Internet", size=14, anchor="middle", weight="600"))
    o.append(t(550, 121, "upstream DNS 8.8.8.8 · 1.1.1.1", "muted", 12, "middle"))
    o.append('<line class="line" x1="550" y1="130" x2="550" y2="156" stroke-width="2"/>')
    o.append('<rect class="box" x="455" y="156" width="190" height="36" rx="8"/>')
    o.append(t(550, 179, f"gateway {V['gateway']}", size=13, anchor="middle", mono=True))
    o.append('<line class="line" x1="550" y1="192" x2="550" y2="214" stroke-width="2"/>')
    # LAN bus
    o.append('<rect class="bus" x="40" y="214" width="1020" height="34" rx="8"/>')
    o.append(t(550, 236, f"Wi-Fi LAN {NET} · mask {V['netmask']} · every Mac one hop from the others (ping TTL 64)",
               size=13, anchor="middle", weight="600"))
    macs = [
        (40, B, "Mac 3", "cli", [("be", "Backend A", f":3001/tcp HTTP"), ("cli", "Main test client", "captures (tcpdump/Wireshark)")]),
        (390, A, "Mac 2", "edge", [("edge", "nginx edge", ":443/tcp TLS 1.2+1.3, HTTP/2"), ("edge", "Load balancer", "round robin -> A, B"),
                                    ("edge", "HTTP redirect", ":80 -> 301 https"), ("edge", "Local CA", "subspace_67 Local Root CA")]),
        (740, V, "Mac 1", "dns", [("dns", "DNS server", "dnsmasq :53/udp+tcp"), ("be", "Backend B", ":3002/tcp HTTP"),
                                   ("cli", "Client + integrator", "failure demos, deliverables"), ("net", "Team bus", ":8099/tcp (HTTP)")]),
    ]
    for x, p, label, accent, rows in macs:
        cx = x + 160
        o.append(f'<line class="line" x1="{cx}" y1="248" x2="{cx}" y2="286" stroke-width="2"/>')
        o.append(t(cx + 8, 272, p["ip"], "muted", 12, mono=True))
        o.append(f'<rect class="box" x="{x}" y="286" width="320" height="300" rx="12"/>')
        o.append(f'<rect class="{accent}" x="{x}" y="286" width="320" height="6" rx="3"/>')
        o.append(t(x + 18, 318, p["name"], size=18, weight="700"))
        o.append(t(x + 302, 318, label, "muted", 12, "end"))
        o.append(t(x + 18, 342, f"{p['ip']}/{p.get('prefix', 19)}  ·  {p.get('interface', 'en0')} ({p.get('network_service', 'Wi-Fi')})", "ink", 12, mono=True))
        o.append(t(x + 18, 360, f"MAC {p.get('mac_address', '?')}", "muted", 12, mono=True))
        y = 386
        for cls, name, detail in rows:
            o.append(f'<rect class="chip" x="{x + 14}" y="{y}" width="292" height="44" rx="8"/>')
            o.append(f'<circle class="{cls}" cx="{x + 30}" cy="{y + 22}" r="6"/>')
            o.append(t(x + 44, y + 18, name, size=13, weight="600"))
            o.append(t(x + 44, y + 35, detail, "muted", 12, mono=True))
            y += 50
    o.append(t(40, 610, "Request path: client -> mac_vachan:53 (DNS over UDP) -> mac_aanya:443 (TCP + TLS + HTTP/2) -> "
               "mac_abhay:3001 or mac_vachan:3002 (plain HTTP on the LAN).", "ink", 12.5))
    o.append(t(40, 630, "Clients only ever use the name app.subspace-67.test; backend IPs are known to the edge alone.", "muted", 12))
    o.append("</svg>")
    return "\n".join(o)


def request_flow():
    W = 1200
    lanes = [(120, "Client", "any Mac (main: mac_abhay)", "cli"),
             (345, "DNS server", f"mac_vachan {V['ip']}:53", "dns"),
             (585, "Edge (nginx)", f"mac_aanya {A['ip']}:443", "edge"),
             (815, "Backend A or B", f"{B['ip']}:3001 / {V['ip']}:3002", "be")]
    steps = [  # from, to, label, layer, group
        (0, 1, "DNS query  A? app.subspace-67.test   (ephemeral port -> 53)", "L7 DNS · L4 UDP · L3 IP", "1 · name -> address"),
        (1, 0, f"answer  {A['ip']}   TTL 60, flag aa (our own zone)", "L7 DNS · L4 UDP", None),
        (0, 2, "SYN   (ephemeral port -> 443, seq x)", "L4 TCP", "2 · TCP 3-way handshake"),
        (2, 0, "SYN-ACK   (seq y, ack x+1)", "L4 TCP", None),
        (0, 2, "ACK   (ack y+1) -> connection established", "L4 TCP", None),
        (0, 2, "ClientHello   SNI app.subspace-67.test, ALPN h2", "TLS (OSI L5-6 · TCP/IP application)", "3 · TLS handshake"),
        (2, 0, "ServerHello, Certificate (signed by our CA), Finished", "TLS", None),
        (0, 2, "Finished -> keys agreed; everything after this is encrypted", "TLS", None),
        (0, 2, "GET /api/status   (HTTP/2 inside TLS)", "L7 HTTP over TLS over TCP", "4 · HTTP request"),
        (2, 3, "round robin: GET /api/status HTTP/1.1 + X-Forwarded-For (plain, LAN)", "L7 reverse proxy / load balancer", "5 · load balancing"),
        (3, 2, "200 OK   X-Backend: A|B   Cache-Control: no-store", "L7 HTTP · L4 TCP", None),
        (2, 0, "HTTP/2 200 (encrypted)   X-Backend shows which backend served it", "L7 HTTP over TLS", "6 · response"),
    ]
    top, dy = 150, 50
    H = top + dy * len(steps) + 150
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" role="img" '
         f'aria-label="request flow for https://app.subspace-67.test/api/status">', STYLE,
         f'<rect class="bg" width="{W}" height="{H}"/>',
         '<defs>' + "".join(
             f'<marker id="ah-{c}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">'
             f'<path d="M0,0 L10,5 L0,10 z" class="{c}"/></marker>' for c in ("cli", "dns", "edge", "be")) + '</defs>']
    o.append(t(40, 40, "One request to https://app.subspace-67.test/api/status, layer by layer", size=22, weight="700"))
    o.append(t(40, 64, "Time flows downwards. Right column: the layer that step belongs to (OSI / TCP-IP).", "muted", 13))
    for x, name, sub, cls in lanes:
        o.append(f'<rect class="box" x="{x - 95}" y="84" width="190" height="46" rx="9"/>')
        o.append(f'<rect class="{cls}" x="{x - 95}" y="84" width="190" height="5" rx="2"/>')
        o.append(t(x, 106, name, size=14, anchor="middle", weight="700"))
        o.append(t(x, 123, sub, "muted", 11, "middle", mono=True))
        o.append(f'<line class="line" x1="{x}" y1="130" x2="{x}" y2="{top + dy * len(steps) + 10}" stroke-width="1.5" stroke-dasharray="4 5"/>')
    o.append(t(1080, 106, "Layer", size=14, anchor="middle", weight="700"))
    for i, (f, to, label, layer, group) in enumerate(steps):
        y = top + dy * i + 20
        x1, x2 = lanes[f][0], lanes[to][0]
        cls = lanes[f][3]
        if group:
            o.append(t(22, y - 22, group, "muted", 11, weight="600"))
        pad = 6 if x2 > x1 else -6
        o.append(f'<line class="s-{cls}" x1="{x1 + pad}" y1="{y}" x2="{x2 - pad}" y2="{y}" stroke-width="2.2" marker-end="url(#ah-{cls})"/>')
        mid = (x1 + x2) / 2
        width = min(len(label) * 6.4 + 14, abs(x2 - x1) + 150)
        o.append(f'<rect class="lbl" x="{mid - width / 2}" y="{y - 21}" width="{width}" height="16" rx="3"/>')
        o.append(t(mid, y - 8, label, "ink", 11.5, "middle"))
        o.append(t(1080, y + 4, layer, "muted", 11, "middle"))
    yb = top + dy * len(steps) + 42
    o.append(t(40, yb, "Under every step: L3 IPv4 packets between 10.7.x.x addresses; L2 Wi-Fi frames between MAC addresses "
               "(found with ARP); L1 radio.", "ink", 12.5))
    o.append(t(40, yb + 22, "TLS ends at the edge: client -> edge is encrypted, edge -> backend is plain HTTP on the LAN "
               "(the edge re-opens a separate TCP connection to the backend).", "ink", 12.5))
    o.append(t(40, yb + 44, "Failure demos: F1/F2 break step 1, F5 breaks step 2 (wrong port -> RST), F3/F4 break step 5 "
               "(F4: TLS still completes, then the edge answers 502).", "muted", 12))
    o.append("</svg>")
    return "\n".join(o)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("topology.svg", topology), ("request_flow.svg", request_flow)):
        with open(os.path.join(OUT, name), "w") as f:
            f.write(fn())
        print("wrote", os.path.join(OUT, name))
