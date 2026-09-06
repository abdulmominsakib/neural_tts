package com.localmind.neural_tts

import com.localmind.neural_tts.audio.*
import com.localmind.neural_tts.engines.BaseEngine
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.*

class LifecycleTest {
    @Test fun partialWritesAndPlaybackCompletion() {
        var offset = 0
        var closed = false
        val player = PcmPlayer { _, _, _, _ -> object : AudioOutput {
            override fun write(bytes: ByteArray, start: Int, length: Int): Int {
                assertEquals(offset, start)
                val count = minOf(length, 2)
                offset += count
                return count
            }
            override fun playedFrames() = offset / 2L
            override fun stop() {}
            override fun close() { closed = true }
        } }
        player.begin()
        player.play(ByteArray(10), 24000, 1f, 1f, 1f)
        assertEquals(10, offset)
        assertTrue(closed)
    }

    @Test fun waitsForAudioTailAfterAllBytesAreWritten() {
        val submitted = CountDownLatch(1)
        val frames = java.util.concurrent.atomic.AtomicLong(0)
        val player = PcmPlayer { _, _, _, _ -> object : AudioOutput {
            override fun write(bytes: ByteArray, offset: Int, length: Int): Int {
                submitted.countDown(); return length
            }
            override fun playedFrames() = frames.get()
            override fun stop() {}
            override fun close() {}
        } }
        val worker = Executors.newSingleThreadExecutor()
        try {
            player.begin()
            val result = worker.submit { player.play(ByteArray(10), 24000, 1f, 1f, 1f) }
            assertTrue(submitted.await(2, TimeUnit.SECONDS))
            assertFalse(result.isDone)
            frames.set(5)
            result.get(2, TimeUnit.SECONDS)
        } finally { worker.shutdownNow() }
    }

    @Test fun writeFailureClosesAudioOutput() {
        var closed = false
        val player = PcmPlayer { _, _, _, _ -> object : AudioOutput {
            override fun write(bytes: ByteArray, offset: Int, length: Int) = -6
            override fun playedFrames() = 0L
            override fun stop() {}
            override fun close() { closed = true }
        } }
        player.begin()
        try { player.play(ByteArray(10), 24000, 1f, 1f, 1f); fail("must fail") }
        catch (_: IllegalStateException) {}
        assertTrue(closed)
    }

    @Test fun cancelledInferenceCannotCreateAudio() {
        var created = false
        val player = PcmPlayer { _, _, _, _ -> created = true; error("late audio") }
        player.begin()
        player.stop()
        try { player.play(ByteArray(10), 24000, 1f, 1f, 1f); fail("must cancel") }
        catch (_: CancellationException) {}
        assertFalse(created)
    }

    @Test fun stopUnblocksPlaybackAndWorkerDisposesOutput() {
        val writing = CountDownLatch(1)
        var closed = false
        val player = PcmPlayer { _, _, _, _ -> object : AudioOutput {
            override fun write(bytes: ByteArray, offset: Int, length: Int): Int {
                writing.countDown(); return 0
            }
            override fun playedFrames() = 0L
            override fun stop() {}
            override fun close() { closed = true }
        } }
        val worker = Executors.newSingleThreadExecutor()
        try {
            player.begin()
            val result = worker.submit { player.play(ByteArray(10), 24000, 1f, 1f, 1f) }
            assertTrue(writing.await(2, TimeUnit.SECONDS))
            player.stop()
            try { result.get(2, TimeUnit.SECONDS); fail("must cancel") }
            catch (error: ExecutionException) { assertTrue(error.cause is CancellationException) }
            assertTrue(closed)
        } finally { worker.shutdownNow() }
    }

    @Test fun stopDoesNotDisposeSessionDuringInference() {
        val started = CountDownLatch(1)
        val finish = CountDownLatch(1)
        var released = false
        var stopped = false
        val engine = object : BaseEngine {
            override fun initialize(args: Map<*, *>) {}
            override fun speak(args: Map<*, *>) {
                started.countDown()
                assertTrue(finish.await(2, TimeUnit.SECONDS))
                assertFalse(released)
            }
            override fun stop() { stopped = true }
            override fun release() { released = true }
            override fun streamAppend(args: Map<*, *>) {}
            override fun streamFinalize(args: Map<*, *>) {}
            override fun streamCancel(args: Map<*, *>) {}
        }
        val manager = TtsManager(null) { engine }
        manager.initialize(mapOf("engine" to "kitten"))
        val worker = Executors.newSingleThreadExecutor()
        try {
            val generation = manager.generation
            val result = worker.submit { manager.speak(mapOf("engine" to "kitten"), generation) }
            assertTrue(started.await(2, TimeUnit.SECONDS))
            manager.stop()
            assertTrue(stopped)
            assertFalse(released)
            val cleanup = worker.submit { manager.release() }
            finish.countDown()
            try { result.get(2, TimeUnit.SECONDS); fail("must cancel") }
            catch (error: ExecutionException) { assertTrue(error.cause is CancellationException) }
            cleanup.get(2, TimeUnit.SECONDS)
            assertTrue(released)
        } finally { worker.shutdownNow() }
    }
}
