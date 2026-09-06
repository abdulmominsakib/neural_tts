import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';
import 'package:neural_tts/src/engines/native_engine.dart';

class TestEngine extends NativeEngine {
  @override
  final EngineId id;
  TestEngine(this.id);
  @override
  Future<Map<String, dynamic>> initializationArguments() async => {
    'engine': id.name,
  };
  @override
  Future<List<Voice>> getVoices() async => [];
}

class FakePlatform extends TtsPlatform {
  final events = <String>[];
  final appends = <Map<String, dynamic>>[];
  Map<String, dynamic>? finalized;
  Object? initError;
  Object? appendError;
  Completer<void>? playback;
  @override
  Future<void> initialize(Map<String, dynamic> args) async {
    events.add('load:${args['engine']}');
    if (initError != null) throw initError!;
  }

  @override
  Future<void> speak(Map<String, dynamic> args) async {
    events.add('speak:${args['engine']}');
    await playback?.future;
  }

  @override
  Future<void> streamAppend(Map<String, dynamic> args) async {
    events.add('append');
    if (appendError != null) throw appendError!;
    appends.add(args);
  }

  @override
  Future<void> streamFinalize(Map<String, dynamic> args) async {
    finalized = args;
    events.add('finalize');
    await playback?.future;
  }

  @override
  Future<void> streamCancel(Map<String, dynamic> args) async {}
  @override
  Future<void> stop() async {
    events.add('stop');
    if (playback != null && !playback!.isCompleted) playback!.complete();
  }

  @override
  Future<void> release() async => events.add('release');
  @override
  Future<List<Voice>> getAvailableVoices() async => [];
}

void main() {
  late FakePlatform platform;
  late TestEngine kitten;
  late TestEngine kokoro;
  late TtsPlatform original;
  const voice = Voice(id: 'custom', name: 'Custom', engine: EngineId.kitten);
  setUp(() {
    original = TtsPlatform.instance;
    TtsPlatform.instance = platform = FakePlatform();
    kitten = TestEngine(EngineId.kitten);
    kokoro = TestEngine(EngineId.kokoro);
  });
  tearDown(() async {
    await kitten.release();
    await kokoro.release();
    TtsPlatform.instance = original;
  });
  test(
    'engine switching reloads and stale stop does not target active engine',
    () async {
      await kitten.load();
      await kokoro.load();
      final before = platform.events.length;
      await kitten.stop();
      expect(platform.events.length, before);
      await kitten.play('hello', voice, phonemize: false);
      expect(platform.events, [
        'load:kitten',
        'release',
        'load:kokoro',
        'release',
        'load:kitten',
        'speak:kitten',
      ]);
    },
  );
  test(
    'system selects the native system identifier and loads before play',
    () async {
      final engine = SystemEngine();
      await engine.play('hello', voice);
      expect(platform.events, ['load:system', 'speak:system']);
      await engine.release();
    },
  );
  test(
    'stream preserves split words and settings through finalization',
    () async {
      final stream = kitten.playStreaming(
        voice,
        language: 'fr',
        rate: 1.2,
        pitch: 0.9,
        volume: 0.5,
        inferenceSteps: 7,
        phonemize: false,
      );
      stream.appendText('Hel');
      stream.appendText('lo. ');
      stream.appendText('Goodbye');
      await stream.finalize();
      await stream.finalize();
      expect(platform.appends.map((a) => a['text']), ['Hello. ', 'Goodbye']);
      expect(platform.events.first, 'load:kitten');
      expect(platform.events.where((e) => e == 'finalize').length, 1);
      expect(platform.finalized, containsPair('voiceId', 'custom'));
      expect(platform.finalized, containsPair('language', 'fr'));
      expect(platform.finalized, containsPair('rate', 1.2));
      expect(platform.finalized, containsPair('pitch', 0.9));
      expect(platform.finalized, containsPair('volume', 0.5));
      expect(platform.finalized, containsPair('inferenceSteps', 7));
      expect(platform.finalized, containsPair('isPhonemized', false));
      expect(() => stream.appendText('late'), throwsStateError);
      expect(stream.isActive, isFalse);
    },
  );
  test('append initialization errors reach finalize', () async {
    platform.initError = StateError('load failed');
    final stream = kitten.playStreaming(voice, phonemize: false);
    stream.appendText('Hello. ');
    await expectLater(stream.finalize(), throwsStateError);
  });
  test('append errors reach finalize without an unhandled future', () async {
    platform.appendError = StateError('append failed');
    final stream = kitten.playStreaming(voice, phonemize: false);
    stream.appendText('Hello. ');
    await expectLater(stream.finalize(), throwsStateError);
  });
  test('competing stream rejected and cancelled handle stays closed', () async {
    final stream = kitten.playStreaming(voice, phonemize: false);
    expect(() => kokoro.playStreaming(voice), throwsStateError);
    await stream.cancel();
    await stream.cancel();
    expect(() => stream.appendText('late'), throwsStateError);
    await expectLater(stream.finalize(), throwsStateError);
    final next = kokoro.playStreaming(voice, phonemize: false);
    await next.cancel();
  });
  test('play remains pending until playback completes', () async {
    platform.playback = Completer<void>();
    var completed = false;
    final play = kitten
        .play('hello', voice, phonemize: false)
        .then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    platform.playback!.complete();
    await play;
    expect(completed, isTrue);
  });
  test('finalize shares pending completion and remains cancellable', () async {
    platform.playback = Completer<void>();
    final stream = kitten.playStreaming(voice, phonemize: false);
    stream.appendText('Hello');
    final finalized = stream.finalize();
    expect(identical(finalized, stream.finalize()), isTrue);
    final interrupted = expectLater(finalized, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(platform.events.last, 'finalize');
    await stream.cancel();
    await interrupted;
  });
  test(
    'a failed stream releases its reservation for subsequent playback',
    () async {
      platform.appendError = StateError('append failed');
      final stream = kitten.playStreaming(voice, phonemize: false);
      stream.appendText('Hello');
      await expectLater(stream.finalize(), throwsStateError);
      platform.appendError = null;
      await kitten.play('Recovery', voice, phonemize: false);
      expect(platform.events.last, 'speak:kitten');
    },
  );
  test('stop interrupts an awaited play', () async {
    platform.playback = Completer<void>();
    final play = kitten.play('hello', voice, phonemize: false);
    final check = expectLater(play, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await kitten.stop();
    await check;
  });
}
