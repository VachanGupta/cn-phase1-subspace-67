#!/usr/bin/env python3
"""Assemble PROJECT_DIR/deliverables/ (brief Section 9) from our own evidence and the peers' collected
evidence (bin/collect_evidence.py), write INDEX.md (one table linking every evidence item by task),
render the Markdown to HTML and zip everything as deliverables_subspace_67_phase1.zip."""
import datetime, fnmatch, glob, hashlib, json, os, re, shutil, subprocess, sys, zipfile

P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(P, "deliverables")
EV = os.path.join(D, "04_evidence")
ZIP = os.path.join(P, "deliverables_subspace_67_phase1.zip")
peers = json.load(open(os.path.join(P, "peers.json")))

TASKS = [("task_A_lan", "Task A · Private LAN (IP, mask, gateway, interface, MAC, ping)"),
         ("task_B_dns", "Task B · Private DNS server (dnsmasq) and clients using it"),
         ("task_C_backends", "Task C · Two backend services (endpoints, X-Backend, bound on the LAN)"),
         ("task_D_load_balancing", "Task D · Edge reverse proxy + round-robin load balancing"),
         ("task_E_tls", "Task E · HTTPS / TLS (certificates, trust, handshake, termination)"),
         ("task_F_caching", "Task F · HTTP caching (Cache-Control, ETag, 304)"),
         ("task_G_protocol_flow", "Task G · Complete protocol flow capture (DNS -> TCP -> TLS -> HTTP)"),
         ("failures", "Failure demonstrations F1-F5")]

# (source root, source prefix, destination under 04_evidence)
MAP = [
    ("share/evidence/mac_vachan", "task_A/", "task_A_lan/mac_vachan/"),
    ("share/evidence/mac_vachan", "task_B_dns/", "task_B_dns/mac_vachan_dns_server/"),
    ("share/evidence/mac_vachan", "task_C_backend_B/", "task_C_backends/mac_vachan_backend_B/"),
    ("share/evidence/mac_vachan", "client_checks/", "task_D_load_balancing/mac_vachan_client/"),
    ("share/evidence/mac_vachan", "failures/", "failures/"),
    ("share/evidence/mac_vachan", "final_gate/", "final_gate/mac_vachan/"),
    ("share/evidence/mac_vachan", "network_health/", "task_A_lan/mac_vachan/network_health/"),
    ("collected/mac_aanya", "task_A/", "task_A_lan/mac_aanya/"),
    ("collected/mac_aanya", "task_B/", "task_B_dns/mac_aanya_client/"),
    ("collected/mac_aanya", "backends/", "task_C_backends/mac_aanya_direct_checks/"),
    ("collected/mac_aanya", "nginx/", "task_D_load_balancing/mac_aanya_edge/"),
    ("collected/mac_aanya", "step5/", "task_D_load_balancing/mac_aanya_edge/gate_check/"),
    ("collected/mac_aanya", "tls/", "task_E_tls/mac_aanya_certificates/"),
    ("collected/mac_aanya", "tls_termination/", "task_E_tls/mac_aanya_tls_termination/"),
    ("collected/mac_aanya", "failures/", "failures/edge_view_mac_aanya/"),
    ("collected/mac_aanya", "final_gate/", "final_gate/mac_aanya/"),
    ("collected/mac_abhay", "task_A/", "task_A_lan/mac_abhay/"),
    ("collected/mac_abhay", "task_B/", "task_B_dns/mac_abhay_client/"),
    ("collected/mac_abhay", "task_C/", "task_C_backends/mac_abhay_backend_A/"),
    ("collected/mac_abhay", "task_D/", "task_D_load_balancing/mac_abhay_client/"),
    ("collected/mac_abhay", "task_E/", "task_E_tls/mac_abhay_client/"),
    ("collected/mac_abhay", "task_F/", "task_F_caching/mac_abhay_client/"),
    ("collected/mac_abhay", "task_G/", "task_G_protocol_flow/"),
    ("collected/mac_abhay", "final_gate/", "final_gate/mac_abhay/"),
]
# single files from this Mac's working folders
EXTRA = [
    ("evidence_work/backend_local_test.txt", "task_C_backends/mac_vachan_backend_B/unit_test_backend_endpoints.txt"),
    ("evidence_work/supervisor_local_test.txt", "task_C_backends/mac_vachan_backend_B/unit_test_supervisor.txt"),
    ("evidence_work/dnsmasq_nonroot_attempt.txt", "task_B_dns/mac_vachan_dns_server/troubleshooting/dnsmasq_nonroot_attempt.txt"),
    ("evidence_work/dnsmasq.conf.first_attempt_desktop_paths", "task_B_dns/mac_vachan_dns_server/troubleshooting/dnsmasq.conf.first_attempt_desktop_paths"),
    ("logs/sudo_01.log", "task_B_dns/mac_vachan_dns_server/troubleshooting/sudo_01_root_batch.log"),
    ("evidence_work/dns_troubleshooting.md", "task_B_dns/mac_vachan_dns_server/troubleshooting/README.md"),
    ("evidence_work/failures/F4_tls_session_keys.log", "failures/F4_both_backends_down/F4_tls_session_keys.log"),
    ("logs/sudo_02.log", "failures/sudo_02_failure_run.log"),
    ("run/failure_times.txt", "failures/failure_time_windows.txt"),
]


