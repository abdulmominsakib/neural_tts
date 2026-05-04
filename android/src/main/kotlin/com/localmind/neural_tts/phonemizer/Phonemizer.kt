package com.localmind.neural_tts.phonemizer

/**
 * Phonemizer that converts English text to IPA.
 *
 * Uses a layered lookup cascade:
 *   1. Reduced forms — hardcoded function-word shortcuts
 *   2. Dictionary lookup — en-us.bin (EPD1 format, ~124K words)
 *   3. Hyphen-split — split compound words, look up each piece
 *   4. Possessive fallback — word's → dict["word"] + "ɪz"
 *   5. G2P fallback — rule-based phonemization for OOV words
 */
class Phonemizer(private val dictPath: String? = null) {

    private val dict: EpDict? by lazy {
        if (dictPath != null) {
            val d = EpDict(dictPath)
            if (d.load()) d else null
        } else null
    }

    fun convert(text: String): String {
        val textToProcess = expandDigits(text)

        val cleaned = textToProcess
            .replace(Regex("[^\\w\\s'.,!?;:\\-]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
            .lowercase()

        val output = StringBuilder()
        var i = 0
        while (i < cleaned.length) {
            val char = cleaned[i]
            if (isPreservablePunctuation(char)) {
                output.append(char)
            } else if (char == ' ') {
                output.append(' ')
            } else {
                val start = i
                while (i < cleaned.length &&
                    cleaned[i] != ' ' &&
                    !isPreservablePunctuation(cleaned[i])
                ) {
                    i++
                }
                i--
                val word = cleaned.substring(start, i + 1)
                if (word.isNotEmpty()) {
                    output.append(phonemizeWord(word))
                }
            }
            i++
        }

        return sanitize(output.toString())
    }

    fun sanitize(ipa: String): String {
        return ipa.filter { it in validChars }
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun expandDigits(text: String): String {
        return text
            .replace("0", " zero ")
            .replace("1", " one ")
            .replace("2", " two ")
            .replace("3", " three ")
            .replace("4", " four ")
            .replace("5", " five ")
            .replace("6", " six ")
            .replace("7", " seven ")
            .replace("8", " eight ")
            .replace("9", " nine ")
    }

    private fun isPreservablePunctuation(char: Char): Boolean =
        char == ',' || ".!?;:".contains(char)

    /**
     * Layered lookup cascade matching the reference implementation.
     */
    private fun phonemizeWord(word: String): String {
        // Layer 1: Reduced forms (function-word shortcuts)
        reducedForms[word]?.let { return it }

        // Layer 2: Dictionary lookup (en-us.bin, ~124K words)
        dict?.lookup(word)?.let { return it }

        // Layer 3: Hyphen-split (compound words)
        if (word.contains('-')) {
            val parts = word.split('-')
            if (parts.size > 1) {
                val phonemized = parts.joinToString(" ") { part ->
                    if (part.isNotEmpty()) phonemizeWord(part) else ""
                }
                if (phonemized.isNotBlank()) return phonemized
            }
        }

        // Layer 4: Possessive fallback (word's → dict["word"] + "ɪz")
        if (word.endsWith("'s") && word.length > 2) {
            val base = word.substring(0, word.length - 2)
            val baseIpa = phonemizeWord(base)
            if (baseIpa.isNotEmpty()) return baseIpa + "ɪz"
        }
        if (word.endsWith("s'") && word.length > 2) {
            val base = word.substring(0, word.length - 1)
            val baseIpa = phonemizeWord(base)
            if (baseIpa.isNotEmpty()) return baseIpa
        }

        // Layer 5: G2P fallback (rule-based for OOV words)
        return phonemizeCore(word)
    }

    private fun phonemizeCore(word: String): String {
        if (word.isEmpty()) return ""
        val buffer = StringBuilder()
        var i = 0

        if (word.length >= 2) {
            val pair = word.substring(0, 2)
            silentInitialClusters[pair]?.let {
                buffer.append(it)
                i = 2
            }
        }

        while (i < word.length) {
            val char = word[i]
            val isLast = i == word.length - 1
            val next = if (!isLast) word[i + 1] else null

            if (char == 'e' && isLast && word.length > 2) {
                i++
                continue
            }

            if (char == 'm' && next == 'b' && i == word.length - 2) {
                buffer.append('m')
                i += 2
                continue
            }

            if (isVowel(char)) {
                if (i + 2 < word.length) {
                    val tri = word.substring(i, i + 3)
                    vowelMultigraphs[tri]?.let {
                        buffer.append(it)
                        i += 3
                        continue
                    }
                }
                if (next != null) {
                    val di = word.substring(i, i + 2)
                    if (di == "er" && i == word.length - 2) {
                        buffer.append('ɚ')
                        i += 2
                        continue
                    }
                    vowelMultigraphs[di]?.let {
                        buffer.append(it)
                        i += 2
                        continue
                    }
                }
                if (hasMagicE(word, i)) {
                    buffer.append(longVowels[char] ?: char)
                    i++
                    continue
                }
                buffer.append(shortVowels[char] ?: char)
                i++
                continue
            }

            if (char == 'c' && next != null && "eiy".contains(next)) {
                buffer.append('s')
                i++
                continue
            }

            if (char == 'g' && next != null && "eiy".contains(next)) {
                buffer.append("dʒ")
                i++
                continue
            }

            if (char == 'y' && isLast) {
                buffer.append(if (word.length <= 3) "aɪ" else "iː")
                i++
                continue
            }

            if (i + 2 < word.length) {
                val tri = word.substring(i, i + 3)
                consonantMultigraphs[tri]?.let {
                    buffer.append(it)
                    i += 3
                    continue
                }
            }

            if (next != null) {
                val di = word.substring(i, i + 2)
                consonantMultigraphs[di]?.let {
                    buffer.append(it)
                    i += 2
                    continue
                }
            }

            buffer.append(singleConsonants[char] ?: "")
            i++
        }

        return buffer.toString()
    }

    private fun isVowel(char: Char): Boolean = "aeiou".contains(char)

    private fun hasMagicE(word: String, index: Int): Boolean {
        if (word.isEmpty() || word.last() != 'e' || word.length < 3) return false
        var j = index + 1
        var consonantCount = 0
        while (j < word.length - 1) {
            if (isVowel(word[j])) return false
            consonantCount++
            j++
        }
        return consonantCount >= 1
    }

    companion object {
        /**
         * Reduced forms — common function words with simplified pronunciations.
         * These take priority over dictionary lookups for consistency.
         */
        private val reducedForms = mapOf(
            "a" to "ɐ", "the" to "ðə", "to" to "tə", "of" to "ʌv",
            "and" to "ən", "an" to "ən", "in" to "ɪn", "is" to "ɪz",
            "it" to "ɪt", "for" to "fɚ", "on" to "ɑn", "at" to "æt",
            "or" to "ɚ", "as" to "æz", "be" to "bi", "by" to "baɪ",
            "he" to "hi", "we" to "wi", "me" to "mi", "do" to "də",
            "my" to "maɪ", "so" to "soʊ", "no" to "noʊ", "up" to "ʌp",
            "if" to "ɪf", "us" to "ʌs", "but" to "bʌt",
        )

        private val validChars = setOf(
            ';', ':', ',', '.', '!', '?', '¡', '¿', '—', '…',
            '"', '«', '»', '\u201C', '\u201D', ' ',
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
            'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
            'U', 'V', 'W', 'X', 'Y', 'Z',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
            'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
            'u', 'v', 'w', 'x', 'y', 'z',
            'ɑ', 'ɐ', 'ɒ', 'æ', 'ɓ', 'ʙ', 'β', 'ɔ', 'ɕ', 'ç',
            'ɗ', 'ɖ', 'ð', 'ʤ', 'ə', 'ɘ', 'ɚ', 'ɛ', 'ɜ', 'ɝ',
            'ɞ', 'ɟ', 'ʄ', 'ɡ', 'ɠ', 'ɢ', 'ʛ', 'ɦ', 'ɧ', 'ħ',
            'ɥ', 'ʜ', 'ɨ', 'ɪ', 'ʝ', 'ɭ', 'ɬ', 'ɫ', 'ɮ', 'ʟ',
            'ɱ', 'ɯ', 'ɰ', 'ŋ', 'ɳ', 'ɲ', 'ɴ', 'ø', 'ɵ', 'ɸ',
            'θ', 'œ', 'ɶ', 'ʘ', 'ɹ', 'ɺ', 'ɾ', 'ɻ', 'ʀ', 'ʁ',
            'ɽ', 'ʂ', 'ʃ', 'ʈ', 'ʧ', 'ʉ', 'ʊ', 'ʋ', 'ⱱ', 'ʌ',
            'ɣ', 'ɤ', 'ʍ', 'χ', 'ʎ', 'ʏ', 'ʑ', 'ʐ', 'ʒ', 'ʔ',
            'ʡ', 'ʕ', 'ʢ', 'ǀ', 'ǁ', 'ǂ', 'ǃ',
            'ˈ', 'ˌ', 'ː', 'ˑ', 'ʼ', 'ʴ', 'ʰ', 'ʱ', 'ʲ', 'ʷ',
            'ˠ', 'ˤ', '˞', '↓', '↑', '→', '↗', '↘', 'ᵻ', '\u0329',
        )

        private val silentInitialClusters = mapOf(
            "kn" to "n", "wr" to "ɹ", "gn" to "n", "ps" to "s", "pn" to "n", "mn" to "m"
        )

        private val consonantMultigraphs = mapOf(
            "tch" to "ʧ", "dge" to "ʤ", "ch" to "ʧ", "sh" to "ʃ", "zh" to "ʒ",
            "th" to "θ", "gh" to "", "ph" to "f", "wh" to "w", "ng" to "ŋ",
            "nk" to "ŋk", "qu" to "kw", "ck" to "k"
        )

        private val singleConsonants = mapOf(
            'b' to "b", 'c' to "k", 'd' to "d", 'f' to "f", 'g' to "ɡ", 'h' to "h",
            'j' to "ʤ", 'k' to "k", 'l' to "l", 'm' to "m", 'n' to "n", 'p' to "p",
            'q' to "k", 'r' to "ɹ", 's' to "s", 't' to "t", 'v' to "v", 'w' to "w",
            'x' to "ks", 'y' to "j", 'z' to "z"
        )

        private val shortVowels = mapOf('a' to "æ", 'e' to "ɛ", 'i' to "ɪ", 'o' to "ɑ", 'u' to "ʌ")
        private val longVowels = mapOf('a' to "eɪ", 'e' to "iː", 'i' to "aɪ", 'o' to "oʊ", 'u' to "juː")

        private val vowelMultigraphs = mapOf(
            "igh" to "aɪ", "ure" to "jʊɹ", "ear" to "ɪɹ", "air" to "ɛɹ",
            "oor" to "ʊɹ", "ar" to "ɑːɹ", "er" to "ɝ", "ir" to "ɝ",
            "or" to "ɔːɹ", "ur" to "ɝ", "ay" to "eɪ", "ai" to "eɪ",
            "ei" to "eɪ", "ee" to "iː", "ea" to "iː", "ie" to "iː",
            "oa" to "oʊ", "ow" to "oʊ", "oo" to "uː", "ue" to "uː",
            "ew" to "juː", "eu" to "juː", "ou" to "aʊ", "oi" to "ɔɪ",
            "oy" to "ɔɪ", "au" to "ɔː", "aw" to "ɔː"
        )
    }
}
