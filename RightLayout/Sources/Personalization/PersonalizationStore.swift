import Foundation

struct PersonalizationState: Codable, Sendable {
    var version: Int = 3
    /// Map of [ContextHash -> [Layout: Score]]
    /// Used for Strategy A (Priors)
    /// Map of [ContextHash -> [Layout: Score]]
    /// Used for Strategy A (Priors)
    var contextPriors: [Int: [String: Double]] = [:]
    
    /// Last time decay was applied
    var lastDecayDate: Date?
    
    /// Total number of learning events (updates processed)
    var totalLearningEvents: Int = 0
    
    // Future expansion for Strategy B
}

public actor PersonalizationStore {
    
    // MARK: - API
    
    public static let shared = PersonalizationStore()

    // MARK: - State
    
    private var state: PersonalizationState
    private let fileURL: URL
    private var isLoaded: Bool = false
    
    // MARK: - Init

    private static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
    
    init(fileManager: FileManager = .default, customDirectory: URL? = nil) {
        let storeDir: URL
        if let custom = customDirectory {
            storeDir = custom
        } else if Self.isRunningTests {
            storeDir = fileManager.temporaryDirectory.appendingPathComponent("rightlayout_personalization_tests", isDirectory: true)
        } else {
            // Construct path: ~/Library/Application Support/com.chernistry.rightlayout/Personalization/store.json
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("com.chernistry.rightlayout")
            storeDir = appDir.appendingPathComponent("Personalization")
        }
        self.fileURL = storeDir.appendingPathComponent("store.json")
        
        // Load or create default
        self.state = PersonalizationState() // Default empty

        // Ensure clean slate for test runs to avoid cross-run contamination.
        if Self.isRunningTests, customDirectory == nil {
            try? fileManager.removeItem(at: fileURL)
        }

        try? fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        self.state = Self.loadState(from: fileURL)
        self.isLoaded = true
    }
    
    // MARK: - API
    
    func getPriors(for contextHash: Int) -> [String: Double] {
        return state.contextPriors[contextHash] ?? [:]
    }
    
    func updatePriors(for contextHash: Int, layout: String, delta: Double) {
        var priors = state.contextPriors[contextHash] ?? [:]
        let current = priors[layout] ?? 0.0
        priors[layout] = current + delta
        state.contextPriors[contextHash] = priors
        
        state.totalLearningEvents += 1
        
        // Debounced save could be added here, for now just save
        save()
    }
    
    func reset() {
        state = PersonalizationState()
        save()
    }
    
    /// Returns statistics for the Settings UI
    func getStats() -> (contexts: Int, events: Int) {
        return (state.contextPriors.count, state.totalLearningEvents)
    }
    
    /// Applies exponential decay to all priors to allow forgetting old habits.
    /// Should be called on app launch or periodically.
    public func applyDecay() {
        let now = Date()
        let lastUpdate = state.lastDecayDate ?? now
        let daysPassed = now.timeIntervalSince(lastUpdate) / (24 * 3600)
        
        // Decay half-life: 14 days
        // Formula: N(t) = N0 * exp(-lambda * t)
        // lambda = ln(2) / half_life
        let halfLifeDays = 14.0
        let lambda = log(2.0) / halfLifeDays
        let decayFactor = exp(-lambda * daysPassed)
        
        // Apply decay if significant time passed (e.g. > 1 hour)
        if daysPassed > (1.0 / 24.0) {
            for (context, priors) in state.contextPriors {
                var newPriors = priors
                for (layout, score) in priors {
                    // Decay towards 0
                    newPriors[layout] = score * decayFactor
                }
                state.contextPriors[context] = newPriors
            }
            state.lastDecayDate = now
            save()
            print("[Personalization] Applied decay (factor: \(decayFactor))")
        }
    }
    
    /// Only for testing: wait until the store has finished its initial load
    func waitForReady() async {
        while !isLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
            await Task.yield()
        }
    }
    
    /// Only for testing: wait for background save to finish
    func waitForSave() async {
       await flush()
    }

    // MARK: - Persistence
    
    private static func loadState(from fileURL: URL) -> PersonalizationState {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return PersonalizationState() }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PersonalizationState.self, from: data)
            guard decoded.version == 3 else {
                try? FileManager.default.removeItem(at: fileURL)
                return PersonalizationState()
            }
            return decoded
        } catch {
            print("[PersonalizationStore] Failed to load state: \(error)")
        }
        return PersonalizationState()
    }
    
    private var pendingSaveTask: Task<Void, Error>?
    
    private func save() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            // Debounce for 2 seconds to batch updates during rapid typing
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try Task.checkCancellation()
            await self.performSave()
        }
    }
    
    private func performSave() async {
        do {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            
            // Atomic write
            let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("store.tmp")
            try data.write(to: tempURL, options: .atomic)
             
            // Rename
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            print("[PersonalizationStore] Failed to save state: \(error)")
        }
    }
    
    /// Force immediate save (for tests/shutdown)
    func flush() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        await performSave()
    }
}
