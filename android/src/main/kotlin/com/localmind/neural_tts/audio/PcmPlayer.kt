package com.localmind.neural_tts.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.PlaybackParams
import java.util.concurrent.CancellationException

interface AudioOutput {
    fun write(bytes: ByteArray, offset: Int, length: Int): Int
    fun playedFrames(): Long
    fun stop()
    fun close()
}

/** The worker owns disposal; cancellation only signals and pauses playback. */
class PcmPlayer(private val factory: (Int, Float, Float, Float) -> AudioOutput =
    { sampleRate, rate, pitch, volume -> AndroidAudioOutput(sampleRate, rate, pitch, volume) }) {
    private val lock = Any()
    @Volatile private var cancelled = false
    private var output: AudioOutput? = null

    fun begin() { synchronized(lock) { cancelled = false } }
    fun checkCancelled() {
        if (cancelled) throw CancellationException("Playback cancelled")
    }
    fun stop() {
        synchronized(lock) {
            cancelled = true
            output?.stop()
        }
    }
    fun play(bytes: ByteArray, sampleRate: Int, rate: Float, pitch: Float, volume: Float) {
        require(rate.isFinite() && rate > 0 && pitch.isFinite() && pitch > 0)
        require(volume.isFinite() && volume in 0f..1f)
        require(bytes.size % 2 == 0) { "PCM16 requires complete samples" }
        if (bytes.isEmpty()) { checkCancelled(); return }
        val device = synchronized(lock) {
            checkCancelled()
            factory(sampleRate, rate, pitch, volume).also { output = it }
        }
        try {
            var offset = 0
            var lastFrames = 0L
            var lastProgress = System.nanoTime()
            while (offset < bytes.size || device.playedFrames() < bytes.size / 2L) {
                checkCancelled()
                var written = 0
                if (offset < bytes.size) {
                    written = device.write(bytes, offset, bytes.size - offset)
                    check(written >= 0) { "Audio write failed: $written" }
                    offset += written
                }
                val frames = device.playedFrames()
                if (written > 0 || frames != lastFrames) lastProgress = System.nanoTime()
                check(System.nanoTime() - lastProgress < 10_000_000_000L) { "Audio playback stalled" }
                lastFrames = frames
                if (written == 0) Thread.sleep(10)
            }
            checkCancelled()
        } finally {
            synchronized(lock) {
                output = null
                device.close()
            }
        }
    }
}

private class AndroidAudioOutput(sampleRate: Int, rate: Float, pitch: Float, volume: Float) : AudioOutput {
    private val track: AudioTrack
    init {
        val minimum = AudioTrack.getMinBufferSize(sampleRate,
            AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Unsupported audio format" }
        track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setBufferSizeInBytes(minimum * 4).build()
        try {
            track.setVolume(volume)
            track.playbackParams = PlaybackParams().setSpeed(rate).setPitch(pitch)
            track.play()
        } catch (error: Exception) {
            track.release()
            throw error
        }
    }
    override fun write(bytes: ByteArray, offset: Int, length: Int) =
        track.write(bytes, offset, length, AudioTrack.WRITE_NON_BLOCKING)
    override fun playedFrames() = track.playbackHeadPosition.toLong() and 0xffffffffL
    override fun stop() { try { track.pause(); track.flush() } catch (_: Exception) {} }
    override fun close() { try { track.stop() } finally { track.release() } }
}
