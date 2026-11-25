# Viva preparation

- **What happens when the client opens the private URL?** DNS maps the test name to the active edge IP. The client opens TCP to port 443, negotiates TLS, validates the certificate, and sends HTTP over the encrypted connection. Nginx terminates TLS and proxies HTTP to one Python backend.
- **How do you identify TCP connection setup?** Find SYN, SYN-ACK, and ACK in that order. Identify the client’s ephemeral source port and the server’s port 443. TCP sequence and acknowledgment numbers track delivery and ordering. DNS uses UDP/53 in the capture.
- **Why does Wireshark show encrypted payloads?** TLS protects the client-to-edge HTTP traffic after the handshake. The edge-to-backend leg uses private HTTP on the separate bridge. Inspect clear request and response headers with curl.
- **What proves load balancing?** The same stable hostname and edge answer repeated requests with different X-Backend values. The two servers use the same code on separate ports.
- **What does a 304 mean?** The client sent an ETag and the representation still matches. A fresh cache hit can avoid the network entirely. A conditional request still goes over the network, with the 304 allowing reuse of the cached body.
- **How do DNS failures differ from backend failures?** Wrong DNS can prevent name resolution or send a client to the wrong address. With both backends stopped, DNS and TLS still work and Nginx returns 502. One backend can continue serving while its peer is stopped.
- **What did Phase 2 add?** Backup DNS, a visible 30-second TTL, separate Docker bridges for service isolation, passive upstream failover and recovery, and a standby edge selected through DNS.
- **How do you diagnose an unfamiliar failure?** Prove name resolution, TCP reachability, TLS validation, and the HTTP/upstream response in that order.
- **What stays a single point of failure?** The primary edge is the active entry point until a DNS cutover. The PC and Docker engine are shared by all containers.
- **What are the cloud analogues?** Private managed DNS, an HTTPS load balancer, and two application compute instances. This demo runs those roles locally.
