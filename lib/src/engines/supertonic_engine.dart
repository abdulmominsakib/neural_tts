import 'dart:async';
import '../engine.dart';
import '../constants.dart';
import '../streaming_handle.dart';
import '../platform/tts_platform.dart';
import '../download/models.dart';
import '../download/downloader.dart';

class SupertonicEngine extends Engine {
  final ModelDownloader _downloader = ModelDownloader();
  bool _loaded = false;

  @override
  EngineId get id => EngineId.supertonic;

  @override
  Future<EngineStatus> checkStatus() async {
    try {
      final installed = await isInstalled();
      return EngineStatus(
        state: installed ? EngineState.installed : EngineState.notInstalled,
      );
    } catch (e) {
      return EngineStatus(state: EngineState.error, error: e.toString());
    }
  }

  @override
  Future<bool> isInstalled() async {
    return _loaded || await _downloader.isEngineDownloaded(EngineId.supertonic);
  }

  @override
  Future<List<Voice>> getVoices() async => [...supertonicVoices];

  @override
  Future<void> load() async {
    if (_loaded) return;
    final engineDir = await _downloader.getEngineDir(EngineId.supertonic);
    await TtsPlatform.instance.initialize({
      'engine': 'supertonic',
      'durationPredictorPath': '${engineDir.path}/duration_predictor.onnx',
      'textEncoderPath': '${engineDir.path}/text_encoder.onnx',
      'vectorEstimatorPath': '${engineDir.path}/vector_estimator.onnx',
      'vocoderPath': '${engineDir.path}/vocoder.onnx',
      'unicodeIndexerPath': '${engineDir.path}/unicode_indexer.json',
      'voicesDir': '${engineDir.path}/voices',
      'executionProviders': 'cpu',
      'maxChunkSize': maxChunkSize,
      'silentMode': 'obey',
      'ducking': true,
    });
    _loaded = true;
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
  }) async {
    if (!_loaded) await load();
    await TtsPlatform.instance.speak({
      'engine': 'supertonic',
      'text': text,
      'voiceId': voice.id,
      'language': language ?? 'en',
      'inferenceSteps': inferenceSteps ?? supertonicStepsDefault,
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
  }) {
    final streamId = 'supertonic.${voice.id}.${DateTime.now().millisecondsSinceEpoch}';
    return _SupertonicStreamingHandle(
      streamId: streamId,
      voiceId: voice.id,
      language: language ?? 'en',
      inferenceSteps: inferenceSteps ?? supertonicStepsDefault,
      rate: rate,
      pitch: pitch,
      volume: volume,
    );
  }

  @override
  Future<void> stop() async {
    await TtsPlatform.instance.stop();
  }

  @override
  Future<void> release() async {
    if (_loaded) {
      await TtsPlatform.instance.release();
      _loaded = false;
    }
  }
}

class _SupertonicStreamingHandle implements StreamingHandle {
  final String streamId;
  final String voiceId;
  final String language;
  final int inferenceSteps;
  final double rate;
  final double pitch;
  final double volume;
  bool _active = false;

  _SupertonicStreamingHandle({
    required this.streamId,
    required this.voiceId,
    required this.language,
    required this.inferenceSteps,
    required this.rate,
    required this.pitch,
    required this.volume,
  });

  @override
  void appendText(String chunk) {
    _active = true;
    TtsPlatform.instance.streamAppend({
      'engine': 'supertonic',
      'streamId': streamId,
      'text': chunk,
      'voiceId': voiceId,
      'language': language,
      'inferenceSteps': inferenceSteps,
      'rate': rate,
      'pitch': pitch,
      'volume': volume,
    });
  }

  @override
  Future<void> finalize() async {
    _active = false;
    await TtsPlatform.instance.streamFinalize({'streamId': streamId});
  }

  @override
  Future<void> cancel() async {
    _active = false;
    await TtsPlatform.instance.streamCancel({'streamId': streamId});
  }

  @override
  bool get isActive => _active;

  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();
}
