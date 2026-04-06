import Foundation
import NaturalLanguage

public enum Language: String, CaseIterable, Sendable, Codable {
    case english = "en"
    case russian = "ru"
    case hebrew = "he"
    
    var nlLanguage: NLLanguage {
        switch self {
        case .english: return .english
        case .russian: return .russian
        case .hebrew: return .hebrew
        }
    }
}
