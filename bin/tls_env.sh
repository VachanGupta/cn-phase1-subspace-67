# bin/tls_env.sh - sourced by our scripts before they call curl. On mac_vachan it deliberately sets
# NOTHING, because it doesn't need to (verified 2026-09-30):
#   /usr/bin/curl 8.7.1 (Apple build, LibreSSL) prints "CAfile: /etc/ssl/cert.pem", but Apple's build
#   also honours the macOS keychain trust settings. Before our CA was trusted:
#     curl https://app.subspace-67.test/  ->  (60) SSL certificate problem: self signed certificate in certificate chain
#   after sudo/01 trusted it in the System keychain (SSL policy):
#     curl https://app.subspace-67.test/  ->  HTTP/2 200, ssl_verify_result=0   (no -k, no --cacert)
# Homebrew's curl (OpenSSL) does NOT read the keychain: with it we pass --cacert tls/ca.crt, which is
# still full validation against our CA (never -k / --insecure).
:
