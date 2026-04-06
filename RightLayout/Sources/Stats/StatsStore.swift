import Foundation
import os.log
import CryptoKit

/// Privacy-safe analytics store for the "Insights" dashboard.
/// Aggregates events into local buckets. No raw text is ever stored.
actor StatsStore {
    static let shared = StatsStore()
    
    private let logger = Logger(subsystem: "com.chernistry.rightlayout", category: "StatsStore")
    private let fileManager = FileManager.default
    
    private var state: StatsState = StatsState()
    private var isLoaded = false
    private let storageUrl: URL
    
    /// Debounce logic for writes
    private var saveTask: Task<Void, Never>?
    private let saveDebounce: UInt64 = 5_000_000_000 // 5 seconds
    
    init(customDirectory: URL? = nil) {
        if let custom = customDirectory {
            self.storageUrl = custom.appendingPathComponent("stats_v1.json")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("com.chernistry.rightlayout/Stats")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            self.storageUrl = dir.appendingPathComponent("stats_v1.json")
        }
        
        Task { await load() }
    }
    
    // MARK: - API
    
    func record(_ event: StatsEvent) {
        Task {
            // Check if stats are enabled
            let enabled = await MainActor.run { SettingsManager.shared.isStatsCollectionEnabled }
            guard enabled else { return }
            await process(event)
        }
    }
    
    /// Returns current state for UI rendering
    func getInsights() -> StatsState {
        return state
    }
    
    /// Force reset all statistics
    func reset() {
        state = StatsState()
        save()
    }
    
    // MARK: - Internal Processing
    
    private func process(_ event: StatsEvent) async {
        if !isLoaded {
             // In rare case record is called before load finishes, we could lose it or buffer.
             // For stats, losing one event on cold start is acceptable trade-off for simplicity.
             // Ideally we'd await load() but record is fire-and-forget.
        }
        
        // Fetch privacy mode once at start of processing
        let strictPrivacy = await MainActor.run { SettingsManager.shared.isStrictPrivacyMode }
        
        let now = Date()
        var bucket = getOrCreateBucket(for: now)
        var bucketChanged = false
        
        switch event {
        case .autoFixed(let app, let from, let to):
            bucket.totalFixes += 1
            bucket.autoFixes += 1
            bucket.savedSeconds += 1.5 // Estimated time saved
            countLanguagePair(from: from, to: to, in: &bucket)
            if let id = app { countApp(id, strictMode: strictPrivacy) }
            
            state.allTimeFixes += 1
            state.allTimeSavedSeconds += 1.5
            bucketChanged = true
            
        case .manualHotkey(let app, let from, let to):
            bucket.totalFixes += 1
            bucket.manualFixes += 1
            bucket.savedSeconds += 0.5 // Manual fix is faster than retyping but slower than auto
            countLanguagePair(from: from, to: to, in: &bucket)
            if let id = app { countApp(id, strictMode: strictPrivacy) }
            
            state.allTimeFixes += 1
            state.allTimeSavedSeconds += 0.5
            bucketChanged = true
            
        case .undo:
            bucket.undos += 1
            state.allTimeUndos += 1
            // We don't decrement totalFixes (to track activity), but we revert the saved time credit
            // Assuming average fix time for the undone action.
            // Since we don't track *which* fix was undone, we subtract the default AutoFix time (1.5s).
            bucket.savedSeconds = max(0, bucket.savedSeconds - 1.5)
            state.allTimeSavedSeconds = max(0, state.allTimeSavedSeconds - 1.5)
            
            bucketChanged = true
            
        case .cycledSelection:
            // Just usage tracking if needed
            break
            
        case .skippedForSecureIntent:
            break
            
        case .secureInputPaused:
            break
        }
        
        if bucketChanged {
            updateBucket(bucket)
            checkAchievements()
            scheduleSave()
        }
    }
    
    private func countLanguagePair(from: Language, to: Language, in bucket: inout StatsDayBucket) {
        let key = "\(from.rawValue)_\(to.rawValue)"
        bucket.languagePairs[key, default: 0] += 1
    }
    
    private func countApp(_ bundleId: String, strictMode: Bool) {
        let key: String
        if strictMode {
            // Simple hash (first 12 hex chars of SHA256)
            let input = bundleId.data(using: .utf8)!
            let hashed = SHA256.hash(data: input)
            key = hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(12).map { String($0) }.joined()
        } else {
            key = bundleId
        }
        
        state.topApps[key, default: 0] += 1
        
        // Evict if too many apps (Privacy/Size)
        if state.topApps.count > 50 {
            // Remove smallest
            if let min = state.topApps.min(by: { $0.value < $1.value }) {
                state.topApps.removeValue(forKey: min.key)
            }
        }
    }
    
    // MARK: - Buckets Management
    
    private func getOrCreateBucket(for date: Date) -> StatsDayBucket {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        if let existing = state.history.first(where: { calendar.isDate($0.date, inSameDayAs: startOfDay) }) {
            return existing
        }
        
        return StatsDayBucket(date: startOfDay)
    }
    
    private func updateBucket(_ bucket: StatsDayBucket) {
        if let idx = state.history.firstIndex(where: { $0.date == bucket.date }) {
            state.history[idx] = bucket
        } else {
            state.history.append(bucket)
            // Sort by date desc? Or keep chronological?
            // Usually append is chronological if we are reliable.
            // But verify:
            state.history.sort(by: { $0.date > $1.date }) // Newest first
        }
        
        // Retention Policy: Keep 180 days
        if state.history.count > 180 {
            state.history = Array(state.history.prefix(180))
        }
    }
    
    // MARK: - Achievements
    
    private func checkAchievements() {
        // Simple checks
        if state.allTimeFixes >= 1 && !state.unlockedBadges.contains("first_fix") {
            unlock("first_fix")
        }
        if state.allTimeFixes >= 1000 && !state.unlockedBadges.contains("1k_fixes") {
             unlock("1k_fixes")
        }
        
        // Polyglot: Check if we have 3 unique FROM languages in history buckets?
        // Or aggregate all time pairs.
        // This is expensive to scan history every event.
        // Do it probabilistically or only on certain milestones.
    }
    
    private func unlock(_ id: String) {
        state.unlockedBadges.insert(id)
        // In future: Notify UI
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageUrl.path) else {
            isLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: storageUrl)
            state = try JSONDecoder().decode(StatsState.self, from: data)
        } catch {
            logger.error("Failed to load stats: \(error.localizedDescription)")
            // Start fresh if corrupted
            state = StatsState()
        }
        isLoaded = true
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounce)
            guard !Task.isCancelled else { return }
            save()
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: storageUrl, options: .atomic)
        } catch {
            logger.error("Failed to save stats: \(error.localizedDescription)")
        }
    }
}
