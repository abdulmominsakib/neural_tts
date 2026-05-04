package com.localmind.neural_tts

import android.content.Context
import android.speech.tts.TextToSpeech
import com.localmind.neural_tts.engines.KittenEngine
import com.localmind.neural_tts.engines.KokoroEngine
import com.localmind.neural_tts.engines.SupertonicEngine
import com.localmind.neural_tts.engines.SystemEngine
import com.localmind.neural_tts.engines.BaseEngine

class TtsManager(private val context: Context) {
    private var currentEngine: BaseEngine? = null
    private val engines = mutableMapOf<String, BaseEngine>()

    fun initialize(args: Map<*, *>) {
        val engineName = args["engine"] as? String ?: "kokoro"
        
        if (currentEngine != null && !engines.containsKey(engineName)) {
            currentEngine?.release()
        }
        
        val engine = engines.getOrPut(engineName) {
            when (engineName) {
                "kokoro" -> KokoroEngine()
                "kitten" -> KittenEngine()
                "supertonic" -> SupertonicEngine()
                "system" -> SystemEngine()
                else -> throw IllegalArgumentException("Unknown engine: $engineName")
            }
        }
        
        val initArgs = if (engineName == "system") {
            args + ("context" to context)
        } else {
            args
        }
        
        engine.initialize(initArgs)
        currentEngine = engine
    }

    fun speak(args: Map<*, *>) {
        currentEngine?.speak(args)
    }

    fun streamAppend(args: Map<*, *>) {
        currentEngine?.streamAppend(args)
    }

    fun streamFinalize(args: Map<*, *>) {
        currentEngine?.streamFinalize(args)
    }

    fun streamCancel(args: Map<*, *>) {
        currentEngine?.streamCancel(args)
    }

    fun stop() {
        currentEngine?.stop()
    }

    fun release() {
        currentEngine?.release()
        currentEngine = null
        engines.clear()
    }

    fun getAvailableVoices(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val latch = java.util.concurrent.CountDownLatch(1)
        
        var tts: TextToSpeech? = null
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                try {
                    val voices = tts?.voices ?: emptySet()
                    for (voice in voices) {
                        result.add(mapOf(
                            "id" to voice.name,
                            "name" to voice.name,
                            "language" to voice.locale.language,
                            "gender" to if (voice.latency > 0) "unknown" else "unknown" // Gender isn't easily exposed
                        ))
                    }
                } catch (_: Exception) {}
            }
            latch.countDown()
        }
        
        try {
            latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: Exception) {}
        
        try {
            tts.stop()
            tts.shutdown()
        } catch (_: Exception) {}
        
        return result
    }
}
