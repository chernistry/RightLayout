import Foundation
import os

public actor UserDictionary {
    private struct UserDictionaryStore: Codable {
        var version: Int = 3
        var rules: [UserDictionaryRule]
    }

    private var rules: [UUID: UserDictionaryRule] = [:]
    private var tokenToId: [String: UUID] = [:]
    private var accessOrder: [UUID] = [] // Last element is most recently used
    
    private let maxRules = 500
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static var isRunningTests: Bool {
        // `swift test` doesn't consistently set a dedicated env var; detect XCTest by presence of its classes.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    private static func resolveStorageURL(customStorageURL: URL?) -> URL {
        if let custom = customStorageURL { return custom }

        // Never read/write the real user dictionary from unit tests.
        if isRunningTests {
            return FileManager.default.temporaryDirectory.appendingPathComponent("rightlayout_user_dictionary_tests.json")
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let rightlayoutDir = home.appendingPathComponent(".rightlayout")
        if !fileManager.fileExists(atPath: rightlayoutDir.path) {
            try? fileManager.createDirectory(at: rightlayoutDir, withIntermediateDirectories: true)
        }
        return rightlayoutDir.appendingPathComponent("user_dictionary.json")
    }
    
    private var storageURL: URL {
        Self.resolveStorageURL(customStorageURL: customStorageURL)
    }
    
    public static let shared = UserDictionary()
    
    private let customStorageURL: URL?
    
    public init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL
        
        // Load synchronously on init
        let url = Self.resolveStorageURL(customStorageURL: storageURL)

        // Ensure a clean slate for test runs to avoid cross-run contamination.
        if Self.isRunningTests, storageURL == nil {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let data = try Data(contentsOf: url)
            let loadedRules = try Self.loadRules(from: data)
            for rule in loadedRules where rule.source == .manual {
                self.rules[rule.id] = rule
                let normalized = rule.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.tokenToId[normalized] = rule.id
                self.accessOrder.append(rule.id)
            }
        } catch {
            // File might not exist or be corrupt, start fresh
        }
    }
    
    // MARK: - Core Operations
    
    public func lookup(_ token: String) -> UserDictionaryRule? {
        let normalized = normalize(token)
        guard let id = tokenToId[normalized], let rule = rules[id] else {
            return nil
        }
        
        touch(id) // Update LRU
        return rule
    }
    
    public func addRule(_ rule: UserDictionaryRule) {
        let normalized = normalize(rule.token)
        
        // If rule exists for token, update it
        if let existingId = tokenToId[normalized] {
            rules[existingId] = rule
            touch(existingId)
        } else {
            // New rule
            if rules.count >= maxRules {
                evictOldest()
            }
            rules[rule.id] = rule
            tokenToId[normalized] = rule.id
            accessOrder.append(rule.id)
        }
        
        save()
    }
    
    public func removeRule(id: UUID) {
        guard let rule = rules[id] else { return }
        let normalized = normalize(rule.token)
        
        rules.removeValue(forKey: id)
        tokenToId.removeValue(forKey: normalized)
        accessOrder.removeAll { $0 == id }
        
        save()
    }
    
    public func clearAll() {
        rules.removeAll()
        tokenToId.removeAll()
        accessOrder.removeAll()
        save()
    }
    
    public func getAllRules() -> [UserDictionaryRule] {
        return rules.values.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    // MARK: - Learning Logic
    
    public func recordAutoReject(token: String, bundleId: String? = nil) {
        let normalized = normalize(token)
        guard let id = tokenToId[normalized], var rule = rules[id], rule.source == .manual else { return }
        rule.evidence.autoRejectCount += 1
        rule.evidence.timestamps.append(Date())
        rule.updatedAt = Date()
        rules[id] = rule
        touch(id)
        save()
    }
    
    public func recordManualApply(token: String, hypothesis: String, convertedText: String? = nil, bundleId: String? = nil) {
        let normalized = normalize(token)
        guard let id = tokenToId[normalized], var rule = rules[id], rule.source == .manual else { return }
        rule.evidence.manualApplyCount += 1
        rule.evidence.timestamps.append(Date())
        rule.updatedAt = Date()
        if case .preferHypothesis = rule.action {
            rule.convertedText = convertedText
        }
        rules[id] = rule
        touch(id)
        save()
    }
    
    public func recordOverride(token: String) {
        let normalized = normalize(token)
        guard let id = tokenToId[normalized], var rule = rules[id] else { return }
        
        // Only unlearn learned rules
        guard rule.source == .learned else { return }
        
        rule.evidence.overrideCount += 1
        rule.updatedAt = Date()
        
        // Check threshold (2+ overrides -> remove)
        if rule.evidence.overrideCount >= 2 {
            removeRule(id: rule.id)
        } else {
            rules[rule.id] = rule
            touch(rule.id)
            save()
        }
    }
    
    // MARK: - Internal Helpers
    
    private func normalize(_ token: String) -> String {
        return token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    private func touch(_ id: UUID) {
        if let index = accessOrder.firstIndex(of: id) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(id)
    }
    
    private func evictOldest() {
        guard let id = accessOrder.first else { return }
        removeRule(id: id)
    }
    
    private func getOrCreateRule(for normalizedToken: String) -> UserDictionaryRule {
        if let id = tokenToId[normalizedToken], let rule = rules[id] {
            return rule
        }
        
        // Create tentative rule (placeholder until learned)
        // Note: We don't save this yet unless it has an action, but for evidence tracking we need to store it.
        // Actually, we should store it to track counts.
        let newRule = UserDictionaryRule(
            token: normalizedToken,
            action: .none, 
            source: .learned,
            evidence: RuleEvidence(),
            updatedAt: Date()
        )
        
        // Add to storage
        if rules.count >= maxRules {
            evictOldest()
        }
        
        rules[newRule.id] = newRule
        tokenToId[normalizedToken] = newRule.id
        accessOrder.append(newRule.id)
        
        return newRule
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let loadedRules = try Self.loadRules(from: data)
            
            rules.removeAll()
            tokenToId.removeAll()
            accessOrder.removeAll()
            
            for rule in loadedRules {
                rules[rule.id] = rule
                tokenToId[normalize(rule.token)] = rule.id
                accessOrder.append(rule.id)
            }
        } catch {
            // File might not exist or be corrupt, start fresh
        }
    }
    
    private func save() {
         do {
            let allRules = Array(rules.values.filter { $0.source == .manual })
            let data = try encoder.encode(UserDictionaryStore(rules: allRules))
            try data.write(to: storageURL)
        } catch {
            print("Failed to save UserDictionary: \(error)")
        }
    }

    private static func loadRules(from data: Data) throws -> [UserDictionaryRule] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let wrapped = try? decoder.decode(UserDictionaryStore.self, from: data) {
            if wrapped.version == 3 {
                return wrapped.rules.filter { $0.source == .manual }
            }
            return wrapped.rules.filter { $0.source == .manual }
        }

        let legacyRules = try decoder.decode([UserDictionaryRule].self, from: data)
        return legacyRules.filter { $0.source == .manual }
    }
}
