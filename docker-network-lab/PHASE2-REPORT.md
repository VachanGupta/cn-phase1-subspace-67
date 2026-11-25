# Subspace 67 Phase 2 report

## Changes from Phase 1

The lab uses Docker Compose on a single Windows PC. Two private Docker bridges represent the client LAN and backend network. dnsmasq and Nginx are separate services, and the original Python backend runs twice with distinct IDs and ports. The lab CA and leaf certificate are generated locally. The standby edge shares the same certificate identity for the two private names.

## Extensions and evidence

| Extension | Implementation | Result and evidence |
|---|---|---|
| A — Backup DNS | Two resolvers provide the same records. Both independent client caches can forward to either resolver. | Passed. Both clients returned `10.67.10.10` after primary DNS stopped and their local caches were flushed. The launcher output includes backup DNS logs. |
| B — TTL and flush | The DNS host records use a 30-second TTL. The clients have independent caches and can flush by signaling their local dnsmasq. | Passed. Client A retained the original answer with 29 seconds left. After 31 seconds it reached the standby, and flushing its cache made the restored primary answer take effect immediately. |
| C — Service isolation | Both edges join both networks. Clients and DNS servers are absent from the backend network. Compose applies Docker bridge isolation and publishes no backend ports. | Passed. The client could not reach either backend port, while Nginx could fetch both upstream status endpoints. See `compose.json` for the isolation configuration. |
| D — Backend failover | Nginx uses passive failure detection, retries eligible failures, and tracks upstream health across workers. | Passed. Four requests succeeded through Backend B while A was stopped. After A restarted, both backend IDs appeared in the response headers. |
| E — Edge migration | Change the private DNS records to the standby edge. Both endpoints are valid for the service hostname. | Passed. Cached Client A reached `10.67.10.10` while fresh Client B reached `10.67.10.20`. Client A reached the standby after its TTL expired. The test restored the primary address. |
| F — Troubleshooting | Follow the DNS, TCP, TLS, then HTTP sequence in DEMO.md. | Evaluator-led. Record the symptom, failing layer, checks, and corrective action after the live fault. |

A standby edge permits a controlled service cutover. The physical Windows host and Docker engine remain shared failure points. Service recovery in this lab demonstrates container outages and controlled routing changes.

## Evidence to attach

- Phase 1 transcript and packet capture produced by Test-Phase1.ps1.
- Phase 2 transcript produced by Test-Phase2.ps1, including backup resolver logs and the two edge addresses.
- Live troubleshooting notes and actual observations. Automated checks for Extensions A–E passed on 24 November 2026. Extension F is performed by the evaluator during grading.
