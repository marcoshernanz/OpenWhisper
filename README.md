# OpenWhisper

OpenWhisper is a local-only macOS dictation app. Hold the `fn`/Globe key to record, release it to transcribe locally with WhisperKit by default, and the final text is pasted into the focused app only after release.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- CMake
- Apple Silicon recommended

## Quick Start

```sh
scripts/install-app.sh
```

This installs and opens `/Applications/OpenWhisper.app`. On first launch, OpenWhisper shows a setup window for:

- Microphone permission, so OpenWhisper can record while `fn` is held.
- Accessibility permission, so OpenWhisper can observe `fn` and paste the result.

macOS does not allow apps to grant Accessibility permission automatically. Use OpenWhisper's setup window to open the right System Settings pane, enable `OpenWhisper`, then relaunch OpenWhisper from the setup window.

Then focus any text field, hold `fn`, speak, and release `fn`. No dictation text is inserted while the key is held.

OpenWhisper downloads Argmax's Core ML WhisperKit model on first use and warms it in the background. The first launch can take a few minutes while the model downloads and Core ML specializes it for your Mac; after that, releasing `fn` should insert text much faster because OpenWhisper keeps the local model path warm.

English is the default recognition language because automatic language detection adds latency to short dictations. Set `OPENWHISPER_LANGUAGE=auto` if you need multilingual detection and can accept the extra latency.

Use the menu bar app to choose:

- Engine: WhisperKit or whisper.cpp. WhisperKit is the default local engine because it uses Apple Silicon/Core ML and downloads Argmax's recommended `openai_whisper-large-v3-v20240930_626MB` model on first use. whisper.cpp remains available as a fallback.
- Quality: Fast, Balanced, or Accurate. Balanced is the default because it keeps `large-v3-turbo` fast while using full audio context and a small decoding search for better dictation quality. Fast keeps the lowest-latency short audio context; Accurate increases decoding search further.
- Model: Large v3 Turbo, Large v3, Distil Large v3, Medium English, Small English, Base English, or Tiny English. Models marked "Download Required" are not on disk yet; install them with `scripts/setup-whisper.sh <model>`.
- Cleanup: Off, Light, or Dictation. Cleanup runs locally after transcription and before the one final paste.

## Runtime Configuration

The WhisperKit engine is the default and stores downloaded Core ML models under:

```text
~/Library/Application Support/OpenWhisper/WhisperKit
```

The optional whisper.cpp fallback expects:

```text
Dependencies/whisper.cpp/build/bin/whisper-cli
Dependencies/whisper.cpp/build/bin/whisper-server
Models/ggml-large-v3-turbo.bin
```

Override those paths when launching from a shell:

```sh
OPENWHISPER_WHISPER_BIN=/path/to/whisper-cli \
OPENWHISPER_SERVER_BIN=/path/to/whisper-server \
OPENWHISPER_MODEL=/path/to/ggml-large-v3-turbo.bin \
OPENWHISPER_LANGUAGE=en \
OPENWHISPER_THREADS=8 \
OPENWHISPER_ENGINE=whisperKit \
OPENWHISPER_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_626MB \
OPENWHISPER_QUALITY=balanced \
OPENWHISPER_MODEL_OPTION=large-v3-turbo \
OPENWHISPER_CLEANUP=dictation \
.build/OpenWhisper.app/Contents/MacOS/OpenWhisper
```

Install whisper.cpp fallback models before selecting them in the menu:

```sh
scripts/setup-whisper.sh large-v3
scripts/setup-whisper.sh distil-large-v3
scripts/setup-whisper.sh medium.en
```

The local server listens on `127.0.0.1:58442` by default when the whisper.cpp engine is selected. Override it with `OPENWHISPER_SERVER_HOST` and `OPENWHISPER_SERVER_PORT` if that port is already in use. `OPENWHISPER_THREADS` defaults to a conservative value based on your CPU core count. `OPENWHISPER_ENGINE=whisperKit|whisperCpp`, `OPENWHISPER_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_626MB`, `OPENWHISPER_QUALITY=fast|balanced|accurate`, `OPENWHISPER_MODEL_OPTION=large-v3-turbo|large-v3|distil-large-v3|medium.en|small.en|base.en|tiny.en`, and `OPENWHISPER_CLEANUP=off|light|dictation` override the menu settings for development. The default local path is WhisperKit; whisper.cpp uses `large-v3-turbo` as its best installed quality/speed fallback.

## Local-Only Behavior

Runtime dictation does not use network services after the local model is downloaded. Audio is streamed into a temporary local 16 kHz mono WAV file while `fn` is held, transcribed locally with WhisperKit or whisper.cpp, optionally cleaned up locally, inserted into the focused app once after release, then the temporary file is removed.

## fn Key Notes

The `fn`/Globe key is exposed by macOS as a function modifier flag. If macOS built-in dictation or Globe-key shortcuts are configured to use the same key, disable or remap those shortcuts in System Settings before using OpenWhisper.

## Build an App Bundle

```sh
scripts/build-app.sh release
open .build/OpenWhisper.app
```

## Development Run

```sh
scripts/run-dev.sh
```

Development builds run from `.build/OpenWhisper.app`, so macOS may show that path in permission lists instead of `/Applications/OpenWhisper.app`. Use `scripts/install-app.sh` when testing permissions like a normal app.
