import Foundation
import os.log

/// Actions the adapter can score
enum AdapterAction: String, Codable, Sendable {
    case correctToEn = "en"
    case correctToRu = "ru"
    case correctToHe = "he"
}

/// An Online Linear Model (Adapter) using SGD.
/// Predicts the likelihood of a correction being accepted based on hashed features.
/// Replaces the previous "BanditSolver".
actor OnlineAdapter {
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "OnlineAdapter")
    
    // MARK: - State
    
    /// Weights state for FTRL
    /// Key: Context Key Hash (from hierarchical features)
    /// Value: Map of [FeatureHash: FTRLState]
    private var weights: [String: [UInt64: FTRLWeights]] = [:]
    
    struct FTRLWeights: Codable, Sendable {
        /// Accumulated gradient (interaction strength)
        var z: Float = 0.0
        /// Accumulated squared gradient (variance/uncertainty)
        var n: Float = 0.0
    }

    private struct OnlineAdapterStore: Codable, Sendable {
        var version: Int = 3
        var weights: [String: [UInt64: FTRLWeights]] = [:]
    }

    private static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
    
    // Shared singleton for app-wide access
    static let shared = OnlineAdapter()
    
    private let fileURL: URL
    
    // Hyperparameters (Ticket 44: Calibration)
    private let alpha: Float = 0.1   // Learning Rate base
    private let beta: Float = 1.0    // Stabilization constant
    private let l1: Float = 0.05     // L1 regularization (Sparsity)
    private let l2: Float = 0.5      // L2 regularization (Prevention of large weights)
    
    // Feature budgeting (LRU-like cap)
    private let maxFeaturesPerAction = 10000
    
    // MARK: - Init
    
    init(fileManager: FileManager = .default, customDirectory: URL? = nil) {
        let storeDir: URL
        if let custom = customDirectory {
            storeDir = custom
        } else if Self.isRunningTests {
            storeDir = fileManager.temporaryDirectory.appendingPathComponent("rightlayout_adapter_tests", isDirectory: true)
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            storeDir = appSupport.appendingPathComponent("com.chernistry.rightlayout/Personalization")
        }
        self.fileURL = storeDir.appendingPathComponent("adapter_weights_v4.json")

        if Self.isRunningTests, customDirectory == nil {
            try? fileManager.removeItem(at: fileURL)
        }

        try? fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        self.weights = Self.loadWeights(from: fileURL, logger: logger)
    }
    
    // MARK: - API
    
    /// Predicts the score (logit delta) for a given action.
    /// Returns a value in [-0.3, 0.3] range to avoid corrupting confidence.
    func predict(action: AdapterAction, features: PersonalFeatures) -> Float {
        let activeFeatures = hashFeatures(features)
        var dotProduct: Float = 0.0
        var totalEvidence: Float = 0.0
        
        guard let actionWeights = weights[action.rawValue] else { return 0.0 }
        
        // Cold start check: If we don't have enough evidence, return neutral
        // This prevents untrained/corrupted weights from affecting confident decisions
        let minEvidenceRequired: Float = 50.0
        
        for feat in activeFeatures {
            if let w = actionWeights[feat] {
                totalEvidence += w.n
                
                // Calculate weight using FTRL formula
                let z = w.z
                if abs(z) <= l1 {
                    continue
                }
                
                let signZ: Float = z > 0 ? 1.0 : -1.0
                let n = w.n
                let eta = alpha / (beta + sqrt(n))
                let weight = -1.0 * (1.0 / eta) * (z - signZ * l1) / (l2 + (1.0 / eta))
                
                // Clamp individual weight contribution to prevent extreme values
                let clampedWeight = max(-1.0, min(1.0, weight))
                dotProduct += clampedWeight
            }
        }
        
        // If not enough evidence accumulated, return neutral (don't affect confidence)
        if totalEvidence < minEvidenceRequired {
            return 0.0
        }
        
        // Clamp final output to sane range for confidence adjustment
        return max(-0.3, min(0.3, dotProduct))
    }
    
    /// Updates the model based on reward signal (FTRL-Proximal).
    func update(action: AdapterAction, features: PersonalFeatures, reward: Float) {
        let activeFeatures = hashFeatures(features)
        
        // 1. Get current prediction (before update)
        let prediction = predict(action: action, features: features)
        
        // 2. Calculate Gradient (MSE Loss)
        // dL/dw = (p - y) * x_i
        // For linear model, this is just error term for active features
        let error = prediction - reward
        let gradient = max(-2.0, min(2.0, error)) // Gradient clipping
        
        var actionWeights = weights[action.rawValue] ?? [:]
        
        for featHash in activeFeatures {
            var w = actionWeights[featHash] ?? FTRLWeights()
            
            let g = gradient // x_i is 1.0 implies gradient is just error
            let sigma = (sqrt(w.n + g * g) - sqrt(w.n)) / alpha
            
            w.z += g - sigma * self.getWeight(w) 
            w.n += g * g
            
            actionWeights[featHash] = w
        }
        
        // Feature Budgeting (Simple Cap)
        if actionWeights.count > maxFeaturesPerAction {
            // Remove features with smallest N (least recently meaningful)
             // This is expensive, so do it probabilistically or rarely
             if Int.random(in: 0...100) == 0 {
                 let sorted = actionWeights.sorted(by: { $0.value.n > $1.value.n })
                 let kept = sorted.prefix(maxFeaturesPerAction / 2) // Aggressive pruning
                 actionWeights = Dictionary(uniqueKeysWithValues: Array(kept))
             }
        }
        
        weights[action.rawValue] = actionWeights
        
        Task { save() }
    }
    
    // Helper to get weight from state (for update step)
    private func getWeight(_ w: FTRLWeights) -> Float {
        let z = w.z
        if abs(z) <= l1 { return 0.0 }
        let signZ: Float = z > 0 ? 1.0 : -1.0
        let eta = alpha / (beta + sqrt(w.n))
        return -1.0 * (1.0 / eta) * (z - signZ * l1) / (l2 + (1.0 / eta))
    }
    
    // MARK: - Reset
    
    func reset() {
        weights.removeAll()
        Task { save() }
    }
    
    // MARK: - Feature Hashing (Hierarchical)
    
    private func hashFeatures(_ f: PersonalFeatures) -> [UInt64] {
        var hashes: [UInt64] = []
        
        // Bias is handled by implicit feature 0
        hashes.append(0)
        
        // Hierarchy Keys (Ticket 44)
        // We treat each context level as a separate feature space by offsetting
        
        // Level 1: Global (Bias + N-grams)
        let globalOffset: UInt64 = 0
        for ngram in f.ngramHashes {
             hashes.append(globalOffset + UInt64(ngram))
        }
        
        // Level 2: App (Bias + N-grams)
        // We mix app hash into the feature ID
        let appSeed = UInt64(bitPattern: Int64(f.contextKey.app))
        hashes.append(appSeed) // App Bias
        // We don't replicate all n-grams per app to save memory, just bias
        
        // Level 3: App+Intent (Bias)
        let intentSeed = UInt64(bitPattern: Int64(f.contextKey.appIntent))
        hashes.append(intentSeed)
        
        // Level 4: App+Time (Bias)
        let timeSeed = UInt64(bitPattern: Int64(f.contextKey.appTime))
        hashes.append(timeSeed)
        
        return hashes
    }
    
    // MARK: - Persistence
    
    private static func loadWeights(from fileURL: URL, logger: Logger) -> [String: [UInt64: FTRLWeights]] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(OnlineAdapterStore.self, from: data),
               decoded.version == 3 {
                logger.info("Loaded V4 weights: \(decoded.weights.count) actions")
                return decoded.weights
            }

            logger.info("Resetting legacy adapter state")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Failed to load weights: \(error.localizedDescription)")
        }
        return [:]
    }
    
    private func save() {
         let snapshot = weights // Capture state
         Task {
            do {
                try? FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                let data = try encoder.encode(OnlineAdapterStore(weights: snapshot))
                let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("adapter_weights_v4.tmp")
                try data.write(to: tempURL, options: .atomic)
                
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            } catch {
                self.logger.error("Failed to save weights: \(error.localizedDescription)")
            }
         }
    }
}
