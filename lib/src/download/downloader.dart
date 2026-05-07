import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

import '../constants.dart';
import '../engine.dart';
import 'models.dart';

class ModelDownloader {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _activeDownloads = {};

  Future<Directory> getTtsDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/$ttsParentSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> getEngineDir(EngineId engine) async {
    final ttsDir = await getTtsDir();
    final subdir = _engineSubdir(engine);
    final dir = Directory('${ttsDir.path}/$subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _engineSubdir(EngineId engine) {
    switch (engine) {
      case EngineId.kitten:
        return 'kitten';
      case EngineId.kokoro:
        return 'kokoro';
      case EngineId.supertonic:
        return 'supertonic';
      case EngineId.system:
        return 'system';
    }
  }

  Future<bool> isEngineDownloaded(EngineId engine) async {
    final dir = await getEngineDir(engine);
    final files = _coreFiles(engine);
    final ttsDir = await getTtsDir();

    for (final file in files) {
      if (file.fileName == 'espeak-ng-data.zip') {
        // Check if the extracted directory exists
        if (!await Directory('${ttsDir.path}/espeak-ng-data').exists()) {
          return false;
        }
        continue;
      }

      final isDictFile = file.fileName == 'en-us.bin';
      final path = isDictFile
          ? '${ttsDir.path}/${file.fileName}'
          : '${dir.path}/${file.fileName}';
      if (!await File(path).exists()) {
        return false;
      }
    }
    return true;
  }

  List<ModelFile> _coreFiles(EngineId engine) {
    switch (engine) {
      case EngineId.kitten:
        return [
          ...KittenVariant.nanoInt8.files,
          const ModelFile(
            fileName: 'en-us.bin',
            downloadUrl: ttsDictUrl,
            sizeBytes: 15 * 1024 * 1024,
          ),
          const ModelFile(
            fileName: 'espeak-ng-data.zip',
            downloadUrl: espeakDataUrl,
            sizeBytes: 3 * 1024 * 1024,
          ),
        ];
      case EngineId.kokoro:
        return [
          ..._kokoroCoreFiles,
          const ModelFile(
            fileName: 'en-us.bin',
            downloadUrl: ttsDictUrl,
            sizeBytes: 15 * 1024 * 1024,
          ),
          const ModelFile(
            fileName: 'espeak-ng-data.zip',
            downloadUrl: espeakDataUrl,
            sizeBytes: 3 * 1024 * 1024,
          ),
        ];
      case EngineId.supertonic:
        return [..._supertonicCoreFiles];
      case EngineId.system:
        return [];
    }
  }

  static const _kokoroCoreFiles = [
    ModelFile(
      fileName: 'model.onnx',
      downloadUrl: '$kokoroModelBaseUrl/onnx/model_fp16.onnx',
      sizeBytes: 82 * 1024 * 1024,
    ),
    ModelFile(
      fileName: 'tokenizer.json',
      downloadUrl: '$kokoroModelBaseUrl/tokenizer.json',
      sizeBytes: 500 * 1024,
    ),
    // Per-voice style embeddings (raw float32 binary, ~522 kB each)
    ModelFile(
      fileName: 'voices/af_heart.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_heart.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_bella.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_bella.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_nicole.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_nicole.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_sarah.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_sarah.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_sky.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_sky.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_aoede.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_aoede.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_jessica.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_jessica.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_kore.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_kore.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/af_river.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/af_river.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_adam.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_adam.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_echo.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_echo.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_eric.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_eric.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_fenrir.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_fenrir.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_liam.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_liam.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_michael.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_michael.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_onyx.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_onyx.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/am_santa.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/am_santa.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/bf_alice.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/bf_alice.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/bf_emma.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/bf_emma.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/bf_lily.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/bf_lily.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/bm_george.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/bm_george.bin',
      sizeBytes: 524 * 1024,
    ),
    ModelFile(
      fileName: 'voices/bm_lewis.bin',
      downloadUrl: '$kokoroVoicesBaseUrl/bm_lewis.bin',
      sizeBytes: 524 * 1024,
    ),
  ];

  static const _supertonicCoreFiles = [
    // 4 ONNX pipeline models + unicode indexer (downloaded from onnx/ subpath, stored flat)
    ModelFile(
      fileName: 'duration_predictor.onnx',
      downloadUrl: '$supertonicModelBaseUrl/onnx/duration_predictor.onnx',
      sizeBytes: 500 * 1024,
    ),
    ModelFile(
      fileName: 'text_encoder.onnx',
      downloadUrl: '$supertonicModelBaseUrl/onnx/text_encoder.onnx',
      sizeBytes: 500 * 1024,
    ),
    ModelFile(
      fileName: 'vector_estimator.onnx',
      downloadUrl: '$supertonicModelBaseUrl/onnx/vector_estimator.onnx',
      sizeBytes: 500 * 1024,
    ),
    ModelFile(
      fileName: 'vocoder.onnx',
      downloadUrl: '$supertonicModelBaseUrl/onnx/vocoder.onnx',
      sizeBytes: 500 * 1024,
    ),
    ModelFile(
      fileName: 'unicode_indexer.json',
      downloadUrl: '$supertonicModelBaseUrl/onnx/unicode_indexer.json',
      sizeBytes: 6 * 1024,
    ),
    // Per-voice style embeddings (JSON with style_ttl + style_dp arrays)
    ModelFile(
      fileName: 'voices/F1.json',
      downloadUrl: '$supertonicVoicesBaseUrl/F1.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/F2.json',
      downloadUrl: '$supertonicVoicesBaseUrl/F2.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/F3.json',
      downloadUrl: '$supertonicVoicesBaseUrl/F3.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/F4.json',
      downloadUrl: '$supertonicVoicesBaseUrl/F4.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/F5.json',
      downloadUrl: '$supertonicVoicesBaseUrl/F5.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/M1.json',
      downloadUrl: '$supertonicVoicesBaseUrl/M1.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/M2.json',
      downloadUrl: '$supertonicVoicesBaseUrl/M2.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/M3.json',
      downloadUrl: '$supertonicVoicesBaseUrl/M3.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/M4.json',
      downloadUrl: '$supertonicVoicesBaseUrl/M4.json',
      sizeBytes: 53 * 1024,
    ),
    ModelFile(
      fileName: 'voices/M5.json',
      downloadUrl: '$supertonicVoicesBaseUrl/M5.json',
      sizeBytes: 53 * 1024,
    ),
  ];

  Stream<FileProgress> downloadEngineFiles(EngineId engine) async* {
    final engineId = engine.name;
    final dir = await getEngineDir(engine);
    final ttsDir = await getTtsDir();
    final files = _coreFiles(engine);

    debugPrint('[Downloader] Starting download for engine=$engineId');
    debugPrint('[Downloader] Engine dir: ${dir.path}');
    debugPrint('[Downloader] TTS dir:    ${ttsDir.path}');
    debugPrint(
      '[Downloader] Files to download: ${files.map((f) => f.fileName).join(', ')}',
    );

    for (final file in files) {
      final cancelToken = CancelToken();
      _activeDownloads[engineId] = cancelToken;

      final isDictFile = file.fileName == 'en-us.bin';
      final filePath = isDictFile
          ? '${ttsDir.path}/${file.fileName}'
          : '${dir.path}/${file.fileName}';
      final partialPath = '$filePath.part';
      final partialFile = File(partialPath);

      // Ensure parent directories exist (needed for nested paths like onnx/, voices/)
      final parentDir = File(filePath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      final finalFile = File(filePath);
      if (await finalFile.exists()) {
        debugPrint(
          '[Downloader] SKIP ${file.fileName} — already exists at $filePath',
        );
        yield FileProgress(
          fileName: file.fileName,
          receivedBytes: await finalFile.length(),
          totalBytes: await finalFile.length(),
          isComplete: true,
        );
        continue;
      }

      int receivedBytes = 0;
      if (await partialFile.exists()) {
        receivedBytes = await partialFile.length();
        debugPrint(
          '[Downloader] Partial file found: $partialPath (${receivedBytes} bytes)',
        );
      } else {
        debugPrint(
          '[Downloader] No partial file, starting fresh: $partialPath',
        );
      }

      debugPrint(
        '[Downloader] Downloading ${file.fileName} from ${file.downloadUrl}',
      );

      try {
        ResolveResult resolved;
        try {
          resolved = await _resolveWithRedirects(
            url: file.downloadUrl,
            startByte: receivedBytes,
            cancelToken: cancelToken,
          );
        } on DioException catch (e) {
          // HuggingFace redirects to pre-signed CDN URLs whose AWS signature
          // does NOT cover the Range header. Sending Range to the CDN causes
          // a signature mismatch → 401. Retry from scratch without Range.
          debugPrint(
            '[Downloader] ERROR resolving ${file.fileName}: status=${e.response?.statusCode} receivedBytes=$receivedBytes',
          );
          debugPrint('[Downloader]   DioException type: ${e.type}');
          debugPrint('[Downloader]   DioException message: ${e.message}');
          debugPrint('[Downloader]   Response headers: ${e.response?.headers}');
          if (receivedBytes > 0 && e.response?.statusCode == 401) {
            debugPrint(
              '[Downloader] 401 on resume — deleting partial and retrying from scratch',
            );
            if (await partialFile.exists()) {
              await partialFile.delete();
            }
            receivedBytes = 0;
            resolved = await _resolveWithRedirects(
              url: file.downloadUrl,
              startByte: 0,
              cancelToken: cancelToken,
            );
          } else {
            rethrow;
          }
        }

        final response = resolved.response;
        debugPrint(
          '[Downloader] Got stream response for ${file.fileName} | status=${response.statusCode} | crossedHost=${resolved.crossedHost}',
        );
        debugPrint(
          '[Downloader]   Content-Length header: ${response.headers.value(Headers.contentLengthHeader)}',
        );
        debugPrint(
          '[Downloader]   Final URL host: ${response.requestOptions.uri.host}',
        );

        final contentLength = response.headers.value(
          Headers.contentLengthHeader,
        );
        final totalBytes = contentLength != null
            ? int.parse(contentLength) + receivedBytes
            : file.sizeBytes;
        debugPrint(
          '[Downloader]   totalBytes=$totalBytes (receivedBytes=$receivedBytes)',
        );

        final writeMode = receivedBytes > 0 ? FileMode.append : FileMode.write;
        debugPrint(
          '[Downloader]   Opening sink in mode=${writeMode == FileMode.append ? 'append' : 'write'}: $partialPath',
        );
        final sink = partialFile.openWrite(mode: writeMode);
        final stream = response.data?.stream;

        if (stream == null) {
          await sink.close();
          debugPrint(
            '[Downloader] ERROR: response data stream is null for ${file.fileName}',
          );
          throw DioException(
            requestOptions: response.requestOptions,
            error: 'Response data stream is null',
          );
        }

        DateTime lastProgressUpdate = DateTime.now();
        int chunkCount = 0;

        try {
          await for (final chunk in stream) {
            if (cancelToken.isCancelled) {
              debugPrint(
                '[Downloader] Cancelled during stream for ${file.fileName}',
              );
              break;
            }
            sink.add(chunk);
            receivedBytes += chunk.length;
            chunkCount++;

            final now = DateTime.now();
            if (now.difference(lastProgressUpdate).inMilliseconds >= 500) {
              debugPrint(
                '[Downloader]   Progress ${file.fileName}: $receivedBytes / $totalBytes bytes (chunk #$chunkCount)',
              );
              yield FileProgress(
                fileName: file.fileName,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
              );
              lastProgressUpdate = now;
            }
          }
        } catch (streamError, st) {
          debugPrint(
            '[Downloader] ERROR reading stream for ${file.fileName}: $streamError',
          );
          debugPrint('[Downloader]   Stack: $st');
          await sink.close();
          rethrow;
        }

        debugPrint(
          '[Downloader] Stream complete for ${file.fileName}. Flushing sink...',
        );
        await sink.flush();
        await sink.close();
        debugPrint('[Downloader] Renaming $partialPath → $filePath');
        await partialFile.rename(filePath);
        debugPrint(
          '[Downloader] DONE ${file.fileName} | total=$receivedBytes bytes',
        );

        yield FileProgress(
          fileName: file.fileName,
          receivedBytes: receivedBytes,
          totalBytes: receivedBytes,
          isComplete: true,
        );

        if (file.fileName == 'espeak-ng-data.zip') {
          debugPrint('[Downloader] Unzipping espeak-ng-data.zip...');
          await _unzipEspeakData(filePath, ttsDir.path);
          debugPrint('[Downloader] Unzip complete.');
        }
      } catch (e, st) {
        if (e is DioException && CancelToken.isCancel(e)) {
          debugPrint('[Downloader] Download cancelled for ${file.fileName}');
          return;
        }
        debugPrint('[Downloader] FATAL ERROR for ${file.fileName}: $e');
        debugPrint('[Downloader]   Stack: $st');
        rethrow;
      }
    }
    debugPrint('[Downloader] All files downloaded for engine=$engineId');
  }

  Future<void> downloadVoiceEmbedding(Voice voice, String voiceUrl) async {
    final engineDir = await getEngineDir(voice.engine);
    final ext = voice.engine == EngineId.supertonic ? '.json' : '.bin';
    final fileName = '${voice.id}$ext';
    final filePath = '${engineDir.path}/voices/$fileName';
    final file = File(filePath);

    if (await file.exists()) return;

    await file.create(recursive: true);
    final response = await _dio.download(voiceUrl, filePath);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download voice embedding: ${response.statusCode}',
      );
    }
  }

