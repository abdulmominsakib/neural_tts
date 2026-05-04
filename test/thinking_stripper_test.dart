import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  group('ThinkingStripper', () {
    test('passes through plain text unchanged', () {
      final s = ThinkingStripper();
      expect(s.feed('Hello world'), equals('Hello world'));
      expect(s.flush(), isEmpty);
    });

    test('strips single think block', () {
      final s = ThinkingStripper();
      expect(s.feed('Before <think>internal</think> after'), equals('Before  after'));
    });

    test('strips think block spanning multiple chunks', () {
      final s = ThinkingStripper();
      expect(s.feed('Before <think>'), equals('Before '));
      expect(s.feed('internal'), isEmpty);
      expect(s.feed('</think> after'), equals(' after'));
    });

    test('detects non-empty think', () {
      final s = ThinkingStripper();
      s.feed('<think>something</think>');
      expect(s.hadNonEmptyThink(), isTrue);
    });

    test('no think content detected', () {
      final s = ThinkingStripper();
      s.feed('<think></think>');
      expect(s.hadNonEmptyThink(), isFalse);
    });

    test('flush is empty after feed consumes all content', () {
      final s = ThinkingStripper();
      s.feed('outside <think>inside');
      expect(s.hadNonEmptyThink(), isTrue);
      expect(s.flush(), isEmpty);
    });

    test('stripFinal static helper', () {
      final result = ThinkingStripper.stripFinal('Hello <think>reasoning</think> world');
      expect(result.text, equals('Hello  world'));
      expect(result.hadReasoning, isTrue);
    });

    test('stripFinal static helper without reasoning', () {
      final result = ThinkingStripper.stripFinal('Hello world', hadReasoning: true);
      expect(result.text, equals('Hello world'));
      expect(result.hadReasoning, isTrue);
    });
  });
}
