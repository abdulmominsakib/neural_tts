package com.localmind.neural_tts

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.AudioTrack.OnPlaybackPositionUpdateListener
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class NeuralTtsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var ttsManager: TtsManager? = null
    private val streamChannels = ConcurrentHashMap<String, EventChannel>()
    private var coroutineScope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.localmind.neural_tts")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        ttsManager = TtsManager(context)
        coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        ttsManager?.release()
        ttsManager = null
        streamChannels.values.forEach { it.setStreamHandler(null) }
        streamChannels.clear()
        coroutineScope?.cancel()
        coroutineScope = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        coroutineScope?.launch {
            try {
                when (call.method) {
                    "tts.initialize" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments")
                        ttsManager?.initialize(args)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.speak" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments")
                        ttsManager?.speak(args)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.stream.append" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments")
                        ttsManager?.streamAppend(args)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.stream.finalize" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments")
                        ttsManager?.streamFinalize(args)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.stream.cancel" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments")
                        ttsManager?.streamCancel(args)
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.stop" -> {
                        ttsManager?.stop()
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.release" -> {
                        ttsManager?.release()
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                    "tts.getAvailableVoices" -> {
                        val voices = ttsManager?.getAvailableVoices() ?: listOf<Map<String, Any?>>()
                        withContext(Dispatchers.Main) { result.success(voices) }
                    }
                    else -> withContext(Dispatchers.Main) { result.notImplemented() }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("TTS_ERROR", e.message ?: "Unknown error", null)
                }
            }
        }
    }
}
