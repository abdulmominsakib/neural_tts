package com.localmind.neural_tts.engines

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.localmind.neural_tts.onnx.KittenSession
import com.localmind.neural_tts.phonemizer.Phonemizer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class KittenEngine : BaseEngine {
    private var session: KittenSession? = null
    private var audioTrack: AudioTrack? = null
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
        val language = args["language"] as? String ?: "en"
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val phonemized = phonemizer.convert(text)
        val chunks = chunkText(phonemized)

        for (chunk in chunks) {
            val wavBytes = session?.synthesize(chunk, voiceId, rate.toFloat()) ?: throw IllegalStateException("Session not initialized")
            playWavBytes(wavBytes, rate.toFloat(), pitch.toFloat(), volume.toFloat())
        }
    }


    private val streamBuffer = StringBuilder()

    override fun streamAppend(args: Map<*, *>) {
        val text = args["text"] as? String ?: return
        val voiceId = args["voiceId"] as? String ?: "expr-voice-2-f"
        val rate = (args["rate"] as? Double)?.toFloat() ?: 1.0f

        streamBuffer.append(text)
        val content = streamBuffer.toString()

        val sentences = splitSentences(content)
        if (sentences.size > 1) {
            val complete = sentences.dropLast(1).joinToString("")
            streamBuffer.clear()
            streamBuffer.append(sentences.last())

            val phonemized = phonemizer.convert(complete)
            val wavBytes = session?.synthesize(phonemized, voiceId, rate)
            if (wavBytes != null) {
                playWavBytes(wavBytes)
            }
        }
    }

    override fun streamFinalize(args: Map<*, *>) {
        val voiceId = args["voiceId"] as? String ?: "expr-voice-2-f"
        val rate = (args["rate"] as? Double)?.toFloat() ?: 1.0f
        if (streamBuffer.isNotEmpty()) {
            val text = streamBuffer.toString()
            streamBuffer.clear()
            val phonemized = phonemizer.convert(text)
            val wavBytes = session?.synthesize(phonemized, voiceId, rate)
            if (wavBytes != null) {
                playWavBytes(wavBytes)
            }
        }
        waitForPlayback()
    }

    override fun streamCancel(args: Map<*, *>) {
        streamBuffer.clear()
        stop()
    }

    override fun stop() {
        try {
            audioTrack?.stop()
        } catch (_: Exception) {}
        try {
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }

    override fun release() {
        stop()
        session?.close()
        session = null
    }

    private fun playWavBytes(wavBytes: ByteArray, rate: Float = 1.0f, pitch: Float = 1.0f, volume: Float = 1.0f) {
        val sampleRate = extractSampleRate(wavBytes)
        val audioData = extractAudioData(wavBytes)

        if (audioTrack == null) {
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
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
                .setBufferSizeInBytes(maxOf(minBufferSize * 4, minBufferSize))
                .build()

            audioTrack?.play()
        }

        audioTrack?.setVolume(volume)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            try {
                audioTrack?.playbackParams = audioTrack?.playbackParams?.setSpeed(rate)?.setPitch(pitch) ?: android.media.PlaybackParams().setSpeed(rate).setPitch(pitch)
            } catch (e: Exception) {}
        }
        
        audioTrack?.write(audioData, 0, audioData.size)
    }

    private fun waitForPlayback() {
        // AudioTrack in STREAM mode blocks on write if the internal buffer is full.
        // It stays in PLAYSTATE_PLAYING until explicitly stopped.
        // Do not spin-lock here.
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
