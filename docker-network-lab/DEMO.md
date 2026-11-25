# Live grading runbook

Use Docker Desktop in Linux container mode on this Windows PC. Open the lab directory and double-click **Show-Demo.cmd** to display test output live, or **Run-Lab.cmd** to save the full console log. The first run downloads the base images. The launcher waits for verified HTTPS, runs both phases, and saves a fresh capture and transcripts in `evidence/`. It leaves the lab running. The ZIP and GitHub copy also include the earlier verified run in `verified-evidence/`.

## Demonstration sequence

From PowerShell in this directory, run the commands below as needed. Use a second window if the launcher is running.

| Step | What to show |
|---|---|
| 1. Architecture | Open the topology and IP/service table in README.md. Describe the two Docker bridges and the dual-homed edges. |
| 2. Private LAN | Run `docker network inspect subspace67_clients subspace67_backends` and `docker compose -f compose.json exec client-a ping -c 2 10.67.10.10`. The verification log maps the container interfaces and bridge membership. |
| 3. Private DNS | Run `docker compose -f compose.json exec client-a dig app.subspace-67.test` and `docker compose -f compose.json exec client-b dig api.subspace-67.test`. Both names normally return 10.67.10.10. |
| 4. HTTPS | Run `docker compose -f compose.json exec client-a curl -v https://app.subspace-67.test/api/status`. Show hostname and certificate validation and the negotiated HTTP version. |
| 5. Load balancing | Repeat `docker compose -f compose.json exec client-a curl -si https://app.subspace-67.test/api/status` and point out the alternating X-Backend values. |
| 6. Packet analysis | Open `evidence/phase1.pcap` in Wireshark. Use `dns`, `tcp.port == 443`, and `tls.handshake`. Identify the DNS query and reply, the TCP three-way handshake, and the TLS ClientHello and ServerHello. The TLS 1.2 stream also exposes the certificate handshake message. |
| 7. HTTP caching | Show the Cache-Control and ETag on `/api/cache-demo` and the conditional HTTP 304 in the Phase 1 transcript. The Phase 1 script performs the live conditional request using the returned ETag. |
| 8. Backend failure | Run `docker compose -f compose.json stop backend-a`. Repeat HTTPS twice and show B-only results. Run `docker compose -f compose.json start backend-a` to restore A. |
| 9. Phase 2 | Open the Phase 2 transcript and replay `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Test-Phase2.ps1` if the evaluator wants the full live sequence. Point out backup DNS, the 30-second TTL, isolation, backend recovery, and both X-Edge addresses. |
| 10. Diagnose a fault | Let the evaluator introduce the fault, then follow the diagnostic sequence below. |
| 11. Individual viva | Explain one request end to end and the difference between service failover and physical-host failover. Use VIVA.md to rehearse. |

The five Phase 1 fault demonstrations are included in `Test-Phase1.ps1`. Its sections F1–F5 cover wrong resolver, wrong A record, one backend down, both backends down, and wrong destination port. The Phase 2 script restores both DNS records to the primary edge and restarts affected services on exit.

## Diagnostic sequence

1. **DNS:** Run `docker compose -f compose.json exec client-a dig app.subspace-67.test`. Compare it with `docker compose -f compose.json exec client-a dig @10.67.10.53 app.subspace-67.test` and the same command with `@10.67.10.54`. Check the answer IP and TTL, then inspect the resolver logs.
2. **TCP:** Check the resolved address and whether port 443 accepts a connection. Compare a failure on port 9443 to a successful HTTPS connection on 443.
3. **TLS:** Run curl with `-v` and inspect the certificate chain, validity, and hostname. The local CA is installed inside each demo client.
4. **HTTP:** Inspect the status and X-Backend/X-Edge headers. If there is a 502, check `docker compose -f compose.json logs edge` and test the upstreams from the edge network.

Record the injected fault, affected layer, evidence, corrective action, and successful retest. The evaluator-led fault and individual viva take place live.

Stop the lab after grading with `docker compose -f compose.json --profile phase2 down` from the lab directory.
