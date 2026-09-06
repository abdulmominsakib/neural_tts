package com.localmind.neural_tts.engines

import com.localmind.neural_tts.onnx.SupertonicSession
import java.io.File

class SupertonicEngine : BaseEngine {
    private var session: SupertonicSession? = null
    private val player = com.localmind.neural_tts.audio.PcmPlayer()
    override fun beginOperation() = player.begin()
    private var maxChunkSize: Int = 200
    private var inferenceSteps: Int = 5

    override fun initialize(args: Map<*, *>) {
        val durationPredictorPath = args["durationPredictorPath"] as? String
            ?: throw IllegalArgumentException("durationPredictorPath required")
        val textEncoderPath = args["textEncoderPath"] as? String
            ?: throw IllegalArgumentException("textEncoderPath required")
        val vectorEstimatorPath = args["vectorEstimatorPath"] as? String
            ?: throw IllegalArgumentException("vectorEstimatorPath required")
        val vocoderPath = args["vocoderPath"] as? String
            ?: throw IllegalArgumentException("vocoderPath required")
        val unicodeIndexerPath = args["unicodeIndexerPath"] as? String
            ?: throw IllegalArgumentException("unicodeIndexerPath required")
        val voicesDir = args["voicesDir"] as? String
            ?: throw IllegalArgumentException("voicesDir required")
        maxChunkSize = (args["maxChunkSize"] as? Int) ?: 200

        val paths = listOf(
            durationPredictorPath, textEncoderPath, vectorEstimatorPath,
            vocoderPath, unicodeIndexerPath
        )
        for (path in paths) {
            if (!File(path).exists()) {
                throw IllegalStateException("Model file not found: $path")
            }
        }

        session = SupertonicSession(
            durationPredictorPath, textEncoderPath, vectorEstimatorPath,
            vocoderPath, unicodeIndexerPath, voicesDir
        )
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "F1"
        val language = args["language"] as? String ?: "en"
        inferenceSteps = (args["inferenceSteps"] as? Int) ?: 5
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val chunks = chunkText(text)
        for (chunk in chunks) {
            player.checkCancelled()
            val audioBytes = session?.synthesize(chunk, voiceId, language, inferenceSteps)
                ?: throw IllegalStateException("Session not initialized")
            player.play(audioBytes, 24000, rate.toFloat(), pitch.toFloat(), volume.toFloat())
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
}
