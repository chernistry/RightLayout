import Foundation
@testable import RightLayout

class MockTimeProvider: TimeProvider {
    var currentTime: Date
    
    init(startTime: Date = Date(timeIntervalSince1970: 1000)) {
        self.currentTime = startTime
    }
    
    var now: Date {
        return currentTime
    }
    
    func advance(by seconds: TimeInterval) {
        currentTime.addTimeInterval(seconds)
    }
}
