package com.localmind.neural_tts.phonemizer

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * Reader for the EPD1 (Endian-agnostic Phoneme Dictionary v1) binary format.
 *
 * The file is memory-mapped for zero-copy binary-search lookups.
 * Format summary (all multi-byte integers are little-endian):
 *
 *   Offset  Size  Field
 *   0       4     MAGIC ("EPD1")
 *   4       4     VERSION (1)
 *   8       4     N_ENTRIES
 *   12      4     (padding)
 *   16      8     KEYS_OFFSET
 *   24      8     KEYS_SIZE
 *   32      8     VALS_OFFSET
 *   40      8     VALS_SIZE
 *   48      8     KOFF_OFFSET
 *   56      8     VOFF_OFFSET
 *   64+     payload (64-byte aligned sections):
 *             KEYS BLOB   — concatenated UTF-8 keys, sorted bytewise
 *             VALS BLOB   — concatenated UTF-8 values (IPA strings)
 *             KOFF TABLE  — uint32[N+1] byte offsets into keys blob
 *             VOFF TABLE  — uint32[N+1] byte offsets into vals blob
 */
class EpDict(private val path: String) {

    private var mapped: ByteBuffer? = null
    private var nEntries: Int = 0
    private var keysOffset: Long = 0
    private var valsOffset: Long = 0
    private var koffOffset: Long = 0
    private var voffOffset: Long = 0
    private var loaded = false

    fun load(): Boolean {
        if (loaded) return mapped != null
        loaded = true

        val file = File(path)
        if (!file.exists()) return false

        try {
            val raf = RandomAccessFile(file, "r")
            val channel = raf.channel
            val buf = channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size())
            buf.order(ByteOrder.LITTLE_ENDIAN)
            raf.close()

            // Validate magic
            val magic = ByteArray(4)
            buf.get(magic)
            if (String(magic) != "EPD1") return false

            // Validate version
            val version = buf.getInt()
            if (version != 1) return false

            nEntries = buf.getInt()
            buf.getInt() // padding

            if (nEntries <= 0 || nEntries > 10_000_000) return false

            keysOffset = buf.getLong()
            val keysSize = buf.getLong()
            valsOffset = buf.getLong()
            val valsSize = buf.getLong()
            koffOffset = buf.getLong()
            voffOffset = buf.getLong()

            // Validate offsets are within file
            val fileSize = channel.size()
            if (keysOffset + keysSize > fileSize) return false
            if (valsOffset + valsSize > fileSize) return false
            if (koffOffset + (nEntries + 1L) * 4 > fileSize) return false
            if (voffOffset + (nEntries + 1L) * 4 > fileSize) return false

            mapped = buf
            return true
        } catch (e: Exception) {
            return false
        }
    }

    /**
     * Look up a word in the dictionary. Returns the IPA transcription or null if not found.
     */
    fun lookup(word: String): String? {
        val buf = mapped ?: return null
        val keyBytes = word.toByteArray(Charsets.UTF_8)

        var lo = 0
        var hi = nEntries - 1

        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val cmp = compareKey(buf, mid, keyBytes)
            when {
                cmp < 0 -> lo = mid + 1
                cmp > 0 -> hi = mid - 1
                else -> return getValue(buf, mid)
            }
        }
        return null
    }

    /**
     * Compare the search key against entry[mid] in the keys blob.
     */
    private fun compareKey(buf: ByteBuffer, index: Int, key: ByteArray): Int {
        val start = buf.getInt((koffOffset + index * 4).toInt()).toLong() and 0xFFFFFFFFL
        val end = buf.getInt((koffOffset + (index + 1) * 4).toInt()).toLong() and 0xFFFFFFFFL
        val len = (end - start).toInt()

        val entryOffset = (keysOffset + start).toInt()
        // Byte-by-byte comparison (equivalent to bytewise string compare)
        val minLen = minOf(key.size, len)
        for (i in 0 until minLen) {
            val a = key[i].toInt() and 0xFF
            val b = buf.get(entryOffset + i).toInt() and 0xFF
            if (a != b) return a - b
        }
        return key.size - len
    }

    /**
     * Read the IPA value for entry[index] from the vals blob.
     */
    private fun getValue(buf: ByteBuffer, index: Int): String {
        val start = buf.getInt((voffOffset + index * 4).toInt()).toLong() and 0xFFFFFFFFL
        val end = buf.getInt((voffOffset + (index + 1) * 4).toInt()).toLong() and 0xFFFFFFFFL
        val len = (end - start).toInt()

        val entryOffset = (valsOffset + start).toInt()
        val bytes = ByteArray(len)
        for (i in 0 until len) {
            bytes[i] = buf.get(entryOffset + i)
        }
        return String(bytes, Charsets.UTF_8)
    }

    fun close() {
        mapped = null
        loaded = false
    }
}
