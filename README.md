# neural_tts

[![Pub Version](https://img.shields.io/pub/v/neural_tts)](https://pub.dev/packages/neural_tts)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)

A high-performance, on-device neural Text-to-Speech (TTS) engine for Flutter. Powered by native ONNX Runtime, it brings state-of-the-art speech synthesis to your Android applications without requiring an internet connection for inference.

## ✨ Features

- 🚀 **Multiple Neural Engines**: Choose the perfect balance between speed, quality, and size.
- 📱 **Android Support**: Currently optimized and supported exclusively for Android devices.
- ⚡ **Native Performance**: Leverages ONNX Runtime with platform-specific optimizations.
- 🗣️ **Multilingual IPA**: Integrated Espeak-NG for accurate phonemization in 100+ languages.
- 🧠 **AI-Ready**: Built-in `ThinkingStripper` to handle LLM reasoning blocks (`<think>`) automatically.
- 🎙️ **Rich Voice Library**: Support for dozens of expressive voices across multiple languages and accents.
- 🎚️ **Granular Control**: Adjust rate, pitch, volume, and engine-specific parameters.
- 🌊 **Streaming Support**: Real-time speech generation for interactive applications.

---

## 🏗️ Engine Comparison

| Engine | Tagline | Model Size | RAM Usage | Voices | Best For |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Kitten** | Lightning-fast neural TTS | ~57 MB | ~235 MB | 8 | Ultra-fast response, lower-end devices |
| **Kokoro** | Expressive 82M param model | ~170 MB | ~510 MB | 22 | High-quality natural narration |
| **Supertonic** | Studio-quality multilingual | ~265 MB | ~428 MB | 10 | Premium, professional-grade speech |
| **System** | Built-in OS TTS | 0 MB | 0 MB | OS Dependent | Fallback, system accessibility |

---

## 🚀 Getting Started

### 1. Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  neural_tts: ^0.1.0
```

### 2. Native Setup

#### Android
Ensure your `minSdkVersion` is at least **21** in `android/app/build.gradle`.

---

## 📖 Usage

### Initializing an Engine

Engines are managed via a registry. You can create a specific engine using its ID:

```dart
import 'package:neural_tts/neural_tts.dart';

final engine = createEngine(EngineId.kokoro);
```

### Downloading Models

Before using a neural engine, you must download its model files. This is handled by the `ModelDownloader`:

```dart
final downloader = ModelDownloader();

// Stream download progress
final stream = downloader.downloadEngineFiles(EngineId.kokoro);
await for (final progress in stream) {
  print('Downloading ${progress.fileName}: ${progress.progress.toStringAsFixed(2)}%');
}
```

### Basic Playback

Once the engine is installed, you can list voices and start speaking:

```dart
// Check if installed
final status = await engine.checkStatus();
if (status.isInstalled) {
  // Get available voices
  final voices = await engine.getVoices();
  final myVoice = voices.first;

  // Play text
  await engine.play(
    "Hello! I am speaking locally on your device.",
    myVoice,
    rate: 1.0,
    pitch: 1.0,
  );
}
```

### Handling AI Reasoning (Thinking Stripper)

If you are using this with an LLM that outputs `<think>` blocks, use the `ThinkingStripper` to ensure the TTS only reads the final response:

```dart
final text = "<think>The user wants a greeting.</think>Hello there! How can I help?";
final result = ThinkingStripper.stripFinal(text);

print(result.text); // "Hello there! How can I help?"
if (result.hadReasoning) {
  print("Stripped reasoning blocks.");
}

await engine.play(result.text, myVoice);
```

### 🧠 Phonemization (Espeak-NG)

For improved IPA accuracy and support for 100+ languages, `neural_tts` integrates **Espeak-NG**. This provides state-of-the-art text-to-phoneme conversion, ensuring natural pronunciation across diverse linguistic rules.

#### 1. Compile Linguistic Data
Run the included helper script to compile binary phoneme data for your target languages. The script will automatically compress the data into a ZIP archive:
```bash
# Compiles English (US), Spanish, and French
dart run neural_tts:compile_espeak_data --languages=en-us,es,fr
```
This generates an `espeak-data/espeak-ng-data.zip` file. You can host this file on your own server or use the default provided URL.

#### 2. Runtime Download (Recommended)
`neural_tts` is designed to download and extract linguistic data at runtime, similar to how it handles ONNX models. This keeps your initial app size small.

The `ModelDownloader` will automatically fetch the data if it's missing when you download an engine:
```dart
final downloader = ModelDownloader();
final stream = downloader.downloadEngineFiles(EngineId.kokoro);
// ... espeak-ng-data.zip will be downloaded and extracted automatically
```

#### 3. Initialization
Once downloaded, initialize the phonemizer by pointing it to the TTS directory:
```dart
final downloader = ModelDownloader();
final ttsDir = await downloader.getTtsDir();
final status = await engine.checkStatus();

if (status.isInstalled) {
  final espeakPhonemizer = EspeakPhonemizer(
    dataPath: ttsDir.path,
    language: 'en-us',
  );
  
  engine.setPhonemizer(espeakPhonemizer);
}
```
Once set, the engine will use Espeak-NG for high-fidelity IPA generation during all playback calls.

---

### Advanced Controls

```dart
await engine.play(
  text,
  voice,
  rate: 1.2,        // Speed (0.5 to 2.0)
  pitch: 1.0,       // Tone
  volume: 1.0,      // Loudness
  inferenceSteps: 5 // Engine specific quality tuning
);

// Stop playback
await engine.stop();
```

---

## 🛠️ Roadmap & Future Plans

- [ ] Support for more languages (Bengali, Hindi, Spanish, etc.)
- [ ] Fine-tuned custom voice support.
- [ ] Improved streaming latency for long-form content.
- [ ] Web and Desktop support via ONNX Runtime Web/C++.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">Made with ❤️ for the LocalMind Ecosystem</p>
