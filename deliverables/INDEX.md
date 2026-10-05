# subspace_67 · Phase 1 deliverables · INDEX

Team **subspace_67** · domain **app.subspace-67.test** · mac_vachan 10.7.23.136, mac_aanya 10.7.19.193, mac_abhay 10.7.1.136 · built 2026-09-30 14:16 IST.

**Folders:** [01_architecture](01_architecture/architecture.html) · [02_configs](02_configs/README.md) · [03_backend_source](03_backend_source/README.md) · [04_evidence](#evidence) · [05_demo](05_demo/runbook.html) · [06_viva](06_viva/viva_guide.html)

## Find it in 30 seconds

| I want to see... | Open |
|---|---|
| Topology diagram, IP/service table, request-flow diagram | [01_architecture/architecture.html](01_architecture/architecture.html) |
| dig from a client: name -> edge IP via our DNS server | [04_evidence/task_B_dns/mac_abhay_client/04_dig_app.txt](04_evidence/task_B_dns/mac_abhay_client/04_dig_app.txt) |
| Proof the other Macs really query our DNS server | [04_evidence/task_B_dns/mac_vachan_dns_server/dnsmasq_log_clients.txt](04_evidence/task_B_dns/mac_vachan_dns_server/dnsmasq_log_clients.txt) |
| Backend endpoints + X-Backend header | [04_evidence/task_C_backends/mac_vachan_backend_B/endpoints_headers.txt](04_evidence/task_C_backends/mac_vachan_backend_B/endpoints_headers.txt) |
| Round robin: repeated requests alternate A/B | [04_evidence/task_D_load_balancing/mac_abhay_client/01_ten_requests_round_robin.txt](04_evidence/task_D_load_balancing/mac_abhay_client/01_ten_requests_round_robin.txt) |
| Edge access log: upstream alternates | [04_evidence/task_D_load_balancing/mac_aanya_edge/access_log_excerpt.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/access_log_excerpt.txt) |
| HTTPS with no -k: curl -v 'SSL certificate verify ok' | [04_evidence/task_E_tls/mac_abhay_client/01_curl_v_no_k.txt](04_evidence/task_E_tls/mac_abhay_client/01_curl_v_no_k.txt) |
| openssl s_client: chain + Verify return code 0 | [04_evidence/task_E_tls/mac_aanya_certificates/s_client_tls12.txt](04_evidence/task_E_tls/mac_aanya_certificates/s_client_tls12.txt) |
| TLS termination proof (encrypted client leg, plain backend leg) | [04_evidence/task_E_tls/mac_aanya_tls_termination/edge_tls_termination.pcapng](04_evidence/task_E_tls/mac_aanya_tls_termination/edge_tls_termination.pcapng) |
| Caching: Cache-Control, ETag headers | [04_evidence/task_F_caching/mac_abhay_client/01_head_cache_headers.txt](04_evidence/task_F_caching/mac_abhay_client/01_head_cache_headers.txt) |
| Caching: conditional GET -> 304 Not Modified (from both backends) | [04_evidence/task_F_caching/mac_abhay_client/04_304_from_both_backends.txt](04_evidence/task_F_caching/mac_abhay_client/04_304_from_both_backends.txt) |
| Wireshark: DNS -> TCP handshake -> TLS 1.2 (Certificate visible) | [04_evidence/task_G_protocol_flow/task_G_tls12.pcapng](04_evidence/task_G_protocol_flow/task_G_tls12.pcapng) |
| Wireshark: the same flow in TLS 1.3 (Certificate encrypted) | [04_evidence/task_G_protocol_flow/task_G_tls13.pcapng](04_evidence/task_G_protocol_flow/task_G_tls13.pcapng) |
| tshark exports with packet numbers (DNS, handshake, TLS, ports) | [04_evidence/task_G_protocol_flow/task_G_tls12_exports/](04_evidence/task_G_protocol_flow/task_G_tls12_exports/) |
| Packet-by-packet explanation of the capture | [04_evidence/task_G_protocol_flow/task_G_explained.md](04_evidence/task_G_protocol_flow/task_G_explained.md) |
| F1 wrong DNS server | [04_evidence/failures/F1_wrong_dns_server/README.md](04_evidence/failures/F1_wrong_dns_server/README.md) |
| F2 DNS record points to the wrong IP | [04_evidence/failures/F2_dns_record_wrong_ip/README.md](04_evidence/failures/F2_dns_record_wrong_ip/README.md) |
| F3 one backend stopped (failover) | [04_evidence/failures/F3_one_backend_down/README.md](04_evidence/failures/F3_one_backend_down/README.md) |
| F4 both backends stopped (TLS ok, then 502) | [04_evidence/failures/F4_both_backends_down/README.md](04_evidence/failures/F4_both_backends_down/README.md) |
| F5 wrong destination port (SYN -> RST) | [04_evidence/failures/F5_wrong_port/README.md](04_evidence/failures/F5_wrong_port/README.md) |
| dnsmasq / nginx configs, TLS setup notes, backend launch | [02_configs/README.md](02_configs/README.md) |
| Backend source code (identical on A and B) | [03_backend_source/README.md](03_backend_source/README.md) |
| Demo runbook (brief Section 8, steps 1-8) | [05_demo/runbook.html](05_demo/runbook.html) |
| Viva guide (whole system + ~45 Q&A) | [06_viva/viva_guide.html](06_viva/viva_guide.html) |

## Evidence

One table, grouped by task. Every text file holds the exact command (`$ ...`) and its full output;
every `.pcapng` has tshark text exports next to it. Mac = the machine the evidence was captured on.

| Task | Mac | File | What it shows |
|---|---|---|---|
| **Task A · Private LAN (IP, mask, gateway, interface, MAC, ping)** | | | |
|  | mac_aanya | [mac_aanya/ping_mac_abhay.txt](04_evidence/task_A_lan/mac_aanya/ping_mac_abhay.txt) | ping (0% loss, TTL 64 = same subnet) + ARP entry of the peer |
|  | mac_aanya | [mac_aanya/ping_mac_vachan.txt](04_evidence/task_A_lan/mac_aanya/ping_mac_vachan.txt) | ping (0% loss, TTL 64 = same subnet) + ARP entry of the peer |
|  | mac_aanya | [mac_aanya/task_A_commands.txt](04_evidence/task_A_lan/mac_aanya/task_A_commands.txt) | ifconfig en0, route -n get default, networksetup -getinfo Wi-Fi on the edge |
|  | mac_aanya | [mac_aanya/task_A_summary.txt](04_evidence/task_A_lan/mac_aanya/task_A_summary.txt) | edge identity: 10.7.19.193/19, gateway 10.7.0.1, en0, MAC (private + hardware) |
|  | mac_abhay | [mac_abhay/01_ifconfig_en0.txt](04_evidence/task_A_lan/mac_abhay/01_ifconfig_en0.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/02_ifconfig_all.txt](04_evidence/task_A_lan/mac_abhay/02_ifconfig_all.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/03_route_default.txt](04_evidence/task_A_lan/mac_abhay/03_route_default.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/04_networksetup_getinfo.txt](04_evidence/task_A_lan/mac_abhay/04_networksetup_getinfo.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/05_hardware_ports.txt](04_evidence/task_A_lan/mac_abhay/05_hardware_ports.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/06_ipconfig.txt](04_evidence/task_A_lan/mac_abhay/06_ipconfig.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/07_routing_table.txt](04_evidence/task_A_lan/mac_abhay/07_routing_table.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/08_dns_before_changes.txt](04_evidence/task_A_lan/mac_abhay/08_dns_before_changes.txt) | 2026-09-30 13:21:17 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/09_ping_mac_aanya.txt](04_evidence/task_A_lan/mac_abhay/09_ping_mac_aanya.txt) | 2026-09-30 13:24:53 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/10_ping_mac_vachan.txt](04_evidence/task_A_lan/mac_abhay/10_ping_mac_vachan.txt) | 2026-09-30 13:26:18 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay/NOTES.md](04_evidence/task_A_lan/mac_abhay/NOTES.md) | Task A: mac_abhay network identity and reachability of the peers |
|  | mac_vachan | [mac_vachan/network_health/latency_diagnosis_before.txt](04_evidence/task_A_lan/mac_vachan/network_health/latency_diagnosis_before.txt) | why mac_vachan was slow: Content Caching bulk traffic -> Wi-Fi queueing (bufferbloat), not DNS/TCP/TLS |
|  | mac_vachan | [mac_vachan/ping_mac_aanya.txt](04_evidence/task_A_lan/mac_vachan/ping_mac_aanya.txt) | ping (0% loss, TTL 64 = same subnet) + ARP entry of the peer |
|  | mac_vachan | [mac_vachan/ping_mac_abhay.txt](04_evidence/task_A_lan/mac_vachan/ping_mac_abhay.txt) | ping (0% loss, TTL 64 = same subnet) + ARP entry of the peer |
|  | mac_vachan | [mac_vachan/task_A_commands_output.txt](04_evidence/task_A_lan/mac_vachan/task_A_commands_output.txt) | ifconfig en0, route -n get default, networksetup -getinfo, ARP |
|  | mac_vachan | [mac_vachan/task_A_summary.md](04_evidence/task_A_lan/mac_vachan/task_A_summary.md) | IP/mask/gateway/interface/MAC table + what /19 means |
| **Task B · Private DNS server (dnsmasq) and clients using it** | | | |
|  | mac_aanya | [mac_aanya_client/dns_settings.txt](04_evidence/task_B_dns/mac_aanya_client/dns_settings.txt) | networksetup -getdnsservers = 10.7.23.136; scutil --dns resolver #1 = mac_vachan |
|  | mac_abhay | [mac_abhay_client/00_check.txt](04_evidence/task_B_dns/mac_abhay_client/00_check.txt) | 00 check |
|  | mac_abhay | [mac_abhay_client/01_dns_servers.txt](04_evidence/task_B_dns/mac_abhay_client/01_dns_servers.txt) | 2026-09-30 13:51:44 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/02_scutil_dns_excerpt.txt](04_evidence/task_B_dns/mac_abhay_client/02_scutil_dns_excerpt.txt) | 2026-09-30 13:52:19 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/03_resolv_conf.txt](04_evidence/task_B_dns/mac_abhay_client/03_resolv_conf.txt) | 2026-09-30 13:51:44 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/04_dig_app.txt](04_evidence/task_B_dns/mac_abhay_client/04_dig_app.txt) | 2026-09-30 13:51:44 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/05_dig_api.txt](04_evidence/task_B_dns/mac_abhay_client/05_dig_api.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/06_nslookup_app.txt](04_evidence/task_B_dns/mac_abhay_client/06_nslookup_app.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/07_dig_tcp53.txt](04_evidence/task_B_dns/mac_abhay_client/07_dig_tcp53.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/08_system_resolver.txt](04_evidence/task_B_dns/mac_abhay_client/08_system_resolver.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/09_outside_name_forwarded.txt](04_evidence/task_B_dns/mac_abhay_client/09_outside_name_forwarded.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/NOTES.md](04_evidence/task_B_dns/mac_abhay_client/NOTES.md) | Task B: this Mac resolves names through OUR DNS server (mac_vachan) |
|  | mac_vachan | [mac_vachan_dns_server/dig_nslookup.txt](04_evidence/task_B_dns/mac_vachan_dns_server/dig_nslookup.txt) | dig/nslookup via our server: app/api -> edge, SERVER 10.7.23.136, flag aa, NXDOMAIN for unknown names, internet names forwarded |
|  | mac_vachan | [mac_vachan_dns_server/dnsmasq_log_clients.txt](04_evidence/task_B_dns/mac_vachan_dns_server/dnsmasq_log_clients.txt) | dnsmasq log lines proving queries arrived FROM mac_aanya and mac_abhay (client IP/port) |
|  | mac_vachan | [mac_vachan_dns_server/dnsmasq_service_and_config.txt](04_evidence/task_B_dns/mac_vachan_dns_server/dnsmasq_service_and_config.txt) | root Homebrew service + the exact config it loads |
|  | mac_vachan | [mac_vachan_dns_server/scutil_dns.txt](04_evidence/task_B_dns/mac_vachan_dns_server/scutil_dns.txt) | scutil --dns: resolver #1 = 10.7.23.136 |
|  | mac_vachan | [mac_vachan_dns_server/troubleshooting/README.md](04_evidence/task_B_dns/mac_vachan_dns_server/troubleshooting/README.md) | how dnsmasq got running on macOS (non-root bind refused, TCC exit code 3, fix) |
|  | mac_vachan | [mac_vachan_dns_server/troubleshooting/dnsmasq.conf.first_attempt_desktop_paths](04_evidence/task_B_dns/mac_vachan_dns_server/troubleshooting/dnsmasq.conf.first_attempt_desktop_paths) | how dnsmasq got running on macOS (non-root bind refused, TCC exit code 3, fix) |
|  | mac_vachan | [mac_vachan_dns_server/troubleshooting/dnsmasq_nonroot_attempt.txt](04_evidence/task_B_dns/mac_vachan_dns_server/troubleshooting/dnsmasq_nonroot_attempt.txt) | how dnsmasq got running on macOS (non-root bind refused, TCC exit code 3, fix) |
|  | mac_vachan | [mac_vachan_dns_server/troubleshooting/sudo_01_root_batch.log](04_evidence/task_B_dns/mac_vachan_dns_server/troubleshooting/sudo_01_root_batch.log) | how dnsmasq got running on macOS (non-root bind refused, TCC exit code 3, fix) |
| **Task C · Two backend services (endpoints, X-Backend, bound on the LAN)** | | | |
|  | mac_aanya | [mac_aanya_direct_checks/backends_direct_check.txt](04_evidence/task_C_backends/mac_aanya_direct_checks/backends_direct_check.txt) | edge -> each backend directly (http://<peer>:300x/api/status) before nginx is involved |
|  | mac_abhay | [mac_abhay_backend_A/00_backend_code_identical.txt](04_evidence/task_C_backends/mac_abhay_backend_A/00_backend_code_identical.txt) | 2026-09-30 13:26:30 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/01_lsof_listen_3001.txt](04_evidence/task_C_backends/mac_abhay_backend_A/01_lsof_listen_3001.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/02_direct_root.txt](04_evidence/task_C_backends/mac_abhay_backend_A/02_direct_root.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/03_direct_api_status.txt](04_evidence/task_C_backends/mac_abhay_backend_A/03_direct_api_status.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/04_direct_head_status.txt](04_evidence/task_C_backends/mac_abhay_backend_A/04_direct_head_status.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/05_direct_cache_demo.txt](04_evidence/task_C_backends/mac_abhay_backend_A/05_direct_cache_demo.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/06_direct_404.txt](04_evidence/task_C_backends/mac_abhay_backend_A/06_direct_404.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/07_supervisor_and_processes.txt](04_evidence/task_C_backends/mac_abhay_backend_A/07_supervisor_and_processes.txt) | 2026-09-30 13:26:23 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/08_via_edge_requests.txt](04_evidence/task_C_backends/mac_abhay_backend_A/08_via_edge_requests.txt) | 2026-09-30 13:51:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/09_backend_A_log_edge_requests.txt](04_evidence/task_C_backends/mac_abhay_backend_A/09_backend_A_log_edge_requests.txt) | 2026-09-30 13:51:49 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/10_established_connections_3001.txt](04_evidence/task_C_backends/mac_abhay_backend_A/10_established_connections_3001.txt) | 2026-09-30 13:51:49 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/11_supervisor_during_failures.txt](04_evidence/task_C_backends/mac_abhay_backend_A/11_supervisor_during_failures.txt) | 2026-09-30 14:11:58 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_backend_A/NOTES.md](04_evidence/task_C_backends/mac_abhay_backend_A/NOTES.md) | Task C: Backend A (mac_abhay, port 3001) |
|  | mac_vachan | [mac_vachan_backend_B/backend_B_log_from_edge.txt](04_evidence/task_C_backends/mac_vachan_backend_B/backend_B_log_from_edge.txt) | Backend B log: every request arrives from the EDGE 10.7.19.193, client only in X-Forwarded-For |
|  | mac_vachan | [mac_vachan_backend_B/endpoints_headers.txt](04_evidence/task_C_backends/mac_vachan_backend_B/endpoints_headers.txt) | Backend B /, /api/status, /api/cache-demo, 304, 404 - all with X-Backend: B |
|  | mac_vachan | [mac_vachan_backend_B/lsof_process.txt](04_evidence/task_C_backends/mac_vachan_backend_B/lsof_process.txt) | lsof: *:3002 LISTEN (all interfaces, not 127.0.0.1) |
|  | mac_vachan | [mac_vachan_backend_B/unit_test_backend_endpoints.txt](04_evidence/task_C_backends/mac_vachan_backend_B/unit_test_backend_endpoints.txt) | local tests before publishing the shared code |
|  | mac_vachan | [mac_vachan_backend_B/unit_test_supervisor.txt](04_evidence/task_C_backends/mac_vachan_backend_B/unit_test_supervisor.txt) | local tests before publishing the shared code |
| **Task D · Edge reverse proxy + round-robin load balancing** | | | |
|  | mac_aanya | [mac_aanya_edge/access_log_excerpt.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/access_log_excerpt.txt) | edge access log: upstream alternates 10.7.1.136:3001 / 10.7.23.136:3002, x_backend A/B, TLSv1.3, 304s |
|  | mac_aanya | [mac_aanya_edge/gate_check/root_batch_log.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/gate_check/root_batch_log.txt) | the edge's one sudo batch: DNS -> 10.7.23.136, flush, CA trusted |
|  | mac_aanya | [mac_aanya_edge/gate_check/start_sh_run.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/gate_check/start_sh_run.txt) | mac_aanya, 2026-09-30 14:02:09 IST: live test of the demo-day script (./start.sh), run while everything was already up |
|  | mac_aanya | [mac_aanya_edge/gate_check/step5_verification.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/gate_check/step5_verification.txt) | gate from the edge: dig via mac_vachan, HTTPS no -k, 10x B A B A, h1.1+h2, 301, 304 from A and B |
|  | mac_aanya | [mac_aanya_edge/nginx_T.txt](04_evidence/task_D_load_balancing/mac_aanya_edge/nginx_T.txt) | nginx -T: the full effective config (upstream, zone, TLS, proxy headers, failover) |
|  | mac_abhay | [mac_abhay_client/01_ten_requests_round_robin.txt](04_evidence/task_D_load_balancing/mac_abhay_client/01_ten_requests_round_robin.txt) | 2026-09-30 13:51:49 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/02_ten_requests_bodies.txt](04_evidence/task_D_load_balancing/mac_abhay_client/02_ten_requests_bodies.txt) | 2026-09-30 13:51:53 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/03_dns_only_knows_the_edge.txt](04_evidence/task_D_load_balancing/mac_abhay_client/03_dns_only_knows_the_edge.txt) | 2026-09-30 13:51:57 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/NOTES.md](04_evidence/task_D_load_balancing/mac_abhay_client/NOTES.md) | Task D: load balancing through the edge (round robin) |
|  | mac_vachan | [mac_vachan_client/step5_https_round_robin.txt](04_evidence/task_D_load_balancing/mac_vachan_client/step5_https_round_robin.txt) | from mac_vachan by name: TLS verify ok + X-Backend alternating |
| **Task E · HTTPS / TLS (certificates, trust, handshake, termination)** | | | |
|  | mac_aanya | [mac_aanya_certificates/README_tls.md](04_evidence/task_E_tls/mac_aanya_certificates/README_tls.md) | how the CA and certificate were made, field by field |
|  | mac_aanya | [mac_aanya_certificates/ca.cnf](04_evidence/task_E_tls/mac_aanya_certificates/ca.cnf) | openssl config used to build the certificate |
|  | mac_aanya | [mac_aanya_certificates/ca_cert_details.txt](04_evidence/task_E_tls/mac_aanya_certificates/ca_cert_details.txt) | CA: CA:TRUE pathlen:0, keyCertSign/cRLSign, nameConstraints subspace-67.test |
|  | mac_aanya | [mac_aanya_certificates/chain_verification.txt](04_evidence/task_E_tls/mac_aanya_certificates/chain_verification.txt) | openssl verify + macOS security verify-cert; name constraint rejects evil.example.com |
|  | mac_aanya | [mac_aanya_certificates/s_client_tls12.txt](04_evidence/task_E_tls/mac_aanya_certificates/s_client_tls12.txt) | openssl s_client TLS 1.2: chain depth 0/1, Verify return code 0 (ok) |
|  | mac_aanya | [mac_aanya_certificates/s_client_tls13.txt](04_evidence/task_E_tls/mac_aanya_certificates/s_client_tls13.txt) | openssl s_client TLS 1.3 (X25519MLKEM768): Verify return code 0 (ok) |
|  | mac_aanya | [mac_aanya_certificates/s_client_wrong_name.txt](04_evidence/task_E_tls/mac_aanya_certificates/s_client_wrong_name.txt) | wrong SNI/name -> hostname mismatch (the SAN check really happens) |
|  | mac_aanya | [mac_aanya_certificates/server.cnf](04_evidence/task_E_tls/mac_aanya_certificates/server.cnf) | openssl config used to build the certificate |
|  | mac_aanya | [mac_aanya_certificates/server_cert_details.txt](04_evidence/task_E_tls/mac_aanya_certificates/server_cert_details.txt) | leaf: CN/SAN app+api.subspace-67.test, EKU serverAuth, 397 days |
|  | mac_aanya | [mac_aanya_tls_termination/capture_traffic_commands.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/capture_traffic_commands.txt) | TLS termination capture support file |
|  | mac_aanya | [mac_aanya_tls_termination/edge_tls_termination.pcapng](04_evidence/task_E_tls/mac_aanya_tls_termination/edge_tls_termination.pcapng) | TLS TERMINATION: client leg encrypted (lo0), same request in plain HTTP to the backend (en0) |
|  | mac_aanya | [mac_aanya_tls_termination/tcpdump_pktap_metadata.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/tcpdump_pktap_metadata.txt) | TLS termination capture support file |
|  | mac_aanya | [mac_aanya_tls_termination/tshark_all_packets.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/tshark_all_packets.txt) | every packet of the termination capture with interface/process |
|  | mac_aanya | [mac_aanya_tls_termination/tshark_backend_leg_http.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/tshark_backend_leg_http.txt) | backend leg: plain GET /api/status + 200 with X-Backend visible |
|  | mac_aanya | [mac_aanya_tls_termination/tshark_client_leg_tls.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/tshark_client_leg_tls.txt) | client leg: ClientHello/ServerHello/Certificate (TLS 1.2), Application Data encrypted |
|  | mac_aanya | [mac_aanya_tls_termination/tshark_dns.txt](04_evidence/task_E_tls/mac_aanya_tls_termination/tshark_dns.txt) | the edge's own DNS query to mac_vachan |
|  | mac_abhay | [mac_abhay_client/00_ca_certificate_check.txt](04_evidence/task_E_tls/mac_abhay_client/00_ca_certificate_check.txt) | 2026-09-30 13:32:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/01_curl_v_no_k.txt](04_evidence/task_E_tls/mac_abhay_client/01_curl_v_no_k.txt) | 2026-09-30 13:51:57 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/02_curl_v_explicit_cafile.txt](04_evidence/task_E_tls/mac_abhay_client/02_curl_v_explicit_cafile.txt) | 2026-09-30 13:51:57 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/03_homebrew_openssl_curl_without_and_with_ca.txt](04_evidence/task_E_tls/mac_abhay_client/03_homebrew_openssl_curl_without_and_with_ca.txt) | 2026-09-30 13:51:58 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/04_openssl_s_client.txt](04_evidence/task_E_tls/mac_abhay_client/04_openssl_s_client.txt) | 2026-09-30 13:51:58 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/05_openssl_s_client_tls12.txt](04_evidence/task_E_tls/mac_abhay_client/05_openssl_s_client_tls12.txt) | 2026-09-30 13:51:59 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/06_openssl_s_client_tls13.txt](04_evidence/task_E_tls/mac_abhay_client/06_openssl_s_client_tls13.txt) | 2026-09-30 13:51:59 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/07_server_cert_details.txt](04_evidence/task_E_tls/mac_abhay_client/07_server_cert_details.txt) | 2026-09-30 13:51:59 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/08_macos_keychain_trust_check.txt](04_evidence/task_E_tls/mac_abhay_client/08_macos_keychain_trust_check.txt) | 2026-09-30 13:51:59 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/09_http1_vs_http2.txt](04_evidence/task_E_tls/mac_abhay_client/09_http1_vs_http2.txt) | 2026-09-30 13:51:59 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/10_http_redirects_to_https.txt](04_evidence/task_E_tls/mac_abhay_client/10_http_redirects_to_https.txt) | 2026-09-30 13:52:00 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/NOTES.md](04_evidence/task_E_tls/mac_abhay_client/NOTES.md) | Task E: TLS with our own CA, validated properly (never -k), and HTTP/1.1 vs HTTP/2 |
| **Task F · HTTP caching (Cache-Control, ETag, 304)** | | | |
|  | mac_abhay | [mac_abhay_client/01_head_cache_headers.txt](04_evidence/task_F_caching/mac_abhay_client/01_head_cache_headers.txt) | 2026-09-30 13:52:00 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/02_conditional_get_304.txt](04_evidence/task_F_caching/mac_abhay_client/02_conditional_get_304.txt) | 2026-09-30 13:52:01 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/03_normal_get_200.txt](04_evidence/task_F_caching/mac_abhay_client/03_normal_get_200.txt) | 2026-09-30 13:52:01 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/04_304_from_both_backends.txt](04_evidence/task_F_caching/mac_abhay_client/04_304_from_both_backends.txt) | 2026-09-30 13:52:01 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/05_wrong_etag_full_200.txt](04_evidence/task_F_caching/mac_abhay_client/05_wrong_etag_full_200.txt) | 2026-09-30 13:52:03 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/06_if_modified_since_304.txt](04_evidence/task_F_caching/mac_abhay_client/06_if_modified_since_304.txt) | 2026-09-30 13:52:03 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/07_curl_etag_save_compare.txt](04_evidence/task_F_caching/mac_abhay_client/07_curl_etag_save_compare.txt) | 2026-09-30 13:52:03 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/08_status_is_no_store.txt](04_evidence/task_F_caching/mac_abhay_client/08_status_is_no_store.txt) | 2026-09-30 13:52:04 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [mac_abhay_client/NOTES.md](04_evidence/task_F_caching/mac_abhay_client/NOTES.md) | Task F: HTTP caching: Cache-Control, ETag, conditional request, 304 |
| **Task G · Complete protocol flow capture (DNS -> TCP -> TLS -> HTTP)** | | | |
|  | mac_abhay | [NOTES.md](04_evidence/task_G_protocol_flow/NOTES.md) | Task G: the main packet capture (DNS + TCP + TLS + HTTP on the wire) |
|  | mac_abhay | [attempt1_blocked_exports/01_all_packets.txt](04_evidence/task_G_protocol_flow/attempt1_blocked_exports/01_all_packets.txt) | 2026-09-30 14:03:45 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [attempt1_blocked_exports/02_no_syn_to_443.txt](04_evidence/task_G_protocol_flow/attempt1_blocked_exports/02_no_syn_to_443.txt) | 2026-09-30 14:03:48 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [attempt1_blocked_task_G_tls12.pcapng](04_evidence/task_G_protocol_flow/attempt1_blocked_task_G_tls12.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [attempt1_blocked_task_G_tls12_commands.txt](04_evidence/task_G_protocol_flow/attempt1_blocked_task_G_tls12_commands.txt) | 2026-09-30 13:54:20 IST mac_abhay - Task G capture: dig + curl --tls-max 1.2 (TLS 1.2, Certificate visible) |
|  | mac_abhay | [attempt1_blocked_task_G_tls12_pktap_process.pcapng](04_evidence/task_G_protocol_flow/attempt1_blocked_task_G_tls12_pktap_process.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [task_G_explained.md](04_evidence/task_G_protocol_flow/task_G_explained.md) | Task G explained: one HTTPS request, packet by packet, layer by layer |
|  | mac_abhay | [task_G_tls12.pcapng](04_evidence/task_G_protocol_flow/task_G_tls12.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [task_G_tls12_commands.txt](04_evidence/task_G_protocol_flow/task_G_tls12_commands.txt) | 2026-09-30 13:57:59 IST mac_abhay - Task G capture: dig + curl --tls-max 1.2 (TLS 1.2, Certificate visible) with SSLKEYLOGFILE |
|  | mac_abhay | [task_G_tls12_exports/00_capinfos.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/00_capinfos.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/01_all_packets.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/01_all_packets.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/02_dns_query_response.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/02_dns_query_response.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/03_dns_detail_dig.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/03_dns_detail_dig.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/04_tcp_handshake.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/04_tcp_handshake.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/05_tcp_handshake_detail.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/05_tcp_handshake_detail.txt) | 2026-09-30 13:59:40 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/06_tls_records_encrypted_view.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/06_tls_records_encrypted_view.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/07_tls_clienthello_sni.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/07_tls_clienthello_sni.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/08_tls_serverhello_certificate_keyexchange.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/08_tls_serverhello_certificate_keyexchange.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/09_port_table.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/09_port_table.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/10_tcp_stream_seq_ack_all.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/10_tcp_stream_seq_ack_all.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/11_edge_to_backendA_hop.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/11_edge_to_backendA_hop.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/12_decrypted_tls_records.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/12_decrypted_tls_records.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/13_decrypted_http.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/13_decrypted_http.txt) | 2026-09-30 13:59:41 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_exports/14_process_per_packet_pktap.txt](04_evidence/task_G_protocol_flow/task_G_tls12_exports/14_process_per_packet_pktap.txt) | 2026-09-30 13:59:43 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls12_pktap_process.pcapng](04_evidence/task_G_protocol_flow/task_G_tls12_pktap_process.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [task_G_tls12_sslkeylog.txt](04_evidence/task_G_protocol_flow/task_G_tls12_sslkeylog.txt) | task G tls12 sslkeylog |
|  | mac_abhay | [task_G_tls13.pcapng](04_evidence/task_G_protocol_flow/task_G_tls13.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [task_G_tls13_commands.txt](04_evidence/task_G_protocol_flow/task_G_tls13_commands.txt) | 2026-09-30 13:54:27 IST mac_abhay - Task G capture: dig + curl --tlsv1.3 (TLS 1.3, Certificate encrypted) with SSLKEYLOGFILE |
|  | mac_abhay | [task_G_tls13_exports/00_capinfos.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/00_capinfos.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/01_all_packets.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/01_all_packets.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/02_dns_query_response.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/02_dns_query_response.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/03_dns_detail_dig.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/03_dns_detail_dig.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/04_tcp_handshake.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/04_tcp_handshake.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/05_tcp_handshake_detail.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/05_tcp_handshake_detail.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/06_tls_records_encrypted_view.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/06_tls_records_encrypted_view.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/07_tls_clienthello_sni.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/07_tls_clienthello_sni.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/08_tls_serverhello_certificate_keyexchange.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/08_tls_serverhello_certificate_keyexchange.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/09_port_table.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/09_port_table.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/10_tcp_stream_seq_ack_all.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/10_tcp_stream_seq_ack_all.txt) | 2026-09-30 13:59:42 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/11_edge_to_backendA_hop.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/11_edge_to_backendA_hop.txt) | 2026-09-30 13:59:43 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/12_decrypted_tls_records.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/12_decrypted_tls_records.txt) | 2026-09-30 13:59:43 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/12_tls13_decrypted_handshake.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/12_tls13_decrypted_handshake.txt) | 2026-09-30 13:58:54 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/13_decrypted_http.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/13_decrypted_http.txt) | 2026-09-30 13:59:43 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/13_tls13_decrypted_http.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/13_tls13_decrypted_http.txt) | 2026-09-30 13:58:54 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_exports/14_process_per_packet_pktap.txt](04_evidence/task_G_protocol_flow/task_G_tls13_exports/14_process_per_packet_pktap.txt) | 2026-09-30 13:59:43 IST on mac_abhay (10.7.1.136) |
|  | mac_abhay | [task_G_tls13_pktap_process.pcapng](04_evidence/task_G_protocol_flow/task_G_tls13_pktap_process.pcapng) | packet capture - open in Wireshark |
|  | mac_abhay | [task_G_tls13_sslkeylog.txt](04_evidence/task_G_protocol_flow/task_G_tls13_sslkeylog.txt) | task G tls13 sslkeylog |
| **Failure demonstrations F1-F5** | | | |
|  | mac_vachan | [F1_wrong_dns_server/F1_queries_to_nowhere.pcapng](04_evidence/failures/F1_wrong_dns_server/F1_queries_to_nowhere.pcapng) | packet capture - open in Wireshark |
|  | mac_vachan | [F1_wrong_dns_server/F1_queries_to_nowhere_tshark.txt](04_evidence/failures/F1_wrong_dns_server/F1_queries_to_nowhere_tshark.txt) | tshark text export of the capture, with packet numbers |
|  | mac_vachan | [F1_wrong_dns_server/README.md](04_evidence/failures/F1_wrong_dns_server/README.md) | observation, layer, why (the explanation) |
|  | mac_vachan | [F1_wrong_dns_server/commands_output.txt](04_evidence/failures/F1_wrong_dns_server/commands_output.txt) | exact commands + full output: break -> observe -> restore -> healthy check |
|  | mac_vachan | [F2_dns_record_wrong_ip/F2_wrong_record.pcapng](04_evidence/failures/F2_dns_record_wrong_ip/F2_wrong_record.pcapng) | packet capture - open in Wireshark |
|  | mac_vachan | [F2_dns_record_wrong_ip/F2_wrong_record_tshark.txt](04_evidence/failures/F2_dns_record_wrong_ip/F2_wrong_record_tshark.txt) | tshark text export of the capture, with packet numbers |
|  | mac_vachan | [F2_dns_record_wrong_ip/README.md](04_evidence/failures/F2_dns_record_wrong_ip/README.md) | observation, layer, why (the explanation) |
|  | mac_vachan | [F2_dns_record_wrong_ip/commands_output.txt](04_evidence/failures/F2_dns_record_wrong_ip/commands_output.txt) | exact commands + full output: break -> observe -> restore -> healthy check |
|  | mac_vachan | [F3_one_backend_down/README.md](04_evidence/failures/F3_one_backend_down/README.md) | observation, layer, why (the explanation) |
|  | mac_vachan | [F3_one_backend_down/commands_output.txt](04_evidence/failures/F3_one_backend_down/commands_output.txt) | exact commands + full output: break -> observe -> restore -> healthy check |
|  | mac_vachan | [F4_both_backends_down/F4_502_after_tls.pcapng](04_evidence/failures/F4_both_backends_down/F4_502_after_tls.pcapng) | packet capture - open in Wireshark |
|  | mac_vachan | [F4_both_backends_down/F4_502_after_tls_tshark.txt](04_evidence/failures/F4_both_backends_down/F4_502_after_tls_tshark.txt) | tshark text export of the capture, with packet numbers |
|  | mac_vachan | [F4_both_backends_down/F4_tls_session_keys.log](04_evidence/failures/F4_both_backends_down/F4_tls_session_keys.log) | TLS session keys of the one decrypted F4 connection (Wireshark: TLS > (Pre)-Master-Secret log) |
|  | mac_vachan | [F4_both_backends_down/README.md](04_evidence/failures/F4_both_backends_down/README.md) | observation, layer, why (the explanation) |
|  | mac_vachan | [F4_both_backends_down/commands_output.txt](04_evidence/failures/F4_both_backends_down/commands_output.txt) | exact commands + full output: break -> observe -> restore -> healthy check |
|  | mac_vachan | [F5_wrong_port/F5_syn_rst.pcapng](04_evidence/failures/F5_wrong_port/F5_syn_rst.pcapng) | packet capture - open in Wireshark |
|  | mac_vachan | [F5_wrong_port/F5_syn_rst_tshark.txt](04_evidence/failures/F5_wrong_port/F5_syn_rst_tshark.txt) | tshark text export of the capture, with packet numbers |
|  | mac_vachan | [F5_wrong_port/README.md](04_evidence/failures/F5_wrong_port/README.md) | observation, layer, why (the explanation) |
|  | mac_vachan | [F5_wrong_port/commands_output.txt](04_evidence/failures/F5_wrong_port/commands_output.txt) | exact commands + full output: break -> observe -> restore -> healthy check |
|  | mac_aanya | [edge_view_mac_aanya/NOTES_failures_edge_view.md](04_evidence/failures/edge_view_mac_aanya/NOTES_failures_edge_view.md) | Failure demos seen from the edge (mac_aanya nginx logs) |
|  | mac_aanya | [edge_view_mac_aanya/edge_logs_failure_demos.txt](04_evidence/failures/edge_view_mac_aanya/edge_logs_failure_demos.txt) | mac_aanya (edge) nginx logs covering mac_vachan's failure demos, 2026-09-30 IST, extracted 14:12:24 |
|  | mac_vachan | [failure_time_windows.txt](04_evidence/failures/failure_time_windows.txt) | failure demo time windows on 2026-09-30 (IST, +0530), reconstructed from the per-demo headers in logs/sudo_02.log |
|  | mac_vachan | [sudo_02_failure_run.log](04_evidence/failures/sudo_02_failure_run.log) | sudo 02 failure run |
| **Final gate check (all three Macs)** | | | |
|  | mac_aanya | [mac_aanya/final_gate_mac_aanya.txt](04_evidence/final_gate/mac_aanya/final_gate_mac_aanya.txt) | Final gate check (step 8) from mac_aanya (the edge itself as a client), 2026-09-30 14:15:27 IST |
|  | mac_abhay | [mac_abhay/final_gate_mac_abhay.txt](04_evidence/final_gate/mac_abhay/final_gate_mac_abhay.txt) | 2026-09-30 14:15:10 IST on mac_abhay (10.7.1.136) |
|  | mac_vachan | [mac_vachan/final_gate_mac_vachan.txt](04_evidence/final_gate/mac_vachan/final_gate_mac_vachan.txt) | Phase 1 gate check on mac_vachan (10.7.23.136) - 2026-09-30 14:14:55 IST |
| **Collection receipts (sha256 of every file pulled from the peers)** | | | |
|  | mac_aanya | [mac_aanya_COLLECTED.txt](04_evidence/_receipts/mac_aanya_COLLECTED.txt) | collected from http://10.7.19.193:8099/evidence/mac_aanya/ by mac_vachan |
|  | mac_aanya | [mac_aanya_MANIFEST.txt](04_evidence/_receipts/mac_aanya_MANIFEST.txt) | mac aanya MANIFEST |
|  | mac_abhay | [mac_abhay_COLLECTED.txt](04_evidence/_receipts/mac_abhay_COLLECTED.txt) | collected from http://10.7.1.136:8099/evidence/mac_abhay/ by mac_vachan |
|  | mac_abhay | [mac_abhay_MANIFEST.txt](04_evidence/_receipts/mac_abhay_MANIFEST.txt) | mac abhay MANIFEST |
| **Per-Mac evidence README** | mac_aanya | [README_mac_aanya.md](04_evidence/README_mac_aanya.md) | that Mac's own walkthrough of its evidence |
