# OpenWhisper

OpenWhisper is a local-only macOS dictation app. Hold the `fn`/Globe key to record, release it to transcribe locally with whisper.cpp, and the final text is pasted into the focused app only after release.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- CMake
- Apple Silicon recommended

## Quick Start

```sh
scripts/setup-whisper.sh large-v3-turbo
scripts/install-app.sh
```

This installs and opens `/Applications/OpenWhisper.app`. On first launch, OpenWhisper shows a setup window for:

- Microphone permission, so OpenWhisper can record while `fn` is held.
- Accessibility permission, so OpenWhisper can observe `fn` and paste the result.

macOS does not allow apps to grant Accessibility permission automatically. Use OpenWhisper's setup window to open the right System Settings pane, enable `OpenWhisper`, then relaunch OpenWhisper from the setup window.

Then focus any text field, hold `fn`, speak, and release `fn`. No dictation text is inserted while the key is held.

OpenWhisper starts a local `whisper-server` when the app launches so the model stays loaded between dictations. The first launch can take several seconds while the model loads; after that, releasing `fn` should insert text much faster because OpenWhisper does not reload the model for every recording.

English is the default recognition language because whisper.cpp's automatic language detection adds several seconds to short dictations. Set `OPENWHISPER_LANGUAGE=auto` if you need multilingual detection and can accept the extra latency.

## Runtime Configuration

The default setup expects:

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
OPENWHISPER_AUDIO_CONTEXT=512 \
.build/OpenWhisper.app/Contents/MacOS/OpenWhisper
```

The local server listens on `127.0.0.1:58442` by default. Override it with `OPENWHISPER_SERVER_HOST` and `OPENWHISPER_SERVER_PORT` if that port is already in use. `OPENWHISPER_THREADS` defaults to a conservative value based on your CPU core count. `OPENWHISPER_AUDIO_CONTEXT=512` is tuned for low-latency short dictation; set it to `0` to use Whisper's full audio context.

## Local-Only Behavior

Runtime dictation does not use network services. Audio is written to a temporary local file, converted locally with `afconvert`, transcribed locally with whisper.cpp, inserted into the focused app, then the temporary files are removed.

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
