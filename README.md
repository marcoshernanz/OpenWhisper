# OpenWhisper

OpenWhisper is a macOS dictation app. Hold the `fn`/Globe key to record, or double-press `fn` to lock recording until the next `fn` press. With a Deepgram API key, recordings are transcribed by Deepgram's Nova-3; without one, they are transcribed on your Mac with WhisperKit. The final text is pasted into the focused app only after recording stops.

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

- Microphone permission, so OpenWhisper can record while `fn` is held or double-tap locked.
- Accessibility permission, so OpenWhisper can observe `fn` and paste the result.

macOS does not allow apps to grant Accessibility permission automatically. Use OpenWhisper's setup window to open the right System Settings pane, enable `OpenWhisper`, then relaunch OpenWhisper from the setup window.

Then focus any text field, hold `fn`, speak, and release `fn`. You can also double-press `fn` to keep recording hands-free, then press `fn` once more to stop. No dictation text is inserted while recording is active.

OpenWhisper downloads Argmax's Core ML WhisperKit model on first use and warms it in the background. The first launch can take a few minutes while the model downloads and Core ML specializes it for your Mac; after that, releasing `fn` should insert text much faster because OpenWhisper keeps the local model path warm.

To transcribe with Deepgram, choose Deepgram API Key... in the menu bar menu and paste your key. See [Deepgram](#deepgram).

Automatic language detection is the default so English and Spanish dictation stay in the language you spoke. If you mostly dictate in English and want the lowest latency, choose English from the Language menu or set `OPENWHISPER_LANGUAGE=en`.

Use the menu bar app to choose:

- Engine: Deepgram, WhisperKit, or whisper.cpp. Deepgram is the default whenever there is a Deepgram API key. Otherwise WhisperKit is, because it uses Apple Silicon/Core ML and downloads Argmax's recommended `openai_whisper-large-v3-v20240930_626MB` model on first use. whisper.cpp remains available as a fallback.
- Deepgram API Key...: add, replace, or remove the key OpenWhisper keeps in your Keychain.
- Language: English, Spanish, or Auto Detect. Auto Detect is the default bilingual-friendly mode; English remains available as the primary fixed-language mode for fastest short dictations.
- Quality: Fast, Balanced, or Accurate, for the engines that run on your Mac. Balanced is the default because it keeps `large-v3-turbo` fast while using full audio context and a small decoding search for better dictation quality. Fast keeps the lowest-latency short audio context; Accurate increases decoding search further.
- Model: Large v3 Turbo, Large v3, Distil Large v3, Medium English, Small English, Base English, or Tiny English. Models marked "Download Required" are not on disk yet; install them with `scripts/setup-whisper.sh <model>`.
- Cleanup: Off, Light, or Dictation. Cleanup runs locally after transcription and before the one final paste.

Recent Transcripts in the same menu lists your last 50 dictations, so one is not lost when a newer dictation replaces it. Click one to copy it to the clipboard. Paste Last Transcript (`ctrl+cmd+V`) pastes the newest one again.

## Deepgram

With a Deepgram API key, OpenWhisper uploads each recording to Deepgram once you stop recording, and pastes the transcript a second or two later. An eight-minute dictation takes about five seconds. Add the key from Deepgram API Key... in the menu, which checks it with Deepgram and saves it in your login Keychain, or save it yourself:

```sh
security add-generic-password -s dev.openwhisper.deepgram -a api-key -w
```

OpenWhisper reads the key through the `security` tool, so it doesn't ask for your password after each update. Any app running as you can read a key saved this way with that same tool.

- Model: Nova-3, Deepgram's most accurate model. It gets the whole recording once you stop, rather than a piece at a time while you speak, so it hears every sentence to the end before writing it.
- Language: Auto Detect uses Nova-3's January 2026 multilingual model, which follows switches between English and Spanish in the middle of a sentence. Its October 2026 version covers 68 languages and was less accurate in these two, mostly with technical terms and sentences that switch language. If Deepgram retires the January version, OpenWhisper uses the newest one. English and Spanish use Deepgram's model for that language.
- Vocabulary: the [custom vocabulary](#custom-vocabulary) becomes Deepgram keyterms. Deepgram accepts about 450 characters of them, and OpenWhisper sends as many terms as fit.
- Formatting: numbers are written as digits, such as "menos 1, 0, 1", and ordinals in Spanish as "1º".
- Privacy: recordings go to Deepgram over HTTPS, and each request asks Deepgram not to use the audio to improve its models.

When Deepgram can't transcribe a recording, for example without a connection, OpenWhisper transcribes it on your Mac with WhisperKit instead, loading the model the first time that happens. A key Deepgram rejects, or an account out of credits, shows an alert once per launch so you can fix it.

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
OPENWHISPER_LANGUAGE=auto \
OPENWHISPER_THREADS=8 \
OPENWHISPER_ENGINE=deepgram \
OPENWHISPER_DEEPGRAM_API_KEY=your-key \
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

The local server listens on `127.0.0.1:58442` by default when the whisper.cpp engine is selected. Override it with `OPENWHISPER_SERVER_HOST` and `OPENWHISPER_SERVER_PORT` if that port is already in use. `OPENWHISPER_THREADS` defaults to a conservative value based on your CPU core count. `OPENWHISPER_ENGINE=deepgram|whisperKit|whisperCpp`, `OPENWHISPER_DEEPGRAM_API_KEY` (instead of the Keychain), `OPENWHISPER_LANGUAGE=auto|en|es`, `OPENWHISPER_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_626MB`, `OPENWHISPER_QUALITY=fast|balanced|accurate`, `OPENWHISPER_MODEL_OPTION=large-v3-turbo|large-v3|distil-large-v3|medium.en|small.en|base.en|tiny.en`, and `OPENWHISPER_CLEANUP=off|light|dictation` override the menu settings for development. The default local path is WhisperKit; whisper.cpp uses `large-v3-turbo` as its best installed quality/speed fallback.

## Custom Vocabulary

Whisper can misspell names and technical terms, especially inside Spanish sentences. List the ones you use so it spells them the way you do:

```sh
defaults write dev.openwhisper.OpenWhisper InitialPrompt "GitHub, AirPods, OpenWhisper, WhisperKit, pull request."
```

Restart OpenWhisper after changing it. Keep the list short:

- Deepgram reads about 450 characters of it, roughly 50 terms like these, and treats each term separately.
- WhisperKit only reads the last 111 tokens of it, roughly 30 terms like these.
- Whisper reads the whole list again for every stretch of audio, so each token makes every dictation slower. A 107-token list takes a short dictation from about 1.5 to about 3.5 seconds on an M4 Mac.
- Whisper writes at most 224 tokens for each stretch of audio, counting the list. OpenWhisper transcribes long dictations in shorter stretches, cut at pauses, so the transcript always fits, and the longer the list, the more stretches that takes.
- A long or off-topic list can nudge unrelated words.

`OPENWHISPER_PROMPT` overrides it for development. Remove it with `defaults delete dev.openwhisper.OpenWhisper InitialPrompt`.

## Where Your Audio Goes

Audio is streamed into a temporary local 16 kHz mono WAV file while `fn` recording is active. After recording stops, it is uploaded to Deepgram when Deepgram is the engine, or transcribed on your Mac with WhisperKit or whisper.cpp, which use no network services once their model is downloaded. The text is optionally cleaned up locally, inserted into the focused app once, then the temporary file is removed. If transcription fails, the file is kept until you choose Try Again or Discard Recording, so a long dictation is not lost.

The text of your last 50 dictations stays on disk in `~/Library/Application Support/OpenWhisper/TranscriptHistory.json` for Recent Transcripts. Clear History in that menu deletes it.

## fn Key Notes

The `fn`/Globe key is exposed by macOS as a function modifier flag. If macOS built-in dictation or Globe-key shortcuts are configured to use the same key, disable or remap those shortcuts in System Settings before using OpenWhisper.

## Audio Input Notes

OpenWhisper records from the macOS default input device. When that changes, for example when AirPods connect and become the default microphone, OpenWhisper rebuilds its audio engine for the new device, including in the middle of a dictation.

When the default input is Bluetooth headphones such as AirPods, OpenWhisper uses their microphone unless something is playing through them. Recording from them switches them to their headset profile, which cuts playback for about a second when recording starts and stops and lowers its quality in between, so while audio is playing OpenWhisper records from the Mac's built-in microphone instead. With the lid closed, the built-in microphone cannot hear anything, so OpenWhisper uses the headphones. OpenWhisper releases the microphone after every dictation, so the headphones return to full quality right away. The first half second of a dictation through the headphones is silent while they switch profiles. To always use the default input:

```sh
defaults write dev.openwhisper.OpenWhisper UseBuiltInMicrophoneDuringPlayback -bool false
```

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
