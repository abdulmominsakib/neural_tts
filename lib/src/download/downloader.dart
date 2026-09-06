import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

import '../constants.dart';
import '../engine.dart';
import 'models.dart';

class ModelDownloader {
  final Dio _dio;
  final Future<Directory> Function()? _directoryProvider;
  final String _espeakArchiveUrl;
  ModelDownloader({
    Dio? dio,
    Future<Directory> Function()? directoryProvider,
    String espeakArchiveUrl = espeakDataUrl,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _directoryProvider = directoryProvider,
       _espeakArchiveUrl = espeakArchiveUrl;
  final Map<String, CancelToken> _activeDownloads = {};

  Future<Directory> getTtsDir() async {
    if (_directoryProvider != null) return _directoryProvider();
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
        if (!await File('${ttsDir.path}/espeak-ng-data/.complete').exists()) {
          return false;
        }
        continue;
      }

      final isDictFile = file.fileName == 'en-us.bin';
      final path = isDictFile
          ? '${ttsDir.path}/${file.fileName}'
          : '${dir.path}/${file.fileName}';
      if (!await File(path).exists() || await File(path).length() == 0) {
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
          ModelFile(
            fileName: 'espeak-ng-data.zip',
            downloadUrl: _espeakArchiveUrl,
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
          ModelFile(
            fileName: 'espeak-ng-data.zip',
            downloadUrl: _espeakArchiveUrl,
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

  static Future<void> _writeTail = Future.value();

  Stream<FileProgress> downloadEngineFiles(EngineId engine) async* {
    if (_activeDownloads.containsKey(engine.name)) {
      throw StateError('Download already active for ${engine.name}');
    }
    final token = CancelToken();
    _activeDownloads[engine.name] = token;
    final previous = _writeTail;
    final finished = Completer<void>();
    _writeTail = finished.future;
    try {
      await previous;
      if (token.isCancelled) throw token.cancelError!;
      final dir = await getEngineDir(engine);
      final root = await getTtsDir();
      for (final file in _coreFiles(engine)) {
        if (token.isCancelled) throw token.cancelError!;
        if (file.fileName == 'espeak-ng-data.zip' &&
            await File('${root.path}/espeak-ng-data/.complete').exists()) {
          yield FileProgress(fileName: file.fileName, isComplete: true);
          continue;
        }
        final path = file.fileName == 'en-us.bin'
            ? '${root.path}/${file.fileName}'
            : '${dir.path}/${file.fileName}';
        await for (final progress in _download(file, path, token)) {
          if (!progress.isComplete) yield progress;
        }
        if (token.isCancelled) throw token.cancelError!;
        if (file.fileName == 'espeak-ng-data.zip') {
          await _unzipEspeakData(path, root.path, token);
        }
        if (token.isCancelled) throw token.cancelError!;
        final length = await File(path).length();
        yield FileProgress(
          fileName: file.fileName,
          receivedBytes: length,
          totalBytes: length,
          isComplete: true,
        );
      }
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error)) rethrow;
    } finally {
      token.cancel();
      if (identical(_activeDownloads[engine.name], token)) {
        _activeDownloads.remove(engine.name);
      }
      finished.complete();
    }
  }

  Stream<FileProgress> _download(
    ModelFile file,
    String path,
    CancelToken token,
  ) async* {
    final target = File(path);
    await target.parent.create(recursive: true);
    if (await target.exists() && await target.length() > 0) return;
    final partial = File('$path.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    Response<ResponseBody>? response;
    int? expected;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = (await _resolveWithRedirects(
          url: file.downloadUrl,
          startByte: offset,
          cancelToken: token,
        )).response;
        if (response.statusCode == 200) {
          offset =
              0; // Range ignored, including redirects that return a full file.
          expected = int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '',
          );
          break;
        }
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
        ).firstMatch(response.headers.value('content-range') ?? '');
        if (range != null &&
            int.parse(range[1]!) == offset &&
            int.parse(range[2]!) >= offset &&
            int.parse(range[2]!) + 1 == int.parse(range[3]!)) {
          expected = int.parse(range[3]!);
          break;
        }
        await response.data?.stream.listen(null).cancel();
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Invalid Content-Range',
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error) ||
            attempt == 1 ||
            !(error.response?.statusCode == 206 ||
                error.response?.statusCode == 416 ||
                (offset > 0 && error.response?.statusCode == 401)))
          rethrow;
        offset = 0;
        response = null;
      }
    }
    final body = response?.data;
    if (body == null) throw StateError('Missing download response');
    if (token.isCancelled) throw token.cancelError!;
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    unawaited(sink.done.catchError((Object _) {}));
    var received = offset;
    try {
      await for (final chunk in body.stream) {
        if (token.isCancelled) throw token.cancelError!;
        sink.add(chunk);
        received += chunk.length;
        yield FileProgress(
          fileName: file.fileName,
          receivedBytes: received,
          totalBytes: expected ?? file.sizeBytes,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (token.isCancelled) throw token.cancelError!;
    if (received == 0 || (expected != null && received != expected)) {
      throw StateError(
        'Incomplete download of ${file.fileName}: $received / $expected',
      );
    }
    await partial.rename(path);
  }

  Future<void> downloadVoiceEmbedding(Voice voice, String voiceUrl) async {
    final previous = _writeTail;
    final finished = Completer<void>();
    _writeTail = finished.future;
    try {
      await previous;
      if (!RegExp(r'^[\w.-]+$').hasMatch(voice.id) || voice.id == '..') {
        throw ArgumentError.value(voice.id, 'voice.id');
      }
      final dir = await getEngineDir(voice.engine);
      final ext = voice.engine == EngineId.supertonic ? '.json' : '.bin';
      final file = ModelFile(
        fileName: '${voice.id}$ext',
        downloadUrl: voiceUrl,
        sizeBytes: 0,
      );
      await _download(
        file,
        '${dir.path}/voices/${file.fileName}',
        CancelToken(),
      ).drain<void>();
    } finally {
      finished.complete();
    }
  }

  void cancelDownload(EngineId engine) =>
      _activeDownloads[engine.name]?.cancel();

  Future<void> deleteEngine(EngineId engine) async {
    cancelDownload(engine);
    final previous = _writeTail;
    final finished = Completer<void>();
    _writeTail = finished.future;
    try {
      await previous;
      final dir = await getEngineDir(engine);
      if (await dir.exists()) await dir.delete(recursive: true);
    } finally {
      finished.complete();
    }
  }

  // Linguistic data belongs to all engines and must survive removal of one.
  Future<void> deleteEngineFiles(EngineId engine) => deleteEngine(engine);

  Future<void> _unzipEspeakData(
    String zipPath,
    String targetDir,
    CancelToken token,
  ) async {
    final target = Directory('$targetDir/espeak-ng-data');
    final marker = File('${target.path}/.complete');
    if (await marker.exists()) return;
    final staging = await Directory(targetDir).createTemp('.espeak-');
    try {
      final archive = ZipDecoder().decodeBytes(
        await File(zipPath).readAsBytes(),
      );
      for (final entry in archive) {
        if (token.isCancelled) throw token.cancelError!;
        final name = entry.name.replaceAll('\\', '/');
        final parts = name.split('/');
        if (name.startsWith('/') ||
            parts.contains('..') ||
            name.contains(':') ||
            entry.isSymbolicLink) {
          throw FormatException('Unsafe archive entry: ${entry.name}');
        }
        // ZIPs made on macOS may contain harmless Finder metadata.
        if (parts.first == '__MACOSX' || parts.last == '.DS_Store') continue;
        if (parts.first != 'espeak-ng-data') {
          throw FormatException('Unexpected archive root: ${entry.name}');
        }
        final path = '${staging.path}/$name';
        if (entry.isFile) {
          final output = File(path);
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(path).create(recursive: true);
        }
      }
      final extracted = Directory('${staging.path}/espeak-ng-data');
      if (!await extracted.exists() ||
          await extracted.list(recursive: true).isEmpty) {
        throw const FormatException('Archive contains no linguistic data');
      }
      if (token.isCancelled) throw token.cancelError!;
      await File('${extracted.path}/.complete').writeAsString('1');
      if (await target.exists()) await target.delete(recursive: true);
      await extracted.rename(target.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<ResolveResult> _resolveWithRedirects({
    required String url,
    required int startByte,
    required CancelToken cancelToken,
  }) async {
    var current = Uri.parse(url);
    final original = current;
    var crossedHost = false;
    for (var hop = 0; hop < 5; hop++) {
      final sameHost = current.host == original.host;
      crossedHost |= !sameHost;
      final response = await _dio.get<ResponseBody>(
        current.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            if (startByte > 0 && sameHost) 'Range': 'bytes=$startByte-',
          },
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 200 || status == 206) {
        return ResolveResult(response: response, crossedHost: crossedHost);
      }
      await response.data?.stream.listen(null).cancel();
      final location = response.headers.value('location');
      if ({301, 302, 303, 307, 308}.contains(status) && location != null) {
        current = current.resolve(location);
        continue;
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error:
            'Download returned HTTP $status from ${current.host}${current.path}',
      );
    }
    throw StateError('Too many redirects');
  }
}

class ResolveResult {
  final Response<ResponseBody> response;
  final bool crossedHost;
  const ResolveResult({required this.response, required this.crossedHost});
}
