import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../engine.dart';
import '../constants.dart';
import '../streaming_handle.dart';
import '../download/downloader.dart';
import '../download/models.dart';
import '../phonemizer.dart';
import '../wav_utils.dart';
import 'supertonic_inference.dart';

class SupertonicEngine extends Engine {
  final ModelDownloader _downloader = ModelDownloader();
  SupertonicInference? _inference;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _loaded = false;

  @override
  void setPhonemizer(Phonemizer phonemizer) {
    // Supertonic doesn't currently use a Dart-side phonemizer.
  }

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
    
    _inference = SupertonicInference(
      durationPredictorPath: '${engineDir.path}/duration_predictor.onnx',
      textEncoderPath: '${engineDir.path}/text_encoder.onnx',
      vectorEstimatorPath: '${engineDir.path}/vector_estimator.onnx',
      vocoderPath: '${engineDir.path}/vocoder.onnx',
      unicodeIndexerPath: '${engineDir.path}/unicode_indexer.json',
      voicesDir: '${engineDir.path}/voices',
    );
    
    await _inference!.initialize();
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
    
    final pcmBytes = await _inference!.synthesize(
      text, 
      voice.id, 
      language ?? 'en', 
      inferenceSteps ?? supertonicStepsDefault
    );
    
    final wavBytes = WavUtils.addWavHeader(pcmBytes, 24000, 1, 16);
    
    await _audioPlayer.stop();
    await _audioPlayer.setPlaybackRate(rate);
    await _audioPlayer.setVolume(volume);
    await _audioPlayer.play(BytesSource(wavBytes));
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
    // Supertonic's current implementation doesn't support true streaming due to the denoising loop.
    // We return a handle that just buffers text and plays it when finalized, or we could chunk it.
    return _SupertonicStreamingHandle(
      engine: this,
      voice: voice,
      language: language,
      inferenceSteps: inferenceSteps,
      rate: rate,
      pitch: pitch,
      volume: volume,
    );
  }

  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  @override
  Future<void> release() async {
    if (_loaded) {
      _inference?.close();
      _inference = null;
      _loaded = false;
    }
  }
}

class _SupertonicStreamingHandle implements StreamingHandle {
  final SupertonicEngine engine;
  final Voice voice;
  final String? language;
  final int? inferenceSteps;
  final double rate;
  final double pitch;
  final double volume;
  
  final StringBuffer _buffer = StringBuffer();
  bool _active = false;

  _SupertonicStreamingHandle({
    required this.engine,
    required this.voice,
    this.language,
    this.inferenceSteps,
    required this.rate,
    required this.pitch,
    required this.volume,
  });

  @override
  void appendText(String chunk) {
    _active = true;
    _buffer.write(chunk);
  }

  @override
  Future<void> finalize() async {
    _active = false;
    if (_buffer.isNotEmpty) {
      await engine.play(
        _buffer.toString(),
        voice,
        language: language,
        inferenceSteps: inferenceSteps,
        rate: rate,
        pitch: pitch,
        volume: volume,
      );
      _buffer.clear();
    }
  }

  @override
  Future<void> cancel() async {
    _active = false;
    _buffer.clear();
    await engine.stop();
  }

  @override
  bool get isActive => _active;

  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();
}
