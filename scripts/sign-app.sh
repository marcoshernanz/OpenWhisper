#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$1"
IDENTITY="${OPENWHISPER_CODESIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F '"' '/Apple Development:/ { print $2; exit }')"
fi

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
fi

codesign --force --deep --sign "$IDENTITY" "$APP_DIR" >/dev/null
