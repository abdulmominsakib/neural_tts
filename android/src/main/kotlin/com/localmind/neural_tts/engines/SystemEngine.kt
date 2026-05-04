package com.localmind.neural_tts.engines

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.util.Locale
import java.util.UUID

class SystemEngine : BaseEngine {
    private var tts: TextToSpeech? = null
    private var initialized = false
    private var isSpeaking = false
    private var context: Context? = null

    override fun initialize(args: Map<*, *>) {
        if (initialized) return
        val context = args["context"] as? Context ?: return
        this.context = context
        
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                initialized = true
            }
        }
        
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                isSpeaking = true
            }

            override fun onDone(utteranceId: String?) {
                isSpeaking = false
            }

            override fun onError(utteranceId: String?) {
                isSpeaking = false
            }
        })
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String
        val language = args["language"] as? String ?: "en"
        val rate = (args["rate"] as? Double)?.toFloat() ?: 1.0f
        val pitch = (args["pitch"] as? Double)?.toFloat() ?: 1.0f
        val volume = (args["volume"] as? Double)?.toFloat() ?: 1.0f

        if (tts == null) {
            throw IllegalStateException("TTS not initialized call init first")
        }

        if (isSpeaking) {
            tts?.stop()
        }

        tts?.setSpeechRate(rate)
        tts?.setPitch(pitch)
        // Volume is harder to set on TextToSpeech directly, usually via params
        
        if (voiceId != null) {
            try {
                val availableVoices = tts?.voices ?: emptyList()
                val matchingVoice = availableVoices.find { v ->
                    v.name.contains(voiceId, ignoreCase = true) ||
                    v.name.replace(" ", "-").contains(voiceId, ignoreCase = true)
                }
                if (matchingVoice != null) {
                    tts?.voice = matchingVoice
                }
            } catch (_: Exception) {}
        } else {
            tts?.language = Locale.forLanguageTag(language)
        }

        val utteranceId = UUID.randomUUID().toString()
        val params = Bundle()
        params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
    }

    override fun streamAppend(args: Map<*, *>) {
        throw UnsupportedOperationException("System engine does not support streaming")
    }

    override fun streamFinalize(args: Map<*, *>) {
        throw UnsupportedOperationException("System engine does not support streaming")
    }

    override fun streamCancel(args: Map<*, *>) {
        throw UnsupportedOperationException("System engine does not support streaming")
    }

    override fun stop() {
        tts?.stop()
        isSpeaking = false
    }

    override fun release() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        initialized = false
    }
}
