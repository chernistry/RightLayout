import XCTest
@testable import RightLayout

final class NgramLanguageModelTests: XCTestCase {
    
    // MARK: - Trigram Hashing Tests
    
    func testTrigramHashConsistency() {
        // Same trigram should always produce same hash
        let hash1 = NgramLanguageModel.trigramHash("a", "b", "c")
        let hash2 = NgramLanguageModel.trigramHash("a", "b", "c")
        XCTAssertEqual(hash1, hash2)
    }
    
    func testTrigramHashUniqueness() {
        // Different trigrams should produce different hashes
        let hash1 = NgramLanguageModel.trigramHash("a", "b", "c")
        let hash2 = NgramLanguageModel.trigramHash("a", "b", "d")
        let hash3 = NgramLanguageModel.trigramHash("x", "y", "z")
        
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
    }
    
    func testTrigramHashWithCyrillic() {
        let hash1 = NgramLanguageModel.trigramHash("п", "р", "и")
        let hash2 = NgramLanguageModel.trigramHash("п", "р", "и")
        let hash3 = NgramLanguageModel.trigramHash("м", "и", "р")
        
        XCTAssertEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
    }
    
    func testTrigramHashWithHebrew() {
        let hash1 = NgramLanguageModel.trigramHash("ש", "ל", "ו")
        let hash2 = NgramLanguageModel.trigramHash("ש", "ל", "ו")
        let hash3 = NgramLanguageModel.trigramHash("ע", "ו", "ל")
        
        XCTAssertEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
    }
    
    // MARK: - Scoring Tests
    
    func testScoringConsistency() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        let score1 = model.score("hello")
        let score2 = model.score("hello")
        
        XCTAssertEqual(score1, score2, accuracy: 0.001)
    }
    
    func testKnownTrigramHasHigherScore() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        let knownScore = model.score("hello")
        let unknownScore = model.score("xyzqw")
        
        // Known trigrams should have higher (less negative) scores
        XCTAssertGreaterThan(knownScore, unknownScore)
    }
    
    func testSmoothingForMissingTrigrams() {
        let customModel = NgramLanguageModel(
            logProbs: [:],  // Empty dictionary
            smoothingValue: -10.0
        )
        
        let score = customModel.score("abc")
        
        // Should return smoothing value since no trigrams are in the model
        XCTAssertEqual(score, -10.0, accuracy: 0.001)
    }
    
    func testNormalizationIsCaseInsensitive() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        let lowerScore = model.score("hello")
        let upperScore = model.score("HELLO")
        let mixedScore = model.score("HeLLo")
        
        XCTAssertEqual(lowerScore, upperScore, accuracy: 0.001)
        XCTAssertEqual(lowerScore, mixedScore, accuracy: 0.001)
    }
    
    func testShortTextHandling() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        // Less than 3 characters should still return a score
        let score1 = model.score("ab")
        let score2 = model.score("a")
        
        // Should not crash and should return smoothing-based scores
        XCTAssertLessThan(score1, 0.0)
        XCTAssertLessThan(score2, 0.0)
    }
    
    func testEmptyStringHandling() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        let score = model.score("")
        
        // Should handle empty string gracefully
        XCTAssertLessThan(score, 0.0)
    }
    
    // MARK: - Mock Data Validation
    
    func testMockDataContainsExpectedRussianTrigrams() {
        let model = NgramLanguageModel(logProbs: MockNgramData.russianTrigrams)
        
        // "привет" should score better than random text
        let privetScore = model.score("привет")
        let randomScore = model.score("абвгде")
        
        XCTAssertGreaterThan(privetScore, randomScore)
    }
    
    func testMockDataContainsExpectedEnglishTrigrams() {
        let model = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        
        // "hello" should score better than random text
        let helloScore = model.score("hello")
        let randomScore = model.score("qwxyz")
        
        XCTAssertGreaterThan(helloScore, randomScore)
    }
    
    func testMockDataContainsExpectedHebrewTrigrams() {
        let model = NgramLanguageModel(logProbs: MockNgramData.hebrewTrigrams)
        
        // "שלום" should score better than random text
        let shalomScore = model.score("שלום")
        let randomScore = model.score("אבגד")
        
        XCTAssertGreaterThan(shalomScore, randomScore)
    }
}
