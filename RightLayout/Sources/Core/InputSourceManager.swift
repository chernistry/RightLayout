import Foundation
import Carbon
import os.log

@MainActor
final class InputSourceManager {
    static let shared = InputSourceManager()
    
    private let logger = Logger.inputSource

    struct InstalledLayoutVariant: Identifiable, Hashable {
        let layoutId: String
        let appleId: String
        let displayName: String
        let languageCode: String

        var id: String { layoutId }
    }
    
    /// Maps macOS layout IDs to our layout IDs (must match layouts.json)
    private let macOSToLayoutID: [String: String] = [
        // Russian
        "com.apple.keylayout.Russian": "russian",
        "com.apple.keylayout.RussianWin": "russianwin",
        "com.apple.keylayout.Russian-Phonetic": "russian_phonetic",
        "com.apple.keylayout.Byelorussian": "byelorussian",
        "com.apple.keylayout.Ingush": "ingush",
        // Hebrew
        "com.apple.keylayout.Hebrew": "hebrew",
        "com.apple.keylayout.Hebrew-QWERTY": "hebrew_qwerty",
        "com.apple.keylayout.Hebrew-PC": "hebrew_pc",
        // English
        "com.apple.keylayout.US": "us",
        "com.apple.keylayout.ABC": "abc",
        "com.apple.keylayout.British": "british",
        "com.apple.keylayout.British-PC": "british_pc",
        "com.apple.keylayout.Australian": "australian",
        "com.apple.keylayout.Austrian": "austrian",
        "com.apple.keylayout.Canadian": "canadian",
        "com.apple.keylayout.Canadian-CSA": "canadian_csa",
        "com.apple.keylayout.CanadianFrench-PC": "canadianfrench_pc",
        "com.apple.keylayout.Irish": "irish",
        "com.apple.keylayout.Colemak": "colemak",
        "com.apple.keylayout.Dvorak": "dvorak",
        "com.apple.keylayout.Dvorak-Left": "dvorak_left",
        "com.apple.keylayout.Dvorak-Right": "dvorak_right",
        "com.apple.keylayout.DVORAK-QWERTYCMD": "dvorak_qwertycmd",
        "com.apple.keylayout.USInternational-PC": "usinternational_pc",
    ]
    
    private init() {
        logger.info("InputSourceManager initialized")
    }

