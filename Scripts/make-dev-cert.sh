#!/usr/bin/env bash
# Creates a self-signed code signing identity so rebuilt bundles keep a stable
# designated requirement. Without it every rebuild is ad-hoc signed with a new
# code hash, and macOS re-prompts for Camera / Calendar / Accessibility access.
#
# macOS will ask for your login password once when the certificate is trusted.
set -euo pipefail

NAME="NotchDeck Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# `security import` refuses an empty-password PKCS#12 ("MAC verification
# failed"), so the transit file gets a throwaway password. It never leaves the
# temporary directory below.
PASSWORD="notchdeck"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = NotchDeck Dev

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"

# OpenSSL 3 writes PKCS#12 with AES/PBKDF2 by default and `security import`
# rejects it; -legacy writes the RC2/3DES form the keychain accepts. LibreSSL
# (/usr/bin/openssl) has no such flag and already writes the legacy form.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    LEGACY="-legacy"
fi

openssl pkcs12 -export ${LEGACY:+$LEGACY} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASSWORD"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$PASSWORD"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created identity '$NAME':"
security find-identity -v -p codesigning
