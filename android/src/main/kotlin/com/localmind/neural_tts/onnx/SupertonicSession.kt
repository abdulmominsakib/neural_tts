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

    fun initialize(): Boolean {
        if (initialized) return true
        durationPredictor = OnnxRuntimeHolder.createSession(durationPredictorPath)
        textEncoder = OnnxRuntimeHolder.createSession(textEncoderPath)
        vectorEstimator = OnnxRuntimeHolder.createSession(vectorEstimatorPath)
        vocoder = OnnxRuntimeHolder.createSession(vocoderPath)
        initialized = true
        return true
    }

    fun synthesize(text: String, voiceId: String, language: String, steps: Int): ByteArray {
        if (!initialized) initialize()
        tokenizer.initialize()

        val env = OnnxRuntimeHolder.getEnvironment()
        val voiceStyle = loadVoiceStyle(voiceId)
        val tokens = tokenizer.encode(text)

        val inputNames = textEncoder?.inputNames ?: emptySet()
        val dpInputNames = durationPredictor?.inputNames ?: emptySet()
        val veInputNames = vectorEstimator?.inputNames ?: emptySet()

        android.util.Log.d("NeuralTtsPlugin", "TextEncoder InputNames: $inputNames")
        android.util.Log.d("NeuralTtsPlugin", "DurationPredictor InputNames: $dpInputNames")
        android.util.Log.d("NeuralTtsPlugin", "VectorEstimator InputNames: $veInputNames")

        // Text encoding
        val encodedResult = try {
            textEncoder?.let { enc ->
                val inputs = mutableMapOf<String, OnnxTensor>()
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
                    val mask = LongArray(tokens.size) { 1L }
                    inputs["text_mask"] = OnnxTensor.createTensor(env, arrayOf(mask))
                }
                enc.run(inputs)
            } ?: throw IllegalStateException("Text encoder not initialized")
        } catch (e: Exception) {
            throw RuntimeException("Error in Text Encoding: ${e.message}", e)
        }

        val encodedTensor = (encodedResult.get("output") ?: encodedResult.get("text_emb")
            ?: throw IllegalStateException("No text encoder output")) as OnnxTensor
        val encodedShape = encodedTensor.info.shape
        val encodedBuffer = encodedTensor.floatBuffer
        val encodedVec = FloatArray(encodedBuffer.remaining())
        encodedBuffer.get(encodedVec)
        encodedResult.close()

        // Duration prediction
        val durationResult = try {
            durationPredictor?.let { dp ->
                val inputs = mutableMapOf<String, OnnxTensor>()
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
                    val mask = LongArray(tokens.size) { 1L }
                    inputs["text_mask"] = OnnxTensor.createTensor(env, arrayOf(mask))
                }
                dp.run(inputs)
            } ?: throw IllegalStateException("Duration predictor not initialized")
        } catch (e: Exception) {
            throw RuntimeException("Error in Duration Predictor: ${e.message}", e)
        }
        durationResult.close()

        // Vector estimation (denoising loop)
        var currentLatent = encodedVec
        for (step in 0 until steps) {
            val estimatedResult = try {
                vectorEstimator?.let { ve ->
                    val inputs = mutableMapOf<String, OnnxTensor>()
                    if (veInputNames.contains("noisy_latent")) {
                        val buf = java.nio.FloatBuffer.wrap(currentLatent)
                        inputs["noisy_latent"] = OnnxTensor.createTensor(env, buf, encodedShape)
                    } else if (veInputNames.contains("encoded")) {
                        val buf = java.nio.FloatBuffer.wrap(currentLatent)
                        inputs["encoded"] = OnnxTensor.createTensor(env, buf, encodedShape)
                    } else if (veInputNames.contains("input")) {
                        val buf = java.nio.FloatBuffer.wrap(currentLatent)
                        inputs["input"] = OnnxTensor.createTensor(env, buf, encodedShape)
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
                    if (veInputNames.contains("current_step")) {
                        inputs["current_step"] = OnnxTensor.createTensor(env, intArrayOf(step))
                    }
                    if (veInputNames.contains("total_step")) {
                        inputs["total_step"] = OnnxTensor.createTensor(env, intArrayOf(steps))
                    }
                    if (veInputNames.contains("steps")) {
                        inputs["steps"] = OnnxTensor.createTensor(env, intArrayOf(steps))
                    }
                    ve.run(inputs)
                } ?: throw IllegalStateException("Vector estimator not initialized")
            } catch (e: Exception) {
                throw RuntimeException("Error in Vector Estimator step $step: ${e.message}", e)
            }

            val estTensor = (estimatedResult.get("output") ?: estimatedResult.get(0)
                ?: throw IllegalStateException("No vector estimator output")) as OnnxTensor
            val estBuffer = estTensor.floatBuffer
            currentLatent = FloatArray(estBuffer.remaining())
            estBuffer.get(currentLatent)
            estimatedResult.close()
        }

        // Vocoder
        val audioResult = try {
            vocoder?.let { v ->
                val inputs = mutableMapOf<String, OnnxTensor>()
                val buf = java.nio.FloatBuffer.wrap(currentLatent)
                inputs["input"] = OnnxTensor.createTensor(env, buf, encodedShape)
                v.run(inputs)
            } ?: throw IllegalStateException("Vocoder not initialized")
        } catch (e: Exception) {
            throw RuntimeException("Error in Vocoder: ${e.message}", e)
        }

        val audioTensor = (audioResult.get("audio") ?: audioResult.get("output")
            ?: audioResult.get(0)
            ?: throw IllegalStateException("No audio output")) as OnnxTensor
        val audioBuffer = audioTensor.floatBuffer
        val floats = FloatArray(audioBuffer.remaining())
        audioBuffer.get(floats)
        audioResult.close()

        val bytes = ByteArray(floats.size * 2)
        for (i in floats.indices) {
            val sample = (floats[i] * 32767).toInt().coerceIn(-32768, 32767)
            bytes[i * 2] = (sample and 0xFF).toByte()
            bytes[(i * 2) + 1] = ((sample shr 8) and 0xFF).toByte()
        }
        return bytes
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

    fun close() {
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
