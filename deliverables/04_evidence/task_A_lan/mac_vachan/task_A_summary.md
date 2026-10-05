# Task A - mac_vachan network identity

| field | value | how it was obtained |
|---|---|---|
| Mac | mac_vachan (Mac 1: DNS server + Backend B + client + integrator) | |
| Interface | en0 (network service "Wi-Fi") | `route -n get default` -> interface |
| IPv4 address | 10.7.23.136 | `ipconfig getifaddr en0` |
| Subnet mask | 255.255.224.0 (/19) | `ipconfig getoption en0 subnet_mask` (ifconfig shows it as 0xffffe000) |
| Network / broadcast | 10.7.0.0/19 / 10.7.31.255 | mask applied to the IP; ifconfig "broadcast" |
| Default gateway | 10.7.0.1 | `route -n get default` -> gateway |
| MAC in use on Wi-Fi | 6a:e1:56:86:a2:23 | `ifconfig en0` -> ether (macOS "Private Wi-Fi Address", randomised per network) |
| Hardware MAC | 10:9f:41:ba:e3:83 | `networksetup -getmacaddress Wi-Fi` / "Wi-Fi ID" in `networksetup -getinfo` |
| DNS before the project | 8.8.8.8, 1.1.1.1 (manually set) | `networksetup -getdnsservers Wi-Fi` (saved to state/original_network.txt) |
| Services on this Mac | dnsmasq 53/udp+tcp, Backend B 3002/tcp, team bus 8099/tcp | |

**What it shows / layer / why.** These are the Layer 2 (MAC) and Layer 3 (IP, mask, gateway) facts
for this Mac. The mask 255.255.224.0 (/19) means every address from 10.7.0.0 to 10.7.31.255 is on the
same link: the three Macs can talk directly (ARP for each other's MAC, no router hop) while anything
else (e.g. 1.1.1.1) is sent to the gateway 10.7.0.1. The MAC in use is a private (randomised) address that
macOS uses on this Wi-Fi network instead of the burned-in one, which is why the two MAC rows differ.
