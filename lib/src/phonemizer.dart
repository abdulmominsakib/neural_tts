class Phonemizer {
  static final Set<String> _validChars = () {
    final chars = <String>{
      ';', ':', ',', '.', '!', '?', '¡', '¿', '—', '…',
      '"', '«', '»', '\u201C', '\u201D', ' ',
    };
    for (int c = 65; c <= 90; c++) chars.add(String.fromCharCode(c));
    for (int c = 97; c <= 122; c++) chars.add(String.fromCharCode(c));
    chars.addAll({
      'ɑ', 'ɐ', 'ɒ', 'æ', 'ɓ', 'ʙ', 'β', 'ɔ', 'ɕ', 'ç',
      'ɗ', 'ɖ', 'ð', 'ʤ', 'ə', 'ɘ', 'ɚ', 'ɛ', 'ɜ', 'ɝ',
      'ɞ', 'ɟ', 'ʄ', 'ɡ', 'ɠ', 'ɢ', 'ʛ', 'ɦ', 'ɧ', 'ħ',
      'ɥ', 'ʜ', 'ɨ', 'ɪ', 'ʝ', 'ɭ', 'ɬ', 'ɫ', 'ɮ', 'ʟ',
      'ɱ', 'ɯ', 'ɰ', 'ŋ', 'ɳ', 'ɲ', 'ɴ', 'ø', 'ɵ', 'ɸ',
      'θ', 'œ', 'ɶ', 'ʘ', 'ɹ', 'ɺ', 'ɾ', 'ɻ', 'ʀ', 'ʁ',
      'ɽ', 'ʂ', 'ʃ', 'ʈ', 'ʧ', 'ʉ', 'ʊ', 'ʋ', 'ⱱ', 'ʌ',
      'ɣ', 'ɤ', 'ʍ', 'χ', 'ʎ', 'ʏ', 'ʑ', 'ʐ', 'ʒ', 'ʔ',
      'ʡ', 'ʕ', 'ʢ', 'ǀ', 'ǁ', 'ǂ', 'ǃ', 'ˈ', 'ˌ', 'ː',
      'ˑ', 'ʼ', 'ʴ', 'ʰ', 'ʱ', 'ʲ', 'ʷ', 'ˠ', 'ˤ', '˞',
      '↓', '↑', '→', '↗', '↘', 'ᵻ', '\u0329',
    });
    return chars;
  }();
  String convert(String text) {
    final cleaned = text
        .replaceAll(RegExp(r"[^\w\s'.,!?;:\-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final output = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (_isPreservablePunctuation(char)) {
        output.write(char);
      } else if (char == ' ') {
        output.write(' ');
      } else {
        final start = i;
        while (i < cleaned.length &&
            cleaned[i] != ' ' &&
            !_isPreservablePunctuation(cleaned[i])) {
          i++;
        }
        i--;
        final word = cleaned.substring(start, i + 1);
        if (word.isNotEmpty) output.write(_phonemizeWord(word));
      }
    }

    return sanitize(output.toString());
  }

  String sanitize(String ipa) => ipa
      .split('')
      .where((c) => _validChars.contains(c))
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isPreservablePunctuation(String char) =>
      ',.!?;:'.contains(char);

  String _phonemizeWord(String word) {
    if (_commonWords.containsKey(word)) return _commonWords[word]!;
    for (final entry in _suffixes) {
      if (word.length > entry.key.length + 1 && word.endsWith(entry.key)) {
        final stem = word.substring(0, word.length - entry.key.length);
        return _phonemizeCore(stem) + entry.value;
      }
    }
    return _phonemizeCore(word);
  }

  String _phonemizeCore(String word) {
    if (word.isEmpty) return '';
    final buffer = StringBuffer();
    int i = 0;

    if (word.length >= 2) {
      final pair = word.substring(0, 2);
      if (_silentInitialClusters.containsKey(pair)) {
        buffer.write(_silentInitialClusters[pair]);
        i = 2;
      }
    }

    while (i < word.length) {
      final char = word[i];
      final isLast = i == word.length - 1;
      final next = isLast ? null : word[i + 1];

      if (char == 'e' && isLast && word.length > 2) {
        i++;
        continue;
      }

      if (char == 'm' && next == 'b' && i == word.length - 2) {
        buffer.write('m');
        i += 2;
        continue;
      }

      if ('aeiou'.contains(char)) {
        if (i + 2 < word.length) {
          final tri = word.substring(i, i + 3);
          if (_vowelMultigraphs.containsKey(tri)) {
            buffer.write(_vowelMultigraphs[tri]);
            i += 3;
            continue;
          }
        }
        if (next != null) {
          final di = word.substring(i, i + 2);
          if (di == 'er' && i == word.length - 2) {
            buffer.write('ɚ');
            i += 2;
            continue;
          }
          if (_vowelMultigraphs.containsKey(di)) {
            buffer.write(_vowelMultigraphs[di]);
            i += 2;
            continue;
          }
        }
        if (_hasMagicE(word, i)) {
          buffer.write(_longVowels[char] ?? char);
          i++;
          continue;
        }
        buffer.write(_shortVowels[char] ?? char);
        i++;
        continue;
      }

      if (char == 'c' && next != null && 'eiy'.contains(next)) {
        buffer.write('s');
        i++;
        continue;
      }

      if (char == 'g' && next != null && 'eiy'.contains(next)) {
        buffer.write('dʒ');
        i++;
        continue;
      }

      if (char == 'y' && isLast) {
        buffer.write(word.length <= 3 ? 'aɪ' : 'iː');
        i++;
        continue;
      }

      if (i + 2 < word.length) {
        final tri = word.substring(i, i + 3);
        if (_consonantMultigraphs.containsKey(tri)) {
          buffer.write(_consonantMultigraphs[tri]!);
          i += 3;
          continue;
        }
      }

      if (next != null) {
        final di = word.substring(i, i + 2);
        if (_consonantMultigraphs.containsKey(di)) {
          buffer.write(_consonantMultigraphs[di]!);
          i += 2;
          continue;
        }
      }

      buffer.write(_singleConsonants[char] ?? '');
      i++;
    }

    return buffer.toString();
  }

  bool _hasMagicE(String word, int index) {
    if (word.isEmpty || word[word.length - 1] != 'e' || word.length < 3) {
      return false;
    }
    int j = index + 1;
    int consonantCount = 0;
    while (j < word.length - 1) {
      if ('aeiou'.contains(word[j])) return false;
      consonantCount++;
      j++;
    }
    return consonantCount >= 1;
  }

  static const Map<String, String> _silentInitialClusters = {
    'kn': 'n', 'wr': 'ɹ', 'gn': 'n', 'ps': 's', 'pn': 'n', 'mn': 'm',
  };

  static const Map<String, String> _consonantMultigraphs = {
    'tch': 'ʧ', 'dge': 'ʤ', 'ch': 'ʧ', 'sh': 'ʃ', 'zh': 'ʒ',
    'th': 'θ', 'gh': '', 'ph': 'f', 'wh': 'w', 'ng': 'ŋ',
    'nk': 'ŋk', 'qu': 'kw', 'ck': 'k',
  };

  static const Map<String, String> _singleConsonants = {
    'b': 'b', 'c': 'k', 'd': 'd', 'f': 'f', 'g': 'ɡ', 'h': 'h',
    'j': 'ʤ', 'k': 'k', 'l': 'l', 'm': 'm', 'n': 'n', 'p': 'p',
    'q': 'k', 'r': 'ɹ', 's': 's', 't': 't', 'v': 'v', 'w': 'w',
    'x': 'ks', 'y': 'j', 'z': 'z',
  };

  static const Map<String, String> _shortVowels = {
    'a': 'æ', 'e': 'ɛ', 'i': 'ɪ', 'o': 'ɑ', 'u': 'ʌ',
  };

  static const Map<String, String> _longVowels = {
    'a': 'eɪ', 'e': 'iː', 'i': 'aɪ', 'o': 'oʊ', 'u': 'juː',
  };

  static const Map<String, String> _vowelMultigraphs = {
    'igh': 'aɪ', 'ure': 'jʊɹ', 'ear': 'ɪɹ', 'air': 'ɛɹ',
    'oor': 'ʊɹ', 'ar': 'ɑːɹ', 'er': 'ɝ', 'ir': 'ɝ',
    'or': 'ɔːɹ', 'ur': 'ɝ', 'ay': 'eɪ', 'ai': 'eɪ',
    'ei': 'eɪ', 'ee': 'iː', 'ea': 'iː', 'ie': 'iː',
    'oa': 'oʊ', 'ow': 'oʊ', 'oo': 'uː', 'ue': 'uː',
    'ew': 'juː', 'eu': 'juː', 'ou': 'aʊ', 'oi': 'ɔɪ',
    'oy': 'ɔɪ', 'au': 'ɔː', 'aw': 'ɔː',
  };

  static const List<MapEntry<String, String>> _suffixes = [
    MapEntry('tion', 'ʃən'), MapEntry('sion', 'ʒən'),
    MapEntry('ture', 'ʧɚ'), MapEntry('ness', 'nɪs'),
    MapEntry('ment', 'mənt'), MapEntry('able', 'əbəl'),
    MapEntry('ible', 'ɪbəl'), MapEntry('ical', 'ɪkəl'),
    MapEntry('ious', 'iəs'), MapEntry('ance', 'əns'),
    MapEntry('ence', 'əns'), MapEntry('ism', 'ɪzəm'),
    MapEntry('ity', 'ɪti'), MapEntry('ise', 'aɪz'),
    MapEntry('ize', 'aɪz'), MapEntry('ive', 'ɪv'),
    MapEntry('ous', 'əs'), MapEntry('ful', 'fəl'),
    MapEntry('ing', 'ɪŋ'), MapEntry('est', 'ɪst'),
    MapEntry('ist', 'ɪst'), MapEntry('ant', 'ənt'),
    MapEntry('ent', 'ənt'), MapEntry('age', 'ɪʤ'),
    MapEntry('less', 'lɪs'), MapEntry('ify', 'ɪfaɪ'),
    MapEntry('fy', 'faɪ'), MapEntry('ly', 'liː'),
    MapEntry('er', 'ɚ'), MapEntry('ed', 'd'),
    MapEntry('s', 'z'),
  ];

  static const Map<String, String> _commonWords = {
    'the': 'ðə', 'a': 'ə', 'an': 'æn',
    'and': 'ænd', 'or': 'ɔːɹ', 'but': 'bʌt', 'if': 'ɪf',
    'of': 'ʌv', 'to': 'tuː', 'in': 'ɪn', 'on': 'ɑn',
    'at': 'æt', 'by': 'baɪ', 'as': 'æz',
    'for': 'fɔːɹ', 'with': 'wɪð', 'from': 'fɹʌm', 'into': 'ɪntuː',
    'up': 'ʌp', 'out': 'aʊt', 'over': 'oʊvɚ', 'than': 'ðæn',
    'then': 'ðɛn', 'so': 'soʊ', 'yet': 'jɛt',
    'i': 'aɪ', 'you': 'juː', 'he': 'hiː', 'she': 'ʃiː',
    'it': 'ɪt', 'we': 'wiː', 'they': 'ðeɪ',
    'me': 'miː', 'him': 'hɪm', 'her': 'hɜːɹ', 'us': 'ʌs',
    'them': 'ðɛm', 'my': 'maɪ', 'your': 'jɔːɹ', 'his': 'hɪz',
    'its': 'ɪts', 'our': 'aʊɚ', 'their': 'ðɛɹ',
    'this': 'ðɪs', 'that': 'ðæt', 'these': 'ðiːz', 'those': 'ðoʊz',
    'who': 'huː', 'which': 'wɪtʃ', 'what': 'wʌt', 'where': 'wɛɹ',
    'when': 'wɛn', 'how': 'haʊ', 'why': 'waɪ',
    'is': 'ɪz', 'are': 'ɑːɹ', 'was': 'wɑz', 'were': 'wɜːɹ',
    'be': 'biː', 'been': 'biːn', 'being': 'biːɪŋ',
    'have': 'hæv', 'has': 'hæz', 'had': 'hæd',
    'do': 'duː', 'does': 'dʌz', 'did': 'dɪd', 'done': 'dʌn',
    'will': 'wɪl', 'would': 'wʊd', 'can': 'kæn', 'could': 'kʊd',
    'shall': 'ʃæl', 'should': 'ʃʊd', 'may': 'meɪ', 'might': 'maɪt',
    'must': 'mʌst', 'need': 'niːd',
    'get': 'ɡɛt', 'got': 'ɡɑt', 'go': 'ɡoʊ', 'went': 'wɛnt',
    'come': 'kʌm', 'came': 'keɪm',
    'make': 'meɪk', 'made': 'meɪd',
    'say': 'seɪ', 'said': 'sɛd',
    'know': 'noʊ', 'think': 'θɪŋk', 'see': 'siː',
    'look': 'lʊk', 'find': 'faɪnd', 'give': 'ɡɪv', 'use': 'juːz',
    'tell': 'tɛl', 'call': 'kɔːl', 'keep': 'kiːp', 'let': 'lɛt',
    'seem': 'siːm', 'feel': 'fiːl', 'try': 'tɹaɪ', 'leave': 'liːv',
    'put': 'pʊt', 'mean': 'miːn', 'show': 'ʃoʊ',
    'time': 'taɪm', 'year': 'jɪɹ', 'day': 'deɪ', 'way': 'weɪ',
    'man': 'mæn', 'men': 'mɛn', 'word': 'wɜːɹd',
    'world': 'wɜːɹld', 'life': 'laɪf', 'hand': 'hænd',
    'place': 'pleɪs', 'case': 'keɪs', 'thing': 'θɪŋ', 'home': 'hoʊm',
    'water': 'wɔːtɚ', 'room': 'ɹuːm', 'book': 'bʊk',
    'eye': 'aɪ', 'door': 'dɔːɹ', 'face': 'feɪs', 'name': 'neɪm',
    'people': 'piːpəl', 'child': 'tʃaɪld', 'children': 'tʃɪldɹən',
    'one': 'wʌn', 'two': 'tuː', 'three': 'θɹiː',
    'not': 'nɑt', 'all': 'ɔːl', 'some': 'sʌm', 'more': 'mɔːɹ',
    'very': 'vɛɹiː', 'just': 'dʒʌst', 'also': 'ɔːlsoʊ',
    'even': 'iːvən', 'well': 'wɛl', 'such': 'sʌtʃ', 'only': 'oʊnliː',
    'any': 'ɛniː', 'many': 'mɛniː', 'each': 'iːtʃ', 'long': 'lɔːŋ',
    'down': 'daʊn', 'first': 'fɜːɹst', 'other': 'ʌðɚ', 'about': 'əbaʊt',
    'hello': 'hɛloʊ', 'hi': 'haɪ', 'hey': 'heɪ',
    'bye': 'baɪ', 'goodbye': 'ɡʊdbaɪ',
    'yes': 'jɛs', 'no': 'noʊ', 'okay': 'oʊkeɪ', 'ok': 'oʊkeɪ',
    'please': 'pliːz', 'thanks': 'θæŋks', 'thank': 'θæŋk',
    'sorry': 'sɑɹiː', 'am': 'æm',
    "i'm": "aɪm", "you're": "jʊɹ", "he's": "hiːz", "she's": "ʃiːz",
    "it's": "ɪts", "we're": "wɪɹ", "they're": "ðɛɹ",
    "i've": "aɪv", "you've": "juːv", "we've": "wiːv", "they've": "ðeɪv",
    "i'll": "aɪl", "you'll": "juːl", "he'll": "hiːl", "she'll": "ʃiːl",
    "we'll": "wiːl", "they'll": "ðeɪl",
    "i'd": "aɪd", "you'd": "juːd", "he'd": "hiːd", "she'd": "ʃiːd",
    "we'd": "wiːd", "they'd": "ðeɪd",
    "isn't": "ɪzənt", "aren't": "ɑːɹnt",
    "wasn't": "wʌzənt", "weren't": "wɜːɹnt",
    "haven't": "hævənt", "hasn't": "hæzənt", "hadn't": "hædənt",
    "won't": "woʊnt", "wouldn't": "wʊdənt",
    "don't": "doʊnt", "doesn't": "dʌzənt", "didn't": "dɪdənt",
    "can't": "kænt", "couldn't": "kʊdənt",
    "shouldn't": "ʃʊdənt", "mightn't": "maɪtənt", "mustn't": "mʌstənt",
  };
}
