import 'dart:async';
import '../engine.dart';
import '../streaming_handle.dart';
import '../phonemizer.dart';
import '../platform/tts_platform.dart';

class SystemEngine extends Engine {
  @override
  void setPhonemizer(Phonemizer phonemizer) {
    // System engine uses OS-native phonemization.
  }

  @override
  EngineId get id => EngineId.system;

  @override
  Future<EngineStatus> checkStatus() async {
    return const EngineStatus(state: EngineState.installed);
  }

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<List<Voice>> getVoices() async {
    try {
      return await TtsPlatform.instance.getAvailableVoices();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> load() async {
    await TtsPlatform.instance.initialize({
      'engine': 'os_native',
    });
  }

  @override
  Future<void> play(
    String text,
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    bool phonemize = true,
  }) async {
    await TtsPlatform.instance.speak({
      'text': text,
      'voiceId': voice.id,
      'language': language ?? 'en',
      'rate': rate,
      'pitch': pitch,
      'volume': volume,
    });
  }

  @override
  StreamingHandle playStreaming(
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    bool phonemize = true,
  }) {
    throw UnsupportedError('System engine does not support streaming');
  }

  @override
  Future<void> stop() async {
    await TtsPlatform.instance.stop();
  }

  @override
  Future<void> release() async {
    await TtsPlatform.instance.release();
  }
}
