# Task D: load balancing through the edge (round robin)

**What it shows**
- 01_ten_requests_round_robin.txt: 10 requests to `https://app.subspace-67.test/api/status` ->
  `X-Backend: B A B A B A B A B A`: strict alternation between Backend B (mac_vachan:3002) and Backend A (mac_abhay:3001).
- 02_ten_requests_bodies.txt: the JSON bodies confirm it from the backends' side: `"backend": "A", "port": 3001,
  "host": "Abhays-MacBook-Pro-4.local"` alternating with `"backend": "B", "port": 3002, "host": "Vachans-MacBook-Pro.local"`.
- 03_dns_only_knows_the_edge.txt: DNS has exactly **one** A record for each name, 10.7.19.193 (the edge). Neither
  backend IP (10.7.1.136, 10.7.23.136) nor port (3001, 3002) appears anywhere the client can see.
- `/api/status` is `Cache-Control: no-store`, so no cache can answer: every request really reaches a backend.

**Which layer**: application layer (HTTP reverse proxy / load balancer, the `X-Backend` header). Transport layer
underneath: the client has one TCP/TLS connection to the edge, and the edge has separate TCP connections to each backend.

**Why the client never needs backend IPs**
The client only knows the name. DNS turns it into the edge's IP, and the edge (nginx) holds the upstream pool
`{10.7.1.136:3001, 10.7.23.136:3002}` and picks one per request (round robin, a shared upstream zone so all nginx
workers share one counter). So:
- backends can be added, removed, restarted, or moved to new IPs by changing **only** nginx's config; clients and DNS don't change;
- the backends are not exposed to clients at all (they only accept plain HTTP from the edge on the LAN);
- TLS certificates, redirects, logging and failure handling live in one place (the edge);
- if one backend is down, nginx gets "connection refused" and sends the request to the other; the client still gets an answer.
