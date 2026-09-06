package com.localmind.neural_tts.onnx

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import com.localmind.neural_tts.phonemizer.Tokenizer
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipFile

/**
 * ONNX inference session for the Kitten TTS (StyleTTS2 nano) model.
 *
 * The model requires 3 inputs:
 *   - input_ids : [1, L]       int64  — phoneme token IDs
 *   - style     : [1, D]       float32 — per-voice style embedding row
 *   - speed     : [1]          float32 — playback speed multiplier
 *
 * Voice embeddings are stored in a `voices.npz` file (numpy zip archive).
 * Each entry `<voice_id>.npy` holds a 2-D float32 array [T, D]. For a given
 * text, the reference row index is clamped to `min(text.length, T-1)`.
 */
class KittenSession(
    private val modelPath: String,
    private val voicesNpzPath: String,
    private val dictPath: String?
) {
    private var session: OrtSession? = null
    private var initialized = false
    private var closed = false

    // vocab path for the Tokenizer is the dict file (IPA → id), NOT the npz.
    private val tokenizer = Tokenizer(dictPath)

    // Cache of loaded voice embeddings: voiceId → float32 matrix [T][D]
    private val voiceEmbeddings = mutableMapOf<String, Array<FloatArray>>()

    @Synchronized
    fun initialize(): Boolean {
        if (closed) throw IllegalStateException("Session is closed")
        if (initialized) return true
        session = OnnxRuntimeHolder.createSession(modelPath)
        initialized = true
        return true
    }

    @Synchronized
    fun synthesize(text: String, voiceId: String, speed: Float = 1.0f): ByteArray {
        if (closed) throw IllegalStateException("Session is closed")
        if (!initialized) initialize()
        tokenizer.initialize()

        val ortSession = session ?: throw IllegalStateException("Session not initialized")
        val env = OnnxRuntimeHolder.getEnvironment()

        // ── 1. Tokenise ──────────────────────────────────────────────────────
        val tokens = tokenizer.encode(text)
        val inputIds: Array<LongArray> = arrayOf(tokens)
        val owned = mutableListOf<OnnxTensor>()
        try {
            val inputIdsTensor = OnnxTensor.createTensor(env, inputIds).also { owned.add(it) }

            // ── 2. Style embedding ───────────────────────────────────────────────
            val embedMatrix = loadVoiceEmbedding(voiceId)
            val refIdx = minOf(text.length, embedMatrix.size - 1)
            val styleRow: Array<FloatArray> = arrayOf(embedMatrix[refIdx])
            val styleTensor = OnnxTensor.createTensor(env, styleRow).also { owned.add(it) }

            // ── 3. Speed ─────────────────────────────────────────────────────────
            val speedTensor = OnnxTensor.createTensor(env, floatArrayOf(speed)).also { owned.add(it) }

            // ── 4. Run inference ─────────────────────────────────────────────────
            val inputs = mutableMapOf(
                "input_ids" to inputIdsTensor,
                "style"     to styleTensor,
                "speed"     to speedTensor,
            )
            val result = ortSession.run(inputs)
            try {
                // Try getting output by name, falling back to index 0 if names don't match.
                val rawOutput: OnnxTensor? =
                    result.get("audio").orElse(null) as? OnnxTensor
                        ?: result.get("output").orElse(null) as? OnnxTensor
                        ?: result.get(0) as? OnnxTensor

                val outputTensor = rawOutput
                    ?: throw IllegalStateException("No audio output tensor found in model output")

                val floatBuffer = outputTensor.floatBuffer
                val floats = FloatArray(floatBuffer.remaining())
                floatBuffer.get(floats)

                // Trim trailing ~5 000 samples (silence artifact, matches Python impl)
                val trimmed = if (floats.size > 5000) floats.copyOf(floats.size - 5000) else floats

                // Convert float32 [-1,1] → PCM int16 LE
                val pcm = FloatToPcm16(trimmed)
                return prependWavHeader(pcm, sampleRate = 24000)
            } finally {
                result.close()
            }
        } finally {
            owned.forEach { try { it.close() } catch (_: Exception) {} }
        }
    }

    // ── Voice embedding loader (NPZ / NPY parser) ──────────────────────────

    private fun loadVoiceEmbedding(voiceId: String): Array<FloatArray> {
        voiceEmbeddings[voiceId]?.let { return it }

        val npzFile = File(voicesNpzPath)
        if (!npzFile.exists()) throw IllegalStateException("voices.npz not found: $voicesNpzPath")

        ZipFile(npzFile).use { zip ->
            // NPZ entries are named "<voiceId>.npy"
            val entryName = "$voiceId.npy"
            val entry = zip.getEntry(entryName)
                ?: throw IllegalStateException("Voice '$voiceId' not found in $voicesNpzPath")

            val matrix = zip.getInputStream(entry).use { stream ->
                parseNpy2DFloat(stream)
            }
            voiceEmbeddings[voiceId] = matrix
            return matrix
        }
    }

    /**
     * Parse a 2-D float32 NPY v1.0 stream.
     *
     * NPY format:
     *   - 6-byte magic  : \x93NUMPY
     *   - 1-byte major  : 0x01 (v1) or 0x02 (v2)
     *   - 1-byte minor
     *   - 2-byte HEADER_LEN (LE for v1) or 4-byte (v2)
     *   - HEADER_LEN bytes of ASCII dict: e.g. {'descr': '<f4', 'fortran_order': False, 'shape': (T, D), }
     *   - raw data in C order
     */
    private fun parseNpy2DFloat(stream: InputStream): Array<FloatArray> {
        val magic = stream.readNBytes(6)
        check(magic[0] == 0x93.toByte() && String(magic, 1, 5) == "NUMPY") {
            "Not a valid NPY file"
        }
        val major = stream.read()
        stream.read() // minor

        val headerLen = if (major == 1) {
            val lo = stream.read()
            val hi = stream.read()
            lo or (hi shl 8)
        } else {
            // v2: 4-byte little-endian
            val b = stream.readNBytes(4)
            ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).int
        }

        val headerBytes = stream.readNBytes(headerLen)
        val header = String(headerBytes, Charsets.US_ASCII)

        // Extract shape tuple from header dict string
        val shapeMatch = Regex("""'shape'\s*:\s*\((\d+)\s*,\s*(\d+)\s*\)""").find(header)
            ?: throw IllegalStateException("Cannot parse shape from NPY header: $header")
        val rows = shapeMatch.groupValues[1].toInt()
        val cols = shapeMatch.groupValues[2].toInt()

        // Check byte order: '<f4' = little-endian float32
        val isFortran = header.contains("'fortran_order': True")
        check(!isFortran) { "Fortran-order NPY arrays are not supported" }

        val dataBytes = stream.readNBytes(rows * cols * 4)
        val buf = ByteBuffer.wrap(dataBytes).order(ByteOrder.LITTLE_ENDIAN)
        val result = Array(rows) { FloatArray(cols) { buf.float } }
        return result
    }

    // ── Audio helpers ──────────────────────────────────────────────────────

    private fun FloatToPcm16(floats: FloatArray): ByteArray {
        val out = ByteArray(floats.size * 2)
        for (i in floats.indices) {
            val s = (floats[i] * 32767f).toInt().coerceIn(-32768, 32767)
            out[i * 2]     = (s and 0xFF).toByte()
            out[i * 2 + 1] = ((s shr 8) and 0xFF).toByte()
        }
        return out
    }

    private fun prependWavHeader(pcmData: ByteArray, sampleRate: Int): ByteArray {
        val header = ByteArray(44)
        val totalDataLen = pcmData.size + 36
        val byteRate = sampleRate * 2  // 16-bit mono

        val buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray())
        buf.putInt(totalDataLen)
        buf.put("WAVE".toByteArray())
        buf.put("fmt ".toByteArray())
        buf.putInt(16)
        buf.putShort(1)      // PCM
        buf.putShort(1)      // Mono
        buf.putInt(sampleRate)
        buf.putInt(byteRate)
        buf.putShort(2)      // Block align
        buf.putShort(16)     // Bits per sample
        buf.put("data".toByteArray())
        buf.putInt(pcmData.size)

        val result = ByteArray(header.size + pcmData.size)
        System.arraycopy(header, 0, result, 0, header.size)
        System.arraycopy(pcmData, 0, result, header.size, pcmData.size)
        return result
    }

    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        try { session?.close() } catch (_: Exception) {}
        session = null
        initialized = false
        voiceEmbeddings.clear()
    }
}
