import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../engine.dart';

import 'tts_method_channel.dart';

abstract class TtsPlatform extends PlatformInterface {
  TtsPlatform() : super(token: _token);

  static final Object _token = Object();

  static TtsPlatform _instance = _defaultInstance();
  static TtsPlatform get instance => _instance;

  static set instance(TtsPlatform value) {
    PlatformInterface.verify(value, _token);
    _instance = value;
  }

  static TtsPlatform _defaultInstance() {
    return TtsMethodChannel();
  }

  Future<void> initialize(Map<String, dynamic> args);

  Future<void> speak(Map<String, dynamic> args);

  Future<void> streamAppend(Map<String, dynamic> args);

  Future<void> streamFinalize(Map<String, dynamic> args);

  Future<void> streamCancel(Map<String, dynamic> args);

  Future<void> stop();

  Future<void> release();

  Future<List<Voice>> getAvailableVoices();
}

class TtsToken {
  const TtsToken();
}
