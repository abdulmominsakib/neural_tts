import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  group('TTSRuntime', () {
    setUp(() async {
      await TTSRuntime.instance.release();
      TTSRuntime.instance.resetStop();
    });
    tearDown(() => TTSRuntime.instance.release());

    test('FIFO and reuse the active engine', () async {
      final runtime = TTSRuntime.instance;
      final engine = _TestEngine();
      final events = <int>[];
      await Future.wait(
        List.generate(
          3,
          (i) => runtime.acquire(engine, () async {
            events.add(i);
          }),
        ),
      );
      expect(events, [0, 1, 2]);
      expect(engine.loads, 1);
    });

    test('load failure settles caller and queue continues', () async {
      final runtime = TTSRuntime.instance;
      final broken = _TestEngine()..loadError = StateError('load failed');
      final bad = runtime.acquire(broken, () async => fail('must not run'));
      final check = expectLater(bad, throwsStateError);
      final good = runtime.acquire(_TestEngine(), () async => 42);
      await check;
      expect(await good, 42);
    });

    test('stop settles active and queued calls during load', () async {
      final runtime = TTSRuntime.instance;
      final loading = Completer<void>();
      final started = Completer<void>();
      final engine = _TestEngine()
        ..loadGate = loading.future
        ..loadStarted = started;
      final active = runtime.acquire(
        engine,
        () async => fail('cancelled action ran'),
      );
      final activeCheck = expectLater(active, throwsStateError);
      final queued = runtime.acquire(
        _TestEngine(),
        () async => fail('queued action ran'),
      );
      final queuedCheck = expectLater(queued, throwsStateError);
      await started.future;
      final release = runtime.release();
      await Future.wait([activeCheck, queuedCheck]);
      expect(engine.releases, 0);
      loading.complete();
      await release;
      expect(runtime.currentEngine, isNull);
      runtime.resetStop();
      expect(
        await runtime.acquire(_TestEngine(), () async => 'again'),
        'again',
      );
    });

    test('stop during playback and repeated release', () async {
      final runtime = TTSRuntime.instance;
      final playing = Completer<void>();
      final started = Completer<void>();
      final engine = _TestEngine()
        ..onStop = () {
          if (!playing.isCompleted) playing.complete();
        };
      final call = runtime.acquire(engine, () async {
        started.complete();
        await playing.future;
      });
      final check = expectLater(call, throwsStateError);
      await started.future;
      await runtime.stop();
      await check;
      await Future.wait([runtime.release(), runtime.release()]);
      expect(runtime.currentEngine, isNull);
      expect(engine.releases, 1);
    });

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
  int loads = 0;
  int releases = 0;
  Object? loadError;
  Future<void>? loadGate;
  Completer<void>? loadStarted;
  void Function()? onStop;
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
  Future<void> load() async {
    loads++;
    loadStarted?.complete();
    await loadGate;
    if (loadError != null) throw loadError!;
    loaded = true;
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
  }) async {}

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
    throw UnimplementedError();
  }

  @override
  Future<void> stop() async {
    stopped = true;
    onStop?.call();
  }

  @override
  Future<void> release() async {
    releases++;
    loaded = false;
  }

  @override
  void setPhonemizer(Phonemizer phonemizer) {}
}
