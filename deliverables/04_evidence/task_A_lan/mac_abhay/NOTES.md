# Task A: mac_abhay network identity and reachability of the peers

**What it shows**
| Item | Value | Evidence file |
|---|---|---|
| Interface | en0 = "Wi-Fi" network service | 01_ifconfig_en0.txt, 05_hardware_ports.txt |
| IPv4 address | 10.7.1.136 (DHCP) | 01, 04, 06 |
| Subnet mask | 255.255.224.0 = /19 (`netmask 0xffffe000`, broadcast 10.7.31.255) | 01, 04, 06 |
| Default gateway | 10.7.0.1 (`route -n get default`: `gateway: 10.7.0.1`, `interface: en0`) | 03 |
| MAC used on the wire | 8e:f6:fb:7b:0a:59 (macOS *private Wi-Fi address*, `ether` in ifconfig) | 01 |
| Hardware MAC | 10:9f:41:b9:7b:b6 ("Wi-Fi ID" in networksetup) | 04, 05 |
| DNS before the project | none set manually; DHCP gave 8.8.8.8 and 10.5.7.1 | 08 (and PROJECT_DIR/original_network_settings.txt) |

- Peers: mac_vachan 10.7.23.136 and mac_aanya 10.7.19.193 (IPs from their own info.json on the team bus). Both are
  in the same 10.7.0.0/19 subnet as this Mac, so traffic between us is delivered directly on the LAN (no router hop).
- `ping` to both peers: 5/5 replies, TTL=64 (the macOS default, not decremented, so no router in between), and `arp -n`
  shows each peer's MAC resolved on en0 (09_ping_mac_aanya.txt, 10_ping_mac_vachan.txt).
- 07_routing_table.txt: `10.7/19 link#11 ... en0` is the directly connected subnet route, and `default 10.7.0.1` is the way out.
  (Most of its lines are ARP-learned neighbours on the busy campus Wi-Fi.)

**Which layer**
- Layer 2 (link): MAC addresses, ARP entries (IP -> MAC on the local segment).
- Layer 3 (network): IP address, mask/prefix, gateway, routing table; ICMP echo (ping) proves IP reachability.

**Why it matters**
Every later step depends on this: backends must be reachable at a LAN IP (not 127.0.0.1), the DNS server and the edge
must be in reach, and the pcaps in Task G show exactly these MAC/IP addresses in their Ethernet and IP headers.
Note: the first ping to mac_aanya failed with "sendto: No route to host" while ARP was still unresolved. Once the ARP
entry existed it worked (5/5). That is ARP resolution, not a firewall problem.
