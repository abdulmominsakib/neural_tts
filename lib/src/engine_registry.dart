import 'engine.dart';
import 'engines/system_engine.dart';
import 'engines/kitten_engine.dart';
import 'engines/kokoro_engine.dart';
import 'engines/supertonic_engine.dart';

final Map<EngineId, Engine Function()> engineFactories = {
  EngineId.system: () => SystemEngine(),
  EngineId.kitten: () => KittenEngine(),
  EngineId.kokoro: () => KokoroEngine(),
  EngineId.supertonic: () => SupertonicEngine(),
};

Engine createEngine(EngineId id) {
  final factory = engineFactories[id];
  if (factory == null) {
    throw ArgumentError('Unknown engine: $id');
  }
  return factory();
}
