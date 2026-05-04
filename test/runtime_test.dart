import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  group('TTSRuntime', () {
    test('singleton instance', () {
      expect(TTSRuntime.instance, same(TTSRuntime.instance));
    });

    test('acquire/release cycle', () async {
      final runtime = TTSRuntime.instance;
      runtime.resetStop();
      final engine = _TestEngine();
      final result = await runtime.acquire(engine, () async => 'done');
      expect(result, equals('done'));
      expect(runtime.currentEngine, same(engine));
    });

    test('stop blocks further operations', () async {
      final runtime = TTSRuntime.instance;
      runtime.resetStop();
      await runtime.stop();
      final engine = _TestEngine();
      await expectLater(
        runtime.acquire(engine, () async {}),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _TestEngine extends Engine {
  bool loaded = false;
  bool stopped = false;

  @override
  EngineId get id => EngineId.kitten;

  @override
  Future<EngineStatus> checkStatus() async =>
      const EngineStatus(state: EngineState.installed);

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<List<Voice>> getVoices() async => [];

  @override
  Future<void> load() async => loaded = true;

  @override
  Future<void> play(
    String text,
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {}

  @override
  StreamingHandle playStreaming(
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> release() async => loaded = false;
}
