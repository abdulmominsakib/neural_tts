package com.localmind.neural_tts.phonemizer

import java.io.File

/**
 * Tokenizer that maps IPA phoneme characters to integer token IDs.
 *
 * The mapping mirrors KittenTTS's Python `TextCleaner`:
 *   symbols = [_pad] + list(_punctuation) + list(_letters) + list(_letters_ipa)
 * where _pad = "$" (index 0).
 *
 * Special tokens added around every sequence:
 *   [0]  <text tokens…>  [10, 0]
 *
 * The vocabPath parameter is ignored (kept for API compatibility).
 * The IPA vocab is hardcoded to match the ONNX model's training vocabulary.
 */
class Tokenizer(private val vocabPath: String? = null) {
    private val vocab = mutableMapOf<String, Int>()
    private var initialized = false

    companion object {
        /** Index 0 reserved for PAD / start / end boundary. */
        const val PAD = 0
        /** End-of-sequence marker (index of '\n' in the symbol list). */
        const val EOS = 10
    }

    fun initialize() {
        if (initialized) return
        buildVocab()
        initialized = true
    }

    /**
     * Encode text as a sequence of token IDs, with KittenTTS boundary tokens:
     *   [PAD, token…, EOS, PAD]
     */
    fun encode(text: String): LongArray {
        if (!initialized) initialize()
        val result = mutableListOf<Long>()
        result.add(PAD.toLong())         // start token
        for (char in text) {
            vocab[char.toString()]?.let { result.add(it.toLong()) }
        }
        result.add(EOS.toLong())         // end token
        result.add(PAD.toLong())         // trailing pad
        return result.toLongArray()
    }

    // ── Vocabulary construction ────────────────────────────────────────────

    private fun buildVocab() {
        val pad         = "$"
        val punctuation = ";:,.!?¡¿—…\"«»\"\" "
        val letters     = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        val lettersIpa  = "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘\u0301\u0329ᵻ"

        val symbols = pad + punctuation + letters + lettersIpa
        symbols.forEachIndexed { idx, char ->
            vocab[char.toString()] = idx
        }
    }
}
