class ThinkingStripper {
  String _buffer = '';
  bool _inside = false;
  bool _nonEmptyThink = false;
  String _reasoningAccumulator = '';

  static const _placeholders = [
    'Hmm, let me think.',
    'Hmm.',
    'Let me think.',
    'Okay, let me think about that.',
    'One moment.',
    'Let me consider this.',
  ];

  static final _random = _SeededRandom();

  String feed(String chunk) {
    _buffer += chunk;
    final result = StringBuffer();

    while (_buffer.isNotEmpty) {
      if (_inside) {
        final closeIdx = _buffer.indexOf('</think>');
        if (closeIdx == -1) {
          final content = _buffer.trim();
          if (content.isNotEmpty) _nonEmptyThink = true;
          _buffer = '';
          break;
        } else {
          final content = _buffer.substring(0, closeIdx).trim();
          if (content.isNotEmpty) _nonEmptyThink = true;
          _buffer = _buffer.substring(closeIdx + '</think>'.length);
          _inside = false;
        }
      } else {
        final openIdx = _buffer.indexOf('<think>');
        if (openIdx == -1) {
          result.write(_buffer);
          _buffer = '';
          break;
        } else {
          result.write(_buffer.substring(0, openIdx));
          _buffer = _buffer.substring(openIdx + '<think>'.length);
          _inside = true;
        }
      }
    }

    return result.toString();
  }

  String flush() {
    final result = _buffer;
    _buffer = '';
    _inside = false;
    return result;
  }

  bool hadNonEmptyThink() => _nonEmptyThink;

  void noteReasoning(String delta) {
    _reasoningAccumulator += delta;
    if (_reasoningAccumulator.trim().isNotEmpty) {
      _nonEmptyThink = true;
    }
  }

  String get placeholder {
    return _placeholders[_random.nextInt(_placeholders.length)];
  }

  static StripResult stripFinal(String text, {bool? hadReasoning}) {
    final stripper = ThinkingStripper();
    final cleaned = stripper.feed(text) + stripper.flush();
    final detected = hadReasoning ?? stripper.hadNonEmptyThink();
    return StripResult(text: cleaned, hadReasoning: detected);
  }
}

class StripResult {
  final String text;
  final bool hadReasoning;

  const StripResult({required this.text, required this.hadReasoning});
}

class _SeededRandom {
  int _seed = DateTime.now().microsecondsSinceEpoch;

  int nextInt(int max) {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed % max;
  }
}
