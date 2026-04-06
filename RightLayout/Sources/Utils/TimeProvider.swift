import Foundation

/// Protocol to abstract time retrieval for testability
protocol TimeProvider {
    var now: Date { get }
}

/// Default implementation returning system time
struct RealTimeProvider: TimeProvider {
    var now: Date {
        Date()
    }
}