  void cancelDownload(EngineId engine) {
    _activeDownloads[engine.name]?.cancel();
  }

  Future<void> deleteEngine(EngineId engine) async {
    final dir = await getEngineDir(engine);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> deleteEngineFiles(EngineId engine) async {
    final dir = await getEngineDir(engine);
    final ttsDir = await getTtsDir();
    final files = _coreFiles(engine);
    for (final file in files) {
      final isDictFile = file.fileName == 'en-us.bin';
      final baseDir = isDictFile ? ttsDir : dir;
      final f = File('${baseDir.path}/${file.fileName}');
      if (await f.exists()) await f.delete();
      final pf = File('${baseDir.path}/${file.fileName}.part');
      if (await pf.exists()) await pf.delete();
    }
  }

  Future<void> _unzipEspeakData(String zipPath, String targetDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('$targetDir/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('$targetDir/$filename').createSync(recursive: true);
      }
    }
  }

  Future<ResolveResult> _resolveWithRedirects({
    required String url,
    required int startByte,
    required CancelToken cancelToken,
  }) async {
    String currentUrl = url;
    final originalUri = Uri.parse(url);
    // Track whether we crossed to a different host (e.g. HF → XetHub CDN).
    // Pre-signed CDN URLs are signed only over 'host'; adding a Range header
    // causes an AWS signature mismatch and a 401 response.
    bool crossedHost = false;

    debugPrint(
      '[Downloader:resolve] Starting resolve: $url | startByte=$startByte',
    );

    for (int hop = 0; hop < 5; hop++) {
      final currentUri = Uri.parse(currentUrl);
      final isOnOriginalHost = currentUri.host == originalUri.host;
      if (!isOnOriginalHost) crossedHost = true;

      // Only send Range on the original host. CDN pre-signed URLs don't
      // include Range in their AWS signature, so sending it would cause 401.
      final effectiveStartByte = isOnOriginalHost ? startByte : 0;

      debugPrint(
        '[Downloader:resolve] hop=$hop host=${currentUri.host} isOriginalHost=$isOnOriginalHost effectiveStartByte=$effectiveStartByte crossedHost=$crossedHost',
      );

      final options = Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          if (effectiveStartByte > 0) 'Range': 'bytes=$effectiveStartByte-',
        },
      );

