import Foundation

/// Unified config for all language-related data: punctuation, mappings, lexicon, whitelists
public struct LanguageDataConfig: Sendable {
    public static let shared = LanguageDataConfig()
    
    // MARK: - Punctuation
    public let wordBoundary: Set<Character>
    public let sentenceEnding: Set<Character>
    public let leadingDelimiters: Set<Character>
    public let trailingDelimiters: Set<Character>
    
    // MARK: - Mappings
    public let chinesePrepositions: [String: String] = [:] // Placeholder
    public let japaneseParticles: [String: String] = [:] // Placeholder
    public let hebrewCommonShortWords: Set<String>
    public let languageConversions: [(from: Language, to: Language)]
    public let russianPrepositions: [String: String]
    public let zeroInterference: Set<String>
    
    // MARK: - Lexicon (basic word lists)
    public let lexiconEnglish: Set<String>
    public let lexiconRussian: Set<String>
    public let lexiconHebrew: Set<String>
    
    // MARK: - Whitelists (slang, profanity, internet culture)
    public let whitelistEnglish: Set<String>
    public let whitelistRussian: Set<String>
    public let whitelistHebrew: Set<String>
    
    private init() {
        guard let url = Bundle.module.url(forResource: "language_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback defaults
            wordBoundary = [".", "!", "?", ":", ")", "]", "}", "\"", "»", "\u{201D}", "…"]
            sentenceEnding = [".", "!", "?"]
            leadingDelimiters = ["(", "[", "{", "\"", "«", "\u{201C}"]
            trailingDelimiters = [")", "]", "}", "\"", "»", "\u{201D}"]
            russianPrepositions = ["f": "а", "d": "в", "r": "к", "j": "о", "e": "у", "b": "и", "z": "я"]
            hebrewCommonShortWords = ["כן", "לא", "גם", "זה", "מה", "מי", "על", "עם", "של", "את", "אני", "הוא", "היא"]
            zeroInterference = ["ok", "api", "no", "id"]
            languageConversions = [
                (.english, .russian), (.english, .hebrew),
                (.russian, .english), (.russian, .hebrew),
                (.hebrew, .english), (.hebrew, .russian)
            ]
            lexiconEnglish = []; lexiconRussian = []; lexiconHebrew = []
            whitelistEnglish = []; whitelistRussian = []; whitelistHebrew = []
            return
        }
        
        // Parse punctuation
        let punct = json["punctuation"] as? [String: Any] ?? [:]
        wordBoundary = Self.parseCharSet(punct["wordBoundary"]) ?? [".", "!", "?", ":", ")", "]", "}", "\"", "»", "\u{201D}", "…"]
        sentenceEnding = Self.parseCharSet(punct["sentenceEnding"]) ?? [".", "!", "?"]
        leadingDelimiters = Self.parseCharSet(punct["leadingDelimiters"]) ?? ["(", "[", "{", "\"", "«", "\u{201C}"]
        trailingDelimiters = Self.parseCharSet(punct["trailingDelimiters"]) ?? [")", "]", "}", "\"", "»", "\u{201D}"]
        
        // Parse mappings
        let mappings = json["mappings"] as? [String: Any] ?? [:]
        russianPrepositions = mappings["russianPrepositions"] as? [String: String] ?? 
            ["f": "а", "d": "в", "r": "к", "j": "о", "e": "у", "b": "и", "z": "я"]
        
        hebrewCommonShortWords = Set((mappings["hebrewCommonShortWords"] as? [String]) ?? 
            ["כן", "לא", "גם", "זה", "מה", "מי", "על", "עם", "של", "את", "אני", "הוא", "היא"])
            
        zeroInterference = Set((mappings["zeroInterference"] as? [String]) ?? ["ok", "api", "no", "id"])

        
        let defaultConversions: [(from: Language, to: Language)] = [
            (.english, .russian), (.english, .hebrew),
            (.russian, .english), (.russian, .hebrew),
            (.hebrew, .english), (.hebrew, .russian)
        ]

        if let convArray = mappings["languageConversions"] as? [[String]] {
            let parsed = convArray.compactMap { pair -> (Language, Language)? in
                guard pair.count == 2,
                      let from = Self.parseLanguage(pair[0]),
                      let to = Self.parseLanguage(pair[1]) else { return nil }
                return (from, to)
            }
            languageConversions = parsed.isEmpty ? defaultConversions : parsed
        } else {
            languageConversions = defaultConversions
        }
        
        // Parse lexicon
        let lexicon = json["lexicon"] as? [String: [String]] ?? [:]
        var enLex = Set((lexicon["english"] ?? []).map { $0.lowercased() })
        // Ticket 55: Manually extend lexicon with critical dev terms
        enLex.formUnion(["github", "api", "email"])
        lexiconEnglish = enLex
        
        var ruLex = Set((lexicon["russian"] ?? []).map { $0.lowercased() })
        // Ticket 64: Ensure common prepositions with punctuation mappings are in lexicon
        ruLex.formUnion(["об"]) 
        lexiconRussian = ruLex
        
        lexiconHebrew = Set((lexicon["hebrew"] ?? []).map { $0.lowercased() })
        
        // Parse whitelists
        let whitelists = json["whitelists"] as? [String: [String]] ?? [:]
        whitelistEnglish = Set((whitelists["english"] ?? []).map { $0.lowercased() })
        whitelistRussian = Set((whitelists["russian"] ?? []).map { $0.lowercased() })
        whitelistHebrew = Set((whitelists["hebrew"] ?? []).map { $0.lowercased() })
    }
    
    private static func parseCharSet(_ value: Any?) -> Set<Character>? {
        guard let arr = value as? [String] else { return nil }
        return Set(arr.compactMap { $0.first })
    }

    private static func parseLanguage(_ value: String) -> Language? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let lang = Language(rawValue: v) { return lang } // "en"/"ru"/"he"

        switch v {
        case "english": return .english
        case "russian": return .russian
        case "hebrew": return .hebrew
        default: return nil
        }
    }
    
    // MARK: - Convenience accessors
    
    public func lexicon(for language: Language) -> Set<String> {
        switch language {
        case .english: return lexiconEnglish
        case .russian: return lexiconRussian
        case .hebrew: return lexiconHebrew
        }
    }
    
    public func whitelist(for language: Language) -> Set<String> {
        switch language {
        case .english: return whitelistEnglish
        case .russian: return whitelistRussian
        case .hebrew: return whitelistHebrew
        }
    }
    
    public func lexiconContains(_ word: String, language: Language) -> Bool {
        lexicon(for: language).contains(word.lowercased())
    }
    
    public func isWhitelisted(_ text: String, language: Language) -> Bool {
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        guard !words.isEmpty else { return false }
        let wl = whitelist(for: language)
        return words.allSatisfy { wl.contains($0) }
    }
    
    public func whitelistedLanguage(_ text: String) -> Language? {
        if isWhitelisted(text, language: .english) { return .english }
        if isWhitelisted(text, language: .russian) { return .russian }
        if isWhitelisted(text, language: .hebrew) { return .hebrew }
        return nil
    }
}
