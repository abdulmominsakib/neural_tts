import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'supertonic_tokenizer.dart';

class SupertonicInference {
  final String durationPredictorPath;
  final String textEncoderPath;
  final String vectorEstimatorPath;
  final String vocoderPath;
  final String voicesDir;

  OrtSession? _durationPredictor;
  OrtSession? _textEncoder;
  OrtSession? _vectorEstimator;
  OrtSession? _vocoder;
  bool _initialized = false;

  final SupertonicTokenizer _tokenizer = SupertonicTokenizer();
  final Map<String, VoiceStyle> _voiceCache = {};
  final String? unicodeIndexerPath;

  SupertonicInference({
    required this.durationPredictorPath,
    required this.textEncoderPath,
    required this.vectorEstimatorPath,
    required this.vocoderPath,
    required this.voicesDir,
    this.unicodeIndexerPath,
  });

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tokenizer.initialize(vocabPath: unicodeIndexerPath);
      _durationPredictor = await _createSession(durationPredictorPath);
      _textEncoder = await _createSession(textEncoderPath);
      _vectorEstimator = await _createSession(vectorEstimatorPath);
      _vocoder = await _createSession(vocoderPath);
      _initialized = true;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<OrtSession> _createSession(String path) async {
    final ort = OnnxRuntime();
    return await ort.createSession(path);
  }

  Future<Uint8List> synthesize(
    String text,
    String voiceId,
    String language,
    int steps, {
    bool Function()? isCancelled,
  }) async {
    final owned = <OrtValue>{};
    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw StateError("Playback cancelled");
    }

    Future<OrtValue> value(dynamic data, List<int> shape) async {
      checkCancelled();
      final result = await OrtValue.fromList(data, shape);
      owned.add(result);
      return result;
    }

    Future<Map<String, OrtValue>> run(
      OrtSession session,
      Map<String, OrtValue> inputs,
    ) async {
      checkCancelled();
      final result = await session.run(inputs);
      owned.addAll(result.values);
      checkCancelled();
      return result;
    }

    Future<void> dispose(OrtValue value) async {
      owned.remove(value);
      await value.dispose();
    }

