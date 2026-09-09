---
name: neural-tts-usage
description: Build or modify Flutter apps that use neural_tts for on-device speech synthesis, model downloads, engine and voice selection, streaming, cancellation, phonemization, or stripping LLM reasoning text.
---

# Use neural_tts

Use the public API from `package:neural_tts/neural_tts.dart`. Target Android unless the package version in the project explicitly documents broader platform support, and configure Android `minSdk` to at least 24.

## Choose an engine

- Use `EngineId.kitten` for the smallest, fastest neural option.
- Use `EngineId.kokoro` for more expressive speech and a larger voice selection.
- Use `EngineId.supertonic` for higher-quality multilingual speech when its larger model and non-incremental synthesis are acceptable.
- Use `EngineId.system` when model-free OS speech is preferred. Its voices depend on the device, and it does not support streaming.

Create engines through `createEngine(EngineId)` rather than constructing implementation classes. Keep the selected `Engine` instance for reuse, and ensure a selected `Voice` came from that engine.

## Prepare a neural engine

Neural engines need their model files before playback. The System engine does not.

```dart
import 'package:neural_tts/neural_tts.dart';

Future<Engine> prepareEngine(
  EngineId engineId, {
  void Function(FileProgress progress)? onProgress,
}) async {
  final engine = createEngine(engineId);
  final status = await engine.checkStatus();

  if (status.isError) {
    throw StateError(status.error ?? 'Could not check TTS engine status');
  }

  if (!status.isInstalled) {
    final downloader = ModelDownloader();
    await for (final progress in downloader.downloadEngineFiles(engineId)) {
      onProgress?.call(progress);
    }
  }

  await engine.load();
  return engine;
}
```

Treat downloads as application state: expose progress from `FileProgress.fraction`, surface failures, and offer an explicit retry. `cancelDownload(engineId)` cancels an active download. Partial files are retained so a later download can resume. Use `deleteEngine(engineId)` to remove only that engine's model files; shared linguistic data is preserved.

Do not start multiple downloads concurrently. The downloader serializes file writes, so a simple sequential UI is clearest.

## Speak and manage the lifecycle

`play()` loads the engine automatically if needed and completes only after audio playback finishes. Still check installation before calling it for a neural engine.

```dart
final engine = await prepareEngine(EngineId.kokoro);
final voices = await engine.getVoices();
if (voices.isEmpty) {
  throw StateError('No voices are available for ${engine.id.name}');
}

final voice = voices.first;
await engine.play(
  'Hello from on-device speech.',
  voice,
  language: voice.language ?? 'en-us',
  rate: 1.0,
  pitch: 1.0,
  volume: 1.0,
);
```

- Await `play()` when later UI state depends on completion.
- Call `stop()` to interrupt current playback. An interrupted `play()` completes with an error; handle that as cancellation where appropriate.
- Call `release()` when the engine is no longer needed. It stops playback, waits for active inference, and disposes resources.
- An engine can be loaded again after `release()`.
- Stop or cancel active speech before switching engines.
- Avoid overlapping speech requests. If the app submits work from multiple sources, serialize it or use the exported `TTSRuntime` queue. After `TTSRuntime.stop()` or `release()`, call `TTSRuntime.instance.resetStop()` before acquiring new work.

## Stream generated text

Kitten and Kokoro buffer incomplete sentences, preserving words split across chunks. Only one native stream can be active at a time.

```dart
final voice = (await engine.getVoices()).first;
final handle = engine.playStreaming(
  voice,
  language: voice.language ?? 'en-us',
  rate: 1.0,
  volume: 1.0,
);

try {
  handle.appendText('This can arrive ');
  handle.appendText('in multiple chunks. ');
  handle.appendText('The last sentence is flushed at the end.');
  await handle.finalize();
} catch (_) {
  await handle.cancel();
  rethrow;
}
```

- Always call and await `finalize()` when input ends; it flushes buffered text and waits for playback.
- Call and await `cancel()` when abandoning a response or before switching native engines.
- `finalize()` and `cancel()` are idempotent, but `appendText()` throws after either closes the handle.
- Append failures are reported by `finalize()`.
- Do not call `playStreaming()` on `EngineId.system`.
- Supertonic accepts the streaming interface but buffers all text and synthesizes only in `finalize()`; it does not provide incremental audio.
- `audioLevelStream` is currently empty. Do not build visualization or completion logic around it.

## Strip LLM reasoning

For a complete response, remove `<think>...</think>` blocks before speaking:

```dart
final result = ThinkingStripper.stripFinal(modelResponse);
if (result.text.trim().isNotEmpty) {
  await engine.play(result.text, voice);
}
```

For streamed model output, keep one `ThinkingStripper` for the whole response and forward only cleaned text:

```dart
final stripper = ThinkingStripper();
final speech = engine.playStreaming(voice);

try {
  await for (final modelChunk in modelChunks) {
    final visibleText = stripper.feed(modelChunk);
    if (visibleText.isNotEmpty) speech.appendText(visibleText);
  }

  final remainder = stripper.flush();
  if (remainder.isNotEmpty) speech.appendText(remainder);
  await speech.finalize();
} catch (_) {
  await speech.cancel();
  rethrow;
}
```

Do not recreate the stripper for every chunk: tags can be split across chunk boundaries.

## Phonemization

Playback phonemizes neural-engine text by default. Pass a BCP-47-like language string such as `en-us`, and set `phonemize: false` only when text is already in the format expected by the backend or when phonemization is intentionally disabled.

Kitten and Kokoro can use eSpeak-NG data downloaded with their model files:

```dart
final downloader = ModelDownloader();
final ttsDir = await downloader.getTtsDir();
final phonemizer = EspeakPhonemizer(
  dataPath: ttsDir.path,
  language: 'en-us',
);

engine.setPhonemizer(phonemizer);
```

The `dataPath` must be the directory containing `espeak-ng-data/`, not the data directory itself. Dispose an `EspeakPhonemizer` when the app is finished with it. Supertonic ignores a Dart-side phonemizer, and System TTS receives ordinary text.

If the default linguistic archive is unavailable, pass a hosted archive to `ModelDownloader(espeakArchiveUrl: ...)`. That archive must contain an `espeak-ng-data/` directory.

## Respect engine-specific controls

- `rate`, `pitch`, and `volume` default to `1.0`.
- `inferenceSteps` is engine-specific; use it chiefly for Supertonic quality tuning and prefer the package default unless the UI intentionally exposes the tradeoff.
- Supertonic's Dart playback backend currently applies rate and volume but not pitch.
- Do not promise voice counts or languages without checking `getVoices()` and the selected `Voice` metadata at runtime.

## Verify changes

Run `flutter analyze` and the relevant Flutter tests. Playback correctness requires an Android device or emulator with audio support. From the package's `example/` directory, the device smoke test is:

```sh
flutter test integration_test/tts_smoke_test.dart -d <device-id>
```

Neural smoke tests skip missing models unless `--dart-define=DOWNLOAD_TTS_MODELS=true` is supplied; enabling it requires network access and several hundred MB of storage. System-engine tests also require an OS speech voice installed on the device.
