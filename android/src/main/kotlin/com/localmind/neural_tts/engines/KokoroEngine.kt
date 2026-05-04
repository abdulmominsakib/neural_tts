package com.localmind.neural_tts.engines

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.localmind.neural_tts.onnx.KokoroSession
import com.localmind.neural_tts.phonemizer.Phonemizer
import java.io.File

class KokoroEngine : BaseEngine {
    private var session: KokoroSession? = null
    private var audioTrack: AudioTrack? = null
    private var maxChunkSize: Int = 200
    private var phonemizer: Phonemizer = Phonemizer()

    override fun initialize(args: Map<*, *>) {
        val modelPath = args["modelPath"] as? String ?: throw IllegalArgumentException("modelPath required")
        val tokenizerPath = args["tokenizerPath"] as? String ?: throw IllegalArgumentException("tokenizerPath required")
        val voicesDir = args["voicesDir"] as? String ?: throw IllegalArgumentException("voicesDir required")
        val dictPath = args["dictPath"] as? String
        maxChunkSize = (args["maxChunkSize"] as? Int) ?: 200
        phonemizer = Phonemizer(dictPath)

        if (!File(modelPath).exists()) {
            throw IllegalStateException("Model file not found: $modelPath")
        }

        session = KokoroSession(modelPath, tokenizerPath, voicesDir, dictPath)
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "af_bella"
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val phonemized = phonemizer.convert(text)
        val chunks = chunkText(phonemized)

        for (chunk in chunks) {
            val audioBytes = session?.synthesize(chunk, voiceId)
                ?: throw IllegalStateException("Session not initialized")
            playAudio(audioBytes, rate.toFloat(), pitch.toFloat(), volume.toFloat())
        }
        waitForPlayback()
    }

    private val streamBuffer = StringBuilder()

    override fun streamAppend(args: Map<*, *>) {
        val text = args["text"] as? String ?: return
        val voiceId = args["voiceId"] as? String ?: "af_bella"

        streamBuffer.append(text)
        val content = streamBuffer.toString()
        val sentences = splitSentences(content)

        if (sentences.size > 1) {
            val complete = sentences.dropLast(1).joinToString("")
            streamBuffer.clear()
            streamBuffer.append(sentences.last())
            val phonemized = phonemizer.convert(complete)
            val audioBytes = session?.synthesize(phonemized, voiceId)
            if (audioBytes != null) playAudio(audioBytes)
        }
    }

    override fun streamFinalize(args: Map<*, *>) {
        val voiceId = args["voiceId"] as? String ?: "af_bella"
        if (streamBuffer.isNotEmpty()) {
            val text = streamBuffer.toString()
            streamBuffer.clear()
            val phonemized = phonemizer.convert(text)
            val audioBytes = session?.synthesize(phonemized, voiceId)
            if (audioBytes != null) playAudio(audioBytes)
        }
        waitForPlayback()
    }

    override fun streamCancel(args: Map<*, *>) {
        streamBuffer.clear()
        stop()
    }

    override fun stop() {
        try { audioTrack?.stop() } catch (_: Exception) {}
        try { audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
    }

    override fun release() {
        stop()
        session?.close()
        session = null
    }

    private fun playAudio(audioBytes: ByteArray, rate: Float = 1.0f, pitch: Float = 1.0f, volume: Float = 1.0f) {
        val sampleRate = 24000
        stop()

        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBufferSize, audioBytes.size))
            .build()

        audioTrack?.setVolume(volume)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            audioTrack?.playbackParams = audioTrack?.playbackParams?.setSpeed(rate)?.setPitch(pitch) ?: android.media.PlaybackParams().setSpeed(rate).setPitch(pitch)
        }

        audioTrack?.write(audioBytes, 0, audioBytes.size)
        audioTrack?.play()
    }

    private fun waitForPlayback() {
        val track = audioTrack
        if (track != null && track.playState == AudioTrack.PLAYSTATE_PLAYING) {
            while (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                Thread.sleep(50)
            }
        }
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
        return chunks
    }

    private fun splitSentences(text: String): List<String> {
        return text.split(Regex("(?<=[.!?])\\s+"))
    }
}
