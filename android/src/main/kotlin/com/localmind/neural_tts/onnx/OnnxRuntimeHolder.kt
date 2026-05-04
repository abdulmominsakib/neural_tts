package com.localmind.neural_tts.onnx

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession

object OnnxRuntimeHolder {
    private var environment: OrtEnvironment? = null

    fun getEnvironment(): OrtEnvironment {
        if (environment == null) {
            environment = OrtEnvironment.getEnvironment()
        }
        return environment!!
    }

    fun createSession(modelPath: String): OrtSession {
        val env = getEnvironment()
        val sessionOptions = OrtSession.SessionOptions()
        sessionOptions.addCPU(true)
        return env.createSession(modelPath, sessionOptions)
    }

    fun close() {
        try {
            environment?.close()
        } catch (_: Exception) {}
        environment = null
    }
}
