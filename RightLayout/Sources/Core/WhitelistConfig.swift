import Foundation

/// Backward-compatible wrapper - delegates to LanguageDataConfig
public struct WhitelistConfig: Sendable {
    public static let shared = WhitelistConfig()
    
    public var english: Set<String> { LanguageDataConfig.shared.whitelistEnglish }
    public var russian: Set<String> { LanguageDataConfig.shared.whitelistRussian }
    public var hebrew: Set<String> { LanguageDataConfig.shared.whitelistHebrew }
    
    private init() {}
    
    public func isWhitelisted(_ text: String, language: Language) -> Bool {
        LanguageDataConfig.shared.isWhitelisted(text, language: language)
    }
    
    public func whitelistedLanguage(_ text: String) -> Language? {
        LanguageDataConfig.shared.whitelistedLanguage(text)
    }
}
