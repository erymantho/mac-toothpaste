#!/usr/bin/env bash
# Creates the self-signed code-signing certificate the build uses.
#
# Why this exists at all: macOS ties the Accessibility permission to the app's code
# signature. Signed ad-hoc, every rebuild produces a different signature and the
# permission is revoked each time. A stable certificate makes the grant stick.
#
# The certificate is self-signed and therefore untrusted, which is fine and expected —
# `security find-identity -v` hides it for that reason, so don't use -v to look for it.
# codesign accepts it regardless, and what ends up in the signature is the certificate
# hash rather than the binary hash. That is the whole point.
#
# Doing this by hand means four menus deep in Keychain Access; this is the same thing.
set -euo pipefail

NAME="${TOOTHPASTE_SIGN_IDENTITY:-Toothpaste Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

existing="$(security find-identity -p codesigning 2>/dev/null | grep -c "\"$NAME\"" || true)"
if [ "$existing" -gt 0 ]; then
	echo "A certificate named '$NAME' already exists:"
	security find-identity -p codesigning 2>/dev/null | grep "\"$NAME\"" | sed 's/^/  /'
	if [ "$existing" -gt 1 ]; then
		echo
		echo "WARNING: there are $existing of them. The build picks whichever the keychain"
		echo "         lists first, and that order is not stable — which makes the"
		echo "         Accessibility grant reset at random. Delete the spares in"
		echo "         Keychain Access, keeping one."
	fi
	echo
	echo "Nothing to do. Creating a second one would be worse than useless."
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $NAME
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

# Ten years. Keychain Access defaults to one, and a certificate that expires means
# re-signing with a new one — which changes the signature and costs everyone their
# Accessibility permission again.
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-days 3650 -nodes -config "$WORK/openssl.cnf" >/dev/null 2>&1

PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/bundle.p12" -passout "pass:$PASS" -name "$NAME" >/dev/null 2>&1

# -T /usr/bin/codesign lets codesign use the key without prompting for the keychain
# password on every build.
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -A >/dev/null

echo "Created signing certificate '$NAME':"
security find-identity -p codesigning 2>/dev/null | grep "\"$NAME\"" | sed 's/^/  /'
echo
echo "It reports CSSMERR_TP_NOT_TRUSTED. That is expected for a self-signed root and"
echo "does not stop codesign from using it."
echo
echo "Next: make install"
