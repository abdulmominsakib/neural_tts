# Changelog

## 0.4.1

- Add a distributable `neural-tts-usage` agent skill with guidance for setup,
  model downloads, playback, streaming, phonemization, and LLM output handling.
- Fix queued runtime cancellation, engine ownership, and load-error propagation.
- Await playback completion and make native stop responsive during inference.
- Preserve streaming settings and reject use of closed or competing streams.
- Fix System TTS initialization and close native/Dart ONNX resources on failure.
- Repair resumed downloads, atomic voice downloads, and staged linguistic-data extraction.
- Restore the example manifest, document Android API 24, and add regression tests.

## 0.4.0

- feat: add phonemization support to TTS engines and implement eSpeak-ng data management and extraction
- Update project metadata and license for public release

## 0.3.0

- refactor: update SupertonicSession to use FloatBuffer for ONNX tensor creation and add error handling for TTS pipeline stages

## 0.2.0

- refactor: optimize AudioTrack playback by reusing instances and removing blocking spin-locks in engine classes.

## 0.1.0

- feat: implement KokoroEngine and update platform-specific native plugin code
