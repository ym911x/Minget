#!/bin/bash
# Create the local code-signing identity that scripts/build.sh uses.
#
# Why this exists
#   An ad-hoc signature (`codesign --sign -`) carries no certificate and no Team ID, so macOS
#   cannot derive a stable identity for the app. The designated requirement degrades to the
#   binary's cdhash, which changes on every rebuild. The keychain access control list stores
#   the requirement from the time the credential was created, so after the next rebuild the
#   comparison fails and macOS asks the user to allow keychain access again. A self-signed
#   certificate makes the requirement stable (`identifier` + `certificate leaf`), so rebuilds
#   keep matching. Full background: docs/versions/1.0.2/SIGNING_HANDOFF.md
#
# What it does
#   1. generates a self-signed code-signing certificate with OpenSSL
#   2. imports it into the login keychain, allowing /usr/bin/codesign and /usr/bin/security
#   3. optionally authorises the private key so codesign does not prompt for a password
#
# What it does NOT do
#   It never touches, rewrites or deletes any existing keychain item, and it never touches the
#   application's own credentials (service `local.usagemonitor.credentials`). Nothing is sent
#   over the network. The temporary private key material lives in a `mktemp -d` directory that
#   is removed on exit; only the login keychain keeps the identity.
#
# Usage
#   scripts/make-signing-identity.sh                 # create the certificate and import it
#   scripts/make-signing-identity.sh --authorize     # also authorise the private key for codesign
#   MINGET_SIGN_IDENTITY_NAME="My Signing" scripts/make-signing-identity.sh
#
# This script was written from SIGNING_HANDOFF.md 3.1 and has had its syntax checked, but the
# certificate has not been created in the authoring environment, so it is not yet proven end to
# end. The verification commands it prints at the end are the proof.
set -euo pipefail

IDENTITY="${MINGET_SIGN_IDENTITY_NAME:-Minget Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
AUTHORIZE=0
for arg in "$@"; do
  case "$arg" in
    --authorize) AUTHORIZE=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# LibreSSL (the /usr/bin/openssl that ships with macOS) does not support -addext, which is
# required for the codeSigning extended key usage. Homebrew's openssl@3 does.
OPENSSL="${MINGET_OPENSSL:-}"
if [[ -z "$OPENSSL" ]]; then
  for candidate in /opt/homebrew/bin/openssl /usr/local/bin/openssl; do
    if [[ -x "$candidate" ]] && "$candidate" version 2>/dev/null | grep -q '^OpenSSL 3'; then
      OPENSSL="$candidate"
      break
    fi
  done
fi
if [[ -z "$OPENSSL" ]]; then
  echo "error: no OpenSSL 3 found. Install it with: brew install openssl@3" >&2
  echo "       /usr/bin/openssl is LibreSSL and does not support -addext." >&2
  exit 1
fi
echo "== openssl: $OPENSSL ($("$OPENSSL" version)) =="

if security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "== identity '$IDENTITY' already exists, nothing to do =="
  echo
  echo "To replace it, remove it first in Keychain Access (login keychain, my certificates),"
  echo "then run this script again. Removing it will require one more keychain authorisation"
  echo "for the app, because the designated requirement changes."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Throwaway passphrase for the temporary PKCS#12 file only. The file is deleted on exit and
# the real private key never leaves the login keychain.
P12PASS="$("$OPENSSL" rand -hex 16)"

echo "== generating self-signed code signing certificate =="
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$IDENTITY/O=Minget/C=CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

echo "== packaging as PKCS#12 =="
if ! "$OPENSSL" pkcs12 -export -legacy \
      -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
      -out "$WORK/identity.p12" -passout "pass:$P12PASS" 2>/dev/null; then
  "$OPENSSL" pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$P12PASS"
fi

echo "== importing into the login keychain =="
security import "$WORK/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12PASS" \
  -T /usr/bin/codesign -T /usr/bin/security

if [[ "$AUTHORIZE" -eq 1 ]]; then
  echo
  echo "== authorising the private key for codesign =="
  echo "Enter your macOS login password. It is passed to 'security' and will be visible in"
  echo "the process list for a moment; it is not written to disk by this script."
  read -rs -p "login password: " LOGIN_PASSWORD
  echo
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$LOGIN_PASSWORD" "$KEYCHAIN" > /dev/null
  unset LOGIN_PASSWORD
  echo "   authorised"
else
  echo
  echo "Note: codesign may ask for the private key password until the key is authorised."
  echo "Either rerun this script with --authorize, or open Keychain Access, select the new"
  echo "private key, open Access Control, and choose 'Allow all applications to access'."
fi

echo
echo "== verify =="
security find-identity -p codesigning 2>/dev/null | grep -F "$IDENTITY" || {
  echo "error: the new identity is not listed. Check the login keychain." >&2
  exit 1
}
echo
echo "Next steps:"
echo "  1. scripts/build.sh                     # signs with this identity from now on"
echo "  2. open \"\$HOME/Applications/Minget.app\" and allow keychain access once (expected)"
echo "  3. scripts/build.sh && open \"\$HOME/Applications/Minget.app\"   # the prompt must not come back"
echo
echo "Ad-hoc fallback, if ever needed: MINGET_SIGN_IDENTITY=- scripts/build.sh"
