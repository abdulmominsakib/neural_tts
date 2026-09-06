package com.localmind.neural_tts.onnx

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class KokoroSession(
    private val modelPath: String,
    private val tokenizerPath: String,
    private val voicesDir: String,
    private val dictPath: String?
) {
    private var session: OrtSession? = null
    private var initialized = false
    private var closed = false
    private var vocab: Map<String, Int> = emptyMap()
    private val voiceCache = mutableMapOf<String, Array<FloatArray>>()

    @Synchronized
    fun initialize(): Boolean {
        if (closed) throw IllegalStateException("Session is closed")
        if (initialized) return true
        loadTokenizer()
        session = OnnxRuntimeHolder.createSession(modelPath)
        initialized = true
        return true
    }

    private fun loadTokenizer() {
        val file = File(tokenizerPath)
        if (!file.exists()) return
        val json = JSONObject(file.readText())
        val model = json.optJSONObject("model") ?: return
        val vocabObj = model.optJSONObject("vocab") ?: return
        val map = mutableMapOf<String, Int>()
        val keys = vocabObj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = vocabObj.getInt(key)
        }
        vocab = map
    }

    private fun encode(text: String): LongArray {
        val result = mutableListOf<Long>()
        result.add(0L) // PAD at start
        for (char in text) {
            val id = vocab[char.toString()]
            if (id != null) {
                result.add(id.toLong())
            }
        }
        result.add(0L) // PAD at end
        return result.toLongArray()
    }

    @Synchronized
    fun synthesize(text: String, voiceId: String): ByteArray {
        if (closed) throw IllegalStateException("Session is closed")
        if (!initialized) initialize()
        if (vocab.isEmpty()) throw IllegalStateException("Tokenizer not initialized")

        val ortSession = session ?: throw IllegalStateException("Session not initialized")
        val env = OnnxRuntimeHolder.getEnvironment()

        val tokens = encode(text)
        val voiceEmbedding = loadVoiceEmbedding(voiceId)
        val tokenCount = tokens.size

        // Voice file is raw float32 with shape (-1, 1, 256).
        // Select style vector by token count, clamped to available rows.
        val numRows = voiceEmbedding.size
        val refIdx = minOf(tokenCount, numRows - 1)
        val styleRow = voiceEmbedding[refIdx] // FloatArray(256)

        val inputs = mutableMapOf<String, OnnxTensor>()
        try {
            val inputNames = ortSession.inputNames

            if (inputNames.contains("input_ids")) {
                inputs["input_ids"] = OnnxTensor.createTensor(env, arrayOf(tokens))
            }
            if (inputNames.contains("style")) {
                inputs["style"] = OnnxTensor.createTensor(env, arrayOf(styleRow))
            }
            if (inputNames.contains("speed")) {
                inputs["speed"] = OnnxTensor.createTensor(env, floatArrayOf(1.0f))
            }

            val result = ortSession.run(inputs)
            try {
                val rawOutput: OnnxTensor? =
                    result.get("audio").orElse(null) as? OnnxTensor
                        ?: result.get("output").orElse(null) as? OnnxTensor
                        ?: result.get(0) as? OnnxTensor

                val outputTensor = rawOutput
                    ?: throw IllegalStateException("No audio output tensor")
                val floatBuffer = outputTensor.floatBuffer
                val floats = FloatArray(floatBuffer.remaining())
                floatBuffer.get(floats)

                val bytes = ByteArray(floats.size * 2)
                for (i in floats.indices) {
                    val sample = (floats[i] * 32767).toInt().coerceIn(-32768, 32767)
                    bytes[i * 2] = (sample and 0xFF).toByte()
                    bytes[(i * 2) + 1] = ((sample shr 8) and 0xFF).toByte()
                }

                return bytes
            } finally {
                result.close()
            }
        } finally {
            inputs.values.forEach { try { it.close() } catch (_: Exception) {} }
        }
    }

    private fun loadVoiceEmbedding(voiceId: String): Array<FloatArray> {
        voiceCache[voiceId]?.let { return it }

        val voiceFile = File(voicesDir, "$voiceId.bin")
        if (!voiceFile.exists()) {
            throw IllegalStateException("Voice file not found: ${voiceFile.absolutePath}")
        }

        val bytes = voiceFile.readBytes()
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val totalFloats = bytes.size / 4
        // Voice file shape: (-1, 1, 256) — each entry is 256 floats
        require(bytes.isNotEmpty() && bytes.size % 1024 == 0) { "Invalid voice embedding" }
        val numEntries = totalFloats / 256
        val matrix = Array(numEntries) { FloatArray(256) { buf.float } }
        voiceCache[voiceId] = matrix
        return matrix
    }

    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        try {
            session?.close()
        } catch (_: Exception) {}
        session = null
        initialized = false
        voiceCache.clear()
    }
}
