package com.localmind.neural_tts.onnx

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession

object OnnxRuntimeHolder {
    private var environment: OrtEnvironment? = null

    @Synchronized
    fun getEnvironment(): OrtEnvironment {
        if (environment == null) {
            environment = OrtEnvironment.getEnvironment()
        }
        return environment!!
    }

    fun createSession(modelPath: String): OrtSession {
        val env = getEnvironment()
        return OrtSession.SessionOptions().use { options ->
            options.addCPU(true)
            env.createSession(modelPath, options)
        }
    }

    fun close() {
        try {
            environment?.close()
        } catch (_: Exception) {}
        environment = null
    }
}
