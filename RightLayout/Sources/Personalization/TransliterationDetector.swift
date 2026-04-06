import Foundation

/// Hint-only transliteration suggestion (Ticket 55).
/// This is intentionally conservative: better to miss than to annoy with false positives.
struct TransliterationSuggestion: Sendable, Equatable {
    let id: UUID
    let original: String
    let replacement: String
    let targetLanguage: Language
    let confidence: Double
}

actor TransliterationDetector {
    static let shared = TransliterationDetector()

    private let wordValidator: WordValidator

    private let russianAllowlist: Set<String> = [
        "privet",
        "spasibo",
        "poka",
        "kak",
        "dela"
    ]

    private let russianSignalSequences: [String] = [
        "shch", "sch",
        "sh", "ch",
        "yo", "yu", "ya",
        "zh", "kh",
        "ts"
    ]

    private let hebrewLexicon: [String: String] = [
        "shalom": "שלום",
        "toda": "תודה",
        "raba": "רבה",
        "sababa": "סבבה",
        "slicha": "סליחה",
        "boker": "בוקר",
        "erev": "ערב"
    ]

    init(wordValidator: WordValidator = HybridWordValidator()) {
        self.wordValidator = wordValidator
    }

    func suggest(for coreText: String) -> TransliterationSuggestion? {
        let parts = splitOuterDelimiters(coreText)
        guard !parts.token.isEmpty else { return nil }

        let token = parts.token
        guard token.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }

        let tokenLower = token.lowercased()
        let isAllowlistedRu = russianAllowlist.contains(tokenLower)
        let hasRuSignal = russianSignalSequences.contains(where: { tokenLower.contains($0) })

        // Ticket 55: Default threshold is conservative (≥ 4), with a tiny allowlist for very common cases.
        if tokenLower.count < 4 && !isAllowlistedRu {
            return nil
        }

        // Avoid showing suggestions for arbitrary Latin tokens unless they look like transliteration.
        if !isAllowlistedRu && !hasRuSignal && hebrewLexicon[tokenLower] == nil {
            return nil
        }

        let isValidEnglish = wordValidator.confidence(for: token, language: .english) >= 1.0

        // For non-allowlisted tokens, respect English validity to avoid noisy suggestions.
        if isValidEnglish && !isAllowlistedRu && hebrewLexicon[tokenLower] == nil {
            return nil
        }

        var candidates: [TransliterationSuggestion] = []
        candidates.reserveCapacity(2)

        if let he = hebrewLexicon[tokenLower] {
            let replacement = parts.leading + he + parts.trailing
            candidates.append(
                TransliterationSuggestion(
                    id: UUID(),
                    original: coreText,
                    replacement: replacement,
                    targetLanguage: .hebrew,
                    confidence: 0.98
                )
            )
        }

        if isAllowlistedRu || hasRuSignal {
            if let ruLower = transliterateLatinToRussian(tokenLower) {
                let isValidRussian = wordValidator.confidence(for: ruLower, language: .russian) >= 1.0
                if isValidRussian {
                    let ruCased = applyCasing(from: token, to: ruLower)
                    let replacement = parts.leading + ruCased + parts.trailing
                    candidates.append(
                        TransliterationSuggestion(
                            id: UUID(),
                            original: coreText,
                            replacement: replacement,
                            targetLanguage: .russian,
                            confidence: 0.95
                        )
                    )
                }
            }
        }

        return candidates.max(by: { $0.confidence < $1.confidence })
    }

    private struct DelimiterSplit {
        let leading: String
        let token: String
        let trailing: String
    }

    private func splitOuterDelimiters(_ text: String) -> DelimiterSplit {
        let chars = Array(text)
        var start = 0
        var end = chars.count

        while start < end, !chars[start].isLetter {
            start += 1
        }
        while end > start, !chars[end - 1].isLetter {
            end -= 1
        }

        return DelimiterSplit(
            leading: String(chars[0..<start]),
            token: String(chars[start..<end]),
            trailing: String(chars[end..<chars.count])
        )
    }

    private func transliterateLatinToRussian(_ tokenLower: String) -> String? {
        let multi: [(String, String)] = [
            ("shch", "щ"),
            ("sch", "щ"),
            ("yo", "ё"),
            ("yu", "ю"),
            ("ya", "я"),
            ("zh", "ж"),
            ("kh", "х"),
            ("ts", "ц"),
            ("sh", "ш"),
            ("ch", "ч")
        ]

        let single: [Character: String] = [
            "a": "а",
            "b": "б",
            "c": "ц",
            "d": "д",
            "e": "е",
            "f": "ф",
            "g": "г",
            "h": "х",
            "i": "и",
            "j": "й",
            "k": "к",
            "l": "л",
            "m": "м",
            "n": "н",
            "o": "о",
            "p": "п",
            "q": "к",
            "r": "р",
            "s": "с",
            "t": "т",
            "u": "у",
            "v": "в",
            "w": "в",
            "x": "кс",
            "y": "ы",
            "z": "з"
        ]

        var out = ""
        out.reserveCapacity(tokenLower.count)

        var idx = tokenLower.startIndex
        while idx < tokenLower.endIndex {
            let remaining = tokenLower[idx...]
            var matched = false

            for (pattern, replacement) in multi {
                if remaining.hasPrefix(pattern) {
                    out.append(contentsOf: replacement)
                    idx = tokenLower.index(idx, offsetBy: pattern.count)
                    matched = true
                    break
                }
            }

            if matched {
                continue
            }

            let ch = tokenLower[idx]
            guard let replacement = single[ch] else { return nil }
            out.append(contentsOf: replacement)
            idx = tokenLower.index(after: idx)
        }

        return out
    }

    private func applyCasing(from sourceToken: String, to targetLower: String) -> String {
        let letters = sourceToken.filter(\.isLetter)
        guard !letters.isEmpty else { return targetLower }

        let isAllUpper = letters.allSatisfy(\.isUppercase)
        if isAllUpper {
            return targetLower.uppercased()
        }

        let isCapitalized = (letters.first?.isUppercase ?? false) && letters.dropFirst().allSatisfy(\.isLowercase)
        if isCapitalized, let first = targetLower.first {
            return String(first).uppercased() + String(targetLower.dropFirst())
        }

        return targetLower
    }
}
