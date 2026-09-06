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
  AudioPlayer? _player;
  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();
  Future<void> _tail = Future.value();
  int _generation = 0;
  Completer<void>? _playback;
  _SupertonicStreamingHandle? _stream;

  Future<void> _serialize(Future<void> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.catchError((Object _) {});
    return future;
  }

  void _check(int generation) {
    if (generation != _generation) throw StateError('Playback cancelled');
  }

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
  Future<void> load() {
    final generation = _generation;
    return _serialize(() async {
      _check(generation);
      await _load();
      _check(generation);
    });
  }

  Future<void> _load() async {
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
    if (_stream?._active ?? false)
      throw StateError('A stream is already active');
    final generation = _generation;
    await _serialize(() async {
      _check(generation);
      await _load();
      _check(generation);
      if (text.trim().isEmpty) return;
      final pcmBytes = await _inference!.synthesize(
        text,
        voice.id,
        language ?? 'en',
        inferenceSteps ?? supertonicStepsDefault,
        isCancelled: () => generation != _generation,
      );
      _check(generation);
      final wavBytes = WavUtils.addWavHeader(pcmBytes, 24000, 1, 16);
      final player = _audioPlayer;
      await player.setPlaybackRate(rate);
      _check(generation);
      await player.setVolume(volume);
      _check(generation);
      final done = Completer<void>();
      // Attach a handler immediately; cancellation can arrive during play().
      unawaited(done.future.catchError((Object _) {}));
      _playback = done;
      final subscription = player.onPlayerComplete.listen(
        (_) {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
      );
      try {
        await player.play(BytesSource(wavBytes));
        if (generation != _generation) await player.stop();
        _check(generation);
        await done.future;
        _check(generation);
      } finally {
        _playback = null;
        await subscription.cancel();
      }
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
    // Supertonic's current implementation doesn't support true streaming due to the denoising loop.
    // We return a handle that just buffers text and plays it when finalized, or we could chunk it.
    if (_stream != null) throw StateError('A stream is already active');
    return _stream = _SupertonicStreamingHandle(
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
    _generation++;
    _stream?._invalidate();
    _stream = null;
    final playback = _playback;
    if (playback != null && !playback.isCompleted) {
      playback.completeError(StateError('Playback cancelled'));
    }
    await _player?.stop();
  }

  @override
  Future<void> release() async {
    await stop();
    await _serialize(() async {
      await _inference?.close();
      _inference = null;
      _loaded = false;
      await _player?.dispose();
      _player = null;
    });
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
  bool _active = true;
  bool _cancelled = false;
  Future<void>? _finalized;
  Future<void>? _cancellation;

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
    if (!_active) throw StateError('Stream is closed');
    _buffer.write(chunk);
  }

  @override
  Future<void> finalize() => _finalized ??= _finish();

  Future<void> _finish() async {
    _active = false;
    if (_cancelled) throw StateError("Stream cancelled");
    try {
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
    } finally {
      if (identical(engine._stream, this)) engine._stream = null;
    }
  }

  @override
  Future<void> cancel() => _cancellation ??= _cancel();
  void _invalidate() {
    _cancelled = true;
    _active = false;
    _buffer.clear();
  }

  Future<void> _cancel() async {
    if (_cancelled || !identical(engine._stream, this)) return;
    _invalidate();
    await engine.stop();
  }

  @override
  bool get isActive => _active;

  @override
  Stream<double> get audioLevelStream => const Stream<double>.empty();
}
