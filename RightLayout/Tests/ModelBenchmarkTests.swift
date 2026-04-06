import XCTest
@testable import RightLayout

final class ModelBenchmarkTests: XCTestCase {
    
    private let testTokens = [
        "ghbdtn",      // ru from en: "привет"
        "vbh",         // ru from en: "мир"
        "kt",          // he from en: "לא"
        "aku",         // he from en: "של"
        "руддщ",       // en from ru: "hello"
        "цщкд",        // en from ru: "world"
        "שלום",        // he (valid)
        "привет",      // ru (valid)
        "hello",       // en (valid)
        "abc",         // en (ambiguous/short)
        "123",         // technical
        "https://"     // technical
    ]
    
    // Manual benchmark entry point. Keep this out of the default XCTest discovery path
    // because Foundation Models availability/runtime support varies across developer machines.
    func benchmarkModelPerformanceHeadToHead() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Foundation Models benchmark requires macOS 26 or newer")
        }

        print("\n🚀 Starting Model Benchmark: CoreML vs Foundation Models")
        
        // 1. Benchmark Initialization
        let coreMLStart = DispatchTime.now()
        let coreML = CoreMLLayoutClassifier()
        let coreMLEnd = DispatchTime.now()
        let coreMLInitNano = coreMLEnd.uptimeNanoseconds - coreMLStart.uptimeNanoseconds
        let coreMLInitMs = Double(coreMLInitNano) / 1_000_000
        
        let fmStart = DispatchTime.now()
        let fm = FoundationModelClassifier()
        let fmEnd = DispatchTime.now()
        let fmInitNano = fmEnd.uptimeNanoseconds - fmStart.uptimeNanoseconds
        let fmInitMs = Double(fmInitNano) / 1_000_000

        guard fm.modelAvailable else {
            throw XCTSkip("Foundation Models are unavailable on this system")
        }
        
        print(String(format: "⏱️ Init Time: CoreML: %.2fms | Foundation: %.2fms", coreMLInitMs, fmInitMs))
        
        // 2. Benchmark Inference Latency
        var coreMLResults: [Double] = []
        var fmResults: [Double] = []
        
        print("\n| Token | CoreML Latency | FM Latency | CoreML Result | FM Result | Match? |")
        print("|-------|----------------|------------|---------------|-----------|--------|")
        
        for token in testTokens {
            // CoreML Inference
            let cStart = DispatchTime.now()
            let cPred = coreML.predict(token)
            let cEnd = DispatchTime.now()
            let cLatMs = Double(cEnd.uptimeNanoseconds - cStart.uptimeNanoseconds) / 1_000_000
            coreMLResults.append(cLatMs)
            
            // Foundation Model Inference
            let fStart = DispatchTime.now()
            let fPred = await fm.predict(token)
            let fEnd = DispatchTime.now()
            let fLatMs = Double(fEnd.uptimeNanoseconds - fStart.uptimeNanoseconds) / 1_000_000
            fmResults.append(fLatMs)
            
            let cLabel = cPred?.0.rawValue ?? "nil"
            let fLabel = fPred?.0.rawValue ?? "nil"
            let match = cLabel == fLabel ? "✅" : "❌"
            
            print(String(format: "| %-5s | %7.2fms | %7.2fms | %-13s | %-9s | %-6s |", 
                         token, cLatMs, fLatMs, cLabel, fLabel, match))
        }
        
        let cAvg = coreMLResults.reduce(0, +) / Double(coreMLResults.count)
        let fAvg = fmResults.reduce(0, +) / Double(fmResults.count)
        
        print(String(format: "\n📊 Average Latency: CoreML: %.2fms | Foundation: %.2fms", cAvg, fAvg))
        
        if fAvg > cAvg * 5 {
            print("⚠️ Foundation Model is significantly slower (expected due to LLM-based on-device weights).")
        } else {
            print("✨ Foundation Model performance is surprisingly competitive!")
        }
    }
}
