import 'package:phonemize/phonemize.dart' as p;
import 'package:espeak/espeak.dart' as e;

abstract class Phonemizer {
  factory Phonemizer() = InternalPhonemizer;
  Phonemizer._();
  String convert(String text, {String? language});
  String sanitize(String ipa) => ipa.trim();
  void dispose() {}
}

class InternalPhonemizer extends Phonemizer {
  InternalPhonemizer() : super._();
  bool _initialized = false;

  void _ensureInitialized() {
    if (!_initialized) {
      p.initDefaultProcessors();
      _initialized = true;
    }
  }

  @override
  String convert(String text, {String? language}) {
    _ensureInitialized();
    return p.phonemize(
      text,
      language: language ?? 'en-us',
      stripStress: false,
      format: 'ipa',
    );
  }
}

class EspeakPhonemizer extends Phonemizer {
  final e.Espeak _espeak;
  final String _defaultLanguage;

  EspeakPhonemizer._(this._espeak, this._defaultLanguage) : super._();

  /// Initialize espeak-ng with data from [dataPath].
  /// [dataPath] is the directory containing `espeak-ng-data/`.
  factory EspeakPhonemizer({
    required String dataPath,
    String language = 'en-us',
  }) {
    final instance = e.Espeak.init(dataPath, voice: language);
    return EspeakPhonemizer._(instance, language);
  }

  @override
  String convert(String text, {String? language}) {
    if (language != null && language != _defaultLanguage) {
      _espeak.setVoice(language);
    }
    return _espeak.phonemize(text);
  }

  @override
  void dispose() {
    _espeak.dispose();
  }
}
