import '../download/models.dart';
import '../engine.dart';
import '../constants.dart';
import 'native_engine.dart';

class KokoroEngine extends NativeEngine {
  @override
  EngineId get id => EngineId.kokoro;
  @override
  Future<List<Voice>> getVoices() async => [...kokoroVoices];
  @override
  Future<Map<String, dynamic>> initializationArguments() async {
    final engineDir = await downloader.getEngineDir(EngineId.kokoro);
    final dictPath = '${(await downloader.getTtsDir()).path}/en-us.bin';
    return {
      'engine': 'kokoro',
      'modelPath': '${engineDir.path}/model.onnx',
      'tokenizerPath': '${engineDir.path}/tokenizer.json',
      'voicesDir': '${engineDir.path}/voices',
      'dictPath': dictPath,
      'executionProviders': 'cpu',
      'maxChunkSize': maxChunkSize,
      'silentMode': 'obey',
      'ducking': true,
    };
  }
}
