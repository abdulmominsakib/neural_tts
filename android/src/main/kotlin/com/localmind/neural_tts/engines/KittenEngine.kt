package com.localmind.neural_tts.engines

import com.localmind.neural_tts.onnx.KittenSession
import com.localmind.neural_tts.phonemizer.Phonemizer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class KittenEngine : BaseEngine {
    private var session: KittenSession? = null
    private val player = com.localmind.neural_tts.audio.PcmPlayer()
    override fun beginOperation() = player.begin()
    private var phonemizer: Phonemizer = Phonemizer()
    private var maxChunkSize: Int = 200

    override fun initialize(args: Map<*, *>) {
        val modelPath = args["modelPath"] as? String ?: throw IllegalArgumentException("modelPath required")
        val voicesPath = args["voicesPath"] as? String ?: throw IllegalArgumentException("voicesPath required")
        val dictPath = args["dictPath"] as? String
        maxChunkSize = (args["maxChunkSize"] as? Int) ?: 200
        phonemizer = Phonemizer(dictPath)

        if (!File(modelPath).exists()) {
            throw IllegalStateException("Model file not found: $modelPath")
        }
        if (!File(voicesPath).exists()) {
            throw IllegalStateException("voices.npz not found: $voicesPath — please re-download the Kitten engine")
        }

        // voicesPath should point to voices.npz (downloaded alongside the ONNX model)
        session = KittenSession(modelPath, voicesPath, dictPath)
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "expr-voice-2-f"
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false
        val phonemized = if (isPhonemized) text else phonemizer.convert(text)
        val chunks = chunkText(phonemized)

        for (chunk in chunks) {
            player.checkCancelled()
            val wavBytes = session?.synthesize(chunk, voiceId, 1.0f) ?: throw IllegalStateException("Session not initialized")
            player.play(extractAudioData(wavBytes), extractSampleRate(wavBytes), rate.toFloat(), pitch.toFloat(), volume.toFloat())
        }
    }


    override fun streamAppend(args: Map<*, *>) = speak(args)
    override fun streamFinalize(args: Map<*, *>) {}
    override fun streamCancel(args: Map<*, *>) = stop()
    override fun stop() = player.stop()
    override fun release() {
        stop()
        session?.close()
        session = null
    }

    private fun chunkText(text: String): List<String> {
        val sentences = splitSentences(text)
        val chunks = mutableListOf<String>()
        var current = StringBuilder()

        for (sentence in sentences) {
            if (current.isNotEmpty() && current.length + sentence.length > maxChunkSize) {
                chunks.add(current.toString().trim())
                current = StringBuilder()
            }
            if (current.isNotEmpty()) current.append(" ")
            current.append(sentence)
        }
        if (current.isNotEmpty()) chunks.add(current.toString().trim())
        return chunks.flatMap { it.chunked(maxChunkSize.coerceIn(1, 400)) }
    }

    private fun splitSentences(text: String): List<String> {
        return text.split(Regex("(?<=[.!?])\\s+"))
    }

    private fun extractSampleRate(wavBytes: ByteArray): Int {
        val buffer = ByteBuffer.wrap(wavBytes)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(24)
        return buffer.getInt()
    }

    private fun extractAudioData(wavBytes: ByteArray): ByteArray {
        val buffer = ByteBuffer.wrap(wavBytes)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(40)
        val dataSize = buffer.getInt()
        return wavBytes.copyOfRange(44, 44 + dataSize)
    }
}
