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

    data class VoiceStyle(val styleTtl: Array<FloatArray>, val styleDp: Array<FloatArray>)

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

        // Text encoding
        val encodedResult = textEncoder?.let { enc ->
            val inputs = mutableMapOf<String, OnnxTensor>()
            if (inputNames.contains("text_ids")) {
                inputs["text_ids"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            } else {
                inputs["input"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            }
            if (inputNames.contains("style_ttl")) {
                inputs["style_ttl"] = OnnxTensor.createTensor(env, voiceStyle.styleTtl)
            } else if (inputNames.contains("style")) {
                inputs["style"] = OnnxTensor.createTensor(env, voiceStyle.styleTtl)
            }
            enc.run(inputs)
        } ?: throw IllegalStateException("Text encoder not initialized")

        val encodedTensor = (encodedResult.get("output") ?: encodedResult.get("text_emb")
            ?: throw IllegalStateException("No text encoder output")) as OnnxTensor
        val encodedBuffer = encodedTensor.floatBuffer
        val encodedVec = FloatArray(encodedBuffer.remaining())
        encodedBuffer.get(encodedVec)
        encodedResult.close()

        // Duration prediction
        val durationResult = durationPredictor?.let { dp ->
            val inputs = mutableMapOf<String, OnnxTensor>()
            if (dpInputNames.contains("text_ids")) {
                inputs["text_ids"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            } else if (dpInputNames.contains("encoded")) {
                inputs["encoded"] = OnnxTensor.createTensor(env, encodedVec)
            }
            if (dpInputNames.contains("style_dp")) {
                inputs["style_dp"] = OnnxTensor.createTensor(env, voiceStyle.styleDp)
            } else if (dpInputNames.contains("style")) {
                inputs["style"] = OnnxTensor.createTensor(env, voiceStyle.styleDp)
            }
            dp.run(inputs)
        } ?: throw IllegalStateException("Duration predictor not initialized")
        durationResult.close()

        // Vector estimation (denoising loop)
        var currentLatent = encodedVec
        for (step in 0 until steps) {
            val estimatedResult = vectorEstimator?.let { ve ->
                val inputs = mutableMapOf<String, OnnxTensor>()
                if (veInputNames.contains("noisy_latent")) {
                    inputs["noisy_latent"] = OnnxTensor.createTensor(env, currentLatent)
                } else if (veInputNames.contains("encoded")) {
                    inputs["encoded"] = OnnxTensor.createTensor(env, currentLatent)
                } else if (veInputNames.contains("input")) {
                    inputs["input"] = OnnxTensor.createTensor(env, currentLatent)
                }
                if (veInputNames.contains("text_emb")) {
                    inputs["text_emb"] = OnnxTensor.createTensor(env, encodedVec)
                }
                if (veInputNames.contains("style_ttl")) {
                    inputs["style_ttl"] = OnnxTensor.createTensor(env, voiceStyle.styleTtl)
                } else if (veInputNames.contains("style")) {
                    inputs["style"] = OnnxTensor.createTensor(env, voiceStyle.styleTtl)
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

            val estTensor = (estimatedResult.get("output") ?: estimatedResult.get(0)
                ?: throw IllegalStateException("No vector estimator output")) as OnnxTensor
            val estBuffer = estTensor.floatBuffer
            currentLatent = FloatArray(estBuffer.remaining())
            estBuffer.get(currentLatent)
            estimatedResult.close()
        }

        // Vocoder
        val audioResult = vocoder?.let { v ->
            val inputs = mutableMapOf<String, OnnxTensor>()
            inputs["input"] = OnnxTensor.createTensor(env, currentLatent)
            v.run(inputs)
        } ?: throw IllegalStateException("Vocoder not initialized")

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
        val ttlData = ttlObj.getJSONArray("data")
        val dpData = dpObj.getJSONArray("data")

        val ttlFloats = FloatArray(ttlData.length()) { ttlData.getDouble(it).toFloat() }
        val dpFloats = FloatArray(dpData.length()) { dpData.getDouble(it).toFloat() }

        // Reshape to match expected tensor shape
        val styleTtl = arrayOf(ttlFloats)
        val styleDp = arrayOf(dpFloats)

        val style = VoiceStyle(styleTtl, styleDp)
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