def cp(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def files_under(root):
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn in (".DS_Store",) or fn.endswith(".tmp"):
                continue
            yield os.path.relpath(os.path.join(dp, fn), root)


def build_tree():
    if os.path.isdir(EV):
        shutil.rmtree(EV)
    placed, leftovers = [], []
    for root, prefix, dest in MAP:
        r = os.path.join(P, root)
        if not os.path.isdir(r):
            continue
        for rel in files_under(r):
            if rel.startswith(prefix):
                cp(os.path.join(r, rel), os.path.join(EV, dest, rel[len(prefix):]))
                placed.append((root, rel))
    for src, dst in EXTRA:
        if os.path.exists(os.path.join(P, src)):
            cp(os.path.join(P, src), os.path.join(EV, dst))
    # peers' other files: README -> 04_evidence, LEARN -> 06_viva, configs/scripts -> 02_configs
    for name in ("mac_aanya", "mac_abhay"):
        r = os.path.join(P, "collected", name)
        if not os.path.isdir(r):
            continue
        done = {rel for root, rel in placed if root == f"collected/{name}"}
        for rel in files_under(r):
            if rel in done or rel in ("MANIFEST.txt", "COLLECTED.txt"):
                continue
            src = os.path.join(r, rel)
            if rel.startswith("LEARN_"):
                cp(src, os.path.join(D, "06_viva", rel))
            elif rel.lower() == "readme.md":
                cp(src, os.path.join(EV, f"README_{name}.md"))
            elif rel.startswith("configs/"):
                cp(src, os.path.join(D, "02_configs", "nginx" if name == "mac_aanya" else name, rel[len("configs/"):]))
            elif rel.startswith("scripts/"):
                cp(src, os.path.join(D, "02_configs", "scripts", name, rel[len("scripts/"):]))
            else:
                cp(src, os.path.join(EV, "other", name, rel))
                leftovers.append(f"{name}/{rel}")
        for extra in ("MANIFEST.txt", "COLLECTED.txt"):
            if os.path.exists(os.path.join(r, extra)):
                cp(os.path.join(r, extra), os.path.join(EV, "_receipts", f"{name}_{extra}"))
    return leftovers


def build_configs_and_source():
    c = os.path.join(D, "02_configs")
    cp(os.path.join(P, "configs", "dnsmasq.conf"), os.path.join(c, "dnsmasq", "dnsmasq.conf"))
    cp(os.path.join(P, "share", "backend", "README.md"), os.path.join(c, "backend", "backend_launch.md"))
    for f in ("README_tls.md", "ca.cnf", "server.cnf"):
        s = os.path.join(P, "collected", "mac_aanya", "tls", f)
        if os.path.exists(s):
            cp(s, os.path.join(c, "tls", f))
    s = os.path.join(P, "collected", "mac_aanya", "nginx", "nginx_T.txt")
    if os.path.exists(s):
        cp(s, os.path.join(c, "nginx", "nginx_T.txt"))
    mine = os.path.join(c, "scripts", "mac_vachan")
    for f in ("start.sh", "stop.sh", "restore_network.sh"):
        cp(os.path.join(P, f), os.path.join(mine, f))
    for f in glob.glob(os.path.join(P, "sudo", "*.sh")):
        cp(f, os.path.join(mine, "sudo", os.path.basename(f)))
    for f in glob.glob(os.path.join(P, "bin", "*")):
        if f.endswith((".py", ".sh")) and "emergency" not in f:
            cp(f, os.path.join(mine, "bin", os.path.basename(f)))
    b = os.path.join(D, "03_backend_source")
    for f in ("backend.py", "supervisor.py", "README.md", "SHA256SUMS"):
        cp(os.path.join(P, "share", "backend", f), os.path.join(b, f))
    cp(os.path.join(P, "bin", "start_backend_B.sh"), os.path.join(b, "helpers", "start_backend_B.sh"))
    cp(os.path.join(P, "LEARN_mac_vachan.md"), os.path.join(D, "06_viva", "LEARN_mac_vachan.md"))


def build_viva():
    """06_viva/viva_guide.md = one whole-system guide: overview + the three LEARN files + ~45 Q&A."""
    v = os.path.join(D, "06_viva")
    os.makedirs(v, exist_ok=True)
    parts = [("mac_vachan", "Mac 1 · DNS server + Backend B + client + integrator"),
             ("mac_aanya", "Mac 2 · edge: nginx reverse proxy, load balancer, TLS termination, local CA"),
             ("mac_abhay", "Mac 3 · Backend A + main test client + packet captures")]
    out = ["# subspace_67 · viva guide (Phase 1, whole system)", "",
           "Every member must be able to explain **any** part, not just their own. Read the overview, then all "
           "three machine sections, then test yourself with the questions at the end. Answers must come from "
           "understanding, not notes.", "",
           "## The whole system in 60 seconds", "",
           "1. **DNS** (UDP 53): the client asks mac_vachan's dnsmasq (10.7.23.136) for `app.subspace-67.test` "
           "and gets the edge IP 10.7.19.193 (TTL 60).",
           "2. **TCP** (443): SYN, SYN-ACK, ACK to the edge.",
           "3. **TLS**: nginx presents a certificate for app.subspace-67.test signed by our own CA "
           "(\"subspace_67 Local Root CA\", trusted in every Mac's System keychain), so there is no warning.",
           "4. **HTTP/2** inside TLS: `GET /api/status`.",
           "5. **Load balancer**: nginx round-robins to Backend A (mac_abhay :3001) or B (mac_vachan :3002) "
           "over plain HTTP on the LAN, adding X-Forwarded-For.",
           "6. The backend answers with `X-Backend: A|B`; nginx relays it back through TLS.",
           "",
           "Where things break (failure demos): wrong DNS server -> no name (F1); wrong record -> wrong host (F2); "
           "one backend down -> failover (F3); both down -> TLS ok then 502 (F4); wrong port -> RST (F5).", ""]
    for name, title in parts:
        f = os.path.join(v, f"LEARN_{name}.md")
        if not os.path.exists(f):
            out += [f"## {title}", "", f"*(LEARN_{name}.md not received yet)*", ""]
            continue
        body = open(f).read().split("\n")
        if body and body[0].startswith("# "):
            body = body[1:]
        demoted = []
        in_code = False
        for line in body:
            if line.startswith("```"):
                in_code = not in_code
            if not in_code and re.match(r"^#{1,5} ", line):
                line = "#" + line
            demoted.append(line)
        out += [f"## {title} ({name})", ""] + demoted + [""]
    q = os.path.join(P, "evidence_work", "viva_questions.md")
    if os.path.exists(q):
        out += open(q).read().split("\n")
    with open(os.path.join(v, "viva_guide.md"), "w") as fh:
        fh.write("\n".join(out) + "\n")


DESC = {  # curated descriptions (path glob under 04_evidence -> text)
    "task_A_lan/mac_vachan/task_A_summary.md": "IP/mask/gateway/interface/MAC table + what /19 means",
    "task_A_lan/mac_vachan/task_A_commands_output.txt": "ifconfig en0, route -n get default, networksetup -getinfo, ARP",
    "task_A_lan/*/ping_*": "ping (0% loss, TTL 64 = same subnet) + ARP entry of the peer",
    "task_B_dns/mac_vachan_dns_server/dig_nslookup.txt": "dig/nslookup via our server: app/api -> edge, SERVER 10.7.23.136, flag aa, NXDOMAIN for unknown names, internet names forwarded",
    "task_B_dns/mac_vachan_dns_server/dnsmasq_log_clients.txt": "dnsmasq log lines proving queries arrived FROM mac_aanya and mac_abhay (client IP/port)",
    "task_B_dns/mac_vachan_dns_server/scutil_dns.txt": "scutil --dns: resolver #1 = 10.7.23.136",
    "task_B_dns/mac_vachan_dns_server/dnsmasq_service_and_config.txt": "root Homebrew service + the exact config it loads",
    "task_B_dns/mac_vachan_dns_server/troubleshooting/*": "how dnsmasq got running on macOS (non-root bind refused, TCC exit code 3, fix)",
    "task_C_backends/mac_vachan_backend_B/backend_B_log_from_edge.txt": "Backend B log: every request arrives from the EDGE 10.7.19.193, client only in X-Forwarded-For",
    "task_C_backends/mac_vachan_backend_B/endpoints_headers.txt": "Backend B /, /api/status, /api/cache-demo, 304, 404 - all with X-Backend: B",
    "task_C_backends/mac_vachan_backend_B/lsof_process.txt": "lsof: *:3002 LISTEN (all interfaces, not 127.0.0.1)",
    "task_C_backends/mac_vachan_backend_B/unit_test_*": "local tests before publishing the shared code",
    "task_D_load_balancing/mac_vachan_client/*": "from mac_vachan by name: TLS verify ok + X-Backend alternating",
    "task_A_lan/mac_vachan/network_health/*": "why mac_vachan was slow: Content Caching bulk traffic -> Wi-Fi queueing (bufferbloat), not DNS/TCP/TLS",
    "task_A_lan/mac_aanya/task_A_commands.txt": "ifconfig en0, route -n get default, networksetup -getinfo Wi-Fi on the edge",
    "task_A_lan/mac_aanya/task_A_summary.txt": "edge identity: 10.7.19.193/19, gateway 10.7.0.1, en0, MAC (private + hardware)",
    "task_B_dns/mac_aanya_client/dns_settings.txt": "networksetup -getdnsservers = 10.7.23.136; scutil --dns resolver #1 = mac_vachan",
    "task_C_backends/mac_aanya_direct_checks/*": "edge -> each backend directly (http://<peer>:300x/api/status) before nginx is involved",
    "task_D_load_balancing/mac_aanya_edge/access_log_excerpt.txt": "edge access log: upstream alternates 10.7.1.136:3001 / 10.7.23.136:3002, x_backend A/B, TLSv1.3, 304s",
    "task_D_load_balancing/mac_aanya_edge/nginx_T.txt": "nginx -T: the full effective config (upstream, zone, TLS, proxy headers, failover)",
    "task_D_load_balancing/mac_aanya_edge/gate_check/step5_verification.txt": "gate from the edge: dig via mac_vachan, HTTPS no -k, 10x B A B A, h1.1+h2, 301, 304 from A and B",
    "task_D_load_balancing/mac_aanya_edge/gate_check/root_batch_log.txt": "the edge's one sudo batch: DNS -> 10.7.23.136, flush, CA trusted",
    "task_E_tls/mac_aanya_certificates/s_client_tls12.txt": "openssl s_client TLS 1.2: chain depth 0/1, Verify return code 0 (ok)",
    "task_E_tls/mac_aanya_certificates/s_client_tls13.txt": "openssl s_client TLS 1.3 (X25519MLKEM768): Verify return code 0 (ok)",
    "task_E_tls/mac_aanya_certificates/s_client_wrong_name.txt": "wrong SNI/name -> hostname mismatch (the SAN check really happens)",
    "task_E_tls/mac_aanya_certificates/chain_verification.txt": "openssl verify + macOS security verify-cert; name constraint rejects evil.example.com",
    "task_E_tls/mac_aanya_certificates/ca_cert_details.txt": "CA: CA:TRUE pathlen:0, keyCertSign/cRLSign, nameConstraints subspace-67.test",
    "task_E_tls/mac_aanya_certificates/server_cert_details.txt": "leaf: CN/SAN app+api.subspace-67.test, EKU serverAuth, 397 days",
    "task_E_tls/mac_aanya_certificates/README_tls.md": "how the CA and certificate were made, field by field",
    "task_E_tls/mac_aanya_certificates/*.cnf": "openssl config used to build the certificate",
    "task_E_tls/mac_aanya_tls_termination/edge_tls_termination.pcapng": "TLS TERMINATION: client leg encrypted (lo0), same request in plain HTTP to the backend (en0)",
    "task_E_tls/mac_aanya_tls_termination/tshark_client_leg_tls.txt": "client leg: ClientHello/ServerHello/Certificate (TLS 1.2), Application Data encrypted",
    "task_E_tls/mac_aanya_tls_termination/tshark_backend_leg_http.txt": "backend leg: plain GET /api/status + 200 with X-Backend visible",
    "task_E_tls/mac_aanya_tls_termination/tshark_all_packets.txt": "every packet of the termination capture with interface/process",
    "task_E_tls/mac_aanya_tls_termination/tshark_dns.txt": "the edge's own DNS query to mac_vachan",
    "task_E_tls/mac_aanya_tls_termination/*": "TLS termination capture support file",
    "failures/*/commands_output.txt": "exact commands + full output: break -> observe -> restore -> healthy check",
    "failures/*/README.md": "observation, layer, why (the explanation)",
    "failures/*_tshark.txt": "tshark text export of the capture, with packet numbers",
    "failures/F4_both_backends_down/F4_tls_session_keys.log": "TLS session keys of the one decrypted F4 connection (Wireshark: TLS > (Pre)-Master-Secret log)",
    "*.pcapng": "packet capture - open in Wireshark",
}


def describe(rel, path):
    for pat, text in DESC.items():
        if fnmatch.fnmatch(rel, pat):
            return text
    if rel.endswith((".txt", ".md", ".log", ".conf", ".cnf")):
        try:
            with open(path, errors="replace") as f:
                for line in f:
                    s = line.strip()
                    if s and s.startswith("#"):
                        s = re.sub(r"^#+\s*", "", s)
                        s = re.sub(r"\s*-\s*captured on .*$", "", s)
                        s = re.sub(r"\(captured .*?\)", "", s)
                        return s[:140]
                    if s:
                        break
        except OSError:
            pass
    base = os.path.basename(rel)
    return re.sub(r"[_-]+", " ", os.path.splitext(base)[0])


def mac_of(rel):
    m = re.search(r"(mac_vachan|mac_aanya|mac_abhay)", rel)
    if m:
        return m.group(1)
    if rel.startswith("failures/"):
        return "mac_vachan"
    if rel.startswith("task_G_protocol_flow/"):
        return "mac_abhay"
    return ""


def first(patterns):
    for pat in patterns:
        hits = sorted(glob.glob(os.path.join(EV, pat), recursive=True))
        if hits:
            rel = os.path.relpath(hits[0], D)
            return rel + ("/" if os.path.isdir(hits[0]) else "")
    return None


def write_index():
    rows = []
    for key, title in TASKS + [("final_gate", "Final gate check (all three Macs)"), ("other", "Other evidence"), ("_receipts", "Collection receipts (sha256 of every file pulled from the peers)")]:
        folder = os.path.join(EV, key)
        if not os.path.isdir(folder):
            continue
        rows.append(f"| **{title}** | | | |")
        for rel in sorted(files_under(folder)):
            full = os.path.join(key, rel)
            link = f"04_evidence/{full}"
            rows.append(f"| {'' } | {mac_of(full)} | [{rel}]({link.replace(' ', '%20')}) | {describe(full, os.path.join(EV, full)).replace('|', '/')} |")
    for readme in sorted(glob.glob(os.path.join(EV, "README_*.md"))):
        rows.append(f"| **Per-Mac evidence README** | {os.path.basename(readme)[7:-3]} | [{os.path.basename(readme)}](04_evidence/{os.path.basename(readme)}) | that Mac's own walkthrough of its evidence |")

    q = [
        ("Topology diagram, IP/service table, request-flow diagram", "01_architecture/architecture.html"),
        ("dig from a client: name -> edge IP via our DNS server", first(["task_B_dns/mac_abhay_client/*dig*", "task_B_dns/mac_abhay_client/*", "task_B_dns/mac_vachan_dns_server/dig_nslookup.txt"])),
        ("Proof the other Macs really query our DNS server", "04_evidence/task_B_dns/mac_vachan_dns_server/dnsmasq_log_clients.txt"),
        ("Backend endpoints + X-Backend header", "04_evidence/task_C_backends/mac_vachan_backend_B/endpoints_headers.txt"),
        ("Round robin: repeated requests alternate A/B", first(["task_D_load_balancing/mac_abhay_client/*", "task_D_load_balancing/mac_vachan_client/*"])),
        ("Edge access log: upstream alternates", first(["task_D_load_balancing/mac_aanya_edge/access_log_excerpt.txt"])),
        ("HTTPS with no -k: curl -v 'SSL certificate verify ok'", first(["task_E_tls/mac_abhay_client/*curl*", "task_E_tls/mac_abhay_client/*"])),
        ("openssl s_client: chain + Verify return code 0", first(["task_E_tls/mac_aanya_certificates/s_client_tls12.txt"])),
        ("TLS termination proof (encrypted client leg, plain backend leg)", first(["task_E_tls/mac_aanya_tls_termination/edge_tls_termination.pcapng"])),
        ("Caching: Cache-Control, ETag headers", first(["task_F_caching/mac_abhay_client/01_head_cache_headers.txt", "task_F_caching/mac_abhay_client/*"])),
        ("Caching: conditional GET -> 304 Not Modified (from both backends)", first(["task_F_caching/mac_abhay_client/04_304_from_both_backends.txt", "task_F_caching/mac_abhay_client/02_conditional_get_304.txt"])),
        ("Wireshark: DNS -> TCP handshake -> TLS 1.2 (Certificate visible)", first(["task_G_protocol_flow/task_G_tls12.pcapng", "task_G_protocol_flow/**/*tls12*.pcapng"])),
        ("Wireshark: the same flow in TLS 1.3 (Certificate encrypted)", first(["task_G_protocol_flow/task_G_tls13.pcapng"])),
        ("tshark exports with packet numbers (DNS, handshake, TLS, ports)", first(["task_G_protocol_flow/task_G_tls12_exports/"])),
        ("Packet-by-packet explanation of the capture", first(["task_G_protocol_flow/**/*explained*"])),
        ("F1 wrong DNS server", "04_evidence/failures/F1_wrong_dns_server/README.md"),
        ("F2 DNS record points to the wrong IP", "04_evidence/failures/F2_dns_record_wrong_ip/README.md"),
        ("F3 one backend stopped (failover)", "04_evidence/failures/F3_one_backend_down/README.md"),
        ("F4 both backends stopped (TLS ok, then 502)", "04_evidence/failures/F4_both_backends_down/README.md"),
        ("F5 wrong destination port (SYN -> RST)", "04_evidence/failures/F5_wrong_port/README.md"),
        ("dnsmasq / nginx configs, TLS setup notes, backend launch", "02_configs/README.md"),
        ("Backend source code (identical on A and B)", "03_backend_source/README.md"),
        ("Demo runbook (brief Section 8, steps 1-8)", "05_demo/runbook.html"),
        ("Viva guide (whole system + ~45 Q&A)", "06_viva/viva_guide.html"),
    ]
    now = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    ips = ", ".join(f"{n} {peers[n]['ip']}" for n in ("mac_vachan", "mac_aanya", "mac_abhay"))
    out = [f"# subspace_67 · Phase 1 deliverables · INDEX", "",
           f"Team **subspace_67** · domain **app.subspace-67.test** · {ips} · built {now}.", "",
           "**Folders:** [01_architecture](01_architecture/architecture.html) · [02_configs](02_configs/README.md) · "
           "[03_backend_source](03_backend_source/README.md) · [04_evidence](#evidence) · [05_demo](05_demo/runbook.html) · "
           "[06_viva](06_viva/viva_guide.html)", "",
           "## Find it in 30 seconds", "", "| I want to see... | Open |", "|---|---|"]
    for text, link in q:
        if link:
            out.append(f"| {text} | [{link}]({link}) |")
    out += ["", "## Evidence", "",
            "One table, grouped by task. Every text file holds the exact command (`$ ...`) and its full output;",
            "every `.pcapng` has tshark text exports next to it. Mac = the machine the evidence was captured on.", "",
            "| Task | Mac | File | What it shows |", "|---|---|---|---|"] + rows + [""]
    with open(os.path.join(D, "INDEX.md"), "w") as f:
        f.write("\n".join(out))


def render():
    mds = [os.path.join(D, "INDEX.md"), os.path.join(D, "01_architecture", "architecture.md"),
           os.path.join(D, "05_demo", "runbook.md"), os.path.join(D, "06_viva", "viva_guide.md"),
           os.path.join(D, "02_configs", "README.md"), os.path.join(D, "03_backend_source", "README.md")]
    mds += glob.glob(os.path.join(EV, "failures", "F*", "README.md"))
    mds += glob.glob(os.path.join(EV, "README_*.md"))
    subprocess.run([sys.executable, os.path.join(P, "bin", "md2html.py")] + [m for m in mds if os.path.exists(m)],
                   check=True, capture_output=True)
    chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    html_arch = os.path.join(D, "01_architecture", "architecture.html")
    if os.path.exists(chrome):                  # PDF version of the architecture document
        subprocess.run([chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        "--print-to-pdf=" + html_arch[:-5] + ".pdf", "file://" + html_arch],
                       capture_output=True, timeout=120)


def make_zip():
    if os.path.exists(ZIP):
        os.remove(ZIP)
    n = 0
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in sorted(files_under(D)):
            z.write(os.path.join(D, rel), os.path.join("deliverables_subspace_67_phase1", rel))
            n += 1
    return n


if __name__ == "__main__":
    left = build_tree()
    build_configs_and_source()
    build_viva()
    write_index()
    render()
    n = make_zip()
    print(f"deliverables built: {n} files zipped into {ZIP} ({os.path.getsize(ZIP) // 1024} KB)")
    if left:
        print("unmapped peer files placed under 04_evidence/other/:", *left, sep="\n  ")
