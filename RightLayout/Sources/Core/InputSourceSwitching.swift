import Foundation

/// Protocol for input source switching, enabling testability.
/// Production uses InputSourceManager.shared, tests use MockInputSourceSwitcher.
protocol InputSourceSwitching: Sendable {
    func switchTo(language: Language)
    func currentLanguage() -> Language?
}

/// Production implementation that delegates to InputSourceManager
@MainActor
final class ProductionInputSourceSwitcher: InputSourceSwitching {
    nonisolated func switchTo(language: Language) {
        Task { @MainActor in
            InputSourceManager.shared.switchTo(language: language)
        }
    }
    
    nonisolated func currentLanguage() -> Language? {
        // Note: This is a simplification; in real usage this should be called from MainActor
        return nil
    }
}

/// Mock implementation for testing - captures switch calls
final class MockInputSourceSwitcher: InputSourceSwitching, @unchecked Sendable {
    private let lock = NSLock()
    private var _switchCalls: [Language] = []
    private var _currentLanguage: Language? = .english
    
    var switchCalls: [Language] {
        lock.lock()
        defer { lock.unlock() }
        return _switchCalls
    }
    
    var switchCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _switchCalls.count
    }
    
    func switchTo(language: Language) {
        lock.lock()
        defer { lock.unlock() }
        _switchCalls.append(language)
        _currentLanguage = language
    }
    
    func currentLanguage() -> Language? {
        lock.lock()
        defer { lock.unlock() }
        return _currentLanguage
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _switchCalls.removeAll()
        _currentLanguage = .english
    }
    
    func setCurrentLanguage(_ lang: Language?) {
        lock.lock()
        defer { lock.unlock() }
        _currentLanguage = lang
    }
}
