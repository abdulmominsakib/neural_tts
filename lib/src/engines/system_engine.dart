import '../engine.dart';
import '../platform/tts_platform.dart';
import 'native_engine.dart';

class SystemEngine extends NativeEngine {
  @override
  EngineId get id => EngineId.system;
  @override
  Future<Map<String, dynamic>> initializationArguments() async => {
    'engine': 'system',
  };
  @override
  Future<List<Voice>> getVoices() => TtsPlatform.instance.getAvailableVoices();
  @override
  Future<bool> isInstalled() async => true;
}
