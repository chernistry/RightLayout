import Foundation

/// Backward-compatible wrapper - delegates to LanguageDataConfig
public struct LanguageMappingsConfig: Sendable {
    public static let shared = LanguageMappingsConfig()
    
    public var russianPrepositions: [String: String] { LanguageDataConfig.shared.russianPrepositions }
    public var hebrewCommonShortWords: Set<String> { LanguageDataConfig.shared.hebrewCommonShortWords }
    public var languageConversions: [(from: Language, to: Language)] { LanguageDataConfig.shared.languageConversions }
    
    private init() {}
}
