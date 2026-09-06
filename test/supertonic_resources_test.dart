import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_onnxruntime/src/flutter_onnxruntime_platform_interface.dart';
import 'package:neural_tts/src/engines/supertonic_inference.dart';

class FakeOnnx extends FlutterOnnxruntimePlatform {
  int sessions = 0;
  int values = 0;
  int? failSession;
  int? failValue;
  bool cancelAfterRun = false;
  final closed = <String>[];
  final live = <String>{};
  @override
  Future<Map<String, dynamic>> createSession(
    String modelPath, {
    Map<String, dynamic>? sessionOptions,
  }) async {
    sessions++;
    if (sessions == failSession) throw StateError('session failed');
    return {
      'sessionId': '$sessions',
      'inputNames': ['text_ids', 'style_ttl'],
      'outputNames': ['output'],
    };
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closed.add(sessionId);
  }

  @override
  Future<Map<String, dynamic>> createOrtValue(
    String sourceType,
    dynamic data,
    List<int> shape,
  ) async {
    values++;
    if (values == failValue) throw StateError('allocation failed');
    final id = 'value$values';
    live.add(id);
    return {'valueId': id, 'dataType': sourceType, 'shape': shape};
  }

  @override
  Future<void> releaseOrtValue(String valueId) async {
    expect(
      live.remove(valueId),
      isTrue,
      reason: 'each tensor must be released exactly once',
    );
  }

  @override
  Future<Map<String, dynamic>> runInference(
    String sessionId,
    Map<String, OrtValue> inputs, {
    Map<String, dynamic>? runOptions,
  }) async {
    if (!cancelAfterRun) throw StateError('inference failed');
    live.add('output');
    return {
      'output': [
        'output',
        'float32',
        [1],
      ],
    };
  }
}

void main() {
  late FlutterOnnxruntimePlatform original;
  late FakeOnnx platform;
  late Directory root;
  late SupertonicInference inference;
  setUp(() async {
    original = FlutterOnnxruntimePlatform.instance;
    platform = FakeOnnx();
    FlutterOnnxruntimePlatform.instance = platform;
    root = await Directory.systemTemp.createTemp('tts-style-');
    await File('${root.path}/F1.json').writeAsString('''{
      "style_ttl": {"dims": [1], "data": [0.1]},
      "style_dp": {"dims": [1], "data": [0.1]}
    }''');
    inference = SupertonicInference(
      durationPredictorPath: 'duration',
      textEncoderPath: 'encoder',
      vectorEstimatorPath: 'vector',
      vocoderPath: 'vocoder',
      voicesDir: root.path,
    );
  });
  tearDown(() async {
    await inference.close();
    FlutterOnnxruntimePlatform.instance = original;
    await root.delete(recursive: true);
  });
  test(
    'partial initialization closes all successfully created sessions',
    () async {
      platform.failSession = 3;
      await expectLater(inference.initialize(), throwsStateError);
      expect(platform.closed, ['1', '2']);
      await inference.close();
      expect(platform.closed, ['1', '2']);
    },
  );
  test('tensor allocation failure releases earlier allocations', () async {
    platform.failValue = 2;
    await expectLater(
      inference.synthesize('Hello', 'F1', 'en', 1),
      throwsStateError,
    );
    expect(platform.live, isEmpty);
  });
  test('inference failure releases all input tensors', () async {
    await expectLater(
      inference.synthesize('Hello', 'F1', 'en', 1),
      throwsStateError,
    );
    expect(platform.live, isEmpty);
    expect(platform.values, greaterThan(0));
  });
  test('cancellation after inference releases outputs too', () async {
    platform.cancelAfterRun = true;
    await expectLater(
      inference.synthesize(
        'Hello',
        'F1',
        'en',
        1,
        isCancelled: () => platform.live.contains('output'),
      ),
      throwsStateError,
    );
    expect(platform.live, isEmpty);
  });
}
