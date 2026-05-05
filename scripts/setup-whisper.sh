#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${1:-large-v3-turbo}"
WHISPER_DIR="$ROOT_DIR/Dependencies/whisper.cpp"
MODELS_DIR="$ROOT_DIR/Models"
MODEL_FILE="$MODELS_DIR/ggml-$MODEL.bin"

mkdir -p "$ROOT_DIR/Dependencies" "$MODELS_DIR"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_DIR/build" --config Release --target whisper-cli whisper-server -j

if [[ ! -f "$MODEL_FILE" ]]; then
  curl --fail --location --continue-at - \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin" \
    --output "$MODEL_FILE"
fi

cat <<EOF
whisper.cpp executable:
  $WHISPER_DIR/build/bin/whisper-cli

whisper.cpp server:
  $WHISPER_DIR/build/bin/whisper-server

model:
  $MODEL_FILE
EOF
