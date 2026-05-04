#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build-app.sh" release | tail -n 1)"
DESTINATION="/Applications/OpenWhisper.app"
CONFIG_DIR="$HOME/Library/Application Support/OpenWhisper"
CONFIG_FILE="$CONFIG_DIR/config.plist"
WHISPER_BIN="$ROOT_DIR/Dependencies/whisper.cpp/build/bin/whisper-cli"
MODEL_FILE="$ROOT_DIR/Models/ggml-large-v3-turbo.bin"

if [[ ! -x "$WHISPER_BIN" || ! -f "$MODEL_FILE" ]]; then
  echo "Missing local whisper.cpp executable or model." >&2
  echo "Run scripts/setup-whisper.sh large-v3-turbo first." >&2
  exit 1
fi

pkill -x OpenWhisper 2>/dev/null || true
rm -rf "$DESTINATION"
cp -R "$APP_DIR" "$DESTINATION"
codesign --force --deep --sign - "$DESTINATION" >/dev/null

mkdir -p "$CONFIG_DIR"
/usr/libexec/PlistBuddy -c "Clear dict" "$CONFIG_FILE" >/dev/null
/usr/libexec/PlistBuddy -c "Set :whisperExecutable $WHISPER_BIN" "$CONFIG_FILE" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :whisperExecutable string $WHISPER_BIN" "$CONFIG_FILE"
/usr/libexec/PlistBuddy -c "Set :model $MODEL_FILE" "$CONFIG_FILE" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :model string $MODEL_FILE" "$CONFIG_FILE"

open "$DESTINATION"
echo "$DESTINATION"
