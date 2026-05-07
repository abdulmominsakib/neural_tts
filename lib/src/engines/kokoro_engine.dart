import 'dart:async';
import '../engine.dart';
import '../constants.dart';
import '../streaming_handle.dart';
import '../platform/tts_platform.dart';
import '../download/models.dart';
import '../download/downloader.dart';
import '../phonemizer.dart';

class KokoroEngine extends Engine {
  final ModelDownloader _downloader = ModelDownloader();
  Phonemizer _phonemizer = Phonemizer();
  bool _loaded = false;

  @override
  void setPhonemizer(Phonemizer phonemizer) {
    _phonemizer = phonemizer;
  }

  @override
  EngineId get id => EngineId.kokoro;

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
    return _loaded || await _downloader.isEngineDownloaded(EngineId.kokoro);
  }

  @override
  Future<List<Voice>> getVoices() async => [...kokoroVoices];

  @override
  Future<void> load() async {
    if (_loaded) return;
    final engineDir = await _downloader.getEngineDir(EngineId.kokoro);
    final dictPath = '${(await _downloader.getTtsDir()).path}/en-us.bin';
    await TtsPlatform.instance.initialize({
      'engine': 'kokoro',
      'modelPath': '${engineDir.path}/model.onnx',
      'tokenizerPath': '${engineDir.path}/tokenizer.json',
      'voicesDir': '${engineDir.path}/voices',
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
    bool phonemize = true,
  }) async {
    if (!_loaded) await load();
    final phonemes = phonemize ? _phonemizer.convert(text, language: language) : text;
    await TtsPlatform.instance.speak({
      'engine': 'kokoro',
      'text': phonemes,
      'isPhonemized': phonemize,
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
    final streamId = 'kokoro.${voice.id}.${DateTime.now().millisecondsSinceEpoch}';
    return _KokoroStreamingHandle(
      streamId: streamId,
      voiceId: voice.id,
      language: language ?? 'en',
      rate: rate,
      pitch: pitch,
      volume: volume,
      phonemizer: _phonemizer,
      phonemize: phonemize,
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

class _KokoroStreamingHandle implements StreamingHandle {
  final String streamId;
  final String voiceId;
  final String language;
  final double rate;
  final double pitch;
  final double volume;
  final Phonemizer phonemizer;
  final bool phonemize;
  bool _active = false;

  _KokoroStreamingHandle({
    required this.streamId,
    required this.voiceId,
    required this.language,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.phonemizer,
    required this.phonemize,
  });

  @override
  void appendText(String chunk) {
    _active = true;
    final phonemes = phonemize ? phonemizer.convert(chunk, language: language) : chunk;
    TtsPlatform.instance.streamAppend({
      'engine': 'kokoro',
      'streamId': streamId,
      'text': phonemes,
      'isPhonemized': phonemize,
      'voiceId': voiceId,
      'language': language,
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
