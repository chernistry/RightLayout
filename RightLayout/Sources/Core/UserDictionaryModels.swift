import Foundation

public struct UserDictionaryRule: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let token: String                    // normalized token
    public let matchMode: MatchMode             // exact, caseInsensitive
    public let scope: RuleScope                 // global, perApp, perMode
    public let action: RuleAction               // keepAsIs, preferLanguage, preferHypothesis
    public let source: RuleSource               // learned, manual
    public var evidence: RuleEvidence           // counts, timestamps
    public let createdAt: Date
    public var updatedAt: Date
    public var convertedText: String?           // result text for preferHypothesis
    
    public init(id: UUID = UUID(), token: String, matchMode: MatchMode = .caseInsensitive, scope: RuleScope = .global, action: RuleAction, source: RuleSource, evidence: RuleEvidence = RuleEvidence(), createdAt: Date = Date(), updatedAt: Date = Date(), convertedText: String? = nil) {
        self.id = id
        self.token = token
        self.matchMode = matchMode
        self.scope = scope
        self.action = action
        self.source = source
        self.evidence = evidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.convertedText = convertedText
    }
    
    public static func == (lhs: UserDictionaryRule, rhs: UserDictionaryRule) -> Bool {
        return lhs.id == rhs.id
    }
}

public enum MatchMode: String, Codable, Sendable {
    case exact
    case caseInsensitive
}

public enum RuleScope: Codable, Sendable, Equatable {
    case global
    case perApp(bundleId: String)
    
    private enum CodingKeys: String, CodingKey {
        case type, bundleId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "global":
            self = .global
        case "perApp":
            let bundleId = try container.decode(String.self, forKey: .bundleId)
            self = .perApp(bundleId: bundleId)
        default:
            self = .global
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode("global", forKey: .type)
        case .perApp(let bundleId):
            try container.encode("perApp", forKey: .type)
            try container.encode(bundleId, forKey: .bundleId)
        }
    }
}

public enum RuleAction: Codable, Sendable, Equatable {
    case none // For pending learned rules that haven't reached threshold
    case keepAsIs
    case preferLanguage(Language)
    case preferHypothesis(String)
    
    private enum CodingKeys: String, CodingKey {
        case type, language, hypothesis
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "none":
            self = .none
        case "keepAsIs":
            self = .keepAsIs
        case "preferLanguage":
            let language = try container.decode(Language.self, forKey: .language)
            self = .preferLanguage(language)
        case "preferHypothesis":
            let hypothesis = try container.decode(String.self, forKey: .hypothesis)
            self = .preferHypothesis(hypothesis)
        default:
            self = .keepAsIs
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .type)
        case .keepAsIs:
            try container.encode("keepAsIs", forKey: .type)
        case .preferLanguage(let language):
            try container.encode("preferLanguage", forKey: .type)
            try container.encode(language, forKey: .language)
        case .preferHypothesis(let hypothesis):
            try container.encode("preferHypothesis", forKey: .type)
            try container.encode(hypothesis, forKey: .hypothesis)
        }
    }
}

public enum RuleSource: String, Codable, Sendable {
    case learned
    case manual
}

public struct RuleEvidence: Codable, Sendable, Equatable {
    public var autoRejectCount: Int = 0
    public var manualApplyCount: Int = 0
    public var overrideCount: Int = 0
    public var timestamps: [Date] = []
    
    public init() {}
}
