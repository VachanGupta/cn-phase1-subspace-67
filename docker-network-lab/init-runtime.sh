#!/usr/bin/env bash
set -euo pipefail
cd /lab
umask 077
mkdir -p runtime/{ca,tls,dns-primary,dns-backup} evidence
# Replace the CA and leaf key pair if this checkout contains the published CA.
published_ca=474294e8c1234957bc929d9321707864c1c9ea75f1496a05be1d06fd0997b8f1
if [[ -s runtime/ca/ca.crt ]] &&
    [[ "$(sha256sum runtime/ca/ca.crt | cut -d ' ' -f 1)" == "$published_ca" ]]; then
    touch runtime/recreate-after-rotation
    rm -f runtime/ca/{ca.crt,ca.key,ca.srl} runtime/tls/{server.crt,server.key,server.csr}
fi
if [[ ! -s runtime/ca/ca.crt || ! -s runtime/ca/ca.key ]]; then
    openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 365 \
        -subj '/CN=Subspace 67 Lab CA' -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -keyout runtime/ca/ca.key -out runtime/ca/ca.crt
fi
if [[ ! -s runtime/tls/server.crt || ! -s runtime/tls/server.key ]]; then
    openssl req -new -newkey rsa:2048 -nodes -subj '/CN=app.subspace-67.test' \
        -keyout runtime/tls/server.key -out runtime/tls/server.csr
    openssl x509 -req -sha256 -days 180 -in runtime/tls/server.csr \
        -CA runtime/ca/ca.crt -CAkey runtime/ca/ca.key -CAcreateserial \
        -extfile <(printf '%s\n' 'subjectAltName=DNS:app.subspace-67.test,DNS:api.subspace-67.test' 'basicConstraints=critical,CA:FALSE' 'extendedKeyUsage=serverAuth') \
        -out runtime/tls/server.crt
fi
openssl verify -CAfile runtime/ca/ca.crt runtime/tls/server.crt
printf '%s\n' '10.67.10.10 app.subspace-67.test api.subspace-67.test' | tee runtime/dns-primary/hosts > runtime/dns-backup/hosts
