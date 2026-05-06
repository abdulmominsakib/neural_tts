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
        // Layer 1: Common words (function-word shortcuts and contractions)
        commonWords[word]?.let { return it }

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

        // Layer 4: Suffix stripping (matches Dart reference)
        for (suffix in suffixes) {
            if (word.length > suffix.first.length + 1 && word.endsWith(suffix.first)) {
                val stem = word.substring(0, word.length - suffix.first.length)
                // Call phonemizeWord instead of phonemizeCore so stem gets dict lookup
                return phonemizeWord(stem) + suffix.second
            }
        }

        // Layer 5: Possessive fallback (word's → dict["word"] + "ɪz")
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

        // Layer 6: G2P fallback (rule-based for OOV words)
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
         * Common words — function words, frequent vocabulary, and contractions with simplified pronunciations.
         * These take priority over dictionary lookups for consistency.
         */
        private val commonWords = mapOf(
            "the" to "ðə", "a" to "ə", "an" to "æn",
            "and" to "ænd", "or" to "ɔːɹ", "but" to "bʌt", "if" to "ɪf",
            "of" to "ʌv", "to" to "tuː", "in" to "ɪn", "on" to "ɑn",
            "at" to "æt", "by" to "baɪ", "as" to "æz",
            "for" to "fɔːɹ", "with" to "wɪð", "from" to "fɹʌm", "into" to "ɪntuː",
            "up" to "ʌp", "out" to "aʊt", "over" to "oʊvɚ", "than" to "ðæn",
            "then" to "ðɛn", "so" to "soʊ", "yet" to "jɛt",
            "i" to "aɪ", "you" to "juː", "he" to "hiː", "she" to "ʃiː",
            "it" to "ɪt", "we" to "wiː", "they" to "ðeɪ",
            "me" to "miː", "him" to "hɪm", "her" to "hɜːɹ", "us" to "ʌs",
            "them" to "ðɛm", "my" to "maɪ", "your" to "jɔːɹ", "his" to "hɪz",
            "its" to "ɪts", "our" to "aʊɚ", "their" to "ðɛɹ",
            "this" to "ðɪs", "that" to "ðæt", "these" to "ðiːz", "those" to "ðoʊz",
            "who" to "huː", "which" to "wɪtʃ", "what" to "wʌt", "where" to "wɛɹ",
            "when" to "wɛn", "how" to "haʊ", "why" to "waɪ",
            "is" to "ɪz", "are" to "ɑːɹ", "was" to "wɑz", "were" to "wɜːɹ",
            "be" to "biː", "been" to "biːn", "being" to "biːɪŋ",
            "have" to "hæv", "has" to "hæz", "had" to "hæd",
            "do" to "duː", "does" to "dʌz", "did" to "dɪd", "done" to "dʌn",
            "will" to "wɪl", "would" to "wʊd", "can" to "kæn", "could" to "kʊd",
            "shall" to "ʃæl", "should" to "ʃʊd", "may" to "meɪ", "might" to "maɪt",
            "must" to "mʌst", "need" to "niːd",
            "get" to "ɡɛt", "got" to "ɡɑt", "go" to "ɡoʊ", "went" to "wɛnt",
            "come" to "kʌm", "came" to "keɪm",
            "make" to "meɪk", "made" to "meɪd",
            "say" to "seɪ", "said" to "sɛd",
            "know" to "noʊ", "think" to "θɪŋk", "see" to "siː",
            "look" to "lʊk", "find" to "faɪnd", "give" to "ɡɪv", "use" to "juːz",
            "tell" to "tɛl", "call" to "kɔːl", "keep" to "kiːp", "let" to "lɛt",
            "seem" to "siːm", "feel" to "fiːl", "try" to "tɹaɪ", "leave" to "liːv",
            "put" to "pʊt", "mean" to "miːn", "show" to "ʃoʊ",
            "time" to "taɪm", "year" to "jɪɹ", "day" to "deɪ", "way" to "weɪ",
            "man" to "mæn", "men" to "mɛn", "word" to "wɜːɹd",
            "world" to "wɜːɹld", "life" to "laɪf", "hand" to "hænd",
            "place" to "pleɪs", "case" to "keɪs", "thing" to "θɪŋ", "home" to "hoʊm",
            "water" to "wɔːtɚ", "room" to "ɹuːm", "book" to "bʊk",
            "eye" to "aɪ", "door" to "dɔːɹ", "face" to "feɪs", "name" to "neɪm",
            "people" to "piːpəl", "child" to "tʃaɪld", "children" to "tʃɪldɹən",
            "one" to "wʌn", "two" to "tuː", "three" to "θɹiː",
            "not" to "nɑt", "all" to "ɔːl", "some" to "sʌm", "more" to "mɔːɹ",
            "very" to "vɛɹiː", "just" to "dʒʌst", "also" to "ɔːlsoʊ",
            "even" to "iːvən", "well" to "wɛl", "such" to "sʌtʃ", "only" to "oʊnliː",
            "any" to "ɛniː", "many" to "mɛniː", "each" to "iːtʃ", "long" to "lɔːŋ",
            "down" to "daʊn", "first" to "fɜːɹst", "other" to "ʌðɚ", "about" to "əbaʊt",
            "hello" to "hɛloʊ", "hi" to "haɪ", "hey" to "heɪ",
            "bye" to "baɪ", "goodbye" to "ɡʊdbaɪ",
            "yes" to "jɛs", "no" to "noʊ", "okay" to "oʊkeɪ", "ok" to "oʊkeɪ",
            "please" to "pliːz", "thanks" to "θæŋks", "thank" to "θæŋk",
            "sorry" to "sɑɹiː", "am" to "æm",
            "i'm" to "aɪm", "you're" to "jʊɹ", "he's" to "hiːz", "she's" to "ʃiːz",
            "it's" to "ɪts", "we're" to "wɪɹ", "they're" to "ðɛɹ",
            "i've" to "aɪv", "you've" to "juːv", "we've" to "wiːv", "they've" to "ðeɪv",
            "i'll" to "aɪl", "you'll" to "juːl", "he'll" to "hiːl", "she'll" to "ʃiːl",
            "we'll" to "wiːl", "they'll" to "ðeɪl",
            "i'd" to "aɪd", "you'd" to "juːd", "he'd" to "hiːd", "she'd" to "ʃiːd",
            "we'd" to "wiːd", "they'd" to "ðeɪd",
            "isn't" to "ɪzənt", "aren't" to "ɑːɹnt",
            "wasn't" to "wʌzənt", "weren't" to "wɜːɹnt",
            "haven't" to "hævənt", "hasn't" to "hæzənt", "hadn't" to "hædənt",
            "won't" to "woʊnt", "wouldn't" to "wʊdənt",
            "don't" to "doʊnt", "doesn't" to "dʌzənt", "didn't" to "dɪdənt",
            "can't" to "kænt", "couldn't" to "kʊdənt",
            "shouldn't" to "ʃʊdənt", "mightn't" to "maɪtənt", "mustn't" to "mʌstənt"
        )

        private val suffixes = listOf(
            "tion" to "ʃən", "sion" to "ʒən",
            "ture" to "ʧɚ", "ness" to "nɪs",
            "ment" to "mənt", "able" to "əbəl",
            "ible" to "ɪbəl", "ical" to "ɪkəl",
            "ious" to "iəs", "ance" to "əns",
            "ence" to "əns", "ism" to "ɪzəm",
            "ity" to "ɪti", "ise" to "aɪz",
            "ize" to "aɪz", "ive" to "ɪv",
            "ous" to "əs", "ful" to "fəl",
            "ing" to "ɪŋ", "est" to "ɪst",
            "ist" to "ɪst", "ant" to "ənt",
            "ent" to "ənt", "age" to "ɪʤ",
            "less" to "lɪs", "ify" to "ɪfaɪ",
            "fy" to "faɪ", "ly" to "liː",
            "er" to "ɚ", "ed" to "d",
            "s" to "z"
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
