import 'package:flutter/services.dart';

import '../engine.dart';
import 'tts_platform.dart';

class TtsMethodChannel extends TtsPlatform {
  final MethodChannel _channel;

  TtsMethodChannel() : _channel = const MethodChannel('com.localmind.neural_tts');

  @override
  Future<void> initialize(Map<String, dynamic> args) async {
    await _channel.invokeMethod('tts.initialize', args);
  }

  @override
  Future<void> speak(Map<String, dynamic> args) async {
    await _channel.invokeMethod('tts.speak', args);
  }

  @override
  Future<void> streamAppend(Map<String, dynamic> args) async {
    await _channel.invokeMethod('tts.stream.append', args);
  }

  @override
  Future<void> streamFinalize(Map<String, dynamic> args) async {
    await _channel.invokeMethod('tts.stream.finalize', args);
  }

  @override
  Future<void> streamCancel(Map<String, dynamic> args) async {
    await _channel.invokeMethod('tts.stream.cancel', args);
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod('tts.stop');
  }

  @override
  Future<void> release() async {
    await _channel.invokeMethod('tts.release');
  }

  @override
  Future<List<Voice>> getAvailableVoices() async {
    final result = await _channel.invokeMethod('tts.getAvailableVoices');
    if (result is! List) return [];
    return result.map((v) {
      final map = v as Map<dynamic, dynamic>;
      return Voice(
        id: map['id'] as String,
        name: map['name'] as String,
        engine: EngineId.system,
      );
    }).toList();
  }
}
