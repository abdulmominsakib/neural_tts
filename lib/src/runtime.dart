import 'dart:async';
import 'engine.dart';

class TTSRuntime {
  static final TTSRuntime _instance = TTSRuntime._();
  static TTSRuntime get instance => _instance;
  TTSRuntime._();

  Engine? _currentEngine;
  final List<_QueuedAction> _queue = [];
  _QueuedAction? _active;
  bool _stopped = false;
  int _generation = 0;
  Future<void> _cleanup = Future.value();

  Engine? get currentEngine => _currentEngine;

  Future<T> acquire<T>(Engine engine, Future<T> Function() fn) {
    if (_stopped) return Future.error(StateError('TTSRuntime stopped'));
    final result = Completer<T>();
    final generation = _generation;
    final action = _QueuedAction(
      cancel: () {
        if (!result.isCompleted) {
          result.completeError(StateError('TTSRuntime stopped'));
        }
      },
      run: () async {
        try {
          await _cleanup;
          if (generation != _generation) return;
          if (!identical(_currentEngine, engine)) {
            await _releaseCurrent();
            if (generation != _generation) return;
            _currentEngine = engine;
            await engine.load();
          }
          if (generation != _generation) return;
          final value = await fn();
          if (!result.isCompleted) result.complete(value);
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
          await _releaseCurrent();
        }
      },
    );
    _queue.add(action);
    _drain();
    return result.future;
  }

  Future<void> stop() => _interrupt(releaseEngine: false);
  Future<void> release() => _interrupt(releaseEngine: true);

  Future<void> _interrupt({required bool releaseEngine}) {
    _stopped = true;
    _generation++;
    _active?.cancel();
    for (final action in _queue) {
      action.cancel();
    }
    _queue.clear();
    final engine = _currentEngine;
    final activeDone = _active?.done.future;
    final priorCleanup = _cleanup;
    final cleanup = () async {
      await priorCleanup;
      try {
        await engine?.stop();
      } finally {
        // Loading/inference must finish before its resources are disposed.
        await activeDone;
        if (releaseEngine) await _releaseCurrent();
      }
    }();
    // Keep later work usable even if a backend reports a cleanup failure.
    _cleanup = cleanup.catchError((Object _) {});
    return cleanup;
  }

  Future<void> _releaseCurrent() async {
    final engine = _currentEngine;
    _currentEngine = null;
    if (engine == null) return;
    try {
      await engine.stop();
    } finally {
      await engine.release();
    }
  }

  void _drain() {
    if (_active != null || _queue.isEmpty) return;
    final action = _queue.removeAt(0);
    _active = action;
    () async {
      try {
        await action.run();
      } catch (_) {
        // The caller already received the primary operation error.
      } finally {
        _active = null;
        action.done.complete();
        _drain();
      }
    }();
  }

  void resetStop() => _stopped = false;
}

class _QueuedAction {
  final Future<void> Function() run;
  final void Function() cancel;
  final done = Completer<void>();
  _QueuedAction({required this.run, required this.cancel});
}
