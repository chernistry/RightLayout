import Foundation

/// Mock n-gram data for testing
/// Real trained models will be added in ticket 11
struct MockNgramData {
    
    // MARK: - Russian Trigrams
    
    /// Common Russian trigrams with log-probabilities
    /// These are hand-crafted to support test cases like "привет"
    static let russianTrigrams: [UInt64: Float] = {
        var dict: [UInt64: Float] = [:]
        
        // "привет" trigrams - make these very strong
        dict[hash("п", "р", "и")] = -1.5
        dict[hash("р", "и", "в")] = -1.3
        dict[hash("и", "в", "е")] = -1.4
        dict[hash("в", "е", "т")] = -1.5
        
        // "мир" trigrams
        dict[hash("м", "и", "р")] = -1.8
        
        // "да" partial
        dict[hash("д", "а", " ")] = -2.5
        
        // Common Russian sequences - make these strong too
        dict[hash("с", "т", "о")] = -1.8
        dict[hash("т", "о", "в")] = -1.9
        dict[hash("е", "н", "и")] = -1.7
        dict[hash("н", "и", "е")] = -1.8
        dict[hash("в", "о", "т")] = -2.0
        dict[hash("о", "т", " ")] = -2.2
        
        // Additional common trigrams to boost Russian scoring
        dict[hash("о", "в", "а")] = -1.9
        dict[hash("и", "я", " ")] = -2.0
        dict[hash("л", "и", " ")] = -2.1
        
        return dict
    }()
    
    // MARK: - English Trigrams
    
    /// Common English trigrams with log-probabilities
    static let englishTrigrams: [UInt64: Float] = {
        var dict: [UInt64: Float] = [:]
        
        // "hello" trigrams
        dict[hash("h", "e", "l")] = -2.1
        dict[hash("e", "l", "l")] = -1.7
        dict[hash("l", "l", "o")] = -2.0
        
        // "world" trigrams
        dict[hash("w", "o", "r")] = -2.2
        dict[hash("o", "r", "l")] = -2.0
        dict[hash("r", "l", "d")] = -2.1
        
        // "ok" partial
        dict[hash("o", "k", " ")] = -2.5
        
        // Common English sequences
        dict[hash("t", "h", "e")] = -1.5
        dict[hash("i", "n", "g")] = -1.8
        dict[hash("a", "n", "d")] = -1.9
        dict[hash("t", "i", "o")] = -2.0
        dict[hash("a", "t", "i")] = -2.1
        
        return dict
    }()
    
    // MARK: - Hebrew Trigrams
    
    /// Common Hebrew trigrams with log-probabilities
    static let hebrewTrigrams: [UInt64: Float] = {
        var dict: [UInt64: Float] = [:]
        
        // "שלום" (shalom) trigrams - make these very strong
        dict[hash("ש", "ל", "ו")] = -1.5
        dict[hash("ל", "ו", "ם")] = -1.4
        
        // "עולם" (olam) trigrams
        dict[hash("ע", "ו", "ל")] = -1.8
        dict[hash("ו", "ל", "ם")] = -1.7
        
        // "כן" partial
        dict[hash("כ", "ן", " ")] = -2.5
        
        // Common Hebrew sequences - make these strong
        dict[hash("ה", "י", "ה")] = -1.8
        dict[hash("ל", "א", " ")] = -2.0
        dict[hash("ש", "ל", " ")] = -1.9
        
        // Additional common trigrams
        dict[hash("א", "ת", " ")] = -2.0
        dict[hash("מ", "ה", " ")] = -2.1
        dict[hash("ב", "ר", " ")] = -2.2
        
        return dict
    }()
    
    // MARK: - Helper
    
    private static func hash(_ c1: String, _ c2: String, _ c3: String) -> UInt64 {
        return NgramLanguageModel.trigramHash(
            Character(c1),
            Character(c2),
            Character(c3)
        )
    }
}
