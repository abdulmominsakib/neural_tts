import 'dart:async';
import 'engine.dart';

class TTSRuntime {
  static final TTSRuntime _instance = TTSRuntime._();
  static TTSRuntime get instance => _instance;
  TTSRuntime._();

  Engine? _currentEngine;
  Completer<void>? _pending;
  final List<_QueuedAction> _queue = [];
  bool _stopped = false;

  Engine? get currentEngine => _currentEngine;

  Future<T> acquire<T>(Engine engine, Future<T> Function() fn) {
    final completer = Completer<T>();
    _queue.add(_QueuedAction(
      engine: engine,
      run: () async {
        if (_stopped) {
          completer.completeError(StateError('TTSRuntime stopped'));
          return;
        }
        await _releaseCurrent();
        await engine.load();
        _currentEngine = engine;
        try {
          final result = await fn();
          if (!completer.isCompleted) completer.complete(result);
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
    ));
    _drain();
    return completer.future;
  }

  Future<void> stop() async {
    _stopped = true;
    _queue.clear();
    await _currentEngine?.stop();
  }

  Future<void> release() async {
    _stopped = true;
    _queue.clear();
    await _releaseCurrent();
  }

  Future<void> _releaseCurrent() async {
    if (_currentEngine != null) {
      try {
        await _currentEngine!.stop();
        await _currentEngine!.release();
      } catch (_) {}
      _currentEngine = null;
    }
  }

  void _drain() {
    if (_pending != null) return;
    if (_queue.isEmpty) return;

    final action = _queue.removeAt(0);
    _pending = Completer<void>();
    action.run().then((_) {
      _pending = null;
      _currentEngine = action.engine;
      _drain();
    }).catchError((_) {
      _pending = null;
      _drain();
    });
  }

  void resetStop() {
    _stopped = false;
  }
}

class _QueuedAction {
  final Engine engine;
  final Future<void> Function() run;

  _QueuedAction({required this.engine, required this.run});
}