    try {
      if (!_initialized) await initialize();

      final voiceStyle = await _loadVoiceStyle(voiceId);
      final tokens = _tokenizer.encode(text);

      // --- Step 1: Text Encoding ---
      final textEncoderInputs = <String, OrtValue>{};
      final teInputNames = _textEncoder!.inputNames;

      if (teInputNames.contains("text_ids")) {
        textEncoderInputs["text_ids"] = await value(tokens, [1, tokens.length]);
      } else {
        textEncoderInputs["input"] = await value(tokens, [1, tokens.length]);
      }

      final styleKey = teInputNames.contains("style_ttl")
          ? "style_ttl"
          : "style";
      textEncoderInputs[styleKey] = await value(
        voiceStyle.styleTtlData,
        voiceStyle.styleTtlShape,
      );

      if (teInputNames.contains("text_mask")) {
        final mask = Float32List.fromList(List.filled(tokens.length, 1.0));
        textEncoderInputs["text_mask"] = await value(mask, [
          1,
          1,
          tokens.length,
        ]);
      }

      final textEncoderOutputs = await run(_textEncoder!, textEncoderInputs);
      final teOutputName = textEncoderOutputs.containsKey("output")
          ? "output"
          : (textEncoderOutputs.containsKey("text_emb")
                ? "text_emb"
                : textEncoderOutputs.keys.first);

      final encodedTensor = textEncoderOutputs[teOutputName]!;
      final encodedVec = Float32List.fromList(
        (await encodedTensor.asFlattenedList()).cast<double>(),
      );
      final encodedShape = encodedTensor.shape;

      // --- Step 2: Duration Prediction ---
      final dpInputs = <String, OrtValue>{};
      final dpInputNames = _durationPredictor!.inputNames;

      if (dpInputNames.contains("text_ids")) {
        dpInputs["text_ids"] = await value(tokens, [1, tokens.length]);
      } else if (dpInputNames.contains("encoded")) {
        dpInputs["encoded"] = await value(encodedVec, encodedShape);
      }

      final dpStyleKey = dpInputNames.contains("style_dp")
          ? "style_dp"
          : "style";
      dpInputs[dpStyleKey] = await value(
        voiceStyle.styleDpData,
        voiceStyle.styleDpShape,
      );

      if (dpInputNames.contains("text_mask")) {
        final mask = Float32List.fromList(List.filled(tokens.length, 1.0));
        dpInputs["text_mask"] = await value(mask, [1, 1, tokens.length]);
      }

      final dpOutputs = await run(_durationPredictor!, dpInputs);
      final dpOutputName = dpOutputs.containsKey("durations")
          ? "durations"
          : (dpOutputs.containsKey("output") ? "output" : dpOutputs.keys.first);

      final durationTensor = dpOutputs[dpOutputName]!;
      final durationFloats = (await durationTensor.asFlattenedList())
          .cast<double>();

      // Compute total mel frames
      int melFrames = 0;
      for (var d in durationFloats) {
        melFrames += d.ceil().clamp(0, 1000).toInt();
      }

      // Dispose Step 1 & 2 resources
      for (var v in textEncoderInputs.values) {
        await dispose(v);
      }
      for (var v in textEncoderOutputs.values) {
        await dispose(v);
      }
      for (var v in dpInputs.values) {
        await dispose(v);
      }
      for (var v in dpOutputs.values) {
        await dispose(v);
      }

      if (melFrames <= 0) {
        throw Exception("Duration predictor returned zero mel frames");
      }

      // --- Step 3: Vector Estimation ---
      int nMels = 144;

      final latentShape = [1, nMels, melFrames];
      final latentSize = nMels * melFrames;

      final random = Random();
      var currentLatent = Float32List.fromList(
        List.generate(latentSize, (_) => _nextGaussian(random)),
      );

      final veInputNames = _vectorEstimator!.inputNames;

      for (var step = 0; step < steps; step++) {
        final veInputs = <String, OrtValue>{};

        final latentKey = veInputNames.contains("noisy_latent")
            ? "noisy_latent"
            : (veInputNames.contains("encoded")
                  ? "encoded"
                  : (veInputNames.contains("input") ? "input" : "input"));
        veInputs[latentKey] = await value(currentLatent, latentShape);

        if (veInputNames.contains("text_emb")) {
          veInputs["text_emb"] = await value(encodedVec, encodedShape);
        }

        final veStyleKey = veInputNames.contains("style_ttl")
            ? "style_ttl"
            : "style";
        veInputs[veStyleKey] = await value(
          voiceStyle.styleTtlData,
          voiceStyle.styleTtlShape,
        );

        if (veInputNames.contains("text_mask")) {
          final mask = Float32List.fromList(List.filled(tokens.length, 1.0));
          veInputs["text_mask"] = await value(mask, [1, 1, tokens.length]);
        }
        if (veInputNames.contains("latent_mask")) {
          final mask = Float32List.fromList(List.filled(melFrames, 1.0));
          veInputs["latent_mask"] = await value(mask, [1, 1, melFrames]);
        }
        if (veInputNames.contains("current_step")) {
          veInputs["current_step"] = await value(
            Float32List.fromList([step.toDouble()]),
            [1],
          );
        }
        if (veInputNames.contains("total_step")) {
          veInputs["total_step"] = await value(
            Float32List.fromList([steps.toDouble()]),
            [1],
          );
        }
        if (veInputNames.contains("steps")) {
          veInputs["steps"] = await value(
            Float32List.fromList([steps.toDouble()]),
            [1],
          );
        }

        final veOutputs = await run(_vectorEstimator!, veInputs);
        final veOutputName = veOutputs.containsKey("output")
            ? "output"
            : veOutputs.keys.first;
        final estTensor = veOutputs[veOutputName]!;
        currentLatent = Float32List.fromList(
          (await estTensor.asFlattenedList()).cast<double>(),
        );

        // Clean up step resources
        for (var v in veInputs.values) {
          await dispose(v);
        }
        for (var v in veOutputs.values) {
          await dispose(v);
        }
      }

      // --- Step 4: Vocoder ---
      final vocInputs = <String, OrtValue>{};
      final vocInputNames = _vocoder!.inputNames;
      final vocInputName = vocInputNames.contains("spectrogram")
          ? "spectrogram"
          : (vocInputNames.contains("mel")
                ? "mel"
                : (vocInputNames.contains("latent") ? "latent" : "input"));

      vocInputs[vocInputName] = await value(currentLatent, latentShape);

      final vocOutputs = await run(_vocoder!, vocInputs);
      final vocOutputName = vocOutputs.containsKey("audio")
          ? "audio"
          : (vocOutputs.containsKey("output")
                ? "output"
                : vocOutputs.keys.first);

      final audioTensor = vocOutputs[vocOutputName]!;
      final audioFloats = (await audioTensor.asFlattenedList()).cast<double>();

      // Peak Normalization
      double maxAmp = 0.0;
      for (var a in audioFloats) {
        if (a.abs() > maxAmp) maxAmp = a.abs();
      }

      final scale = maxAmp > 1.0 ? 1.0 / maxAmp : 1.0;

      // Convert to PCM16
      final pcm = Int16List(audioFloats.length);
      for (var i = 0; i < audioFloats.length; i++) {
        pcm[i] = (audioFloats[i] * scale * 32767).toInt().clamp(-32768, 32767);
      }

      // Final clean up
      for (var v in vocInputs.values) {
        await dispose(v);
      }
      for (var v in vocOutputs.values) {
        await dispose(v);
      }

      return pcm.buffer.asUint8List();
    } finally {
      for (final value in owned) {
        try {
          await value.dispose();
        } catch (_) {}
      }
    }
  }

  double _nextGaussian(Random r) {
    var u = 0.0, v = 0.0, s = 0.0;
    do {
      u = r.nextDouble() * 2 - 1;
      v = r.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1 || s == 0);
    var multiplier = sqrt(-2 * log(s) / s);
    return u * multiplier;
  }

  Future<VoiceStyle> _loadVoiceStyle(String voiceId) async {
    if (_voiceCache.containsKey(voiceId)) return _voiceCache[voiceId]!;

    final file = File('$voicesDir/$voiceId.json');
    if (!await file.exists()) {
      throw Exception("Voice style file not found: ${file.path}");
    }

    final json = jsonDecode(await file.readAsString());
    final ttlObj = json['style_ttl'];
    final dpObj = json['style_dp'];

    final ttlDims = List<int>.from(ttlObj['dims']);
    final dpDims = List<int>.from(dpObj['dims']);

    final ttlData = Float32List.fromList(_flattenJsonArray(ttlObj['data']));
    final dpData = Float32List.fromList(_flattenJsonArray(dpObj['data']));

    final style = VoiceStyle(
      styleTtlData: ttlData,
      styleTtlShape: ttlDims,
      styleDpData: dpData,
      styleDpShape: dpDims,
    );
    _voiceCache[voiceId] = style;
    return style;
  }

  List<double> _flattenJsonArray(dynamic jsonArray) {
    final result = <double>[];
    void extract(dynamic item) {
      if (item is List) {
        for (var sub in item) {
          extract(sub);
        }
      } else if (item is num) {
        result.add(item.toDouble());
      }
    }

    extract(jsonArray);
    return result;
  }

  Future<void> close() async {
    final sessions = [
      _durationPredictor,
      _textEncoder,
      _vectorEstimator,
      _vocoder,
    ];
    _durationPredictor = null;
    _textEncoder = null;
    _vectorEstimator = null;
    _vocoder = null;
    _initialized = false;
    _voiceCache.clear();
    for (final session in sessions) {
      try {
        await session?.close();
      } catch (_) {}
    }
  }
}

class VoiceStyle {
  final Float32List styleTtlData;
  final List<int> styleTtlShape;
  final Float32List styleDpData;
  final List<int> styleDpShape;

  VoiceStyle({
    required this.styleTtlData,
    required this.styleTtlShape,
    required this.styleDpData,
    required this.styleDpShape,
  });
}
