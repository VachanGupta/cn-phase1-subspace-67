# Getting dnsmasq to serve port 53 on macOS: what went wrong, and how it was diagnosed

This is a real layer-by-layer diagnosis from our build day on mac_vachan. It is worth telling in the viva.

## 1. A normal user can't bind port 53 on a specific address
- Test (Python, as a normal user): `bind 0.0.0.0:53 OK`, but `bind 127.0.0.1:53: [Errno 13] Permission denied`.
  Since macOS 10.14 a normal user may bind ports below 1024 only on the **wildcard** address.
- dnsmasq on macOS logs `setting --bind-interfaces option because of OS limitations`. It always binds each
  listen address separately, so non-root it fails (`dnsmasq_nonroot_attempt.txt`):
  `dnsmasq: failed to create listening socket for 10.7.23.136: Permission denied`.
- **Fix:** run it as a **root Homebrew service** (`sudo brew services start dnsmasq`). It binds as root, then
  drops to `user=nobody`.

## 2. The root service crash-looped: exit code 3 = "filesystem problem"
- The first root start used `/opt/homebrew/etc/dnsmasq.conf` = `conf-file=~/Desktop/work/CN/configs/dnsmasq.conf`
  and a log file under `~/Desktop` (`dnsmasq.conf.first_attempt_desktop_paths`).
- `launchctl print system/homebrew.mxcl.dnsmasq` showed `runs = 17, last exit code = 3`. dnsmasq's exit
  code 3 means a missing file or permission problem.
- **Cause:** macOS privacy protection (TCC) stops a root **launchd daemon** from reading or writing inside
  `~/Desktop`. The same config had worked in a per-user test, because that agent was started from the
  desktop terminal app, which has Desktop access.
- **Fix:** `bin/gen_dnsmasq.py` now installs a **byte-identical copy** of `configs/dnsmasq.conf` at
  `/opt/homebrew/etc/dnsmasq.conf` and logs to `/opt/homebrew/var/log/dnsmasq_subspace_67.log`
  (symlinked from `logs/dnsmasq.log`). launchd's KeepAlive respawned the daemon, which then started
  normally (pid 57900). No second sudo was needed.

## 3. A health check that lied
- The root batch (`sudo_01_root_batch.log`) checked "is dnsmasq answering?" with `[ -n "$(dig +short ...)" ]`.
  On a timeout, `dig +short` prints `;; connection timed out; no servers could be reached` **to stdout**,
  so the check passed while nothing was listening. The script then pointed this Mac's DNS at itself:
  this Mac briefly had no working DNS.
- **Stopgap:** a tiny relay on the wildcard `0.0.0.0:53`, allowed for a normal user, which accepted only
  queries from this Mac itself and forwarded them to 1.1.1.1/8.8.8.8. It was stopped as soon as dnsmasq ran.
- **Fix:** every check now accepts only a real IPv4 answer (`dig +short | grep -E '^[0-9]+(\.[0-9]+){3}$'`),
  and the final checks compare the answer with mac_aanya's IP.

## Lessons (layer thinking)
- "Service started" is not "service answering": always test the **protocol**, `dig @server name`, and
  parse the answer, not just the exit status or "non-empty output".
- Diagnose bottom-up: process running? (`pgrep`, `launchctl print`) -> socket bound? (`lsof -i :53`) ->
  answering? (`dig @127.0.0.1`, `dig @LAN-IP`) -> correct answer? -> clients configured? (`scutil --dns`).
