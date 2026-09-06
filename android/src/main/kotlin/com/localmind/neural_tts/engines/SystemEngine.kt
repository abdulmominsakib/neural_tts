package com.localmind.neural_tts.engines

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.CancellationException

class SystemEngine : BaseEngine {
    private val controlLock = Any()
    @Volatile private var tts: TextToSpeech? = null
    @Volatile private var cancelled = false
    @Volatile private var pending: CountDownLatch? = null
    @Volatile private var utterance: String? = null
    @Volatile private var failure: String? = null

    override fun beginOperation() { cancelled = false }
    private fun checkCancelled() {
        if (cancelled) throw CancellationException("Playback cancelled")
    }
    override fun initialize(args: Map<*, *>) {
        val context = args["context"] as? Context ?: throw IllegalArgumentException("context required")
        val ready = CountDownLatch(1)
        var status = TextToSpeech.ERROR
        tts = TextToSpeech(context) { result -> status = result; ready.countDown() }
        try {
            check(ready.await(10, TimeUnit.SECONDS)) { "System TTS initialization timed out" }
            checkCancelled()
            check(status == TextToSpeech.SUCCESS) { "System TTS initialization failed" }
            tts!!.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) { if (id == utterance) pending?.countDown() }
                override fun onError(id: String?) {
                    if (id == utterance) { failure = "System TTS utterance failed"; pending?.countDown() }
                }
                override fun onStop(id: String?, interrupted: Boolean) {
                    if (id == utterance) { failure = "System TTS utterance stopped"; pending?.countDown() }
                }
            })
        } catch (error: Exception) {
            release()
            throw error
        }
    }
    override fun speak(args: Map<*, *>) {
        checkCancelled()
        val engine = tts ?: throw IllegalStateException("TTS not initialized")
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        if (text.isBlank()) return
        val rate = (args["rate"] as? Number)?.toFloat() ?: 1f
        val pitch = (args["pitch"] as? Number)?.toFloat() ?: 1f
        val volume = (args["volume"] as? Number)?.toFloat() ?: 1f
        require(rate.isFinite() && rate > 0 && pitch.isFinite() && pitch > 0)
        require(volume.isFinite() && volume in 0f..1f)
        check(engine.setSpeechRate(rate) != TextToSpeech.ERROR) { "Unsupported rate" }
        check(engine.setPitch(pitch) != TextToSpeech.ERROR) { "Unsupported pitch" }
        val voiceId = args["voiceId"] as? String
        val voice = engine.voices?.find { it.name == voiceId }
        if (voice != null) engine.voice = voice
        else {
            val result = engine.setLanguage(Locale.forLanguageTag(args["language"] as? String ?: "en"))
            check(result >= 0) { "System TTS language unavailable" }
        }
        // The OS limits utterance length. Preserve order and await each chunk.
        for (chunk in text.chunked(TextToSpeech.getMaxSpeechInputLength() - 1)) {
            checkCancelled()
            val done = CountDownLatch(1)
            pending = done
            failure = null
            utterance = UUID.randomUUID().toString()
            try {
                val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume) }
                synchronized(controlLock) {
                    checkCancelled()
                    check(engine.speak(chunk, TextToSpeech.QUEUE_FLUSH, params, utterance) == TextToSpeech.SUCCESS) {
                        "System TTS rejected speech"
                    }
                }
                val timeoutSeconds = (30 + chunk.length / (rate * 5)).toLong()
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(timeoutSeconds)
                while (!done.await(50, TimeUnit.MILLISECONDS)) {
                    checkCancelled()
                    if (System.nanoTime() > deadline) {
                        engine.stop()
                        throw IllegalStateException("System TTS playback timed out")
                    }
                }
                checkCancelled()
                check(failure == null) { failure!! }
            } finally { pending = null; utterance = null }
        }
    }
    override fun streamAppend(args: Map<*, *>) { throw UnsupportedOperationException("System streaming unsupported") }
    override fun streamFinalize(args: Map<*, *>) { throw UnsupportedOperationException("System streaming unsupported") }
    override fun streamCancel(args: Map<*, *>) = stop()
    override fun stop() {
        synchronized(controlLock) {
            cancelled = true
            tts?.stop()
            pending?.countDown()
        }
    }
    override fun release() {
        try { stop() } finally { tts?.shutdown(); tts = null }
    }
    companion object {
        fun availableVoices(context: Context): List<Map<String, Any?>> {
            val engine = SystemEngine()
            try {
                engine.initialize(mapOf("context" to context))
                return engine.tts?.voices.orEmpty().map { voice -> mapOf(
                    "id" to voice.name, "name" to voice.name,
                    "language" to voice.locale.toLanguageTag(), "gender" to "unknown") }
            } finally { engine.release() }
        }
    }
}
