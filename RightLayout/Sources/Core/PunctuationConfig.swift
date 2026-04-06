import Foundation

/// Backward-compatible wrapper - delegates to LanguageDataConfig
public struct PunctuationConfig: Sendable {
    public static let shared = PunctuationConfig()
    
    public var wordBoundary: Set<Character> { LanguageDataConfig.shared.wordBoundary }
    public var sentenceEnding: Set<Character> { LanguageDataConfig.shared.sentenceEnding }
    public var leadingDelimiters: Set<Character> { LanguageDataConfig.shared.leadingDelimiters }
    public var trailingDelimiters: Set<Character> { LanguageDataConfig.shared.trailingDelimiters }
    
    private init() {}
}
