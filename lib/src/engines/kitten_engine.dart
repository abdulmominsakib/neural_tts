import 'dart:async';
import '../engine.dart';
import '../constants.dart';
import '../streaming_handle.dart';
import '../platform/tts_platform.dart';
import '../download/models.dart';
import '../download/downloader.dart';

class KittenEngine extends Engine {
  final ModelDownloader _downloader = ModelDownloader();
  bool _loaded = false;

  @override
  EngineId get id => EngineId.kitten;

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
    return _loaded || await _downloader.isEngineDownloaded(EngineId.kitten);
  }

  @override
  Future<List<Voice>> getVoices() async => [...kittenVoices];

  @override
  Future<void> load() async {
    if (_loaded) return;
    final engineDir = await _downloader.getEngineDir(EngineId.kitten);
    final dictPath = '${(await _downloader.getTtsDir()).path}/en-us.bin';
    await TtsPlatform.instance.initialize({
      'engine': 'kitten',
      'modelPath': '${engineDir.path}/${KittenVariant.nanoInt8.modelFileName}',
      'voicesPath': '${engineDir.path}/voices.npz',
      'dictPath': dictPath,
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
      'engine': 'kitten',
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
    final streamId = 'kitten.${voice.id}.${DateTime.now().millisecondsSinceEpoch}';
    return _KittenStreamingHandle(
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

class _KittenStreamingHandle implements StreamingHandle {
  final String streamId;
  final String voiceId;
  final String language;
  final int inferenceSteps;
  final double rate;
  final double pitch;
  final double volume;
  bool _active = false;

  _KittenStreamingHandle({
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
      'engine': 'kitten',
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
    await TtsPlatform.instance.streamFinalize({
      'streamId': streamId,
    });
  }

  @override
  Future<void> cancel() async {
    _active = false;
    await TtsPlatform.instance.streamCancel({
      'streamId': streamId,
    });
  }

  @override
  bool get isActive => _active;

  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();
}
