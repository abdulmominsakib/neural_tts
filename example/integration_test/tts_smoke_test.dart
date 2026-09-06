import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('System TTS completes, interrupts, and reloads', (tester) async {
    final engine = SystemEngine();
    try {
      final voices = await engine.getVoices();
      expect(
        voices,
        isNotEmpty,
        reason: 'Install an OS TTS voice for this smoke test',
      );
      final voice = voices.firstWhere(
        (voice) => voice.language == 'en-US',
        orElse: () => voices.first,
      );
      await engine.play('Playback completion test.', voice);
      final playback = engine.play(
        List.filled(20, 'This speech will be interrupted.').join(' '),
        voice,
      );
      final interrupted = expectLater(playback, throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await engine.stop();
      await interrupted;
      await engine.release();
      await engine.play('Reload succeeded.', voice);
    } finally {
      await engine.release();
    }
  });

  for (final id in [EngineId.kitten, EngineId.kokoro, EngineId.supertonic]) {
    testWidgets('${id.name} playback and cancellation with installed models', (
      tester,
    ) async {
      final engine = createEngine(id);
      final downloader = ModelDownloader();
      if (!await downloader.isEngineDownloaded(id)) {
        if (const bool.fromEnvironment('DOWNLOAD_TTS_MODELS')) {
          // Exercise extraction with the example's existing linguistic archive.
          // The default remote archive may be unavailable independently of models.
          if (id != EngineId.supertonic) {
            final dir = await downloader.getEngineDir(id);
            final archive = await rootBundle.load('assets/espeak-ng-data.zip');
            await File('${dir.path}/espeak-ng-data.zip').writeAsBytes(
              archive.buffer.asUint8List(
                archive.offsetInBytes,
                archive.lengthInBytes,
              ),
            );
          }
          await downloader.downloadEngineFiles(id).drain<void>();
        } else {
          markTestSkipped(
            'Models absent; rerun with --dart-define=DOWNLOAD_TTS_MODELS=true',
          );
          return;
        }
      }
      try {
        final voice = (await engine.getVoices()).first;
        await engine.play('Hello from the speech engine.', voice);
        final stream = engine.playStreaming(voice);
        stream.appendText('Streaming completion. ');
        stream.appendText('Final sentence.');
        await stream.finalize();
        final playback = engine.play(
          List.filled(20, 'Cancel this speech.').join(' '),
          voice,
        );
        final interrupted = expectLater(playback, throwsA(anything));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.stop();
        await interrupted;
      } finally {
        await engine.release();
      }
    });
  }
}
