import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';

void main() {
  late HttpServer server;
  late Directory root;
  late ModelDownloader downloader;
  late Future<void> Function(HttpRequest) respond;
  const voice = Voice(id: 'test', name: 'Test', engine: EngineId.kokoro);
  String url() => 'http://127.0.0.1:${server.port}/voice';
  File partial() => File('${root.path}/kokoro/voices/test.bin.part');
  File target() => File('${root.path}/kokoro/voices/test.bin');
  Future<void> seedPartial() async {
    await partial().parent.create(recursive: true);
    await partial().writeAsBytes([1, 2]);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tts-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) async {
      request.response.contentLength = 4;
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    };
    server.listen((request) async {
      try {
        await respond(request);
      } catch (_) {
        await request.response.close();
      }
    });
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final original = options.uri;
          options.path = 'http://127.0.0.1:${server.port}${original.path}';
          handler.next(options);
        },
      ),
    );
    downloader = ModelDownloader(dio: dio, directoryProvider: () async => root);
  });
  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('valid range appends only missing bytes', () async {
    await seedPartial();
    respond = (request) async {
      expect(request.headers.value('range'), 'bytes=2-');
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 2-3/4');
      request.response.contentLength = 2;
      request.response.add([3, 4]);
      await request.response.close();
    };
    await downloader.downloadVoiceEmbedding(voice, url());
    expect(await target().readAsBytes(), [1, 2, 3, 4]);
    expect(await partial().exists(), isFalse);
  });
  test('ignored range replaces the partial file', () async {
    await seedPartial();
    await downloader.downloadVoiceEmbedding(voice, url());
    expect(await target().readAsBytes(), [1, 2, 3, 4]);
  });
  test('redirect returning full body replaces partial', () async {
    await seedPartial();
    respond = (request) async {
      if (request.uri.path == '/voice') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/final');
      } else {
        request.response.contentLength = 4;
        request.response.add([1, 2, 3, 4]);
      }
      await request.response.close();
    };
    await downloader.downloadVoiceEmbedding(voice, url());
    expect(await target().readAsBytes(), [1, 2, 3, 4]);
  });
  for (final status in [206, 416, 401]) {
    test('bad resume $status retries once from zero', () async {
      await seedPartial();
      var requests = 0;
      respond = (request) async {
        requests++;
        if (requests == 1) {
          request.response.statusCode = status;
          request.response.headers.set('content-range', 'bytes 0-1/4');
          request.response.add([1, 2]);
        } else {
          expect(request.headers.value('range'), isNull);
          request.response.contentLength = 4;
          request.response.add([1, 2, 3, 4]);
        }
        await request.response.close();
      };
      await downloader.downloadVoiceEmbedding(voice, url());
      expect(requests, 2);
      expect(await target().readAsBytes(), [1, 2, 3, 4]);
    });
  }
  test('truncated body is never promoted', () async {
    respond = (request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nabc',
      );
      await socket.flush();
      await socket.close();
    };
    await expectLater(
      downloader.downloadVoiceEmbedding(voice, url()),
      throwsA(anything),
    );
    expect(await target().exists(), isFalse);
  });
  test('failed voice download can be retried', () async {
    var fail = true;
    respond = (request) async {
      request.response.statusCode = fail ? 404 : 200;
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    };
    await expectLater(
      downloader.downloadVoiceEmbedding(voice, url()),
      throwsA(isA<DioException>()),
    );
    expect(await target().exists(), isFalse);
    fail = false;
    await downloader.downloadVoiceEmbedding(voice, url());
    expect(await target().length(), 4);
  });
  test('cancellation preserves partial and allows retry', () async {
    final progress = <FileProgress>[];
    await for (final item in downloader.downloadEngineFiles(
      EngineId.supertonic,
    )) {
      progress.add(item);
      downloader.cancelDownload(EngineId.supertonic);
    }
    expect(progress.any((p) => p.isComplete), isFalse);
    expect(
      await File('${root.path}/supertonic/duration_predictor.onnx').exists(),
      isFalse,
    );
    await downloader.downloadEngineFiles(EngineId.supertonic).drain<void>();
    expect(await downloader.isEngineDownloaded(EngineId.supertonic), isTrue);
  });
  test('shared writes are serialized across downloader instances', () async {
    var active = 0;
    var maximum = 0;
    respond = (request) async {
      active++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
      active--;
    };
    final second = ModelDownloader(directoryProvider: () async => root);
    await Future.wait([
      downloader.downloadVoiceEmbedding(voice, url()),
      second.downloadVoiceEmbedding(voice, url()),
    ]);
    expect(maximum, 1);
  });
  test(
    'existing ZIP repairs extraction and deletion preserves shared data',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile('espeak-ng-data/phondata', 3, [1, 2, 3]));
      archive.addFile(ArchiveFile('__MACOSX/._espeak-ng-data', 1, [0]));
      final zip = ZipEncoder().encode(archive);
      respond = (request) async {
        request.response.add(
          request.uri.path.endsWith('.zip') ? zip : [1, 2, 3, 4],
        );
        await request.response.close();
      };
      await downloader.downloadEngineFiles(EngineId.kitten).drain<void>();
      final data = Directory('${root.path}/espeak-ng-data');
      await data.delete(recursive: true);
      await downloader.downloadEngineFiles(EngineId.kitten).drain<void>();
      expect(await File('${data.path}/.complete').exists(), isTrue);
      await downloader.deleteEngineFiles(EngineId.kitten);
      expect(await File('${root.path}/en-us.bin').exists(), isTrue);
      expect(await data.exists(), isTrue);
    },
  );
  test('installed linguistic data avoids a second archive request', () async {
    final marker = File('${root.path}/espeak-ng-data/.complete');
    await marker.parent.create(recursive: true);
    await marker.writeAsString('1');
    var zipRequests = 0;
    respond = (request) async {
      if (request.uri.path.endsWith('.zip')) {
        zipRequests++;
        request.response.statusCode = 404;
      } else {
        request.response.add([1, 2, 3, 4]);
      }
      await request.response.close();
    };
    final progress = await downloader
        .downloadEngineFiles(EngineId.kitten)
        .toList();
    expect(zipRequests, 0);
    expect(progress.last.isComplete, isTrue);
    expect(progress.last.fraction, 1);
  });
  test('archive traversal fails without an installation marker', () async {
    final archive = Archive()..addFile(ArchiveFile('../escaped', 3, [1, 2, 3]));
    final zip = ZipEncoder().encode(archive);
    respond = (request) async {
      request.response.add(
        request.uri.path.endsWith('.zip') ? zip : [1, 2, 3, 4],
      );
      await request.response.close();
    };
    await expectLater(
      downloader.downloadEngineFiles(EngineId.kitten).drain<void>(),
      throwsFormatException,
    );
    expect(
      await File('${root.path}/espeak-ng-data/.complete').exists(),
      isFalse,
    );
    expect(await File('${root.parent.path}/escaped').exists(), isFalse);
  });
}
