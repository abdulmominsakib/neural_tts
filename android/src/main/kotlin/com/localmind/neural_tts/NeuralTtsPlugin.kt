package com.localmind.neural_tts

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class NeuralTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var manager: TtsManager? = null
    private var worker: java.util.concurrent.ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())
    private val pending = ConcurrentHashMap.newKeySet<Reply>()

    private inner class Reply(val result: MethodChannel.Result) {
        private val completed = AtomicBoolean(false)
        fun finish(error: Throwable? = null, value: Any? = null, unknown: Boolean = false) {
            if (!completed.compareAndSet(false, true)) return
            pending.remove(this)
            main.post {
                when {
                    error != null -> result.error("TTS_ERROR", error.message, null)
                    unknown -> result.notImplemented()
                    else -> result.success(value)
                }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.localmind.neural_tts")
        manager = TtsManager(binding.applicationContext)
        worker = Executors.newSingleThreadExecutor()
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        val retiring = manager
        manager = null
        retiring?.stop()
        pending.toList().forEach { it.finish(IllegalStateException("TTS plugin detached")) }
        worker?.execute { retiring?.release() }
        worker?.shutdown()
        worker = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = Reply(result)
        pending.add(reply)
        val tts = manager
        val executor = worker
        if (tts == null || executor == null) {
            reply.finish(IllegalStateException("TTS plugin detached")); return
        }
        // Invalidate queued work and pause active audio without waiting behind inference.
        if (call.method in setOf("tts.stop", "tts.stream.cancel", "tts.release")) tts.stop()
        val generation = tts.generation
        executor.execute {
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                if (call.method !in setOf("tts.stop", "tts.stream.cancel", "tts.release")) {
                    tts.checkGeneration(generation)
                }
                when (call.method) {
                    "tts.initialize" -> tts.initialize(args, generation)
                    "tts.speak" -> tts.speak(args, generation)
                    "tts.stream.append" -> tts.streamAppend(args, generation)
                    "tts.stream.finalize" -> tts.streamFinalize(args, generation)
                    "tts.stop", "tts.stream.cancel" -> tts.clearStream()
                    "tts.release" -> tts.release()
                    "tts.getAvailableVoices" -> {
                        reply.finish(value = tts.getAvailableVoices()); return@execute
                    }
                    else -> { reply.finish(unknown = true); return@execute }
                }
                reply.finish()
            } catch (error: Exception) {
                reply.finish(error)
            }
        }
    }
}
