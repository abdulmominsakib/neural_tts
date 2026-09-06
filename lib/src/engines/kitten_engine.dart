import '../engine.dart';
import '../constants.dart';
import '../download/models.dart';
import 'native_engine.dart';

class KittenEngine extends NativeEngine {
  @override
  EngineId get id => EngineId.kitten;
  @override
  Future<List<Voice>> getVoices() async => [...kittenVoices];
  @override
  Future<Map<String, dynamic>> initializationArguments() async {
    final engineDir = await downloader.getEngineDir(EngineId.kitten);
    final dictPath = '${(await downloader.getTtsDir()).path}/en-us.bin';
    return {
      'engine': 'kitten',
      'modelPath': '${engineDir.path}/${KittenVariant.nanoInt8.modelFileName}',
      'voicesPath': '${engineDir.path}/voices.npz',
      'dictPath': dictPath,
      'executionProviders': 'cpu',
      'maxChunkSize': maxChunkSize,
      'silentMode': 'obey',
      'ducking': true,
    };
  }
}
