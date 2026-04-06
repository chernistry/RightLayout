import Foundation
import AppKit

// MARK: - CLI Mode

public final class CLI {
    @MainActor
    public static func run(verbose: Bool) {
        // Disable stdout buffering
        setbuf(stdout, nil)
        
        if verbose {
            print("Starting CLI Mode...")
            fflush(stdout)
        }
        
        // Ensure settings and engine are initialized on MainActor
        let settings = SettingsManager.shared
        let engine = CorrectionEngine(settings: settings)
        
        // Print ready message AFTER engine is initialized
        print("RightLayout REPL Ready")
        fflush(stdout)
        
        // Use DispatchQueue for stdin reading to avoid blocking MainActor
        DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem {
            while let line = readLine() {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard !parts.isEmpty else { continue }
                
                let command = parts[0]
                let arg = parts.count > 1 ? parts[1] : ""
                
                switch command {
                case "CORRECT":
                    let text = arg
                    // Dispatch to MainActor for engine call
                    let semaphore = DispatchSemaphore(value: 0)
                    var corrected: String? = nil
                    var action: String = "noChange"
                    
                    Task { @MainActor in
                        let result = await engine.correctText(text, phraseBuffer: "", expectedLayout: nil)
                        corrected = result.corrected
                        action = "\(result.action)"
                        semaphore.signal()
                    }
                    
                    semaphore.wait()
                    
                    let json = """
                    {"corrected": "\(corrected?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")", "action": "\(action)", "original": "\(text.replacingOccurrences(of: "\"", with: "\\\""))"}
                    """
                    print(json)
                    fflush(stdout)
                    
                case "EXIT":
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                    return
                    
                default:
                    print("ERROR: Unknown command \(command)")
                    fflush(stdout)
                }
            }
            
            // End of stdin, terminate
            DispatchQueue.main.async { NSApp.terminate(nil) }
        })
    }
}
