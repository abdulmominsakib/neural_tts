import '../engine.dart';

enum KittenVariant {
  nano,
  nanoInt8,
  micro,
  mini;

  String get displayName {
    switch (this) {
      case KittenVariant.nano:
        return 'Kitten TTS Nano';
      case KittenVariant.nanoInt8:
        return 'Kitten TTS Nano (Int8)';
      case KittenVariant.micro:
        return 'Kitten TTS Micro';
      case KittenVariant.mini:
        return 'Kitten TTS Mini';
    }
  }

  int get totalSizeBytes {
    switch (this) {
      case KittenVariant.nano:
        return 57 * 1024 * 1024;
      case KittenVariant.nanoInt8:
        return 25 * 1024 * 1024;
      case KittenVariant.micro:
        return 41 * 1024 * 1024;
      case KittenVariant.mini:
        return 80 * 1024 * 1024;
    }
  }

  String get huggingFaceRepoId {
    switch (this) {
      case KittenVariant.nano:
        return 'palshub/kitten-tts-nano-0.8-fp32';
      case KittenVariant.nanoInt8:
        return 'palshub/kitten-tts-nano-0.8-int8';
      case KittenVariant.micro:
        return 'palshub/kitten-tts-micro-0.8';
      case KittenVariant.mini:
        return 'palshub/kitten-tts-mini-0.8';
    }
  }

  String get modelFileName {
    switch (this) {
      case KittenVariant.nano:
      case KittenVariant.nanoInt8:
        return 'kitten_tts_nano_v0_8.onnx';
      case KittenVariant.micro:
        return 'kitten_tts_micro_v0_8.onnx';
      case KittenVariant.mini:
        return 'kitten_tts_mini_v0_8.onnx';
    }
  }

  List<ModelFile> get files {
    return [
      ModelFile(
        fileName: 'config.json',
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/config.json',
        sizeBytes: 2 * 1024,
      ),
      ModelFile(
        fileName: modelFileName,
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/$modelFileName',
        sizeBytes: _modelFileSizeBytes,
      ),
      ModelFile(
        fileName: 'voices.npz',
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/voices.npz',
        sizeBytes: 3 * 1024 * 1024,
      ),
    ];
  }

  int get _modelFileSizeBytes {
    switch (this) {
      case KittenVariant.nano:
        return 52 * 1024 * 1024;
      case KittenVariant.nanoInt8:
        return 21 * 1024 * 1024;
      case KittenVariant.micro:
        return 37 * 1024 * 1024;
      case KittenVariant.mini:
        return 76 * 1024 * 1024;
    }
  }
}

const kittenVoices = [
  Voice(id: 'expr-voice-2-f', name: 'Bella', engine: EngineId.kitten, gender: 'f'),
  Voice(id: 'expr-voice-3-f', name: 'Luna', engine: EngineId.kitten, gender: 'f'),
  Voice(id: 'expr-voice-4-f', name: 'Rosie', engine: EngineId.kitten, gender: 'f'),
  Voice(id: 'expr-voice-5-f', name: 'Kiki', engine: EngineId.kitten, gender: 'f'),
  Voice(id: 'expr-voice-2-m', name: 'Jasper', engine: EngineId.kitten, gender: 'm'),
  Voice(id: 'expr-voice-3-m', name: 'Bruno', engine: EngineId.kitten, gender: 'm'),
  Voice(id: 'expr-voice-4-m', name: 'Hugo', engine: EngineId.kitten, gender: 'm'),
  Voice(id: 'expr-voice-5-m', name: 'Leo', engine: EngineId.kitten, gender: 'm'),
];

const kokoroVoices = [
  Voice(id: 'af_heart', name: 'Heart', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_bella', name: 'Bella', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_nicole', name: 'Nicole', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_sarah', name: 'Sarah', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_sky', name: 'Sky', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_aoede', name: 'Aoede', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_jessica', name: 'Jessica', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_kore', name: 'Kore', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'af_river', name: 'River', engine: EngineId.kokoro, gender: 'f'),
  Voice(id: 'am_adam', name: 'Adam', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_echo', name: 'Echo', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_eric', name: 'Eric', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_fenrir', name: 'Fenrir', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_liam', name: 'Liam', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_michael', name: 'Michael', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_onyx', name: 'Onyx', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'am_santa', name: 'Santa', engine: EngineId.kokoro, gender: 'm'),
  Voice(id: 'bf_alice', name: 'Alice', engine: EngineId.kokoro, gender: 'f', language: 'en-GB'),
  Voice(id: 'bf_emma', name: 'Emma', engine: EngineId.kokoro, gender: 'f', language: 'en-GB'),
  Voice(id: 'bf_lily', name: 'Lily', engine: EngineId.kokoro, gender: 'f', language: 'en-GB'),
  Voice(id: 'bm_george', name: 'George', engine: EngineId.kokoro, gender: 'm', language: 'en-GB'),
  Voice(id: 'bm_lewis', name: 'Lewis', engine: EngineId.kokoro, gender: 'm', language: 'en-GB'),
];

const supertonicVoices = [
  Voice(id: 'F1', name: 'Sarah', engine: EngineId.supertonic, gender: 'f'),
  Voice(id: 'F2', name: 'Lily', engine: EngineId.supertonic, gender: 'f'),
  Voice(id: 'F3', name: 'Jessica', engine: EngineId.supertonic, gender: 'f'),
  Voice(id: 'F4', name: 'Olivia', engine: EngineId.supertonic, gender: 'f'),
  Voice(id: 'F5', name: 'Emily', engine: EngineId.supertonic, gender: 'f'),
  Voice(id: 'M1', name: 'Alex', engine: EngineId.supertonic, gender: 'm'),
  Voice(id: 'M2', name: 'James', engine: EngineId.supertonic, gender: 'm'),
  Voice(id: 'M3', name: 'Robert', engine: EngineId.supertonic, gender: 'm'),
  Voice(id: 'M4', name: 'Sam', engine: EngineId.supertonic, gender: 'm'),
  Voice(id: 'M5', name: 'Daniel', engine: EngineId.supertonic, gender: 'm'),
];

List<Voice> voicesForEngine(EngineId engine) {
  switch (engine) {
    case EngineId.kitten:
      return [...kittenVoices];
    case EngineId.kokoro:
      return [...kokoroVoices];
    case EngineId.supertonic:
      return [...supertonicVoices];
    case EngineId.system:
      return [];
  }
}

class ModelFile {
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;

  const ModelFile({
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
  });
}

class FileProgress {
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  final bool isComplete;

  const FileProgress({
    required this.fileName,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.isComplete = false,
  });

  double get fraction => isComplete
      ? 1.0
      : totalBytes > 0
      ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
      : 0.0;
}
