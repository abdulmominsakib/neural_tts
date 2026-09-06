import 'dart:async';

abstract class StreamingHandle {
  /// Appends text; throws after closure. Async append errors reach [finalize].
  void appendText(String chunk);

  /// Closes input and waits for audio completion. Repeated calls share the result.
  Future<void> finalize();

  /// Closes input and interrupts playback. Safe to call repeatedly.
  Future<void> cancel();

  bool get isActive;

  Stream<double> get audioLevelStream;
}
