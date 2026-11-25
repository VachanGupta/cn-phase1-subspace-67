#!/usr/bin/env bash
set -euo pipefail
cd /lab
umask 077
mkdir -p runtime/{ca,tls,dns-primary,dns-backup} evidence
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
printf '%s\n' '10.67.10.10 app.subspace-67.test api.subspace-67.test' | tee runtime/dns-primary/hosts > runtime/dns-backup/hosts
