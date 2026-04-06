import Foundation
import RightLayout

@main
struct BenchmarkTool {
    static func main() async {
#if canImport(FoundationModels)
        guard #available(macOS 26, *) else {
            print("❌ This benchmark requires macOS 26+")
            return
        }
        
        let testTokens = [
            "ghbdtn",      // ru from en: "привет"
            "vbh",         // ru from en: "мир"
            "kt",          // he from en: "לא"
            "aku",         // he from en: "של"
            "руддщ",       // en from ru: "hello"
            "цщкд",        // en from ru: "world"
            "שלום",        // he (valid)
            "привет",      // ru (valid)
            "hello",       // en (valid)
            "abc"          // en (ambiguous/short)
        ]
        
        print("\n🚀 Starting Model Benchmark: CoreML vs Foundation Models")
        
        // 1. Benchmark Initialization
        let coreMLStart = DispatchTime.now()
        let coreML = CoreMLLayoutClassifier()
        let coreMLEnd = DispatchTime.now()
        let coreMLInitMs = Double(coreMLEnd.uptimeNanoseconds - coreMLStart.uptimeNanoseconds) / 1_000_000
        
        let fmStart = DispatchTime.now()
        let fm = FoundationModelClassifier()
        let fmEnd = DispatchTime.now()
        let fmInitMs = Double(fmEnd.uptimeNanoseconds - fmStart.uptimeNanoseconds) / 1_000_000
        
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
            
            print(String(format: "| %-6@ | %7.2fms | %7.2fms | %-13@ | %-9@ | %-6@ |", 
                         token as NSString, cLatMs, fLatMs, cLabel as NSString, fLabel as NSString, match as NSString))
        }
        
        let cAvg = coreMLResults.reduce(0, +) / Double(coreMLResults.count)
        let fAvg = fmResults.reduce(0, +) / Double(fmResults.count)
        
        print(String(format: "\n📊 Average Latency: CoreML: %.2fms | Foundation: %.2fms", cAvg, fAvg))
        
        if fAvg > cAvg * 5 {
            print("⚠️ Foundation Model is significantly slower (expected due to LLM-based on-device weights).")
        } else {
            print("✨ Foundation Model performance is surprisingly competitive!")
        }
#else
        print("❌ FoundationModels framework is unavailable in this toolchain.")
#endif
    }
}
