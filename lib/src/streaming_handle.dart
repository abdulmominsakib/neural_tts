import 'dart:async';

abstract class StreamingHandle {
  void appendText(String chunk);

  Future<void> finalize();

  Future<void> cancel();

  bool get isActive;

  Stream<double> get audioLevelStream;
}
