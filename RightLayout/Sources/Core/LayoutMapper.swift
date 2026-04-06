import Foundation
import Carbon
import AppKit

/// Maps characters between different keyboard layouts using a data-driven approach.
public final class LayoutMapper: @unchecked Sendable {
    private var layoutData: LayoutData?
    
    // Cache: LayoutID -> [Character : (Key: String, Modifier: String)]
    private var charToKeyMap: [String: [Character: (key: String, mod: String)]] = [:]
    // Cache: LayoutID -> [Character : [(Key: String, Modifier: String)]]
    // Some layouts (e.g. phonetic Hebrew) intentionally repeat letters on multiple keys; this makes
    // conversion ambiguous and requires disambiguation when converting back to EN/RU.
    private var charToKeyCandidates: [String: [Character: [(key: String, mod: String)]]] = [:]
    
    // Detected user layouts: Language -> LayoutID
    private var activeLayouts: [Language: String] = [:]
    
    // All available layouts per language for brute-force conversion
    private var allLayoutsPerLanguage: [Language: [String]] = [:]
    private var layoutLanguageById: [String: Language] = [:]
    private var ambiguousLayoutIds: Set<String> = []

    private lazy var wordValidator: WordValidator = HybridWordValidator()
    private lazy var ngramModels: [Language: NgramLanguageModel] = {
        var out: [Language: NgramLanguageModel] = [:]
        if let ru = try? NgramLanguageModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? NgramLanguageModel.loadLanguage("en") { out[.english] = en }
        if let he = try? NgramLanguageModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()
    private lazy var unigramModels: [Language: WordFrequencyModel] = {
        var out: [Language: WordFrequencyModel] = [:]
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()
    private let languageData = LanguageDataConfig.shared
    
    public static let shared = LayoutMapper()
    
    public init() {
        loadLayoutData()
        buildMaps()
        buildAllLayoutsPerLanguage()
        // HIToolbox input-source APIs must be queried on the main queue.
        // LayoutMapper can be initialized from background queues (e.g. during detection),
        // so we defer detection safely.
        setDefaults()
        if Thread.isMainThread {
            detectActiveLayouts()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.detectActiveLayouts()
            }
        }
    }
    
    private func buildAllLayoutsPerLanguage() {
        guard let layouts = layoutData?.layouts else { return }
        for layout in layouts {
            guard let lang = Language(rawValue: layout.language) else { continue }
            if allLayoutsPerLanguage[lang] == nil { allLayoutsPerLanguage[lang] = [] }
            allLayoutsPerLanguage[lang]!.append(layout.id)
            layoutLanguageById[layout.id] = lang
        }
    }
    
    private func loadLayoutData() {
        guard let url = Bundle.module.url(forResource: "layouts", withExtension: "json") else {
            print("LayoutMapper: Could not find layouts.json in bundle.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            self.layoutData = try JSONDecoder().decode(LayoutData.self, from: data)
        } catch {
            print("LayoutMapper: Failed to decode layouts.json: \(error)")
        }
    }
    
    private func buildMaps() {
        guard let map = layoutData?.map,
              let layouts = layoutData?.layouts else { return }

        // Build layout language lookup
        var layoutLang: [String: String] = [:]
        for layout in layouts {
            layoutLang[layout.id] = layout.language
        }

        func modRank(_ mod: String) -> Int {
            // Prefer mappings that do not require modifiers. This improves reversibility
            // and reduces accidental case shifts when converting back-and-forth.
            switch mod {
            case "n": return 0
            case "s": return 1
            case "a": return 2
            case "sa": return 3
            default: return 99
            }
        }

        // Latin letters for filtering "escape hatch" mappings
        let latinLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        
        for (keyCode, layoutsMap) in map {
            for (layoutID, mapping) in layoutsMap {
                if charToKeyMap[layoutID] == nil { charToKeyMap[layoutID] = [:] }
                if charToKeyCandidates[layoutID] == nil { charToKeyCandidates[layoutID] = [:] }
                
                let lang = layoutLang[layoutID] ?? "en"
                let isNonLatinLayout = (lang == "ru" || lang == "he")
                
                for (mod, charString) in [("n", mapping.n), ("s", mapping.s), ("a", mapping.a), ("sa", mapping.sa)] {
                    if let s = charString, let char = s.first, s.count == 1 {
                        // Skip Latin letters with Alt modifiers in non-Latin layouts
                        // These are "escape hatches" for typing Latin, not real layout mappings
                        if isNonLatinLayout && (mod == "a" || mod == "sa") {
                            if let scalar = char.unicodeScalars.first, latinLetters.contains(scalar) {
                                continue
                            }
                        }
                        
                        charToKeyCandidates[layoutID]?[char, default: []].append((key: keyCode, mod: mod))
                        if let existing = charToKeyMap[layoutID]?[char] {
                            if modRank(mod) < modRank(existing.mod) {
                                charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                            }
                        } else {
                            charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                        }
                    }
                }
            }
        }

        // Identify layouts with ambiguous reverse-mapping for LETTERS (same letter on multiple keys).
        // Some layouts may repeat punctuation across modifiers on the same key; that is not the
        // ambiguity we want to disambiguate in `convertBest`.
        for (layoutID, chars) in charToKeyCandidates {
            let hasAmbiguousLetters = chars.contains { (ch, candidates) in
                guard ch.isLetter else { return false }
                let distinctKeys = Set(candidates.map { $0.key })
                return distinctKeys.count > 1
            }
            if hasAmbiguousLetters {
                ambiguousLayoutIds.insert(layoutID)
            }
        }
    }
    
    /// Detects user's active keyboard layouts from macOS using InputSourceManager's scoring
    private func detectActiveLayouts() {
        // HIToolbox enforces main-queue usage.
        guard Thread.isMainThread else {
            setDefaults()
            return
        }

        // Call InputSourceManager on main actor
        let detected = MainActor.assumeIsolated {
            InputSourceManager.shared.detectInstalledLayouts()
        }
        for (langCode, layoutID) in detected {
            if let lang = Language(rawValue: langCode) {
                activeLayouts[lang] = layoutID
                // Suppress debug output in CLI mode to avoid polluting JSON output
                if !CommandLine.arguments.contains("--cli") {
                    print("LayoutMapper: Detected \(langCode) -> \(layoutID)")
                }
            }
        }
        

        
        // Fill in defaults for missing languages
        setDefaults()
    }
    
    private func setDefaults() {
        if activeLayouts[.english] == nil { activeLayouts[.english] = "us" }
        if activeLayouts[.russian] == nil { activeLayouts[.russian] = "russianwin" }
        if activeLayouts[.hebrew] == nil { activeLayouts[.hebrew] = "hebrew" }
        rebuildPreserveChars()
    }
    
    /// Recomputes the set of characters that are safe to preserve (don't map to letters in active layouts)
    private func rebuildPreserveChars() {
        var safe = Self.basePreserveChars
        
        // Check each candidate punctuation mark
        for char in Self.candidatePreserveChars {
            var isSafe = true
            
            // Check against all active layouts
            // If this char maps to a letter in ANY active layout, it's not safe to unconditionall preserve
            outerLoop: for (_, sourceID) in activeLayouts {
                // We need to check if 'char', when typed in sourceID, produces a letter in any TARGET active layout
                // Actually, the check is simpler: 
                // Does 'char' exist as a key in sourceID? 
                // And if so, does it map to a letter in any other layout?
                
                guard let sourceMap = charToKeyMap[sourceID] else { continue }
                
                // If the char itself isn't in the source map (e.g. it's not on the keyboard), it's safeish?
                // But usually we are converting FROM sourceID.
                // If I type ` on EN, I look up ` in EN map -> KeyCode 50.
                // Then I look up KeyCode 50 in RU map -> ё (Letter).
                // So ` is NOT safe.
                
                if let (keyCode, _) = sourceMap[char] {
                    // Check what this key maps to in all OTHER active layouts
                    if let fullMap = layoutData?.map {
                        for (_, targetID) in activeLayouts {
                            if let mapping = fullMap[keyCode]?[targetID] {
                                // Check all shift states just to be safe? 
                                // Usually we care about the primary state (n/s) matching the input char.
                                // But simpler: if the output is a letter, it's risky.
                                
                                // Let's check the 'n' (normal) and 's' (shift) states
                                for targetChar in [mapping.n, mapping.s] {
                                    if let s = targetChar, s.count == 1, let c = s.first, c.isLetter {
                                        isSafe = false
                                        break outerLoop
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if isSafe {
                safe.insert(char)
            }
        }
        
        self.preserveChars = safe
    }
    
    /// Returns the active layout ID for a given language, if detected/configured.
    public func activeLayoutID(for language: Language) -> String? {
        return activeLayouts[language]
    }
    
    /// Checks if a character (usually punctuation) acts as a valid letter in any of the OTHER active layouts when typed on the same physical key.
    /// This is used to prevent splitting words on delimiters like "," if the user might be typing a letter in a wrong layout.
    public func isAmbiguousBoundaryChar(_ char: Character) -> Bool {
        guard !char.isLetter && !char.isNumber else { return false }
        
        // Find which layout could produce this character (Reverse lookup)
        // We assume the character was produced by one of the active layouts.
        // If multiple layouts produce it, we check all potential source keys.
        
        var candidateKeys: [(key: String, mod: String)] = []
        
        // Check all active "Source" layouts
        for (_, sourceLayoutID) in activeLayouts {
            if let mapping = charToKeyMap[sourceLayoutID]?[char] {
                candidateKeys.append(mapping)
            }
        }
        
        // For each potential physical key that produced this char:
        for (key, mod) in candidateKeys {
            // Check if this physical key maps to a LETTER in any OTHER active layout
            for (_, targetLayoutID) in activeLayouts {
                // Determine character in target layout for this key + mod
                // Optimization: We don't have a fast Forward-Lookup cache here (Key->Char),
                // but we can query layoutData directly if we assume it's loaded.
                // Or checking charToKeyMap candidates? No.
                
                // Let's use the layoutData map for forward lookup
                if let layoutMapData = layoutData?.map[key]?[targetLayoutID] {
                    // Determine which character is produced by modifier 'mod'
                    // mod is usually "n" (none) or "s" (shift) for punctuation.
                    let targetCharString: String?
                    switch mod {
                    case "n": targetCharString = layoutMapData.n
                    case "s": targetCharString = layoutMapData.s
                    case "a": targetCharString = layoutMapData.a
                    case "sa": targetCharString = layoutMapData.sa
                    default: targetCharString = nil
                    }
                    
                    if let s = targetCharString, let targetChar = s.first, s.count == 1 {
                        // Is this a letter?
                        if targetChar.isLetter {
                            return true
                        }
                        // Also checking specific known mappings if they aren't technically letters but act as word parts?
                        // For now, isLetter is robust enough for standard alphabets.
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Legacy / Helper Methods (Internal)
    // Characters that should be preserved during conversion (not layout-dependent)
    // Dynamic set, updated based on active layouts
    private var preserveChars: Set<Character> = []
    
    // Base set of characters that are always preserved (mostly typographic / non-keyboard)
    private static let basePreserveChars: Set<Character> = [
        // Typographic quotes and dashes
        "\u{00AB}", "\u{00BB}", "\u{201E}", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}",
        "\u{2014}", "\u{2013}", "\u{2026}", "\u{2116}",
        // Copyright, trademark, degree
        "\u{00A9}", "\u{00AE}", "\u{2122}", "\u{00B0}",
        // Currency symbols
        "\u{20AC}", "\u{00A3}", "\u{00A5}", "\u{20BD}", "\u{20B4}", "\u{20AA}"
    ]
    
    // Candidate punctuation to check for safety
    private static let candidatePreserveChars: Set<Character> = Set("!@#$%^&*()-_=+[{]}\\|;:'\",<.>/?`~")

    // Punctuation that should be preserved when it appears at word boundaries
    private static let boundaryPunctuation: Set<Character> = [
        ".", ",", "!", "?", ":", ";", "-", "(", ")", "[", "]", "{", "}"
    ]

    // Some Hebrew layout outputs use combining marks (notably dagesh U+05BC) that may join with the
    // preceding letter into a single grapheme cluster. Split only these cases to keep mapping reversible.
    private static let splitCombiningScalarValues: Set<UInt32> = [0x05BC]

    private static func splitIfNeeded(_ ch: Character) -> [Character] {
        let scalars = Array(ch.unicodeScalars)
        guard scalars.count > 1,
              scalars.contains(where: { splitCombiningScalarValues.contains($0.value) }) else {
            return [ch]
        }
        return scalars.map(Character.init)
    }
    
    /// Converts text from source layout to target layout
    public func convert(_ text: String, fromLayout: String, toLayout: String) -> String? {
        if fromLayout == toLayout { return text }
        
        guard let sourceMap = charToKeyMap[fromLayout],
              let fullMap = layoutData?.map else { return nil }
        
        // Punctuation that acts as word separator even if it maps to a letter
        let wordSeparatorPunct: Set<Character> = [".", ",", ";", ":", "!", "?"]
        
        var result = ""
        result.reserveCapacity(text.count)
        
        let chars = Array(text)
        var i = 0
        var lastWasLetter = false

        while i < chars.count {
            let char = chars[i]
            for c in Self.splitIfNeeded(char) {
                // Preserve special characters that aren't layout-dependent
                if preserveChars.contains(c) {
                    result.append(c)
                    lastWasLetter = false
                    continue
                }
                
                // Check if this is word-separator punctuation that should be preserved
                // Special case: '.' and ',' might be part of a word on RU/HE layouts
                // (. = ю on RU, , = б on RU), so don't preserve them - always convert
                if wordSeparatorPunct.contains(c) && lastWasLetter {
                    // For '.', ',', ';' and ':' NEVER preserve - these keys map to letters in RU/HE
                    // and preserving them breaks wrong-layout words (e.g. "cj;fktyb." → "сожалению").
                    if c == "." || c == "," || c == ";" || c == ":" {
                        // Don't preserve, fall through to conversion logic
                    } else {
                        // For other punctuation, preserve as before
                        let nextIdx = i + 1
                        var shouldPreserve = false
                        
                        if nextIdx >= chars.count {
                            shouldPreserve = true
                        } else {
                            let nextChar = chars[nextIdx]
                            if nextChar.isWhitespace || nextChar.isNewline || !nextChar.isLetter {
                                shouldPreserve = true
                            } else if let (nextKey, nextMod) = sourceMap[nextChar],
                               let nextMapping = fullMap[nextKey]?[toLayout] {
                                let nextTarget: String?
                                switch nextMod {
                                case "n": nextTarget = nextMapping.n
                                case "s": nextTarget = nextMapping.s
                                case "a": nextTarget = nextMapping.a
                                case "sa": nextTarget = nextMapping.sa
                                default: nextTarget = nil
                                }
                                if let s = nextTarget, s.count == 1, let nc = s.first, nc.isLetter {
                                    shouldPreserve = true
                                }
                            }
                        }
                        
                        if shouldPreserve {
                            result.append(c)
                            lastWasLetter = false
                            continue
                        }
                    }
                }

                if let (keyCode, mod) = sourceMap[c],
                   let targetMapping = fullMap[keyCode]?[toLayout] {
                    let targetChar: String?
                    switch mod {
                    case "n": targetChar = targetMapping.n
                    case "s": targetChar = targetMapping.s
                    case "a": targetChar = targetMapping.a
                    case "sa": targetChar = targetMapping.sa
                    default: targetChar = nil
                    }
                    let converted = targetChar ?? String(c)
                    result.append(converted)
                    lastWasLetter = converted.count == 1 && converted.first?.isLetter == true
                } else {
                    result.append(c)
                    lastWasLetter = c.isLetter
                }
            }
            i += 1
        }
        return result
    }

    /// Convert using Language enum with auto-detected layouts, but with disambiguation for
    /// layouts that repeat letters on multiple keys (e.g. Hebrew QWERTY phonetic).
    public func convertBest(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> String? {
        let fromID = activeLayouts?[from.rawValue] ?? self.activeLayouts[from] ?? "us"
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        return convertBest(text, fromLayout: fromID, toLayout: toID)
    }

    public func convertBest(_ text: String, fromLayout: String, toLayout: String) -> String? {
        if fromLayout == toLayout { return text }
        guard let sourceMap = charToKeyMap[fromLayout],
              let fullMap = layoutData?.map else { return nil }

        guard ambiguousLayoutIds.contains(fromLayout),
              let candidatesMap = charToKeyCandidates[fromLayout],
              let targetLanguage = layoutLanguageById[toLayout],
              let targetNgram = ngramModels[targetLanguage] else {
            // No ambiguity or no LM available -> deterministic conversion.
            return convert(text, fromLayout: fromLayout, toLayout: toLayout)
        }
        let targetUnigram = unigramModels[targetLanguage]

        var result = ""
        result.reserveCapacity(text.count)

        var buffer: [Character] = []
        buffer.reserveCapacity(text.count)

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            if let converted = convertAmbiguousWord(buffer, fromLayout: fromLayout, toLayout: toLayout, candidatesMap: candidatesMap, fullMap: fullMap, targetLanguage: targetLanguage, targetNgram: targetNgram, targetUnigram: targetUnigram) {
                result.append(contentsOf: converted)
            } else {
                result.append(contentsOf: String(buffer))
            }
            buffer.removeAll(keepingCapacity: true)
        }

        var convertibleCache: [Character: Bool] = [:]
        convertibleCache.reserveCapacity(64)

        func isConvertibleWordChar(_ ch: Character) -> Bool {
            if ch.isLetter || ch.isNumber { return true }
            if let cached = convertibleCache[ch] { return cached }

            guard let keyCands = candidatesMap[ch], !keyCands.isEmpty else {
                convertibleCache[ch] = false
                return false
            }

            for (key, mod) in keyCands {
                guard let mapping = fullMap[key]?[toLayout] else { continue }
                let targetChar: String?
                switch mod {
                case "n": targetChar = mapping.n
                case "s": targetChar = mapping.s
                case "a": targetChar = mapping.a
                case "sa": targetChar = mapping.sa
                default: targetChar = nil
                }
                if let s = targetChar, s.count == 1, let c = s.first, c.isLetter {
                    convertibleCache[ch] = true
                    return true
                }
            }

            convertibleCache[ch] = false
            return false
        }

        // Punctuation that acts as word separator even if it maps to a letter
        let wordSeparatorPunct: Set<Character> = [".", ",", ";", ":", "!", "?"]
        
        let chars = Array(text)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            let expanded = Self.splitIfNeeded(char)
            
            for c in expanded {
                // Check if this is word-separator punctuation that should be preserved
                // Special case: '.' and ',' might be part of a word on RU/HE layouts
                if wordSeparatorPunct.contains(c) && !buffer.isEmpty {
                    let nextIdx = i + 1
                    
                    // For '.', ',', ';' and ':' ALWAYS add to buffer (they can convert to letters on RU/HE)
                    if c == "." || c == "," || c == ";" || c == ":" {
                        buffer.append(c)
                        continue
                    }
                    
                    // For other punctuation, preserve as before
                    var shouldPreserve = false
                    if nextIdx >= chars.count {
                        shouldPreserve = true
                    } else {
                        let nextChar = chars[nextIdx]
                        if nextChar.isWhitespace || nextChar.isNewline {
                            shouldPreserve = true
                        } else if nextChar.isLetter || isConvertibleWordChar(nextChar) {
                            shouldPreserve = true
                        }
                    }
                    
                    if shouldPreserve {
                        flushBuffer()
                        result.append(c)
                        continue
                    }
                }
                
                if isConvertibleWordChar(c) {
                    buffer.append(c)
                    continue
                }

                flushBuffer()

                // Convert non-letters deterministically (punctuation often isn't ambiguous).
                if let (keyCode, mod) = sourceMap[c],
                   let targetMapping = fullMap[keyCode]?[toLayout] {
                    let targetChar: String?
                    switch mod {
                    case "n": targetChar = targetMapping.n
                    case "s": targetChar = targetMapping.s
                    case "a": targetChar = targetMapping.a
                    case "sa": targetChar = targetMapping.sa
                    default: targetChar = nil
                    }
                    result.append(targetChar ?? String(c))
                } else {
                    result.append(c)
                }
            }
            i += 1
        }

        flushBuffer()
        return result
    }
    
    /// Convenience: Convert using Language enum with auto-detected layouts
    public func convert(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> String? {
        let fromID = activeLayouts?[from.rawValue] ?? self.activeLayouts[from] ?? "us"
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        return convert(text, fromLayout: fromID, toLayout: toID)
    }
    
    /// Try all relevant layout variants and return all possible conversions.
    /// - Always tries **all target layouts** for the destination language.
    /// - Additionally tries **all source layouts** for RU/HE (small variant sets) to handle cases
    ///   where the detected/selected layout variant doesn't match what produced the typed text.
    ///
    /// Example: user typed English on Russian Phonetic → Cyrillic token like "челло".
    /// If the app is configured for "russianwin", deterministic RU→EN conversion fails, but trying
    /// RU source variants recovers "hello".
    public func convertAllVariants(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> [(layout: String, result: String)] {
        guard let targetLayouts = allLayoutsPerLanguage[to] else { return [] }
        let fromID = activeLayouts?[from.rawValue] ?? self.activeLayouts[from] ?? "us"
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"

        var sourceLayouts: [String] = [fromID]
        if (from == .russian || from == .hebrew),
           let allSources = allLayoutsPerLanguage[from] {
            for src in allSources where !sourceLayouts.contains(src) {
                sourceLayouts.append(src)
            }
        }

        var orderedTargets: [String] = [toID]
        for tgt in targetLayouts where !orderedTargets.contains(tgt) {
            orderedTargets.append(tgt)
        }

        var results: [(String, String)] = []
        results.reserveCapacity(min(orderedTargets.count, 8))

        var seenResults = Set<String>()
        seenResults.reserveCapacity(min(orderedTargets.count, 16))

        for srcLayout in sourceLayouts {
            for tgtLayout in orderedTargets {
                guard let converted = convertBest(text, fromLayout: srcLayout, toLayout: tgtLayout),
                      converted != text,
                      seenResults.insert(converted).inserted else {
                    continue
                }
                let label = (srcLayout == fromID) ? tgtLayout : "\(srcLayout)->\(tgtLayout)"
                results.append((label, converted))
            }
        }

        return results
    }
    
    /// Try ALL source layouts for a language and return all possible conversions
    /// This handles reverse conversion (e.g., Hebrew text -> English/Russian)
    public func convertAllSourceVariants(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> [(layout: String, result: String)] {
        guard let sourceLayouts = allLayoutsPerLanguage[from] else { return [] }
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        
        var results: [(String, String)] = []
        for srcLayout in sourceLayouts {
            if let converted = convertBest(text, fromLayout: srcLayout, toLayout: toID),
               converted != text {  // Only include if actually changed
                results.append((srcLayout, converted))
            }
        }
        return results
    }

    private func convertAmbiguousWord(
        _ word: [Character],
        fromLayout: String,
        toLayout: String,
        candidatesMap: [Character: [(key: String, mod: String)]]?,
        fullMap: [String: [String: KeyMapping]],
        targetLanguage: Language?,
        targetNgram: NgramLanguageModel?
        ,
        targetUnigram: WordFrequencyModel?
    ) -> String? {
        guard let candidatesMap else { return nil }
        guard let targetNgram else { return nil }
        guard !word.isEmpty else { return "" }

        func modPenalty(_ mod: String) -> Double {
            // Prefer mappings without modifiers; avoid alt/option outputs for "word" decoding.
            switch mod {
            case "n": return 0.0
            case "s": return 0.15
            case "a": return 0.65
            case "sa": return 0.80
            default: return 1.0
            }
        }

        // Build per-position candidate output characters with a penalty based on modifiers.
        var perPos: [[(c: Character, penalty: Double)]] = []
        perPos.reserveCapacity(word.count)

        for ch in word {
            let keyCands = candidatesMap[ch] ?? []
            var bestPenaltyByChar: [Character: Double] = [:]
            bestPenaltyByChar.reserveCapacity(max(1, keyCands.count))

            let allowHyphenOutput: Bool = {
                // Hyphen-like graphemes can appear from layout conversions (e.g. RU "где-то" → HE text).
                // When decoding back to the target language, prefer preserving the hyphen over mapping
                // it to a letter from an alternative key candidate.
                let s = String(ch)
                return s == "-" || s == "–" || s == "—" || s == "־"
            }()

            for (key, mod) in keyCands {
                guard let mapping = fullMap[key]?[toLayout] else { continue }
                let targetChar: String?
                switch mod {
                case "n": targetChar = mapping.n
                case "s": targetChar = mapping.s
                case "a": targetChar = mapping.a
                case "sa": targetChar = mapping.sa
                default: targetChar = nil
                }
                if let s = targetChar, s.count == 1, let c = s.first, (c.isLetter || (allowHyphenOutput && c == "-")) {
                    let p = modPenalty(mod)
                    if let existing = bestPenaltyByChar[c] {
                        if p < existing { bestPenaltyByChar[c] = p }
                    } else {
                        bestPenaltyByChar[c] = p
                    }
                }
            }

            if bestPenaltyByChar.isEmpty {
                perPos.append([(c: ch, penalty: 0.0)])
            } else {
                // Deterministic order: lowest penalty first, then lexicographic.
                var opts = bestPenaltyByChar.map { (c: $0.key, penalty: $0.value) }
                opts.sort { (a, b) in
                    if a.penalty != b.penalty { return a.penalty < b.penalty }
                    return a.c < b.c
                }
                perPos.append(opts)
            }
        }

        let maxBrute = 500_000
        let product = perPos.reduce(1) { acc, opts in
            if acc > maxBrute { return acc }
            return acc * max(1, opts.count)
        }

        func fullScore(_ candidate: String) -> Double {
            let lang = targetLanguage
            let unigramHit = targetUnigram?.contains(candidate) ?? false
            let whitelistHit = lang.map { languageData.isWhitelisted(candidate, language: $0) } ?? false
            let wconf: Double = (unigramHit || whitelistHit) ? 1.0 : 0.0
            let freq = targetUnigram?.score(candidate) ?? 0.0
            let ngram = targetNgram.normalizedScore(candidate)
            let isEnglish = lang == .english
            let ngramWeight = candidate.count >= 3 ? (isEnglish ? 0.45 : 0.8) : 0.0
            let freqWeight = candidate.count <= 3 ? (isEnglish ? 1.2 : 0.8) : (isEnglish ? 2.0 : 1.4)
            let builtinBonus: Double
            if let lang, BuiltinLexicon.contains(candidate, language: lang) {
                builtinBonus = candidate.count <= 3 ? 1.2 : 0.6
            } else {
                builtinBonus = 0.0
            }
            let whitelistBonus = whitelistHit ? (candidate.count <= 3 ? 1.4 : 1.0) : 0.0
            return (2.6 * wconf) + (freqWeight * freq) + (ngramWeight * ngram) + builtinBonus + whitelistBonus
        }

        // When ambiguity is limited, brute-force all candidates and choose the best by scoring.
        // (Product is driven only by ambiguous Hebrew-QWERTY duplicates, not word length.)
        if product <= maxBrute {
            var best: (String, Double) = ("", -1e18)

            func rec(_ i: Int, _ buf: inout [Character], _ penaltySum: Double) {
                if i == perPos.count {
                    let candidate = String(buf)
                    let score = fullScore(candidate) - penaltySum
                    if score > best.1 {
                        best = (candidate, score)
                    }
                    return
                }
                for opt in perPos[i] {
                    buf.append(opt.c)
                    rec(i + 1, &buf, penaltySum + opt.penalty)
                    buf.removeLast()
                }
            }

            var buf: [Character] = []
            rec(0, &buf, 0.0)
            return best.0.isEmpty ? nil : best.0
        }

        // Beam search for longer words.
        struct Beam {
            var text: [Character]
            var score: Double
            var penalty: Double
        }

        let ambiguousPositions = perPos.filter { $0.count > 1 }.count
        let beamWidth = min(1024, max(64, 96 * max(1, ambiguousPositions)))
        var beams: [Beam] = [Beam(text: [], score: 0.0, penalty: 0.0)]

        func trigramIncrement(_ prefix: [Character], next: Character) -> Double {
            guard prefix.count >= 2 else { return 0.0 }
            let a = prefix[prefix.count - 2]
            let b = prefix[prefix.count - 1]
            return Double(targetNgram.lookup(a, b, next))
        }

        for opts in perPos {
            var nextBeams: [Beam] = []
            nextBeams.reserveCapacity(beams.count * opts.count)

            for beam in beams {
                for opt in opts {
                    var t = beam.text
                    t.append(opt.c)
                    let inc = trigramIncrement(beam.text, next: opt.c)
                    nextBeams.append(Beam(text: t, score: beam.score + inc, penalty: beam.penalty + opt.penalty))
                }
            }

            nextBeams.sort { $0.score > $1.score }
            if nextBeams.count > beamWidth {
                nextBeams = Array(nextBeams.prefix(beamWidth))
            }
            beams = nextBeams
            if beams.isEmpty { return nil }
        }

        // Evaluate final candidates with full (word + unigram + ngram) scoring.
        var bestFinal: (String, Double) = ("", -1e18)
        for beam in beams {
            let s = String(beam.text)
            let score = fullScore(s) - beam.penalty
            if score > bestFinal.1 {
                bestFinal = (s, score)
            }
        }
        return bestFinal.0.isEmpty ? beams.first.map { String($0.text) } : bestFinal.0
    }
}