    /// Switches to an input source that matches our internal layout ID (as used in `layouts.json`),
    /// e.g. "russian_phonetic", "hebrew_qwerty", "us".
    ///
    /// Returns `true` if a matching enabled layout was found and selected.
    @discardableResult
    func switchToLayoutVariant(_ layoutId: String) -> Bool {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]

        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.warning("Failed to get input source list for variant switch")
            return false
        }

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let macOSID = unsafeBitCast(idPtr, to: CFString.self) as String

            guard macOSToLayoutID[macOSID] == layoutId else { continue }

            let status = TISSelectInputSource(source)
            if status == noErr {
                logger.info("✅ Switched input source to layout variant: \(layoutId, privacy: .public)")
                return true
            } else {
                logger.error("❌ Failed to select input source for layout variant \(layoutId, privacy: .public), OSStatus: \(status)")
                return false
            }
        }

        logger.warning("No matching input source found for layout variant: \(layoutId, privacy: .public)")
        return false
    }

    /// Detects all installed keyboard layouts and returns our layout IDs
    func detectInstalledLayouts() -> [String: String] {
        var best: [String: (id: String, score: Int)] = [
            "en": ("us", 0),
            "ru": ("russianwin", 0),
            "he": ("hebrew", 0)
        ]

        // Prefer "most likely user" variants when multiple layouts exist.
        // Higher score wins.
        let layoutInfo: [String: (lang: String, score: Int)] = [
            // English
            "us": ("en", 300),
            "abc": ("en", 200),
            "british": ("en", 180),
            "british_pc": ("en", 170),
            "australian": ("en", 160),
            "austrian": ("en", 155),
            "canadian": ("en", 150),
            "canadian_csa": ("en", 145),
            "canadianfrench_pc": ("en", 140),
            "irish": ("en", 135),
            "colemak": ("en", 120),
            "dvorak": ("en", 120),
            "dvorak_left": ("en", 115),
            "dvorak_right": ("en", 115),
            "dvorak_qwertycmd": ("en", 115),
            "usinternational_pc": ("en", 110),

            // Russian
            "russianwin": ("ru", 300),
            "russian": ("ru", 250),
            "russian_phonetic": ("ru", 200),
            "byelorussian": ("ru", 150),
            "ingush": ("ru", 120),

            // Hebrew
            "hebrew_qwerty": ("he", 300),
            "hebrew_pc": ("he", 200),
            "hebrew": ("he", 150)
        ]
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.warning("Failed to get input source list")
            return Dictionary(uniqueKeysWithValues: best.map { ($0.key, $0.value.id) })
        }
        
        for i in 0..<CFArrayGetCount(list) {
            guard let src = CFArrayGetValueAtIndex(list, i) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let macOSID = unsafeBitCast(idPtr, to: CFString.self) as String
            
            if let ourID = macOSToLayoutID[macOSID] {
                if let info = layoutInfo[ourID] {
                    let current = best[info.lang]?.score ?? Int.min
                    if info.score > current {
                        best[info.lang] = (ourID, info.score)
                        logger.info("Detected \(info.lang, privacy: .public) layout: \(ourID, privacy: .public)")
                    }
                }
            }
        }
        
        return Dictionary(uniqueKeysWithValues: best.map { ($0.key, $0.value.id) })
    }

    /// Returns installed keyboard layout variants (restricted to layouts RightLayout knows about), grouped by language code.
    func installedLayoutVariantsByLanguage() -> [String: [InstalledLayoutVariant]] {
        // Keep scoring consistent with `detectInstalledLayouts()`.
        let layoutInfo: [String: (lang: String, score: Int)] = [
            // English
            "us": ("en", 300),
            "abc": ("en", 200),
            "british": ("en", 180),
            "british_pc": ("en", 170),
            "australian": ("en", 160),
            "austrian": ("en", 155),
            "canadian": ("en", 150),
            "canadian_csa": ("en", 145),
            "canadianfrench_pc": ("en", 140),
            "irish": ("en", 135),
            "colemak": ("en", 120),
            "dvorak": ("en", 120),
            "dvorak_left": ("en", 115),
            "dvorak_right": ("en", 115),
            "dvorak_qwertycmd": ("en", 115),
            "usinternational_pc": ("en", 110),

            // Russian
            "russianwin": ("ru", 300),
            "russian": ("ru", 250),
            "russian_phonetic": ("ru", 200),
            "byelorussian": ("ru", 150),
            "ingush": ("ru", 120),

            // Hebrew
            "hebrew_qwerty": ("he", 300),
            "hebrew_pc": ("he", 200),
            "hebrew": ("he", 150),
        ]

        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]

        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return [:]
        }

        var grouped: [String: [InstalledLayoutVariant]] = [:]

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let appleId = unsafeBitCast(idPtr, to: CFString.self) as String

            guard let layoutId = macOSToLayoutID[appleId] else { continue }
            guard let info = layoutInfo[layoutId] else { continue }

            var displayName = layoutId
            if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                displayName = unsafeBitCast(namePtr, to: CFString.self) as String
            }

            grouped[info.lang, default: []].append(
                InstalledLayoutVariant(
                    layoutId: layoutId,
                    appleId: appleId,
                    displayName: displayName,
                    languageCode: info.lang
                )
            )
        }

        // De-dupe by internal layoutId and sort by likelihood + name.
        for (lang, variants) in grouped {
            var seen: Set<String> = []
            let deduped = variants.filter { seen.insert($0.layoutId).inserted }
            grouped[lang] = deduped.sorted { lhs, rhs in
                let lScore = layoutInfo[lhs.layoutId]?.score ?? 0
                let rScore = layoutInfo[rhs.layoutId]?.score ?? 0
                if lScore != rScore { return lScore > rScore }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }

        return grouped
    }
    
    func currentLanguage() -> Language? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            logger.warning("Failed to get current input source")
            return nil
        }
        
        guard let langsPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            logger.warning("Failed to get input source languages property")
            return nil
        }
        
        let langsUnmanaged = unsafeBitCast(langsPointer, to: CFArray.self)
        let langs = langsUnmanaged as [AnyObject]
        guard let tag = langs.first as? String else {
            logger.warning("Failed to extract language tag")
            return nil
        }
        
        logger.info("Current input source language tag: \(tag, privacy: .public)")
        
        if tag.hasPrefix("ru") {
            logger.info("Current layout: Russian")
            return .russian
        }
        if tag.hasPrefix("he") {
            logger.info("Current layout: Hebrew")
            return .hebrew
        }
        if tag.hasPrefix("en") {
            logger.info("Current layout: English")
            return .english
        }
        
        logger.warning("Unrecognized language tag: \(tag, privacy: .public)")
        return nil
    }
    
    func switchTo(language: Language) {
        let langCode = language.rawValue
        logger.info("🔄 === SWITCHING INPUT SOURCE ===")
        logger.info("Target language: \(langCode, privacy: .public)")
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.error("❌ Failed to get input source list")
            return
        }
        
        let count = CFArrayGetCount(list)
        logger.info("Found \(count) input sources")
        
        var availableSources: [String] = []
        
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            guard let langsPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
                continue
            }
            let langsUnmanaged = unsafeBitCast(langsPointer, to: CFArray.self)
            let langsCount = CFArrayGetCount(langsUnmanaged)
            var tags: [String] = []
            for i in 0..<langsCount {
                if let langPtr = CFArrayGetValueAtIndex(langsUnmanaged, i) {
                    let str = unsafeBitCast(langPtr, to: CFString.self) as String
                    tags.append(str)
                }
            }
            
            let tagsStr = tags.joined(separator: ", ")
            availableSources.append(tagsStr)
            logger.debug("Source \(index): [\(tagsStr, privacy: .public)]")
            
            if tags.contains(where: { $0.hasPrefix(langCode) }) {
                logger.info("✅ Found matching source: [\(tagsStr, privacy: .public)]")
                let status = TISSelectInputSource(source)
                if status == noErr {
                    logger.info("✅ Successfully switched to \(langCode, privacy: .public)")
                } else {
                    logger.error("❌ Failed to select input source for \(langCode, privacy: .public), OSStatus: \(status)")
                }
                return
            }
        }
        
        logger.error("❌ No input source found for language: \(langCode, privacy: .public)")
        logger.error("Available sources: \(availableSources.joined(separator: " | "), privacy: .public)")
    }
    
    /// Returns the Apple ID of the currently selected input source
    func currentLayoutId() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return unsafeBitCast(idPtr, to: CFString.self) as String
    }
    
    /// Switches to a specific input source by its Apple ID
    func switchToLayoutId(_ appleId: String) {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return
        }
        
        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceId = unsafeBitCast(idPtr, to: CFString.self) as String
            if sourceId == appleId {
                TISSelectInputSource(source)
                return
            }
        }
    }
}
