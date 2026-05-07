import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Tokenizer that maps IPA phoneme characters to integer token IDs.
class SupertonicTokenizer {
  final Map<String, int> _vocab = {};
  bool _initialized = false;

  static const int pad = 0;
  static const int eos = 10;

  Future<void> initialize({String? vocabPath}) async {
    if (_initialized) return;
    if (vocabPath != null && await File(vocabPath).exists()) {
      try {
        final json = jsonDecode(await File(vocabPath).readAsString());
        if (json is Map) {
          json.forEach((key, value) {
            _vocab[key.toString()] = value as int;
          });
          _initialized = true;
          return;
        }
      } catch (e) {
        // Fallback to hardcoded
      }
    }
    _buildVocab();
    _initialized = true;
  }

  Int64List encode(String text) {
    if (!_initialized) _buildVocab();
    final result = <int>[];
    result.add(pad); // start token
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final id = _vocab[char];
      if (id != null) {
        result.add(id);
      }
    }
    result.add(eos); // end token
    result.add(pad); // trailing pad
    return Int64List.fromList(result);
  }

  void _buildVocab() {
    const padChar = "\$";
    const punctuation = ";:,.!?¡¿—…\"«»\"\" ";
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    const lettersIpa =
        "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘\u0301\u0329ᵻ";

    const symbols = padChar + punctuation + letters + lettersIpa;
    for (var i = 0; i < symbols.length; i++) {
      _vocab[symbols[i]] = i;
    }
    _initialized = true;
  }
}
