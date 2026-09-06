import 'dart:async';
import '../engine.dart';
import '../download/downloader.dart';
import '../phonemizer.dart';
import '../platform/tts_platform.dart';
import '../streaming_handle.dart';

/// Serializes access to the single native engine without blocking cancellation.
abstract class NativeEngine extends Engine {
  static Future<void> _tail = Future.value();
  static NativeEngine? _owner;
  static NativeStreamingHandle? _stream;
  static int _nextStream = 0;
  int _generation = 0;
  Phonemizer phonemizer = Phonemizer();
  final downloader = ModelDownloader();

  Future<Map<String, dynamic>> initializationArguments();

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _select() async {
    if (identical(_owner, this)) return;
    if (_owner != null) {
      _owner = null;
      await TtsPlatform.instance.release();
    }
    final args = await initializationArguments();
    _owner = this;
    try {
      await TtsPlatform.instance.initialize(args);
    } catch (_) {
      _owner = null;
      rethrow;
    }
  }

  Future<void> perform(
    Future<void> Function() action, {
    NativeStreamingHandle? stream,
  }) {
    final generation = _generation;
    return _serialize(() async {
      if (generation != _generation) throw StateError('Playback cancelled');
      if (_stream != null && !identical(_stream, stream)) {
        throw StateError('A native stream is already active');
      }
      await _select();
      if (generation != _generation) throw StateError('Playback cancelled');
      await action();
      if (generation != _generation) throw StateError('Playback cancelled');
    });
  }

  @override
  Future<void> load() => perform(() async {});

  @override
  void setPhonemizer(Phonemizer phonemizer) => this.phonemizer = phonemizer;

  @override
  Future<bool> isInstalled() => downloader.isEngineDownloaded(id);

  @override
  Future<EngineStatus> checkStatus() async {
    try {
      return EngineStatus(
        state: await isInstalled()
            ? EngineState.installed
            : EngineState.notInstalled,
      );
    } catch (error) {
      return EngineStatus(state: EngineState.error, error: error.toString());
    }
  }

  Map<String, dynamic> _options(
    Voice voice,
    String? language,
    int? steps,
    double rate,
    double pitch,
    double volume,
    bool phonemize,
  ) => {
    'engine': id.name,
    'voiceId': voice.id,
    'language': language ?? 'en',
    if (steps != null) 'inferenceSteps': steps,
    'rate': rate,
    'pitch': pitch,
    'volume': volume,
    'isPhonemized': phonemize && id != EngineId.system,
  };

  String _text(String text, Map<String, dynamic> options) =>
      options['isPhonemized'] == true
      ? phonemizer.convert(text, language: options['language'] as String)
      : text;

  @override
  Future<void> play(
    String text,
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1,
    double pitch = 1,
    double volume = 1,
    bool phonemize = true,
  }) {
    final options = _options(
      voice,
      language,
      inferenceSteps,
      rate,
      pitch,
      volume,
      phonemize,
    );
    return perform(
      () => TtsPlatform.instance.speak({
        ...options,
        'text': _text(text, options),
      }),
    );
  }

  @override
  StreamingHandle playStreaming(
    Voice voice, {
    String? language,
    int? inferenceSteps,
    double rate = 1,
    double pitch = 1,
    double volume = 1,
    bool phonemize = true,
  }) {
    if (id == EngineId.system) {
      throw UnsupportedError('System engine does not support streaming');
    }
    if (_stream != null) throw StateError('A native stream is already active');
    final handle = NativeStreamingHandle(this, {
      ..._options(
        voice,
        language,
        inferenceSteps,
        rate,
        pitch,
        volume,
        phonemize,
      ),
      'streamId': '${id.name}.${++_nextStream}',
    });
    _stream = handle;
    return handle;
  }

  @override
  Future<void> stop() async {
    _generation++;
    if (identical(_stream?.engine, this)) _stream?._invalidate();
    if (identical(_owner, this)) await TtsPlatform.instance.stop();
  }

  @override
  Future<void> release() async {
    await stop();
    await _serialize(() async {
      if (identical(_owner, this)) {
        _owner = null;
        await TtsPlatform.instance.release();
      }
    });
  }
}

class NativeStreamingHandle implements StreamingHandle {
  final NativeEngine engine;
  final Map<String, dynamic> options;
  Future<void> _tail = Future.value();
  Future<void>? _finalized;
  Future<void>? _cancelled;
  Object? _error;
  StackTrace? _stack;
  bool _closed = false;
  bool _wasCancelled = false;
  String _buffer = '';
  NativeStreamingHandle(this.engine, this.options);

  void _enqueue(Future<void> Function() action) {
    _tail = _tail
        .then((_) async {
          if (_wasCancelled || _error != null) return;
          await action();
        })
        .catchError((Object error, StackTrace stack) {
          _error ??= error;
          _stack ??= stack;
        });
  }

  @override
  void appendText(String chunk) {
    if (_closed) throw StateError('Stream is closed');
    // Buffer whole sentences before phonemization so split words stay intact.
    _buffer += chunk;
    final boundaries = RegExp(r'[.!?]\s+').allMatches(_buffer).toList();
    if (boundaries.isEmpty) return;
    final end = boundaries.last.end;
    final text = _buffer.substring(0, end);
    _buffer = _buffer.substring(end);
    _append(text);
  }

  void _append(String text) => _enqueue(
    () => engine.perform(
      () => TtsPlatform.instance.streamAppend({
        ...options,
        'text': engine._text(text, options),
      }),
      stream: this,
    ),
  );

  @override
  Future<void> finalize() => _finalized ??= _finish();

  Future<void> _finish() async {
    _closed = true;
    if (_buffer.isNotEmpty && !_wasCancelled) _append(_buffer);
    _buffer = '';
    try {
      await _tail;
      if (_wasCancelled) throw StateError('Stream cancelled');
      if (_error != null) Error.throwWithStackTrace(_error!, _stack!);
      await engine.perform(
        () => TtsPlatform.instance.streamFinalize(options),
        stream: this,
      );
    } catch (_) {
      if (!_wasCancelled) await engine.stop();
      rethrow;
    } finally {
      if (identical(NativeEngine._stream, this)) NativeEngine._stream = null;
    }
  }

  void _invalidate() {
    _closed = true;
    _wasCancelled = true;
    _buffer = '';
    if (identical(NativeEngine._stream, this)) NativeEngine._stream = null;
  }

  @override
  Future<void> cancel() => _cancelled ??= _cancel();
  Future<void> _cancel() async {
    if (_wasCancelled) return;
    if (_closed && !_wasCancelled) {
      // A finalize may still be playing; it remains cancellable.
      if (!identical(NativeEngine._stream, this)) return;
    }
    _invalidate();
    await engine.stop();
    await _tail;
  }

  @override
  bool get isActive => !_closed;
  @override
  Stream<double> get audioLevelStream => const Stream.empty();
}
