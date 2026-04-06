import Foundation

struct BioEvent: Sendable {
    let timestamp: TimeInterval
    let isBackspace: Bool
    let isChar: Bool
}

/// Extracts Keystroke Dynamics (biometrics) from a stream of typing events.
/// Computes privacy-safe aggregates like WPM, Flight Time Variance, and Backspace Ratio.
actor BioFeatureExtractor {
    
    // MARK: - Configuration
    
    private let windowSize: Int = 15 // Last 15 keystrokes for "instant" analytics
    
    // MARK: - State
    
    private var events: [BioEvent] = []
    
    // MARK: - API
    
    func register(event: BioEvent) {
        events.append(event)
        if events.count > windowSize {
            events.removeFirst(events.count - windowSize)
        }
    }
    
    func extract() -> BioFeatures? {
        // Need min data to be statistically useful
        guard events.count >= 5 else { return nil }
        
        let now = events.last?.timestamp ?? Date().timeIntervalSince1970
        let recentEvents = events // Actor isolation makes this safe copy
        
        let wpm = calculateWPM(events: recentEvents, now: now)
        let flightTimeVar = calculateFlightTimeVariance(events: recentEvents)
        let backspaceRatio = calculateBackspaceRatio(events: recentEvents)
        
        return BioFeatures(
            wpm: wpm,
            flightTimeVar: flightTimeVar,
            backspaceRatio: backspaceRatio
        )
    }
    
    // MARK: - Logic
    
    private func calculateWPM(events: [BioEvent], now: TimeInterval) -> Double {
        guard let first = events.first else { return 0 }
        let duration = now - first.timestamp
        if duration < 1.0 { return 0 } // Avoid huge spikes
        
        let charCount = Double(events.filter { $0.isChar }.count)
        // Std def: 5 chars = 1 word
        let words = charCount / 5.0
        let minutes = duration / 60.0
        
        return min(200.0, words / minutes) // Cap at 200 to remove noise
    }
    
    private func calculateFlightTimeVariance(events: [BioEvent]) -> Double {
        var flightTimes: [Double] = []
        
        for i in 1..<events.count {
            let flight = events[i].timestamp - events[i-1].timestamp
            // Filter out pauses > 2 seconds (thinking time, not typing rhythm)
            if flight < 2.0 {
                flightTimes.append(flight)
            }
        }
        
        guard flightTimes.count > 2 else { return 0 }
        
        let mean = flightTimes.reduce(0, +) / Double(flightTimes.count)
        let variance = flightTimes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(flightTimes.count)
        
        return variance
    }
    
    private func calculateBackspaceRatio(events: [BioEvent]) -> Double {
        let total = Double(events.count)
        let backspaces = Double(events.filter { $0.isBackspace }.count)
        return backspaces / total
    }
}
