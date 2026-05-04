package com.localmind.neural_tts.engines

interface BaseEngine {
    fun initialize(args: Map<*, *>)
    fun speak(args: Map<*, *>)
    fun streamAppend(args: Map<*, *>)
    fun streamFinalize(args: Map<*, *>)
    fun streamCancel(args: Map<*, *>)
    fun stop()
    fun release()
}
