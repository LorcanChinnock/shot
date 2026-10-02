#!/bin/bash
# Creates a self-signed code-signing certificate named "Shot Dev" in the login keychain.
# macOS ties Screen Recording permission to the app's signature; a stable certificate keeps
# the permission across rebuilds, where an ad-hoc signature would reset it every time.
set -euo pipefail

name="${1:-Shot Dev}"
if security find-identity -p codesigning | grep -q "\"$name\""; then
    echo "A signing identity named '$name' already exists."
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 3650 -config "$work/cert.cnf" 2>/dev/null
pass="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" -out "$work/cert.p12" -passout "pass:$pass"
security import "$work/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
echo "Created '$name'. Keychain Access shows it as not trusted; code signing works anyway."
