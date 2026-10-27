#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$1"
IDENTITY="${OPENWHISPER_CODESIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --sign "$IDENTITY" "$APP_DIR" >/dev/null
  exit 0
fi

# Without a developer certificate, sign with a self-signed one. macOS ties Microphone and Accessibility
# permissions to the signature, and an ad-hoc signature is new with every build, so they would be lost on each
# install. The certificate lives in its own keychain, whose password is kept in the login keychain.
LOCAL_IDENTITY="OpenWhisper Local Signing"
KEYCHAIN="$HOME/Library/Keychains/openwhisper-signing.keychain-db"
PASSWORD_SERVICE="dev.openwhisper.signing-keychain"

keychain_password() {
  security find-generic-password -s "$PASSWORD_SERVICE" -a "$KEYCHAIN" -w 2>/dev/null
}

create_local_identity() {
  local password work
  password="$(/usr/bin/openssl rand -hex 24)"
  work="$(mktemp -d)"

  # The system's LibreSSL writes a PKCS#12 file that the security tool can import.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=$LOCAL_IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -name "$LOCAL_IDENTITY" \
    -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$work/identity.p12" -passout "pass:$password"

  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p "$password" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p "$password" "$KEYCHAIN"
  security import "$work/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$password" -T /usr/bin/codesign >/dev/null
  # Lets codesign use the key without asking for the keychain password.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
  security add-generic-password -U -s "$PASSWORD_SERVICE" -a "$KEYCHAIN" \
    -l "OpenWhisper signing keychain" -w "$password"
  rm -rf "$work"

  echo "Created the \"$LOCAL_IDENTITY\" certificate. macOS asks for OpenWhisper's permissions once more." >&2
}

if [[ ! -f "$KEYCHAIN" ]] || ! keychain_password >/dev/null; then
  create_local_identity
fi
security unlock-keychain -p "$(keychain_password)" "$KEYCHAIN"

# codesign only finds identities in keychains on the search list, so the keychain joins it while signing.
SEARCH_LIST=()
while IFS= read -r keychain; do
  keychain="${keychain#"${keychain%%[![:space:]]*}"}"
  keychain="${keychain//\"/}"
  [[ "$keychain" == "$KEYCHAIN" ]] || SEARCH_LIST+=("$keychain")
done < <(security list-keychains -d user)
trap 'security list-keychains -d user -s "${SEARCH_LIST[@]}"' EXIT
security list-keychains -d user -s "${SEARCH_LIST[@]}" "$KEYCHAIN"

codesign --force --deep --keychain "$KEYCHAIN" --sign "$LOCAL_IDENTITY" "$APP_DIR" >/dev/null
