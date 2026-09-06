import 'dart:async';
import 'streaming_handle.dart';
import 'phonemizer.dart';

enum EngineId { kitten, kokoro, supertonic, system }

class Voice {
  final String id;
  final String name;
  final EngineId engine;
  final String? language;
  final String? gender;

  const Voice({
    required this.id,
    required this.name,
    required this.engine,
    this.language,
    this.gender,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Voice && runtimeType == other.runtimeType && id == other.id && engine == other.engine;

  @override
  int get hashCode => id.hashCode ^ engine.hashCode;
}

class EngineMeta {
  final String name;
  final String tagline;
  final int sizeMb;
  final int ramMb;
  final int voiceCount;
  final int accentColor;
  final bool hasQualitySelector;

  const EngineMeta({
    required this.name,
    required this.tagline,
    required this.sizeMb,
    required this.ramMb,
    required this.voiceCount,
    required this.accentColor,
    this.hasQualitySelector = false,
  });

  static const kitten = EngineMeta(
    name: 'Kitten',
    tagline: 'Lightning-fast neural TTS',
    sizeMb: 57,
    ramMb: 235,
    voiceCount: 8,
    accentColor: 0xFFF29547,
  );

  static const kokoro = EngineMeta(
    name: 'Kokoro',
    tagline: 'Expressive 82M param model',
    sizeMb: 170,
    ramMb: 510,
    voiceCount: 22,
    accentColor: 0xFF6F5CD6,
  );

  static const supertonic = EngineMeta(
    name: 'Supertonic',
    tagline: 'Studio-quality multilingual',
    sizeMb: 265,
    ramMb: 428,
    voiceCount: 10,
    accentColor: 0xFF1E4DF6,
    hasQualitySelector: true,
  );

  static const system = EngineMeta(
    name: 'System',
    tagline: 'Built-in OS TTS',
    sizeMb: 0,
    ramMb: 0,
    voiceCount: 0,
    accentColor: 0xFF6B7280,
  );

  static EngineMeta forEngine(EngineId id) {
    switch (id) {
      case EngineId.kitten:
        return kitten;
      case EngineId.kokoro:
        return kokoro;
      case EngineId.supertonic:
        return supertonic;
      case EngineId.system:
        return system;
    }
  }
}

enum EngineState { notInstalled, downloading, installed, error }

class EngineStatus {
  final EngineState state;
  final String? error;

  const EngineStatus({required this.state, this.error});

  bool get isNotInstalled => state == EngineState.notInstalled;
  bool get isDownloading => state == EngineState.downloading;
  bool get isInstalled => state == EngineState.installed;
  bool get isError => state == EngineState.error;
}

abstract class Engine {
  EngineId get id;

  Future<EngineStatus> checkStatus();

  Future<bool> isInstalled();

  Future<List<Voice>> getVoices();

  Future<void> load();

  /// Completes when audio finishes; interruption completes with an error.
  Future<void> play(
    String text,
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    bool phonemize = true,
  });

  StreamingHandle playStreaming(
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    bool phonemize = true,
  });

  Future<void> stop();

  /// Stops playback and disposes resources after active inference finishes.
  Future<void> release();

  void setPhonemizer(Phonemizer phonemizer);
}
