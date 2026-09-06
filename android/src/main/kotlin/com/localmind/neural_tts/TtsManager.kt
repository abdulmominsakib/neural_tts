package com.localmind.neural_tts

import android.content.Context
import com.localmind.neural_tts.engines.*
import java.util.concurrent.CancellationException

class TtsManager(private val context: Context?,
    private val factory: (String) -> BaseEngine = { name ->
        when (name) {
            "kitten" -> KittenEngine()
            "kokoro" -> KokoroEngine()
            "supertonic" -> SupertonicEngine()
            "system" -> SystemEngine()
            else -> throw IllegalArgumentException("Unknown engine: $name")
        }
    }) {
    private val lock = Any()
    @Volatile private var currentEngine: BaseEngine? = null
    private var engineName: String? = null
    @Volatile var generation: Long = 0
        private set
    private var streamId: String? = null

    fun checkGeneration(expected: Long) {
        if (generation != expected) throw CancellationException("TTS operation cancelled")
    }

    // All methods except stop run on the plugin's single worker.
    fun initialize(args: Map<*, *>, expected: Long = generation) {
        checkGeneration(expected)
        releaseCurrent()
        val name = args["engine"] as? String ?: throw IllegalArgumentException("engine required")
        val engine = factory(name)
        synchronized(lock) {
            checkGeneration(expected)
            currentEngine = engine
            engineName = name
            engine.beginOperation()
        }
        try {
            engine.initialize(args + ("context" to context))
            checkGeneration(expected)
        } catch (error: Exception) {
            releaseCurrent()
            throw error
        }
    }

    private fun begin(args: Map<*, *>, expected: Long): BaseEngine = synchronized(lock) {
        checkGeneration(expected)
        if (args["engine"] != null && args["engine"] != engineName) {
            throw IllegalStateException("Requested engine is not active")
        }
        val engine = currentEngine ?: throw IllegalStateException("TTS not initialized")
        engine.beginOperation()
        engine
    }

    fun speak(args: Map<*, *>, expected: Long = generation) {
        check(streamId == null) { "A stream is already active" }
        begin(args, expected).speak(args)
        checkGeneration(expected)
    }

    fun streamAppend(args: Map<*, *>, expected: Long = generation) {
        val id = args["streamId"] as? String ?: throw IllegalArgumentException("streamId required")
        check(streamId == null || streamId == id) { "A stream is already active" }
        val engine = begin(args, expected)
        streamId = id
        engine.speak(args)
        checkGeneration(expected)
    }

    fun streamFinalize(args: Map<*, *>, expected: Long = generation) {
        checkGeneration(expected)
        check(streamId == null || streamId == args["streamId"]) { "Unknown stream" }
        // Append calls already wait for their submitted audio to finish.
        streamId = null
    }

    fun stop() {
        synchronized(lock) {
            generation++
            currentEngine?.stop()
        }
    }

    fun clearStream() { streamId = null }
    private fun releaseCurrent() {
        val engine = synchronized(lock) {
            currentEngine.also { currentEngine = null; engineName = null }
        }
        clearStream()
        engine?.release()
    }
    fun release() = releaseCurrent()
    fun getAvailableVoices(): List<Map<String, Any?>> = SystemEngine.availableVoices(requireNotNull(context))
}
