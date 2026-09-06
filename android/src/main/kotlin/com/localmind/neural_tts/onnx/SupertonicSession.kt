package com.localmind.neural_tts.onnx

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import com.localmind.neural_tts.phonemizer.Tokenizer
import org.json.JSONObject
import java.io.File

class SupertonicSession(
    private val durationPredictorPath: String,
    private val textEncoderPath: String,
    private val vectorEstimatorPath: String,
    private val vocoderPath: String,
    private val unicodeIndexerPath: String,
    private val voicesDir: String
) {
    private var durationPredictor: OrtSession? = null
    private var textEncoder: OrtSession? = null
    private var vectorEstimator: OrtSession? = null
    private var vocoder: OrtSession? = null
    private var initialized = false
    private var closed = false
    private val tokenizer = Tokenizer(unicodeIndexerPath)
    private val voiceCache = mutableMapOf<String, VoiceStyle>()

    data class VoiceStyle(
        val styleTtlData: FloatArray, val styleTtlShape: LongArray,
        val styleDpData: FloatArray, val styleDpShape: LongArray
    )

    private fun flattenJsonArray(jsonArray: org.json.JSONArray): FloatArray {
        val list = mutableListOf<Float>()
        fun extract(arr: org.json.JSONArray) {
            for (i in 0 until arr.length()) {
                val item = arr.get(i)
                if (item is org.json.JSONArray) {
                    extract(item)
                } else if (item is Number) {
                    list.add(item.toFloat())
                }
            }
        }
        extract(jsonArray)
        return list.toFloatArray()
    }

    @Synchronized
    fun initialize(): Boolean {
        if (closed) throw IllegalStateException("Session is closed")
        if (initialized) return true
        try {
            durationPredictor = OnnxRuntimeHolder.createSession(durationPredictorPath)
            textEncoder = OnnxRuntimeHolder.createSession(textEncoderPath)
            vectorEstimator = OnnxRuntimeHolder.createSession(vectorEstimatorPath)
            vocoder = OnnxRuntimeHolder.createSession(vocoderPath)
        } catch (error: Exception) {
            close()
            throw error
        }
        initialized = true
        return true
    }

    @Synchronized
    fun synthesize(text: String, voiceId: String, language: String, steps: Int): ByteArray {
        if (closed) throw IllegalStateException("Session is closed")
        if (!initialized) initialize()
        tokenizer.initialize()

        val env = OnnxRuntimeHolder.getEnvironment()
        val voiceStyle = loadVoiceStyle(voiceId)
        val tokens = tokenizer.encode(text)

        val inputNames = textEncoder?.inputNames ?: emptySet()
        val dpInputNames = durationPredictor?.inputNames ?: emptySet()
        val veInputNames = vectorEstimator?.inputNames ?: emptySet()
        val vocInputNames = vocoder?.inputNames ?: emptySet()

        android.util.Log.d("NeuralTtsPlugin", "TextEncoder InputNames: $inputNames")
        android.util.Log.d("NeuralTtsPlugin", "DurationPredictor InputNames: $dpInputNames")
        android.util.Log.d("NeuralTtsPlugin", "VectorEstimator InputNames: $veInputNames")
        android.util.Log.d("NeuralTtsPlugin", "Vocoder InputNames: $vocInputNames")
        android.util.Log.d("NeuralTtsPlugin", "Token count: ${tokens.size}")

        // --- Step 1: Text Encoding ---
        val (encodedVec, encodedShape) = runTextEncoder(env, tokens, voiceStyle, inputNames)

        // --- Step 2: Duration Prediction ---
        val melFrames = runDurationPredictor(env, tokens, voiceStyle, encodedVec, encodedShape, dpInputNames)

        if (melFrames <= 0) {
            throw RuntimeException("Duration predictor returned zero mel frames")
        }

        // --- Step 3: Vector Estimation (denoising loop) ---
        val (currentLatent, latentShape) = runVectorEstimator(env, voiceStyle, encodedVec, encodedShape, veInputNames, steps, melFrames, tokens.size)

        // --- Step 4: Vocoder ---
        val floats = runVocoder(env, currentLatent, latentShape, vocInputNames)

        val bytes = ByteArray(floats.size * 2)
        for (i in floats.indices) {
            val sample = (floats[i] * 32767).toInt().coerceIn(-32768, 32767)
            bytes[i * 2] = (sample and 0xFF).toByte()
            bytes[(i * 2) + 1] = ((sample shr 8) and 0xFF).toByte()
        }
        return bytes
    }

    private fun runTextEncoder(
        env: ai.onnxruntime.OrtEnvironment,
        tokens: LongArray,
        voiceStyle: VoiceStyle,
        inputNames: Set<String>
    ): Pair<FloatArray, LongArray> {
        val inputs = mutableMapOf<String, OnnxTensor>()
        val enc = textEncoder ?: throw IllegalStateException("Text encoder not initialized")
        try {
            if (inputNames.contains("text_ids")) {
                inputs["text_ids"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            } else {
                inputs["input"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            }
            if (inputNames.contains("style_ttl")) {
                val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleTtlData)
                inputs["style_ttl"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleTtlShape)
            } else if (inputNames.contains("style")) {
                val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleTtlData)
                inputs["style"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleTtlShape)
            }
            if (inputNames.contains("text_mask")) {
                val mask = FloatArray(tokens.size) { 1.0f }
                inputs["text_mask"] = OnnxTensor.createTensor(env, arrayOf(arrayOf(mask)))
            }

            val encodedResult = enc.run(inputs)
            try {
                for (entry in encodedResult) {
                    val tensor = entry.value as? OnnxTensor
                    android.util.Log.d("NeuralTtsPlugin", "TextEncoder output '${entry.key}' shape: ${tensor?.info?.shape?.toList()}")
                }

                val encodedValue = encodedResult.find { it.key == "output" || it.key == "text_emb" }?.value
                                   ?: encodedResult.iterator().next().value
                val encodedTensor = encodedValue as OnnxTensor
                val encodedShape = encodedTensor.info.shape
                val encodedBuffer = encodedTensor.floatBuffer
                val encodedVec = FloatArray(encodedBuffer.remaining())
                encodedBuffer.get(encodedVec)
                android.util.Log.d("NeuralTtsPlugin", "Encoded shape: ${encodedShape.toList()}, data size: ${encodedVec.size}")
                return Pair(encodedVec, encodedShape)
            } finally {
                encodedResult.close()
            }
        } finally {
            inputs.values.forEach { try { it.close() } catch (_: Exception) {} }
        }
    }

    private fun runDurationPredictor(
        env: ai.onnxruntime.OrtEnvironment,
        tokens: LongArray,
        voiceStyle: VoiceStyle,
        encodedVec: FloatArray,
        encodedShape: LongArray,
        dpInputNames: Set<String>
    ): Int {
        val inputs = mutableMapOf<String, OnnxTensor>()
        val dp = durationPredictor ?: throw IllegalStateException("Duration predictor not initialized")
        try {
            if (dpInputNames.contains("text_ids")) {
                inputs["text_ids"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            } else if (dpInputNames.contains("encoded")) {
                val buf = java.nio.FloatBuffer.wrap(encodedVec)
                inputs["encoded"] = OnnxTensor.createTensor(env, buf, encodedShape)
            }
            if (dpInputNames.contains("style_dp")) {
                val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleDpData)
                inputs["style_dp"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleDpShape)
            } else if (dpInputNames.contains("style")) {
                val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleDpData)
                inputs["style"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleDpShape)
            }
            if (dpInputNames.contains("text_mask")) {
                val mask = FloatArray(tokens.size) { 1.0f }
                inputs["text_mask"] = OnnxTensor.createTensor(env, arrayOf(arrayOf(mask)))
            }

            val durationResult = dp.run(inputs)
            try {
                for (entry in durationResult) {
                    val tensor = entry.value as? OnnxTensor
                    android.util.Log.d("NeuralTtsPlugin", "DurationPredictor output '${entry.key}' shape: ${tensor?.info?.shape?.toList()}")
                }

                val durationValue = durationResult.find { it.key == "durations" || it.key == "output" }?.value
                                    ?: durationResult.iterator().next().value
                val durationTensor = durationValue as OnnxTensor
                val durationShape = durationTensor.info.shape
                android.util.Log.d("NeuralTtsPlugin", "Duration tensor shape: ${durationShape.toList()}")

                val durationBuffer = durationTensor.floatBuffer
                val durationFloats = FloatArray(durationBuffer.remaining())
                durationBuffer.get(durationFloats)
                android.util.Log.d("NeuralTtsPlugin", "Raw durations (first 10): ${durationFloats.take(10)}")

                val melFrames = durationFloats.sumOf { Math.ceil(it.toDouble().coerceAtLeast(0.0)).toInt() }
                android.util.Log.d("NeuralTtsPlugin", "Computed mel frames T=$melFrames from ${durationFloats.size} durations")
                return melFrames
            } finally {
                durationResult.close()
            }
        } finally {
            inputs.values.forEach { try { it.close() } catch (_: Exception) {} }
        }
    }

    private fun runVectorEstimator(
        env: ai.onnxruntime.OrtEnvironment,
        voiceStyle: VoiceStyle,
        encodedVec: FloatArray,
        encodedShape: LongArray,
        veInputNames: Set<String>,
        steps: Int,
        melFrames: Int,
        tokenCount: Int
    ): Pair<FloatArray, LongArray> {
        val veSession = vectorEstimator ?: throw IllegalStateException("Vector estimator not initialized")
        val noisyLatentInfo = veSession.inputInfo["noisy_latent"]
        val noisyLatentExpectedShape = (noisyLatentInfo?.info as? ai.onnxruntime.TensorInfo)?.shape
        val nMels = if (noisyLatentExpectedShape != null && noisyLatentExpectedShape.size >= 2) {
            noisyLatentExpectedShape[1].toInt()
        } else {
            144
        }
        android.util.Log.d("NeuralTtsPlugin", "n_mels=$nMels (from model input info)")

        val latentShape = longArrayOf(1, nMels.toLong(), melFrames.toLong())
        val latentSize = nMels * melFrames

        val random = java.util.Random()
        var currentLatent = FloatArray(latentSize) { random.nextGaussian().toFloat() }
        android.util.Log.d("NeuralTtsPlugin", "Initial latent shape: ${latentShape.toList()}, size: $latentSize")

        val textLen = tokenCount
        val latentLen = melFrames

        for (step in 0 until steps) {
            val inputs = mutableMapOf<String, OnnxTensor>()
            try {
                if (veInputNames.contains("noisy_latent")) {
                    val buf = java.nio.FloatBuffer.wrap(currentLatent)
                    inputs["noisy_latent"] = OnnxTensor.createTensor(env, buf, latentShape)
                } else if (veInputNames.contains("encoded")) {
                    val buf = java.nio.FloatBuffer.wrap(currentLatent)
                    inputs["encoded"] = OnnxTensor.createTensor(env, buf, latentShape)
                } else if (veInputNames.contains("input")) {
                    val buf = java.nio.FloatBuffer.wrap(currentLatent)
                    inputs["input"] = OnnxTensor.createTensor(env, buf, latentShape)
                }
                if (veInputNames.contains("text_emb")) {
                    val buf = java.nio.FloatBuffer.wrap(encodedVec)
                    inputs["text_emb"] = OnnxTensor.createTensor(env, buf, encodedShape)
                }
                if (veInputNames.contains("style_ttl")) {
                    val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleTtlData)
                    inputs["style_ttl"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleTtlShape)
                } else if (veInputNames.contains("style")) {
                    val buf = java.nio.FloatBuffer.wrap(voiceStyle.styleTtlData)
                    inputs["style"] = OnnxTensor.createTensor(env, buf, voiceStyle.styleTtlShape)
                }
                if (veInputNames.contains("text_mask")) {
                    val mask = FloatArray(textLen) { 1.0f }
                    inputs["text_mask"] = OnnxTensor.createTensor(env, arrayOf(arrayOf(mask)))
                }
                if (veInputNames.contains("latent_mask")) {
                    val mask = FloatArray(latentLen) { 1.0f }
                    inputs["latent_mask"] = OnnxTensor.createTensor(env, arrayOf(arrayOf(mask)))
                }
                if (veInputNames.contains("current_step")) {
                    inputs["current_step"] = OnnxTensor.createTensor(env, floatArrayOf(step.toFloat()))
                }
                if (veInputNames.contains("total_step")) {
                    inputs["total_step"] = OnnxTensor.createTensor(env, floatArrayOf(steps.toFloat()))
                }
                if (veInputNames.contains("steps")) {
                    inputs["steps"] = OnnxTensor.createTensor(env, floatArrayOf(steps.toFloat()))
                }

                if (step == 0) {
                    for ((name, tensor) in inputs) {
                        android.util.Log.d("NeuralTtsPlugin", "VE input '$name' shape: ${tensor.info.shape.toList()}")
                    }
                }

                val estimatedResult = veSession.run(inputs)
                try {
                    if (step == 0) {
                        for (entry in estimatedResult) {
                            val tensor = entry.value as? OnnxTensor
                            android.util.Log.d("NeuralTtsPlugin", "VE output '${entry.key}' shape: ${tensor?.info?.shape?.toList()}")
                        }
                    }

                    val estValue = estimatedResult.find { it.key == "output" }?.value
                                   ?: estimatedResult.iterator().next().value
                    val estTensor = estValue as OnnxTensor
                    val estBuffer = estTensor.floatBuffer
                    currentLatent = FloatArray(estBuffer.remaining())
                    estBuffer.get(currentLatent)
                } finally {
                    estimatedResult.close()
                }
            } finally {
                inputs.values.forEach { try { it.close() } catch (_: Exception) {} }
            }
        }
        return Pair(currentLatent, latentShape)
    }

    private fun runVocoder(
        env: ai.onnxruntime.OrtEnvironment,
        currentLatent: FloatArray,
        latentShape: LongArray,
        vocInputNames: Set<String>
    ): FloatArray {
        val vocoderSession = vocoder ?: throw IllegalStateException("Vocoder not initialized")
        val vocInputInfo = vocoderSession.inputInfo
        android.util.Log.d("NeuralTtsPlugin", "Vocoder input info: ${vocInputInfo.keys}")

        val inputs = mutableMapOf<String, OnnxTensor>()
        try {
            val buf = java.nio.FloatBuffer.wrap(currentLatent)
            val vocInputName = if (vocInputNames.contains("spectrogram")) "spectrogram"
                               else if (vocInputNames.contains("mel")) "mel"
                               else if (vocInputNames.contains("latent")) "latent"
                               else "input"
            inputs[vocInputName] = OnnxTensor.createTensor(env, buf, latentShape)
            android.util.Log.d("NeuralTtsPlugin", "Vocoder input '$vocInputName' shape: ${latentShape.toList()}")
            val audioResult = vocoderSession.run(inputs)
            try {
                val audioValue = audioResult.find { it.key == "audio" || it.key == "output" }?.value
                                 ?: audioResult.iterator().next().value
                val audioTensor = audioValue as OnnxTensor
                android.util.Log.d("NeuralTtsPlugin", "Vocoder output shape: ${audioTensor.info.shape.toList()}")
                val audioBuffer = audioTensor.floatBuffer
                val floats = FloatArray(audioBuffer.remaining())
                audioBuffer.get(floats)
                return floats
            } finally {
                audioResult.close()
            }
        } finally {
            inputs.values.forEach { try { it.close() } catch (_: Exception) {} }
        }
    }

    private fun loadVoiceStyle(voiceId: String): VoiceStyle {
        voiceCache[voiceId]?.let { return it }

        val voiceFile = File(voicesDir, "$voiceId.json")
        if (!voiceFile.exists()) {
            throw IllegalStateException("Voice style file not found: ${voiceFile.absolutePath}")
        }

        val json = JSONObject(voiceFile.readText())
        val ttlObj = json.getJSONObject("style_ttl")
        val dpObj = json.getJSONObject("style_dp")

        val ttlDims = ttlObj.getJSONArray("dims")
        val dpDims = dpObj.getJSONArray("dims")
        val ttlShape = LongArray(ttlDims.length()) { ttlDims.getLong(it) }
        val dpShape = LongArray(dpDims.length()) { dpDims.getLong(it) }

        val ttlData = flattenJsonArray(ttlObj.getJSONArray("data"))
        val dpData = flattenJsonArray(dpObj.getJSONArray("data"))

        val style = VoiceStyle(ttlData, ttlShape, dpData, dpShape)
        voiceCache[voiceId] = style
        return style
    }

    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        listOf(durationPredictor, textEncoder, vectorEstimator, vocoder).forEach {
            try { it?.close() } catch (_: Exception) {}
        }
        durationPredictor = null
        textEncoder = null
        vectorEstimator = null
        vocoder = null
        initialized = false
        voiceCache.clear()
    }
}