      if (!isOnOriginalHost) {
        options.headers?.remove('Authorization');
      }

      debugPrint(
        '[Downloader:resolve]   GET $currentUrl | headers=${options.headers}',
      );

      final response = await _dio.get<ResponseBody>(
        currentUrl,
        options: options,
        cancelToken: cancelToken,
      );

      debugPrint(
        '[Downloader:resolve]   Response status=${response.statusCode}',
      );
      debugPrint(
        '[Downloader:resolve]   Response headers: ${response.headers.map}',
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        debugPrint(
          '[Downloader:resolve] SUCCESS at hop=$hop | status=${response.statusCode}',
        );
        return ResolveResult(response: response, crossedHost: crossedHost);
      }

      if (response.statusCode! >= 300 && response.statusCode! < 400) {
        final location = response.headers.value('location');
        if (location == null) {
          debugPrint(
            '[Downloader:resolve] ERROR: redirect ${response.statusCode} with no Location header',
          );
          throw DioException(
            requestOptions: response.requestOptions,
            error: 'Redirect without location header',
          );
        }
        final nextUrl = Uri.parse(currentUrl).resolve(location).toString();
        debugPrint(
          '[Downloader:resolve]   Redirect ${response.statusCode} → $nextUrl',
        );
        currentUrl = nextUrl;
        continue;
      }

      debugPrint(
        '[Downloader:resolve] ERROR: unexpected status=${response.statusCode} at hop=$hop url=$currentUrl',
      );
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Server returned ${response.statusCode}',
      );
    }

    debugPrint('[Downloader:resolve] ERROR: too many redirects for $url');
    throw DioException(
      requestOptions: RequestOptions(path: url),
      error: 'Too many redirects',
    );
  }
}

class ResolveResult {
  final Response<ResponseBody> response;
  final bool crossedHost;
  const ResolveResult({required this.response, required this.crossedHost});
}
