#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="Susurro Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# If already present, exit
if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERT_NAME"; then
  echo "Cert '$CERT_NAME' already exists in login keychain."
  exit 0
fi

cd "$WORKDIR"

# OpenSSL config for code-signing cert
cat > cert.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_codesign

[dn]
CN = $CERT_NAME
O = Susurro
OU = Personal Dev
C = ES

[v3_codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# Generate private key + self-signed cert
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 3650 -nodes -config cert.cnf

# Convert to PKCS12
# Use -legacy and a non-empty temp password for macOS security tool compatibility
TMPPASS="$(openssl rand -hex 16)"
openssl pkcs12 -legacy -export -out cert.p12 -inkey key.pem -in cert.pem \
  -name "$CERT_NAME" -passout "pass:$TMPPASS"

# Import into login keychain
security import cert.p12 -k "$KEYCHAIN" -P "$TMPPASS" -T /usr/bin/codesign -A

# Trust it for code signing
# (Note: this prompts the user for their password — unavoidable for trust changes)
security add-trusted-cert -p codeSign -k "$KEYCHAIN" cert.pem

echo "Cert '$CERT_NAME' installed and trusted."
echo "Verify with: security find-identity -v -p codesigning"
